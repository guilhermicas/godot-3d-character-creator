@tool
extends Resource
class_name CharacterComponent

# Read-only model data (from folder/file scan)
@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Editable configuration (saved to global_config.tres)
@export_group("Configuration")
@export var display_name: String = ""
@export var metadata: Dictionary = {}

# Hierarchy
@export var children: Array[CharacterComponent] = []

var instanced_model: PackedScene = null
