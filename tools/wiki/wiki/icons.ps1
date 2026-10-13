# Icon resolution that mimics the Almura content loader (see ..\loader\loader-spec.md).
# Dot-sourced by build.ps1 after lib.ps1 and ..\loader\objlib.ps1.
#   $IR_ROOT  = ...\fs_2\assets   (folder that contains the 'almura' namespace dir)
#   $AtlasMode = 'whole' (show the whole texture, contain-fit) | 'uv' (crop atlases to the UV box of the chosen faces)
#   $SproutMode = 'plant' (shared sprout_N.obj stages use the crop's plant texture) | 'game' (what the mtl really draws: dirt)

$script:IR_ROOT    = $env:WIKI_PACK_ROOT
$script:VANILLA_ASSETS = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\vanilla\jar\assets'))     # extracted vanilla 1.12.2 client assets (minecraft namespace)
$script:IR_ROOTS   = @($env:WIKI_PACK_ROOT, $env:WIKI_MOD_ASSETS, $script:VANILLA_ASSETS)
function Find-Asset([string]$ns, [string]$rel) {   # first resource pack/root that has <ns>/<rel>; later roots only fill gaps
  foreach ($r in $script:IR_ROOTS) { $f = Join-Path (Join-Path $r $ns) $rel; if (Test-Path -LiteralPath $f) { return $f } }
  return $null
}
$script:jsonCache  = @{}
$script:objCache   = @{}
$script:texInfo    = @{}
$script:icoNotes   = New-Object System.Collections.ArrayList     # human-readable problems found while resolving
$script:icoCounters = @{}
function Ico-Count([string]$k) { $script:icoCounters[$k] = 1 + [int]$script:icoCounters[$k] }
function Ico-Note([string]$id, [string]$msg) { [void]$script:icoNotes.Add("$id :: $msg") }

# approximate colours of vanilla 1.12 textures that the pack references by bare 'blocks/<name>' (vanilla jar is not available offline)
$script:VanillaColors = @{
  'blocks/dirt' = '866043'; 'blocks/gravel' = '837F7E'; 'blocks/ice_packed' = '8DB4F2'
  'blocks/prismarine_bricks' = '63AB99'; 'blocks/stonebrick_cracked' = '767676'; 'blocks/stonebrick_mossy' = '6C7A60'
}

