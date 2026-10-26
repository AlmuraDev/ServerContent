import com.google.gson.*;
import com.google.gson.stream.JsonReader;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;
import java.util.zip.*;

/**
 * Writes Dynmap 3.2.1 (Minecraft 1.12, metadata based) render data for Almura's content blocks: almura-models.txt and almura-texture.txt.
 *
 * Every content block's blockstate is resolved per metadata value (using Almura's own state to meta mapping per block genre), its model
 * (JSON with elements and parents, vanilla parents read from the client jar, or OBJ with its material library) is flattened into textured
 * quads, then:
 *  - a plain full cube becomes a block line with per face textures,
 *  - stairs use Dynmap's stair renderer,
 *  - anything else becomes a patch block: one Dynmap patch per quad.
 *
 * Dynmap 3.2.1 patches always show a whole image (corners must stay within -1..2 and texture ranges within 0..1), so every texture region a
 * face uses is written out as its own image into a texture pack (out/pack), which Dynmap's texturepack setting then points at.
 *
 * Usage: DynmapGen <almura assets dir> <minecraft client jar> <out dir>
 */
public class DynmapGen {

    static Path assets;
    static ZipFile client;
    static final Map<String, JsonObject> modelCache = new HashMap<>();

    // Output state
    static final Map<String, String> patchIds = new LinkedHashMap<>();   // patch definition -> id
    static final Map<String, String> textures = new TreeMap<>();         // texture id -> filename
    static final List<String> modelLines = new ArrayList<>();
    static final List<String> textureLines = new ArrayList<>();
    static final Map<String, Integer> stats = new TreeMap<>();
    static final List<String> problems = new ArrayList<>();

    static final class Quad {
        double[][] p;  // corners (block units 0..1)
        double[][] uv; // per corner, Dynmap convention (u right, v up), 0..1
        String tex;    // texture file, "namespace:path" under textures/ without .png
    }

    static Path pack;

    public static void main(String[] a) throws Exception {
        assets = Paths.get(a[0]);
        client = new ZipFile(a[1]);
        Path out = Paths.get(a[2]);
        pack = out.resolve("pack");
        Path blocks = assets.resolve("content/block");
        List<Path> files;
        try (Stream<Path> s = Files.walk(blocks)) {
            files = s.filter(p -> p.toString().endsWith(".json") && !p.toString().contains("_recipes") && !p.toString().contains("_translations"))
                    .sorted().collect(Collectors.toList());
        }
        for (Path f : files) {
            String rel = blocks.relativize(f).toString().replace(File.separatorChar, '/').replaceAll("[.]json$", "");
            try {
                block(rel, read(f));
            } catch (Exception e) {
                problems.add(rel + ": " + e);
                stats.merge("failed", 1, Integer::sum);
            }
        }

        List<String> m = new ArrayList<>();
        m.add("# Almura blocks for Dynmap 3.2.1 (Minecraft 1.12). Generated from the content loader assets by DynmapGen; do not edit by hand.");
        m.add("modname:almura");
        m.add("");
        patchIds.forEach((def, id) -> m.add("patch:id=" + id + "," + def));
        m.add("");
        m.addAll(modelLines);
        Files.write(out.resolve("almura-models.txt"), m, StandardCharsets.UTF_8);

        List<String> t = new ArrayList<>();
        t.add("# Almura blocks for Dynmap 3.2.1 (Minecraft 1.12). Generated from the content loader assets by DynmapGen; do not edit by hand.");
        t.add("modname:almura");
        t.add("");
        textures.forEach((id, file) -> t.add("texture:id=" + id + ",filename=" + file + ",xcount=1,ycount=1"));
        t.add("");
        t.addAll(textureLines);
        Files.write(out.resolve("almura-texture.txt"), t, StandardCharsets.UTF_8);

        stats.forEach((k, v) -> System.out.println(v + "\t" + k));
        System.out.println(patchIds.size() + "\tpatch definitions, " + textures.size() + " textures");
        problems.stream().limit(60).forEach(p -> System.out.println("PROBLEM " + p));
        if (problems.size() > 60) System.out.println("... " + (problems.size() - 60) + " more problems");
    }

    // ------------------------------------------------------------------ blocks

