extends CharacterBody3D

#variables
@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25

@export_group("Movement")
@export var move_speed := 8.0
@export var acceleration := 20.0
@export var rotation_speed := 12.0
@export var jump_strength := 12.0

var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.FORWARD
var _gravity := -30.0

@onready var _camera_origin: Node3D = %CameraOrigin
@onready var _camera: Camera3D = %Camera3D
@onready var body_mesh: MeshInstance3D = %BodyMesh

#capture mouse on click, release mouse on escape
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
#set camera input direction to the mouse position if mouse is captured
func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (
		event is InputEventMouseMotion and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)
	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sensitivity

#rotate the camera when mouse is moved. clamped to avoid odd rotations
func _physics_process(delta: float) -> void:
	_camera_origin.rotation.x -= _camera_input_direction.y * delta
	_camera_origin.rotation.x = clamp(_camera_origin.rotation.x, -PI / 2.75, PI / 6.5)
	_camera_origin.rotation.y -= _camera_input_direction.x * delta
	
	_camera_input_direction = Vector2.ZERO

	var raw_input := Input.get_vector("left", "right", "up", "down")

	var forward := Vector3.BACK.rotated(Vector3.UP, _camera_origin.rotation.y)
	var right := forward.rotated(Vector3.UP, PI/2)

	var move_direction := forward * raw_input.y + right * raw_input.x

	#move_direction.y = 0.0
	move_direction = move_direction.normalized()
	
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	velocity.y = y_velocity + _gravity * delta
	
	var is_starting_jump := Input.is_action_just_pressed("jump") and is_on_floor()
	if is_starting_jump:
		velocity.y += jump_strength
	
	move_and_slide()

	if move_direction.length() > 0.2:
		_last_movement_direction = move_direction
	var target_angle := Vector3.FORWARD.signed_angle_to(_last_movement_direction, Vector3.UP)
	body_mesh.global_rotation.y = lerp_angle(body_mesh.rotation.y, target_angle, rotation_speed * delta)
		
