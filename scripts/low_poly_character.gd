extends CharacterBody3D

# === Node References ===

@onready var _camera_origin: Node3D = $SpringArmPivot
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D
@onready var _camera: Camera3D = $SpringArmPivot/SpringArm3D/Camera3D


@onready var armature_node: Node3D = $Armature

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

#@onready var remote_transform_3d: RemoteTransform3D = $Armature/Skeleton3D/GroceryBlue/RemoteTransform3D
#@onready var remote_transform_3d: RemoteTransform3D = $Armature/Skeleton3D/GroceryGreen/RemoteTransform3D


	# Track carts that are close enough to grab
var nearby_carts: Array[RigidBody3D] = []
	# Track the cart we are currently pushing
var attached_cart: RigidBody3D = null


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


@export_group("Network Replication")
@export var network_position := Vector3.ZERO
@export var network_velocity := Vector3.ZERO
@export var network_anim_blend := 0.0
@export var network_is_falling := false
@export var network_is_grounded := true
@export var network_hat_visible := true
@export var network_on_moving_platform := false

var _network_position_history: Array[Dictionary] = []
var _network_position_last_received := Vector3.ZERO
var _network_velocity_last_received := Vector3.ZERO
var _network_velocity_received_time := 0.0
var _network_position_initialized := false

const NORMAL_INTERPOLATION_DELAY := 0.06
const PLATFORM_INTERPOLATION_DELAY := 0.0


@export_group("UI Navigation")
@export var gamepad_cursor_speed := 800.0


# === Internal State Variables ===

var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.FORWARD
var _gravity := -30.0
var _was_airborne := false
var _target_zoom := 4.0


# === Player Scene Reference ===

const PLAYER_SCENE = preload(
	"res://scenes/low_poly_character.tscn"
)


