param(
  [ValidateSet('full','contact','census')][string]$Mode = 'full',
  [string[]]$Specs = @(),
  [string]$OutPng = '',
  [int]$Zoom = 2
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition ([IO.File]::ReadAllText("$here\AlmuraRender.cs")) -Language CSharp
$wiki = Join-Path $here '..\wiki\wiki-data-uv.json'
$vanillaAssets = [IO.Path]::GetFullPath((Join-Path $here '..\vanilla\jar\assets'))     # extracted vanilla 1.12.2 client assets
$vanillaSpec   = [IO.Path]::GetFullPath((Join-Path $here '..\vanilla\vanilla-render.json'))   # written by wiki\build.ps1
[AlmuraRender.Program]::AddRoot($env:WIKI_PACK_ROOT)
if ($env:WIKI_MOD_ASSETS -and (Test-Path -LiteralPath $env:WIKI_MOD_ASSETS)) { [AlmuraRender.Program]::AddRoot($env:WIKI_MOD_ASSETS) }
[AlmuraRender.Program]::AddRoot($vanillaAssets)
switch ($Mode) {
  'census'  { [AlmuraRender.Program]::ObjCensus() }
  'contact' { $Specs = @($Specs | % { $_ -split ',,' } | ? { $_ }); $log = [AlmuraRender.Program]::Contact($Specs, $OutPng, $Zoom); if ($log) { $log } }
  'full'    { $vs = $null; if (Test-Path -LiteralPath $vanillaSpec) { $vs = $vanillaSpec }; [AlmuraRender.Program]::Full($wiki, $here, $vs) }
}
