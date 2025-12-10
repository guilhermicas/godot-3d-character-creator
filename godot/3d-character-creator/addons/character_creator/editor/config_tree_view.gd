@tool
extends VBoxContainer
# Reusable tree view for displaying CharacterComponent hierarchy

signal node_selected(component: CharacterComponent)
signal add_child_requested(parent: CharacterComponent)
signal remove_requested(component: CharacterComponent)
signal property_changed(component: CharacterComponent, property: String, value: Variant)

@onready var tree: Tree = $HSplit/Tree
@onready var properties_panel: VBoxContainer = $HSplit/PropertiesPanel

var root_config: CharacterComponent
var editable_structure: bool = false
var global_config: CharacterComponent
var selected_component: CharacterComponent

func _ready() -> void:
	if tree:
		tree.item_selected.connect(_on_tree_item_selected)
		tree.button_clicked.connect(_on_tree_button_clicked)

func set_config(config: CharacterComponent, editable: bool, global_ref: CharacterComponent = null) -> void:
	root_config = config
	editable_structure = editable
	global_config = global_ref
	_rebuild_tree()

func _rebuild_tree() -> void:
	if not tree:
		return
	
	tree.clear()
	if not root_config:
		return
	
	var root := tree.create_item()
	tree.hide_root = false
	_populate_tree_item(root, root_config)

func _populate_tree_item(tree_item: TreeItem, component: CharacterComponent) -> void:
	var display := component.display_name if component.display_name else component.name
	var icon_text := "📁" if component.name.begins_with("CCC_") else "📦"
	
	tree_item.set_text(0, icon_text + " " + display)
	tree_item.set_metadata(0, component)
	
	# Add buttons if structure is editable
	if editable_structure and component.cc_id != "":
		tree_item.add_button(0, get_theme_icon("Add", "EditorIcons"), 0)
		tree_item.add_button(0, get_theme_icon("Remove", "EditorIcons"), 1)
	
	for child in component.children:
		var child_item := tree.create_item(tree_item)
		_populate_tree_item(child_item, child)

func _on_tree_item_selected() -> void:
	var selected := tree.get_selected()
	if not selected:
		return
	
	selected_component = selected.get_metadata(0)
	_show_properties(selected_component)
	node_selected.emit(selected_component)

func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	
	var component: CharacterComponent = item.get_metadata(0)
	
	if id == 0:  # Add child
		add_child_requested.emit(component)
	elif id == 1:  # Remove
		remove_requested.emit(component)

func _show_properties(component: CharacterComponent) -> void:
	if not properties_panel:
		return
	
	# Clear previous properties
	for child in properties_panel.get_children():
		child.queue_free()
	
	if not component:
		return
	
	var title := Label.new()
	title.text = "Properties"
	title.add_theme_font_size_override("font_size", 16)
	properties_panel.add_child(title)
	
	properties_panel.add_child(HSeparator.new())
	
	# Show read-only info
	var name_label := Label.new()
	name_label.text = "Name: " + component.name
	properties_panel.add_child(name_label)
	
	if component.cc_id != "":
		var id_label := Label.new()
		id_label.text = "ID: " + component.cc_id
		id_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		properties_panel.add_child(id_label)
	
	if component.glb_path != "":
		var path_label := Label.new()
		path_label.text = "Path: " + component.glb_path.get_file()
		path_label.tooltip_text = component.glb_path
		properties_panel.add_child(path_label)
	
	properties_panel.add_child(HSeparator.new())
	
	# Editable display_name
	var display_container := HBoxContainer.new()
	
	var display_label := Label.new()
	display_label.text = "Display Name:"
	display_label.custom_minimum_size.x = 100
	display_container.add_child(display_label)
	
	var display_edit := LineEdit.new()
	display_edit.text = component.display_name
	display_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_edit.text_changed.connect(func(new_text: String):
		component.display_name = new_text
		property_changed.emit(component, "display_name", new_text)
		_rebuild_tree()
	)
	display_container.add_child(display_edit)
	
	# Revert button if differs from global
	if global_config and editable_structure:
		var global_comp := _find_in_global(component.cc_id)
		if global_comp and global_comp.display_name != component.display_name:
			var revert_btn := Button.new()
			revert_btn.text = "↺"
			revert_btn.tooltip_text = "Revert to Global"
			revert_btn.pressed.connect(func():
				component.display_name = global_comp.display_name
				display_edit.text = global_comp.display_name
				property_changed.emit(component, "display_name", global_comp.display_name)
				_rebuild_tree()
			)
			display_container.add_child(revert_btn)
	
	properties_panel.add_child(display_container)

	# Defaults & Mandatory (CCC_ only)
	if component.glb_path == "" and not component.children.is_empty():
		properties_panel.add_child(HSeparator.new())

		var defaults_label := Label.new()
		defaults_label.text = "Defaults & Mandatory (CCC_ only)"
		defaults_label.add_theme_font_size_override("font_size", 14)
		properties_panel.add_child(defaults_label)

		# Mandatory checkbox
		var mandatory_container := HBoxContainer.new()
		var mandatory_check := CheckBox.new()
		mandatory_check.text = "Is Child Mandatory"
		mandatory_check.button_pressed = component.is_child_mandatory
		mandatory_check.toggled.connect(func(pressed: bool):
			component.is_child_mandatory = pressed
			property_changed.emit(component, "is_child_mandatory", pressed)
			_rebuild_tree()
			_show_properties(component)  # Refresh to update dropdown
		)
		mandatory_container.add_child(mandatory_check)
		properties_panel.add_child(mandatory_container)

		# Default child dropdown
		var default_container := HBoxContainer.new()

		var default_label := Label.new()
		default_label.text = "Default Child:"
		default_label.custom_minimum_size.x = 100
		default_container.add_child(default_label)

		var default_dropdown := OptionButton.new()
		default_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Populate with CC_ children
		var default_idx := 0  # Start at 0 for "(None)"
		default_dropdown.add_item("(None)")
		default_dropdown.set_item_metadata(0, "")  # Store empty string for None

		var dropdown_idx := 1  # Start children at index 1
		for child in component.children:
			if child.name.begins_with("CC_"):
				var display := child.display_name if child.display_name else child.name
				default_dropdown.add_item(display)
				default_dropdown.set_item_metadata(dropdown_idx, child.cc_id)
				if child.cc_id == component.default_child_id:
					default_idx = dropdown_idx
				dropdown_idx += 1

		# Select current default
		default_dropdown.select(default_idx)

		default_dropdown.item_selected.connect(func(selected_idx: int):
			var cc_id = default_dropdown.get_item_metadata(selected_idx)
			if cc_id == null:
				component.default_child_id = ""
			else:
				component.default_child_id = cc_id
			property_changed.emit(component, "default_child_id", component.default_child_id)
			_rebuild_tree()
		)

		default_container.add_child(default_dropdown)
		properties_panel.add_child(default_container)

	# TODO: Add metadata editor

func _find_in_global(cc_id: String) -> CharacterComponent:
	if not global_config:
		return null
	return _find_recursive(global_config, cc_id)

func _find_recursive(node: CharacterComponent, cc_id: String) -> CharacterComponent:
	if node.cc_id == cc_id:
		return node
	for child in node.children:
		var found := _find_recursive(child, cc_id)
		if found:
			return found
	return null
