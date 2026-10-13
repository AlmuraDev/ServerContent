# Vanilla Minecraft 1.12.2 id+metadata -> item model, display name, icon layers / 3D render model.
# Dot-sourced by build.ps1 after lib.ps1, objlib.ps1 and icons.ps1 (needs Resolve-ModelChain, Item-Layers, Block-JsonTexture, Tex-From-Ref).
# 1.12 still uses metadata: the item model name is the one ItemModelMesher registers for that meta (models/item/<name>.json in the jar),
# the display name is the lang key of the item's unlocalized name (item.X.name / tile.X.name) for that meta.

$script:VJAR = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\vanilla\jar\assets\minecraft'))
$script:VLang = @{}
foreach ($ln in [IO.File]::ReadAllLines("$script:VJAR\lang\en_us.lang", [Text.Encoding]::UTF8)) {
  if ($ln -match '^\s*#' -or $ln -notmatch '=') { continue }
  $i = $ln.IndexOf('='); $script:VLang[$ln.Substring(0, $i).Trim()] = $ln.Substring($i + 1).Trim()
}

# ---- families -------------------------------------------------------------
$script:cWool = 'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray', 'silver', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'
$script:cLang = 'white', 'orange', 'magenta', 'lightBlue', 'yellow', 'lime', 'pink', 'gray', 'silver', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'
$script:cDye  = 'black', 'red', 'green', 'brown', 'blue', 'purple', 'cyan', 'silver', 'gray', 'pink', 'lime', 'yellow', 'light_blue', 'magenta', 'orange', 'white'
$script:cDyeL = 'black', 'red', 'green', 'brown', 'blue', 'purple', 'cyan', 'silver', 'gray', 'pink', 'lime', 'yellow', 'lightBlue', 'magenta', 'orange', 'white'
$script:wModel = 'oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak'
$script:wLang  = 'oak', 'spruce', 'birch', 'jungle', 'acacia', 'big_oak'

