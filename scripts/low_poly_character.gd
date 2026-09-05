extends CharacterBody3D

# === Configuration Properties ===
@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25
@export var gamepad_sensitivty := 3.0 
@export var zoom_speed := 1.0
@export var gamepad_zoom_speed := 2.0 
@export var min_zoom := 2.0
@export var max_zoom := 8.0

@export_group("Movement")
@export var move_speed := 6.0
@export var acceleration := 36.0
@export var rotation_speed := 12.0
@export var jump_strength := 12.0
@export var air_acceleration := 12.0

@export_group("UI Navigation")
@export var gamepad_cursor_speed := 800.0 

# === Internal State Variables ===
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.FORWARD
var _gravity := -30.0
var _was_airborne := false
var _target_zoom := 4.0

# Ref to player scene
const PLAYER_SCENE = preload("res://scenes/low_poly_character.tscn")

# === Node References ===
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D
@onready var _camera_origin: Node3D = $SpringArmPivot
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var anim_tree = $AnimationTree
@onready var _mesh_default_y : float = body_mesh.position.y 
@onready var grocery_red: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var grocery_blue: MeshInstance3D = $Armature/Skeleton3D/GroceryBlue


func _ready() -> void:
	print(
		"PLAYER READY: ",
		name,
		" authority=",
		get_multiplayer_authority(),
		" local_id=",
		multiplayer.get_unique_id()
	)
	
	# Initialize the AnimationTree.
	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true

	# Capture the initial placement rotation from the level editor.
	_last_movement_direction = -global_transform.basis.z
	body_mesh.rotation.y = 0.0

	# Only the locally controlled Player should capture
	# the mouse.
	if is_multiplayer_authority():
		print("PLAYER ", name, ": I HAVE AUTHORITY")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	
	# Accumulate relative mouse motion values to process camera rotation later
	var is_camera_motion := (
		event is InputEventMouseMotion and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)
	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sensitivity
	
	# Handle camera distance zooming via the mouse scroll wheel
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom += zoom_speed
		
		_target_zoom = clamp(_target_zoom, min_zoom, max_zoom)


func _physics_process(delta: float) -> void:
	
	# Only the Player who owns this node should process
	# keyboard/controller input and movement.
	if not is_multiplayer_authority():
		return
	
	# --- 1. Camera View Tracking / UI Mouse Simulation ---
	var gamepad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	
	# BRANCH: If menu is open, right stick drives virtual cursor position instead of camera
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		if gamepad_look.length() > 0.05:
			var current_mouse_pos := get_viewport().get_mouse_position()
			var new_mouse_pos := current_mouse_pos + (gamepad_look * gamepad_cursor_speed * delta)
			
			# Clamp the cursor coordinates within window boundaries
			var window_size := get_viewport().get_visible_rect().size
			new_mouse_pos.x = clamp(new_mouse_pos.x, 0, window_size.x)
			new_mouse_pos.y = clamp(new_mouse_pos.y, 0, window_size.y)
			
			get_viewport().warp_mouse(new_mouse_pos)
		
	else:
		# Process standard camera orbit manipulations when actively playing
		if gamepad_look.length() > 0.05:
			_camera_input_direction += gamepad_look * gamepad_sensitivty
			
		_camera_origin.rotation.x -= _camera_input_direction.y * delta
		_camera_origin.rotation.x = clamp(_camera_origin.rotation.x, -PI / 2.75, PI / 6.5)
		_camera_origin.rotation.y -= _camera_input_direction.x * delta
		_camera_input_direction = Vector2.ZERO

	# Handle D-pad camera zooming
	if Input.is_action_pressed("zoom_in"):
		_target_zoom -= gamepad_zoom_speed * delta
	elif Input.is_action_pressed("zoom_out"):
		_target_zoom += gamepad_zoom_speed * delta
	_target_zoom = clamp(_target_zoom, min_zoom, max_zoom)

	# Smoothly interpolate the boom arm length toward the target zoom setting
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, 8.0 * delta)

	# --- 2. Directional Movement Vectors ---
	var raw_input := Input.get_vector("left", "right", "up", "down")
	var forward := Vector3.BACK.rotated(Vector3.UP, _camera_origin.global_rotation.y)
	var right := forward.rotated(Vector3.UP, PI/2)
	var move_direction := (forward * raw_input.y + right * raw_input.x).normalized()
	
	# --- 3. Velocity and Kinematics ---
	var y_velocity := velocity.y
	velocity.y = 0.0
	var current_acceleration := acceleration if is_on_floor() else air_acceleration
	velocity = velocity.move_toward(move_direction * move_speed, current_acceleration * delta)
	velocity.y = y_velocity + _gravity * delta
	
	# --- 4. Animation Blend Configuration ---
	var horizontal_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	anim_tree.set("parameters/BlendSpace1D/blend_position", horizontal_speed / move_speed)
	
	var is_starting_jump := Input.is_action_just_pressed("jump") and is_on_floor()
	if is_starting_jump:
		velocity.y += jump_strength
	
	anim_tree.set("parameters/conditions/is_falling", not is_on_floor())
	anim_tree.set("parameters/conditions/is_grounded", is_on_floor())
		
	# --- 5. Visual Impact Secondary Effects ---
	if is_on_floor() and _was_airborne:
		body_mesh.position.y = _mesh_default_y - 0.3 
		_was_airborne = false
	elif not is_on_floor():
		_was_airborne = true
		
	if body_mesh.position.y < _mesh_default_y:
		body_mesh.position.y = move_toward(body_mesh.position.y, _mesh_default_y, 5.0 * delta)
	
	# --- 6. Execution ---
	move_and_slide()

	# --- 7. Mesh Rotation Alignment ---
	if move_direction.length() > 0.2:
		_last_movement_direction = move_direction

	var local_movement_dir := global_transform.basis.inverse() * _last_movement_direction
	var target_angle := Vector3.FORWARD.signed_angle_to(local_movement_dir, Vector3.UP)
	body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, target_angle, rotation_speed * delta)


func set_character(character_id: int) -> void:
	grocery_red.visible = character_id == 0
	grocery_blue.visible = character_id == 1
	
	body_mesh = grocery_red if character_id == 0 else grocery_blue
	_mesh_default_y = body_mesh.position.y