    static void block(String rel, JsonObject content) throws Exception {
        String genre = rel.substring(0, rel.indexOf('/'));
        String id = "%" + rel;
        Path bsPath = assets.resolve("blockstates/" + rel + ".json");
        if (!Files.exists(bsPath)) {
            problems.add(rel + ": no blockstate");
            stats.merge("no blockstate", 1, Integer::sum);
            return;
        }
        JsonObject bs = read(bsPath);

        // State (property value) -> metadata values, per genre (matches each block class's getMetaFromState)
        LinkedHashMap<String, List<Integer>> states = new LinkedHashMap<>();
        String prop = null;
        switch (genre) {
            case "horizontal":
            case "container":
                prop = "facing";
                states.put("south", Arrays.asList(0));
                states.put("west", Arrays.asList(1));
                states.put("north", Arrays.asList(2));
                states.put("east", Arrays.asList(3));
                break;
            case "log":
                prop = "axis";
                states.put("y", Arrays.asList(0, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15));
                states.put("x", Arrays.asList(1));
                states.put("z", Arrays.asList(2));
                states.put("none", Arrays.asList(4));
                break;
            case "slab":
                if (content.has("is_double") && content.get("is_double").getAsBoolean()) {
                    states.put("", null);
                } else {
                    prop = "half";
                    states.put("bottom", Arrays.asList(0));
                    states.put("top", Arrays.asList(1));
                }
                break;
            case "crop": {
                prop = "age";
                List<String> ages = new ArrayList<>(propertyValues(bs, "age"));
                ages.sort(Comparator.comparingInt(Integer::parseInt));
                // Surface aquatic (paddy) crops add 8 to the age while the block holds water
                boolean paddy = content.has("aquatic") && content.get("aquatic").isJsonPrimitive() && content.get("aquatic").getAsString().equals("surface");
                for (String age : ages) {
                    int n = Integer.parseInt(age);
                    states.put(age, paddy ? Arrays.asList(n, n | 8) : Arrays.asList(n));
                }
                break;
            }
            case "stair":
                stair(id, rel, bs);
                return;
            default:
                // flower, leaf, normal, sapling: one model whatever the metadata
                states.put("", null);
        }

        for (Map.Entry<String, List<Integer>> st : states.entrySet()) {
            JsonObject variant = variant(bs, prop, st.getKey());
            if (variant == null || !variant.has("model")) {
                problems.add(rel + " " + st.getKey() + ": no model in blockstate");
                continue;
            }
            String data = st.getValue() == null ? "data=*" : st.getValue().stream().map(d -> "data=" + d).collect(Collectors.joining(","));
            List<Quad> quads = modelQuads(variant.get("model").getAsString(), variant.has("textures") ? variant.getAsJsonObject("textures") : null);
            int rx = variant.has("x") ? (int) Math.round(variant.get("x").getAsDouble()) : 0;
            int ry = variant.has("y") ? (int) Math.round(variant.get("y").getAsDouble()) : 0;
            for (Quad q : quads) {
                for (double[] p : q.p) rotateBlock(p, rx, ry);
            }
            emit(id, data, quads, genre, rel);
        }
    }

    /** Values a property takes in the blockstate (forge "variants": {"prop": {...}} or "prop=value" keys). */
    static Set<String> propertyValues(JsonObject bs, String prop) {
        Set<String> out = new LinkedHashSet<>();
        JsonObject variants = bs.has("variants") ? bs.getAsJsonObject("variants") : new JsonObject();
        for (Map.Entry<String, JsonElement> e : variants.entrySet()) {
            if (e.getKey().equals(prop) && e.getValue().isJsonObject()) e.getValue().getAsJsonObject().entrySet().forEach(x -> out.add(x.getKey()));
            for (String part : e.getKey().split(",")) {
                if (part.startsWith(prop + "=")) out.add(part.substring(prop.length() + 1));
            }
        }
        return out;
    }

    /** The merged variant for one property value: forge defaults + the value's entry (or "normal"), or a vanilla "prop=value" variant. */
    static JsonObject variant(JsonObject bs, String prop, String value) {
        JsonObject variants = bs.has("variants") ? bs.getAsJsonObject("variants") : new JsonObject();
        JsonObject merged = new JsonObject();
        if (bs.has("defaults")) merge(merged, bs.getAsJsonObject("defaults"));
        JsonElement pick = null;
        if (prop != null && variants.has(prop) && variants.get(prop).isJsonObject() && variants.getAsJsonObject(prop).has(value)) {
            pick = variants.getAsJsonObject(prop).get(value);
        } else if (prop != null) {
            for (Map.Entry<String, JsonElement> e : variants.entrySet()) {
                if (Arrays.asList(e.getKey().split(",")).contains(prop + "=" + value)) {
                    pick = e.getValue();
                    break;
                }
            }
        }
        if (pick == null && variants.has("normal")) pick = variants.get("normal");
        if (pick == null && variants.has("")) pick = variants.get("");
        if (pick != null) {
            if (pick.isJsonArray()) pick = pick.getAsJsonArray().size() > 0 ? pick.getAsJsonArray().get(0) : null;
            if (pick != null && pick.isJsonObject()) merge(merged, pick.getAsJsonObject());
        }
        return merged;
    }