# default item-model name = registry path; exceptions:
$script:ModelOverride = @{
  'potion' = 'bottle_drinkable'; 'splash_potion' = 'bottle_splash'; 'lingering_potion' = 'bottle_lingering'
  'fish' = 'cod'; 'cooked_fish' = 'cooked_cod'; 'stone_slab' = 'stone_slab'
}
# lang key per registry path (meta 0 / only variant)
$script:LangMap = @{
  'apple'='item.apple.name'; 'beef'='item.beefRaw.name'; 'blaze_powder'='item.blazePowder.name'; 'blaze_rod'='item.blazeRod.name'; 'book'='item.book.name'; 'bow'='item.bow.name'
  'bowl'='item.bowl.name'; 'bread'='item.bread.name'; 'brewing_stand'='item.brewingStand.name'; 'brick'='item.brick.name'; 'brick_block'='tile.brick.name'; 'bucket'='item.bucket.name'
  'carrot'='item.carrots.name'; 'chest'='tile.chest.name'; 'trapped_chest'='tile.chestTrap.name'; 'ender_chest'='tile.enderChest.name'; 'chicken'='item.chickenRaw.name'; 'clay_ball'='item.clay.name'; 'clay'='tile.clay.name'
  'cobblestone'='tile.stonebrick.name'; 'cooked_chicken'='item.chickenCooked.name'; 'cooked_porkchop'='item.porkchopCooked.name'; 'cooked_beef'='item.beefCooked.name'
  'cookie'='item.cookie.name'; 'diamond'='item.diamond.name'; 'egg'='item.egg.name'; 'emerald'='item.emerald.name'; 'ender_eye'='item.eyeOfEnder.name'; 'ender_pearl'='item.enderPearl.name'
  'farmland'='tile.farmland.name'; 'fermented_spider_eye'='item.fermentedSpiderEye.name'; 'flint'='item.flint.name'; 'ghast_tear'='item.ghastTear.name'; 'glass'='tile.glass.name'
  'glass_bottle'='item.glassBottle.name'; 'glass_pane'='tile.thinGlass.name'; 'glowstone'='tile.lightgem.name'; 'glowstone_dust'='item.yellowDust.name'; 'gold_ingot'='item.ingotGold.name'
  'gravel'='tile.gravel.name'; 'ice'='tile.ice.name'; 'iron_axe'='item.hatchetIron.name'; 'iron_block'='tile.blockIron.name'; 'iron_chestplate'='item.chestplateIron.name'
  'iron_ingot'='item.ingotIron.name'; 'iron_shovel'='item.shovelIron.name'; 'iron_sword'='item.swordIron.name'; 'iron_pickaxe'='item.pickaxeIron.name'; 'iron_hoe'='item.hoeIron.name'
  'jukebox'='tile.jukebox.name'; 'lapis_block'='tile.blockLapis.name'; 'gold_block'='tile.blockGold.name'; 'diamond_block'='tile.blockDiamond.name'; 'emerald_block'='tile.blockEmerald.name'; 'coal_block'='tile.blockCoal.name'
  'lead'='item.leash.name'; 'leather'='item.leather.name'; 'leather_boots'='item.bootsCloth.name'; 'leather_helmet'='item.helmetCloth.name'; 'leather_chestplate'='item.chestplateCloth.name'; 'leather_leggings'='item.leggingsCloth.name'
  'map'='item.map.name'; 'melon'='item.melon.name'; 'melon_block'='tile.melon.name'; 'melon_seeds'='item.seeds_melon.name'; 'mossy_cobblestone'='tile.stoneMoss.name'; 'nether_wart'='item.netherStalkSeeds.name'
  'obsidian'='tile.obsidian.name'; 'packed_ice'='tile.icePacked.name'; 'porkchop'='item.porkchopRaw.name'; 'potato'='item.potato.name'; 'pumpkin'='tile.pumpkin.name'; 'lit_pumpkin'='tile.litpumpkin.name'
  'pumpkin_seeds'='item.seeds_pumpkin.name'; 'redstone'='item.redstone.name'; 'redstone_block'='tile.blockRedstone.name'; 'reeds'='item.reeds.name'; 'rotten_flesh'='item.rottenFlesh.name'
  'sign'='item.sign.name'; 'stick'='item.stick.name'; 'string'='item.string.name'; 'sugar'='item.sugar.name'; 'torch'='tile.torch.name'; 'waterlily'='tile.waterlily.name'; 'wheat'='item.wheat.name'
  'wheat_seeds'='item.seeds.name'; 'diamond_sword'='item.swordDiamond.name'; 'cactus'='tile.cactus.name'; 'snowball'='item.snowball.name'; 'paper'='item.paper.name'; 'bone'='item.bone.name'
  'gunpowder'='item.sulphur.name'; 'slime_ball'='item.slimeball.name'; 'spider_eye'='item.spiderEye.name'; 'milk_bucket'='item.milk.name'; 'water_bucket'='item.bucketWater.name'; 'lava_bucket'='item.bucketLava.name'
  'quartz'='item.netherquartz.name'; 'netherbrick'='item.netherbrick.name'; 'feather'='item.feather.name'; 'cooked_mutton'='item.muttonCooked.name'; 'mutton'='item.muttonRaw.name'
  'baked_potato'='item.potatoBaked.name'; 'poisonous_potato'='item.potatoPoisonous.name'; 'beetroot'='item.beetroot.name'; 'beetroot_seeds'='item.beetroot_seeds.name'; 'mushroom_stew'='item.mushroomStew.name'
  'golden_carrot'='item.carrotGolden.name'; 'speckled_melon'='item.speckledMelon.name'; 'gold_nugget'='item.goldNugget.name'; 'iron_nugget'='item.ironNugget.name'; 'sponge'='tile.sponge.dry.name'
  'cobblestone_wall'='tile.cobbleWall.normal.name'; 'oak_stairs'='tile.stairsWood.name'; 'stone_stairs'='tile.stairsStone.name'; 'brick_stairs'='tile.stairsBrick.name'; 'sandstone_stairs'='tile.stairsSandStone.name'
  'crafting_table'='tile.workbench.name'; 'furnace'='tile.furnace.name'; 'bookshelf'='tile.bookshelf.name'; 'tnt'='tile.tnt.name'; 'ladder'='tile.ladder.name'; 'snow'='tile.snow.name'; 'soul_sand'='tile.hellsand.name'
  'netherrack'='tile.hellrock.name'; 'end_stone'='tile.whiteStone.name'; 'mycelium'='tile.mycel.name'; 'hay_block'='tile.hayBlock.name'; 'web'='tile.web.name'; 'vine'='tile.vine.name'; 'grass'='tile.grass.name'
  'gold_ore'='tile.oreGold.name'; 'iron_ore'='tile.oreIron.name'; 'coal_ore'='tile.oreCoal.name'; 'lapis_ore'='tile.oreLapis.name'; 'diamond_ore'='tile.oreDiamond.name'; 'redstone_ore'='tile.oreRedstone.name'; 'emerald_ore'='tile.oreEmerald.name'
}
# vanilla lang is ambiguous here (both mushrooms are "Mushroom"), keep the two distinguishable
$script:NameOverride = @{ 'brown_mushroom' = 'Brown Mushroom'; 'red_mushroom' = 'Red Mushroom'; 'wheat_seeds' = 'Wheat Seeds'; 'clay_ball' = 'Clay Ball'; 'melon' = 'Melon Slice'; 'milk_bucket' = 'Milk Bucket' }
# wildcard (":*") display names where the lang file has no generic key
$script:AnyOverride = @{ 'dye' = 'Dye'; 'bed' = 'Bed'; 'potion' = 'Potion' }
# colour tints applied the way ItemColors / BlockColors do in the inventory: path -> meta (-1 = all) -> @{ rgb; layer (-1 = every tintindex face) }
$script:GRASS = '7CBD6B'
$script:Tints = @{
  'tallgrass'   = @{ 1 = @{ rgb = $script:GRASS; layer = 0 }; 2 = @{ rgb = $script:GRASS; layer = 0 } }
  'double_plant' = @{ 2 = @{ rgb = $script:GRASS; layer = 0 }; 3 = @{ rgb = $script:GRASS; layer = 0 } }
  'waterlily'   = @{ -1 = @{ rgb = '208030'; layer = 0 } }
  'vine'        = @{ -1 = @{ rgb = $script:GRASS; layer = 0 } }
  'grass'       = @{ -1 = @{ rgb = $script:GRASS; layer = -1 } }
  'leaves'      = @{ 0 = @{ rgb = '48B518'; layer = -1 }; 1 = @{ rgb = '619961'; layer = -1 }; 2 = @{ rgb = '80A755'; layer = -1 }; 3 = @{ rgb = '48B518'; layer = -1 } }
  'leaves2'     = @{ -1 = @{ rgb = '48B518'; layer = -1 } }
  'potion'      = @{ -1 = @{ rgb = '385DC6'; layer = 0 } }       # water bottle: PotionUtils default colour (3694022)
  'leather_boots' = @{ -1 = @{ rgb = 'A06540'; layer = 0 } }; 'leather_helmet' = @{ -1 = @{ rgb = 'A06540'; layer = 0 } }
  'leather_chestplate' = @{ -1 = @{ rgb = 'A06540'; layer = 0 } }; 'leather_leggings' = @{ -1 = @{ rgb = 'A06540'; layer = 0 } }
}
# items whose model is builtin/entity (rendered by a TileEntity renderer, no JSON geometry): small hand-made stand-ins, flagged "guessed"
$script:EntityStandIn = @{
  'chest' = '{"textures":{"p":"blocks/planks_oak","m":"blocks/iron_block"},"elements":[{"from":[1,0,1],"to":[15,14,15],"faces":{"down":{"texture":"#p"},"up":{"texture":"#p"},"north":{"texture":"#p"},"south":{"texture":"#p"},"west":{"texture":"#p"},"east":{"texture":"#p"}}},{"from":[7,7,15],"to":[9,11,16],"faces":{"down":{"texture":"#m"},"up":{"texture":"#m"},"north":{"texture":"#m"},"south":{"texture":"#m"},"west":{"texture":"#m"},"east":{"texture":"#m"}}}]}'
  'bed'   = '{"textures":{"p":"blocks/planks_oak","r":"blocks/wool_colored_red","w":"blocks/wool_colored_white"},"elements":[{"from":[0,0,0],"to":[16,3,16],"faces":{"down":{"texture":"#p"},"up":{"texture":"#p"},"north":{"texture":"#p"},"south":{"texture":"#p"},"west":{"texture":"#p"},"east":{"texture":"#p"}}},{"from":[0,3,0],"to":[16,9,16],"faces":{"down":{"texture":"#r"},"up":{"texture":"#r"},"north":{"texture":"#r"},"south":{"texture":"#r"},"west":{"texture":"#r"},"east":{"texture":"#r"}}},{"from":[2,9,1],"to":[14,10,6],"faces":{"down":{"texture":"#w"},"up":{"texture":"#w"},"north":{"texture":"#w"},"south":{"texture":"#w"},"west":{"texture":"#w"},"east":{"texture":"#w"}}}]}'
}
$script:EntityStandIn['trapped_chest'] = $script:EntityStandIn['chest']

