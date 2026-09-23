extends CharacterBody3D

# === Node References ===

@onready var _third_person_camera: Camera3D = $SpringArmPivot/SpringArm3D/Camera3D
@onready var _first_person_camera: Camera3D = $FirstPersonCameraPivot/FirstPersonCamera
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D

@onready var _spring_arm_pivot: Node3D = $SpringArmPivot
@onready var _first_person_pivot: Node3D = $FirstPersonCameraPivot
@export var network_first_person: bool = false

var _first_person: bool = true
#var _third_person_root_rotation_y: float = 0.0

@onready var armature_node: Node3D = $Armature
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var anim_tree = $AnimationTree
@onready var _mesh_default_y: float = $Armature.position.y

@onready var grocery_red: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var grocery_blue: MeshInstance3D = $Armature/Skeleton3D/GroceryBlue
@onready var grocery_green: MeshInstance3D = $Armature/Skeleton3D/GroceryGreen




# PushCart stuff
# === Hand IK References ===
@onready var left_hand_ik: SkeletonIK3D = $Armature/Skeleton3D/LeftHandIK
@onready var right_hand_ik: SkeletonIK3D = $Armature/Skeleton3D/RightHandIK
@onready var cart_detector: Area3D = $CartDetector


@export_group("Cart")
@export var strafe_rotation := 35.0
	# Track carts that are close enough to grab
var nearby_carts: Array[RigidBody3D] = []
	# Track the cart we are currently pushing
var attached_cart: RigidBody3D = null


# === Configuration Properties ===

@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25 ## Mouse camera sensitivity.
@export var gamepad_sensitivty := 3.0 ## Gamepad camera sensitivity.
@export var zoom_speed := 1.0 ## Mouse camera zoom speed.
@export var gamepad_zoom_speed := 2.0 ## Gamepad camera zoom speed.
@export var min_zoom := 2.0 ## Minimum camera distance.
@export var max_zoom := 8.0 ## Maximum camera distance.


@export_group("Movement")
@export var move_speed := 6.0 ## Maximum movement speed.
@export var acceleration := 36.0 ## Ground movement acceleration.
@export var rotation_speed := 12.0 ## Character rotation speed.
@export var jump_strength := 12.0 ## Initial upward force when jumping.
@export var air_acceleration := 12.0 ## Movement acceleration while airborne.


@export_group("Network Replication")
@export var network_position := Vector3.ZERO
@export var network_velocity := Vector3.ZERO
@export var network_rotation_y : float = 0.0
@export var network_anim_blend : float = 0.0
@export var network_is_falling : bool = false
@export var network_is_grounded : bool = true
@export var network_hat_visible : bool = true
@export var network_on_moving_platform : bool = false
@export var network_is_pushing_cart: bool = false

var _network_position_history: Array[Dictionary] = []
var _network_position_last_received := Vector3.ZERO
var _network_velocity_last_received := Vector3.ZERO
var _network_rotation_y_last_received : float = 0.0
var _network_velocity_received_time : float = 0.0
var _network_position_initialized : bool = false
var _network_first_person_last_received: bool = false

const NORMAL_INTERPOLATION_DELAY := 0.07
const PLATFORM_INTERPOLATION_DELAY := 0.05


@export_group("UI Navigation")
@export var gamepad_cursor_speed := 800.0


@export_group("Blink")
@export var blink_min_time: float = 2.5 ## Minimum time to wait before a blink.
@export var blink_max_time: float = 6.5 ## Maximum time to wait before a blink.
@export var blink_duration: float = 0.14 ## How long it takes for the eyes to close and reopen.
@export var blink_min_value: float = 0.32 ## Shape key value when the eyes are normally open.
@export var blink_max_value: float = 1.65 ## Shape key value when the eyes are fully closed.
@export_range(0.0, 1.0) var double_blink_chance: float = 0.08 ## Chance of a second blink after a normal blink.
@export var double_blink_delay: float = 0.10 ## Delay between the first and second blink.

var blink_timer := 0.0
var blink_progress := -1.0
var double_blink_pending := false

