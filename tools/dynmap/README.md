# Almura blocks on Dynmap

Dynmap can't read Almura's content loader blocks by itself. `DynmapGen` turns the content (blockstates, JSON and OBJ models,
textures) into the render data Dynmap 3.2.1 understands, and `update-dynmap.cmd` builds it, runs it and installs the result.

## When to run it

After adding or changing any block, block model or block texture in the content loader:

```
update-dynmap.cmd                       (dev server: C:\spongesrv\dynmap)
update-dynmap.cmd <path to a dynmap folder>
```

Then restart the server (Dynmap only reads this at startup) and re-render: `/dynmap radiusrender 100` to check an area,
`/dynmap fullrender <world>` for everything. Check the log for `almura[...] models enabled` / `textures enabled` and no
`Invalid ...` or `Format error` lines after them.

## What it produces (all generated, never edit by hand)

| File | Goes to | What it is |
| --- | --- | --- |
| `almura-models.txt` | `dynmap/renderdata/` | Shapes: crossed planes for crops/flowers/saplings, faces of OBJ and JSON models, stairs |
| `almura-texture.txt` | `dynmap/renderdata/` | Which texture each face of each block (per metadata value) shows |
| `pack/` | `dynmap/texturepacks/almura/` | The textures those files point at, including the parts of shared texture sheets cut out as their own images |

## One-time server settings it relies on

- `dynmap/custom-shaders.txt` points the textured shaders at the generated pack:

  ```
  shaders:
      - class: org.dynmap.hdmap.TexturePackHDShader
        name: stdtexture
        texturepack: almura
      - class: org.dynmap.hdmap.TexturePackHDShader
        name: default
        texturepack: almura
  ```
- `dynmap/shaders.txt` must not list `ChunkVersionHDShader` / `ChunkStatusHDShader` (written by Dynmap 3.6; 3.2.1 can't load them).

## Why it works this way (Dynmap 3.2.1, Minecraft 1.12)

- Blocks are matched by **metadata** (`data=`), not block state names. `state=` and `modellist:` lines (Dynmap 3.3+, and what the
  2023 DynmapBlockScan files used) are ignored by 3.2.1, which is why Almura blocks never rendered before.
- The metadata per block genre must match each Almura block class's `getMetaFromState`: horizontal/container facing S0 W1 N2 E3,
  crop age (+8 while a paddy crop holds water), log Y0 X1 Z2 none4, slab bottom0 top1, everything else one model for all values.
  If one of those classes changes its metadata, update `block()` in `DynmapGen.java`.
- A patch (flat surface) always shows a whole image and its corners must stay within -1..2 blocks, so every texture region a face uses
  is written out as its own image. Plain cubes become block lines with per-face textures; stairs use Dynmap's stair renderer.
- Parts of crops taller than two blocks (hop, top of corn) can't be expressed and are skipped; the generator prints a count.
