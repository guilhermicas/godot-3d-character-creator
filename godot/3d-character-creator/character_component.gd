@tool
extends Resource
class_name CharacterComponent

# Read-only model data (from folder/file scan)
@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Editable configuration (saved to global_config.json)
@export_group("Configuration")
@export var display_name: String = "":
	set(value):
		display_name = value
		emit_changed()

@export var metadata: Dictionary = {}:
	set(value):
		metadata = value
		emit_changed()

# Hierarchy
@export var children: Array[CharacterComponent] = []

var instanced_model: PackedScene = null

# Reference to parent node for saving
# TODO: should this below be a signal?
var _parent_node: Node = null

func _init():
	changed.connect(_on_changed)

func _on_changed():
	if _parent_node and _parent_node.has_method("_save_config"):
		_parent_node._save_config()