@export_group("Idle Look")
@export var look_distance: float = 5.0 ## Maximum distance to look at another player.
@export var look_speed: float = 5.0 ## Speed at which the head turns toward another player.
@export_range(0.0, 180.0) var look_angle: float = 90.0 ## Maximum angle from forward that the character will look.

@onready var look_at_modifier: LookAtModifier3D = $Armature/Skeleton3D/LookAtModifier3D
var look_target: Node3D = null

# === Internal State Variables ===
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.FORWARD
var _gravity := -30.0
var _was_airborne := false
var _target_zoom := 4.0


# === Player Scene Reference ===
const PLAYER_SCENE = preload(
	"res://scenes/low_poly_character_FP.tscn"
)


func _enter_tree() -> void:
	# Convert your node's string name (e.g. "933642306") into its real integer peer ID 
	# and claim network authority BEFORE any child nodes initialize!
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	print(
		"PLAYER READY: ",
		name,
		" authority=",
		get_multiplayer_authority(),
		" local_id=",
		multiplayer.get_unique_id()
	)
	
	if is_multiplayer_authority():
		
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	
	blink_timer = randf_range(blink_min_time, blink_max_time)
	
	# Initialize the AnimationTree.
	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true

	# Capture the initial placement rotation from the level editor.
	_last_movement_direction = -global_transform.basis.z
	#_third_person_root_rotation_y = rotation.y
	grocery_red.rotation.y = 0.0

		
	# Set the player's selected character.
	var character := LobbyManager.get_character(
		get_multiplayer_authority()
	)

	match character:
		"red":
			set_character(0)
			body_mesh = grocery_red

		"blue":
			set_character(1)
			body_mesh = grocery_blue

		"green":
			set_character(2)
			body_mesh = grocery_green

	if is_multiplayer_authority():
		_set_perspective(true)

	_network_position_last_received = network_position
	_network_velocity_last_received = network_velocity
	_network_rotation_y_last_received = network_rotation_y
	_network_velocity_received_time = (
		Time.get_ticks_usec() / 1000000.0
	)

	# 
	_network_position_initialized = false # (Your current last line)

	# --- FIXED MULTIPLAYER SYNCHRONIZER TIMING BUFFER ---
	# We search through the entire character folder hierarchy dynamically, 
	# completely preventing "null instance" layout crashes if paths change!
	var sync_node: MultiplayerSynchronizer = null
	
	if has_node("MultiplayerSynchronizer"):
		sync_node = $MultiplayerSynchronizer
	else:
		# Fallback: Loop through your child nodes to locate it dynamically
		for child in get_children():
			if child is MultiplayerSynchronizer:
				sync_node = child
				break
				
	# If found safely, initialize visibility states cleanly
	if sync_node != null and is_multiplayer_authority():
		sync_node.public_visibility = true




