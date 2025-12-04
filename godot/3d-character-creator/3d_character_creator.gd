@tool
extends Node3D

## ------------------ Godot's Inspector Logic for Configuration ------------------
@export_dir var blender_export_path: String:
	set(value):
		blender_export_path = value
		_rebuild_tree()

@export var global_config: CharacterComponent

func _rebuild_tree() -> void:
	if not Engine.is_editor_hint(): return

	if blender_export_path == "" or not DirAccess.dir_exists_absolute(blender_export_path):
		global_config = null
		return

	# All store instances point to the same tres file
	# Godot already handles edits made on the Inspector window
	# So we just have a "pointer" from all scenes to the same tres Resource
	var config_path := blender_export_path.path_join("global_config.tres")

	# Load existing config or create new one
	if FileAccess.file_exists(config_path):
		global_config = load(config_path)
		if global_config == null:
			push_error("Failed to load global_config.tres")
			global_config = CharacterComponent.new()
	else:
		global_config = CharacterComponent.new()

	# Scan filesystem and merge with existing config
	var scanned_tree := _scan_component(blender_export_path)
	_merge_scanned_into_config(global_config, scanned_tree)

	# Save the updated config
	var save_result := ResourceSaver.save(global_config, config_path)
	if save_result != OK: push_error("Failed to save global_config.tres")

	notify_property_list_changed()

## ------------------ Merge Logic: Preserve user edits, update file system data ------------------

func _merge_scanned_into_config(existing: CharacterComponent, scanned: CharacterComponent) -> void:
	"""
	Merges scanned filesystem data into existing config:
	- Updates read-only fields (name, glb_path, cc_id) from scan
	- Preserves user-editable fields (display_name, metadata)
	- Adds new items, removes missing items
	"""
	
	# Update read-only fields from scan
	existing.name = scanned.name
	existing.glb_path = scanned.glb_path
	existing.cc_id = scanned.cc_id

	# Build a map of existing children by cc_id for quick lookup
	var existing_children_map := {}
	for child in existing.children:
		if child.cc_id != "":
			existing_children_map[child.cc_id] = child

	# Build new children array by merging scanned with existing
	var merged_children: Array[CharacterComponent] = []

	for scanned_child in scanned.children:
		if scanned_child.cc_id != "" and existing_children_map.has(scanned_child.cc_id):
			# Item exists: merge recursively to preserve edits
			var existing_child: CharacterComponent = existing_children_map[scanned_child.cc_id]
			_merge_scanned_into_config(existing_child, scanned_child)
			merged_children.append(existing_child)
			existing_children_map.erase(scanned_child.cc_id)  # Mark as processed
		else:
			# New item: use scanned data as-is
			merged_children.append(scanned_child)

	# Note: Items in existing_children_map that weren't processed are now removed
	# (they no longer exist in the filesystem)

	existing.children = merged_children

## ------------------ Filesystem Scanning ------------------

func _scan_component(path: String) -> CharacterComponent:
	"""
	Scans filesystem and creates a fresh component tree.
	Does NOT look at existing config - that's handled by _merge_scanned_into_config.
	"""
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open: " + path)
		return null

	var comp := CharacterComponent.new()
	
	var folder_name := path.get_file()

	# Extract CC_id from folder name (e.g., "CC_male_CC_id_9efe906c" -> "9efe906c")
	if folder_name.contains("_CC_id_"):
		var parts := folder_name.split("_CC_id_")
		comp.name = parts[0]  # e.g., "CC_male"
		comp.cc_id = parts[1] if parts.size() > 1 else ""
	else:
		comp.name = folder_name
		comp.cc_id = ""

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
