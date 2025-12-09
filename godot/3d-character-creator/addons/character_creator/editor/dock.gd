@tool
extends VBoxContainer

var plugin: EditorPlugin

# References
@onready var path_container: HBoxContainer = $PathConfig
@onready var path_edit: LineEdit = $PathConfig/PathEdit
@onready var browse_btn: Button = $PathConfig/BrowseButton
@onready var rescan_btn: Button = $PathConfig/RescanButton
@onready var tabs: TabBar = $Tabs
@onready var tab_container: MarginContainer = $Content
@onready var global_view: Control = $Content/GlobalView
@onready var local_view: Control = $Content/LocalView

# Current state
var global_config: CharacterComponent
var blender_export_path: String = ""

func _ready() -> void:
	tabs.tab_changed.connect(_on_tab_changed)
	browse_btn.pressed.connect(_on_browse_pressed)
	rescan_btn.pressed.connect(_on_rescan_pressed)
	path_edit.text_submitted.connect(_on_path_submitted)

	_load_saved_path()
	_refresh_ui()

	# Default to global tab
	global_view.visible = 1
	local_view.visible = 0

func _load_saved_path() -> void:
	# Load from EditorSettings (persisted across sessions)
	if plugin and plugin.get_editor_interface():
		var settings := plugin.get_editor_interface().get_editor_settings()
		if settings.has_setting("character_creator/blender_export_path"):
			blender_export_path = settings.get_setting("character_creator/blender_export_path")
			path_edit.text = blender_export_path
			_load_global_config()

func _save_path() -> void:
	# Save to EditorSettings
	if plugin and plugin.get_editor_interface():
		var settings := plugin.get_editor_interface().get_editor_settings()
		if not settings.has_setting("character_creator/blender_export_path"):
			settings.set_setting("character_creator/blender_export_path", "")
			settings.set_initial_value("character_creator/blender_export_path", "", false)
		settings.set_setting("character_creator/blender_export_path", blender_export_path)

func _on_browse_pressed() -> void:
	var file_dialog := EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.current_dir = blender_export_path if blender_export_path != "" else "res://"
	file_dialog.dir_selected.connect(func(dir: String):
		blender_export_path = dir
		path_edit.text = dir
		_save_path()
		_load_global_config()
		_refresh_ui()
		file_dialog.queue_free()
	)
	file_dialog.canceled.connect(func(): file_dialog.queue_free())
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_path_submitted(new_path: String) -> void:
	blender_export_path = new_path
	_save_path()
	_load_global_config()
	_refresh_ui()

func _on_rescan_pressed() -> void:
	if blender_export_path == "":
		push_warning("No export path set")
		return

	_scan_and_build_global_config()
	_load_global_config()
	_refresh_ui()

func _load_global_config() -> void:
	if blender_export_path == "":
		return

	var config_path := blender_export_path.path_join("global_config.tres")
	if FileAccess.file_exists(config_path):
		global_config = load(config_path)
		if global_view:
			global_view.set_config(global_config, false)
	else:
		push_warning("Global config not found at: " + config_path)

func _on_tab_changed(tab: int) -> void:
	if global_view and local_view:
		global_view.visible = (tab == 0)
		local_view.visible = (tab == 1)

func _refresh_ui() -> void:
	if global_config and global_view:
		global_view.set_config(global_config, false)

	if blender_export_path != "" and local_view:
		local_view.set_export_path(blender_export_path, global_config)

func _scan_and_build_global_config() -> void:
	if not DirAccess.dir_exists_absolute(blender_export_path):
		push_error("Blender export path does not exist: " + blender_export_path)
		return

	var config_path := blender_export_path.path_join("global_config.tres")

	# Load existing or create new
	if FileAccess.file_exists(config_path):
		global_config = load(config_path)
		if global_config == null:
			push_error("Failed to load global_config.tres")
			global_config = CharacterComponent.new()
	else:
		global_config = CharacterComponent.new()

	# Find the top-level CCC_
	var dirs := DirAccess.get_directories_at(blender_export_path)
	var first_dir := ""
	for d in dirs:
		if d.begins_with("CCC_"):
			first_dir = d
			break

	if first_dir == "":
		push_error("No top-level CCC_ folder found in: " + blender_export_path)
		return

	# Scan and merge
	var scanned := _scan_component(blender_export_path.path_join(first_dir))
	_merge_scanned_into_config(global_config, scanned)

	# Save
	var save_result := ResourceSaver.save(global_config, config_path)
	if save_result == OK:
		print("✅ Global config saved: " + config_path)
	else:
		push_error("Failed to save global_config.tres")

func _scan_component(path: String) -> CharacterComponent:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open: " + path)
		return null

	var comp := CharacterComponent.new()
	var folder_name := path.get_file()

	# Parse name and ID from folder
	if folder_name.contains("_CC_id_"):
		var parts := folder_name.split("_CC_id_")
		comp.name = parts[0]
		comp.cc_id = parts[1] if parts.size() > 1 else ""
	else:
		comp.name = folder_name
		comp.cc_id = ""

	# Find GLB file
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".glb"):
			comp.glb_path = path.path_join(f)
			break
		f = dir.get_next()
	dir.list_dir_end()

	# Recursively scan children
	dir.list_dir_begin()
	f = dir.get_next()
	while f != "":
		if dir.current_is_dir() and (f.begins_with("CC_") or f.begins_with("CCC_")):
			var child := _scan_component(path.path_join(f))
			if child:
				comp.children.append(child)
		f = dir.get_next()
	dir.list_dir_end()

	return comp

func _merge_scanned_into_config(existing: CharacterComponent, scanned: CharacterComponent) -> void:
	# Update core properties from scan
	existing.name = scanned.name
	existing.glb_path = scanned.glb_path
	existing.cc_id = scanned.cc_id

	# Build map of existing children by cc_id
	var existing_map := {}
	for child in existing.children:
		if child.cc_id != "":
			existing_map[child.cc_id] = child

	# Merge scanned children with existing (preserving user edits)
	var merged: Array[CharacterComponent] = []
	for scanned_child in scanned.children:
		if scanned_child.cc_id != "" and existing_map.has(scanned_child.cc_id):
			# Child already exists, merge recursively (keeps display_name, metadata)
			var existing_child := existing_map[scanned_child.cc_id] as CharacterComponent
			_merge_scanned_into_config(existing_child, scanned_child)
			merged.append(existing_child)
			existing_map.erase(scanned_child.cc_id)
		else:
			# New child from scan
			merged.append(scanned_child)

	existing.children = merged
