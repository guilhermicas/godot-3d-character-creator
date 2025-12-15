@tool
class_name GridItem
extends PanelContainer
## Individual item in the character creator grid
## Shows icon, label, and optional settings button when selected

signal item_clicked(item: GridItem)
signal settings_clicked(item: GridItem)

var component: CharacterComponent
var is_selected: bool = false:
	set(value):
		is_selected = value
		_update_visual_state()

var is_loading: bool = false:
	set(value):
		is_loading = value
		_update_loading_state()

@onready var texture_rect: TextureRect = $VBox/TextureRect
@onready var label: Label = $VBox/Label
@onready var settings_button: Button = $VBox/TextureRect/SettingsButton
@onready var loading_indicator: ColorRect = $VBox/TextureRect/LoadingIndicator

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
		settings_button.visible = false  # Hidden until selected

	# Apply deferred states that were set before _ready
	# This handles is_loading and is_selected set before node was ready
	_update_loading_state()
	_update_visual_state()

func setup(comp: CharacterComponent, icon: Texture2D, icon_size: Vector2i, custom_loading: Resource = null) -> void:
	component = comp

	# Get references manually (node might not be ready yet, so @onready vars are null)
	var tex_rect := get_node_or_null("VBox/TextureRect") as TextureRect
	var lbl := get_node_or_null("VBox/Label") as Label
	var load_ind := get_node_or_null("VBox/TextureRect/LoadingIndicator") as ColorRect

	if tex_rect:
		tex_rect.texture = icon
		tex_rect.custom_minimum_size = icon_size
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if lbl:
		var display := comp.display_name if comp.display_name else comp.name
		lbl.text = display
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# Apply custom loading indicator if provided
	if load_ind and custom_loading:
		if custom_loading is Shader:
			var mat := ShaderMaterial.new()
			mat.shader = custom_loading
			load_ind.material = mat
		elif custom_loading is Texture2D:
			# For textures, use a TextureRect instead of ColorRect with shader
			# We'll overlay a texture by setting the color to white and using a texture
			load_ind.material = null
			load_ind.color = Color.WHITE
			# Create a child TextureRect for the texture
			var tex_child := load_ind.get_node_or_null("LoadingTexture") as TextureRect
			if not tex_child:
				tex_child = TextureRect.new()
				tex_child.name = "LoadingTexture"
				tex_child.set_anchors_preset(Control.PRESET_FULL_RECT)
				tex_child.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_child.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				load_ind.add_child(tex_child)
			tex_child.texture = custom_loading

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			item_clicked.emit(self)

func _on_settings_pressed() -> void:
	settings_clicked.emit(self)
	# TODO: Open albedo/shape key/material editor

func _update_visual_state() -> void:
	if not is_node_ready():
		return

	# Update border/style to show selection
	if is_selected:
		add_theme_stylebox_override("panel", _get_selected_style())
		if settings_button:
			settings_button.visible = true
	else:
		remove_theme_stylebox_override("panel")
		if settings_button:
			settings_button.visible = false

func _update_loading_state() -> void:
	if not is_node_ready():
		return

	if loading_indicator:
		loading_indicator.visible = is_loading
		# Reset loading indicator's modulate in case parent affected it
		loading_indicator.self_modulate.a = 1.0
	if texture_rect:
		# Use self_modulate to not affect children (like LoadingIndicator)
		texture_rect.self_modulate.a = 0.0 if is_loading else 1.0

func _get_selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.5)  # Subtle background
	style.border_color = Color(0.4, 0.7, 1.0, 1.0)  # Blue border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
