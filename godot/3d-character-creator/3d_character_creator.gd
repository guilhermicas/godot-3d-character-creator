@tool
extends Node3D

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


func _scan_component(path: String) -> CharacterComponent:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open: " + path)
		return null

	var comp := CharacterComponent.new()
	comp.name = path.get_file()

	# Find .glb
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if not dir.current_is_dir() and f.ends_with(".glb"):
			comp.glb_path = path.path_join(f)
	dir.list_dir_end()

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
