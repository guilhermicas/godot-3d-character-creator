# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A 3D character creator system for Godot that bridges Blender modeling with Godot runtime customization. Characters are structured in Blender with a `CC_`/`CCC_` naming convention, exported as GLB files via a Blender addon, then loaded in Godot through a plugin that provides both editor tools and runtime UI for character customization.

## Dual Codebase Structure

This repository contains TWO separate but interconnected codebases:

### Blender Side (`/blender`)
- **Language**: Python (Blender addon)
- **Main file**: [cc_exporter_addon.py](blender/cc_exporter_addon.py)
- **Purpose**: Export structured character models to GLB format with UUID tracking
- **Key concept**: Walks object hierarchy and exports `CC_`/`CCC_` prefixed objects individually

### Godot Side (`/godot/3d-character-creator`)
- **Language**: GDScript (Godot 4.x addon)
- **Entry point**: [character_creator_plugin.gd](godot/3d-character-creator/addons/character_creator/character_creator_plugin.gd)
- **Purpose**: Editor tools + runtime character creator UI
- **Key concept**: Scans exported GLBs, builds hierarchical configs, provides runtime customization

## Character Structure System

The `CC_`/`CCC_` naming convention defines the entire character hierarchy:

- **`CCC_*`** (Container): Collections/categories (e.g., `CCC_genders`, `CCC_shirts`)
  - Have children
  - Define selection rules (`is_child_mandatory`, `allow_multiple_selection`, `default_child_id`)
  - No GLB model themselves

- **`CC_*`** (Component): Actual 3D models (e.g., `CC_male`, `CC_t_shirt`)
  - Have GLB files exported from Blender
  - Are leaf nodes (no children in typical cases)
  - Each has unique `CC_id` (8-char UUID fragment) for identity tracking

Example hierarchy:
```
CCC_genders/
├── CC_male_CC_id_a1b2c3d4/
│   ├── CC_male.glb
│   └── CCC_shirts_CC_id_e5f6g7h8/
│       ├── CC_t_shirt_CC_id_i9j0k1l2/
│       │   └── CC_t_shirt.glb
│       └── CC_tank_top_CC_id_m3n4o5p6/
│           └── CC_tank_top.glb
└── CC_female_CC_id_q7r8s9t0/
    └── CC_female.glb
```

## Core Resource Types

### CharacterComponent ([character_component.gd](godot/3d-character-creator/addons/character_creator/resources/character_component.gd))
The central data structure representing both containers and components:
- **Read-only fields** (from Blender scan): `name`, `glb_path`, `cc_id`
- **Editable fields** (user config): `display_name`, `metadata`, `default_child_id`, `is_child_mandatory`, `allow_multiple_selection`
- **Hierarchy**: `children` array for tree structure
- **Runtime**: `instanced_model` cached PackedScene

Key method: `assemble_from_global()` - Rebuilds hierarchical tree from flat array using global config as authority.

### LocalConfig ([local_config.gd](godot/3d-character-creator/addons/character_creator/resources/local_config.gd))
Stores a flat array of CharacterComponents. Used for:
- Saved player characters (`characters/` folder)
- Shop inventories (filtered subsets of global config)
- Presets

### Global Config
The authoritative source scanned from Blender exports. Located at `{blender_export_path}/global_config.tres`. Contains the complete hierarchy of all available components.

## Configuration Flow

1. **Blender Export** → Folder structure with GLBs + UUIDs
2. **Editor Rescan** → Walks folders, builds `global_config.tres` with full hierarchy
3. **Local Configs** → Filtered/customized subsets created via editor dock
4. **Runtime Loading** → `CharacterComponent.assemble_from_global(flat_items, global_config)` rebuilds tree

## Key Nodes

### CCharacter ([c_character.gd](godot/3d-character-creator/addons/character_creator/resources/c_character.gd))
Attach to player for persistent character management:
- Auto-loads/saves character from `{characters_dir}/{parent_name}.tres`
- Validates character on load (filters orphaned components)
- `get_character_config()` → flat array of current character
- `apply_character_config(config)` → saves and rebuilds mesh
- `_rebuild_mesh()` → instantiates GLBs with proper hierarchy using `assemble_from_global()`

### 3DCharacterCreator ([3d_character_creator.gd](godot/3d-character-creator/addons/character_creator/resources/3d_character_creator.gd))
The runtime UI scene for character customization. Two modes:

**Standalone Mode** (`standalone_mode = true`):
- Requires `local_config_path`
- Shows export button to save characters
- UI always visible

**Interactive Mode** (default):
- Call `enter_with_character(Array[CharacterComponent])`
- Shows Done/Cancel buttons
- Emits `character_saved(config)` or `character_cancelled()`
- Used for in-game character creators

Important export vars:
- `hide_definitive_base_model`: Skip root CCC selection if user already has a valid base model (for shops)
- `grid_columns`: Layout columns for item grids
- `custom_loading_indicator`: Optional shader/texture for async loading

## Blender Workflow

### Installing the Addon
1. Open Blender preferences → Add-ons → Install
2. Select [blender/cc_exporter_addon.py](blender/cc_exporter_addon.py)
3. Enable "3D Character Creator Exporter"

### Structuring Characters
1. Create top-level `CCC_` collection (e.g., `CCC_genders`)
2. Add `CC_` child objects (actual models)
3. Nest `CCC_` collections under `CC_` objects as needed
4. Use exactly **one** top-level `CCC_` object

