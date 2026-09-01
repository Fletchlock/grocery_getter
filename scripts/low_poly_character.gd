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

# === Node References ===
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D
@onready var _camera_origin: Node3D = $SpringArmPivot
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/Cube
@onready var anim_tree = $AnimationTree
@onready var _mesh_default_y : float = body_mesh.position.y 
@onready var close_button: Button = $"../../CanvasLayer/CloseButton"

# ADDED: Link your new UI texture node right here
@onready var virtual_cursor: TextureRect = $"../../CanvasLayer/VirtualCursor"


func _ready() -> void:
	# Initialize the AnimationTree state link
	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true
	
	# Set up initial application interface state
	close_button.visible = false
	virtual_cursor.visible = false # Keep software pointer hidden until paused
	
	# Explicitly capture the mouse and force the system cursor to hide instantly
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# FIX: Warp the physical hardware mouse off-screen instantly on launch.
	# This clears the phantom cursor leftover from clicking the editor's play button.
	get_viewport().warp_mouse(Vector2(-100, -100))
	
	# Snap the software cursor data position to the initial viewport coordinates
	virtual_cursor.global_position = get_viewport().get_mouse_position()
	
	# Capture the initial placement rotation from the level editor
	_last_movement_direction = -global_transform.basis.z
	body_mesh.rotation.y = 0.0



func _input(event: InputEvent) -> void:
	# Toggle mouse lock / UI state when pressing Escape or Gamepad Start
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_menu"):
		get_viewport().set_input_as_handled()
		
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN 
			close_button.visible = true
			virtual_cursor.visible = true # Show custom cursor image
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			close_button.visible = false
			virtual_cursor.visible = false # Hide custom cursor image
			
	# Handle simulated cursor clicking via the Right Trigger while menu is open
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN and event.is_action_pressed("ui_click"):
		var click_event := InputEventMouseButton.new()
		click_event.button_index = MOUSE_BUTTON_LEFT
		click_event.position = get_viewport().get_mouse_position()
		click_event.pressed = true
		Input.parse_input_event(click_event)
		
		var release_event := click_event.duplicate()
		release_event.pressed = false
		Input.parse_input_event(release_event)


func _unhandled_input(event: InputEvent) -> void:
	# Ignore tracking mouse movement inputs for camera controls when menu is active
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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
		
		# UPDATED: Permanently snap your TextureRect visual image to follow Godot's cursor coordinates
		virtual_cursor.global_position = get_viewport().get_mouse_position()
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
