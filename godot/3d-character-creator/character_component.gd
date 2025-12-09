@tool
extends Resource
class_name CharacterComponent

# Read-only model data (from folder/file scan)
@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Editable configuration (saved to global_config.tres or local_config.tres)
@export_group("Configuration")
@export var display_name: String = ""
@export var metadata: Dictionary = {}

# TODO: Future local config features (add when implementing):
# @export var allow_empty: bool = false  # Show "Empty" option in CCC_
# @export var is_default: bool = false  # Auto-select on character creation
# @export var is_mandatory: bool = false  # Can't deselect
# @export var allow_material_edit: bool = false  # Enable albedo/material customization

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
	# Filter out nodes not in local config
	if source.cc_id != "" and not override_map.has(source.cc_id):
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