# Add this function directly ABOVE your func _ready() block!
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

	# Initialize the AnimationTree.
	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true

	# Capture the initial placement rotation from the level editor.
	_last_movement_direction = -global_transform.basis.z
	grocery_red.rotation.y = 0.0

	# Only the locally controlled player captures the mouse.
	if is_multiplayer_authority():
		print("PLAYER ", name, ": I HAVE AUTHORITY")

		_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

	_network_position_last_received = network_position
	_network_velocity_last_received = network_velocity
	_network_velocity_received_time = (
		Time.get_ticks_usec() / 1000000.0
	)

	# Inside your player script's _ready() function, at the very bottom:
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

	# Accumulate relative mouse motion for camera rotation.
	var is_camera_motion := (
		event is InputEventMouseMotion
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if is_camera_motion:
		_camera_input_direction = (
			event.screen_relative * mouse_sensitivity
		)

	# Mouse wheel zoom.
	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom -= zoom_speed

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom += zoom_speed

		_target_zoom = clamp(
			_target_zoom,
			min_zoom,
			max_zoom
		)

	#Cart handling code
	if event.is_action_pressed("interact"): # Make sure "interact" is mapped in Input Map
		if attached_cart == null:
			try_grab_cart()
		else:
			try_release_cart()


func try_grab_cart() -> void:
	if nearby_carts.is_empty():
		return
		
	attached_cart = nearby_carts[0]
	
	attached_cart.linear_velocity = Vector3.ZERO
	attached_cart.angular_velocity = Vector3.ZERO
	
	# Extract a forward direction from the camera origin
	var forward_dir = -_camera_origin.global_transform.basis.z
	forward_dir.y = 0.0 
	forward_dir = forward_dir.normalized()
	
	# Safe property look up for your cart's attach distance variable
	var distance_offset = 1.2
	if "attach_distance" in attached_cart:
		distance_offset = attached_cart.attach_distance
		
	var target_pos = global_position + (forward_dir * distance_offset)
	attached_cart.global_position = target_pos
	
	var target_look = target_pos + forward_dir
	attached_cart.look_at(target_look, Vector3.UP)
	
	# Force your complete armature container folder to match your camera forward look angle
	armature_node.global_rotation.y = _camera_origin.global_rotation.y
	
	# ============================================================
	# ORIGINAL SKELETONIK3D GRIP INITIALIZATION
	# ============================================================
	# Now that your cart node names match exactly, this lookup will connect!
	var left_target = attached_cart.get_node_or_null("LeftHandTarget")
	var right_target = attached_cart.get_node_or_null("RightHandTarget")
	
	if left_target and right_target:
		# Map the absolute scene tree paths directly over to the solvers
		left_hand_ik.target_node = left_target.get_path()
		right_hand_ik.target_node = right_target.get_path()
		
		# Ignite the calculation engine to bend the arms forward
		left_hand_ik.start()
		right_hand_ik.start()
	
	attached_cart.grab_cart(self)


func try_release_cart() -> void:
	if attached_cart:
		var forward_dir = -_camera_origin.global_transform.basis.z
		forward_dir.y = 0.0 
		if forward_dir.length_squared() > 0.001:
			_last_movement_direction = forward_dir.normalized()
			
		# ============================================================
		# TERMINATE SKELETONIK3D OVERRIDES
		# ============================================================
		# Stop tracking the handle markers so arms return to idle/running loops
		left_hand_ik.stop()
		right_hand_ik.stop()
		
		attached_cart.release_cart()
		attached_cart = null




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



func _physics_process(delta: float) -> void:

	# ============================================================
	# REMOTE PLAYER
	# ============================================================

	if not is_multiplayer_authority():
		set_anim_tree()

		var hat = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible

		# Detect a new received network state.
		if (
			network_position != _network_position_last_received
			or network_velocity != _network_velocity_last_received
		):

			var current_time := (
				Time.get_ticks_usec() / 1000000.0
			)

			_network_position_history.append({
				"time": current_time,
				"position": network_position,
				"velocity": network_velocity
			})

			_network_position_last_received = network_position
			_network_velocity_last_received = network_velocity
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

	# === 1. Camera View Tracking / UI Mouse Simulation ===

	var gamepad_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	# If a menu is open, the right stick controls the virtual mouse.
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:

		if gamepad_look.length() > 0.05:
			var current_mouse_pos := (
				get_viewport().get_mouse_position()
			)

			var new_mouse_pos := (
				current_mouse_pos
				+ gamepad_look
				* gamepad_cursor_speed
				* delta
			)

			var window_size := (
				get_viewport().get_visible_rect().size
			)

			new_mouse_pos.x = clamp(
				new_mouse_pos.x,
				0,
				window_size.x
			)

			new_mouse_pos.y = clamp(
				new_mouse_pos.y,
				0,
				window_size.y
			)

			get_viewport().warp_mouse(new_mouse_pos)

	else:

		# Normal camera orbit.
		if gamepad_look.length() > 0.05:
			_camera_input_direction += (
				gamepad_look * gamepad_sensitivty
			)

		_camera_origin.rotation.x -= (
			_camera_input_direction.y * delta
		)

		_camera_origin.rotation.x = clamp(
			_camera_origin.rotation.x,
			-PI / 2.75,
			PI / 6.5
		)

		_camera_origin.rotation.y -= (
			_camera_input_direction.x * delta
		)

		_camera_input_direction = Vector2.ZERO


	# === 2. Camera Zoom ===

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


	# === 3. Directional Movement ===

	var raw_input := Input.get_vector(
		"left",
		"right",
		"up",
		"down"
	)

	var forward := Vector3.BACK.rotated(
		Vector3.UP,
		_camera_origin.global_rotation.y
	)

	var right := forward.rotated(
		Vector3.UP,
		PI / 2
	)

	var move_direction := (
		forward * raw_input.y
		+ right * raw_input.x
	).normalized()


	# === 4. Velocity and Kinematics ===

	var y_velocity := velocity.y

	velocity.y = 0.0

	var current_acceleration := (
		acceleration
		if is_on_floor()
		else air_acceleration
	)

	velocity = velocity.move_toward(
		move_direction * move_speed,
		current_acceleration * delta
	)

	velocity.y = y_velocity + _gravity * delta


	# === 5. Animation State ===

	var horizontal_speed := Vector3(
		velocity.x,
		0.0,
		velocity.z
	).length()

	network_anim_blend = (
		horizontal_speed / move_speed
	)

	network_is_falling = not is_on_floor()
	network_is_grounded = is_on_floor()

	set_anim_tree()


	# === 6. Jump ===

	var is_starting_jump := (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	)

	if is_starting_jump:
		velocity.y += jump_strength


	# === 7. Landing / Visual Effects ===

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


	# === 8. Hat Toggle ===

	if Input.is_action_just_pressed("toggle_hat"):

		network_hat_visible = (
			not network_hat_visible
		)

		var hat = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible


	# === 9. Movement ===

	move_and_slide()

	network_position = global_position
	network_velocity = velocity

	network_on_moving_platform = (
		is_on_floor()
		and get_platform_velocity().length() > 0.1
	)

	# === 10. Mesh Rotation ===

	# Always keep the internal character skin bone mesh completely flat relative to its skeleton folder parent
	if body_mesh:
		body_mesh.rotation.y = 0.0

	if attached_cart == null:
		# NORMAL MODE: Smoothly spin the entire armature node container folder to face your travel path (WASD)
		if move_direction.length() > 0.2:
			_last_movement_direction = move_direction

		var local_movement_dir := (
			global_transform.basis.inverse()
			* _last_movement_direction
		)

		var target_angle := Vector3.FORWARD.signed_angle_to(
			local_movement_dir,
			Vector3.UP
		)

		armature_node.rotation.y = lerp_angle(
			armature_node.rotation.y,
			target_angle,
			rotation_speed * delta
		)
	else:
		# CART STRAFE MODE: Force the entire armature container folder to face your camera origin's look angle.
		var camera_yaw := _camera_origin.global_rotation.y
		var flat_camera_forward := Vector3.FORWARD.rotated(Vector3.UP, camera_yaw).normalized()
		var local_camera_dir := global_transform.basis.inverse() * flat_camera_forward
		
		var target_camera_angle := Vector3.FORWARD.signed_angle_to(
			local_camera_dir,
			Vector3.UP
		)
		
		armature_node.rotation.y = lerp_angle(
			armature_node.rotation.y,
			target_camera_angle,
			rotation_speed * delta
		)

	# ============================================================
	# DYNAMIC VECTOR-DRIVEN INTERACTION ZONE POSITIONING
	# ============================================================
	if is_multiplayer_authority():
		# Reconstruct a flat forward vector relative to the armature's actual facing direction
		var mesh_forward_dir = -armature_node.global_transform.basis.z
		mesh_forward_dir.y = 0.0
		mesh_forward_dir = mesh_forward_dir.normalized()
		
		var desired_zone_position = global_position + (mesh_forward_dir * 0.4) + Vector3(0, 1.0, 0)
		$Armature/Skeleton3D/CartDetector.global_position = desired_zone_position


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

	var interpolation_delay := NORMAL_INTERPOLATION_DELAY

	if network_on_moving_platform:
		interpolation_delay = PLATFORM_INTERPOLATION_DELAY

	var render_time := (
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

		var duration := newer_time - older_time

		if duration > 0.0:

			var weight := (
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

			return


	# ============================================================
	# DEAD RECKONING
	#
	# If we don't have a pair of snapshots available, predict
	# the remote player's position using its last received
	# velocity.
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

	var current_time := (
		Time.get_ticks_usec() / 1000000.0
	)

	var elapsed : float = (
		current_time
		- latest_snapshot["time"]
	)

	# Don't allow prediction to run indefinitely if packets
	# stop arriving.
	elapsed = min(elapsed, 0.25)

	global_position = (
		latest_position
		+ latest_velocity * elapsed
	)