# ids that are not items (biomes in worldgen lists, creative tab ids)
$script:NonItems = @('ocean','plains','desert','extreme_hills','forest','taiga','swampland','river','hell','sky','frozen_ocean','frozen_river','ice_flats','ice_mountains','mushroom_island','mushroom_island_shore','beaches','desert_hills','forest_hills','taiga_hills','smaller_extreme_hills','jungle','jungle_hills','jungle_edge','deep_ocean','stone_beach','cold_beach','birch_forest','birch_forest_hills','roofed_forest','cold_taiga','cold_taiga_hills','redwood_taiga','redwood_taiga_hills','extreme_hills_with_trees','savanna','savanna_rock','mesa','mesa_rock','mesa_clear_rock','void','buildingblocks','decorations','transportation','misc')
function Is-VanillaNonItem([string]$id) { $p = $id -replace '^minecraft:', ''; return ($script:NonItems -contains $p) -or $p.StartsWith('mutated_') }

function VLangGet([string]$key) { if ($key -and $script:VLang.ContainsKey($key)) { return $script:VLang[$key] } return $null }

# -> @{ model; lang; any; note } for registry path + meta (model = models/item/<model>.json)
function Get-VanillaDef([string]$p, [int]$m) {
  $d = @{ model = $null; lang = $null; any = $null; note = $null }
  $w = $script:wModel; $wl = $script:wLang; $cw = $script:cWool; $cl = $script:cLang
  switch ($p) {
    'wool'                  { $d.model = "$($cw[$m])_wool"; $d.lang = "tile.cloth.$($cl[$m]).name"; $d.any = 'tile.cloth.name' }
    'stained_hardened_clay' { $d.model = "$($cw[$m])_stained_hardened_clay"; $d.lang = "tile.clayHardenedStained.$($cl[$m]).name"; $d.any = 'tile.clayHardenedStained.name' }
    'stained_glass'         { $d.model = "$($cw[$m])_stained_glass"; $d.lang = "tile.stainedGlass.$($cl[$m]).name"; $d.any = 'tile.stainedGlass.name' }
    'stained_glass_pane'    { $d.model = "$($cw[$m])_stained_glass_pane"; $d.lang = "tile.thinStainedGlass.$($cl[$m]).name"; $d.any = 'tile.thinStainedGlass.name' }
    'carpet'                { $d.model = "$($cw[$m])_carpet"; $d.lang = "tile.woolCarpet.$($cl[$m]).name"; $d.any = 'tile.woolCarpet.name' }
    'concrete'              { $d.model = "$($cw[$m])_concrete"; $d.lang = "tile.concrete.$($cl[$m]).name"; $d.any = $null }
    'concrete_powder'       { $d.model = "$($cw[$m])_concrete_powder"; $d.lang = "tile.concretePowder.$($cl[$m]).name"; $d.any = $null }
    'bed'                   { $d.model = 'bed'; $d.lang = "item.bed.$($cl[$m]).name"; $d.any = 'item.bed.name' }
    'dye'                   { $d.model = "dye_$($script:cDye[$m])"; $d.lang = "item.dyePowder.$($script:cDyeL[$m]).name"; $d.any = 'item.dyePowder.name' }
    'planks'                { $d.model = "$($w[$m])_planks"; $d.lang = "tile.wood.$($wl[$m]).name"; $d.any = 'tile.wood.name' }
    'log'                   { $d.model = "$($w[$m])_log"; $d.lang = "tile.log.$($wl[$m]).name"; $d.any = 'tile.log.name' }
    'log2'                  { $d.model = "$($w[$m + 4])_log"; $d.lang = "tile.log.$($wl[$m + 4]).name"; $d.any = 'tile.log.name' }
    'sapling'               { $d.model = "$($w[$m])_sapling"; $d.lang = "tile.sapling.$($wl[$m]).name"; $d.any = 'tile.sapling.name' }
    'leaves'                { $d.model = "$($w[$m])_leaves"; $d.lang = "tile.leaves.$($wl[$m]).name"; $d.any = 'tile.leaves.name' }
    'leaves2'               { $d.model = "$($w[$m + 4])_leaves"; $d.lang = "tile.leaves.$($wl[$m + 4]).name"; $d.any = 'tile.leaves.name' }
    'wooden_slab'           { $d.model = "$($w[$m])_slab"; $d.lang = "tile.woodSlab.$($wl[$m]).name"; $d.any = 'tile.woodSlab.name' }
    'stone'                 { $n = 'stone','granite','granite_smooth','diorite','diorite_smooth','andesite','andesite_smooth'; $l = 'stone','granite','graniteSmooth','diorite','dioriteSmooth','andesite','andesiteSmooth'; $d.model = $n[$m]; $d.lang = "tile.stone.$($l[$m]).name"; $d.any = 'tile.stone.stone.name' }
    'stonebrick'            { $n = 'stonebrick','mossy_stonebrick','cracked_stonebrick','chiseled_stonebrick'; $l = 'default','mossy','cracked','chiseled'; $d.model = $n[$m]; $d.lang = "tile.stonebricksmooth.$($l[$m]).name"; $d.any = 'tile.stonebricksmooth.name' }
    'prismarine'            { $n = 'prismarine','prismarine_bricks','dark_prismarine'; $l = 'rough','bricks','dark'; $d.model = $n[$m]; $d.lang = "tile.prismarine.$($l[$m]).name"; $d.any = 'tile.prismarine.rough.name' }
    'sand'                  { $n = 'sand','red_sand'; $l = 'default','red'; $d.model = $n[$m]; $d.lang = "tile.sand.$($l[$m]).name"; $d.any = 'tile.sand.name' }
    'dirt'                  { $n = 'dirt','coarse_dirt','podzol'; $l = 'default','coarse','podzol'; $d.model = $n[$m]; $d.lang = "tile.dirt.$($l[$m]).name"; $d.any = 'tile.dirt.name' }
    'sandstone'             { $n = 'sandstone','chiseled_sandstone','smooth_sandstone'; $l = 'default','chiseled','smooth'; $d.model = $n[$m]; $d.lang = "tile.sandStone.$($l[$m]).name"; $d.any = 'tile.sandStone.name' }
    'red_sandstone'         { $n = 'red_sandstone','chiseled_red_sandstone','smooth_red_sandstone'; $l = 'default','chiseled','smooth'; $d.model = $n[$m]; $d.lang = "tile.redSandStone.$($l[$m]).name"; $d.any = 'tile.redSandStone.name' }
    'quartz_block'          { $n = 'quartz_block','chiseled_quartz_block','quartz_column'; $l = 'default','chiseled','lines'; $d.model = $n[$m]; $d.lang = "tile.quartzBlock.$($l[$m]).name"; $d.any = 'tile.quartzBlock.default.name' }
    'stone_slab'            { $n = 'stone_slab','sandstone_slab','oak_slab','cobblestone_slab','brick_slab','stone_brick_slab','nether_brick_slab','quartz_slab'; $l = 'stone','sand','wood','cobble','brick','smoothStoneBrick','netherBrick','quartz'; $d.model = $n[$m]; $d.lang = "tile.stoneSlab.$($l[$m]).name"; $d.any = 'tile.stoneSlab.name' }
    'stone_slab2'           { $d.model = 'red_sandstone_slab'; $d.lang = 'tile.stoneSlab2.red_sandstone.name' }
    'coal'                  { if ($m -eq 1) { $d.model = 'charcoal'; $d.lang = 'item.charcoal.name' } else { $d.model = 'coal'; $d.lang = 'item.coal.name' }; $d.any = 'item.coal.name' }
    'fish'                  { $n = 'cod','salmon','clownfish','pufferfish'; $d.model = $n[$m]; $d.lang = "item.fish.$($n[$m]).raw.name"; $d.any = 'item.fish.cod.raw.name' }
    'cooked_fish'           { $n = 'cod','salmon'; $d.model = "cooked_$($n[$m])"; $d.lang = "item.fish.$($n[$m]).cooked.name"; $d.any = 'item.fish.cod.cooked.name' }
    'golden_apple'          { $d.model = 'golden_apple'; $d.lang = 'item.appleGold.name'; if ($m -eq 1) { $d.note = 'meta 1 = enchanted golden apple; vanilla 1.12 art has no glint here' } }
    'skull'                 { $n = 'skeleton','wither','zombie','char','creeper','dragon'; $d.model = "skull_$($n[$m])"; $d.lang = "item.skull.$($n[$m]).name"; $d.any = 'item.skull.char.name' }
    'potion'                { $d.model = 'bottle_drinkable'; $d.lang = $null; $d.any = 'item.potion.name' }
    'splash_potion'         { $d.model = 'bottle_splash'; $d.any = 'item.splash_potion.name' }
    'lingering_potion'      { $d.model = 'bottle_lingering'; $d.any = 'item.lingering_potion.name' }
    'red_flower'            { $n = 'poppy','blue_orchid','allium','houstonia','red_tulip','orange_tulip','white_tulip','pink_tulip','oxeye_daisy'; $l = 'poppy','blueOrchid','allium','houstonia','tulipRed','tulipOrange','tulipWhite','tulipPink','oxeyeDaisy'; $d.model = $n[$m]; $d.lang = "tile.flower2.$($l[$m]).name"; $d.any = 'tile.flower2.name' }
    'yellow_flower'         { $d.model = 'dandelion'; $d.lang = 'tile.flower1.dandelion.name'; $d.any = 'tile.flower1.name' }
    'tallgrass'             { $n = 'dead_bush','tall_grass','fern'; $l = 'shrub','grass','fern'; $d.model = $n[$m]; $d.lang = "tile.tallgrass.$($l[$m]).name"; $d.any = 'tile.tallgrass.name' }
    'double_plant'          { $n = 'sunflower','syringa','double_grass','double_fern','double_rose','paeonia'; $l = 'sunflower','syringa','grass','fern','rose','paeonia'; $d.model = $n[$m]; $d.lang = "tile.doublePlant.$($l[$m]).name"; $d.any = 'tile.doublePlant.name' }
    'anvil'                 { $n = 'anvil_intact','anvil_slightly_damaged','anvil_very_damaged'; $l = 'intact','slightlyDamaged','veryDamaged'; $d.model = $n[[math]::Min(2, $m)]; $d.lang = "tile.anvil.$($l[[math]::Min(2, $m)]).name" }
    'sponge'                { if ($m -eq 1) { $d.model = 'sponge_wet'; $d.lang = 'tile.sponge.wet.name' } else { $d.model = 'sponge'; $d.lang = 'tile.sponge.dry.name' } }
    'cobblestone_wall'      { if ($m -eq 1) { $d.model = 'mossy_cobblestone_wall'; $d.lang = 'tile.cobbleWall.mossy.name' } else { $d.model = 'cobblestone_wall'; $d.lang = 'tile.cobbleWall.normal.name' } }
    'monster_egg'           { $n = 'stone_monster_egg','cobblestone_monster_egg','stone_brick_monster_egg','mossy_brick_monster_egg','cracked_brick_monster_egg','chiseled_brick_monster_egg'; $l = 'stone','cobble','brick','mossybrick','crackedbrick','chiseledbrick'; $d.model = $n[$m]; $d.lang = "tile.monsterStoneEgg.$($l[$m]).name" }
    default {
      $d.model = if ($script:ModelOverride.ContainsKey($p)) { $script:ModelOverride[$p] } else { $p }
      $d.lang = $script:LangMap[$p]
    }
  }
  return $d
}

