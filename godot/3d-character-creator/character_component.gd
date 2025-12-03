
@tool
extends Resource
class_name CharacterComponent

@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Properties
@export var children: Array[CharacterComponent] = []

var instanced_model: PackedScene = null
