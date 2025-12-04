@tool
extends Node3D

## ------------------ Godot's Inspector Logic for Configuration ------------------
@export_dir var blender_export_path: String:
	set(value):
		blender_export_path = value
		_rebuild_tree()

@export var global_config: CharacterComponent

# Loaded global config data
# TODO: i notice in the .tscn of this scene, that global config is being saved there
#       is there a need for saving the things to JSON since the editor itself already
#	    stores these values?
var _global_config_file: Dictionary = {}
var _loading: bool = false

func _ready(): if Engine.is_editor_hint(): _load_config()

func _rebuild_tree():
	if not Engine.is_editor_hint(): return

	if blender_export_path == "" or not DirAccess.dir_exists_absolute(blender_export_path):
		global_config = null
		return

	_global_config_file = _load_config() # Dictionary representation of global_config.json
	global_config = _scan_component(blender_export_path)
	notify_property_list_changed()

func _load_config() -> Dictionary:
	_loading = true

	var config_path := blender_export_path.path_join("global_config.json")
	if not FileAccess.file_exists(config_path):
		_loading = false
		return {}

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open config: " + config_path)
		_loading = false
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("JSON parse error in global_config.json: " + json.get_error_message())
		_loading = false
		return {}

	_loading = false
	return json.data

func _save_config():
	if _loading or not Engine.is_editor_hint(): return

	if blender_export_path == "" or global_config == null: return

	var config_path := blender_export_path.path_join("global_config.json")

	var data := {
		"items": {}
		# TODO: in the future, user may configure categories/tags, or maybe more dynamically what they want
		#       so it can be configured for sorting and association with models
	}

	# Collect all items from tree
	_collect_items_recursive(global_config, data["items"])

	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write config: " + config_path)
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Saved global_config.json")

func _collect_items_recursive(comp: CharacterComponent, items: Dictionary):
	if comp.cc_id != "":
		items[comp.cc_id] = {
			"display_name": comp.display_name,
			"metadata": comp.metadata.duplicate()
		}

	for child in comp.children: _collect_items_recursive(child, items)

## ------------------ Functions below can be used by users to make their own UI ------------------
# TODO: document these functions
# TODO: maybe for a user to use these, we need to set a class_name on top of the file
#       so this file can be referenced on other files

func _scan_component(path: String) -> CharacterComponent:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open: " + path)
		return null

	var comp := CharacterComponent.new()
	comp._parent_node = self # TODO: if we use signal, this isnt needed
	
	var folder_name := path.get_file()
	
	# Extract CC_id from folder name (e.g., "CC_male_CC_id_9efe906c" -> "9efe906c")
	if folder_name.contains("_CC_id_"):
		var parts := folder_name.split("_CC_id_")
		comp.name = parts[0]  # e.g., "CC_male"
		comp.cc_id = parts[1] if parts.size() > 1 else ""
	else:
		comp.name = folder_name
		comp.cc_id = ""

	# Load global_config.json configuration for this CC_id
	if comp.cc_id != "" and _global_config_file.has("items") and _global_config_file["items"].has(comp.cc_id):
		var item_data: Dictionary = _global_config_file["items"][comp.cc_id]
		if item_data.has("display_name") and item_data["display_name"] != null: comp.display_name = item_data["display_name"]
		if item_data.has("metadata") and item_data["metadata"] != null: comp.metadata = item_data["metadata"].duplicate()

	# Find .glb file (for CC_ components, not CCC_ collections)
	var glb_file := ""
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "": break
		if not dir.current_is_dir() and f.ends_with(".glb"):
			glb_file = f
			break
	dir.list_dir_end()

	if glb_file != "": comp.glb_path = path.path_join(glb_file)

	# Recurse into CC_/CCC_ folders
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "": break
		if dir.current_is_dir() and (f.begins_with("CC_") or f.begins_with("CCC_")):
			var child := _scan_component(path.path_join(f))
			if child != null: comp.children.append(child)
	dir.list_dir_end()

	return comp
