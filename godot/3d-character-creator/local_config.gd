# Local configuration for character creator
# Stores a filtered/customized subset of global_config as a flat array
# Saved as .tres file, can be shared across multiple scenes
class_name LocalConfig extends Resource

# Flat storage - saves to disk without hierarchy
@export var items: Array[CharacterComponent] = []

# TODO: Future configuration flags
# @export var allow_empty_selections: bool = true
# @export var defaults: Dictionary = {}  # cc_id -> bool (auto-select on init)
# @export var mandatory: Dictionary = {}  # cc_id -> bool (can't deselect)

# Flatten a hierarchical tree into a flat array for saving
static func flatten_tree(tree: CharacterComponent) -> Array[CharacterComponent]:
	var result: Array[CharacterComponent] = []
	_flatten_recursive(tree, result)
	return result

static func _flatten_recursive(node: CharacterComponent, result: Array[CharacterComponent]) -> void:
	if node.cc_id != "":
		# Store full component (allows overrides of display_name, metadata, etc.)
		var flat := CharacterComponent.new()
		flat.cc_id = node.cc_id
		flat.name = node.name
		flat.glb_path = node.glb_path
		flat.display_name = node.display_name
		flat.metadata = node.metadata.duplicate()
		# NOTE: children array is NOT saved (reconstructed from global_config)
		# NOTE: instanced_model is NOT saved (transient runtime data)
		result.append(flat)
	
	for child in node.children:
		_flatten_recursive(child, result)

# Deep copy a tree for creating new local configs
static func deep_copy_tree(source: CharacterComponent) -> CharacterComponent:
	return source.duplicate(true)
