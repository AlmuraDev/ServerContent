# Almura 3.0 wiki generator

Regenerates the player wiki from the content pack. Run it after content changes:

    powershell -File tools\wiki\Build-Wiki.ps1            # writes tools\wiki\dist
    powershell -File tools\wiki\Build-Wiki.ps1 -Serve     # also previews on http://localhost:8080/

Takes about two minutes. Needs only Windows PowerShell 5.1.

- Output: `dist\` holds `index.html`, `wiki-data.json`, `icons.png`, `renders.png`, `renders-index.json`. Host the folder anywhere static.
- First run extracts vanilla 1.12.2 art from the ForgeGradle client jar (override with `-MinecraftJar`), or downloads the jar from Mojang and checks its sha1 when there's none. It is cached in `vanilla\jar` and git-ignored.
- Published automatically: `.github/workflows/wiki.yml` rebuilds the site on GitHub Actions for every content or generator push to `master` and publishes it on GitHub Pages (https://almuradev.github.io/ServerContent/). Pushes to `wiki-generator` only build it; the pack problem reports are kept as the run's `wiki-reports` artifact.
- Pack problems it notices go to `wiki\failures.txt`, `icon-missing.txt` and `recipe-unmatched.txt`.
- Optional: `-PackRoot`, `-ModAssets` (the Almura mod's `src\main\resources\assets`, found at `..\Almura` by default), `-OutDir`.
- Layout: `wiki\` data/icon extractor and page template, `render\` 3D block renderer (C#), `loader\` OBJ/MTL reader, `vanilla\` vanilla lookups.
