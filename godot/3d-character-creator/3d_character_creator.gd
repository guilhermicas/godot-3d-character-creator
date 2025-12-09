@tool
extends Node3D

## ------------------ Inspector Configuration ------------------
@export_file("*.tres") var local_config_path: String = "":
	set(value):
		local_config_path = value
		update_configuration_warnings()

## ------------------ Runtime State (not exported) ------------------
var _local_config: CharacterComponent
var export_character: Array[CharacterComponent] = []

## ------------------ UI References ------------------
@onready var model_tree: VBoxContainer = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer
@onready var ccc_ref: VBoxContainer = $UI/CCC_
@onready var character_preview_spot: Node3D = $CharacterPreviewSpot

## ------------------ Runtime State ------------------
var _active_cccs: Array[Control] = []
var _loading_items: Dictionary = {}
var _item_list_map: Dictionary = {}
var _placeholder_icon: ImageTexture

func _ready() -> void:
	if not Engine.is_editor_hint():
		_create_placeholder_icon()
		ccc_ref.visible = false
		_load_local_config_for_runtime()
		if _local_config: _expand_top_level()

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

			if _item_list_map.has(cc_id):
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

func _load_local_config_for_runtime() -> void:
	if local_config_path == "":
		push_error("No local_config_path set. Cannot build character UI.")
		return

	# Load the local config resource
	var local_res: LocalConfig = load(local_config_path)
	if local_res == null:
		push_error("Failed to load local config: " + local_config_path)
		return

	# Get the actual filesystem path (handles uid:// paths)
	var actual_path := local_res.resource_path
	if actual_path == "":
		push_error("Local config has no resource_path")
		return

	# Load global config from the same directory as local config
	var config_dir := actual_path.get_base_dir()
	# TODO: be careful with this, because this implies local configs and global config are on the same folder
	var global_config_path := config_dir.path_join("global_config.tres")

	if not FileAccess.file_exists(global_config_path):
		push_error("Global config not found at: " + global_config_path)
		return

	var global_config: CharacterComponent = load(global_config_path)
	if global_config == null:
		push_error("Failed to load global config: " + global_config_path)
		return

	_local_config = CharacterComponent.assemble_from_global(local_res.items, global_config)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if local_config_path == "":
		warnings.append("⚠ Local config path not set. Required for runtime character building.")
	return warnings

func _expand_top_level() -> void:
	_clear_ui()
	export_character.clear()
	_update_character_preview()
	_expand_ccc(_local_config, 0, model_tree)

## ------------------ UI Construction ------------------

func _expand_ccc(component: CharacterComponent, depth: int, parent: Control) -> void:
	var ccc_node := ccc_ref.duplicate() as VBoxContainer
	ccc_node.visible = true

	var title_label := ccc_node.get_node("TitleLabel") as Label
	var item_list := ccc_node.get_node("ModelList") as ItemList

	title_label.text = component.display_name if component.display_name else component.name
	ccc_node.modulate = Color.from_hsv(0, 0, 1.0 - (depth * 0.15))

	for child in component.children:
		if child.name.begins_with("CC_"):
			var display := child.display_name if child.display_name else child.name

			var cached := GLBCache.get_cached(child.cc_id)
			if cached:
				child.instanced_model = cached
			elif child.glb_path != "" and not _loading_items.has(child.cc_id):
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

	export_character.resize(depth + 1)
	export_character[depth] = selected

	_clear_cccs_after(ccc_node)
	_update_character_preview()

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
	for child: Node in character_preview_spot.get_children():
		child.queue_free()

	# TODO: Use CharacterComponent.assemble_from_global() for proper hierarchy
	#       with bone/animation parenting from global_config authority
	for comp in export_character:
		if comp.instanced_model:
			var instance := comp.instanced_model.instantiate()
			character_preview_spot.add_child(instance)