# ---------------------------------------------------------------- textures
function Tex-Lookup([string]$ns, [string]$path) {
  # ResourceLocation lower-cases; TextureMap builds "textures/<path>.png"; Path.resolve collapses '//' (so a leading '/' is harmless)
  $ns = $ns.ToLowerInvariant(); $p = ($path.ToLowerInvariant() -replace '//+', '/').TrimStart('/')
  $key = "$ns|$p"
  if ($script:texInfo.ContainsKey($key)) { return $script:texInfo[$key] }
  $r = @{ ns = $ns; path = $p; file = $null; vanilla = $null; missing = $false; w = 0; h = 0; strip = $false }
  if ($ns -eq 'minecraft') {
    $r.vanilla = $p
    $f = Join-Path $script:VANILLA_ASSETS ('minecraft\textures\' + ($p -replace '/', '\') + '.png')
    if (Test-Path -LiteralPath $f) {
      $r.file = $f
      try { $fs = [IO.File]::OpenRead($f); $im = [Drawing.Image]::FromStream($fs, $false, $false); $r.w = $im.Width; $r.h = $im.Height; $im.Dispose(); $fs.Dispose() } catch { $r.file = $null }
    }
  }
  elseif ($ns -ne 'almura') { $r.missing = $true }
  else {
    $f = Find-Asset 'almura' ('textures\' + ($p -replace '/', '\') + '.png')
    if ($f) {
      $r.file = $f
      try {
        $fs = [IO.File]::OpenRead($f); $im = [Drawing.Image]::FromStream($fs, $false, $false); $r.w = $im.Width; $r.h = $im.Height; $im.Dispose(); $fs.Dispose()
      } catch { $r.file = $null; $r.missing = $true }
    } else { $r.missing = $true }
  }
  $script:texInfo[$key] = $r
  return $r
}
function Tex-From-Ref([string]$ref) {   # JSON model texture value: "ns:path" or "path" (-> minecraft)
  $ns = 'minecraft'; $p = $ref; $i = $ref.IndexOf(':')
  if ($i -ge 0) { $ns = $ref.Substring(0, $i); $p = $ref.Substring($i + 1) }
  if ($ns -eq '') { $ns = 'minecraft' }
  return (Tex-Lookup $ns $p)
}

# ---------------------------------------------------------------- JSON models (vanilla ModelBlock rules)
function Load-ModelJson([string]$ns, [string]$path) {     # path relative to models/, no extension
  $ns = $ns.ToLowerInvariant(); $p = ($path.ToLowerInvariant() -replace '//+', '/').TrimStart('/')
  $key = "$ns|$p"
  if ($script:jsonCache.ContainsKey($key)) { return $script:jsonCache[$key] }
  $f = Find-Asset $ns ('models\' + ($p -replace '/', '\') + '.json')
  $m = $null
  if ($f) { $m = Read-Json $f }
  $script:jsonCache[$key] = $m
  return $m
}
# builtin (vanilla 1.12) parents we cannot read offline -> which texture variable is the "up" face
$script:BuiltinUp = @{
  'block/cube_all' = 'all'; 'block/cube_column' = 'end'; 'block/half_slab' = 'top'; 'block/upper_slab' = 'top'
  'block/stairs' = 'top'; 'block/inner_stairs' = 'top'; 'block/outer_stairs' = 'top'
  'block/stone_stairs' = 'top'; 'block/stone_inner_stairs' = 'top'; 'block/stone_outer_stairs' = 'top'
}
function Resolve-ModelChain([string]$ns, [string]$path, [int]$depth = 0) {
  # returns @{ found; textures(merged, child wins); elements; builtin (vanilla parent path or $null); missingParent }
  $res = @{ found = $false; textures = @{}; elements = $null; builtin = $null; missingParent = $null }
  if ($depth -gt 12) { return $res }
  $m = Load-ModelJson $ns $path
  if ($null -eq $m) { $res.missingParent = "$ns`:$path"; return $res }
  $res.found = $true
  $parentRes = $null
  if ($m['parent']) {
    $par = [string]$m['parent']; $pns = 'minecraft'; $pp = $par; $i = $par.IndexOf(':')
    if ($i -ge 0) { $pns = $par.Substring(0, $i); $pp = $par.Substring($i + 1) }
    if ($pns -eq 'minecraft' -and ($null -ne (Load-ModelJson 'minecraft' $pp))) {      # real vanilla JSON from the extracted jar
      $parentRes = Resolve-ModelChain 'minecraft' $pp ($depth + 1)
    } elseif ($pns -eq 'minecraft') {
      $pp = $pp.ToLowerInvariant()
      if ($pp -eq 'builtin/entity') { $res.builtin = 'builtin/entity' }
      elseif ($pp -eq 'item/generated' -or $pp -eq 'builtin/generated') { $res.builtin = 'item/generated' }
      elseif ($script:BuiltinUp.ContainsKey($pp)) { $res.builtin = $pp }
      else { $res.builtin = $pp; $res.missingParent = "minecraft:$pp (unknown vanilla model)" }
    } else {
      $parentRes = Resolve-ModelChain $pns $pp ($depth + 1)
      if (-not $parentRes.found) { $res.missingParent = $parentRes.missingParent }
    }
  }
  if ($parentRes) {
    foreach ($k in $parentRes.textures.Keys) { $res.textures[$k] = $parentRes.textures[$k] }
    $res.elements = $parentRes.elements; if ($parentRes.builtin) { $res.builtin = $parentRes.builtin }
    if ($parentRes.missingParent -and -not $res.missingParent) { $res.missingParent = $parentRes.missingParent }
  }
  if ($m['textures'] -is [System.Collections.IDictionary]) { foreach ($k in $m['textures'].Keys) { $res.textures[$k] = [string]$m['textures'][$k] } }
  if ($m['elements']) { $res.elements = $m['elements'] }
  return $res
}
function Resolve-TexVar($chain, [string]$v, [int]$depth = 0) {   # '#name' chains -> final ref string or $null
  while ($v -and $v.StartsWith('#') -and $depth -lt 10) { $k = $v.Substring(1); if ($chain.textures.ContainsKey($k)) { $v = $chain.textures[$k] } else { return $null }; $depth++ }
  if ($v -and $v.StartsWith('#')) { return $null }
  return $v
}

# Layers for an item model (item/generated): layer0, layer1, ...
function Item-Layers($chain) {
  $out = @()
  for ($i = 0; $i -lt 5; $i++) {
    $k = "layer$i"
    if (-not $chain.textures.ContainsKey($k)) { break }
    $r = Resolve-TexVar $chain $chain.textures[$k]
    if ($r) { $out += , @{ tex = (Tex-From-Ref $r); uv = $null } }
  }
  return $out
}
# One texture for a block-style JSON model (inventory/gui): up-facing texture, else the texture with the largest face area, else known keys
function Block-JsonTexture($chain) {
  if ($chain.builtin -and $script:BuiltinUp.ContainsKey($chain.builtin) -and -not $chain.elements) {
    $r = Resolve-TexVar $chain ('#' + $script:BuiltinUp[$chain.builtin])
    if ($r) { return @{ tex = (Tex-From-Ref $r); uv = $null } }
  }
  if ($chain.elements) {
    $areaBy = @{}; $upBy = @{}
    foreach ($el in @($chain.elements)) {
      if ($el -isnot [System.Collections.IDictionary] -or $el['faces'] -isnot [System.Collections.IDictionary]) { continue }
      $f = $el['from']; $t = $el['to']
      if ($f -eq $null -or $t -eq $null -or @($f).Count -lt 3) { continue }
      $dx = [math]::Abs([double]$t[0] - [double]$f[0]); $dy = [math]::Abs([double]$t[1] - [double]$f[1]); $dz = [math]::Abs([double]$t[2] - [double]$f[2])
      foreach ($dir in $el['faces'].Keys) {
        $face = $el['faces'][$dir]; if ($face -isnot [System.Collections.IDictionary] -or -not $face['texture']) { continue }
        $r = Resolve-TexVar $chain ([string]$face['texture']); if (-not $r) { continue }
        $a = switch ($dir) { 'up' { $dx * $dz } 'down' { $dx * $dz } 'north' { $dx * $dy } 'south' { $dx * $dy } default { $dz * $dy } }
        $areaBy[$r] = [double]$areaBy[$r] + $a
        if ($dir -eq 'up') { $upBy[$r] = [double]$upBy[$r] + $a }
      }
    }
    $pick = $null
    if ($upBy.Count) { $pick = ($upBy.GetEnumerator() | sort Value -desc | select -first 1).Key }
    elseif ($areaBy.Count) { $pick = ($areaBy.GetEnumerator() | sort Value -desc | select -first 1).Key }
    if ($pick) { return @{ tex = (Tex-From-Ref $pick); uv = $null } }
  }
  foreach ($k in 'all', 'top', 'end', 'crop', 'leaf', 'sapling', 'texture', 'side', '0', '1', 'layer0', 'particle') {
    if ($chain.textures.ContainsKey($k)) { $r = Resolve-TexVar $chain $chain.textures[$k]; if ($r) { return @{ tex = (Tex-From-Ref $r); uv = $null } } }
  }
  foreach ($k in $chain.textures.Keys) { $r = Resolve-TexVar $chain $chain.textures[$k]; if ($r) { return @{ tex = (Tex-From-Ref $r); uv = $null } } }
  return $null
}

# ---------------------------------------------------------------- OBJ models
function Get-ObjModel([string]$rl) {   # rl: path under models/ e.g. "block/container/x.obj" (lower-cased by ResourceLocation)
  if ($script:objCache.ContainsKey($rl)) { return $script:objCache[$rl] }
  $file = Find-Asset 'almura' ('models\' + ($rl -replace '/', '\'))
  $r = $null
  if (-not $file) { $r = @{ ok = $false; error = "obj not found: models/$rl"; groups = @() } }
  else { $r = Parse-Obj $script:IR_ROOT $file "models/$rl" 'almura' }
  $script:objCache[$rl] = $r
  return $r
}
# The texture the inventory model of an OBJ shows most: weight = sum of face area per map_Kd texture. Returns @{tex; uv} or @{error}
function Obj-Texture([string]$rl) {
  $o = Get-ObjModel $rl
  if (-not $o.ok) { return @{ error = $o.error } }
  $area = @{}; $uvb = @{}; $texBy = @{}
  foreach ($g in $o.groups) {
    if (-not $g.tex) { continue }
    $t = Strip-Png $g.tex; $key = "$($t.ns)|$($t.path)"
    $texBy[$key] = $t
    foreach ($face in $g.faces) {
      $area[$key] = [double]$area[$key] + (Quad-Area $face)
      if (-not $uvb.ContainsKey($key)) { $uvb[$key] = @{ u0 = 9; v0 = 9; u1 = -1; v1 = -1 } }
      foreach ($pt in $face) { if ($pt.hasUV) { $b = $uvb[$key]; if ($pt.u -lt $b.u0) { $b.u0 = $pt.u }; if ($pt.u -gt $b.u1) { $b.u1 = $pt.u }; if ($pt.v -lt $b.v0) { $b.v0 = $pt.v }; if ($pt.v -gt $b.v1) { $b.v1 = $pt.v } } }
    }
  }
  if ($area.Count -eq 0) { return @{ error = 'no textured group (white)' } }
  $best = ($area.GetEnumerator() | sort Value -desc | select -first 1).Key
  $t = $texBy[$best]; $b = $uvb[$best]
  $uv = $null; if ($b.u1 -ge $b.u0 -and $b.v1 -ge $b.v0) { $uv = @{ u0 = $b.u0; v0 = $b.v0; u1 = $b.u1; v1 = $b.v1 } }
  return @{ tex = (Tex-Lookup $t.ns $t.path); uv = $uv }
}

# ---------------------------------------------------------------- blockstate model strings
# "almura:container/x.obj" -> vanilla Variant rule: models/block/<path>  (.obj => OBJ loader, else models/block/<path>.json)
function Model-Icon([string]$id, [string]$modelRef) {
  $ns = 'minecraft'; $p = $modelRef; $i = $modelRef.IndexOf(':')
  if ($i -ge 0) { $ns = $modelRef.Substring(0, $i); $p = $modelRef.Substring($i + 1) }
  if ($ns -eq '') { $ns = 'minecraft' }
  $ns = $ns.ToLowerInvariant(); $p = ($p.ToLowerInvariant() -replace '//+', '/').TrimStart('/')
  if ($ns -ne 'almura') { return @{ broken = "model '$modelRef' is a vanilla/unknown namespace (minecraft:models/block/$p)" ; vanilla = $true } }
  if ($p.EndsWith('.obj')) {
    $ot = Obj-Texture "block/$p"
    if ($ot.error) { return @{ broken = "OBJ fails to load: $($ot.error)" } }
    return @{ layers = @($ot) }
  }
  $chain = Resolve-ModelChain 'almura' "block/$p"
  if (-not $chain.found) { return @{ broken = "model json not found: models/block/$p.json" } }
  $bt = Block-JsonTexture $chain
  if (-not $bt) { return @{ broken = "model has no resolvable texture: models/block/$p.json" } }
  return @{ layers = @($bt) }
}
function Item-Icon([string]$rel) {   # models/item/<rel>.json
  $chain = Resolve-ModelChain 'almura' "item/$rel"
  if (-not $chain.found) { return @{ broken = "item model json not found: models/item/$rel.json" } }
  if ($chain.builtin -eq 'item/generated') {
    $l = Item-Layers $chain
    if ($l.Count) { return @{ layers = $l } }
    return @{ broken = "item model has no layer0: models/item/$rel.json" }
  }
  $bt = Block-JsonTexture $chain      # e.g. slab items parent a block model
  if ($bt) { return @{ layers = @($bt) } }
  return @{ broken = "item model has no resolvable texture: models/item/$rel.json" }
}

# Blockstate (forge_marker 1): variant "inventory" = defaults merged with variants.inventory[0]
function Inv-ModelRef($bsd) {
  if ($bsd -isnot [System.Collections.IDictionary]) { return $null }
  $dm = $null; if ($bsd['defaults'] -is [System.Collections.IDictionary]) { $dm = $bsd['defaults']['model'] }
  $v = $bsd['variants']
  if ($v -is [System.Collections.IDictionary] -and $v.Contains('inventory')) {
    $iv = $v['inventory']
    if ($iv -is [System.Collections.IEnumerable] -and $iv -isnot [System.Collections.IDictionary] -and $iv -isnot [string]) { $iv = @($iv)[0] }
    if ($iv -is [System.Collections.IDictionary] -and $iv['model']) { return @{ model = [string]$iv['model']; hasInv = $true } }
    return @{ model = $dm; hasInv = $true }
  }
  return @{ model = $dm; hasInv = $false }
}
function Age-ModelRef($bsd, [int]$age) {   # variants.age.<n>.model, else defaults.model
  $mv = $null
  if ($bsd -is [System.Collections.IDictionary] -and $bsd['variants'] -is [System.Collections.IDictionary] -and $bsd['variants']['age'] -is [System.Collections.IDictionary]) { $mv = $bsd['variants']['age']["$age"] }
  if ($mv -is [System.Collections.IEnumerable] -and $mv -isnot [System.Collections.IDictionary] -and $mv -isnot [string]) { $mv = @($mv)[0] }
  if ($mv -is [System.Collections.IDictionary] -and $mv['model']) { return [string]$mv['model'] }
  if ($bsd -is [System.Collections.IDictionary] -and $bsd['defaults'] -is [System.Collections.IDictionary]) { return [string]$bsd['defaults']['model'] }
  return $null
}
function Is-SharedSprout([string]$modelRef) { return ($modelRef -match '(?i)^almura:crop/common/sprout_\d+\.obj$') }

# ---------------------------------------------------------------- compositing
$script:imgCache = @{}
function Get-Img([string]$file) {
  if (-not $script:imgCache.ContainsKey($file)) {
    $bytes = [IO.File]::ReadAllBytes($file); $ms = New-Object IO.MemoryStream (, $bytes)
    $script:imgCache[$file] = [Drawing.Image]::FromStream($ms)   # stream must stay open
  }
  return $script:imgCache[$file]
}
function Layer-Key($layer, [string]$atlasMode) {
  $t = $layer.tex
  if ($t.file) {
    $k = "F:$($t.file.ToLower())"
    if ($layer.tint) { $k += "|tint=$($layer.tint)" }
    if ($atlasMode -eq 'uv' -and $layer.uv -and ($t.w -gt 0) -and ($layer.uv.u1 - $layer.uv.u0 -lt 0.98 -or $layer.uv.v1 - $layer.uv.v0 -lt 0.98)) {
      $k += ('|uv={0:0.####},{1:0.####},{2:0.####},{3:0.####}' -f $layer.uv.u0, $layer.uv.v0, $layer.uv.u1, $layer.uv.v1)
    }
    return $k
  }
  if ($t.vanilla) { return "V:$($t.vanilla)" }
  return 'MISSING'
}
function Draw-Missing($g, [int]$x, [int]$y) {
  $m = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 248, 0, 248)); $k = New-Object Drawing.SolidBrush ([Drawing.Color]::Black)
  $g.FillRectangle($k, $x, $y, 32, 32); $g.FillRectangle($m, $x, $y, 16, 16); $g.FillRectangle($m, $x + 16, $y + 16, 16, 16)
  $m.Dispose(); $k.Dispose()
}
function Draw-Layer($g, $layer, [int]$x, [int]$y, [string]$atlasMode) {
  $t = $layer.tex
  if ($t.missing -and -not $t.file) { Draw-Missing $g $x $y; return }
  if ($t.vanilla -and -not $t.file) {
    $hex = $script:VanillaColors[$t.vanilla]; if (-not $hex) { $hex = '808080' }
    $c = [Drawing.Color]::FromArgb(255, [Convert]::ToInt32($hex.Substring(0, 2), 16), [Convert]::ToInt32($hex.Substring(2, 2), 16), [Convert]::ToInt32($hex.Substring(4, 2), 16))
    $b = New-Object Drawing.SolidBrush $c; $g.FillRectangle($b, $x + 2, $y + 2, 28, 28); $b.Dispose(); return
  }
  $img = Get-Img $t.file
  $W = $img.Width; $H = $img.Height
  $sx = 0; $sy = 0; $sw = $W; $sh = $H
  if ($H -gt $W -and ($H % $W) -eq 0) { $sh = $W }                 # animated strip: frame 0, square to the width
  elseif ($W -gt $H -and ($W % $H) -eq 0) { $sw = $H }
  if ($atlasMode -eq 'uv' -and $layer.uv -and ($layer.uv.u1 - $layer.uv.u0 -lt 0.98 -or $layer.uv.v1 - $layer.uv.v0 -lt 0.98)) {
    $sx = [math]::Floor($layer.uv.u0 * $W); $sw = [math]::Max(1, [math]::Ceiling(($layer.uv.u1 - $layer.uv.u0) * $W))
    $sy = [math]::Floor((1 - $layer.uv.v1) * $H); $sh = [math]::Max(1, [math]::Ceiling(($layer.uv.v1 - $layer.uv.v0) * $H))
    $sx = [math]::Min($sx, $W - 1); $sy = [math]::Max(0, [math]::Min($sy, $H - 1))
    if ($sx + $sw -gt $W) { $sw = $W - $sx }; if ($sy + $sh -gt $H) { $sh = $H - $sy }
    $sw = [math]::Max(1, $sw); $sh = [math]::Max(1, $sh)
  }
  # contain-fit, keep aspect ratio, centre
  $scale = [math]::Min(32.0 / $sw, 32.0 / $sh)
  $dw = [math]::Max(1, [math]::Round($sw * $scale)); $dh = [math]::Max(1, [math]::Round($sh * $scale))
  $dx = $x + [math]::Floor((32 - $dw) / 2); $dy = $y + [math]::Floor((32 - $dh) / 2)
  $ia = New-Object Drawing.Imaging.ImageAttributes; $ia.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
  if ($layer.tint) {      # multiply colour tint (tintindex / ItemColors), hex RRGGBB
    $tr = [Convert]::ToInt32($layer.tint.Substring(0, 2), 16) / 255.0; $tg = [Convert]::ToInt32($layer.tint.Substring(2, 2), 16) / 255.0; $tb = [Convert]::ToInt32($layer.tint.Substring(4, 2), 16) / 255.0
    $cm = New-Object Drawing.Imaging.ColorMatrix
    $cm.Matrix00 = [single]$tr; $cm.Matrix11 = [single]$tg; $cm.Matrix22 = [single]$tb; $cm.Matrix33 = [single]1; $cm.Matrix44 = [single]1
    $ia.SetColorMatrix($cm)
  }
  if ($scale -lt 1) { $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality }
  else { $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor; $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half }
  $g.DrawImage($img, (New-Object Drawing.Rectangle $dx, $dy, $dw, $dh), $sx, $sy, $sw, $sh, [Drawing.GraphicsUnit]::Pixel, $ia)
  $ia.Dispose()
}
