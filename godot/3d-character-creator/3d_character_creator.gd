@tool
extends Node3D

## ------------------ Inspector Configuration ------------------
@export_dir var blender_export_path: String:
	set(value):
		blender_export_path = value
		_rebuild_tree()

@export var global_config: CharacterComponent
@export var export_character: Array[CharacterComponent] = []

## ------------------ UI References ------------------
@onready var model_tree: VBoxContainer = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer
@onready var ccc_ref: VBoxContainer = $UI/CCC_ # script will duplicate this to create the UI dynamically

## ------------------ Runtime State ------------------
var _active_cccs: Array[Control] = []  # Currently displayed CCC containers
# TODO: maybe this var shouldn't exist
#       instead of the _create_placeholder_icon, we could have
#       _get_thumbnail_safe, which tries to get thumbnail based
#       on the model's config or whatever, if it fails returns the
#       image, and this var doesn't exist
var _placeholder_icon: ImageTexture  # 32x32 black square for items

func _ready() -> void:
	if not Engine.is_editor_hint():
		_create_placeholder_icon()
		ccc_ref.visible = false  # Hide reference node
		if global_config: _expand_top_level()

func _create_placeholder_icon() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	_placeholder_icon = ImageTexture.create_from_image(img)

func _expand_top_level() -> void:
	_clear_ui()
	export_character.clear()
	_expand_ccc(global_config, 0, model_tree)

## ------------------ UI Construction ------------------

func _expand_ccc(component: CharacterComponent, depth: int, parent: Control) -> void:
	var ccc_node := ccc_ref.duplicate() as VBoxContainer
	ccc_node.visible = true
	
	# Set title and background color (darker as depth increases)
	var title_label := ccc_node.get_node("TitleLabel") as Label
	var item_list := ccc_node.get_node("ModelList") as ItemList
	
	title_label.text = component.display_name if component.display_name else component.name
	ccc_node.modulate = Color.from_hsv(0, 0, 1.0 - (depth * 0.15))  # Lighter → darker
	
	# Populate ItemList with direct CC_ children only
	for child in component.children:
		if child.name.begins_with("CC_"):
			var display := child.display_name if child.display_name else child.name
			item_list.add_item(display, _placeholder_icon)
			item_list.set_item_metadata(item_list.item_count - 1, child)
	
	# Connect selection signal
	item_list.item_selected.connect(_on_item_selected.bind(depth, ccc_node, parent))
	
	parent.add_child(ccc_node)
	_active_cccs.append(ccc_node)

func _on_item_selected(idx: int, depth: int, ccc_node: Control, parent_container: Control) -> void:
	var item_list := ccc_node.get_node("ModelList") as ItemList
	var selected := item_list.get_item_metadata(idx) as CharacterComponent
	
	# Update export_character: set at depth, clear deeper levels
	export_character.resize(depth + 1)
	export_character[depth] = selected
	
	# print("Current export_character state:", export_character) # DEBUG
	
	# Clear all CCCs deeper than current depth
	_clear_cccs_after(ccc_node)
	
	# Expand child CCCs if selected component has any
	for child in selected.children:
		if child.name.begins_with("CCC_"):
			_expand_ccc(child, depth + 1, parent_container)
	
	# TODO: Lazy load GLB asynchronously when item selected
	# Use ResourceLoader.load_threaded_request() for async loading

func _clear_cccs_after(from_node: Control) -> void:
	var start_removing := false
	var to_remove: Array[Control] = []
	
	for ccc in _active_cccs:
		if start_removing:
			to_remove.append(ccc)
		elif ccc == from_node:
			start_removing = true
	
	for ccc in to_remove:
		ccc.queue_free()
		_active_cccs.erase(ccc)

func _clear_ui() -> void:
	for ccc in _active_cccs:
		ccc.queue_free()
	_active_cccs.clear()

## ------------------ Editor Tree Building ------------------

func _rebuild_tree() -> void:
	if not Engine.is_editor_hint(): return

	if blender_export_path == "" or not DirAccess.dir_exists_absolute(blender_export_path):
		global_config = null
		return

	var config_path := blender_export_path.path_join("global_config.tres")

	# Load or create config
	if FileAccess.file_exists(config_path):
		global_config = load(config_path)
		if global_config == null:
			push_error("Failed to load global_config.tres")
			global_config = CharacterComponent.new()
	else:
		global_config = CharacterComponent.new()

	# Find top-level CCC_
	var dirs := DirAccess.get_directories_at(blender_export_path)
	var first_dir := ""
	for d in dirs:
		if d.begins_with("CCC_"):
			first_dir = d
			break
	
	if first_dir == "":
		push_error("No top-level CCC_ found")
		global_config = null
		return
	
	# Scan and merge
	var scanned := _scan_component(blender_export_path.path_join(first_dir))
	_merge_scanned_into_config(global_config, scanned)
	
	var save_result := ResourceSaver.save(global_config, config_path)
	if save_result != OK:
		push_error("Failed to save global_config.tres")
	
	notify_property_list_changed()

func _merge_scanned_into_config(existing: CharacterComponent, scanned: CharacterComponent) -> void:
	# Update read-only fields
	existing.name = scanned.name
	existing.glb_path = scanned.glb_path
	existing.cc_id = scanned.cc_id

	# Build map of existing children by cc_id
	var existing_map := {}
	for child in existing.children:
		if child.cc_id != "":
			existing_map[child.cc_id] = child

	# Merge scanned children with existing
	var merged: Array[CharacterComponent] = []
	for scanned_child in scanned.children:
		if scanned_child.cc_id != "" and existing_map.has(scanned_child.cc_id):
			var existing_child := existing_map[scanned_child.cc_id] as CharacterComponent
			_merge_scanned_into_config(existing_child, scanned_child)
			merged.append(existing_child)
			existing_map.erase(scanned_child.cc_id)
		else:
			merged.append(scanned_child)

	existing.children = merged

func _scan_component(path: String) -> CharacterComponent:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open: " + path)
		return null

	var comp := CharacterComponent.new()
	var folder_name := path.get_file()

	# Extract CC_id from folder name
	if folder_name.contains("_CC_id_"):
		var parts := folder_name.split("_CC_id_")
		comp.name = parts[0]
		comp.cc_id = parts[1] if parts.size() > 1 else ""
	else:
		comp.name = folder_name
		comp.cc_id = ""

	# Find .glb file
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".glb"):
			comp.glb_path = path.path_join(f)
			break
		f = dir.get_next()
	dir.list_dir_end()

	# Recurse into CC_/CCC_ folders
	dir.list_dir_begin()
	f = dir.get_next()
	while f != "":
		if dir.current_is_dir() and (f.begins_with("CC_") or f.begins_with("CCC_")):
			var child := _scan_component(path.path_join(f))
			if child: comp.children.append(child)
		f = dir.get_next()
	dir.list_dir_end()

	return comp
