extends Area3D

@export_node_path var creator_scene_path: NodePath
@export_node_path("CCharacter") var target_character_path: NodePath

var _player_nearby: bool = false
var _in_creator: bool = false
var _creator_scene: Node3D
var _target_character: CCharacter

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Resolve creator scene from NodePath
	if creator_scene_path:
		_creator_scene = get_node(creator_scene_path)
		if not _creator_scene:
			push_error("InteractionCube: creator_scene_path does not point to a valid node")
		elif _creator_scene.has_signal("character_saved"):
			_creator_scene.character_saved.connect(_on_character_saved)
			_creator_scene.character_cancelled.connect(_on_character_cancelled)
		else:
			push_error("InteractionCube: creator_scene does not have 'character_saved' signal")

	# Resolve target character from NodePath
	if target_character_path:
		_target_character = get_node(target_character_path) as CCharacter
		if not _target_character:
			push_error("InteractionCube: target_character_path does not point to a CCharacter node")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_E and event.pressed and not event.echo:
			if _player_nearby and not _in_creator:
				_enter_creator()
				get_viewport().set_input_as_handled()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false

func _enter_creator() -> void:
	if not _creator_scene:
		push_error("InteractionCube: No creator scene set")
		return

	if not _target_character:
		push_error("InteractionCube: No target character set")
		return

	_in_creator = true

	# Get current character config
	var current_config := _target_character.get_character_config()

	# Enter creator (it handles camera switching)
	_creator_scene.enter_with_character(current_config)

	# Disable player movement
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("disable_movement"):
		player.disable_movement()

func _on_character_saved(config: Array[CharacterComponent]) -> void:
	_in_creator = false

	# Apply new config to character
	if _target_character:
		_target_character.apply_character_config(config)

	# Re-enable player movement
	_enable_player_movement()

func _on_character_cancelled() -> void:
	_in_creator = false

	# Re-enable player movement
	_enable_player_movement()

func _enable_player_movement() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("enable_movement"):
		player.enable_movement()