    static void merge(JsonObject into, JsonObject from) {
        for (Map.Entry<String, JsonElement> e : from.entrySet()) {
            if (e.getKey().equals("textures") && into.has("textures") && e.getValue().isJsonObject()) {
                for (Map.Entry<String, JsonElement> t : e.getValue().getAsJsonObject().entrySet()) into.getAsJsonObject("textures").add(t.getKey(), t.getValue());
            } else if (e.getKey().equals("textures") && e.getValue().isJsonObject()) {
                // A copy, so merging a variant's textures later doesn't change the blockstate's defaults
                JsonObject copy = new JsonObject();
                for (Map.Entry<String, JsonElement> t : e.getValue().getAsJsonObject().entrySet()) copy.add(t.getKey(), t.getValue());
                into.add("textures", copy);
            } else {
                into.add(e.getKey(), e.getValue());
            }
        }
    }

    static void stair(String id, String rel, JsonObject bs) throws Exception {
        // Any variant's model carries the textures; Dynmap's own renderer builds the stair shapes from the vanilla metadata
        JsonObject variant = null;
        for (String v : new String[]{"east", "north", "south", "west"}) {
            variant = variant(bs, "facing", v);
            if (variant.has("model")) break;
        }
        if (variant == null || !variant.has("model")) {
            JsonObject variants = bs.getAsJsonObject("variants");
            for (Map.Entry<String, JsonElement> e : variants.entrySet()) {
                JsonElement v = e.getValue().isJsonArray() ? e.getValue().getAsJsonArray().get(0) : e.getValue();
                if (v.isJsonObject() && v.getAsJsonObject().has("model")) {
                    variant = v.getAsJsonObject();
                    break;
                }
            }
        }
        if (variant == null || !variant.has("model")) {
            problems.add(rel + ": stair without a model");
            return;
        }
        Map<String, String> tex = resolveTextures(variant.get("model").getAsString(), variant.has("textures") ? variant.getAsJsonObject("textures") : null);
        String side = whole(textureId(tex.getOrDefault("side", tex.getOrDefault("all", tex.get("particle")))));
        String top = whole(textureId(tex.getOrDefault("top", tex.getOrDefault("all", tex.get("particle")))));
        String bottom = whole(textureId(tex.getOrDefault("bottom", tex.getOrDefault("all", tex.get("particle")))));
        if (side == null) {
            problems.add(rel + ": stair textures not found");
            return;
        }
        modelLines.add("customblock:id=" + id + ",data=*,class=org.dynmap.hdmap.renderer.StairBlockRenderer");
        textureLines.add("block:id=" + id + ",data=*,patch0=0:" + side + ",patch1=0:" + (top == null ? side : top) + ",patch2=0:" + (bottom == null ? side : bottom)
                + ",transparency=SEMITRANSPARENT");
        stats.merge("stair (Dynmap stair renderer)", 1, Integer::sum);
    }

    // ------------------------------------------------------------------ emitting

    static final String[] FACE_KEYS = {"bottom", "top", "north", "south", "west", "east"};

    static void emit(String id, String data, List<Quad> quads, String genre, String rel) throws IOException {
        if (quads.isEmpty()) {
            problems.add(rel + " " + data + ": model has no faces");
            stats.merge("empty model", 1, Integer::sum);
            return;
        }
        String[] cube = fullCube(quads);
        if (cube != null) {
            StringBuilder sb = new StringBuilder("block:id=").append(id).append(',').append(data);
            for (int i = 0; i < 6; i++) sb.append(',').append(FACE_KEYS[i]).append("=0:").append(cube[i]);
            sb.append(",stdrot=true");
            if (genre.equals("leaf")) sb.append(",transparency=TRANSPARENT");
            textureLines.add(sb.toString());
            stats.merge(genre + " cube", 1, Integer::sum);
            return;
        }
        StringBuilder model = new StringBuilder("patchblock:id=").append(id).append(',').append(data);
        StringBuilder tex = new StringBuilder("block:id=").append(id).append(',').append(data);
        int n = 0;
        for (Quad q : quads) {
            double[] r = rect(q);
            if (r == null) continue;
            String patch = patch(q, r);
            if (patch == null) continue;
            String region = region(q.tex, r);
            if (region == null) continue;
            model.append(",patch").append(n).append('=').append(patch);
            tex.append(",patch").append(n).append("=0:").append(region);
            n++;
        }
        if (n == 0) {
            problems.add(rel + " " + data + ": no usable faces");
            return;
        }
        String transparency = genre.equals("slab") ? "SEMITRANSPARENT" : "TRANSPARENT";
        modelLines.add(model.toString());
        textureLines.add(tex.append(",transparency=").append(transparency).toString());
        stats.merge(genre + " patches", 1, Integer::sum);
    }

