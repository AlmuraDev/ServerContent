# Faithful offline port of com.almuradev.content.model.obj.OBJModelParser (+ ResourceLocations helpers).
# Dot-source this file. $script:AssetRoot must point at .../assets/<ns>-parent (the folder that contains the 'almura' dir).
$script:ModelsRoot = $null
function RL-Lower([string]$s) { return $s.ToLowerInvariant() }   # ResourceLocation lower-cases namespace and path

# ResourceLocations.buildResourceLocationPath(string, parent)
# returns @{ ns=; path= } or throws like requireNamespace (IllegalArgumentException)
function Build-RLPath([string]$str, [string]$parent) {
  $i = $str.IndexOf(':')
  if ($i -lt 0) { throw "IllegalArgumentException: Expected a namespaced string ('$str')" }
  $ns = $str.Substring(0, $i); $val = $str.Substring($i + 1)
  if ($val.IndexOf('/') -eq -1 -and $null -ne $parent) { $val = $parent + '/' + $val }
  return @{ ns = (RL-Lower $ns); path = (RL-Lower $val) }
}

# model location -> filesystem path under <root>\<ns>\models\block\...  (blockstate "model" string)
# returns hashtable: ext ('obj'|'json'), rl (e.g. models/block/x/y.obj), file (existing path or $null)
function Locate-BlockModel([string]$root, [string]$model) {
  $m = $model
  $ns = 'minecraft'; $p = $m
  $i = $m.IndexOf(':'); if ($i -ge 0) { $ns = $m.Substring(0, $i); $p = $m.Substring($i + 1) }
  if ($ns -eq '') { $ns = 'minecraft' }
  $ns = RL-Lower $ns; $p = RL-Lower $p
  $isObj = $p.EndsWith('.obj')
  $rl = if ($isObj) { "models/block/$p" } else { "models/block/$p.json" }
  $rel = ($rl -replace '//+', '/')           # Path.resolve collapses duplicate slashes
  $file = Join-Path (Join-Path $root $ns) ($rel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $file)) { $file = $null }
  return @{ ns = $ns; isObj = $isObj; rl = $rl; file = $file }
}

# Parse a .mtl exactly like parseMaterialLibrary. $objRL = "models/block/dir/x.obj" (source location path)
function Parse-Mtl([string]$mtlFile, [string]$objRL) {
  $mats = [ordered]@{}; $cur = $null; $curTex = $null; $lastSlash = $objRL.LastIndexOf('/')
  $parentDirs = if ($lastSlash -ge 0) { $objRL.Substring(0, $lastSlash) } else { $null }   # getParent(source).path
  $parentName = $null; if ($parentDirs) { $ls = $parentDirs.LastIndexOf('/'); if ($ls -ne -1) { $parentName = $parentDirs.Substring($ls + 1) } }
  foreach ($line in [IO.File]::ReadAllLines($mtlFile)) {
    if ($line.StartsWith('#') -or $line.Length -eq 0) { continue }
    $parts = $line -split ' '           # Java String.split(" ") drops trailing empties
    while ($parts.Count -gt 1 -and $parts[-1] -eq '') { $parts = $parts[0..($parts.Count - 2)] }
    $hdr = $parts[0]; $args_ = @(); if ($parts.Count -gt 1) { $args_ = $parts[1..($parts.Count - 1)] }
    switch -CaseSensitive ($hdr) {
      'newmtl' { if ($null -ne $cur) { $mats[$cur] = $curTex }; $cur = $args_[0]; $curTex = $null }
      'map_Kd' {
        if ($null -eq $cur) { throw 'MalformedMaterialLibraryException: map_Kd before newmtl' }
        $curTex = Build-RLPath $args_[0] $parentName
      }
      default { }
    }
  }
  if ($null -ne $cur) { $mats[$cur] = $curTex }
  if ($mats.Count -eq 0) { throw 'IllegalStateException: material library needs at least one material' }
  return $mats
}

function Strip-Png($rl) {   # OBJModel/OBJBakedModel: path.endsWith(".png") -> path.split("\\.")[0]
  $p = $rl.path
  if ($p.EndsWith('.png')) { $p = $p.Split('.')[0] }
  return @{ ns = $rl.ns; path = $p }
}

