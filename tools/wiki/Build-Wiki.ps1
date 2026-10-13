<#
.SYNOPSIS
  Regenerates the Almura 3.0 wiki page from the content pack.
.DESCRIPTION
  Reads 3.0\fs_2\assets\almura, builds the data, icon atlas and 3D renders, and writes a
  ready-to-host site into tools\wiki\dist (almura-wiki.html, wiki-data.json, icons.png,
  renders.png, renders-index.json). Needs Windows PowerShell 5.1 only; no Python or Node.
  The first run extracts vanilla 1.12.2 art from the client jar into tools\wiki\vanilla\jar
  (git-ignored); the jar is found in the ForgeGradle cache or via -MinecraftJar.
.EXAMPLE
  .\tools\wiki\Build-Wiki.ps1
  .\tools\wiki\Build-Wiki.ps1 -Serve        # also opens http://localhost:8080/ to preview
#>
param(
  [string]$PackRoot     = '',   # folder holding the 'almura' dir; default <repo>\3.0\fs_2\assets
  [string]$ModAssets    = '',   # optional Almura mod assets dir; default <repo>\..\Almura\src\main\resources\assets
  [string]$MinecraftJar = '',   # 1.12.2 client jar; default: ForgeGradle cache
  [string]$OutDir       = '',   # default tools\wiki\dist
  [switch]$Serve
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = [IO.Path]::GetFullPath((Join-Path $here '..\..'))
if (-not $PackRoot)  { $PackRoot  = Join-Path $repo '3.0\fs_2\assets' }
if (-not $ModAssets) { $ModAssets = Join-Path $repo '..\Almura\src\main\resources\assets' }
if (-not $OutDir)    { $OutDir    = Join-Path $here 'dist' }
$PackRoot = [IO.Path]::GetFullPath($PackRoot)
if (-not (Test-Path -LiteralPath (Join-Path $PackRoot 'almura'))) { throw "Pack not found: $PackRoot\almura (use -PackRoot)" }
if (Test-Path -LiteralPath $ModAssets) { $ModAssets = [IO.Path]::GetFullPath($ModAssets) } else { Write-Warning "Almura mod assets not found at $ModAssets; building without them (use -ModAssets)."; $ModAssets = '' }
$env:WIKI_PACK_ROOT = $PackRoot
$env:WIKI_MOD_ASSETS = $ModAssets

# ---- 1. vanilla 1.12.2 assets (one-time extract)
$vAssets = Join-Path $here 'vanilla\jar\assets'
if (-not (Test-Path -LiteralPath (Join-Path $vAssets 'minecraft\lang\en_us.lang'))) {
  if (-not $MinecraftJar) {
    $MinecraftJar = Join-Path $env:USERPROFILE '.gradle\caches\minecraft\net\minecraft\minecraft\1.12.2\minecraft-1.12.2.jar'
    if (-not (Test-Path -LiteralPath $MinecraftJar)) {
      $hit = Get-ChildItem (Join-Path $env:APPDATA '.minecraft\versions\1.12.2') -Filter '1.12.2.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { $MinecraftJar = $hit.FullName }
    }
  }
  if (-not (Test-Path -LiteralPath $MinecraftJar)) { throw "Minecraft 1.12.2 client jar not found. Pass -MinecraftJar <path>." }
  Write-Host "Extracting vanilla assets from $MinecraftJar"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($MinecraftJar)
  try {
    foreach ($e in $zip.Entries) {
      if ($e.FullName -notlike 'assets/minecraft/*' -or $e.FullName.EndsWith('/')) { continue }
      $dest = Join-Path (Join-Path $here 'vanilla\jar') ($e.FullName -replace '/', '\')
      [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
    }
  } finally { $zip.Dispose() }
}

function Run([string]$label, [string]$script, [string[]]$more) {
  Write-Host "`n== $label"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @more
  if ($LASTEXITCODE -ne 0) { throw "$label failed (exit $LASTEXITCODE)" }
}

# ---- 2. data + icons; 3D renders; data again (picks up the vanilla render index)
Run 'Data and icons (pass 1)' (Join-Path $here 'wiki\build.ps1')   @('-AtlasMode', 'uv', '-OutSuffix', '-uv')
Run '3D renders'              (Join-Path $here 'render\render.ps1') @()
Run 'Data and icons (pass 2)' (Join-Path $here 'wiki\build.ps1')   @('-AtlasMode', 'uv', '-OutSuffix', '-uv')

# ---- 4. assemble the site
[void][IO.Directory]::CreateDirectory($OutDir)
Copy-Item (Join-Path $here 'wiki\almura-wiki.html')    $OutDir -Force
Copy-Item (Join-Path $here 'wiki\wiki-data-uv.json')   (Join-Path $OutDir 'wiki-data.json') -Force
Copy-Item (Join-Path $here 'wiki\icons-uv.png')        (Join-Path $OutDir 'icons.png') -Force
Copy-Item (Join-Path $here 'render\renders.png')       $OutDir -Force
Copy-Item (Join-Path $here 'render\renders-index.json') $OutDir -Force
Copy-Item (Join-Path $OutDir 'almura-wiki.html') (Join-Path $OutDir 'index.html') -Force
Write-Host "`nDone. Site written to $OutDir"
Get-ChildItem $OutDir | Select-Object Name, @{n='KB';e={[int]($_.Length/1KB)}} | Format-Table -AutoSize
Write-Host "Notes (problems found while reading the pack): tools\wiki\wiki\failures.txt, icon-missing.txt, recipe-unmatched.txt"

if ($Serve) {
  $l = New-Object Net.HttpListener; $l.Prefixes.Add('http://localhost:8080/'); $l.Start()
  Write-Host 'Serving http://localhost:8080/  (Ctrl+C to stop)'; Start-Process 'http://localhost:8080/'
  $types = @{ '.html'='text/html'; '.json'='application/json'; '.png'='image/png' }
  try { while ($true) {
    $c = $l.GetContext(); $p = $c.Request.Url.LocalPath.TrimStart('/'); if (-not $p) { $p = 'index.html' }
    $f = Join-Path $OutDir ($p -replace '/', '\')
    if ((Test-Path -LiteralPath $f -PathType Leaf) -and ($f.StartsWith($OutDir))) {
      $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = $types[[IO.Path]::GetExtension($f)]
      $c.Response.OutputStream.Write($b, 0, $b.Length)
    } else { $c.Response.StatusCode = 404 }
    $c.Response.Close()
  } } finally { $l.Stop() }
}
