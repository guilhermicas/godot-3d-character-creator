@tool
extends Node3D

## Character creator UI scene for editing character configurations.
## Can be used standalone (with local_config_path) or via interaction API.

## ------------------ Signals ------------------
signal character_saved(config: Array[CharacterComponent])
signal character_cancelled()

## ------------------ Inspector Configuration ------------------
@export_file("*.tres") var local_config_path: String = "":
	set(value):
		local_config_path = value
		update_configuration_warnings()

@export var standalone_mode: bool = false
@export var show_cancel_button: bool = true
## If true, skip showing the root CCC_ when character already has a selection from it.
## Use in shops to hide base model re-selection. Safety: Always shows root if no selection exists.
@export var hide_definitive_base_model: bool = true

## ------------------ Runtime State (not exported) ------------------
var _global_config: CharacterComponent
var _local_config: CharacterComponent
var export_character: Array[CharacterComponent] = []
var _session_active: bool = false  ## True when UI is active (standalone OR interactive)

## ------------------ UI References ------------------
@onready var ui: Control = $UI
@onready var model_tree: VBoxContainer = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer
@onready var ccc_ref: VBoxContainer = $UI/CCC_
@onready var character_preview_spot: Node3D = $CharacterPreviewSpot
@onready var done_button: Button = $UI/DoneButton
@onready var cancel_button: Button = $UI/CancelButton
@onready var camera: Camera3D = $Camera3D
@onready var standalone_ui: VBoxContainer = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer/StandaloneUI
@onready var name_field: LineEdit = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer/StandaloneUI/NameField
@onready var export_button: Button = $UI/HBoxContainer/MarginContainer/Panel/ScrollContainer/VBoxContainer/StandaloneUI/ExportButton

## ------------------ Runtime State ------------------
var _active_cccs: Array[Control] = []
var _loading_items: Dictionary = {}
var _item_list_map: Dictionary = {}
var _placeholder_icon: ImageTexture

## ------------------ Constants ------------------
const DEPTH_DARKENING_FACTOR := 0.15

func _ready() -> void:
	if not Engine.is_editor_hint():
		_create_placeholder_icon()
		ccc_ref.visible = false
		character_preview_spot.visible = false
		done_button.pressed.connect(_on_done_pressed)
		cancel_button.pressed.connect(_on_cancel_pressed)
		export_button.pressed.connect(_on_export_pressed)

		# Load config if path provided (defines available items inventory)
		if local_config_path != "":
			_load_local_config_for_runtime()

			# Only auto-show UI in standalone mode
			if standalone_mode and _local_config:
				_session_active = true
				ui.visible = true
				camera.current = true
				character_preview_spot.visible = true
				standalone_ui.visible = true
				done_button.visible = false
				cancel_button.visible = false
				_expand_top_level()

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

	# Only clear export_character in standalone mode
	# In interactive mode, it's pre-populated with current character
	if standalone_mode:
		export_character.clear()

	_update_character_preview()

	# Check if we should skip the root CCC_ (e.g., hide gender selection in shops)
	if hide_definitive_base_model:

		# First, check for mismatch: user has a root selection that doesn't exist in local config
		var user_root_from_global := _find_user_root_in_global()
		if user_root_from_global != null:

			# Check if it exists in local config
			var exists_in_local := false
			for local_child in _local_config.children:
				if local_child.cc_id == user_root_from_global.cc_id:
					exists_in_local = true
					break

			if not exists_in_local:
				# MISMATCH: User has CC_female but shop only has CC_male
				_show_base_model_mismatch_message(user_root_from_global)
				return
			else:
				# User's root exists in local - skip root UI and show children
				_expand_from_selected_root(user_root_from_global)
				return
		else:
			print("[Warning] User has no root selection, showing root CCC_ normally")

	# Default: show root CCC_ normally (safety fallback if no root selection)
	_expand_ccc(_local_config, 0, model_tree)

## ------------------ UI Construction ------------------

## Find which root CC_ the user currently has selected (from export_character)
## Returns the component from _global_config (with full hierarchy)
## Returns null if user has no root selection
func _find_user_root_in_global() -> CharacterComponent:
	if export_character.is_empty():
		return null

	for child in _global_config.children:
		if child.name.begins_with("CC_") and TreeUtils.is_in_flat_array(child.cc_id, export_character):
			return child

	return null

