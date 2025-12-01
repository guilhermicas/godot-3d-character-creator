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
		comp.glb_path = path.path_join(glb_file)

		var glb_scene: PackedScene = load(comp.glb_path)
		if glb_scene:
			var inst: Node = glb_scene.instantiate()

			# Imported GLB scenes always have the real object under a wrapper:
			var root: Node = inst.get_child(0)

			if root.has_meta("extras"):
				var extras = root.get_meta("extras")
				if extras.has("CC_id"):
					comp.cc_id = extras["CC_id"]

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
