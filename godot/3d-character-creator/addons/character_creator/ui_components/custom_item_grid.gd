@tool
extends VBoxContainer
## Custom grid/list control for character creator items
## Replaces ItemList with more flexibility
## Extends VBoxContainer to properly propagate minimum size from children

signal item_clicked(idx: int, at_position: Vector2, mouse_button_index: int)

@export var columns: int = 1:
	set(value):
		columns = max(1, value)
		if is_node_ready():
			_rebuild_layout()

@export var icon_size: Vector2i = Vector2i(64, 64):
	set(value):
		icon_size = value
		_update_icon_sizes()

@export var allow_multi_select: bool = false  ## Allow selecting multiple items

## Custom loading indicator (Shader or Texture2D) - passed to GridItems
var custom_loading_indicator: Resource

var _grid_item_scene: PackedScene
var _items: Array[GridItem] = []
var _selected_indices: Array[int] = []  # Supports multi-selection
var _inner_container: Container  # GridContainer or HFlowContainer for multi-column

func _ready() -> void:
	_grid_item_scene = load("res://addons/character_creator/ui_components/grid_item.tscn")
	_rebuild_layout()

func add_item(text: String, icon: Texture2D, metadata: Variant = null) -> int:
	if not _grid_item_scene:
		_grid_item_scene = load("res://addons/character_creator/ui_components/grid_item.tscn")

	# Ensure inner container exists
	if not _inner_container:
		_ensure_container_exists()

	var item: GridItem = _grid_item_scene.instantiate()
	item.setup(metadata, icon, icon_size, custom_loading_indicator)
	item.item_clicked.connect(_on_grid_item_clicked.bind(_items.size()))
	item.settings_clicked.connect(_on_grid_item_settings_clicked.bind(_items.size()))

	_items.append(item)

	if _inner_container:
		_inner_container.add_child(item)

	return _items.size() - 1

func clear() -> void:
	for item in _items:
		if item and is_instance_valid(item):
			item.queue_free()
	_items.clear()
	_selected_indices.clear()

func select(idx: int) -> void:
	if idx < 0 or idx >= _items.size():
		return

	if allow_multi_select:
		# Multi-select: toggle selection
		if idx in _selected_indices:
			return  # Already selected, don't re-add
		_selected_indices.append(idx)
		_items[idx].is_selected = true
	else:
		# Single select: deselect previous, select new
		for sel_idx in _selected_indices:
			if sel_idx >= 0 and sel_idx < _items.size():
				_items[sel_idx].is_selected = false
		_selected_indices.clear()
		_selected_indices.append(idx)
		_items[idx].is_selected = true

func deselect(idx: int) -> void:
	"""Deselect a specific item by index"""
	if idx < 0 or idx >= _items.size():
		return

	var pos := _selected_indices.find(idx)
	if pos >= 0:
		_selected_indices.remove_at(pos)
		_items[idx].is_selected = false

func deselect_all() -> void:
	for sel_idx in _selected_indices:
		if sel_idx >= 0 and sel_idx < _items.size():
			_items[sel_idx].is_selected = false
	_selected_indices.clear()

func is_selected(idx: int) -> bool:
	"""Check if an item is currently selected"""
	return idx in _selected_indices

func get_item_metadata(idx: int) -> Variant:
	if idx < 0 or idx >= _items.size():
		return null
	return _items[idx].component

func set_item_text(idx: int, text: String) -> void:
	if idx < 0 or idx >= _items.size():
		return
	if _items[idx].label:
		_items[idx].label.text = text

func set_item_loading(idx: int, loading: bool) -> void:
	if idx < 0 or idx >= _items.size():
		return
	_items[idx].is_loading = loading

func get_selected_items() -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in _selected_indices:
		result.append(idx)
	return result

func _on_grid_item_clicked(item: GridItem, idx: int) -> void:
	var mouse_pos: Vector2 = item.get_local_mouse_position()
	item_clicked.emit(idx, mouse_pos, MOUSE_BUTTON_LEFT)

func _on_grid_item_settings_clicked(_item: GridItem, idx: int) -> void:
	# TODO: Emit settings signal for handling externally
	pass

func _ensure_container_exists() -> void:
	"""Create inner container if it doesn't exist"""
	if _inner_container:
		return

	# For single column, we ARE the VBoxContainer, so add items directly
	# For multi-column, create a GridContainer child
	if columns > 1:
		var grid := GridContainer.new()
		grid.columns = columns
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inner_container = grid
		add_child(_inner_container)
	else:
		# Use self as container (we extend VBoxContainer)
		_inner_container = self

func _rebuild_layout() -> void:
	if not is_node_ready():
		return

	# Save items before clearing
	var saved_items := _items.duplicate()

	# Remove old inner container if it's a child (not self)
	if _inner_container and _inner_container != self:
		_inner_container.queue_free()
	_inner_container = null

	# Create new container
	_ensure_container_exists()

	# Re-add existing items
	for item in saved_items:
		if is_instance_valid(item):
			if item.get_parent():
				item.get_parent().remove_child(item)
			_inner_container.add_child(item)

func _update_icon_sizes() -> void:
	for item in _items:
		if is_instance_valid(item) and item.texture_rect:
			item.texture_rect.custom_minimum_size = icon_size