# Parse an .obj. Returns @{ ok; error; groups = list of @{name; mat; tex(@{ns;path}|$null); faces=list of @{v=@(@{x;y;z;u;v;hasUV;nx;ny;nz})}}}
function Parse-Obj([string]$root, [string]$objFile, [string]$objRL, [string]$ns) {
  $res = @{ ok = $false; error = $null; groups = @(); mtllib = $null }
  try {
    $lines = [IO.File]::ReadAllLines($objFile)
    $V = New-Object System.Collections.ArrayList; $VT = New-Object System.Collections.ArrayList; $VN = New-Object System.Collections.ArrayList
    $mats = $null; $groups = New-Object System.Collections.ArrayList
    $gb = $null; $gname = $null
    $ls = $objRL.LastIndexOf('/'); $parentPath = $objRL.Substring(0, $ls)      # getParent(source).getPath()
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line.StartsWith('#') -or $line.Length -eq 0) { continue }
      $idx = $line.IndexOf(' ')
      if ($idx -lt 0) { throw "StringIndexOutOfBounds at line $($i + 1): '$line'" }     # substring(0,-1)
      $hdr = $line.Substring(0, $idx)
      $rest = $line.Substring($idx).Trim() -split ' '
      switch -CaseSensitive ($hdr) {
        'mtllib' {
          $r = Build-RLPath $rest[0] $parentPath
          $res.mtllib = $r
          $mf = Join-Path (Join-Path $root $r.ns) ($r.path -replace '/', '\')
          if (-not (Test-Path -LiteralPath $mf)) { throw "mtl not found: $($r.ns):$($r.path)" }
          $mats = Parse-Mtl $mf $objRL
        }
        'v'  { $V.Add(@([single]$rest[0], [single]$rest[1], [single]$rest[2])) | Out-Null }
        'vn' { $VN.Add(@([single]$rest[0], [single]$rest[1], [single]$rest[2])) | Out-Null }
        'vt' { $u = [math]::Max(0, [math]::Min(1, [single]$rest[0])); $vv = [math]::Max(0, [math]::Min(1, [single]$rest[1])); $VT.Add(@($u, $vv)) | Out-Null }
        'g'  { if ($null -ne $gb) { if ($gb.faces.Count -eq 0) { throw 'Faces cannot be empty' }; $groups.Add($gb) | Out-Null }
               $gb = @{ name = $rest[0]; mat = $null; faces = New-Object System.Collections.ArrayList } }
        'usemtl' {
          if ($null -eq $gb) { $gb = @{ name = 'default'; mat = $null; faces = New-Object System.Collections.ArrayList } }
          if ($null -eq $mats) { throw 'usemtl but no material library' }
          if (-not $mats.Contains($rest[0])) { throw "material '$($rest[0])' not in library" }
          $gb.mat = $rest[0]
        }
        'f' {
          if ($null -eq $gb) { $gb = @{ name = 'default'; mat = $null; faces = New-Object System.Collections.ArrayList } }
          $face = @()
          foreach ($seg in $rest) {
            $ix = $seg -split '/'
            $vi = [int]$ix[0]; if ($vi -lt 1 -or $vi -gt $V.Count) { throw "bad vertex index $vi (line $($i + 1))" }
            $pt = @{ x = $V[$vi - 1][0]; y = $V[$vi - 1][1]; z = $V[$vi - 1][2]; hasUV = $false; u = 0; v = 0; hasN = $false }
            $ti = -1; $ni = -1
            if ($ix.Count -gt 1) { if ($ix.Count -eq 3 -and $ix[1] -eq '') { $ni = [int]$ix[2] } else { $ti = [int]$ix[1]; if ($ix.Count -gt 2) { $ni = [int]$ix[2] } } }
            if ($ti -ne -1) { if ($ti -lt 1 -or $ti -gt $VT.Count) { throw "bad vt index $ti (line $($i + 1))" }; $pt.hasUV = $true; $pt.u = $VT[$ti - 1][0]; $pt.v = $VT[$ti - 1][1] }
            if ($ni -ne -1) { if ($ni -lt 1 -or $ni -gt $VN.Count) { throw "bad vn index $ni (line $($i + 1))" }; $pt.hasN = $true; $pt.nx = $VN[$ni - 1][0]; $pt.ny = $VN[$ni - 1][1]; $pt.nz = $VN[$ni - 1][2] }
            $face += , $pt
          }
          $gb.faces.Add($face) | Out-Null
        }
        default { }
      }
    }
    if ($null -ne $gb) { if ($gb.faces.Count -eq 0) { throw 'Faces cannot be empty' }; $groups.Add($gb) | Out-Null }
    if ($groups.Count -eq 0) { throw 'Groups cannot be empty' }
    if ($null -eq $mats) { throw 'NullPointerException: no mtllib (OBJModel ctor dereferences the material library)' }
    foreach ($g in $groups) { $g.tex = $null; if ($g.mat) { $g.tex = $mats[$g.mat] } }
    $res.groups = @($groups); $res.ok = $true
  } catch { $res.error = $_.Exception.Message }
  return $res
}

function Quad-Area($face) {   # area of a polygon (fan), model units
  $a = 0.0
  for ($k = 1; $k -lt $face.Count - 1; $k++) {
    $p0 = $face[0]; $p1 = $face[$k]; $p2 = $face[$k + 1]
    $ux = $p1.x - $p0.x; $uy = $p1.y - $p0.y; $uz = $p1.z - $p0.z
    $wx = $p2.x - $p0.x; $wy = $p2.y - $p0.y; $wz = $p2.z - $p0.z
    $cx = $uy * $wz - $uz * $wy; $cy = $uz * $wx - $ux * $wz; $cz = $ux * $wy - $uy * $wx
    $a += 0.5 * [math]::Sqrt($cx * $cx + $cy * $cy + $cz * $cz)
  }
  return $a
}