    /**
     * Face texture ids of a plain unit cube, in bottom, top, north, south, west, east order; else null. Every quad must cover a whole side
     * (leaves draw each side twice, front and back); each side shows the texture region its quad uses.
     */
    static String[] fullCube(List<Quad> quads) throws IOException {
        String[] out = new String[6];
        for (Quad q : quads) {
            if (q.p.length != 4) return null;
            int face = -1;
            for (int axis = 0; axis < 3 && face < 0; axis++) {
                final int ax = axis;
                if (Arrays.stream(q.p).allMatch(p -> near(p[ax], 0))) face = axis == 1 ? 0 : axis == 2 ? 2 : 4;
                else if (Arrays.stream(q.p).allMatch(p -> near(p[ax], 1))) face = axis == 1 ? 1 : axis == 2 ? 3 : 5;
            }
            if (face < 0) return null;
            for (double[] p : q.p) for (double c : p) if (!near(c, 0) && !near(c, 1)) return null;
            double[] r = rect(q);
            if (r == null) return null;
            // The quad's corners must sit on its texture rectangle's corners
            for (double[] uv : q.uv) {
                if (!(near(uv[0], r[0]) || near(uv[0], r[1])) || !(near(uv[1], r[2]) || near(uv[1], r[3]))) return null;
            }
            if (out[face] == null) {
                out[face] = region(q.tex, r);
                if (out[face] == null) return null;
            }
        }
        for (String s : out) if (s == null) return null;
        return out;
    }

    static boolean near(double a, double b) {
        return Math.abs(a - b) < 1e-4;
    }

    /** The quad's texture rectangle {umin, umax, vmin, vmax} (Dynmap convention, v up), or null when it has no area. */
    static double[] rect(Quad q) {
        double umin = Double.MAX_VALUE, umax = -Double.MAX_VALUE, vmin = Double.MAX_VALUE, vmax = -Double.MAX_VALUE;
        for (double[] uv : q.uv) {
            umin = Math.min(umin, uv[0]);
            umax = Math.max(umax, uv[0]);
            vmin = Math.min(vmin, uv[1]);
            vmax = Math.max(vmax, uv[1]);
        }
        if (umax - umin < 1e-6 || vmax - vmin < 1e-6) return null;
        return new double[]{umin, umax, vmin, vmax};
    }

