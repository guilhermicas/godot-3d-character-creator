@tool
extends Node3D

## ------------------ Godot's Inspector Logic for Configuration ------------------
@export_dir var blender_export_path: String:
	set(value):
		blender_export_path = value
		_rebuild_tree()

@export var root: CharacterComponent

func _rebuild_tree():
	if not Engine.is_editor_hint():
		return

	if blender_export_path == "" or not DirAccess.dir_exists_absolute(blender_export_path):
		root = null
		return

	root = _scan_component(blender_export_path)
	notify_property_list_changed()  # forces inspector refresh

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
	comp.name = path.get_file()

	# Find .glb
	var glb_file := ""
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if not dir.current_is_dir() and f.ends_with(".glb"):
			glb_file = f
	dir.list_dir_end()

	if glb_file != "":
		# Read CC_id without instancing a PackedScene from .glb
		comp.glb_path = path.path_join(glb_file)
		
		var gltf_state := GLTFState.new()
		
		var error = GLTFDocument.new().append_from_file(comp.glb_path, gltf_state)
		if error == OK:
			var json_data = gltf_state.get_json()
			if json_data.has("nodes"):
				for node_data in json_data["nodes"]:
					if node_data.has("extras") and node_data["extras"].has("CC_id"):
						comp.cc_id = node_data["extras"]["CC_id"]
						break  # Found it, stop searching

	# Recurse into CC_/CCC_ folders
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if dir.current_is_dir() and (f.begins_with("CC_") or f.begins_with("CCC_")):
			var child := _scan_component(path.path_join(f))
			if child != null:
				comp.children.append(child)
	dir.list_dir_end()

	return comp
