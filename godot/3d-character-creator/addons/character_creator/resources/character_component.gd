@tool
extends Resource
class_name CharacterComponent

## Represents a character component (either a container or an actual model).
##
## FIELD USAGE BY NODE TYPE:
##
## CC_ (Actual Component - has GLB model):
##   - name: Folder name (e.g., "CC_male")
##   - glb_path: Path to 3D model file
##   - cc_id: Unique identifier
##   - display_name: User-facing label (editable)
##   - metadata: Custom data (e.g., albedo overrides)
##   - children: EMPTY (leaf nodes)
##   - instanced_model: Cached GLB PackedScene
##
## CCC_ (Container - organizes components):
##   - name: Folder name (e.g., "CCC_genders")
##   - glb_path: EMPTY (containers don't have models)
##   - cc_id: Unique identifier
##   - display_name: User-facing label (editable)
##   - metadata: EMPTY (not used for containers)
##   - children: Array of child components
##   - instanced_model: EMPTY (containers don't have models)
##
## BOTH types use:
##   - name, cc_id, display_name, metadata
##
## ONLY CC_ uses:
##   - glb_path, instanced_model
##
## ONLY CCC_ uses:
##   - children (non-empty array)

# Read-only model data (from folder/file scan)
@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Editable configuration (saved to global_config.tres or local_config.tres)
@export_group("Configuration")
@export var display_name: String = ""
@export var metadata: Dictionary = {}

# TODO: Future features (Phase 4 - Defaults & Mandatory):
# @export var default_child_id: String = ""  # CCC_ only: which child to pre-select
# @export var is_child_mandatory: bool = false  # CCC_ only: must pick ≥1 child

# Hierarchy
@export var children: Array[CharacterComponent] = []

var instanced_model: PackedScene = null  # Not exported, transient runtime data

# Assemble hierarchical tree from flat array using global_config as authority
static func assemble_from_global(
	flat_items: Array[CharacterComponent],
	global_config: CharacterComponent
) -> CharacterComponent:
	var override_map := {}
	for item in flat_items:
		if item.cc_id != "":
			override_map[item.cc_id] = item
	
	return _assemble_recursive(global_config, override_map)

static func _assemble_recursive(
	source: CharacterComponent,
	override_map: Dictionary
) -> CharacterComponent:
	# Filter out CC_ nodes (actual components) not in local config
	# But keep CCC_ nodes (containers) - they define structure
	var is_component := source.glb_path != ""  # CC_ nodes have GLB paths
	if is_component and not override_map.has(source.cc_id):
		return null
	
	# Create copy with overrides
	var result := CharacterComponent.new()
	result.name = source.name
	result.glb_path = source.glb_path
	result.cc_id = source.cc_id
	result.display_name = source.display_name
	result.metadata = source.metadata.duplicate()
	
	# Apply local overrides
	if source.cc_id != "" and override_map.has(source.cc_id):
		var override: CharacterComponent = override_map[source.cc_id]
		if override.display_name != "":
			result.display_name = override.display_name
		if not override.metadata.is_empty():
			result.metadata = override.metadata.duplicate()
	
	# Recursively process children
	for child in source.children:
		var assembled := _assemble_recursive(child, override_map)
		if assembled:
			result.children.append(assembled)
	
	return result
