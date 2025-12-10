extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const CAMERA_DISTANCE := 2.5
const CAMERA_HEIGHT := 1.5

@onready var character: CCharacter = $CCharacter
@onready var camera: Camera3D = $Camera3D

var _movement_enabled: bool = true
var _camera_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera_position()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _movement_enabled:
		_camera_rotation.x -= event.relative.x * MOUSE_SENSITIVITY  # Yaw (horizontal)
		_camera_rotation.y -= event.relative.y * MOUSE_SENSITIVITY  # Pitch (vertical)
		_camera_rotation.y = clamp(_camera_rotation.y, -PI/3, PI/3)  # Limit vertical rotation
		_update_camera_position()

func _update_camera_position() -> void:
	var offset := Vector3(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	offset = offset.rotated(Vector3.UP, _camera_rotation.x)
	offset = offset.rotated(Vector3.RIGHT.rotated(Vector3.UP, _camera_rotation.x), _camera_rotation.y)
	camera.global_position = global_position + offset
	camera.look_at(global_position + Vector3(0, 1, 0))

func _physics_process(delta: float) -> void:
	if not _movement_enabled:
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement relative to camera direction (WASD)
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0

	# Get camera's forward and right directions (ignoring vertical component)
	var cam_forward := -camera.global_transform.basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var cam_right := camera.global_transform.basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()

	# Fix: negate input_dir.y to match forward = negative z
	var direction := (cam_right * input_dir.x - cam_forward * input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_update_camera_position()

func disable_movement() -> void:
	_movement_enabled = false
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func enable_movement() -> void:
	_movement_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
