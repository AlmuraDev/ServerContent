// Offline Almura 3.0 block renderer (software rasterizer). C# 5 compatible (Windows PowerShell 5.1 Add-Type).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace AlmuraRender
{
    // ------------------------------------------------------------------ lenient JSON (comments, trailing commas, ordered keys)
    public class JV
    {
        public char T; // o a s n b z
        public List<string> Keys = new List<string>();
        public Dictionary<string, JV> Map = new Dictionary<string, JV>();
        public List<JV> Arr = new List<JV>();
        public string S; public double N; public bool B;
        public JV Get(string k) { JV v; if (T == 'o' && Map.TryGetValue(k, out v)) return v; return null; }
        public bool Has(string k) { return T == 'o' && Map.ContainsKey(k); }
        public string Str(string k) { JV v = Get(k); return (v != null && v.T == 's') ? v.S : null; }
        public double Num(string k, double d) { JV v = Get(k); return (v != null && v.T == 'n') ? v.N : d; }
        public bool Bool(string k, bool d) { JV v = Get(k); return (v != null && v.T == 'b') ? v.B : d; }
    }

    public class JP
    {
        string s; int i;
        public static JV Parse(string text) { JP p = new JP(); p.s = text; p.i = 0; return p.Value(); }
        void Skip()
        {
            while (i < s.Length)
            {
                char c = s[i];
                if (char.IsWhiteSpace(c) || c == (char)0xFEFF) i++;
                else if (c == '/' && i + 1 < s.Length && s[i + 1] == '/') { while (i < s.Length && s[i] != '\n') i++; }
                else if (c == '/' && i + 1 < s.Length && s[i + 1] == '*') { i += 2; while (i + 1 < s.Length && !(s[i] == '*' && s[i + 1] == '/')) i++; i += 2; }
                else break;
            }
        }
        JV Value()
        {
            Skip();
            if (i >= s.Length) throw new Exception("JSON: unexpected end");
            char c = s[i];
            JV v = new JV();
            if (c == '{')
            {
                v.T = 'o'; i++;
                while (true)
                {
                    Skip();
                    if (i >= s.Length) throw new Exception("JSON: unterminated object");
                    if (s[i] == '}') { i++; break; }
                    if (s[i] == ',') { i++; continue; }
                    string key;
                    if (s[i] == '"' || s[i] == '\'') key = Str();
                    else { int st = i; while (i < s.Length && s[i] != ':' && !char.IsWhiteSpace(s[i])) i++; key = s.Substring(st, i - st); }
                    Skip();
                    if (i >= s.Length || s[i] != ':') throw new Exception("JSON: expected ':' at " + i);
                    i++;
                    JV val = Value();
                    if (!v.Map.ContainsKey(key)) v.Keys.Add(key);
                    v.Map[key] = val;
                }
            }
            else if (c == '[')
            {
                v.T = 'a'; i++;
                while (true)
                {
                    Skip();
                    if (i >= s.Length) throw new Exception("JSON: unterminated array");
                    if (s[i] == ']') { i++; break; }
                    if (s[i] == ',') { i++; continue; }
                    v.Arr.Add(Value());
                }
            }
            else if (c == '"' || c == '\'') { v.T = 's'; v.S = Str(); }
            else
            {
                int st = i;
                while (i < s.Length && (char.IsLetterOrDigit(s[i]) || s[i] == '-' || s[i] == '+' || s[i] == '.')) i++;
                string tok = s.Substring(st, i - st);
                if (tok == "true") { v.T = 'b'; v.B = true; }
                else if (tok == "false") { v.T = 'b'; v.B = false; }
                else if (tok == "null") { v.T = 'z'; }
                else
                {
                    double d;
                    if (!double.TryParse(tok, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) throw new Exception("JSON: bad token '" + tok + "' at " + st);
                    v.T = 'n'; v.N = d;
                }
            }
            return v;
        }
        string Str()
        {
            char q = s[i++];
            StringBuilder sb = new StringBuilder();
            while (i < s.Length && s[i] != q)
            {
                char c = s[i++];
                if (c == '\\' && i < s.Length)
                {
                    char e = s[i++];
                    switch (e)
                    {
                        case 'n': sb.Append('\n'); break;
                        case 't': sb.Append('\t'); break;
                        case 'r': sb.Append('\r'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u': sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16)); i += 4; break;
                        default: sb.Append(e); break;
                    }
                }
                else sb.Append(c);
            }
            i++;
            return sb.ToString();
        }
    }

    // ------------------------------------------------------------------ geometry
    public struct V3
    {
        public double X, Y, Z;
        public V3(double x, double y, double z) { X = x; Y = y; Z = z; }
    }

    public class Quad
    {
        public V3[] P = new V3[4];
        public double[] U = new double[4];
        public double[] V = new double[4];
        public Tex T;
        public V3 N;
        public bool Shade = true;
    }

    // ------------------------------------------------------------------ textures (mip chain, nearest sampling)
    public class Tex
    {
        public int W, H;
        public int Levels;
        public byte[][] L;
        public int[] LW, LH;
        public bool Trans;
        public string Name;

        public static Tex FromRGBA(byte[] rgba, int w, int h, string name)
        {
            Tex t = new Tex(); t.W = w; t.H = h; t.Name = name;
            for (int i = 3; i < rgba.Length; i += 4) { int a = rgba[i]; if (a >= 26 && a < 250) { t.Trans = true; break; } }
            List<byte[]> lv = new List<byte[]>(); List<int> lw = new List<int>(); List<int> lh = new List<int>();
            lv.Add(rgba); lw.Add(w); lh.Add(h);
            int cw = w, ch = h; byte[] cur = rgba;
            while ((cw > 1 || ch > 1) && lv.Count < 14)
            {
                int nw = Math.Max(1, cw >> 1), nh = Math.Max(1, ch >> 1);
                byte[] nx = new byte[nw * nh * 4];
                for (int y = 0; y < nh; y++)
                    for (int x = 0; x < nw; x++)
                    {
                        double r = 0, g = 0, b = 0, a = 0;
                        for (int dy = 0; dy < 2; dy++)
                            for (int dx = 0; dx < 2; dx++)
                            {
                                int sx = Math.Min(cw - 1, x * 2 + dx), sy = Math.Min(ch - 1, y * 2 + dy);
                                int si = (sy * cw + sx) * 4;
                                double al = cur[si + 3] / 255.0;
                                r += cur[si] * al; g += cur[si + 1] * al; b += cur[si + 2] * al; a += al;
                            }
                        int di = (y * nw + x) * 4;
                        if (a > 0)
                        {
                            nx[di] = (byte)Math.Min(255, Math.Round(r / a)); nx[di + 1] = (byte)Math.Min(255, Math.Round(g / a)); nx[di + 2] = (byte)Math.Min(255, Math.Round(b / a));
                            double aa = a / 4.0;
                            if (t.Trans) nx[di + 3] = (byte)Math.Round(aa * 255); else nx[di + 3] = (byte)(aa >= 0.5 ? 255 : 0);
                        }
                        else { nx[di] = 0; nx[di + 1] = 0; nx[di + 2] = 0; nx[di + 3] = 0; }
                    }
                lv.Add(nx); lw.Add(nw); lh.Add(nh);
                cur = nx; cw = nw; ch = nh;
            }
            t.L = lv.ToArray(); t.LW = lw.ToArray(); t.LH = lh.ToArray(); t.Levels = lv.Count;
            return t;
        }

        public static Tex Solid(int r, int g, int b, string name)
        {
            return FromRGBA(new byte[] { (byte)r, (byte)g, (byte)b, 255 }, 1, 1, name);
        }
        public static Tex Checker(int w, int h, int cell, int[] c1, int[] c2, string name)
        {
            byte[] d = new byte[w * h * 4];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int[] c = (((x / cell) + (y / cell)) % 2 == 0) ? c1 : c2;
                    int i = (y * w + x) * 4; d[i] = (byte)c[0]; d[i + 1] = (byte)c[1]; d[i + 2] = (byte)c[2]; d[i + 3] = 255;
                }
            return FromRGBA(d, w, h, name);
        }
        public static Tex Noise(int r, int g, int b, int amp, int seed, string name)
        {
            byte[] d = new byte[16 * 16 * 4];
            uint h = (uint)(seed * 2654435761u + 12345u);
            for (int i = 0; i < 256; i++)
            {
                h = h * 1664525u + 1013904223u;
                int n = (int)((h >> 16) % (uint)(amp * 2 + 1)) - amp;
                d[i * 4] = (byte)Math.Max(0, Math.Min(255, r + n)); d[i * 4 + 1] = (byte)Math.Max(0, Math.Min(255, g + n)); d[i * 4 + 2] = (byte)Math.Max(0, Math.Min(255, b + n)); d[i * 4 + 3] = 255;
            }
            return FromRGBA(d, 16, 16, name);
        }
    }

    // ------------------------------------------------------------------ rasterizer
    public class Rend
    {
        public const int CELL = 96, SS = 2, W = CELL * SS, MARGIN = 4;
        float[] cr = new float[W * W], cg = new float[W * W], cb = new float[W * W], ca = new float[W * W];
        float[] zb = new float[W * W];
        bool[] front = new bool[W * W];
        const double C225 = -0.70710678118654757, S225 = -0.70710678118654757, C30 = 0.86602540378443865, S30 = 0.5;
        const float ZEPS = 1e-5f;

        static void View(V3 p, out double x, out double y, out double z)
        {
            double qx = p.X - 0.5, qy = p.Y - 0.5, qz = p.Z - 0.5;
            double x1 = qx * C225 + qz * S225;
            double z1 = -qx * S225 + qz * C225;
            y = qy * C30 - z1 * S30;
            z = qy * S30 + z1 * C30;
            x = x1;
        }

        public static double ShadeOf(V3 n, bool shade)
        {
            if (!shade) return 1.0;
            double l = Math.Sqrt(n.X * n.X + n.Y * n.Y + n.Z * n.Z);
            if (l < 1e-9) return 1.0;
            double nx = n.X / l, ny = n.Y / l, nz = n.Z / l;
            return nx * nx * 0.6 + nz * nz * 0.8 + ny * ny * (ny >= 0 ? 1.0 : 0.5);
        }

        // returns CELL*CELL ARGB (straight alpha)
        public uint[] Render(List<Quad> quads)
        {
            int n = quads.Count;
            double[][] X = new double[n][], Y = new double[n][], Z = new double[n][];
            double minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
            for (int q = 0; q < n; q++)
            {
                X[q] = new double[4]; Y[q] = new double[4]; Z[q] = new double[4];
                for (int k = 0; k < 4; k++)
                {
                    View(quads[q].P[k], out X[q][k], out Y[q][k], out Z[q][k]);
                    if (X[q][k] < minx) minx = X[q][k]; if (X[q][k] > maxx) maxx = X[q][k];
                    if (Y[q][k] < miny) miny = Y[q][k]; if (Y[q][k] > maxy) maxy = Y[q][k];
                }
            }
            // reference: the unit cube is always part of the fit box, so every block that fits in 1x1x1 gets the same scale
            for (int c = 0; c < 8; c++)
            {
                double x, y, z; View(new V3(c & 1, (c >> 1) & 1, (c >> 2) & 1), out x, out y, out z);
                if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y;
            }
            double frame = CELL - 2 * MARGIN;
            double scale = Math.Min(frame / (maxx - minx), frame / (maxy - miny));
            double cx = (minx + maxx) / 2, cy = (miny + maxy) / 2;
            for (int q = 0; q < n; q++)
                for (int k = 0; k < 4; k++)
                {
                    X[q][k] = (CELL / 2.0 + (X[q][k] - cx) * scale) * SS;
                    Y[q][k] = (CELL / 2.0 - (Y[q][k] - cy) * scale) * SS;
                }

            Array.Clear(cr, 0, cr.Length); Array.Clear(cg, 0, cg.Length); Array.Clear(cb, 0, cb.Length); Array.Clear(ca, 0, ca.Length);
            for (int i = 0; i < zb.Length; i++) zb[i] = -1e9f;
            Array.Clear(front, 0, front.Length);

            List<int> trans = new List<int>();
            for (int q = 0; q < n; q++)
            {
                Quad qd = quads[q];
                double sh = ShadeOf(qd.N, qd.Shade);
                Tri(X[q], Y[q], Z[q], qd.U, qd.V, 0, 1, 2, qd.T, sh, 0);
                Tri(X[q], Y[q], Z[q], qd.U, qd.V, 0, 2, 3, qd.T, sh, 0);
                if (qd.T.Trans) trans.Add(q);
            }
            if (trans.Count > 0)
            {
                double[] mz = new double[n];
                for (int q = 0; q < n; q++) mz[q] = (Z[q][0] + Z[q][1] + Z[q][2] + Z[q][3]) / 4;
                trans.Sort(delegate (int a, int b) { return mz[a].CompareTo(mz[b]); }); // far (small z) first
                foreach (int q in trans)
                {
                    Quad qd = quads[q];
                    double sh = ShadeOf(qd.N, qd.Shade);
                    Tri(X[q], Y[q], Z[q], qd.U, qd.V, 0, 1, 2, qd.T, sh, 1);
                    Tri(X[q], Y[q], Z[q], qd.U, qd.V, 0, 2, 3, qd.T, sh, 1);
                }
            }
            // downscale SS x SS box filter (premultiplied)
            uint[] outp = new uint[CELL * CELL];
            for (int y = 0; y < CELL; y++)
                for (int x = 0; x < CELL; x++)
                {
                    double r = 0, g = 0, b = 0, a = 0;
                    for (int dy = 0; dy < SS; dy++)
                        for (int dx = 0; dx < SS; dx++)
                        {
                            int i = (y * SS + dy) * W + (x * SS + dx);
                            r += cr[i]; g += cg[i]; b += cb[i]; a += ca[i];
                        }
                    double inv = 1.0 / (SS * SS);
                    a *= inv; r *= inv; g *= inv; b *= inv;
                    if (a <= 0.004) { outp[y * CELL + x] = 0; continue; }
                    int ia = (int)Math.Round(a * 255), ir = (int)Math.Round(r / a * 255), ig = (int)Math.Round(g / a * 255), ib = (int)Math.Round(b / a * 255);
                    if (ir > 255) ir = 255; if (ig > 255) ig = 255; if (ib > 255) ib = 255; if (ia > 255) ia = 255;
                    outp[y * CELL + x] = ((uint)ia << 24) | ((uint)ir << 16) | ((uint)ig << 8) | (uint)ib;
                }
            return outp;
        }

        void Tri(double[] X, double[] Y, double[] Z, double[] U, double[] V, int a, int b, int c, Tex t, double shade, int pass)
        {
            double x0 = X[a], y0 = Y[a], z0 = Z[a], u0 = U[a], v0 = V[a];
            double x1 = X[b], y1 = Y[b], z1 = Z[b], u1 = U[b], v1 = V[b];
            double x2 = X[c], y2 = Y[c], z2 = Z[c], u2 = U[c], v2 = V[c];
            double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
            if (Math.Abs(area) < 1e-7) return;
            bool isFront = area < 0; // vertex tables are CCW seen from outside; screen Y is down, so front-facing = negative area
            if (area < 0)
            {
                double tt;
                tt = x1; x1 = x2; x2 = tt; tt = y1; y1 = y2; y2 = tt; tt = z1; z1 = z2; z2 = tt; tt = u1; u1 = u2; u2 = tt; tt = v1; v1 = v2; v2 = tt;
                area = -area;
            }
            int mnx = (int)Math.Floor(Math.Min(x0, Math.Min(x1, x2))), mxx = (int)Math.Ceiling(Math.Max(x0, Math.Max(x1, x2)));
            int mny = (int)Math.Floor(Math.Min(y0, Math.Min(y1, y2))), mxy = (int)Math.Ceiling(Math.Max(y0, Math.Max(y1, y2)));
            if (mnx < 0) mnx = 0; if (mny < 0) mny = 0; if (mxx > W - 1) mxx = W - 1; if (mxy > W - 1) mxy = W - 1;
            double texA = Math.Abs((u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)) * t.W * t.H;
            int lod = 0; double ratio = texA / area;
            if (ratio > 1.0) { lod = (int)(0.5 * Math.Log(ratio) / Math.Log(2.0)); if (lod > t.Levels - 1) lod = t.Levels - 1; if (lod < 0) lod = 0; }
            byte[] tex = t.L[lod]; int tw = t.LW[lod], th = t.LH[lod];
            double invA = 1.0 / area;
            for (int y = mny; y <= mxy; y++)
            {
                double py = y + 0.5;
                for (int x = mnx; x <= mxx; x++)
                {
                    double px = x + 0.5;
                    double w0 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1);
                    double w1 = (x0 - x2) * (py - y2) - (y0 - y2) * (px - x2);
                    double w2 = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0);
                    if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                    double b0 = w0 * invA, b1 = w1 * invA, b2 = w2 * invA;
                    float z = (float)(b0 * z0 + b1 * z1 + b2 * z2);
                    int idx = y * W + x;
                    float dz = z - zb[idx];
                    if (dz < -ZEPS) continue;
                    // coplanar tie (two-sided planes, double faces): keep the front-facing quad rather than whichever was drawn last
                    if (pass == 0 && dz <= ZEPS && front[idx] && !isFront) continue;
                    double u = b0 * u0 + b1 * u1 + b2 * u2, v = b0 * v0 + b1 * v1 + b2 * v2;
                    int tx = (int)(u * tw), ty = (int)(v * th);
                    if (tx < 0) tx = 0; else if (tx >= tw) tx = tw - 1;
                    if (ty < 0) ty = 0; else if (ty >= th) ty = th - 1;
                    int ti = (ty * tw + tx) * 4;
                    int al = tex[ti + 3];
                    if (pass == 0)
                    {
                        if (al < 250) continue;
                        cr[idx] = (float)(tex[ti] * shade / 255.0); cg[idx] = (float)(tex[ti + 1] * shade / 255.0); cb[idx] = (float)(tex[ti + 2] * shade / 255.0); ca[idx] = 1f;
                        zb[idx] = z; front[idx] = isFront;
                    }
                    else
                    {
                        if (al < 26 || al >= 250) continue;
                        float fa = al / 255f;
                        cr[idx] = (float)(tex[ti] * shade / 255.0) * fa + cr[idx] * (1 - fa);
                        cg[idx] = (float)(tex[ti + 1] * shade / 255.0) * fa + cg[idx] * (1 - fa);
                        cb[idx] = (float)(tex[ti + 2] * shade / 255.0) * fa + cb[idx] * (1 - fa);
                        ca[idx] = fa + ca[idx] * (1 - fa);
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ OBJ model (port of OBJModelParser as in objlib.ps1)
    public class RL { public string Ns, Path; }
    public class ObjPt { public double X, Y, Z, U, V, NX, NY, NZ; public bool HasUV, HasN; }
    public class ObjGroup { public string Name; public string Mat; public List<List<ObjPt>> Faces = new List<List<ObjPt>>(); public RL Tex; }
    public class ObjModel { public List<ObjGroup> Groups = new List<ObjGroup>(); }

    public class RM // resolved JSON model
    {
        public Dictionary<string, string> Tex = new Dictionary<string, string>();
        public List<JV> Elems;
    }

    public class Sel { public string Model; public int X, Y; public bool UvLock; }

    public static class Program
    {
        public static string[] Roots = new string[0];   // filled by render.ps1: pack, mod, vanilla
        // extracted vanilla 1.12.2 client assets (the minecraft namespace)
        public static void AddRoot(string r) { List<string> l = new List<string>(Roots); if (!l.Contains(r)) { l.Add(r); Roots = l.ToArray(); } }
        public static bool VanillaTexUsed = false;     // set whenever a minecraft: texture is resolved (per-block counter in Full)
        static int curTint = -1;                       // RGB applied to faces with a tintindex while building a vanilla model, -1 = none
        static Dictionary<string, Tex> tintCache = new Dictionary<string, Tex>();
        public static List<string> Failures = new List<string>();
        public static List<string> Warns = new List<string>();
        static HashSet<string> warnSeen = new HashSet<string>();
        static string ctx = "";
        static Dictionary<string, Tex> texCache = new Dictionary<string, Tex>();
        static Dictionary<string, ObjModel> objCache = new Dictionary<string, ObjModel>();
        static Dictionary<string, string> objErr = new Dictionary<string, string>();
        static Dictionary<string, RM> jsonCache = new Dictionary<string, RM>();
        static Tex vanillaTex, missingTex, whiteTex, farmTop, farmSide;
        public static int UvLockSeen = 0;

        static void Warn(string msg) { string k = ctx + "|" + msg; if (warnSeen.Add(k)) Warns.Add("WARN " + ctx + ": " + msg); }

        static Program()
        {
            vanillaTex = Tex.Checker(16, 16, 2, new int[] { 122, 122, 122 }, new int[] { 134, 134, 134 }, "vanilla-placeholder");
            missingTex = Tex.Checker(16, 16, 8, new int[] { 248, 0, 248 }, new int[] { 0, 0, 0 }, "missing");
            whiteTex = Tex.Solid(255, 255, 255, "white");
            farmTop = Tex.Noise(96, 64, 40, 7, 1, "farmland-top");
            farmSide = Tex.Noise(134, 96, 67, 8, 2, "farmland-side");
        }

        // ---------------------------------------------------------------- resource lookup
        static string Norm(string p) { while (p.IndexOf("//") >= 0) p = p.Replace("//", "/"); return p.TrimStart('/'); }
        public static string Find(string ns, string rel)
        {
            rel = Norm(rel).Replace('/', '\\');
            foreach (string r in Roots) { string f = System.IO.Path.Combine(r, ns, rel); if (File.Exists(f)) return f; }
            return null;
        }
        static void SplitRef(string s, string defNs, out string ns, out string path)
        {
            int i = s.IndexOf(':');
            if (i >= 0) { ns = s.Substring(0, i); path = s.Substring(i + 1); } else { ns = defNs; path = s; }
            if (ns == "") ns = defNs;
            ns = ns.ToLowerInvariant(); path = path.ToLowerInvariant();
        }

        static Tex LoadFile(string file) { return LoadFile(file, false); }
        // strip = vanilla texture: an animated strip (h = n*w) shows its first frame
        static Tex LoadFile(string file, bool strip)
        {
            string key = file.ToLowerInvariant();
            Tex t;
            if (texCache.TryGetValue(key, out t)) return t;
            byte[] bytes = File.ReadAllBytes(file);
            using (MemoryStream ms = new MemoryStream(bytes))
            using (Bitmap src = new Bitmap(ms))
            {
                int w = src.Width, h = src.Height;
                if (strip && h > w && h % w == 0) h = w;
                if (w != h) { Warn("non-square texture " + w + "x" + h + " (" + Path.GetFileName(file) + ") -> missing texture, as in game"); texCache[key] = missingTex; return missingTex; }
                using (Bitmap c = new Bitmap(w, h, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(c)) { g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy; g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, w, h, GraphicsUnit.Pixel); }
                    BitmapData bd = c.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                    byte[] raw = new byte[w * h * 4];
                    System.Runtime.InteropServices.Marshal.Copy(bd.Scan0, raw, 0, raw.Length);
                    c.UnlockBits(bd);
                    for (int i = 0; i < raw.Length; i += 4) { byte b = raw[i]; raw[i] = raw[i + 2]; raw[i + 2] = b; } // BGRA -> RGBA
                    t = Tex.FromRGBA(raw, w, h, file);
                }
            }
            texCache[key] = t;
            return t;
        }

        // texture ref "ns:path" ('path' = minecraft) -> textures/<path>.png
        static Tex TexRef(string ns, string path)
        {
            path = Norm(path.ToLowerInvariant());
            if (ns == "minecraft")
            {
                VanillaTexUsed = true;
                string vf = Find(ns, "textures/" + path + ".png");
                if (vf == null) { Warn("missing vanilla texture minecraft:" + path + " -> placeholder"); return vanillaTex; }
                try { return LoadFile(vf, true); }
                catch (Exception e) { Warn("vanilla texture load failed minecraft:" + path + " (" + e.Message + ")"); return vanillaTex; }
            }
            string f = Find(ns, "textures/" + path + ".png");
            if (f == null) { Warn("missing texture " + ns + ":" + path); return missingTex; }
            try { return LoadFile(f); }
            catch (Exception e) { Warn("texture load failed " + ns + ":" + path + " (" + e.Message + ")"); return missingTex; }
        }

        // ---------------------------------------------------------------- OBJ
        static RL BuildRL(string str, string parent)
        {
            int i = str.IndexOf(':');
            if (i < 0) throw new Exception("IllegalArgumentException: Expected a namespaced string ('" + str + "')");
            string ns = str.Substring(0, i), val = str.Substring(i + 1);
            if (val.IndexOf('/') == -1 && parent != null) val = parent + "/" + val;
            RL r = new RL(); r.Ns = ns.ToLowerInvariant(); r.Path = val.ToLowerInvariant(); return r;
        }
        static string[] JavaSplitSpace(string line)
        {
            List<string> p = new List<string>(line.Split(' '));
            while (p.Count > 1 && p[p.Count - 1] == "") p.RemoveAt(p.Count - 1);
            return p.ToArray();
        }
        static Dictionary<string, RL> ParseMtl(string file, string objRL)
        {
            Dictionary<string, RL> mats = new Dictionary<string, RL>();
            string cur = null; RL curTex = null;
            int ls = objRL.LastIndexOf('/');
            string parentDirs = ls >= 0 ? objRL.Substring(0, ls) : null;
            string parentName = null;
            if (parentDirs != null) { int l2 = parentDirs.LastIndexOf('/'); if (l2 != -1) parentName = parentDirs.Substring(l2 + 1); }
            foreach (string line in File.ReadAllLines(file))
            {
                if (line.StartsWith("#") || line.Length == 0) continue;
                string[] p = JavaSplitSpace(line);
                string hdr = p[0];
                if (hdr == "newmtl") { if (cur != null) mats[cur] = curTex; cur = p.Length > 1 ? p[1] : null; curTex = null; if (cur == null) throw new Exception("newmtl without name"); }
                else if (hdr == "map_Kd")
                {
                    if (cur == null) throw new Exception("MalformedMaterialLibraryException: map_Kd before newmtl");
                    if (p.Length < 2) throw new Exception("map_Kd without value");
                    curTex = BuildRL(p[1], parentName);
                }
            }
            if (cur != null) mats[cur] = curTex;
            if (mats.Count == 0) throw new Exception("IllegalStateException: material library needs at least one material");
            return mats;
        }
        static double Dbl(string s) { return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture); }
        static int Int(string s) { return int.Parse(s, NumberStyles.Integer, CultureInfo.InvariantCulture); }

        static ObjModel ParseObj(string file, string objRL)
        {
            ObjModel m = new ObjModel();
            string[] lines = File.ReadAllLines(file);
            List<double[]> V = new List<double[]>(), VT = new List<double[]>(), VN = new List<double[]>();
            Dictionary<string, RL> mats = null;
            ObjGroup gb = null;
            int lsl = objRL.LastIndexOf('/'); string parentPath = objRL.Substring(0, lsl);
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i];
                if (line.StartsWith("#") || line.Length == 0) continue;
                int idx = line.IndexOf(' ');
                if (idx < 0) throw new Exception("StringIndexOutOfBounds at line " + (i + 1) + ": '" + line + "'");
                string hdr = line.Substring(0, idx);
                string[] rest = line.Substring(idx).Trim().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                switch (hdr)
                {
                    case "mtllib":
                        {
                            RL r = BuildRL(rest[0], parentPath);
                            string mf = Find(r.Ns, r.Path);
                            if (mf == null) throw new Exception("mtl not found: " + r.Ns + ":" + r.Path);
                            mats = ParseMtl(mf, objRL);
                            break;
                        }
                    case "v": V.Add(new double[] { Dbl(rest[0]), Dbl(rest[1]), Dbl(rest[2]) }); break;
                    case "vn": VN.Add(new double[] { Dbl(rest[0]), Dbl(rest[1]), Dbl(rest[2]) }); break;
                    case "vt":
                        VT.Add(new double[] { Math.Max(0, Math.Min(1, Dbl(rest[0]))), Math.Max(0, Math.Min(1, Dbl(rest[1]))) }); break;
                    case "g":
                        if (gb != null) { if (gb.Faces.Count == 0) throw new Exception("Faces cannot be empty"); m.Groups.Add(gb); }
                        gb = new ObjGroup(); gb.Name = rest.Length > 0 ? rest[0] : ""; break;
                    case "usemtl":
                        if (gb == null) { gb = new ObjGroup(); gb.Name = "default"; }
                        if (mats == null) throw new Exception("usemtl but no material library");
                        if (rest.Length < 1 || !mats.ContainsKey(rest[0])) throw new Exception("material '" + (rest.Length > 0 ? rest[0] : "") + "' not in library");
                        gb.Mat = rest[0]; break;
                    case "f":
                        {
                            if (gb == null) { gb = new ObjGroup(); gb.Name = "default"; }
                            List<ObjPt> face = new List<ObjPt>();
                            foreach (string seg in rest)
                            {
                                string[] ix = seg.Split('/');
                                int vi = ix[0] == "" ? 0 : Int(ix[0]);
                                if (vi < 1 || vi > V.Count) throw new Exception("bad vertex index " + vi + " (line " + (i + 1) + ")");
                                ObjPt pt = new ObjPt(); double[] pv = V[vi - 1]; pt.X = pv[0]; pt.Y = pv[1]; pt.Z = pv[2];
                                int ti = -1, ni = -1;
                                if (ix.Length > 1)
                                {
                                    if (ix.Length == 3 && ix[1] == "") ni = Int(ix[2]);
                                    else { ti = Int(ix[1]); if (ix.Length > 2) ni = Int(ix[2]); }
                                }
                                if (ti != -1) { if (ti < 1 || ti > VT.Count) throw new Exception("bad vt index " + ti + " (line " + (i + 1) + ")"); pt.HasUV = true; pt.U = VT[ti - 1][0]; pt.V = VT[ti - 1][1]; }
                                if (ni != -1) { if (ni < 1 || ni > VN.Count) throw new Exception("bad vn index " + ni + " (line " + (i + 1) + ")"); pt.HasN = true; pt.NX = VN[ni - 1][0]; pt.NY = VN[ni - 1][1]; pt.NZ = VN[ni - 1][2]; }
                                face.Add(pt);
                            }
                            gb.Faces.Add(face);
                            break;
                        }
                }
            }
            if (gb != null) { if (gb.Faces.Count == 0) throw new Exception("Faces cannot be empty"); m.Groups.Add(gb); }
            if (m.Groups.Count == 0) throw new Exception("Groups cannot be empty");
            if (mats == null) throw new Exception("NullPointerException: no mtllib (OBJModel ctor dereferences the material library)");
            foreach (ObjGroup g in m.Groups) { g.Tex = null; if (g.Mat != null) g.Tex = mats[g.Mat]; }
            return m;
        }

        public static ObjModel GetObj(string ns, string rl) // rl = models/block/....obj
        {
            string key = ns + "|" + rl;
            ObjModel m;
            if (objCache.TryGetValue(key, out m)) return m;
            string err;
            if (objErr.TryGetValue(key, out err)) throw new Exception(err);
            try
            {
                string f = Find(ns, rl);
                if (f == null) throw new Exception("OBJ not found: " + ns + ":" + rl);
                m = ParseObj(f, Norm(rl));
                objCache[key] = m; return m;
            }
            catch (Exception e) { objErr[key] = e.Message; throw; }
        }

        // ---------------------------------------------------------------- vanilla parents (hard-coded, 1.12.2)
        static Dictionary<string, string> Builtin = MakeBuiltin();
        const string SLAB_SIDES = "\"north\":{\"uv\":[0,8,16,16],\"texture\":\"#side\"},\"south\":{\"uv\":[0,8,16,16],\"texture\":\"#side\"},\"west\":{\"uv\":[0,8,16,16],\"texture\":\"#side\"},\"east\":{\"uv\":[0,8,16,16],\"texture\":\"#side\"}";
        static Dictionary<string, string> MakeBuiltin()
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            d["block/block"] = "{}";
            d["block/cube"] = "{\"parent\":\"block/block\",\"elements\":[{\"from\":[0,0,0],\"to\":[16,16,16],\"faces\":{\"down\":{\"texture\":\"#down\"},\"up\":{\"texture\":\"#up\"},\"north\":{\"texture\":\"#north\"},\"south\":{\"texture\":\"#south\"},\"west\":{\"texture\":\"#west\"},\"east\":{\"texture\":\"#east\"}}}]}";
            d["block/cube_all"] = "{\"parent\":\"block/cube\",\"textures\":{\"particle\":\"#all\",\"down\":\"#all\",\"up\":\"#all\",\"north\":\"#all\",\"east\":\"#all\",\"south\":\"#all\",\"west\":\"#all\"}}";
            d["block/cube_mirrored_all"] = d["block/cube_all"];
            d["block/cube_column"] = "{\"parent\":\"block/cube\",\"textures\":{\"particle\":\"#side\",\"down\":\"#end\",\"up\":\"#end\",\"north\":\"#side\",\"east\":\"#side\",\"south\":\"#side\",\"west\":\"#side\"}}";
            d["block/cube_bottom_top"] = "{\"parent\":\"block/cube\",\"textures\":{\"particle\":\"#side\",\"down\":\"#bottom\",\"up\":\"#top\",\"north\":\"#side\",\"east\":\"#side\",\"south\":\"#side\",\"west\":\"#side\"}}";
            d["block/orientable"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#front\"},\"elements\":[{\"from\":[0,0,0],\"to\":[16,16,16],\"faces\":{\"down\":{\"texture\":\"#bottom\"},\"up\":{\"texture\":\"#top\"},\"north\":{\"texture\":\"#front\"},\"south\":{\"texture\":\"#side\"},\"west\":{\"texture\":\"#side\"},\"east\":{\"texture\":\"#side\"}}}]}";
            string cross = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#cross\"},\"elements\":["
                + "{\"from\":[0.8,0,8],\"to\":[15.2,16,8],\"rotation\":{\"origin\":[8,8,8],\"axis\":\"y\",\"angle\":45,\"rescale\":true},\"shade\":false,\"faces\":{\"north\":{\"uv\":[0,0,16,16],\"texture\":\"#cross\"},\"south\":{\"uv\":[0,0,16,16],\"texture\":\"#cross\"}}},"
                + "{\"from\":[8,0,0.8],\"to\":[8,16,15.2],\"rotation\":{\"origin\":[8,8,8],\"axis\":\"y\",\"angle\":45,\"rescale\":true},\"shade\":false,\"faces\":{\"west\":{\"uv\":[0,0,16,16],\"texture\":\"#cross\"},\"east\":{\"uv\":[0,0,16,16],\"texture\":\"#cross\"}}}]}";
            d["block/cross"] = cross; d["block/tinted_cross"] = cross;
            d["block/crop"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#crop\"},\"elements\":["
                + "{\"from\":[4,-1,0],\"to\":[4,15,16],\"shade\":false,\"faces\":{\"east\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"},\"west\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"}}},"
                + "{\"from\":[12,-1,0],\"to\":[12,15,16],\"shade\":false,\"faces\":{\"east\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"},\"west\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"}}},"
                + "{\"from\":[0,-1,4],\"to\":[16,15,4],\"shade\":false,\"faces\":{\"north\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"},\"south\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"}}},"
                + "{\"from\":[0,-1,12],\"to\":[16,15,12],\"shade\":false,\"faces\":{\"north\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"},\"south\":{\"uv\":[0,0,16,16],\"texture\":\"#crop\"}}}]}";
            d["block/half_slab"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#side\"},\"elements\":[{\"from\":[0,0,0],\"to\":[16,8,16],\"faces\":{\"down\":{\"uv\":[0,0,16,16],\"texture\":\"#bottom\"},\"up\":{\"uv\":[0,0,16,16],\"texture\":\"#top\"}," + SLAB_SIDES + "}}]}";
            d["block/upper_slab"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#side\"},\"elements\":[{\"from\":[0,8,0],\"to\":[16,16,16],\"faces\":{\"down\":{\"uv\":[0,0,16,16],\"texture\":\"#bottom\"},\"up\":{\"uv\":[0,0,16,16],\"texture\":\"#top\"},"
                + "\"north\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"},\"south\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"},\"west\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"},\"east\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"}}}]}";
            string baseSlab = "{\"from\":[0,0,0],\"to\":[16,8,16],\"faces\":{\"down\":{\"uv\":[0,0,16,16],\"texture\":\"#bottom\"},\"up\":{\"uv\":[0,0,16,16],\"texture\":\"#top\"}," + SLAB_SIDES + "}}";
            d["block/stairs"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#side\"},\"elements\":[" + baseSlab + ","
                + "{\"from\":[8,8,0],\"to\":[16,16,16],\"faces\":{\"up\":{\"uv\":[8,0,16,16],\"texture\":\"#top\"},\"north\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"},\"south\":{\"uv\":[8,0,16,8],\"texture\":\"#side\"},\"west\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"},\"east\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"}}}]}";
            d["block/inner_stairs"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#side\"},\"elements\":[" + baseSlab + ","
                + "{\"from\":[8,8,0],\"to\":[16,16,16],\"faces\":{\"up\":{\"uv\":[8,0,16,16],\"texture\":\"#top\"},\"north\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"},\"south\":{\"uv\":[8,0,16,8],\"texture\":\"#side\"},\"west\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"},\"east\":{\"uv\":[0,0,16,8],\"texture\":\"#side\"}}},"
                + "{\"from\":[0,8,8],\"to\":[8,16,16],\"faces\":{\"up\":{\"uv\":[0,8,8,16],\"texture\":\"#top\"},\"south\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"},\"west\":{\"uv\":[8,0,16,8],\"texture\":\"#side\"},\"east\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"}}}]}";
            d["block/outer_stairs"] = "{\"parent\":\"block/block\",\"textures\":{\"particle\":\"#side\"},\"elements\":[" + baseSlab + ","
                + "{\"from\":[8,8,8],\"to\":[16,16,16],\"faces\":{\"up\":{\"uv\":[8,8,16,16],\"texture\":\"#top\"},\"north\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"},\"south\":{\"uv\":[8,0,16,8],\"texture\":\"#side\"},\"west\":{\"uv\":[0,0,8,8],\"texture\":\"#side\"},\"east\":{\"uv\":[8,0,16,8],\"texture\":\"#side\"}}}]}";
            d["block/stone_stairs"] = "{\"parent\":\"block/stairs\"}";
            d["block/stone_inner_stairs"] = "{\"parent\":\"block/inner_stairs\"}";
            d["block/stone_outer_stairs"] = "{\"parent\":\"block/outer_stairs\"}";
            return d;
        }

        static RM ResolveJson(string ns, string path, int depth)
        {
            if (depth > 16) throw new Exception("model parent chain too deep");
            path = Norm(path.ToLowerInvariant());
            string key = ns + "|" + path;
            RM rm;
            if (jsonCache.TryGetValue(key, out rm)) return rm;
            string js;
            string f = Find(ns, "models/" + path + ".json");
            if (f != null) js = File.ReadAllText(f, Encoding.UTF8);
            else if (ns == "minecraft" && Builtin.TryGetValue(path, out js)) { }
            else if (ns == "minecraft") throw new Exception("vanilla model 'minecraft:" + path + "' is not available (not in the extracted jar)");
            else throw new Exception("model json not found: " + ns + ":models/" + path + ".json");
            rm = BuildRM(js, depth);
            jsonCache[key] = rm;
            return rm;
        }
        // inline model text (custom stand-ins) or a loaded file: parent chain + textures + elements
        static RM BuildRM(string js, int depth)
        {
            JV m = JP.Parse(js);
            RM rm = new RM();
            string par = m.Str("parent");
            if (par != null)
            {
                string pns, pp; SplitRef(par, "minecraft", out pns, out pp);
                RM pr = ResolveJson(pns, pp, depth + 1);
                foreach (KeyValuePair<string, string> kv in pr.Tex) rm.Tex[kv.Key] = kv.Value;
                rm.Elems = pr.Elems;
            }
            JV tx = m.Get("textures");
            if (tx != null && tx.T == 'o') foreach (string k in tx.Keys) { JV v = tx.Map[k]; if (v.T == 's') rm.Tex[k] = v.S; }
            JV el = m.Get("elements");
            if (el != null && el.T == 'a') rm.Elems = el.Arr;
            return rm;
        }
        public static RM InlineModel(string js) { return BuildRM(js, 0); }

        static Tex ResolveFaceTex(RM rm, string t)
        {
            int guard = 0;
            while (t != null && t.StartsWith("#") && guard++ < 12) { string v; if (rm.Tex.TryGetValue(t.Substring(1), out v)) t = v; else { t = null; } }
            if (t == null || t.StartsWith("#")) { Warn("unresolved texture variable"); return missingTex; }
            string ns, p; SplitRef(t, "minecraft", out ns, out p);
            return TexRef(ns, p);
        }

        // vertex corner selectors per facing (0 = min, 1 = max) in vanilla FaceInfo order; facing order D,U,N,S,W,E
        static readonly string[] FaceNames = new string[] { "down", "up", "north", "south", "west", "east" };
        static readonly int[][] FaceVerts = new int[][] {
            new int[] { 0,0,1, 0,0,0, 1,0,0, 1,0,1 },   // down
            new int[] { 0,1,0, 0,1,1, 1,1,1, 1,1,0 },   // up
            new int[] { 1,1,0, 1,0,0, 0,0,0, 0,1,0 },   // north
            new int[] { 0,1,1, 0,0,1, 1,0,1, 1,1,1 },   // south
            new int[] { 0,1,0, 0,0,0, 0,0,1, 0,1,1 },   // west
            new int[] { 1,1,1, 1,0,1, 1,0,0, 1,1,0 } }; // east
        static readonly double[][] FaceNormals = new double[][] {
            new double[] { 0,-1,0 }, new double[] { 0,1,0 }, new double[] { 0,0,-1 }, new double[] { 0,0,1 }, new double[] { -1,0,0 }, new double[] { 1,0,0 } };

        static V3 ElemRot(V3 p, double[] o, string axis, double ang, bool rescale)
        {
            double x = p.X - o[0], y = p.Y - o[1], z = p.Z - o[2];
            double r = ang * Math.PI / 180.0, c = Math.Cos(r), s = Math.Sin(r);
            double sc = rescale ? 1.0 / Math.Cos(r) : 1.0;
            double nx = x, ny = y, nz = z;
            if (axis == "y") { x *= sc; z *= sc; nx = x * c + z * s; nz = -x * s + z * c; }
            else if (axis == "x") { y *= sc; z *= sc; ny = y * c - z * s; nz = y * s + z * c; }
            else { x *= sc; y *= sc; nx = x * c - y * s; ny = x * s + y * c; }
            return new V3(nx + o[0], ny + o[1], nz + o[2]);
        }
        static V3 ElemRotN(V3 p, string axis, double ang)
        {
            double r = ang * Math.PI / 180.0, c = Math.Cos(r), s = Math.Sin(r);
            if (axis == "y") return new V3(p.X * c + p.Z * s, p.Y, -p.X * s + p.Z * c);
            if (axis == "x") return new V3(p.X, p.Y * c - p.Z * s, p.Y * s + p.Z * c);
            return new V3(p.X * c - p.Y * s, p.X * s + p.Y * c, p.Z);
        }

        static Tex TintTex(Tex t, int rgb)
        {
            string key = t.Name + "|" + rgb; Tex r;
            if (tintCache.TryGetValue(key, out r)) return r;
            byte[] src = t.L[0]; byte[] d = new byte[src.Length];
            double tr = ((rgb >> 16) & 255) / 255.0, tg = ((rgb >> 8) & 255) / 255.0, tb = (rgb & 255) / 255.0;
            for (int i = 0; i < src.Length; i += 4)
            {
                d[i] = (byte)Math.Round(src[i] * tr); d[i + 1] = (byte)Math.Round(src[i + 1] * tg); d[i + 2] = (byte)Math.Round(src[i + 2] * tb); d[i + 3] = src[i + 3];
            }
            r = Tex.FromRGBA(d, t.W, t.H, key);
            tintCache[key] = r;
            return r;
        }

        static List<Quad> BuildJson(RM rm)
        {
            if (rm.Elems == null || rm.Elems.Count == 0) throw new Exception("model has no elements");
            List<Quad> res = new List<Quad>();
            foreach (JV el in rm.Elems)
            {
                JV fr = el.Get("from"), to = el.Get("to"), faces = el.Get("faces");
                if (fr == null || to == null || faces == null || fr.Arr.Count < 3 || to.Arr.Count < 3) continue;
                double[] f = new double[] { fr.Arr[0].N, fr.Arr[1].N, fr.Arr[2].N };
                double[] t = new double[] { to.Arr[0].N, to.Arr[1].N, to.Arr[2].N };
                bool shade = el.Bool("shade", true);
                JV rot = el.Get("rotation");
                double[] origin = null; string axis = null; double ang = 0; bool rescale = false;
                if (rot != null && rot.T == 'o')
                {
                    JV o = rot.Get("origin"); axis = rot.Str("axis"); ang = rot.Num("angle", 0); rescale = rot.Bool("rescale", false);
                    if (o != null && o.Arr.Count >= 3 && axis != null && Math.Abs(ang) > 1e-9) origin = new double[] { o.Arr[0].N / 16, o.Arr[1].N / 16, o.Arr[2].N / 16 };
                }
                for (int fi = 0; fi < 6; fi++)
                {
                    JV face = faces.Get(FaceNames[fi]);
                    if (face == null || face.T != 'o') continue;
                    Quad q = new Quad();
                    q.T = ResolveFaceTex(rm, face.Str("texture"));
                    if (curTint >= 0 && face.Has("tintindex")) q.T = TintTex(q.T, curTint);
                    q.Shade = shade;
                    double[] uv = new double[4];
                    JV uvj = face.Get("uv");
                    if (uvj != null && uvj.Arr.Count >= 4) { for (int k = 0; k < 4; k++) uv[k] = uvj.Arr[k].N; }
                    else
                    {
                        switch (fi)
                        {
                            case 0: uv = new double[] { f[0], 16 - t[2], t[0], 16 - f[2] }; break;
                            case 1: uv = new double[] { f[0], f[2], t[0], t[2] }; break;
                            case 2: uv = new double[] { 16 - t[0], 16 - t[1], 16 - f[0], 16 - f[1] }; break;
                            case 3: uv = new double[] { f[0], 16 - t[1], t[0], 16 - f[1] }; break;
                            case 4: uv = new double[] { f[2], 16 - t[1], t[2], 16 - f[1] }; break;
                            default: uv = new double[] { 16 - t[2], 16 - t[1], 16 - f[2], 16 - f[1] }; break;
                        }
                    }
                    int frot = (int)face.Num("rotation", 0);
                    int[] sel = FaceVerts[fi];
                    for (int k = 0; k < 4; k++)
                    {
                        double px = (sel[k * 3] == 0 ? f[0] : t[0]) / 16, py = (sel[k * 3 + 1] == 0 ? f[1] : t[1]) / 16, pz = (sel[k * 3 + 2] == 0 ? f[2] : t[2]) / 16;
                        V3 p = new V3(px, py, pz);
                        if (origin != null) p = ElemRot(p, origin, axis, ang, rescale);
                        q.P[k] = p;
                        int j = (k + frot / 90) % 4;
                        q.U[k] = ((j == 0 || j == 1) ? uv[0] : uv[2]) / 16.0;
                        q.V[k] = ((j == 0 || j == 3) ? uv[1] : uv[3]) / 16.0;
                    }
                    V3 n = new V3(FaceNormals[fi][0], FaceNormals[fi][1], FaceNormals[fi][2]);
                    if (origin != null) n = ElemRotN(n, axis, ang);
                    q.N = n;
                    res.Add(q);
                }
            }
            if (res.Count == 0) throw new Exception("model has no drawable faces");
            return res;
        }

        static V3 Cross(V3 a, V3 b) { return new V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X); }

        static List<Quad> BuildObj(ObjModel m)
        {
            List<Quad> res = new List<Quad>();
            foreach (ObjGroup g in m.Groups)
            {
                Tex tx;
                if (g.Tex == null) tx = whiteTex;
                else
                {
                    string p = g.Tex.Path; if (p.EndsWith(".png")) p = p.Split('.')[0];
                    tx = TexRef(g.Tex.Ns, p);
                }
                foreach (List<ObjPt> face in g.Faces)
                {
                    int n = face.Count;
                    if (n < 3) throw new Exception("face with " + n + " vertices");
                    int tris = n - 2; // fan; every pack face is a quad
                    for (int s = 0; s < (n == 4 ? 1 : tris); s++)
                    {
                        Quad q = new Quad(); q.T = tx;
                        ObjPt[] pts;
                        if (n == 4) pts = new ObjPt[] { face[0], face[1], face[2], face[3] };
                        else pts = new ObjPt[] { face[0], face[s + 1], face[s + 2], face[s + 2] };
                        bool hasN = false; V3 nn = new V3(0, 0, 0);
                        for (int k = 0; k < 4; k++)
                        {
                            ObjPt pt = pts[k];
                            q.P[k] = new V3(pt.X, pt.Y, pt.Z);
                            if (pt.HasUV) { q.U[k] = pt.U; q.V[k] = 1.0 - pt.V; } else { q.U[k] = 0; q.V[k] = 1; }
                            if (!hasN && pt.HasN) { hasN = true; nn = new V3(pt.NX, pt.NY, pt.NZ); }
                        }
                        if (!hasN || (nn.X * nn.X + nn.Y * nn.Y + nn.Z * nn.Z) < 1e-12)
                        {
                            V3 a = new V3(q.P[2].X - q.P[0].X, q.P[2].Y - q.P[0].Y, q.P[2].Z - q.P[0].Z);
                            V3 b = new V3(q.P[3].X - q.P[1].X, q.P[3].Y - q.P[1].Y, q.P[3].Z - q.P[1].Z);
                            nn = Cross(a, b);
                        }
                        q.N = nn;
                        res.Add(q);
                    }
                }
            }
            return res;
        }

        static V3 RotVariant(V3 p, int rx, int ry)
        {
            double x = p.X - 0.5, y = p.Y - 0.5, z = p.Z - 0.5;
            if (rx != 0)
            {
                double a = -rx * Math.PI / 180.0, c = Math.Cos(a), s = Math.Sin(a);
                double ny = y * c - z * s, nz = y * s + z * c; y = ny; z = nz;
            }
            if (ry != 0)
            {
                double b = -ry * Math.PI / 180.0, c = Math.Cos(b), s = Math.Sin(b);
                double nx = x * c + z * s, nz = -x * s + z * c; x = nx; z = nz;
            }
            return new V3(x + 0.5, y + 0.5, z + 0.5);
        }
        static V3 RotVariantN(V3 p, int rx, int ry)
        {
            V3 a = RotVariant(new V3(p.X + 0.5, p.Y + 0.5, p.Z + 0.5), rx, ry);
            return new V3(a.X - 0.5, a.Y - 0.5, a.Z - 0.5);
        }

        public static List<Quad> BuildQuads(string modelRef, int rx, int ry)
        {
            string ns, p; SplitRef(modelRef, "minecraft", out ns, out p);
            p = Norm(p);
            List<Quad> quads;
            if (p.EndsWith(".obj"))
            {
                if (ns != "almura") throw new Exception("OBJ model outside the almura namespace (" + modelRef + ")");
                ObjModel m = GetObj(ns, "models/block/" + p);
                quads = BuildObj(m);
            }
            else
            {
                RM rm = ResolveJson(ns, "block/" + p, 0);
                quads = BuildJson(rm);
            }
            if (rx != 0 || ry != 0)
                foreach (Quad q in quads)
                {
                    for (int k = 0; k < 4; k++) q.P[k] = RotVariant(q.P[k], rx, ry);
                    q.N = RotVariantN(q.N, rx, ry);
                }
            return quads;
        }

        static void AddFarmland(List<Quad> quads)
        {
            double y0 = -15.0 / 16.0, y1 = 0.0;
            // top (up) and four sides, same vertex tables as JSON faces
            double[] f = new double[] { 0, y0, 0 }, t = new double[] { 1, y1, 1 };
            for (int fi = 1; fi < 6; fi++)
            {
                Quad q = new Quad(); q.T = fi == 1 ? farmTop : farmSide;
                int[] sel = FaceVerts[fi];
                double[] u = new double[] { 0, 0, 1, 1 }, v = new double[] { 0, 1, 1, 0 };
                for (int k = 0; k < 4; k++)
                {
                    q.P[k] = new V3(sel[k * 3] == 0 ? f[0] : t[0], sel[k * 3 + 1] == 0 ? f[1] : t[1], sel[k * 3 + 2] == 0 ? f[2] : t[2]);
                    q.U[k] = u[k]; q.V[k] = v[k];
                }
                q.N = new V3(FaceNormals[fi][0], FaceNormals[fi][1], FaceNormals[fi][2]);
                quads.Add(q);
            }
        }

        // ---------------------------------------------------------------- blockstates
        static void Apply(Sel s, JV o)
        {
            if (o == null || o.T != 'o') return;
            string m = o.Str("model"); if (m != null) s.Model = m;
            if (o.Has("x")) s.X = ((int)Math.Round(o.Num("x", 0)) % 360 + 360) % 360;
            if (o.Has("y")) s.Y = ((int)Math.Round(o.Num("y", 0)) % 360 + 360) % 360;
            if (o.Has("uvlock")) s.UvLock = o.Bool("uvlock", false);
        }
        static JV FirstObj(JV v)
        {
            if (v == null) return null;
            if (v.T == 'a') return v.Arr.Count > 0 ? v.Arr[0] : null;
            return v;
        }
        static readonly string[] VariantKeys = new string[] { "model", "x", "y", "uvlock", "transform", "textures", "custom", "submodel", "weight" };
        static bool LooksLikeVariant(JV v)
        {
            if (v.T == 'a') return true;
            if (v.T != 'o') return false;
            if (v.Keys.Count == 0) return true;
            foreach (string k in v.Keys) if (Array.IndexOf(VariantKeys, k) >= 0) return true;
            return false;
        }
        static JV LoadBlockstate(string id)
        {
            string ns, p; SplitRef(id, "almura", out ns, out p);
            string f = Find(ns, "blockstates/" + p + ".json");
            if (f == null) throw new Exception("blockstate not found: " + ns + ":blockstates/" + p + ".json");
            return JP.Parse(File.ReadAllText(f, Encoding.UTF8));
        }

        // candidates: label -> variant object, in file order (property maps flattened as prop=value)
        static List<KeyValuePair<string, JV>> Candidates(JV vars)
        {
            List<KeyValuePair<string, JV>> c = new List<KeyValuePair<string, JV>>();
            if (vars == null || vars.T != 'o') return c;
            foreach (string k in vars.Keys)
            {
                JV v = vars.Map[k];
                if (LooksLikeVariant(v)) c.Add(new KeyValuePair<string, JV>(k, v));
                else if (v.T == 'o') foreach (string k2 in v.Keys) c.Add(new KeyValuePair<string, JV>(k + "=" + k2, v.Map[k2]));
            }
            return c;
        }

        public static Sel SelectInventory(JV bs)
        {
            Sel s = new Sel(); Apply(s, bs.Get("defaults"));
            JV vars = bs.Get("variants");
            if (vars != null && vars.T == 'o' && vars.Has("inventory"))
            {
                Apply(s, FirstObj(vars.Get("inventory")));
                if (s.Model == null) throw new Exception("inventory variant has no model");
                return s;
            }
            if (s.Model != null) return s;
            List<KeyValuePair<string, JV>> cand = Candidates(vars);
            if (cand.Count == 0) throw new Exception("blockstate has no variants and no defaults.model");
            // preference: facing=north, else lowest age, else first
            List<KeyValuePair<string, JV>> ordered = new List<KeyValuePair<string, JV>>();
            foreach (KeyValuePair<string, JV> kv in cand) if (kv.Key.Contains("facing=north")) ordered.Add(kv);
            List<KeyValuePair<string, JV>> ages = new List<KeyValuePair<string, JV>>();
            foreach (KeyValuePair<string, JV> kv in cand) if (kv.Key.StartsWith("age=")) ages.Add(kv);
            ages.Sort(delegate (KeyValuePair<string, JV> a, KeyValuePair<string, JV> b)
            { int x, y; int.TryParse(a.Key.Substring(4), out x); int.TryParse(b.Key.Substring(4), out y); return x.CompareTo(y); });
            ordered.AddRange(ages);
            ordered.AddRange(cand);
            Sel baseSel = s;
            foreach (KeyValuePair<string, JV> kv in ordered)
            {
                Sel t = new Sel(); t.Model = baseSel.Model; t.X = baseSel.X; t.Y = baseSel.Y; t.UvLock = baseSel.UvLock;
                Apply(t, FirstObj(kv.Value));
                if (t.Model != null) return t;
            }
            throw new Exception("no variant with a model");
        }

        public static Sel SelectAge(JV bs, int age)
        {
            Sel s = new Sel(); Apply(s, bs.Get("defaults"));
            JV vars = bs.Get("variants");
            if (vars != null) { JV a = vars.Get("age"); if (a != null) Apply(s, FirstObj(a.Get(age.ToString()))); }
            if (vars != null)
            {
                JV flat = vars.Get("age=" + age); if (flat != null) Apply(s, FirstObj(flat));
            }
            return s;
        }

        // ---------------------------------------------------------------- entry rendering
        static Rend rend = new Rend();
        public static uint[] RenderBlock(string id)
        {
            ctx = id;
            JV bs = LoadBlockstate(id);
            Sel s = SelectInventory(bs);
            if (s.UvLock && (s.X != 0 || s.Y != 0)) UvLockSeen++;
            List<Quad> quads = BuildQuads(s.Model, s.X, s.Y);
            return rend.Render(quads);
        }
        public static uint[] RenderStage(string id, int age, string stageModel)
        {
            ctx = id + " stage " + age;
            JV bs = LoadBlockstate(id);
            Sel s = SelectAge(bs, age);
            string model = stageModel != null && stageModel != "" ? stageModel : s.Model;
            if (model == null) throw new Exception("no stage model");
            if (s.UvLock && (s.X != 0 || s.Y != 0)) UvLockSeen++;
            List<Quad> quads = BuildQuads(model, s.X, s.Y);
            AddFarmland(quads);
            return rend.Render(quads);
        }

        // ---------------------------------------------------------------- driver
        static string CellKey(uint[] px)
        {
            byte[] b = new byte[px.Length * 4];
            Buffer.BlockCopy(px, 0, b, 0, b.Length);
            using (MD5 md5 = MD5.Create()) return Convert.ToBase64String(md5.ComputeHash(b));
        }
        static string Esc(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        public static string Full(string wikiJson, string outDir) { return Full(wikiJson, outDir, null); }
        // vanillaSpec: json file { "<key>": { "model": "minecraft:item/oak_planks" | null, "json": "<inline model>" | null, "tint": "RRGGBB" | null } }
        public static string Full(string wikiJson, string outDir, string vanillaSpec)
        {
            JV wiki = JP.Parse(File.ReadAllText(wikiJson, Encoding.UTF8));
            JV entries = wiki.Get("entries");
            List<uint[]> cells = new List<uint[]>();
            Dictionary<string, int> dedup = new Dictionary<string, int>();
            List<KeyValuePair<string, int>> blocks = new List<KeyValuePair<string, int>>();
            List<KeyValuePair<string, List<int>>> stages = new List<KeyValuePair<string, List<int>>>();
            int nBlocks = 0, nStages = 0, failBlocks = 0, failStages = 0, total = 0;
            HashSet<string> vanillaBlocks = new HashSet<string>();
            List<string> vanillaBlockList = new List<string>();
            Func<uint[], int> addCell = delegate (uint[] px)
            {
                string k = CellKey(px); int ix;
                if (dedup.TryGetValue(k, out ix)) return ix;
                ix = cells.Count; cells.Add(px); dedup[k] = ix; return ix;
            };
            System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
            foreach (JV e in entries.Arr)
            {
                if (e.Str("kind") != "block") continue;
                string id = e.Str("id");
                total++;
                try
                {
                    VanillaTexUsed = false;
                    uint[] px = RenderBlock(id);
                    if (VanillaTexUsed && vanillaBlocks.Add(id)) vanillaBlockList.Add(id);
                    blocks.Add(new KeyValuePair<string, int>(id, addCell(px))); nBlocks++;
                }
                catch (Exception ex) { failBlocks++; Failures.Add("FAIL block " + id + ": " + ex.Message); }
                JV st = e.Get("stages");
                if (st != null && st.T == 'a')
                {
                    List<int> idxs = new List<int>();
                    foreach (JV s in st.Arr)
                    {
                        int age = (int)s.Num("age", idxs.Count);
                        try
                        {
                            VanillaTexUsed = false;
                            uint[] px = RenderStage(id, age, s.Str("stageModel"));
                            if (VanillaTexUsed && vanillaBlocks.Add(id)) vanillaBlockList.Add(id);
                            idxs.Add(addCell(px)); nStages++;
                        }
                        catch (Exception ex) { idxs.Add(-1); failStages++; Failures.Add("FAIL stage " + id + " age " + age + " (" + s.Str("stageModel") + "): " + ex.Message); }
                    }
                    stages.Add(new KeyValuePair<string, List<int>>(id, idxs));
                }
                if (total % 100 == 0) Console.WriteLine("  " + total + " blocks done, " + sw.Elapsed.TotalSeconds.ToString("0.0") + "s");
            }
            // vanilla items shown as 3D blocks (models/item/<name>.json in the extracted jar, or an inline stand-in model)
            int nVan = 0, failVan = 0;
            if (vanillaSpec != null)
            {
                JV vs = JP.Parse(File.ReadAllText(vanillaSpec, Encoding.UTF8));
                StringBuilder vb = new StringBuilder("{");
                bool first = true;
                foreach (string key in vs.Keys)
                {
                    JV o = vs.Map[key];
                    ctx = "vanilla " + key;
                    try
                    {
                        RM rm; string js = o.Str("json"), mdl = o.Str("model"), tint = o.Str("tint");
                        if (js != null) rm = InlineModel(js);
                        else
                        {
                            string ns, p; SplitRef(mdl, "minecraft", out ns, out p);
                            rm = ResolveJson(ns, Norm(p), 0);
                        }
                        curTint = (tint != null && tint.Length == 6) ? Convert.ToInt32(tint, 16) : -1;
                        List<Quad> q;
                        try { q = BuildJson(rm); } finally { curTint = -1; }
                        uint[] px = rend.Render(q);
                        int ix = addCell(px);
                        if (!first) vb.Append(","); first = false;
                        vb.Append("\"" + Esc(key) + "\":" + ix); nVan++;
                    }
                    catch (Exception ex) { failVan++; Failures.Add("FAIL vanilla " + key + ": " + ex.Message); }
                }
                vb.Append("}");
                File.WriteAllText(Path.Combine(outDir, "vanilla-render-index.json"), vb.ToString(), new UTF8Encoding(false));
            }
            File.WriteAllLines(Path.Combine(outDir, "vanilla-blocks-rerendered.txt"), vanillaBlockList.ToArray(), new UTF8Encoding(false));
            // sprite sheet
            int cols = 32, rows = (cells.Count + cols - 1) / cols;
            using (Bitmap bmp = new Bitmap(cols * Rend.CELL, Math.Max(1, rows) * Rend.CELL, PixelFormat.Format32bppArgb))
            {
                BitmapData bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int[] all = new int[bmp.Width * bmp.Height];
                for (int c = 0; c < cells.Count; c++)
                {
                    int ox = (c % cols) * Rend.CELL, oy = (c / cols) * Rend.CELL;
                    uint[] px = cells[c];
                    for (int y = 0; y < Rend.CELL; y++)
                        for (int x = 0; x < Rend.CELL; x++) all[(oy + y) * bmp.Width + ox + x] = (int)px[y * Rend.CELL + x];
                }
                System.Runtime.InteropServices.Marshal.Copy(all, 0, bd.Scan0, all.Length);
                bmp.UnlockBits(bd);
                bmp.Save(Path.Combine(outDir, "renders.png"), ImageFormat.Png);
            }
            StringBuilder sb = new StringBuilder();
            sb.Append("{\"blocks\":{");
            for (int i = 0; i < blocks.Count; i++) { if (i > 0) sb.Append(","); sb.Append("\"" + Esc(blocks[i].Key) + "\":" + blocks[i].Value); }
            sb.Append("},\"stages\":{");
            for (int i = 0; i < stages.Count; i++)
            {
                if (i > 0) sb.Append(",");
                sb.Append("\"" + Esc(stages[i].Key) + "\":[" + string.Join(",", stages[i].Value.ConvertAll<string>(delegate (int v) { return v.ToString(); }).ToArray()) + "]");
            }
            sb.Append("}}");
            File.WriteAllText(Path.Combine(outDir, "renders-index.json"), sb.ToString(), new UTF8Encoding(false));
            List<string> log = new List<string>();
            log.AddRange(Failures); log.AddRange(Warns);
            File.WriteAllLines(Path.Combine(outDir, "render-failures.txt"), log.ToArray(), new UTF8Encoding(false));
            return "vanilla items rendered " + nVan + " (failed " + failVan + "), almura blocks using vanilla textures " + vanillaBlockList.Count + "; blocks rendered " + nBlocks + "/" + total + " (failed " + failBlocks + "), stages rendered " + nStages + " (failed " + failStages + "), unique cells " + cells.Count + ", sheet rows " + rows + ", warnings " + Warns.Count + ", uvlock-rotated " + UvLockSeen + ", " + sw.Elapsed.TotalSeconds.ToString("0.0") + "s";
        }

        // contact sheet: specs "b|<id>" or "s|<id>|<age>[|<stageModel>]"
        public static string Contact(string[] specs, string outPng, int zoom)
        {
            int cols = Math.Min(specs.Length, 6), rows = (specs.Length + cols - 1) / cols;
            int cw = Rend.CELL * zoom, ch = Rend.CELL * zoom + 16;
            using (Bitmap bmp = new Bitmap(cols * cw, rows * ch, PixelFormat.Format32bppArgb))
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font font = new Font("Arial", 8))
            {
                g.Clear(Color.FromArgb(70, 70, 76));
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                for (int i = 0; i < specs.Length; i++)
                {
                    string[] p = specs[i].Split('|');
                    int ox = (i % cols) * cw, oy = (i / cols) * ch;
                    g.FillRectangle(Brushes.DimGray, ox + 1, oy + 1, cw - 2, Rend.CELL * zoom - 2);
                    string label = p[1];
                    try
                    {
                        uint[] px = p[0] == "b" ? RenderBlock(p[1]) : RenderStage(p[1], int.Parse(p[2]), p.Length > 3 ? p[3] : null);
                        using (Bitmap cell = new Bitmap(Rend.CELL, Rend.CELL, PixelFormat.Format32bppArgb))
                        {
                            BitmapData bd = cell.LockBits(new Rectangle(0, 0, Rend.CELL, Rend.CELL), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                            int[] arr = new int[px.Length]; for (int k = 0; k < px.Length; k++) arr[k] = (int)px[k];
                            System.Runtime.InteropServices.Marshal.Copy(arr, 0, bd.Scan0, arr.Length);
                            cell.UnlockBits(bd);
                            g.DrawImage(cell, new Rectangle(ox, oy, Rend.CELL * zoom, Rend.CELL * zoom), 0, 0, Rend.CELL, Rend.CELL, GraphicsUnit.Pixel);
                        }
                    }
                    catch (Exception ex) { label = "FAIL " + ex.Message; }
                    if (p[0] == "s") label = "st" + p[2] + " " + label;
                    g.DrawString(label.Length > 40 ? label.Substring(label.Length - 40) : label, font, Brushes.White, ox + 2, oy + Rend.CELL * zoom);
                }
                bmp.Save(outPng, ImageFormat.Png);
            }
            List<string> log = new List<string>(); log.AddRange(Failures); log.AddRange(Warns);
            return string.Join("\n", log.ToArray());
        }

        // OBJ parse census (parity check against loader-spec: 23 of 1050 fail)
        public static string ObjCensus()
        {
            int ok = 0, bad = 0; List<string> msgs = new List<string>();
            string dir = Path.Combine(Roots[0], "almura", "models");
            foreach (string f in Directory.GetFiles(dir, "*.obj", SearchOption.AllDirectories))
            {
                string rel = f.Substring(dir.Length + 1).Replace('\\', '/').ToLowerInvariant();
                try { ParseObj(f, "models/" + rel); ok++; }
                catch (Exception e) { bad++; msgs.Add(rel + " :: " + e.Message); }
            }
            return "obj ok " + ok + " fail " + bad + "\n" + string.Join("\n", msgs.ToArray());
        }
    }
}