func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("toggle_perspective"):
		_toggle_perspective()
		return

	var is_camera_motion := (
		event is InputEventMouseMotion
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if is_camera_motion:
		_camera_input_direction = (
			event.screen_relative * mouse_sensitivity
		)
		# Mouse wheel zoom.
	if event is InputEventMouseButton and event.pressed and not _first_person:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom -= zoom_speed

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom += zoom_speed

		_target_zoom = clamp(
			_target_zoom,
			min_zoom,
			max_zoom
		)
	
	# Accumulate relative mouse motion for camera rotation.
	if (
		event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		_camera_input_direction = (
			event.screen_relative * mouse_sensitivity
		)
	
	
	# Cart handling.
	if event.is_action_pressed("interact"):
		if attached_cart == null:
			try_grab_cart()
		else:
			try_release_cart()


func _toggle_perspective() -> void:
	_set_perspective(not _first_person)


func _set_perspective(first_person: bool) -> void:
	_first_person = first_person

	grocery_red.visible = false
	grocery_blue.visible = false
	grocery_green.visible = false

	if _first_person:
		# Transfer the current third-person camera yaw
		# to the player root before switching to first person.
		rotation.y = _spring_arm_pivot.global_rotation.y

		# Keep the same vertical look angle.
		_first_person_pivot.rotation.x = _spring_arm_pivot.rotation.x

		_first_person_camera.make_current()

	else:
		# Transfer the first-person facing to the third-person camera.
		_spring_arm_pivot.global_rotation.y = rotation.y

		# Keep the same vertical look angle.
		_spring_arm_pivot.rotation.x = _first_person_pivot.rotation.x

		# Match the character's facing to the camera direction.
		var camera_yaw: float = _spring_arm_pivot.global_rotation.y

		var flat_camera_forward: Vector3 = (
			Vector3.FORWARD.rotated(
				Vector3.UP,
				camera_yaw
			).normalized()
		)

		_last_movement_direction = flat_camera_forward

		var local_camera_dir: Vector3 = (
			global_transform.basis.inverse()
			* flat_camera_forward
		)

		var target_camera_angle: float = (
			Vector3.FORWARD.signed_angle_to(
				local_camera_dir,
				Vector3.UP
			)
		)

		armature_node.rotation.y = target_camera_angle

		_third_person_camera.make_current()
		body_mesh.visible = true

	network_first_person = _first_person

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func try_grab_cart() -> void:
	if nearby_carts.is_empty():
		return

	attached_cart = nearby_carts[0]

	attached_cart.linear_velocity = Vector3.ZERO
	attached_cart.angular_velocity = Vector3.ZERO

	var forward_dir: Vector3 = get_camera_forward()

	if _first_person:
		armature_node.global_rotation.y = global_rotation.y

	var distance_offset: float = 1.0

	if "attach_distance" in attached_cart:
		distance_offset = attached_cart.attach_distance

	var target_pos: Vector3 = (
		global_position
		+ forward_dir * distance_offset
	)

	attached_cart.global_position = target_pos

	var target_look: Vector3 = target_pos + forward_dir
	attached_cart.look_at(
		target_look,
		Vector3.UP
	)

	var cart_path: NodePath = attached_cart.get_path()

	sync_ik_start.rpc(cart_path)

	attached_cart.grab_cart(self)


func try_release_cart() -> void:
	if attached_cart:
		var forward_dir: Vector3 = get_camera_forward()

		if forward_dir.length_squared() > 0.001:
			_last_movement_direction = forward_dir

		# ============================================================
		# TERMINATE SKELETONIK3D OVERRIDES
		# ============================================================

		sync_ik_stop.rpc()

		attached_cart.release_cart()
		attached_cart = null

# Cart RPCs
@rpc("any_peer", "call_local")
func sync_ik_start(cart_node_path: NodePath) -> void:
	network_is_pushing_cart = true
	
	# Look up the node directly using the received network path flag
	var target_cart = get_node_or_null(cart_node_path) as RigidBody3D
	
	if target_cart and left_hand_ik and right_hand_ik:
		var left_target = target_cart.get_node_or_null("LeftHandTarget")
		var right_target = target_cart.get_node_or_null("RightHandTarget")
		
		if left_target and right_target:
			left_hand_ik.target_node = left_target.get_path()
			right_hand_ik.target_node = right_target.get_path()
			
			left_hand_ik.start()
			right_hand_ik.start()


@rpc("any_peer", "call_local")
func sync_ik_stop() -> void:
	network_is_pushing_cart = false
	
	if left_hand_ik and right_hand_ik:
		left_hand_ik.stop()
		right_hand_ik.stop()


# Helper function to find the cart linked to this player
func _find_active_push_cart() -> RigidBody3D:
	var root_node = get_tree().root
	var all_rigid_bodies = root_node.find_children("*", "RigidBody3D", true, false)
	
	for body in all_rigid_bodies:
		if body.has_method("is_cart") and body.player_character == self:
			return body as RigidBody3D
			
	return null



func _on_cart_detector_area_entered(area: Area3D) -> void:
	# Look up to the root of the cart to see if it's a valid push cart
	var cart_body = area.get_parent()
	if cart_body and cart_body.has_method("is_cart"):
		if not nearby_carts.has(cart_body):
			nearby_carts.append(cart_body)

func _on_cart_detector_area_exited(area: Area3D) -> void:
	var cart_body = area.get_parent()
	if cart_body and cart_body.has_method("is_cart"):
		nearby_carts.erase(cart_body)
		
		if attached_cart == cart_body:
			try_release_cart()


func _process(delta: float) -> void:

	#Blink
	if blink_progress < 0.0:
		blink_timer -= delta

		if blink_timer <= 0.0:
			blink_progress = 0.0
	else:
		blink_progress += delta / blink_duration

		var blink_amount: float = lerp(
			blink_min_value,
			blink_max_value,
			1.0 - abs(blink_progress * 2.0 - 1.0)
		)

		body_mesh.set_blend_shape_value(0, blink_amount)

		if blink_progress >= 1.0:
			blink_progress = -1.0

			if double_blink_pending:
				double_blink_pending = false
				blink_timer = randf_range(blink_min_time, blink_max_time)
			elif randf() < double_blink_chance:
				double_blink_pending = true
				blink_timer = double_blink_delay
			else:
				blink_timer = randf_range(blink_min_time, blink_max_time)
	
	update_idle_look(delta)

func _physics_process(delta: float) -> void:

	# ============================================================
	# REMOTE PLAYER
	# ============================================================

	if not is_multiplayer_authority():
		set_anim_tree()

		var hat = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible

		# (All your previous conditional IK code is gone from here!)
		
		# Detect a new received network state...
		if (
			network_position != _network_position_last_received
			or network_velocity != _network_velocity_last_received
			or network_rotation_y != _network_rotation_y_last_received
			or network_first_person != _network_first_person_last_received
		):


			var current_time := (
				Time.get_ticks_usec() / 1000000.0
			)

			_network_position_history.append({
				"time": current_time,
				"position": network_position,
				"velocity": network_velocity,
				"rotation_y": network_rotation_y,
				"first_person": network_first_person
			})

			_network_position_last_received = network_position
			_network_velocity_last_received = network_velocity
			_network_rotation_y_last_received = network_rotation_y
			_network_first_person_last_received = network_first_person
			_network_velocity_received_time = current_time

			while _network_position_history.size() > 10:
				_network_position_history.pop_front()

			if not _network_position_initialized:
				global_position = network_position
				_network_position_initialized = true

		_update_network_position()

		return


	# ============================================================
	# LOCAL PLAYER
	# ============================================================

	# === 1. Camera / Look ===

	var gamepad_look: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:

		if gamepad_look.length() > 0.05:
			var current_mouse_pos: Vector2 = (
				get_viewport().get_mouse_position()
			)

			var new_mouse_pos: Vector2 = (
				current_mouse_pos
				+ gamepad_look
				* gamepad_cursor_speed
				* delta
			)

			var window_size: Vector2 = (
				get_viewport().get_visible_rect().size
			)

			new_mouse_pos.x = clamp(
				new_mouse_pos.x,
				0.0,
				window_size.x
			)

			new_mouse_pos.y = clamp(
				new_mouse_pos.y,
				0.0,
				window_size.y
			)

			get_viewport().warp_mouse(new_mouse_pos)

	else:

		if gamepad_look.length() > 0.05:
			_camera_input_direction += (
				gamepad_look
				* gamepad_sensitivty
			)

	if _first_person:
		rotation.y -= (
			_camera_input_direction.x
			* delta
		)

		_first_person_pivot.rotation.x -= (
			_camera_input_direction.y
			* delta
		)

		_first_person_pivot.rotation.x = clamp(
			_first_person_pivot.rotation.x,
			-PI / 2.75,
			PI / 6.5
		)

	else:
		_spring_arm_pivot.rotation.x -= (
			_camera_input_direction.y
			* delta
		)

		_spring_arm_pivot.rotation.x = clamp(
			_spring_arm_pivot.rotation.x,
			-PI / 2.75,
			PI / 6.5
		)

		_spring_arm_pivot.rotation.y -= (
			_camera_input_direction.x
			* delta
		)

	_camera_input_direction = Vector2.ZERO

	# Camera Zoom for TPP
	
		
	if Input.is_action_pressed("zoom_in"):
		_target_zoom -= (
			gamepad_zoom_speed * delta
		)

	elif Input.is_action_pressed("zoom_out"):
		_target_zoom += (
			gamepad_zoom_speed * delta
		)

	_target_zoom = clamp(
		_target_zoom,
		min_zoom,
		max_zoom
	)

	_spring_arm.spring_length = lerp(
		_spring_arm.spring_length,
		_target_zoom,
		8.0 * delta
	)


	# === 2. Directional Movement ===

	var raw_input: Vector2 = Input.get_vector(
		"left",
		"right",
		"up",
		"down"
	)

	# Movement is relative to the player's horizontal facing.
	var camera_yaw: float

	if _first_person:
		camera_yaw = global_rotation.y
	else:
		camera_yaw = _spring_arm_pivot.global_rotation.y

	var forward: Vector3 = Vector3.BACK.rotated(
		Vector3.UP,
		camera_yaw
	)

	var right: Vector3 = forward.rotated(
		Vector3.UP,
		PI / 2.0
	)

	var move_direction: Vector3 = (
		forward * raw_input.y
		+ right * raw_input.x
	).normalized()


	# === 3. Velocity and Kinematics ===

	var y_velocity: float = velocity.y

	velocity.y = 0.0

	var current_acceleration: float = (
		acceleration
		if is_on_floor()
		else air_acceleration
	)

	velocity = velocity.move_toward(
		move_direction * move_speed,
		current_acceleration * delta
	)

	velocity.y = y_velocity + _gravity * delta


	# === 4. Animation State ===

	var horizontal_speed: float = Vector3(
		velocity.x,
		0.0,
		velocity.z
	).length()

	network_anim_blend = horizontal_speed / move_speed

	if attached_cart != null and horizontal_speed > 0.1:
		var armature_forward: Vector3 = (
			-armature_node.global_transform.basis.z
		)

		var movement_direction: Vector3 = Vector3(
			velocity.x,
			0.0,
			velocity.z
		).normalized()

		var forward_amount: float = (
			armature_forward.dot(movement_direction)
		)

		if forward_amount < 0.0:
			network_anim_blend = -network_anim_blend

	network_is_falling = not is_on_floor()
	network_is_grounded = is_on_floor()
	network_is_pushing_cart = (
		attached_cart != null
	)

	set_anim_tree()


	# === 5. Jump ===

	var is_starting_jump: bool = (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	)

	if is_starting_jump:
		velocity.y += jump_strength


	# === 6. Landing / Visual Effects ===

	if is_on_floor() and _was_airborne:

		body_mesh.position.y = (
			_mesh_default_y - 0.3
		)

		_was_airborne = false

	elif not is_on_floor():

		_was_airborne = true

	if body_mesh.position.y < _mesh_default_y:

		body_mesh.position.y = move_toward(
			body_mesh.position.y,
			_mesh_default_y,
			5.0 * delta
		)


	# === 7. Hat Toggle ===

	if Input.is_action_just_pressed("toggle_hat"):

		network_hat_visible = (
			not network_hat_visible
		)

		var hat: Node3D = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible


	# === 8. Movement ===

	move_and_slide()

	network_position = global_position
	network_velocity = velocity

	network_on_moving_platform = (
		is_on_floor()
		and get_platform_velocity().length() > 0.1
	)


	# === 9. Character Rotation ===

	if _first_person:
		network_rotation_y = rotation.y

	else:

		# Third person: preserve the original armature-based rotation.
		if body_mesh:
			body_mesh.rotation.y = 0.0

		if attached_cart == null:

			if move_direction.length() > 0.2:
				_last_movement_direction = move_direction

			var local_movement_dir: Vector3 = (
				global_transform.basis.inverse()
				* _last_movement_direction
			)

			var target_angle: float = Vector3.FORWARD.signed_angle_to(
				local_movement_dir,
				Vector3.UP
			)

			armature_node.rotation.y = lerp_angle(
				armature_node.rotation.y,
				target_angle,
				rotation_speed * delta
			)

		else:
			
			camera_yaw = _spring_arm_pivot.global_rotation.y
			
			var flat_camera_forward: Vector3 = (
				Vector3.FORWARD.rotated(
					Vector3.UP,
					camera_yaw
				).normalized()
			)

			var local_camera_dir: Vector3 = (
				global_transform.basis.inverse()
				* flat_camera_forward
			)

			var target_camera_angle: float = (
				Vector3.FORWARD.signed_angle_to(
					local_camera_dir,
					Vector3.UP
				)
			)

			var strafe_angle: float = 0.0

			if raw_input.x != 0.0:
				strafe_angle = (
					-raw_input.x
					* deg_to_rad(strafe_rotation)
				)

			var target_angle: float = (
				target_camera_angle
				+ strafe_angle
			)

			armature_node.rotation.y = lerp_angle(
				armature_node.rotation.y,
				target_angle,
				rotation_speed * delta
			)

		network_rotation_y = armature_node.global_rotation.y

	# ============================================================
	# CART DETECTOR POSITIONING
	# ============================================================

	if is_multiplayer_authority():
		var detector_forward: Vector3

		if _first_person:
			detector_forward = -global_transform.basis.z
		else:
			detector_forward = -armature_node.global_transform.basis.z

		detector_forward.y = 0.0

		if detector_forward.length_squared() > 0.001:
			detector_forward = detector_forward.normalized()

			cart_detector.global_position = (
				global_position
				+ detector_forward * 0.4
				+ Vector3(0.0, 1.0, 0.0)
			)

			cart_detector.global_rotation.y = atan2(
				-detector_forward.x,
				-detector_forward.z
			)


	# ============================================================
	# SMOOTHED MULTIPLAYER SKELETAL IK JITTER FILTER
	# ============================================================
	# If we are a remote client viewing another player push a cart,
	# we smoothly blend the local target paths to prevent network tick-rate 
	# stutter from shaking the spine, neck, and head bones!
	if not is_multiplayer_authority() and network_is_pushing_cart:
		# Locate the local hand markers we spawned inside the player scene tree earlier
		var local_left_marker = $Armature/Skeleton3D/GroceryRed/IK_LeftHandTarget
		var local_right_marker = $Armature/Skeleton3D/GroceryRed/IK_RightHandTarget
		
		# Locate the real moving network cart handle nodes
		var target_cart = _find_active_push_cart()
		if target_cart and local_left_marker and local_right_marker:
			var net_left_grip = target_cart.get_node_or_null("LeftHandTarget")
			var net_right_grip = target_cart.get_node_or_null("RightHandTarget")
			
			if net_left_grip and net_right_grip:
				# FIX: Instead of snapping instantly, we smoothly interpolate (lerp)
				# the local target anchors toward the jittery network handle positions.
				# 15.0 * delta serves as a dampening buffer, filtering out raw packet jumps!
				local_left_marker.global_transform = local_left_marker.global_transform.interpolate_with(
					net_left_grip.global_transform, 
					15.0 * delta
				)
				local_right_marker.global_transform = local_right_marker.global_transform.interpolate_with(
					net_right_grip.global_transform, 
					15.0 * delta
				)




func set_character(character_id: int) -> void:

	var characters: Array[MeshInstance3D] = [
		grocery_red,
		grocery_blue,
		grocery_green
	]

	for character in characters:
		character.visible = false

	body_mesh = characters[character_id]
	body_mesh.visible = true

	_mesh_default_y = body_mesh.position.y


func set_anim_tree() -> void:
	anim_tree.set(
		"parameters/BlendSpace1D/blend_position",
		network_anim_blend
	)

	anim_tree.set(
		"parameters/conditions/is_falling",
		network_is_falling
	)

	anim_tree.set(
		"parameters/conditions/is_grounded",
		network_is_grounded
	)


func _update_network_position() -> void:

	if _network_position_history.is_empty():
		return

	var interpolation_delay: float = NORMAL_INTERPOLATION_DELAY

	if network_on_moving_platform or network_is_pushing_cart:
		interpolation_delay = PLATFORM_INTERPOLATION_DELAY

	var render_time: float = (
		Time.get_ticks_usec() / 1000000.0
		- interpolation_delay
	)

	var older_snapshot: Dictionary
	var newer_snapshot: Dictionary

	for i in range(_network_position_history.size() - 1):

		var a: Dictionary = _network_position_history[i]
		var b: Dictionary = _network_position_history[i + 1]

		if (
			a["time"] <= render_time
			and b["time"] >= render_time
		):
			older_snapshot = a
			newer_snapshot = b
			break

	# ============================================================
	# INTERPOLATE WHEN WE HAVE TWO SNAPSHOTS
	# ============================================================

	if not older_snapshot.is_empty():

		var older_time: float = older_snapshot["time"]
		var newer_time: float = newer_snapshot["time"]

		var duration: float = newer_time - older_time

		if duration > 0.0:

			var weight: float = (
				(render_time - older_time)
				/ duration
			)

			weight = clamp(
				weight,
				0.0,
				1.0
			)

			var older_position: Vector3 = (
				older_snapshot["position"]
			)

			var newer_position: Vector3 = (
				newer_snapshot["position"]
			)

			global_position = older_position.lerp(
				newer_position,
				weight
			)

			var older_rotation: float = (
				older_snapshot["rotation_y"]
			)

			var newer_rotation: float = (
				newer_snapshot["rotation_y"]
			)

			var interpolated_rotation: float = lerp_angle(
				older_rotation,
				newer_rotation,
				weight
			)

			# Use the perspective state of the newer snapshot.
			var interpolated_first_person: bool = (
				newer_snapshot["first_person"]
			)

			if interpolated_first_person:
				rotation.y = interpolated_rotation
				armature_node.rotation.y = 0.0
			else:
				armature_node.global_rotation.y = interpolated_rotation
				rotation.y = 0.0

	# ============================================================
	# DEAD RECKONING
	# ============================================================

	var latest_snapshot: Dictionary = (
		_network_position_history[
			_network_position_history.size() - 1
		]
	)

	var latest_position: Vector3 = (
		latest_snapshot["position"]
	)

	var latest_velocity: Vector3 = (
		latest_snapshot["velocity"]
	)

	var latest_rotation: float = (
		latest_snapshot["rotation_y"]
	)

	var latest_first_person: bool = (
		latest_snapshot["first_person"]
	)

	var current_time: float = (
		Time.get_ticks_usec() / 1000000.0
	)

	var elapsed: float = (
		current_time
		- latest_snapshot["time"]
	)

	elapsed = min(elapsed, 0.25)

	global_position = (
		latest_position
		+ latest_velocity * elapsed
	)

	if latest_first_person:
		rotation.y = latest_rotation
		armature_node.rotation.y = 0.0
	else:
		armature_node.global_rotation.y = latest_rotation
		rotation.y = 0.0

func update_idle_look(delta: float) -> void:
	var grounded: bool = network_is_grounded

	if is_multiplayer_authority():
		grounded = is_on_floor()

	if not grounded:
		look_target = null
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			0.0,
			look_speed * delta
		)
		return

	look_target = find_nearest_player()
	

	if look_target != null:
		look_at_modifier.target_node = look_target.get_node("LookTarget").get_path()
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			1.0,
			look_speed * delta
		)
	else:
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			0.0,
			look_speed * delta
		)


func find_nearest_player() -> Node3D:
	var nearest_player: Node3D = null
	var nearest_distance: float = look_distance
	var max_angle: float = deg_to_rad(look_angle)
	var min_dot: float = cos(max_angle)

	for player in get_parent().get_children():
		if player == self or not player is CharacterBody3D:
			continue

		var to_player: Vector3 = player.global_position - global_position
		var distance: float = to_player.length()

		if distance >= nearest_distance:
			continue

		var direction: Vector3 = to_player.normalized()
		var forward: Vector3 = -$Armature.global_transform.basis.z

		if forward.dot(direction) < min_dot:
			continue

		nearest_distance = distance
		nearest_player = player

	return nearest_player


func get_camera_forward() -> Vector3:
	var active_camera: Camera3D

	if _first_person:
		active_camera = _first_person_camera
	else:
		active_camera = _third_person_camera

	var forward_dir: Vector3 = -active_camera.global_transform.basis.z
	forward_dir.y = 0.0

	if forward_dir.length_squared() > 0.001:
		forward_dir = forward_dir.normalized()

	return forward_dir