function Add-VTint($layers, $p, [int]$m) {      # layers: array of @{tex; uv}; returns tint info or $null
  $t = $script:Tints[$p]; if (-not $t) { return $null }
  if ($t.ContainsKey($m)) { return $t[$m] }
  if ($t.ContainsKey(-1)) { return $t[-1] }
  return $null
}

# -> $null (not a vanilla item id) or @{ key; id; meta; any; name; kind (item|block|custom|none); layers; model; json; tint; flags[] }
function Resolve-Vanilla([string]$key) {
  if ($key -notmatch '^minecraft:([^:]+)(?::(\d+|\*))?$') { return $null }
  $p = $Matches[1].ToLowerInvariant(); $ds = $Matches[2]
  if (Is-VanillaNonItem "minecraft:$p") { return $null }
  $any = ($ds -eq '*'); $m = 0; if ($ds -and $ds -ne '*') { $m = [int]$ds }
  $flags = New-Object System.Collections.ArrayList
  $r = [ordered]@{ key = $key; id = "minecraft:$p"; meta = $m; any = $any; name = $null; kind = 'none'; layers = @(); model = $null; json = $null; tint = $null; flags = $flags }
  $def = $null
  try { $def = Get-VanillaDef $p $m } catch { [void]$flags.Add("bad metadata for $p`: $m"); $def = @{ model = $p; lang = $null; any = $null; note = $null } }
  if ($def.note) { [void]$flags.Add($def.note) }
  # ---- name
  $nm = $null
  if ($script:NameOverride.ContainsKey($p) -and -not $any) { $nm = $script:NameOverride[$p]; [void]$flags.Add('name clarified (vanilla lang name is ambiguous or generic)') }
  elseif ($any -and $script:AnyOverride.ContainsKey($p)) { $nm = $script:AnyOverride[$p] }
  if (-not $nm) {
    if ($p -eq 'potion' -and -not $any) { $nm = if ($m -eq 0) { VLangGet 'potion.effect.water' } else { VLangGet 'item.potion.name' } }
    elseif ($any) { $nm = VLangGet $def.any; if (-not $nm -and $def.lang) { $nm = VLangGet $def.lang; [void]$flags.Add('wildcard: used data-0 name') } }
    else { $nm = VLangGet $def.lang }
  }
  if (-not $nm) {
    # last resort: item.<camel>.name / tile.<camel>.name, then humanized registry path
    $camel = ($p -split '_' | % { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
    $camel = $camel.Substring(0, 1).ToLower() + $camel.Substring(1)
    $nm = (VLangGet "item.$camel.name"); if (-not $nm) { $nm = VLangGet "tile.$camel.name" }
    if ($nm) { [void]$flags.Add('name from camelCase lang guess') }
    else { $nm = (($p -split '_' | % { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ' '); [void]$flags.Add('GUESSED name (no lang key)') }
  }
  $r.name = $nm
  # ---- art
  $mn = $def.model
  $tint = Add-VTint $null $p $m
  if ($any -and $p -eq 'potion') { $tint = $script:Tints['potion'][-1] }
  $r.tint = $tint
  $chain = $null
  if ($mn) { $chain = Resolve-ModelChain 'minecraft' "item/$mn" }
  if ($mn -and $script:EntityStandIn.ContainsKey($p) -and $chain -and $chain.found -and $chain.builtin -eq 'builtin/entity') {
    $r.kind = 'custom'; $r.json = $script:EntityStandIn[$p]; [void]$flags.Add('GUESSED art: builtin/entity item (TileEntity renderer), hand-made stand-in model')
    return $r
  }
  if (-not $chain -or -not $chain.found) { [void]$flags.Add("item model not found: models/item/$mn.json"); return $r }
  $r.model = "item/$mn"
  if ($chain.builtin -eq 'item/generated') {
    $ls = @(Item-Layers $chain)
    if (-not $ls.Count) { [void]$flags.Add('item model has no layers'); return $r }
    $out = @()
    for ($i = 0; $i -lt $ls.Count; $i++) {
      $l = @{ tex = $ls[$i].tex; uv = $null; tint = $null }
      if ($tint -and ($tint.layer -eq $i -or $tint.layer -eq -1)) { $l.tint = $tint.rgb }
      if (-not $l.tex.file) { [void]$flags.Add("texture missing: $($l.tex.ns):$($l.tex.path)") }
      $out += , $l
    }
    $r.layers = $out; $r.kind = 'item'
    return $r
  }
  if ($chain.builtin -eq 'builtin/entity') { [void]$flags.Add('builtin/entity item without stand-in model'); return $r }
  if ($chain.elements) {
    $bt = Block-JsonTexture $chain
    if ($bt) {
      $l = @{ tex = $bt.tex; uv = $null; tint = $null }
      if ($tint) { $l.tint = $tint.rgb }
      if (-not $l.tex.file) { [void]$flags.Add("texture missing: $($l.tex.ns):$($l.tex.path)") }
      $r.layers = @($l)
    }
    $r.kind = 'block'
    return $r
  }
  [void]$flags.Add("item model has neither layers nor elements (builtin=$($chain.builtin), missingParent=$($chain.missingParent))")
  return $r
}
