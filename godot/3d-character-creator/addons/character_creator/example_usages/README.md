# Character Creator - Example Usages

This folder contains example scenes demonstrating how to use the Character Creator addon.

## Folder Structure

```
example_usages/
├── character_config/          # Shared character assets
│   ├── global_config.tres     # Global config (scanned from Blender)
│   ├── *.tres                 # Local configs (presets)
│   ├── characters/            # Saved player characters (gitignored)
│   └── CCC_*_CC_id_*/         # GLB models exported from Blender
├── 01_simplest/               # Basic usage example
└── 02_player_interaction/     # Full player interaction demo
```

## Examples

### 01_simplest
**What it shows:** Basic character creator scene with pre-configured local config.

**How to use:**
1. Open `01_simplest/example_scene.tscn`
2. Run the scene
3. Select different character components from the UI

**Key concepts:**
- Placing a `3d_character_creator` instance in your scene
- Configuring it with a `local_config_path`

### 02_player_interaction
**What it shows:** Player character with interaction system to enter/exit character creator.

**How to use:**
1. Open `02_player_interaction/world.tscn`
2. Run the scene
3. Use arrow keys to move the player
4. Walk up to the cube and press **E** to enter the character creator
5. Select character components
6. Press the "Done" button to exit and apply changes
7. The character mesh updates on the player automatically

**Key concepts:**
- `CCharacter` node attached to player (auto-loads/saves character)
- Interaction cube with Area3D to detect player
- `enter_with_character()` and `character_saved` signal
- Disabling player movement while in creator
- Character meshes auto-build with proper hierarchy

## Character Config

The `character_config/` folder contains all character assets:

- **global_config.tres**: Scanned from Blender exports, defines the full hierarchy
- **Local configs** (e.g., `fancy_shop.tres`): Presets/filtered subsets of available components
- **characters/**: Runtime-saved player characters (not tracked in git)
- **GLB folders**: Exported 3D models from Blender

## Getting Started

1. Configure the Blender export path in the editor plugin (bottom panel: "Character Creator")
2. Click "Rescan" to build the global config from your Blender exports
3. Create local configs using the "Local Configs" tab
4. Use the example scenes as templates for your game

For more information, see the main addon documentation.
