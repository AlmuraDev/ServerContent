param(
  # 'whole' = show the whole texture contain-fit (default, as requested); 'uv' = crop atlas textures to the UV box of the faces the game draws
  [ValidateSet('whole','uv')][string]$AtlasMode = 'whole',
  # 'plant' = shared sprout_N.obj stages get the crop's plant texture; 'game' = what the .mtl really draws (dirt mound)
  [ValidateSet('plant','game')][string]$SproutMode = 'plant',
  [string]$OutSuffix = ''
)
$ErrorActionPreference = 'Continue'
$sp  = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$sp\lib.ps1"
. "$sp\..\loader\objlib.ps1"
. "$sp\icons.ps1"
. "$sp\vanilla.ps1"
$script:stageBroken = 0
$root = Join-Path $env:WIKI_PACK_ROOT 'almura'
$cr   = "$root\content"
$NS   = 'almura'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------- helpers
function G($o, [string[]]$path) {
  foreach ($p in $path) {
    if ($o -is [System.Collections.IDictionary] -and $o.Contains($p)) { $o = $o[$p] } else { return $null }
  }
  return $o
}
function Has($o, [string]$k) { return ($o -is [System.Collections.IDictionary]) -and $o.Contains($k) }
function Humanize([string]$s) {
  if (-not $s) { return $s }
  $s = $s -replace '^[^:]+:', ''
  $s = ($s -split '/')[-1]
  $s = $s -creplace '([a-z])([A-Z])', '$1 $2'
  $words = $s -split '[_\s]+' | ? { $_ }
  return (($words | % { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ' ')
}
function CleanText($t) {
  if ($t -is [System.Collections.IEnumerable] -and $t -isnot [string]) { $t = ($t -join "`n") }
  if ($null -eq $t) { return $null }
  $t = [string]$t
  $t = $t -replace "\u00A7.", ''
  $t = $t -replace "\r", ''
  $lines = $t -split "`n" | % { ($_ -replace '[ \t]+', ' ').Trim() }
  $t = ($lines -join "`n").Trim()
  if ($t.Length -eq 0) { return $null }
  return $t
}
function NumStr($n) {
  if ($null -eq $n) { return $null }
  if ($n -is [double] -or $n -is [decimal] -or $n -is [single]) { return ([double]$n).ToString('0.####', [Globalization.CultureInfo]::InvariantCulture) }
  return [string]$n
}
function Rng($x) {
  if ($null -eq $x) { return $null }
  if ($x -is [System.Collections.IDictionary]) {
    if ((Has $x 'min') -or (Has $x 'max')) {
      $a = NumStr $x['min']; $b = NumStr $x['max']
      if ($null -eq $a) { return $b }; if ($null -eq $b) { return $a }
      if ($a -eq $b) { return $a }
      if ($a.StartsWith('-') -or $b.StartsWith('-')) { return "$a to $b" }
      return "$a-$b"
    }
    return $null
  }
  return NumStr $x
}
function NumOrRng($x) { if ($x -is [System.Collections.IDictionary]) { return Rng $x } else { return $x } }
function ShortBiome($b) { ($b | % { $_ -replace '^minecraft:', '' }) -join '/' }
# list of {biome?,min,max} -> "a-b" (default) plus "; biome: a-b"
function RangeList($lst) {
  if ($null -eq $lst) { return $null }
  if ($lst -is [System.Collections.IDictionary]) { $lst = @($lst) }
  $def = @(); $bio = @()
  foreach ($e in $lst) {
    $rg = Rng $e
    if ($null -eq $rg) { continue }
    if (Has $e 'biome') { $bio += ("$(ShortBiome $e['biome']): $rg") } else { $def += $rg }
  }
  $parts = @(); if ($def.Count) { $parts += ($def -join ', ') }; if ($bio.Count) { $parts += $bio }
  if (-not $parts.Count) { return $null }
  return ($parts -join '; ')
}
function ToolKind([string]$t) { if ($t -match '_(axe|pickaxe|shovel|hoe|sword)$') { return $Matches[1] } return $null }

# ------------------------------------------------------- minecraft names
$dyeNames = 'Ink Sac','Rose Red','Cactus Green','Cocoa Beans','Lapis Lazuli','Purple Dye','Cyan Dye','Light Gray Dye','Gray Dye','Pink Dye','Lime Dye','Dandelion Yellow','Light Blue Dye','Magenta Dye','Orange Dye','Bone Meal'
$colors   = 'White','Orange','Magenta','Light Blue','Yellow','Lime','Pink','Gray','Light Gray','Cyan','Purple','Blue','Brown','Green','Red','Black'
$woods    = 'Oak','Spruce','Birch','Jungle','Acacia','Dark Oak'
$mcOverride = @{
  'minecraft:reeds'='Sugar Canes'; 'minecraft:fish'='Raw Fish'; 'minecraft:cooked_fish'='Cooked Fish'
  'minecraft:beef'='Raw Beef'; 'minecraft:porkchop'='Raw Porkchop'; 'minecraft:chicken'='Raw Chicken'
  'minecraft:melon'='Melon Slice'; 'minecraft:waterlily'='Lily Pad'; 'minecraft:ender_eye'='Eye of Ender'
  'minecraft:brown_mushroom'='Brown Mushroom'; 'minecraft:glass_bottle'='Glass Bottle'
  'minecraft:bed'='Bed'; 'minecraft:sign'='Sign'; 'minecraft:brick'='Brick'; 'minecraft:lead'='Lead'
  'mocreatures:turkeycooked'='Cooked Turkey'
}
function McName([string]$id, [string]$data) {
  $d = 0; if ($data -eq '*') { $d = -1 } elseif ($data -match '^\d+$') { $d = [int]$data }
  switch ($id) {
    'minecraft:potion'     { if ($d -eq 0) { return 'Water Bottle' } else { return 'Potion' } }
    'minecraft:dye'        { if ($d -ge 0 -and $d -le 15) { return $dyeNames[$d] } else { return 'Dye' } }
    'minecraft:wool'       { if ($d -ge 0 -and $d -le 15) { return "$($colors[$d]) Wool" } else { return 'Wool' } }
    'minecraft:planks'     { if ($d -ge 0 -and $d -le 5) { return "$($woods[$d]) Planks" } else { return 'Planks' } }
    'minecraft:log'        { if ($d -ge 0 -and $d -le 3) { return "$($woods[$d]) Log" } else { return 'Log' } }
    'minecraft:coal'       { if ($d -eq 1) { return 'Charcoal' } else { return 'Coal' } }
    'minecraft:stone'      { $n = 'Stone','Granite','Polished Granite','Diorite','Polished Diorite','Andesite','Polished Andesite'; if ($d -ge 0 -and $d -le 6) { return $n[$d] } else { return 'Stone' } }
    'minecraft:stonebrick' { $n = 'Stone Bricks','Mossy Stone Bricks','Cracked Stone Bricks','Chiseled Stone Bricks'; if ($d -ge 0 -and $d -le 3) { return $n[$d] } else { return 'Stone Bricks' } }
    'minecraft:prismarine' { $n = 'Prismarine','Prismarine Bricks','Dark Prismarine'; if ($d -ge 0 -and $d -le 2) { return $n[$d] } else { return 'Prismarine' } }
    'minecraft:red_flower' { if ($d -le 0) { return 'Poppy' } else { return 'Flower' } }
    'minecraft:yellow_flower' { return 'Dandelion' }
    'minecraft:tallgrass'  { if ($d -eq 1) { return 'Grass' } elseif ($d -eq 2) { return 'Fern' } else { return 'Dead Bush' } }
    'minecraft:stone_slab' { $n = 'Stone Slab','Sandstone Slab','Wooden Slab','Cobblestone Slab','Brick Slab','Stone Brick Slab','Nether Brick Slab','Quartz Slab'; if ($d -ge 0 -and $d -le 7) { return $n[$d] } else { return 'Stone Slab' } }
    'minecraft:quartz_block' { return 'Block of Quartz' }
    'minecraft:sandstone'  { return 'Sandstone' }
  }
  if ($mcOverride.ContainsKey($id)) { return $mcOverride[$id] }
  return (Humanize $id)
}

# ------------------------------------------------------------ translations
$tr = @{}                # dir -> hashtable(key lower -> value)
$globalTr = @{}
function Get-DirTr([string]$dir) {
  if ($script:tr.ContainsKey($dir)) { return $script:tr[$dir] }
  $h = @{}
  $td = Join-Path $dir '_translations'
  if (Test-Path $td) {
    $pj = Join-Path $td 'en_us.json'
    if (Test-Path $pj) {
      $d = Read-Json $pj
      if ($null -eq $d) {   # malformed file: line-based salvage
        $d = [ordered]@{}
        foreach ($ln in [System.IO.File]::ReadAllLines($pj, [System.Text.Encoding]::UTF8)) {
          if ($ln -match '^\s*"([^"]+)"\s*:\s*"(.*)"\s*[,;]?\s*$') {
            try { $d[$Matches[1]] = $script:ser.DeserializeObject('"' + $Matches[2] + '"') } catch { }
          }
        }
        [void]$script:failures.Add("$pj :: salvaged $($d.Count) keys by line parsing")
      }
      if ($d -is [System.Collections.IDictionary]) { foreach ($k in $d.Keys) { $h[$k.ToLower()] = $d[$k]; if (-not $script:globalTr.ContainsKey($k.ToLower())) { $script:globalTr[$k.ToLower()] = $d[$k] } } }
    }
    $pp = Join-Path $td 'en_us.properties'
    if (Test-Path $pp) {
      foreach ($line in [System.IO.File]::ReadAllLines($pp, [System.Text.Encoding]::UTF8)) {
        $line = $line.TrimStart([char]0xFEFF)
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $i = $line.IndexOf('='); $k = $line.Substring(0,$i).Trim().ToLower(); $v = $line.Substring($i+1).Trim()
        if (-not $h.ContainsKey($k)) { $h[$k] = $v }
      }
    }
  }
  $script:tr[$dir] = $h
  return $h
}

# item groups
$groups = [ordered]@{}
$gtr = Read-Json "$cr\item_group\_translations\en_us.json"
if ($gtr) { foreach ($k in $gtr.Keys) { $groups[$k] = $gtr[$k] } }
function GroupName($g) {
  if (-not $g) { return $null }
  $key = $g -replace "^$NS`:", ''
  if ($g -like 'minecraft:*') {
    $groups[$g] = Humanize $g
    if ($g -eq 'minecraft:buildingblocks') { $groups[$g] = 'Building Blocks' }
    return $groups[$g]
  }
  if ($groups.Contains($key)) { return $groups[$key] }
  $groups[$key] = Humanize $key
  return $groups[$key]
}

# ------------------------------------------------------------ entries
$entries = [ordered]@{}   # lower id -> entry
$stat = @{ nameTr = 0; nameFallback = 0 }
$sectionMap = @{
  'block/container'='Containers'; 'block/crop'='Crops'; 'block/flower'='Flowers'; 'block/leaf'='Leaves'; 'block/log'='Logs'
  'block/sapling'='Saplings'; 'block/slab'='Slabs'; 'block/stair'='Stairs'
  'block/horizontal/agriculture'='Agriculture'; 'block/horizontal/building'='Building'; 'block/horizontal/crop'='Crop Blocks'
  'block/horizontal/decoration'='Decoration'; 'block/horizontal/flag'='Flags'; 'block/horizontal/flooring'='Flooring'
  'block/horizontal/furniture'='Furniture'; 'block/horizontal/letter'='Letters'; 'block/horizontal/lighting'='Lighting'
  'block/horizontal/ore'='Ores'; 'block/horizontal/sign'='Signs'; 'block/horizontal/roofing'='Roofing'; 'block/horizontal/currency'='Currency'
  'item/food/drink'='Drinks'; 'item/food/food'='Food'; 'item/seed'='Seeds'; 'item/slab'='Slabs'
  'item/tool_hoe'='Hoes'; 'item/tool_sickle'='Sickles'
  'item/normal/component'='Components'; 'item/normal/crop'='Crops'; 'item/normal/currency'='Currency'; 'item/normal/decoration'='Decoration'
  'item/normal/flower'='Flowers'; 'item/normal/furniture'='Furniture'; 'item/normal/ingredient'='Ingredients'; 'item/normal/light'='Lighting'
  'item/normal/ore'='Ores'; 'item/normal/tool'='Tools'
}
$tierTable = @{
  'wood'=@{dur=59;eff=2;lvl=0}; 'wooden'=@{dur=59;eff=2;lvl=0}; 'stone'=@{dur=131;eff=4;lvl=1}; 'iron'=@{dur=250;eff=6;lvl=2}
  'gold'=@{dur=32;eff=12;lvl=0}; 'golden'=@{dur=32;eff=12;lvl=0}; 'diamond'=@{dur=1561;eff=8;lvl=3}
}

$seedByCrop = @{}   # crop id lower -> seed id
$cropRaw    = @{}

function Get-Drops($state) {
  $out = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($s in $state.Values) {
    $acts = G $s @('action','destroy')
    if (-not $acts) { continue }
    foreach ($a in $acts) {
      foreach ($dr in @(G $a @('drop'))) {
        if (-not $dr -or -not (Has $dr 'item')) { continue }
        $it = [string]$dr['item']
        if ($seen.ContainsKey($it)) { continue }
        $seen[$it] = 1
        $o = [ordered]@{ item = $it; amount = (NumOrRng $dr['amount']) }
        $b = G $dr @('bonus')
        if ($b) { $o['bonusAmount'] = (NumOrRng $b['amount']); $o['bonusChancePct'] = (NumOrRng $b['chance']) }
        [void]$out.Add($o)
      }
    }
  }
  return ,$out
}

function Resolve-State($state, [string]$key, [int]$depth = 0) {
  $s = $state[$key]
  if ($depth -gt 5 -or -not (Has $s 'parent')) { return $s }
  $p = $s['parent']
  if (-not $state.Contains($p)) { return $s }
  $base = Resolve-State $state $p ($depth+1)
  $m = @{}
  foreach ($k in $base.Keys) { $m[$k] = $base[$k] }
  foreach ($k in $s.Keys) { if ($k -ne 'parent') { $m[$k] = $s[$k] } }
  return $m
}

function Block-Stats($def, [string]$id) {
  $st = G $def @('state')
  $o = [ordered]@{}
  if ($st -is [System.Collections.IDictionary] -and $st.Count) {
    $pick = $null
    foreach ($k in $st.Keys) { $rs = Resolve-State $st $k; if ((Has $rs 'hardness') -or (Has $rs 'resistance')) { $pick = $rs; break } }
    if (-not $pick) { $pick = Resolve-State $st (@($st.Keys)[0]) }
    if (Has $pick 'hardness') { $o['hardness'] = $pick['hardness'] }
    if (Has $pick 'resistance') { $o['resistance'] = $pick['resistance'] }
    $em = G $pick @('light','emission')
    if ($em -and $em -gt 0) { $o['lightLevel'] = [int][math]::Round($em) }
  }
  $mat = G $def @('material'); if ($mat) { $o['material'] = ($mat -replace '^minecraft:', '') }
  $tools = G $def @('effective_tools')
  if ($tools) {
    $kinds = @($tools | % { ToolKind $_ } | ? { $_ } | select -Unique)
    if ($kinds.Count) { $o['tool'] = ($kinds -join '/') }
  }
  if (Has $def 'slots') { $o['slots'] = $def['slots'] }
  if (Has $def 'limit') { $o['stackLimit'] = $def['limit'] }
  if ($st -is [System.Collections.IDictionary] -and $st.Count) {
    $dr = Get-Drops $st
    $dr = @($dr | ? { $_['item'] -ne $id })
    if ($dr.Count) { $o['drops'] = $dr }
  }
  return $o
}

function Add-Entry($id, $kind, $section, $baseName, $dirPath, $def) {
  $key = $id.ToLower()
  if ($entries.Contains($key)) { return $entries[$key] }
  $t = Get-DirTr $dirPath
  $nm = $null; $tip = $null
  $k1 = ($baseName + '.name').ToLower()
  if ($t.ContainsKey($k1)) { $nm = $t[$k1] } elseif ($globalTr.ContainsKey($k1)) { $nm = $globalTr[$k1] }
  $k2 = ($baseName + '.tooltip').ToLower()
  if ($t.ContainsKey($k2)) { $tip = $t[$k2] }
  $nm = CleanText $nm
  if ($nm) { $stat.nameTr++ } else { $nm = Humanize $baseName; $stat.nameFallback++ }
  $e = [ordered]@{
    id = $id; kind = $kind; section = $section; name = $nm; tooltip = (CleanText $tip)
    group = (GroupName (G $def @('item_group')))
    stats = [ordered]@{}; recipes = New-Object System.Collections.ArrayList; usedIn = New-Object System.Collections.ArrayList; icon = -1
  }
  $entries[$key] = $e
  return $e
}

function Get-Files([string]$dir) {
  if (-not (Test-Path $dir)) { return @() }
  return @(Get-ChildItem $dir -Recurse -File -Filter *.json | ? { $_.FullName -notmatch '\\_(recipes|translations)\\' } | sort FullName)
}
function RelParts($f, [string]$base) {   # returns @(relpath-without-ext (slashes), sectionKey, baseName, dir)
  $rel = $f.FullName.Substring($base.Length + 1) -replace '\\', '/'
  $rel = $rel -replace '\.json$', ''
  return $rel
}

# ---- blocks
$blockBase = "$cr\block"
$blockDirs = @('container','crop','flower','horizontal','leaf','log','sapling','slab','stair')
foreach ($bd in $blockDirs) {
  foreach ($f in (Get-Files "$blockBase\$bd")) {
    $def = Read-Json $f.FullName
    if ($def -isnot [System.Collections.IDictionary]) { continue }
    $rel = RelParts $f $blockBase           # e.g. horizontal/building/afledos_plank
    if ($def['is_double'] -eq $true) { continue }
    $secKey = 'block/' + (($rel -split '/')[0..($(if ($bd -eq 'horizontal') {1} else {0}))] -join '/')
    $section = $sectionMap[$secKey]
    if (-not $section) { $section = Humanize $bd }
    $id = "$NS`:$rel"
    $e = Add-Entry $id 'block' $section $f.BaseName $f.DirectoryName $def
    $stats = $e['stats']
    $bs = Block-Stats $def $id
    if ($bd -eq 'crop') {
      $c = [ordered]@{}
      $st = $def['state']
      $ages = @($st.Keys | ? { $_ -match '^age=' })
      $c['stages'] = $ages.Count
      $gs = $null
      foreach ($k in $st.Keys) { $rs = Resolve-State $st $k; if (Has $rs 'growth') { $gs = $rs; break } }
      if ($gs) {
        $lt = RangeList (G $gs @('growth','light')); if ($lt) { $c['light'] = $lt }
        $tp = RangeList (G $gs @('growth','temperature_required')); if ($tp) { $c['temperature'] = $tp }
        $ch = RangeList (G $gs @('growth','chance')); if ($ch) { $c['growthChance'] = $ch }
        $hy = G $gs @('hydration','block')
        if ($hy) {
          foreach ($h in $hy) {
            $lv = G $h @('state','level')
            if ($lv -and ($h['id'] -like '*farmland')) { $c['farmlandMoisture'] = (Rng $lv) }
          }
        }
      }
      if (Has $def 'seed') { $c['seed'] = $def['seed']; $seedByCrop[$id.ToLower()] = $def['seed'] }
      if ($bs.Contains('drops')) { $c['drops'] = $bs['drops'] }
      $stats['crop'] = $c
      $cropRaw[$id.ToLower()] = $c
      # ---- per-stage data
      $bsPath = "$root\blockstates\" + ($rel -replace '/', '\') + '.json'
      $bsd = $null; if (Test-Path -LiteralPath $bsPath) { $bsd = Read-Json $bsPath }
      $stl = New-Object System.Collections.ArrayList
      $ageKeys = @($st.Keys | ? { $_ -match '^age=\d+$' } | sort { [int]($_ -replace 'age=', '') })
      foreach ($ak in $ageKeys) {
        $n = [int]($ak -replace 'age=', '')
        $rs = Resolve-State $st $ak
        $so = [ordered]@{ age = $n }
        $v = RangeList (G $rs @('growth','chance'));               if ($v) { $so['growthChance'] = $v }
        $v = RangeList (G $rs @('growth','light'));                if ($v) { $so['light'] = $v }
        $v = RangeList (G $rs @('growth','temperature_required')); if ($v) { $so['temperature'] = $v }
        if (Has $rs 'hardness')   { $so['hardness'] = $rs['hardness'] }
        if (Has $rs 'resistance') { $so['resistance'] = $rs['resistance'] }
        $hyb = G $rs @('hydration','block')
        if ($hyb) {
          foreach ($h in $hyb) {
            $lv = G $h @('state','level')
            if ($lv -and ($h['id'] -like '*farmland')) { $so['farmlandMoisture'] = (Rng $lv) }
          }
          $hr = G $rs @('hydration','max_radius'); if ($null -ne $hr) { $so['hydrationRadius'] = $hr }
        }
        if (Has $rs 'can_rollback') { $so['canRollback'] = $rs['can_rollback'] }
        $one = [ordered]@{ x = $rs }
        $dr = @((Get-Drops $one) | ? { $_['item'] -ne $id })
        if ($dr.Count) { $so['drops'] = $dr }
        $mref = $null
        $mv = G $bsd @('variants','age',"$n")
        if ($mv -is [System.Collections.IEnumerable] -and $mv -isnot [System.Collections.IDictionary] -and $mv -isnot [string]) { $mv = @($mv)[0] }
        if ($mv -is [System.Collections.IDictionary] -and (Has $mv 'model')) { $mref = [string]$mv['model'] }
        if (-not $mref) { $mref = G $bsd @('defaults','model') }
        if ($mref) { $so['stageModel'] = $mref }
        $so['icon'] = -1
        [void]$stl.Add($so)
      }
      $e['stages'] = $stl
      foreach ($k in 'hardness','resistance') { }   # crops: keep block stats minimal
    } else {
      if ($bs.Count) { $stats['block'] = $bs }
      if ($bd -eq 'sapling') {
        $tree = G $def @('state','normal','tree')
        if (-not $tree) { foreach ($s in $def['state'].Values) { if (Has $s 'tree') { $tree = $s['tree']; break } } }
        if ($tree) { $stats['sapling'] = [ordered]@{ tree = $tree } }
      }
      if ($bd -eq 'leaf') {
        foreach ($s in $def['state'].Values) {
          $sp2 = G $s @('spread','block'); if ($sp2) { $stats['leaf'] = [ordered]@{ spreadsInto = $sp2 }; break }
        }
      }
      if ($bd -eq 'stair' -and (Has $def 'block')) { $stats['stair'] = [ordered]@{ base = $def['block'] } }
    }
  }
}

# ---- items
$itemBase = "$cr\item"
function Tier-Stats($def, $kind) {
  $o = [ordered]@{}
  $tier = G $def @('tier'); if (-not $tier) { return $o }
  $tn = ($tier -replace '^minecraft:', '').ToLower()
  $o['tier'] = $tn
  if ($tierTable.ContainsKey($tn)) {
    $tt = $tierTable[$tn]
    $o['durability'] = $tt.dur; $o['efficiency'] = $tt.eff; $o['harvestLevel'] = $tt.lvl
  }
  return $o
}
foreach ($idr in @('food/drink','food/food','normal','seed','slab','tool_hoe','tool_sickle')) {
  foreach ($f in (Get-Files "$itemBase\$($idr -replace '/','\')")) {
    $def = Read-Json $f.FullName
    if ($def -isnot [System.Collections.IDictionary]) { continue }
    $rel = RelParts $f $itemBase            # e.g. food/drink/beer_beer
    $parts = $rel -split '/'
    $secKey = if ($parts[0] -in 'food','normal') { 'item/' + $parts[0] + '/' + $parts[1] } else { 'item/' + $parts[0] }
    $section = $sectionMap[$secKey]; if (-not $section) { $section = Humanize $parts[0] }
    $id = "$NS`:$rel"
    if ($parts[0] -eq 'slab') {
      # merge with the slab block entry (same id)
      $key = $id.ToLower()
      if ($entries.Contains($key)) {
        if (-not $entries[$key]['group']) { $entries[$key]['group'] = GroupName $def['item_group'] }
      } else {
        $e = Add-Entry $id 'block' 'Slabs' $f.BaseName $f.DirectoryName $def
      }
      continue
    }
    $e = Add-Entry $id 'item' $section $f.BaseName $f.DirectoryName $def
    $stats = $e['stats']
    switch ($parts[0]) {
      'food' {
        $fo = [ordered]@{}
        $hg = Rng (G $def @('apply','food_level_change')); if ($null -ne $hg) { $fo['hunger'] = $hg }
        $hl = G $def @('apply','health_change'); if ($null -ne $hl) { $fo['health'] = $hl }
        $sa = G $def @('apply','saturation_change'); if ($null -ne $sa) { $fo['saturation'] = $sa }
        if (Has $def 'duration_ticks') { $fo['eatTicks'] = $def['duration_ticks'] }
        if ($def['always_edible'] -eq $true) { $fo['alwaysEdible'] = $true }
        $fx = New-Object System.Collections.ArrayList
        foreach ($pe in @(G $def @('potion_effects'))) {
          if (-not $pe) { continue }
          foreach ($pn in @($pe['potion'])) {
            $x = [ordered]@{ effect = (Humanize $pn) }
            if (Has $pe 'amplifier') { $x['amplifier'] = $pe['amplifier'] }
            if (Has $pe 'duration') { $x['durationTicks'] = $pe['duration'] }
            $cp = Rng $pe['chance']; if ($cp) { $x['chancePct'] = $cp }
            [void]$fx.Add($x)
          }
        }
        if ($fx.Count) { $fo['effects'] = $fx }
        $stats['food'] = $fo
      }
      'seed' {
        $s = [ordered]@{}
        if ($def['crop']) { $s['crop'] = $def['crop'] }
        if ($def['soil']) { $s['soil'] = $def['soil'] }
        $gc = RangeList (G $def @('grass','chance')); if ($gc) { $s['grassDropChance'] = $gc }
        $ga = RangeList (G $def @('grass','amount')); if ($ga) { $s['grassDropAmount'] = $ga }
        $stats['seed'] = $s
      }
      'tool_hoe'    { $stats['tool'] = Tier-Stats $def 'hoe' }
      'tool_sickle' {
        $t = Tier-Stats $def 'sickle'
        if ($def['effective_on']) { $t['effectiveOn'] = @($def['effective_on']) }
        $stats['tool'] = $t
      }
      'normal' { if (Has $def 'durability') { $stats['tool'] = [ordered]@{ durability = $def['durability'] } } }
    }
  }
}

# ---- items the Almura mod registers in code (no content json); their models and translations are in the pack or the mod's assets
$codeItems = @(
  @{ rel = 'normal/ingredient/glass_cruet';       group = 'almura:ingredient' }
  @{ rel = 'normal/ingredient/glass_water_cruet'; group = 'almura:ingredient' }
  @{ rel = 'normal/ingredient/glass_milk_cruet';  group = 'almura:ingredient'; name = 'Milk Filled Cruet' }   # names from the mod's en_us.lang
  @{ rel = 'normal/tool/farmers_almanac';         group = 'almura:tool'; name = "Farmer's Almanac" }
  @{ rel = 'normal/tool/harvesting_sack';         group = 'almura:agriculture' }
)
foreach ($ci in $codeItems) {
  $parts = $ci.rel -split '/'
  $section = $sectionMap['item/' + $parts[0] + '/' + $parts[1]]; if (-not $section) { $section = Humanize $parts[1] }
  $e = Add-Entry "$NS`:$($ci.rel)" 'item' $section $parts[-1] "$itemBase\$($parts[0])\$($parts[1])" @{ item_group = $ci.group }
  if ($ci.name -and $stat.nameFallback -and $e['name'] -eq (Humanize $parts[-1])) { $e['name'] = $ci.name; $stat.nameFallback--; $stat.nameTr++ }
}

# seeds -> crop soil
foreach ($e in $entries.Values) {
  if ($e['stats'].Contains('seed')) {
    $s = $e['stats']['seed']
    $ck = ([string]$s['crop']).ToLower()
    if ($cropRaw.ContainsKey($ck)) {
      $soil = $s['soil']; if ($soil) { $cropRaw[$ck]['soil'] = @($soil) }
    }
  }
}
# reorder crop stats so soil is next to seed (already assembled); nothing else needed

# ---------------------------------------------------------------- recipes
function ItemKey($it) {
  if ($null -eq $it) { return $null }
  $id = $null
  if (Has $it 'item') { $id = [string]$it['item'] }
  elseif (Has $it 'ore') { $id = 'ore:' + $it['ore'] }
  else { return $null }
  $d = ''
  if (Has $it 'data') { $d = [string]$it['data'] }
  if ($d -eq '32767') { return "${id}:*" }
  if ($d -match '^\d+$' -and $d -ne '0') { return "${id}:$d" }
  return $id
}
$recipeCount = 0; $recipeUnmatched = New-Object System.Collections.ArrayList
$refIds = @{}
$recipeFiles = Get-ChildItem $cr -Recurse -File -Filter *.json | ? { $_.Directory.Name -eq '_recipes' } | sort FullName
foreach ($f in $recipeFiles) {
  $d = Read-Json $f.FullName
  if ($d -isnot [System.Collections.IDictionary]) { continue }
  $type = $d['type']
  $rec = [ordered]@{}
  $resItem = $null; $inputs = @()
  switch ($type) {
    'crafting_shaped' {
      $rec['type'] = 'shaped'
      $pattern = @($d['pattern'])
      $key = $d['key']
      $grid = @(); for ($i=0; $i -lt 9; $i++) { $grid += ,$null }
      for ($y=0; $y -lt $pattern.Count -and $y -lt 3; $y++) {
        $row = [string]$pattern[$y]
        for ($x=0; $x -lt $row.Length -and $x -lt 3; $x++) {
          $ch = [string]$row[$x]
          if ($ch -ne ' ' -and $key.Contains($ch)) { $grid[$y*3+$x] = ItemKey $key[$ch] }
        }
      }
      $g3 = @(); for ($y=0; $y -lt 3; $y++) { $g3 += ,@($grid[($y*3)..($y*3+2)]) }
      $rec['grid'] = $g3
      $resItem = $d['result']
      $inputs = @($grid | ? { $_ })
    }
    'crafting_shapeless' {
      $rec['type'] = 'shapeless'
      $ing = New-Object System.Collections.ArrayList
      foreach ($i in @($d['ingredients'])) {
        $k = ItemKey $i
        $c = 1; if ((Has $i 'count') -and $i['count'] -gt 1) { $c = [int]$i['count'] }
        for ($n=0; $n -lt $c; $n++) { [void]$ing.Add($k) }
      }
      $rec['ingredients'] = $ing
      $resItem = $d['result']; $inputs = @($ing)
    }
    'furnace' {
      $rec['type'] = 'furnace'
      $k = ItemKey $d['input']
      $rec['ingredients'] = @($k)
      $resItem = $d['output']; $inputs = @($k)
      if (Has $d 'experience') { $rec['xp'] = $d['experience'] }
    }
    default { [void]$failures.Add("$($f.FullName) :: unknown recipe type $type"); continue }
  }
  $rid = ItemKey $resItem
  $rcount = 1; if ((Has $resItem 'count')) { $rcount = $resItem['count'] }
  $rec['count'] = $rcount
  $baseRid = if ($resItem -and (Has $resItem 'item')) { [string]$resItem['item'] } else { $null }
  if (-not $baseRid -or -not $entries.Contains($baseRid.ToLower())) { [void]$recipeUnmatched.Add("$($f.Name) -> $baseRid"); continue }
  $ent = $entries[$baseRid.ToLower()]
  [void]$ent['recipes'].Add($rec)
  $recipeCount++
  foreach ($k in $inputs) {
    $refIds[$k] = 1
    $baseK = ($k -replace '^(.+?:[^:]+):(\d+|\*)$', '$1')
    foreach ($kk in @($k, $baseK)) {
      if ($entries.Contains($kk.ToLower())) {
        $u = $entries[$kk.ToLower()]['usedIn']
        if (-not $u.Contains($ent['id'])) { [void]$u.Add($ent['id']) }
      }
    }
  }
}

# ---------------------------------------------------------------- names
$names = [ordered]@{}
function NameFor([string]$k) {
  $base = $k; $data = ''
  if ($k -match '^(.+?:[^:]+):(\d+|\*)$') { $base = $Matches[1]; $data = $Matches[2] }
  if ($entries.Contains($base.ToLower())) { return $entries[$base.ToLower()]['name'] }
  if ($base -like 'ore:*') { return (Humanize ($base -replace '^ore:', '')) }
  if ($base -like "$NS`:*") { return (Humanize $base) }
  return (McName $base $data)
}
foreach ($k in ($refIds.Keys | sort)) { $names[$k] = NameFor $k }
foreach ($e in $entries.Values) {   # ids used in stats (drops, seeds, sickles etc.)
  $st = $e['stats']
  $extra = @()
  if ($st.Contains('crop')) { $extra += $st['crop']['seed']; foreach ($dd in @($st['crop']['drops'])) { if ($dd) { $extra += $dd['item'] } } }
  if ($st.Contains('seed')) { $extra += $st['seed']['crop'] }
  if ($st.Contains('block')) { foreach ($dd in @($st['block']['drops'])) { if ($dd) { $extra += $dd['item'] } } }
  if ($st.Contains('tool') -and $st['tool'].Contains('effectiveOn')) { $extra += $st['tool']['effectiveOn'] }
  if ($st.Contains('sapling')) { $extra += $st['sapling']['tree'] }
  if ($st.Contains('leaf')) { $extra += $st['leaf']['spreadsInto'] }
  if ($st.Contains('stair')) { $extra += $st['stair']['base'] }
  foreach ($x in $extra) { if ($x -and -not $names.Contains($x)) { $names[$x] = NameFor $x } }
}

# ---------------------------------------------------------------- icons
# Mimics what the game shows in the inventory (rules: ..\loader\loader-spec.md, helpers: icons.ps1 + ..\loader\objlib.ps1).
#   items            -> models/item/<id>.json, item/generated layer0..N composited
#   blocks           -> blockstate variant "inventory" (defaults.model + variants.inventory): JSON = up face / "all", OBJ = map_Kd with the largest face area
#   slab items       -> models/item/slab/<id>.json (the single-slab blockstates have no "inventory" variant)
#   crops            -> no inventory item; entry icon = highest stage whose model loads; stage icons = that stage's model
#   cells            -> 32x32, contain-fit (aspect kept, centred), tall strips -> frame 0, models that fail in game -> magenta/black checker
$iconMissing = New-Object System.Collections.ArrayList
$specIndex = @{}; $specList = New-Object System.Collections.ArrayList; $cellKeys = New-Object System.Collections.ArrayList
function Cell-For($layers) {
  $key = (@($layers | % { Layer-Key $_ $AtlasMode }) -join '+')
  if (-not $specIndex.ContainsKey($key)) { $specIndex[$key] = $specList.Count; [void]$specList.Add($layers); [void]$cellKeys.Add($key) }
  return $specIndex[$key]
}
$missingLayer = @(@{ tex = @{ missing = $true; file = $null; vanilla = $null }; uv = $null })
function Broken-Cell([string]$what, [string]$why) { [void]$iconMissing.Add("$what :: $why"); Ico-Count 'broken'; return (Cell-For $missingLayer) }

$cropStageIcons = @{}
foreach ($e in $entries.Values) {
  $rel = $e['id'] -replace "^$NS`:", ''
  if ($e.Contains('stages')) { continue }     # crops handled below
  $ic = $null
  if ($e['kind'] -eq 'item' -or $e['section'] -eq 'Slabs') {
    $ic = Item-Icon $rel
  } else {
    $bsf = "$root\blockstates\" + ($rel -replace '/', '\') + '.json'
    if (-not (Test-Path -LiteralPath $bsf)) { $ic = @{ broken = "no blockstate file blockstates/$rel.json" } }
    else {
      $im = Inv-ModelRef (Read-Json $bsf)
      if (-not $im.hasInv) { $ic = @{ broken = 'blockstate has no "inventory" variant (game: missing item model)' } }
      elseif (-not $im.model) { $ic = @{ broken = 'blockstate inventory variant has no model' } }
      else { $ic = Model-Icon $e['id'] $im.model }
    }
  }
  if ($ic.broken) { $e['icon'] = Broken-Cell $e['id'] $ic.broken }
  else {
    $e['icon'] = Cell-For $ic.layers; Ico-Count 'ok'
    foreach ($l in $ic.layers) { if ($l.tex.vanilla -and -not $l.tex.file) { Ico-Count 'vanillaColour'; [void]$iconMissing.Add("$($e['id']) :: uses vanilla texture '$($l.tex.vanilla)' (not in this pack) - drawn as a flat approximate colour") } elseif ($l.tex.missing) { Ico-Count 'texMissing'; [void]$iconMissing.Add("$($e['id']) :: texture '$($l.tex.ns):$($l.tex.path)' does not exist (game shows the missing texture)") } }
  }
}

foreach ($e in $entries.Values) {
  if (-not $e.Contains('stages')) { continue }
  $rel = $e['id'] -replace "^$NS`:", ''
  $bsf = "$root\blockstates\" + ($rel -replace '/', '\') + '.json'
  $bsd = $null; if (Test-Path -LiteralPath $bsf) { $bsd = Read-Json $bsf }
  # per-stage specs
  $specs = @{}
  foreach ($so in $e['stages']) {
    $mref = Age-ModelRef $bsd ([int]$so['age'])
    $so['stageModel'] = $mref
    if (-not $mref) { $specs[[int]$so['age']] = @{ broken = 'no model for this age' }; continue }
    $specs[[int]$so['age']] = Model-Icon $e['id'] $mref
  }
  # plant texture of the crop = first stage that is not a shared sprout and loads
  $plant = $null
  foreach ($so in ($e['stages'] | sort { [int]$_['age'] })) {
    $sp2 = $specs[[int]$so['age']]
    if (-not (Is-SharedSprout $so['stageModel']) -and -not $sp2.broken -and $so['stageModel'] -notmatch '(?i)flat_\d+\.obj$') { $plant = $sp2; break }
  }
  $best = $null
  foreach ($so in ($e['stages'] | sort { [int]$_['age'] })) {
    $age = [int]$so['age']; $sp2 = $specs[$age]; $mref = $so['stageModel']
    if ((Is-SharedSprout $mref) -and $SproutMode -eq 'plant' -and $plant) { $sp2 = $plant; Ico-Count 'sproutAsPlant' }
    if ($sp2.broken) { $so['icon'] = Broken-Cell "$($e['id']) stage $age ($mref)" $sp2.broken; $script:stageBroken++ }
    else {
      $so['icon'] = Cell-For $sp2.layers; $best = $so['icon']
      foreach ($l in $sp2.layers) { if ($l.tex.missing -and -not $l.tex.file) { [void]$iconMissing.Add("$($e['id']) stage $age :: texture '$($l.tex.ns):$($l.tex.path)' does not exist") } }
    }
  }
  if ($null -ne $best) { $e['icon'] = $best } else { $e['icon'] = Broken-Cell $e['id'] 'no stage model loads' }
}

# ---------------------------------------------------------------- worldgen
$wg = [ordered]@{ ores = New-Object System.Collections.ArrayList; trees = New-Object System.Collections.ArrayList }
foreach ($f in (Get-ChildItem "$cr\generation\underground\ore" -File -Filter *.json -ErrorAction SilentlyContinue)) {
  $d = Read-Json $f.FullName; if ($d -isnot [System.Collections.IDictionary]) { continue }
  foreach ($en in @($d['entries'])) {
    $bid = [string]$en['block']
    $o = [ordered]@{ id = $bid; name = (NameFor $bid); dimension = (Humanize $f.BaseName); veinSize = $en['size']; veinsPerChunk = $en['count']; weight = $d['weight'] }
    foreach ($k in $en.Keys) { if ($k -notin 'block','size','count') { $o[$k] = $en[$k] } }
    [void]$wg['ores'].Add($o)
    if (-not $names.Contains($bid)) { $names[$bid] = NameFor $bid }
  }
}
foreach ($f in (Get-Files "$cr\tree")) {
  $d = Read-Json $f.FullName; if ($d -isnot [System.Collections.IDictionary]) { continue }
  $tid = "$NS`:$($f.BaseName)"
  $o = [ordered]@{ id = $tid; name = (Humanize $f.BaseName) }
  $hs = @()
  foreach ($h in @($d['height'])) {
    if (-not $h) { continue }
    $mn = $h['min']; $vr = G $h @('variance'); $lo = $mn; $hi = $mn
    if ($vr) { $lo = $mn + [int]$vr['min']; $hi = $mn + [int]$vr['max'] }
    $rg = if ($lo -eq $hi) { "$lo" } else { "$lo-$hi" }
    if (Has $h 'biome') { $hs += ("$(ShortBiome $h['biome']): $rg") } else { $hs += $rg }
  }
  if ($hs.Count) { $o['trunkHeight'] = $hs }
  if ($d['log']) { $o['log'] = $d['log']; $names[$d['log']] = NameFor $d['log'] }
  if ($d['leaves']) { $o['leaves'] = $d['leaves']; $names[$d['leaves']] = NameFor $d['leaves'] }
  if ($d['fruit']) { $fr = [ordered]@{ block = $d['fruit']['block'] }; $fc = RangeList $d['fruit']['chance']; if ($fc) { $fr['chancePct'] = $fc }; $o['fruit'] = $fr; $names[$fr['block']] = NameFor $fr['block'] }
  foreach ($k in $d.Keys) { if ($k -notin 'height','log','leaves','fruit') { $o[$k] = $d[$k] } }
  $gf = Join-Path "$cr\generation\feature\tree" ($f.BaseName + '.json')
  if (Test-Path $gf) {
    $gd = Read-Json $gf
    if ($gd) {
      $gen = @()
      foreach ($c in @($gd['chance'])) {
        if (-not $c) { continue }
        $rg = Rng $c
        if (Has $c 'biome') { $gen += [ordered]@{ biomes = @($c['biome']); chancePct = $rg } } else { $gen += [ordered]@{ biomes = @('all'); chancePct = $rg } }
      }
      if ($gen.Count) {
        $o['generation'] = $gen
        $o['generatesNaturally'] = [bool](@($gen | ? { $_['chancePct'] -and ($_['chancePct'] -replace '[^\d.]+', ' ').Trim().Split(' ') | ? { $_ -and [double]$_ -gt 0 } }).Count)
      }
      if ($gd['requires']) { $o['requires'] = $gd['requires'] }
      if ($gd['worlds']) { $o['worlds'] = $gd['worlds'] }
    }
  }
  [void]$wg['trees'].Add($o)
}
# sapling names for trees
foreach ($e in $entries.Values) { if ($e['stats'].Contains('sapling')) { $t = $e['stats']['sapling']['tree'] } }

# ---------------------------------------------------------------- tree links
$treeIds = @{}; foreach ($tr2 in $wg['trees']) { $treeIds[([string]$tr2['id']).ToLower()] = $tr2 }
$treeBy = @{}
foreach ($tr2 in $wg['trees']) {
  foreach ($b in @($tr2['log'], $tr2['leaves'], (G $tr2 @('fruit','block')))) {
    if (-not $b) { continue }
    $bk = ([string]$b).ToLower()
    if (-not $treeBy.ContainsKey($bk)) { $treeBy[$bk] = New-Object System.Collections.ArrayList }
    if (-not $treeBy[$bk].Contains($tr2['id'])) { [void]$treeBy[$bk].Add($tr2['id']) }
  }
}
$saplingBy = @{}
foreach ($e in $entries.Values) {
  if ($e['section'] -notin 'Logs','Leaves','Saplings') { continue }
  if ($e['section'] -eq 'Saplings') {
    $tid = G $e['stats'] @('sapling','tree')
    if ($tid -and $treeIds.ContainsKey(([string]$tid).ToLower())) {
      $e['tree'] = $tid
      $tk = ([string]$tid).ToLower()
      if (-not $saplingBy.ContainsKey($tk)) { $saplingBy[$tk] = New-Object System.Collections.ArrayList }
      [void]$saplingBy[$tk].Add($e['id'])
    }
  } else {
    $c2 = $treeBy[$e['id'].ToLower()]
    if ($c2 -and $c2.Count -eq 1) { $e['tree'] = $c2[0] }
    elseif ($c2 -and $c2.Count -gt 1) { $e['trees'] = @($c2) }
  }
}
foreach ($tr2 in $wg['trees']) {
  $sl = $saplingBy[([string]$tr2['id']).ToLower()]
  if ($sl -and $sl.Count -eq 1) { $tr2['sapling'] = $sl[0] } elseif ($sl -and $sl.Count -gt 1) { $tr2['saplings'] = @($sl) }
}

# ---------------------------------------------------------------- output
$out = [ordered]@{ groups = $groups; entries = @(); names = $names; worldgen = $wg }
$list = New-Object System.Collections.ArrayList
foreach ($e in ($entries.Values | sort { $_['section'] }, { $_['name'] })) {
  $o = [ordered]@{}
  foreach ($k in 'id','kind','section','name','tooltip','group') { $o[$k] = $e[$k] }
  $o['stats'] = $e['stats']
  if ($e.Contains('tree')) { $o['tree'] = $e['tree'] }
  if ($e.Contains('trees')) { $o['trees'] = @($e['trees']) }
  if ($e.Contains('stages')) { $o['stages'] = @($e['stages']) }
  $o['recipes'] = @($e['recipes'])
  if ($e['usedIn'].Count) { $o['usedIn'] = @($e['usedIn']) }
  $o['icon'] = $e['icon']
  [void]$list.Add($o)
}
$out['entries'] = $list
# ---------------------------------------------------------------- vanilla (minecraft:) ids -> name + icon + render
# every "minecraft:<id>[:<data>|:*]" string the wiki data references (recipes, drops, soils, worldgen, names...), resolved against the extracted 1.12.2 jar
$vanillaIn = [ordered]@{ entries = $list; names = $names; worldgen = $wg } | ConvertTo-Json -Depth 30 -Compress
$vanillaKeys = @([regex]::Matches($vanillaIn, '"(minecraft:[^"]+)"') | % { $_.Groups[1].Value } | sort -Unique)
$vanilla = [ordered]@{}; $vanillaSkipped = New-Object System.Collections.ArrayList; $vanillaReport = New-Object System.Collections.ArrayList
$vanillaRender = [ordered]@{}
$vrPath = Join-Path $sp '..\render\vanilla-render-index.json'
$vrIndex = $null; if (Test-Path -LiteralPath $vrPath) { $vrIndex = Read-Json $vrPath }
foreach ($vk in $vanillaKeys) {
  $r = Resolve-Vanilla $vk
  if ($null -eq $r) { [void]$vanillaSkipped.Add($vk); continue }
  $ic = -1
  if ($r.layers.Count -gt 0) { $ic = Cell-For $r.layers }
  $rd = -1
  if ($r.kind -eq 'block' -or $r.kind -eq 'custom') {
    $spec = [ordered]@{ model = $null; json = $null; tint = $null }
    if ($r.kind -eq 'custom') { $spec.json = $r.json } else { $spec.model = 'minecraft:' + $r.model }
    if ($r.tint) { $spec.tint = $r.tint.rgb }
    $vanillaRender[$vk] = $spec
    if ($vrIndex -and (Has $vrIndex $vk)) { $rd = [int]$vrIndex[$vk] }
  }
  $vanilla[$vk] = [ordered]@{ name = $r.name; icon = $ic; render = $rd }
  $names[$vk] = $r.name
  [void]$vanillaReport.Add(("{0}`t{1}`t{2}`ticon={3}`trender={4}`t{5}`t{6}" -f $vk, $r.name, $r.kind, $ic, $rd, $r.model, ($r.flags -join '; ')))
}
foreach ($o in $wg['ores']) { $bk = [string]$o['id']; if ($vanilla.Contains($bk)) { $o['name'] = $vanilla[$bk]['name'] } }
$sortedNames = [ordered]@{}; foreach ($nk in ($names.Keys | sort)) { $sortedNames[$nk] = $names[$nk] }
$names = $sortedNames; $out['names'] = $names
$out['vanilla'] = $vanilla
[System.IO.File]::WriteAllText((Join-Path $sp '..\vanilla\vanilla-render.json'), ($vanillaRender | ConvertTo-Json -Depth 6), $utf8)
[System.IO.File]::WriteAllLines((Join-Path $sp '..\vanilla\vanilla-resolve.txt'), [string[]]@($vanillaReport), $utf8)
[System.IO.File]::WriteAllLines((Join-Path $sp '..\vanilla\vanilla-skipped.txt'), [string[]]@($vanillaSkipped), $utf8)
# ---- draw the atlas of cells (64 columns x 32px, unchanged format)
$cols = 64
$rows = [int][math]::Ceiling([math]::Max(1, $specList.Count) / $cols)
$bmp = New-Object System.Drawing.Bitmap ($cols * 32), ($rows * 32), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$badTex = 0
for ($i = 0; $i -lt $specList.Count; $i++) {
  $cx = ($i % $cols) * 32; $cy = [int][math]::Floor($i / $cols) * 32
  foreach ($layer in $specList[$i]) {
    try { Draw-Layer $g $layer $cx $cy $AtlasMode }
    catch { $badTex++; [void]$failures.Add("icon cell $i :: $($layer.tex.file) :: $($_.Exception.Message)") }
  }
}
$g.Dispose()
$bmp.Save("$sp\icons$OutSuffix.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$texList = $specList
$mapLines = New-Object System.Collections.ArrayList
foreach ($e in $entries.Values) { [void]$mapLines.Add(("{0}`t{1}`t{2}" -f $e['id'], $e['icon'], $cellKeys[$e['icon']])); if ($e.Contains('stages')) { foreach ($so in $e['stages']) { [void]$mapLines.Add(("{0}#stage{1}`t{2}`t{3}`t{4}" -f $e['id'], $so['age'], $so['icon'], $cellKeys[$so['icon']], $so['stageModel'])) } } }
[System.IO.File]::WriteAllLines("$sp\icon-map$OutSuffix.txt", [string[]]@($mapLines), $utf8)
$stageIconOk = 0; $stageIconMissing = $script:stageBroken
foreach ($e in $entries.Values) { if ($e.Contains('stages')) { foreach ($so in $e['stages']) { if ($so['icon'] -ge 0) { $stageIconOk++ } } } }


$json = $out | ConvertTo-Json -Depth 30 -Compress
[System.IO.File]::WriteAllText("$sp\wiki-data$OutSuffix.json", $json, $utf8)
[System.IO.File]::WriteAllLines("$sp\failures.txt", [string[]]@($failures), $utf8)
[System.IO.File]::WriteAllLines("$sp\icon-missing.txt", [string[]]@($iconMissing), $utf8)
[System.IO.File]::WriteAllLines("$sp\recipe-unmatched.txt", [string[]]@($recipeUnmatched), $utf8)

"ENTRIES: $($entries.Count)"
$entries.Values | group { $_['section'] } | sort Name | % { "  $($_.Name): $($_.Count)" }
"names from translations: $($stat.nameTr); fallback: $($stat.nameFallback)"
"icons: unique cells $($specList.Count); notes $($iconMissing.Count); bad draws $badTex"
"recipes attached: $recipeCount (files $($recipeFiles.Count)); unmatched $($recipeUnmatched.Count)"
"crop stage icons: resolved $stageIconOk, missing $stageIconMissing"
"parse failures: $($failures.Count)"
"wiki-data.json: $([math]::Round((Get-Item "$sp\wiki-data$OutSuffix.json").Length/1KB)) KB; icons$OutSuffix.png: $([math]::Round((Get-Item "$sp\icons$OutSuffix.png").Length/1KB)) KB; mode atlas=$AtlasMode sprout=$SproutMode; cells $($specList.Count); icon counters: $(($script:icoCounters.GetEnumerator() | sort Name | % { "$($_.Name)=$($_.Value)" }) -join ' ')"




