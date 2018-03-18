The purpose of this is to provide documentation to anything required to create a custom tree. Any undocumented keys are either not required or documented elsewhere.

## Sapling
Required for planting a tree manually.

### Blockstate
**Path:** `fs/assets/almura/blockstates/sapling/SAPLING_NAME.json`
```javascript
{
    "forge_marker": 1,
    "defaults": {
        "model": "almura:SAPLING_NAME",
        "transform": "forge:default-block"
    },

    "variants": {
        "inventory": [{}],
        // Stages of the sapling growth life
        "stage": {
            // Stage when not grown yet
            "0": {
                // Model to be used during this stage
                "model": "almura:SAPLING_NAME"
            },
            // Stage when grown into a tree, technically isn't seen as a tree generates at this stage currently.
            "1": {
                // Model to be used during this stage
                "model": "almura:SAPLING_NAME"
            }
        }
    }
}
```

### Content
**Path:** `fs/assets/almura/content/block/sapling/SAPLING_NAME.json`
```javascript
{
    "material": "minecraft:rock",
    "map_color": "minecraft:stone",
    "item_group": "almura:crop",
    // States of the block
    "state": {
        "normal": {
            // The tree to map to, this must match the filename without the trailing `.json`
            "tree": "almura:TREE_NAME",
            "hardness": 1.25,
            "resistance": 1000.0
        }
    }
}
```

### Model
**Path:** `fs/assets/almura/models/block/SAPLING_NAME.json`
```javascript
{
    "parent": "block/cross",
    "textures": {
        "cross": "blocks/stone"
    }
}
```

## Log
The log of the tree

### Blockstate
**Path:** `fs/assets/almura/blockstates/log/LOG_NAME.json`
```javascript
{
    "forge_marker": 1,
    "defaults": {
        "model": "almura:LOG_MODEL.obj",
        "transform": "forge:default-block"
    },
    "variants": {
        "inventory": [{}],
        // Axis of the log
        "axis": {
            "x": {},
            "y": {},
            "z": {},
            "none": {}
        }
    }
}
```

### Content
**Path:** `fs/assets/almura/content/block/log/LOG_NAME.json`
```javascript
{
    "material": "minecraft:rock",
    "map_color": "minecraft:stone",
    "item_group": "almura:crop",
    "state": {
        "normal": {
            "resistance": 10.0
        }
    }
}
```

## Leaf
The leaf of the tree

### Blockstate
**Path:** `fs/assets/almura/blockstates/leaf/LEAF_NAME.json`
```javascript
{
    "forge_marker": 1,
    "defaults": {
        "model": "almura:LEAF_MODEL.obj",
        "transform": "forge:default-block"
    },
    "variants": {
        "inventory": [{}],
        "normal": [{}]
    }
}
```

### Content
**Path:** `fs/assets/almura/content/block/leaf/LEAF_NAME.json`
```javascript
{
    "material": "minecraft:rock",
    "map_color": "minecraft:stone",
    "item_group": "almura:crop",
    "state": {
        "normal": {
            "resistance": 10.0
        }
    }
}
```

## Tree
The specifics of the tree itself

### Content
**Path:** `fs/assets/almura/content/tree/TREE_NAME.json`
```javascript
{
    "height": [
        // Specifies the biome the settings apply to, can be specific to a biome or to a domain
        {
            "biome": [
                "minecraft",
                "terraincontrol"
            ],
            // The minimum height of the tree trunk
            "min": 5,
            // The variance applied to the minimum height (min+/-)
            "variance": {
                "min": 0,
                "max": 5
            }
        },
        // Defaults for non-biome specific settings
        {
            "min": 5,
            "variance": {
                "min": 0,
                "max": 5
            }
        }
    ],
    // The log of the tree, used for the trunk. This doesn't need to be a true log, a normal block could be used without issue.
    "log": "almura:log/LOG_NAME",
    // The leaves of the tree.  This doesn't need to be a true leaf, a normal block could be used without issue.
    "leaves": "almura:leaf/LEAF_NAME",
    // The fruit of the tree
    "fruit": {
        // The block to use for the fruit
        "block": "minecraft:stone",
        // Chance of generation, 0-100 scale.
        "chance": [
            // Biome specific chance of generating
            {
                "biome": [
                    "minecraft",
                    "terraincontrol"
                ],
                "min": 5,
                "max": 20
            },
            // Global chance of generating
            {
                "min": 30,
                "max": 40
            }
        ]
    },
    // Hanging fruit of the tree
    "hanging": {
        // The block to use for hanging fruit
        "block": "minecraft:glowstone",
        // Chance of generation, 0-100 scale.
        "chance": [
            // Biome specific chance of generating
            {
                "biome": [
                    "minecraft",
                    "terraincontrol"
                ],
                "min": 5,
                "max": 20
            },
            // Global chance of generating
            {
                "min": 30,
                "max": 40
            }
        ]
    }
}
```

## Generation
Defines how the tree generates

### Content
**Path:** `fs/assets/almura/content/generation/feature/tree/TREE_NAME.json`
```javascript
{
    // Tree used for generation
    "tree": "almura:TREE_NAME",
    // Worlds this generation applies to. Only applies to worlds that have tree generation. If this isn't specified then it will apply to all worlds with tree generation
    "worlds": [
        "test",
        "world"
    ],
    // The block(s) required for placement during generation. Can either be a single block or multiple. If not specified it will default to vanilla logic for requirement.
    "requires": "minecraft:water",
    // Chance of generation, 0-100 scale.
    "chance": [
        // Biome specific chance of generating
        {
            "biome": [
                "minecraft:forest",
                "terraincontrol"
            ],
            "min": 0,
            "max": 10
        },
        // Global chance of generating
        {
            "min": 0,
            "max": 10
        }
    ]
}
```