### Exporting
1. Open side panel "CC Exporter" tab (3D View → N panel)
2. Set export path (recommend outside Godot project, to avoid re-imports)
3. Enable "Delete and recreate" to avoid stale files
4. Click "Export"
5. Addon assigns 8-char `CC_id` UUIDs to all `CC_`/`CCC_` objects
6. Exports to folder structure: `{export_path}/character_config/CCC_*/CC_*/model.glb`

**CRITICAL**: Windows has 260-char max path length. Keep names short if exporting on Windows.

## Godot Workflow

### Setting Up the Plugin
1. Copy `godot/3d-character-creator/addons/character_creator/` to your project's `res://addons/`
2. Enable plugin: Project → Project Settings → Plugins → Character Creator
3. Open bottom panel "Character Creator"
4. Set Blender export path to where you exported (e.g., `res://assets/character_config/`)
5. Click "Rescan" to build `global_config.tres`

### Creating Local Configs (Shop Inventories)
1. Switch to "Local Configs" tab
2. Click "New Local Config"
3. Use tree checkboxes to filter which components are available
4. Save to a `.tres` file

### Runtime Usage - Simple
1. Add `3DCharacterCreator` node to scene
2. Set `local_config_path` to a local config `.tres`
3. Set `standalone_mode = true`
4. Run scene → character creator UI appears

### Runtime Usage - In-Game Interaction
```gdscript
# Player scene has CCharacter node
var character_creator = preload("res://addons/character_creator/3d_character_creator.tscn").instantiate()
add_child(character_creator)

# When player enters customization area
var current_char = $CCharacter.get_character_config()
character_creator.enter_with_character(current_char)

# Connect signals
character_creator.character_saved.connect(func(config):
    $CCharacter.apply_character_config(config)
)
```

See [example_usages/02_player_interaction](godot/3d-character-creator/addons/character_creator/example_usages/02_player_interaction) for full example.

## Important Paths & Settings

### ProjectSettings
The plugin stores the Blender export path in:
```gdscript
ProjectSettings.get_setting("character_creator/blender_export_path")
```

### File Structure
Given `blender_export_path = "res://assets/character_config"`:
- Global config: `res://assets/character_config/global_config.tres`
- Characters folder: `res://assets/character_config/characters/` (gitignored)
- Character save: `res://assets/character_config/characters/{name}.tres`
- GLB folders: `res://assets/character_config/CCC_*/CC_*/model.glb`

## Caching & Performance

### GLBCache ([GLB_cache.gd](godot/3d-character-creator/addons/character_creator/resources/GLB_cache.gd))
Singleton autoload that caches loaded GLB PackedScenes by `cc_id`:
- `cache(cc_id, packed_scene)` - Store
- `get_cached(cc_id)` - Retrieve
- `evict_except(used_ids)` - Free unused GLBs from memory

The UI uses threaded loading (`ResourceLoader.load_threaded_request()`) for async GLB loading with loading spinners.

## Future Architecture - Skeleton & Animation System

The [docs/](docs/) folder contains design documents for a planned skeleton/animation system:

- **Multiple skeleton archetypes** (humanoid, arachnid, etc.) as separate rigs
- **Bone scale profiles** per mesh variant (e.g., female mesh scales humanoid skeleton slightly)
- **Animation ownership** via role + mesh override system
- **Animation orchestrator** resolves animations at character load based on skeleton + mesh
- **Custom AnimationTree** that operates on semantic roles, not concrete animation names

This is **not yet implemented** but influences the current architecture (why `assemble_from_global()` exists, why hierarchy is authoritative).

## Common Gotchas

1. **Always use `assemble_from_global()`** when rebuilding character hierarchy from flat arrays. Don't manually reconstruct trees.

2. **CC_ids are identity, not names**: Characters save `cc_id` references. Renaming in Blender preserves identity via UUID.

3. **Local configs are filters, not replacements**: They subset global config, not define new structure.

4. **Depth-based selection in UI**: Single-select containers replace selection at same depth and deeper. Multi-select containers append/remove from flat array.

5. **Mandatory containers**: If `is_child_mandatory = true`, must have `default_child_id` set. Editor validates this.

6. **Blender export cleanup**: The addon only deletes `CC_`/`CCC_` folders when "Delete and recreate" is enabled. Preserves `characters/`, `*.tres` files.

7. **Path resolution**: Use `ConfigLoader.get_export_path()` and related utilities for consistent path handling.

## Testing & Debugging

Run example scenes:
- `addons/character_creator/example_usages/01_simplest/example_scene.tscn` - Basic UI
- `addons/character_creator/example_usages/02_player_interaction/world.tscn` - Full interaction system

Check console for:
- `[CC Exporter]` prefixed Blender logs
- `CCharacter:` prefixed character loading logs
- `ConfigLoader:` prefixed path/config errors

## Code Style Notes

- **GDScript**: Uses type hints extensively (`var x: Type`), `@tool` for editor scripts
- **Resource serialization**: CharacterComponent has explicit `copy_fields()` for safe copying (doesn't copy `children` or `instanced_model`)
- **Validation**: `validate_defaults()` method auto-fixes invalid configs with warnings
- **Editor integration**: Plugin uses bottom panel dock, EditorSettings for persistence
