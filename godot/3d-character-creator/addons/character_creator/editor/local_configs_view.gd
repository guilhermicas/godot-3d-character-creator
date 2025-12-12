@tool
extends VBoxContainer

@onready var config_list: ItemList = $HBox/ConfigList
@onready var new_btn: Button = $HBox/Actions/NewButton
@onready var duplicate_btn: Button = $HBox/Actions/DuplicateButton
@onready var tree_view: Control = $TreeView

var export_path: String = ""
var global_config: CharacterComponent
var current_config: CharacterComponent
var current_config_path: String = ""
var local_configs: Array[String] = []

func _ready() -> void:
	new_btn.pressed.connect(_on_new_config)
	duplicate_btn.pressed.connect(_on_duplicate_config)
	config_list.item_selected.connect(_on_config_selected)
	
	tree_view.add_child_requested.connect(_on_add_child_requested)
	tree_view.remove_requested.connect(_on_remove_requested)
	tree_view.property_changed.connect(_on_property_changed)

func set_export_path(path: String, global_cfg: CharacterComponent = null) -> void:
	export_path = path
	if global_cfg:
		global_config = global_cfg
	else:
		_load_global_config()
	_refresh_config_list()

func _load_global_config() -> void:
	if export_path == "":
		return
	
	var global_path := export_path.path_join("global_config.tres")
	if FileAccess.file_exists(global_path):
		global_config = load(global_path)

func _refresh_config_list() -> void:
	config_list.clear()
	local_configs.clear()
	
	if export_path == "":
		return
	
	var dir := DirAccess.open(export_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres") and file != "global_config.tres":
			local_configs.append(file)
			config_list.add_item(file.trim_suffix(".tres"))
		file = dir.get_next()
	dir.list_dir_end()

func _on_config_selected(idx: int) -> void:
	if idx < 0 or idx >= local_configs.size():
		return
	
	current_config_path = export_path.path_join(local_configs[idx])
	_load_local_config(current_config_path)

func _load_local_config(path: String) -> void:
	var local_res: LocalConfig = load(path)
	if not local_res or not global_config:
		return
	
	current_config = CharacterComponent.assemble_from_global(local_res.items, global_config)
	tree_view.set_config(current_config, true, global_config)

func _on_new_config() -> void:
	if not global_config:
		push_error("No global config loaded")
		return

	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.current_dir = export_path if export_path != "" else "res://"
	dialog.current_file = "new_config.tres"
	dialog.add_filter("*.tres", "Resource Files")
	dialog.file_selected.connect(func(path: String):
		_create_new_config(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

func _create_new_config(path: String) -> void:
	current_config = LocalConfig.deep_copy_tree(global_config)
	current_config_path = path
	_save_current_config()
	_refresh_config_list()
	
	# Select the newly created config
	for i in local_configs.size():
		if export_path.path_join(local_configs[i]) == path:
			config_list.select(i)
			_on_config_selected(i)
			break

func _on_duplicate_config() -> void:
	if not current_config:
		push_error("No config selected to duplicate")
		return

	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.current_dir = export_path if export_path != "" else "res://"
	dialog.current_file = current_config_path.get_file().get_basename() + "_copy.tres"
	dialog.add_filter("*.tres", "Resource Files")
	dialog.file_selected.connect(func(path: String):
		var copy := LocalConfig.deep_copy_tree(current_config)
		var local_res := LocalConfig.new()
		local_res.items = LocalConfig.flatten_tree(copy)
		ResourceSaver.save(local_res, path)
		_refresh_config_list()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

func _on_add_child_requested(parent: CharacterComponent) -> void:
	if not global_config:
		return
	
	# Find this component in global to see available children
	var global_parent := _find_in_global(parent.cc_id)
	if not global_parent:
		return
	
	# Get children not already in local
	var available: Array[CharacterComponent] = []
	for child in global_parent.children:
		if not _has_child_with_id(parent, child.cc_id):
			available.append(child)
	
	if available.is_empty():
		push_warning("No additional children available")
		return
	
	# Show popup to select which child to add
	var popup := PopupMenu.new()
	for i in available.size():
		var child := available[i]
		var display := child.display_name if child.display_name else child.name
		popup.add_item(display, i)
	
	popup.id_pressed.connect(func(id: int):
		var to_add := available[id]
		var new_child := CharacterComponent.new()
		CharacterComponent.copy_fields(to_add, new_child)
		parent.children.append(new_child)
		tree_view.set_config(current_config, true, global_config)
		_save_current_config()
		popup.queue_free()
	)
	popup.popup_hide.connect(func(): popup.queue_free())

	add_child(popup)
	popup.popup_on_parent(Rect2i(get_viewport().get_mouse_position(), Vector2i(1, 1)))

func _on_remove_requested(component: CharacterComponent) -> void:
	# Find parent and remove this child
	if not _remove_from_parent(current_config, component):
		push_error("Failed to remove component")
		return
	
	tree_view.set_config(current_config, true, global_config)
	_save_current_config()

func _remove_from_parent(node: CharacterComponent, to_remove: CharacterComponent) -> bool:
	for i in node.children.size():
		if node.children[i] == to_remove:
			node.children.remove_at(i)
			return true
		if _remove_from_parent(node.children[i], to_remove):
			return true
	return false

func _on_property_changed(component: CharacterComponent, property: String, value: Variant) -> void:
	_save_current_config()

func _save_current_config() -> void:
	if current_config_path == "" or not current_config:
		return
	
	var local_res := LocalConfig.new()
	local_res.items = LocalConfig.flatten_tree(current_config)
	
	var result := ResourceSaver.save(local_res, current_config_path)
	if result == OK:
		print("💾 Saved: " + current_config_path)
	else:
		push_error("Failed to save: " + current_config_path)

func _find_in_global(cc_id: String) -> CharacterComponent:
	if not global_config:
		return null
	return TreeUtils.find_by_id(global_config, cc_id)

func _has_child_with_id(parent: CharacterComponent, cc_id: String) -> bool:
	for child in parent.children:
		if child.cc_id == cc_id:
			return true
	return false