    /**
     * A Dynmap patch for a quad showing a whole (cut out) image: O at the quad's texture rectangle's (umin, vmin) corner, U at (umax, vmin),
     * V at (umin, vmax), through the quad's plane. Null when it falls outside the -1..2 range Dynmap accepts.
     */
    static String patch(Quad q, double[] r) {
        int n = q.p.length;
        // Three corners whose texture coordinates aren't collinear give the plane's texture to position mapping
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n, k = (i + 2) % n;
            double du1 = q.uv[j][0] - q.uv[i][0], dv1 = q.uv[j][1] - q.uv[i][1];
            double du2 = q.uv[k][0] - q.uv[i][0], dv2 = q.uv[k][1] - q.uv[i][1];
            double det = du1 * dv2 - du2 * dv1;
            if (Math.abs(det) < 1e-9) continue;
            double[] O = new double[3], U = new double[3], V = new double[3];
            for (int c = 0; c < 3; c++) {
                double e1 = q.p[j][c] - q.p[i][c], e2 = q.p[k][c] - q.p[i][c];
                double a = (e1 * dv2 - e2 * dv1) / det, b = (e2 * du1 - e1 * du2) / det;
                double origin = q.p[i][c] - q.uv[i][0] * a - q.uv[i][1] * b;
                O[c] = origin + r[0] * a + r[2] * b;
                U[c] = origin + r[1] * a + r[2] * b;
                V[c] = origin + r[0] * a + r[3] * b;
            }
            for (double[] pt : new double[][]{O, U, V}) {
                for (double c : pt) {
                    if (c < -1 - 1e-6 || c > 2 + 1e-6) {
                        stats.merge("faces outside the block range Dynmap accepts (skipped)", 1, Integer::sum);
                        return null;
                    }
                }
            }
            String def = "Ox=" + f(O[0]) + ",Oy=" + f(O[1]) + ",Oz=" + f(O[2]) + ",Ux=" + f(U[0]) + ",Uy=" + f(U[1]) + ",Uz=" + f(U[2])
                    + ",Vx=" + f(V[0]) + ",Vy=" + f(V[1]) + ",Vz=" + f(V[2]);
            return patchIds.computeIfAbsent(def, d -> "p" + patchIds.size());
        }
        return null;
    }

    // ------------------------------------------------------------------ texture regions

    static final Map<String, java.awt.image.BufferedImage> images = new HashMap<>();

    static java.awt.image.BufferedImage image(String file) throws IOException {
        if (images.containsKey(file)) return images.get(file);
        String ns = file.substring(0, file.indexOf(':')), path = file.substring(file.indexOf(':') + 1);
        java.awt.image.BufferedImage img;
        if (ns.equals("almura")) {
            img = javax.imageio.ImageIO.read(assets.resolve("textures/" + path + ".png").toFile());
        } else {
            try (InputStream in = client.getInputStream(client.getEntry("assets/" + ns + "/textures/" + path + ".png"))) {
                img = javax.imageio.ImageIO.read(in);
            }
        }
        images.put(file, img);
        return img;
    }

    /** The whole texture (first frame of an animation strip). */
    static String whole(String file) throws IOException {
        return file == null ? null : region(file, new double[]{0, 1, 0, 1});
    }

    /**
     * Writes the texture region {umin, umax, vmin, vmax} (of the first frame, for animation strips) into the pack as its own image and returns
     * its Dynmap texture id.
     */
    static String region(String file, double[] r) throws IOException {
        java.awt.image.BufferedImage img = image(file);
        if (img == null) {
            problems.add("unreadable texture " + file);
            return null;
        }
        int w = img.getWidth(), h = img.getHeight();
        int fh = h > w && h % w == 0 ? w : h;
        int x0 = (int) Math.round(clamp01(r[0]) * w), x1 = (int) Math.round(clamp01(r[1]) * w);
        int y0 = (int) Math.round((1 - clamp01(r[3])) * fh), y1 = (int) Math.round((1 - clamp01(r[2])) * fh);
        if (x1 <= x0) x1 = Math.min(w, x0 + 1);
        if (x1 <= x0) x0 = x1 - 1;
        if (y1 <= y0) y1 = Math.min(fh, y0 + 1);
        if (y1 <= y0) y0 = y1 - 1;
        String ns = file.substring(0, file.indexOf(':')), path = file.substring(file.indexOf(':') + 1);
        boolean full = x0 == 0 && y0 == 0 && x1 == w && y1 == fh && fh == h;
        String id = full ? ns + "/" + path : ns + "/" + path + "_" + x0 + "_" + y0 + "_" + x1 + "_" + y1;
        if (!textures.containsKey(id)) {
            String filename = full ? "assets/" + ns + "/textures/" + path + ".png"
                    : "assets/almura/textures/dynmap/" + ns + "/" + path + "_" + x0 + "_" + y0 + "_" + x1 + "_" + y1 + ".png";
            Path target = pack.resolve(filename);
            Files.createDirectories(target.getParent());
            javax.imageio.ImageIO.write(full ? img : img.getSubimage(x0, y0, x1 - x0, y1 - y0), "png", target.toFile());
            textures.put(id, filename);
        }
        return id;
    }

    static double clamp01(double d) {
        return Math.max(0, Math.min(1, d));
    }

    static String f(double d) {
        if (Math.abs(d) < 1e-7) d = 0;
        // Within rounding of Dynmap's -1..2 limits counts as on them
        if (d < -1 && d > -1 - 1e-5) d = -1;
        if (d > 2 && d < 2 + 1e-5) d = 2;
        String s = String.format(Locale.ROOT, "%.6f", d);
        s = s.replaceAll("0+$", "");
        return s.endsWith(".") ? s + "0" : s;
    }

    // ------------------------------------------------------------------ models

    static List<Quad> modelQuads(String model, JsonObject textureOverrides) throws Exception {
        if (model.endsWith(".obj")) return objQuads(model);
        JsonObject resolved = flatten(model);
        Map<String, String> tex = textureMap(resolved, textureOverrides);
        List<Quad> quads = new ArrayList<>();
        if (!resolved.has("elements")) return quads;
        for (JsonElement el : resolved.getAsJsonArray("elements")) elementQuads(el.getAsJsonObject(), tex, quads);
        return quads;
    }

    static Map<String, String> resolveTextures(String model, JsonObject overrides) throws Exception {
        return textureMap(flatten(model), overrides);
    }

    /** The model with its parent chain merged: the nearest elements, and textures from every level (nearer wins). */
    static JsonObject flatten(String model) throws Exception {
        JsonObject out = new JsonObject();
        JsonObject textures = new JsonObject();
        String m = model;
        for (int depth = 0; depth < 20 && m != null; depth++) {
            JsonObject o = loadModel(m);
            if (o == null) throw new FileNotFoundException("model " + m);
            if (o.has("textures")) {
                for (Map.Entry<String, JsonElement> e : o.getAsJsonObject("textures").entrySet()) {
                    if (!textures.has(e.getKey())) textures.add(e.getKey(), e.getValue());
                }
            }
            if (!out.has("elements") && o.has("elements")) out.add("elements", o.get("elements"));
            m = o.has("parent") ? o.get("parent").getAsString() : null;
            if (m != null && (m.equals("builtin/generated") || m.equals("item/generated"))) m = null;
        }
        out.add("textures", textures);
        return out;
    }

    static Map<String, String> textureMap(JsonObject resolved, JsonObject overrides) {
        Map<String, String> raw = new HashMap<>();
        for (Map.Entry<String, JsonElement> e : resolved.getAsJsonObject("textures").entrySet()) raw.put(e.getKey(), e.getValue().getAsString());
        if (overrides != null) for (Map.Entry<String, JsonElement> e : overrides.entrySet()) raw.put(e.getKey(), e.getValue().getAsString());
        Map<String, String> out = new HashMap<>();
        for (String k : raw.keySet()) {
            String v = raw.get(k);
            for (int i = 0; i < 10 && v != null && v.startsWith("#"); i++) v = raw.get(v.substring(1));
            if (v != null && !v.startsWith("#")) out.put(k, v);
        }
        return out;
    }

    static JsonObject loadModel(String name) throws IOException {
        String ns = name.contains(":") ? name.substring(0, name.indexOf(':')) : "minecraft";
        String path = name.contains(":") ? name.substring(name.indexOf(':') + 1) : name;
        path = path.replaceAll("/+", "/");
        if (!path.startsWith("block/") && !path.startsWith("item/")) path = "block/" + path;
        String key = ns + ":" + path;
        if (modelCache.containsKey(key)) return modelCache.get(key);
        JsonObject o = null;
        if (ns.equals("almura")) {
            Path p = assets.resolve("models/" + path + ".json");
            if (Files.exists(p)) o = read(p);
        } else if (ns.equals("minecraft")) {
            ZipEntry e = client.getEntry("assets/minecraft/models/" + path + ".json");
            if (e != null) {
                try (Reader r = new InputStreamReader(client.getInputStream(e), StandardCharsets.UTF_8)) {
                    o = new JsonParser().parse(r).getAsJsonObject();
                }
            }
        }
        modelCache.put(key, o);
        return o;
    }

    static final String[] FACES = {"down", "up", "north", "south", "west", "east"};

    static void elementQuads(JsonObject el, Map<String, String> tex, List<Quad> out) {
        double[] from = vec(el.getAsJsonArray("from")), to = vec(el.getAsJsonArray("to"));
        JsonObject faces = el.has("faces") ? el.getAsJsonObject("faces") : new JsonObject();
        for (String face : FACES) {
            if (!faces.has(face)) continue;
            JsonObject fo = faces.getAsJsonObject(face);
            String t = fo.has("texture") ? fo.get("texture").getAsString() : null;
            String file = t == null ? null : t.startsWith("#") ? tex.get(t.substring(1)) : t;
            String texId = textureId(file);
            if (texId == null) continue;
            double[][] corners = faceCorners(face, from, to); // in texture order: top-left, top-right, bottom-right, bottom-left (as seen)
            double[] uvr = fo.has("uv") ? vec(fo.getAsJsonArray("uv")) : defaultUv(face, from, to);
            // Corner texture coordinates in model space (pixels, v down), then the face's uv rotation
            double[][] uvs = {{uvr[0], uvr[1]}, {uvr[2], uvr[1]}, {uvr[2], uvr[3]}, {uvr[0], uvr[3]}};
            int rot = fo.has("rotation") ? (fo.get("rotation").getAsInt() / 90) & 3 : 0;
            double[][] rotated = new double[4][];
            for (int i = 0; i < 4; i++) rotated[i] = uvs[(i + 4 - rot) % 4];
            Quad q = new Quad();
            q.p = new double[4][];
            q.uv = new double[4][];
            for (int i = 0; i < 4; i++) {
                q.p[i] = new double[]{corners[i][0] / 16, corners[i][1] / 16, corners[i][2] / 16};
                q.uv[i] = new double[]{rotated[i][0] / 16, 1 - rotated[i][1] / 16};
            }
            q.tex = texId;
            if (el.has("rotation")) rotateElement(q, el.getAsJsonObject("rotation"));
            out.add(q);
        }
    }

    /** Corners of a cuboid face in texture order (top-left, top-right, bottom-right, bottom-left), as Minecraft maps uv onto faces. */
    static double[][] faceCorners(String face, double[] f, double[] t) {
        switch (face) {
            case "down":  return new double[][]{{f[0], f[1], t[2]}, {t[0], f[1], t[2]}, {t[0], f[1], f[2]}, {f[0], f[1], f[2]}};
            case "up":    return new double[][]{{f[0], t[1], f[2]}, {t[0], t[1], f[2]}, {t[0], t[1], t[2]}, {f[0], t[1], t[2]}};
            case "north": return new double[][]{{t[0], t[1], f[2]}, {f[0], t[1], f[2]}, {f[0], f[1], f[2]}, {t[0], f[1], f[2]}};
            case "south": return new double[][]{{f[0], t[1], t[2]}, {t[0], t[1], t[2]}, {t[0], f[1], t[2]}, {f[0], f[1], t[2]}};
            case "west":  return new double[][]{{f[0], t[1], f[2]}, {f[0], t[1], t[2]}, {f[0], f[1], t[2]}, {f[0], f[1], f[2]}};
            default:      return new double[][]{{t[0], t[1], t[2]}, {t[0], t[1], f[2]}, {t[0], f[1], f[2]}, {t[0], f[1], t[2]}};
        }
    }

    static double[] defaultUv(String face, double[] f, double[] t) {
        switch (face) {
            case "down":
            case "up":    return new double[]{f[0], f[2], t[0], t[2]};
            case "north":
            case "south": return new double[]{f[0], 16 - t[1], t[0], 16 - f[1]};
            default:      return new double[]{f[2], 16 - t[1], t[2], 16 - f[1]};
        }
    }

    static void rotateElement(Quad q, JsonObject r) {
        double[] o = vec(r.getAsJsonArray("origin"));
        for (int i = 0; i < 3; i++) o[i] /= 16;
        String axis = r.get("axis").getAsString();
        double ang = Math.toRadians(r.get("angle").getAsDouble());
        boolean rescale = r.has("rescale") && r.get("rescale").getAsBoolean();
        double scale = rescale ? 1 / Math.cos(Math.abs(ang)) : 1;
        double cos = Math.cos(ang), sin = Math.sin(ang);
        for (double[] p : q.p) {
            double x = p[0] - o[0], y = p[1] - o[1], z = p[2] - o[2];
            double nx = x, ny = y, nz = z;
            switch (axis) {
                case "x": ny = y * cos - z * sin; nz = y * sin + z * cos; ny *= scale; nz *= scale; break;
                case "y": nx = x * cos + z * sin; nz = -x * sin + z * cos; nx *= scale; nz *= scale; break;
                default:  nx = x * cos - y * sin; ny = x * sin + y * cos; nx *= scale; ny *= scale; break;
            }
            p[0] = nx + o[0];
            p[1] = ny + o[1];
            p[2] = nz + o[2];
        }
    }

    /** The blockstate's x then y rotation (clockwise looking down for y, as Minecraft applies them), about the block centre. */
    static void rotateBlock(double[] p, int rx, int ry) {
        for (int i = 0; i < ((rx / 90) & 3); i++) {
            double y = p[1] - 0.5, z = p[2] - 0.5;
            p[1] = 0.5 - z;
            p[2] = 0.5 + y;
        }
        for (int i = 0; i < ((ry / 90) & 3); i++) {
            double x = p[0] - 0.5, z = p[2] - 0.5;
            p[0] = 0.5 - z;
            p[2] = 0.5 + x;
        }
    }

    // ------------------------------------------------------------------ OBJ

    static List<Quad> objQuads(String model) throws IOException {
        String path = model.substring(model.indexOf(':') + 1);
        if (!path.startsWith("block/")) path = "block/" + path;
        Path obj = assets.resolve("models/" + path);
        if (!Files.exists(obj)) throw new FileNotFoundException(obj.toString());
        List<double[]> v = new ArrayList<>(), vt = new ArrayList<>();
        Map<String, String> materials = new HashMap<>();
        String current = null;
        List<Quad> out = new ArrayList<>();
        for (String raw : Files.readAllLines(obj, StandardCharsets.ISO_8859_1)) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] t = line.split("\\s+");
            switch (t[0]) {
                case "mtllib": materials.putAll(mtl(obj, t[1])); break;
                case "usemtl": current = t[1]; break;
                case "v": v.add(new double[]{Double.parseDouble(t[1]), Double.parseDouble(t[2]), Double.parseDouble(t[3])}); break;
                case "vt": vt.add(new double[]{Double.parseDouble(t[1]), t.length > 2 ? Double.parseDouble(t[2]) : 0}); break;
                case "f": {
                    String file = current == null ? null : materials.get(current);
                    String texId = textureId(file);
                    if (texId == null || t.length < 4) break;
                    int n = t.length - 1;
                    Quad q = new Quad();
                    q.p = new double[n][];
                    q.uv = new double[n][];
                    boolean ok = true;
                    for (int i = 0; i < n; i++) {
                        String[] idx = t[i + 1].split("/");
                        int vi = Integer.parseInt(idx[0]);
                        double[] pos = v.get(vi < 0 ? v.size() + vi : vi - 1);
                        q.p[i] = pos.clone();
                        if (idx.length > 1 && !idx[1].isEmpty()) {
                            int ti = Integer.parseInt(idx[1]);
                            q.uv[i] = vt.get(ti < 0 ? vt.size() + ti : ti - 1).clone();
                        } else ok = false;
                    }
                    if (!ok) break;
                    q.tex = texId;
                    out.add(q);
                    if (n == 3) stats.merge("obj triangles (drawn as their texture rectangle)", 1, Integer::sum);
                    break;
                }
                default:
            }
        }
        return out;
    }

    /** Material name -> texture file, resolving map_Kd the way Almura's OBJ parser does (no folder: the mtl file's folder name). */
    static Map<String, String> mtl(Path obj, String lib) throws IOException {
        String name = lib.contains(":") ? lib.substring(lib.indexOf(':') + 1) : lib;
        name = name.substring(name.lastIndexOf('/') + 1);
        Path p = obj.resolveSibling(name);
        Map<String, String> out = new HashMap<>();
        if (!Files.exists(p)) return out;
        String folder = obj.getParent().getFileName().toString();
        String current = null;
        for (String raw : Files.readAllLines(p, StandardCharsets.ISO_8859_1)) {
            String[] t = raw.trim().split("\\s+");
            if (t[0].equals("newmtl")) current = t[1];
            else if (t[0].equals("map_Kd") && current != null) {
                String s = t[1];
                String ns = s.contains(":") ? s.substring(0, s.indexOf(':')) : "minecraft";
                String value = s.contains(":") ? s.substring(s.indexOf(':') + 1) : s;
                if (value.indexOf('/') == -1) value = folder + "/" + value;
                if (value.endsWith(".png")) value = value.substring(0, value.length() - 4);
                out.put(current, ns + ":" + value);
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ textures

    /** The texture file as "namespace:path" (textures/ relative, no .png); null if it doesn't exist. */
    static String textureId(String file) {
        if (file == null) return null;
        String ns = file.contains(":") ? file.substring(0, file.indexOf(':')) : "minecraft";
        String path = file.contains(":") ? file.substring(file.indexOf(':') + 1) : file;
        String filename = "assets/" + ns + "/textures/" + path + ".png";
        boolean exists = ns.equals("almura") ? Files.exists(assets.resolve("textures/" + path + ".png")) : client.getEntry(filename) != null;
        if (!exists) {
            problems.add("missing texture " + file);
            return null;
        }
        return ns + ":" + path;
    }

    static double[] vec(JsonArray a) {
        double[] d = new double[a.size()];
        for (int i = 0; i < d.length; i++) d[i] = a.get(i).getAsDouble();
        return d;
    }

    static JsonObject read(Path p) throws IOException {
        try (Reader r = Files.newBufferedReader(p, StandardCharsets.UTF_8)) {
            JsonReader jr = new JsonReader(r);
            jr.setLenient(true);
            return new JsonParser().parse(jr).getAsJsonObject();
        }
    }
}
