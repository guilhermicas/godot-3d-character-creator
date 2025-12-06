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
@onready var character_preview_spot: Node3D = $CharacterPreviewSpot

## ------------------ Runtime State ------------------
var _active_cccs: Array[Control] = [] # Currently displayed CCC containers
var _loading_items: Dictionary = {}  # cc_id -> CharacterComponent for in-progress loads
var _item_list_map: Dictionary = {}  # cc_id -> {list: ItemList, idx: int} for UI updates
# TODO: maybe this var shouldn't exist
#       instead of the _create_placeholder_icon, we could have
#       _get_thumbnail_safe, which tries to get thumbnail based
#       on the model's config or whatever, if it fails returns the
#       image, and this var doesn't exist
var _placeholder_icon: ImageTexture # 32x32 black square for items

func _ready() -> void:
	if not Engine.is_editor_hint():
		_create_placeholder_icon()
		ccc_ref.visible = false # Hide reference node
		if global_config: _expand_top_level()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_poll_loading_items()

func _poll_loading_items() -> void:
	for cc_id: String in _loading_items.keys():
		var comp := _loading_items[cc_id] as CharacterComponent
		var status := ResourceLoader.load_threaded_get_status(comp.glb_path)

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			comp.instanced_model = ResourceLoader.load_threaded_get(comp.glb_path)
			GLBCache.cache(cc_id, comp.instanced_model)
			_loading_items.erase(cc_id)

			# Update UI to remove loading indicator
			if _item_list_map.has(cc_id):
				# TODO: this could be cleaner, maybe make a function for this
				#       since this is used in two spots
				var data: Dictionary = _item_list_map[cc_id]
				var item_list := data.list as ItemList
				var idx: int = data.idx
				var display := comp.display_name if comp.display_name else comp.name
				item_list.set_item_text(idx, display)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Failed to load GLB: " + comp.glb_path)
			_loading_items.erase(cc_id)

func _create_placeholder_icon() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	_placeholder_icon = ImageTexture.create_from_image(img)

func _expand_top_level() -> void:
	_clear_ui()
	export_character.clear()
	_update_character_preview()
	_expand_ccc(global_config, 0, model_tree)

## ------------------ UI Construction ------------------

func _expand_ccc(component: CharacterComponent, depth: int, parent: Control) -> void:
	var ccc_node := ccc_ref.duplicate() as VBoxContainer
	ccc_node.visible = true

	var title_label := ccc_node.get_node("TitleLabel") as Label
	var item_list := ccc_node.get_node("ModelList") as ItemList

	title_label.text = component.display_name if component.display_name else component.name
	ccc_node.modulate = Color.from_hsv(0, 0, 1.0 - (depth * 0.15)) # Lighter → darker background color

	# Populate and start loading all visible CC_ children
	for child in component.children:
		if child.name.begins_with("CC_"):
			# TODO: this could be cleaner, maybe make a function for this
			#       since this is used in two spots
			var display := child.display_name if child.display_name else child.name

			# Check if already cached
			var cached := GLBCache.get_cached(child.cc_id)
			if cached:
				child.instanced_model = cached
			elif child.glb_path != "" and not _loading_items.has(child.cc_id):
				# Start async load
				# TODO: Replace text loading indicator with animated TextureRect + shader for polish
				#       maybe a gif the user can configure?
				display += " [Loading...]"
				ResourceLoader.load_threaded_request(child.glb_path)
				_loading_items[child.cc_id] = child

			var idx := item_list.add_item(display, _placeholder_icon)
			item_list.set_item_metadata(idx, child)
			_item_list_map[child.cc_id] = {"list": item_list, "idx": idx}

	item_list.item_selected.connect(_on_item_selected.bind(depth, ccc_node, parent))

	parent.add_child(ccc_node)
	_active_cccs.append(ccc_node)

func _on_item_selected(idx: int, depth: int, ccc_node: Control, parent_container: Control) -> void:
	var item_list := ccc_node.get_node("ModelList") as ItemList
	var selected := item_list.get_item_metadata(idx) as CharacterComponent

	# Deep copy component but share instanced_model pointer:
	# Instead of re-importing the glb just for the exported character,
	# just point the already loaded glb to the exported character
	# TODO: double check if this is good, and if maybe i can shave a few lines off of this
	var exported_comp := CharacterComponent.new()
	exported_comp.name = selected.name
	exported_comp.glb_path = selected.glb_path
	exported_comp.cc_id = selected.cc_id
	exported_comp.display_name = selected.display_name
	exported_comp.metadata = selected.metadata.duplicate()
	exported_comp.instanced_model = selected.instanced_model

	# Update export_character: set at depth, clear deeper levels
	export_character.resize(depth + 1)
	export_character[depth] = exported_comp

	# Clear CCCs and update preview
	_clear_cccs_after(ccc_node)
	_update_character_preview()

	# Expand child CCCs if any
	for child in selected.children:
		if child.name.begins_with("CCC_"):
			_expand_ccc(child, depth + 1, parent_container)

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
	_item_list_map.clear()

func _update_character_preview() -> void:
	# Clear existing preview instances
	for child: Node in character_preview_spot.get_children():
		child.queue_free()

	# TODO: Use hierarchy assembly function
	#       to properly parent instances based on global_config authority
	#       For now, instantiate flat until proper bone/animation hierarchy is implemented
	for comp in export_character:
		if comp.instanced_model:
			var instance := comp.instanced_model.instantiate()
			character_preview_spot.add_child(instance)

## ------------------ Editor Tree Building ------------------

func _rebuild_tree() -> void:
	if not Engine.is_editor_hint(): return

	if blender_export_path == "" or not DirAccess.dir_exists_absolute(blender_export_path):
		global_config = null
		return
	# All store instances point to the same tres file
	# Godot already handles edits made on the Inspector window
	# So we just have a "pointer" from all scenes to the same tres Resource
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

	# Extract CC_id from folder name (e.g., "CC_male_CC_id_9efe906c" -> "9efe906c")
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