## Expand UI starting from the already-selected root child (skip root CCC_)
## Assumes root_selection has already been validated to exist in _local_config
func _expand_from_selected_root(root_selection: CharacterComponent) -> void:

	# CRITICAL: Ensure root selection is in export_character so it renders in preview
	var already_in_export := TreeUtils.is_in_flat_array(root_selection.cc_id, export_character)

	if not already_in_export:
		var root_copy := CharacterComponent.new()
		CharacterComponent.copy_fields(root_selection, root_copy)
		export_character.append(root_copy)
		_update_character_preview()  # Refresh preview with base model

	# Expand children of the selected root (filter by what's in local_config)
	for child in root_selection.children:
		# Only expand CCC_ children that exist in the local_config
		if child.name.begins_with("CCC_"):
			# Check if this child exists in local config
			var local_match := TreeUtils.find_by_id(_local_config, child.cc_id)
			if local_match:
				print("  - Expanding: ", child.name, " (exists in local)")
				_expand_ccc(child, 0, model_tree)  # Start at depth 0 since we're skipping root

				# Apply defaults if needed
				if child.is_child_mandatory and child.default_child_id != "":
					_auto_select_default(child, 0, model_tree)
			else:
				print("  - Skipping: ", child.name, " (not in local config)")

## Show message when user's base model doesn't match the current config
func _show_base_model_mismatch_message(user_selection: CharacterComponent) -> void:
	var message := Label.new()
	var base_model_name := user_selection.display_name if user_selection.display_name else user_selection.name
	message.text = "This location doesn't have items for your current base model (%s).\nPlease visit a different location." % base_model_name
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 16)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(400, 100)
	model_tree.add_child(message)

func _is_in_export_character(cc_id: String) -> bool:
	return TreeUtils.is_in_flat_array(cc_id, export_character)

func _has_descendant_in_export(component: CharacterComponent) -> bool:
	# Check if this component or any of its descendants are in export_character
	if _is_in_export_character(component.cc_id):
		return true
	for child in component.children:
		if _has_descendant_in_export(child):
			return true
	return false

func _auto_select_default(container: CharacterComponent, depth: int, parent_container: Control) -> void:
	# Find the default child
	var default_child: CharacterComponent = null

	for child in container.children:
		if child.cc_id == container.default_child_id:
			default_child = child
			break

	if default_child == null:
		return  # No valid default

	# Add to export_character
	if export_character.size() <= depth:
		export_character.resize(depth + 1)
	export_character[depth] = default_child

	# Find and select in the ItemList that was just created for this container
	for ccc in _active_cccs:
		var item_list := ccc.get_node_or_null("ModelList") as ItemList
		if item_list:
			for i in range(item_list.item_count):
				var item_meta = item_list.get_item_metadata(i) as CharacterComponent
				if item_meta and item_meta.cc_id == default_child.cc_id:
					item_list.select(i)
					break

	# Update preview
	_update_character_preview()

	# Recursively expand and apply defaults to nested mandatory containers
	for child in default_child.children:
		if child.name.begins_with("CCC_"):
			_expand_ccc(child, depth + 1, parent_container)
			if child.is_child_mandatory and child.default_child_id != "":
				_auto_select_default(child, depth + 1, parent_container)

func _expand_ccc(component: CharacterComponent, depth: int, parent: Control) -> void:
	var ccc_node := ccc_ref.duplicate() as VBoxContainer
	ccc_node.visible = true

	var title_label := ccc_node.get_node("TitleLabel") as Label
	var item_list := ccc_node.get_node("ModelList") as ItemList

	title_label.text = component.display_name if component.display_name else component.name
	ccc_node.modulate = Color.from_hsv(0, 0, 1.0 - (depth * DEPTH_DARKENING_FACTOR))

	var selected_child: CharacterComponent = null
	var selected_idx := -1

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

			# Check if this item should be pre-selected
			if _is_in_export_character(child.cc_id):
				selected_child = child
				selected_idx = idx

	item_list.item_selected.connect(_on_item_selected.bind(depth, ccc_node, parent))

	parent.add_child(ccc_node)
	_active_cccs.append(ccc_node)

	# Pre-select item if found in export_character
	if selected_idx >= 0:
		item_list.select(selected_idx)
		# Auto-expand children if this item has descendants in export_character
		if selected_child and _has_descendant_in_export(selected_child):
			for child in selected_child.children:
				if child.name.begins_with("CCC_"):
					_expand_ccc(child, depth + 1, parent)

func _on_item_selected(idx: int, depth: int, ccc_node: Control, parent_container: Control) -> void:
	var item_list := ccc_node.get_node("ModelList") as ItemList
	var selected := item_list.get_item_metadata(idx) as CharacterComponent

	export_character.resize(depth + 1)
	export_character[depth] = selected

	_clear_cccs_after(ccc_node)
	_update_character_preview()

	# Expand child containers
	for child in selected.children:
		if child.name.begins_with("CCC_"):
			_expand_ccc(child, depth + 1, parent_container)

			# If this child is mandatory, auto-select its default
			if child.is_child_mandatory and child.default_child_id != "":
				_auto_select_default(child, depth + 1, parent_container)

func _clear_cccs_after(from_node: Control) -> void:
	var idx := _active_cccs.find(from_node)
	if idx == -1:
		return

	# Remove everything after idx
	for i in range(idx + 1, _active_cccs.size()):
		_active_cccs[i].queue_free()

	_active_cccs.resize(idx + 1)

func _clear_ui() -> void:
	for ccc in _active_cccs:
		ccc.queue_free()
	_active_cccs.clear()
	_item_list_map.clear()

func _update_character_preview() -> void:
	UIUtils.clear_children(character_preview_spot)

	# TODO: Use CharacterComponent.assemble_from_global() for proper hierarchy
	#       with bone/animation parenting from global_config authority
	for comp in export_character:
		# Ensure model is loaded (either from cache or load fresh)
		if not comp.instanced_model and comp.glb_path != "":
			var cached := GLBCache.get_cached(comp.cc_id)
			if cached:
				comp.instanced_model = cached
			else:
				comp.instanced_model = load(comp.glb_path)
				if comp.instanced_model:
					GLBCache.cache(comp.cc_id, comp.instanced_model)
				else:
					push_error("Failed to load GLB: " + comp.glb_path)

		if comp.instanced_model:
			var instance := comp.instanced_model.instantiate()
			character_preview_spot.add_child(instance)

## ------------------ Public API for Interactive Mode ------------------

func enter_with_character(input_config: Array[CharacterComponent]) -> void:
	_session_active = true

	# Load global config using ConfigLoader (if not already loaded)
	if not _global_config:
		_global_config = ConfigLoader.load_global_config()
		if _global_config == null:
			return

	# Use local_config if already loaded (shop inventory), otherwise use global
	if not _local_config:
		_local_config = _global_config

	# Validate defaults in config before using
	var validation_warnings: Array[String] = _local_config.validate_defaults()
	for warning in validation_warnings:
		push_warning("Config validation: " + warning)

	# Initialize export_character
	if input_config.is_empty():
		# New character: Apply top-level defaults
		export_character.clear()
	else:
		# Existing character: Pre-populate with current selections
		export_character = input_config.duplicate()

	# Show UI, camera, Done button, and optionally Cancel button
	ui.visible = true
	camera.current = true
	character_preview_spot.visible = true
	standalone_ui.visible = false
	done_button.visible = true
	cancel_button.visible = show_cancel_button
	_expand_top_level()

	# Apply top-level defaults for new characters (after UI is built)
	if input_config.is_empty():
		# The _local_config itself IS the top-level container (e.g., CCC_genders)
		# Check if it has mandatory defaults
		if _local_config.is_child_mandatory and _local_config.default_child_id != "":
			_auto_select_default(_local_config, 0, model_tree)

func exit_and_save() -> void:
	_exit_session(true)

func exit_and_discard() -> void:
	_exit_session(false)

func _exit_session(emit_save: bool) -> void:
	if not _session_active:
		push_warning("exit called but session not active")
		return

	# Hide UI and camera
	ui.visible = false
	camera.current = false
	character_preview_spot.visible = false
	done_button.visible = false
	cancel_button.visible = false

	# Conditional emission
	if emit_save:
		character_saved.emit(export_character.duplicate())
	else:
		character_cancelled.emit()

	# Clear character preview meshes
	UIUtils.clear_children(character_preview_spot)

	# Clear state
	_clear_ui()
	export_character.clear()
	_session_active = false

func _on_done_pressed() -> void:
	if _session_active and not standalone_mode:
		exit_and_save()

func _on_cancel_pressed() -> void:
	if _session_active and not standalone_mode:
		exit_and_discard()

func _on_export_pressed() -> void:
	if not _session_active or not standalone_mode:
		push_warning("Export button pressed but not in standalone mode")
		return

	var character_name := name_field.text.strip_edges()

	if character_name.is_empty():
		push_error("Character name is required for export")
		return

	# Validate that we have a character to export
	if export_character.is_empty():
		push_error("No character configured to export")
		return

	# Get save path using ConfigLoader
	var file_path := ConfigLoader.get_character_save_path(character_name)
	if file_path == "":
		return

	# Ensure characters directory exists
	var characters_dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(characters_dir):
		DirAccess.make_dir_recursive_absolute(characters_dir)

	# Create a LocalConfig resource and save the flat character array
	# export_character is already flat (Array[CharacterComponent])
	var local_res := LocalConfig.new()
	local_res.items = export_character.duplicate()

	var err := ResourceSaver.save(local_res, file_path)
	if err == OK:
		print("Character exported successfully to: ", file_path)
		name_field.text = ""  # Clear the name field
		export_character.clear()  # Clear the current character
		_clear_ui()  # Clear UI
		_expand_top_level()  # Reset to fresh state
	else:
		push_error("Failed to save character to: " + file_path)
