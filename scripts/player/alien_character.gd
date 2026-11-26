
extends CharacterBody3D


# ============================================================
# ENUMS
# ============================================================

enum ItemOrigin {
	NONE,
	PRODUCT_DISPLAY,
	CART_GRID,
	CHECKOUT_GRID,
	ORDER_GRID
}


# ============================================================
# CONSTANTS
# ============================================================

const FOOTSTEP_COOLDOWN_MS: int = 180

const NORMAL_INTERPOLATION_DELAY: float = 0.07
const PLATFORM_INTERPOLATION_DELAY: float = 0.05


# ============================================================
# EXPORTED CONFIGURATION
# ============================================================

@export_group("Movement")
@export var walk_speed: float = 3.5 ## Speed while walking.
@export var sprint_speed: float = 6.0 ## Speed while sprinting.
@export var crouch_speed: float = 2.0 ## Speed while crouching.
@export var acceleration: float = 36.0 ## Ground movement acceleration.
@export var rotation_speed: float = 12.0 ## Character rotation speed.
@export var jump_strength: float = 10.0 ## Initial upward force when jumping.
@export_range(0.1, 1.0, 0.05)
var jump_release_multiplier: float = 0.40
@export var air_acceleration: float = 3.0 ## Movement acceleration while airborne.


@export_group("Camera")
@export_range(0.0, 1.0, 0.0001)
var mouse_sensitivity: float = 0.0017 ## Mouse camera sensitivity.
@export_range(0.0, 100.0, 1.0)
var mouse_smoothing: float = 25.0
@export var gamepad_sensitivity: float = 3.0 ## Gamepad camera sensitivity.
@export var zoom_speed: float = 1.0 ## Mouse camera zoom speed.
@export var gamepad_zoom_speed: float = 2.0 ## Gamepad camera zoom speed.
@export var min_zoom: float = 2.0 ## Minimum camera distance.
@export var max_zoom: float = 8.0 ## Maximum camera distance.


@export_group("Cart")
@export var strafe_rotation: float = 35.0
@export var attached_cart: RigidBody3D = null


@export_group("Knockback")
@export var knockback_decay: float = 8.0


@export_group("Blink")
@export var blink_min_time: float = 2.5 ## Minimum time between blinks.
@export var blink_max_time: float = 6.5 ## Maximum time between blinks.
@export var blink_duration: float = 0.14 ## Duration of a complete blink.
@export var blink_min_value: float = 0.32 ## Open eye blend shape value.
@export var blink_max_value: float = 1.65 ## Closed eye blend shape value.
@export_range(0.0, 1.0)
var double_blink_chance: float = 0.08 ## Chance of a second blink.
@export var double_blink_delay: float = 0.10 ## Delay before the second blink.


@export_group("Idle Look")
@export var look_distance: float = 5.0 ## Maximum distance to another player.
@export var look_speed: float = 5.0 ## Head turning speed.
@export_range(0.0, 180.0)
var look_angle: float = 90.0 ## Maximum look angle from forward.


@export_group("UI Navigation")
@export var gamepad_cursor_speed: float = 500.0


@export_group("Checkout Cursor")
@export_range(1.0, 5.0, 0.1)
var checkout_controller_sensitivity: float = 2.0
@export_range(0.5, 5.0, 0.1)
var checkout_mouse_sensitivity: float = 1.4


@export_group("Checkout Cursor Item")
@export var checkout_cursor_offset: Vector2 = Vector2.ZERO
@export var checkout_cursor_depth: float = 1.0


@export_group("Held Product Rotation")
@export var held_product_rotation_sensitivity: float = 0.008


@export_group("Held Mop")
@export var mop_hold_position: Vector3 = Vector3(0.25, 0.0, 0.0)
@export var mop_hold_rotation: Vector3 = Vector3(110.0, 0.0, -25.0)


@export_group("Spill Cleaning")
@export var spill_cleaning_distance: float = 3.0


# ============================================================
# NETWORK REPLICATION
# ============================================================

@export_group("Network Replication")

# Movement and perspective.
@export var network_position: Vector3 = Vector3.ZERO
@export var network_velocity: Vector3 = Vector3.ZERO
@export var network_rotation_y: float = 0.0
@export var network_first_person: bool = false
@export var network_on_moving_platform: bool = false

# Animation.
@export var network_anim_blend: float = 0.0
@export var network_is_falling: bool = false
@export var network_is_grounded: bool = true
@export var network_is_crouching: bool = false
@export var network_is_pushing_cart: bool = false

# Held product.
@export var network_holding_item: bool = false
@export var network_held_item_path: String = ""

# Restock box.
@export var network_holding_restock_box: bool = false
@export var network_restock_box_product_path: String = ""
@export var network_restock_box_quantity: int = 0

# Restock scanner.
@export var network_holding_restock_scanner: bool = false

# Mop and spill cleaning.
@export var network_holding_mop: bool = false
@export var network_is_cleaning_spill: bool = false


# ============================================================
# NODE REFERENCES
# ============================================================

# Cameras and pivots.
@onready var _third_person_camera: Camera3D = $SpringArmPivot/SpringArm3D/Camera3D
@onready var _first_person_camera: Camera3D = $FirstPersonCameraPivot/FirstPersonCamera
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D
@onready var _spring_arm_pivot: Node3D = $SpringArmPivot
@onready var first_person_camera_pivot: Node3D = $FirstPersonCameraPivot
@onready var inspection_camera: Camera3D = $InspectionCameraPivot/InspectionCamera

# Character and animation.
@onready var armature_node: Node3D = $Armature
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh_default_y: float = $Armature.position.y

# Alien meshes.
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/AlienBody
@onready var alien_head: MeshInstance3D = $Armature/Skeleton3D/Head
@onready var alien_top: MeshInstance3D = $Armature/Skeleton3D/Top
@onready var alien_bottom: MeshInstance3D = $Armature/Skeleton3D/Bottom
@onready var alien_feet: MeshInstance3D = $Armature/Skeleton3D/Feet

# Skeleton modifiers and IK.
@onready var look_at_modifier: LookAtModifier3D = $Armature/Skeleton3D/LookAtModifier3D
@onready var left_hand_ik: TwoBoneIK3D = $Armature/Skeleton3D/LeftTwoBoneIK3D
@onready var right_hand_ik: TwoBoneIK3D = $Armature/Skeleton3D/RightTwoBoneIK3D
@onready var left_hand_rot: CopyTransformModifier3D = $Armature/Skeleton3D/LeftHandRotationModifier
@onready var right_hand_rot: CopyTransformModifier3D = $Armature/Skeleton3D/RightHandRotationModifier

# Interaction and equipment.
@onready var interact_raycast_3d: RayCast3D = $FirstPersonCameraPivot/FirstPersonCamera/InteractRaycast3D
@onready var held_item_holder: Node3D = $FirstPersonCameraPivot/HeldItemHolder
@onready var held_box_holder: Node3D = $FirstPersonCameraPivot/HeldBoxHolder
@onready var player_equipment: PlayerEquipment = $PlayerEquipment
@onready var player_checkout: PlayerCheckout = $PlayerCheckout
@onready var player_product_rotation: PlayerProductRotation = $PlayerProductRotation
@onready var cart_pusher: RigidBody3D = $CartPusher

# User interface.
@onready var crosshair: Control = $FirstPersonCameraPivot/FirstPersonCamera/UI/Crosshair

# Audio.
@onready var footstep_player: AudioStreamPlayer3D = $FirstPersonCameraPivot/FirstPersonCamera/FootstepPlayer
@onready var audio_listener: AudioListener3D = $AudioListener3D


# ============================================================
# MOVEMENT STATE
# ============================================================

var is_sprinting: bool = false
var is_crouching: bool = false
var movement_locked: bool = false
var block_movement_until_keys_released: bool = false

var _gravity: float = -30.0
var _last_movement_direction: Vector3 = Vector3.FORWARD
var _was_airborne: bool = false

var knockback_velocity: Vector3 = Vector3.ZERO
var conveyor_velocity: Vector3 = Vector3.ZERO


# ============================================================
# CAMERA STATE
# ============================================================

var _first_person: bool = true
var _target_zoom: float = 2.0

var _camera_input_direction: Vector2 = Vector2.ZERO
var _mouse_input_direction: Vector2 = Vector2.ZERO
var _smoothed_mouse_velocity: Vector2 = Vector2.ZERO

var camera_fade_tween: Tween = null
var inspection_camera_active: bool = false


# ============================================================
# ANIMATION AND VISUAL STATE
# ============================================================

var _smoothed_sprint_blend: float = 0.0
var _smoothed_crouch_blend: float = 0.0

# Blinking.
var blink_timer: float = 0.0
var blink_progress: float = -1.0
var double_blink_pending: bool = false

# Idle head tracking.
var look_target: Node3D = null

# Footsteps.
var last_footstep_time: int = 0


# ============================================================
# HELD PRODUCT STATE
# ============================================================

var held_item: ProductData = null
var held_item_visual: MeshInstance3D = null
var held_item_origin: ItemOrigin = ItemOrigin.NONE
var held_item_order_id: int = -1


# ============================================================
# RESTOCK BOX STATE
# ============================================================

var held_restock_box: RestockBox = null

# Server-authoritative contents of the carried box.
var server_restock_product_path: String = ""
var server_restock_quantity: int = 0


# ============================================================
# RESTOCK SCANNER STATE
# ============================================================

var held_restock_scanner: Node3D = null
var held_restock_scanner_holder: Node3D = null
var last_restock_wheel_time_usec: int = 0


# ============================================================
# MOP AND SPILL CLEANING STATE
# ============================================================

var held_mop: Node3D = null
var cleaning_spill: Spill = null
var cleaning_progress: float = 0.0

# Server-authoritative cleaning state.
var server_holding_mop: bool = false
var server_cleaning_spill_path: NodePath = NodePath()
var server_cleaning_started_usec: int = 0


# ============================================================
# CHECKOUT INTERFACE
# ============================================================

var checkout_mode_active: bool:
	get:
		return player_checkout.checkout_mode_active
	set(value):
		player_checkout.checkout_mode_active = value

var active_checkout: Checkout:
	get:
		return player_checkout.active_checkout
	set(value):
		player_checkout.active_checkout = value

var checkout_cursor_visual: MeshInstance3D:
	get:
		return player_checkout.checkout_cursor_visual

var checkout_scanned_product_path: String:
	get:
		return player_checkout.checkout_scanned_product_path
	set(value):
		player_checkout.checkout_scanned_product_path = value

var checkout_barcode_product_path: String = ""

# ============================================================
# NETWORK INTERPOLATION STATE
# ============================================================

var _network_position_history: Array[Dictionary] = []

var _network_position_last_received: Vector3 = Vector3.ZERO
var _network_velocity_last_received: Vector3 = Vector3.ZERO
var _network_rotation_y_last_received: float = 0.0
var _network_first_person_last_received: bool = false

var _network_velocity_received_time: float = 0.0
var _network_position_initialized: bool = false


# ============================================================
# NETWORK EQUIPMENT STATE
# ============================================================

# Held product.
var _network_holding_item_last_received: bool = false
var _network_held_item_path_last_received: String = ""

# Restock box.
var _network_holding_restock_box_last_received: bool = false
var _network_restock_box_product_path_last_received: String = ""
var _network_restock_box_quantity_last_received: int = 0

# Restock scanner.
var _network_holding_restock_scanner_last_received: bool = false

# Mop and spill cleaning.
var _network_holding_mop_last_received: bool = false
var _network_is_cleaning_spill_last_received: bool = false


# ============================================================
# GAMEPLAY INPUT HELPERS
# ============================================================

func can_process_gameplay_input() -> bool:
	return (
		is_multiplayer_authority()
		and GameManager.current_state == GameManager.GameState.PLAYING
	)


func is_holding_equipment() -> bool:
	return (
		held_item != null
		or held_restock_box != null
		or held_restock_scanner != null
		or held_mop != null
	)


func can_pickup_equipment() -> bool:
	return (
		not is_holding_equipment()
		and attached_cart == null
	)
	

# ============================================================
# MULTIPLAYER VALIDATION HELPERS
# ============================================================

func _is_valid_server_request(requesting_peer_id: int) -> bool:
	return (
		multiplayer.is_server()
		and get_multiplayer_authority() == requesting_peer_id
	)	


func _is_server_rpc() -> bool:
	return multiplayer.get_remote_sender_id() == 1
	

# ============================================================
# PLAYER INITIALIZATION
# ============================================================

func _enter_tree() -> void:
	# Convert your node's string name (e.g. "933642306") into its real integer peer ID 
	# and claim network authority BEFORE any child nodes initialize!
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	_initialize_player_authority()
	_initialize_animation()
	_initialize_perspective()
	_initialize_network_state()
	_initialize_network_synchronizer()


# ============================================================
# PLAYER INITIALIZATION HELPERS
# ============================================================

func _initialize_player_authority() -> void:
	var is_local_player: bool = is_multiplayer_authority()

	audio_listener.current = is_local_player

	if is_local_player:
		add_to_group("local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		crosshair.hide()


func _initialize_animation() -> void:
	blink_timer = randf_range(blink_min_time, blink_max_time)

	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true


func _initialize_perspective() -> void:
	if not is_multiplayer_authority():
		return

	# These minigames start in third-person perspective.
	var starts_in_third_person: bool = (
		get_parent().get_parent().name in [
			"OrangeSurvival",
			"ConveyorShowdown"
		]
	)

	_set_perspective(not starts_in_third_person)
	_update_alien_visibility()

	if starts_in_third_person:
		_target_zoom = max_zoom
		_spring_arm.spring_length = max_zoom


func _initialize_network_state() -> void:
	_network_position_last_received = network_position
	_network_velocity_last_received = network_velocity
	_network_rotation_y_last_received = network_rotation_y

	_network_velocity_received_time = (
		Time.get_ticks_usec() / 1000000.0
	)

	_network_position_initialized = false


func _initialize_network_synchronizer() -> void:
	var sync_node: MultiplayerSynchronizer = null

	if has_node("MultiplayerSynchronizer"):
		sync_node = $MultiplayerSynchronizer
	else:
		# Fall back to searching the player's direct children.
		for child in get_children():
			if child is MultiplayerSynchronizer:
				sync_node = child
				break

	if sync_node != null and is_multiplayer_authority():
		sync_node.public_visibility = true


# ============================================================
# PLAYER INPUT
# ============================================================


func _unhandled_input(event: InputEvent) -> void:
	if not can_process_gameplay_input():
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("LEFT CLICK: ", event)
			print("MATCHES INTERACT: ", event.is_action_pressed("interact"))
			print("JUST PRESSED BY EVENT: ",
				Input.is_action_just_pressed_by_event("interact", event))
	
	# Handle local held-product rotation before other input.
	if player_product_rotation.handle_held_product_rotation_input(event):
		return
	
	if checkout_mode_active:
		if event.is_action_pressed("checkout_exit"):
			exit_checkout_mode()
			get_viewport().set_input_as_handled()
			return

		# Track captured mouse movement in viewport coordinates.
		if event is InputEventMouseMotion:
			player_checkout.handle_mouse_motion(
				event,
				player_product_rotation.rotating_held_product,
				checkout_mouse_sensitivity
			)

			get_viewport().set_input_as_handled()
			return

		# Escape (or q) exits checkout mode.
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (
				event.keycode == KEY_ESCAPE
				or event.keycode == KEY_Q
	)
		):
			exit_checkout_mode()
			get_viewport().set_input_as_handled()
			return

		# E interacts with the product/scanner under the cursor.
		# Interact once per button press.
		if Input.is_action_just_pressed_by_event("interact", event):
			player_checkout.handle_checkout_interaction()
			get_viewport().set_input_as_handled()
			return

		# Left mouse button performs the same interaction.
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			player_checkout.handle_checkout_interaction()
			get_viewport().set_input_as_handled()
			return

		# Consume other input so normal gameplay cannot interfere.
		get_viewport().set_input_as_handled()
		return
	
	if handle_restock_scanner_input(event):
		return
	
	if (
		event.is_action_pressed("crouch")
		and attached_cart == null
		and not movement_locked
	):
		is_crouching = !is_crouching
		update_crouch_collision()
		
	var interact_pressed: bool = (
		Input.is_action_just_pressed_by_event("interact", event)
		or (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
	)

	if interact_pressed:
		if attached_cart != null:
			try_release_cart()
		elif not _start_spill_cleaning():
			if interact_raycast_3d.has_method("interact"):
				interact_raycast_3d.interact()

		return

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
		_mouse_input_direction += (
			event.screen_relative * mouse_sensitivity
		)
	
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_F9:
			toggle_inspection_camera()
			return


func _transition_to_perspective(first_person: bool) -> void:
	if camera_fade_tween != null:
		camera_fade_tween.kill()

	camera_fade_tween = create_tween()

	camera_fade_tween.tween_property(
		TransitionManager.fade_rect,
		"modulate:a",
		1.0,
		0.10
	)

	camera_fade_tween.tween_callback(
		func() -> void:
			_set_perspective(first_person)
	)

	camera_fade_tween.tween_property(
		TransitionManager.fade_rect,
		"modulate:a",
		0.0,
		0.10
	)


func _set_perspective(first_person: bool) -> void:
	_first_person = first_person

	if _first_person:
		rotation.y = _spring_arm_pivot.global_rotation.y
		first_person_camera_pivot.rotation.x = _spring_arm_pivot.rotation.x
		_first_person_camera.make_current()
		if interact_raycast_3d:
			interact_raycast_3d.enabled = true

	else:
		_spring_arm_pivot.global_rotation.y = rotation.y
		_spring_arm_pivot.rotation.x = first_person_camera_pivot.rotation.x
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
		
		if interact_raycast_3d:
			interact_raycast_3d.enabled = false

	network_first_person = _first_person
	
	crosshair.visible = is_multiplayer_authority() and _first_person
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	_update_alien_visibility()

func try_grab_cart(cart: RigidBody3D) -> void:
	if is_crouching:
		is_crouching = false
		update_crouch_collision()
	
	cart_pusher.set_collision_layer_value(2, false)
	
	attached_cart = cart

	attached_cart.linear_velocity = Vector3.ZERO
	attached_cart.angular_velocity = Vector3.ZERO

	var forward_dir: Vector3 = get_camera_forward()

	if _first_person:
		armature_node.global_rotation.y = global_rotation.y

	var distance_offset: float = 0.6
		
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
	
	_transition_to_perspective(false) # Third person
	if interact_raycast_3d:
		interact_raycast_3d.set_interaction_enabled(false)

func try_release_cart() -> void:
	if attached_cart:
		var forward_dir: Vector3 = get_camera_forward()
		
		cart_pusher.set_collision_layer_value(2, true)
		
		if forward_dir.length_squared() > 0.001:
			_last_movement_direction = forward_dir

		# ============================================================
		# TERMINATE SKELETONIK3D OVERRIDES
		# ============================================================

		sync_ik_stop.rpc()

		attached_cart.release_cart()
		attached_cart = null
		
		_transition_to_perspective(true) # First person
		if interact_raycast_3d:
			interact_raycast_3d.set_interaction_enabled(true)

# Cart RPCs
@rpc("any_peer", "call_local")
func sync_ik_start(cart_node_path: NodePath) -> void:
	network_is_pushing_cart = true
	anim_tree.set("parameters/PushCartBlend/blend_amount", 1.0)
	# Look up the node directly using the received network path flag
	var target_cart = get_node_or_null(cart_node_path) as RigidBody3D
	
	if target_cart and left_hand_ik and right_hand_ik:
		var left_target = target_cart.get_node_or_null("LeftHandTarget")
		var right_target = target_cart.get_node_or_null("RightHandTarget")
		
		if left_target and right_target:
			# Directly assign the target paths to the properties
			left_hand_ik.set_target_node(0, left_target.get_path())
			right_hand_ik.set_target_node(0, right_target.get_path())
		
			# Enable the modifier stack instantly
			left_hand_ik.influence = 1.0
			right_hand_ik.influence = 1.0
			
			# Set rotation targets to the same nodes and turn them on
			left_hand_rot.set_reference_node(
				0,
				left_hand_rot.get_path_to(left_target)
			)
			right_hand_rot.set_reference_node(
				0,
				right_hand_rot.get_path_to(right_target)
			)
			left_hand_rot.influence = 1.0
			right_hand_rot.influence = 1.0


@rpc("any_peer", "call_local")
func sync_ik_stop() -> void:
	network_is_pushing_cart = false
	anim_tree.set("parameters/PushCartBlend/blend_amount", 0.0)
	if left_hand_ik and right_hand_ik:
		# Disable the modifier stack instantly
		left_hand_ik.influence = 0.0
		right_hand_ik.influence = 0.0
		
		# Cleanly detach target references
		left_hand_ik.target_node = NodePath("")
		right_hand_ik.target_node = NodePath("")
		
		# Disable and clear rotation modifiers safely
		if left_hand_rot and right_hand_rot:
			left_hand_rot.influence = 0.0
			right_hand_rot.influence = 0.0
			left_hand_rot.set_reference_node(0, NodePath(""))
			right_hand_rot.set_reference_node(0, NodePath(""))


# Helper function to find the cart linked to this player
func _find_active_push_cart() -> RigidBody3D:
	var root_node = get_tree().root
	var all_rigid_bodies = root_node.find_children("*", "RigidBody3D", true, false)
	
	for body in all_rigid_bodies:
		if body.has_method("is_cart") and body.player_character == self:
			return body as RigidBody3D
			
	return null


# ============================================================
# FRAME PROCESS
# ============================================================

func _process(delta: float) -> void:
	_update_blink(delta)
	update_idle_look(delta)
	_update_equipment_ik(delta)
	_update_checkout_frame(delta)


# ============================================================
# CHARACTER BLINKING
# ============================================================

func _update_blink(delta: float) -> void:
	# Wait until the next blink.
	if blink_progress < 0.0:
		blink_timer -= delta

		if blink_timer <= 0.0:
			blink_progress = 0.0

		return

	# Advance the active blink.
	blink_progress += delta / blink_duration

	var blink_amount: float = lerp(
		blink_min_value,
		blink_max_value,
		1.0 - abs(blink_progress * 2.0 - 1.0)
	)

	_apply_blink_amount(blink_amount)

	if blink_progress >= 1.0:
		blink_progress = -1.0
		_schedule_next_blink()


func _apply_blink_amount(blink_amount: float) -> void:
	var blend_shape_count: int = (
		body_mesh.mesh.get_blend_shape_count()
	)

	for i: int in range(blend_shape_count):
		if body_mesh.mesh.get_blend_shape_name(i) == &"Blink":
			body_mesh.set_blend_shape_value(i, blink_amount)
			break


func _schedule_next_blink() -> void:
	if double_blink_pending:
		double_blink_pending = false
		blink_timer = double_blink_delay

	elif randf() < double_blink_chance:
		double_blink_pending = true
		blink_timer = double_blink_delay

	else:
		blink_timer = randf_range(
			blink_min_time,
			blink_max_time
		)


# ============================================================
# EQUIPMENT IK
# ============================================================

func _update_equipment_ik(delta: float) -> void:
	player_equipment.update_hand_targets(
		delta,
		network_is_crouching
	)

	player_equipment.update_mop_right_hand_target(delta)


# ============================================================
# CHECKOUT FRAME UPDATES
# ============================================================

func _update_checkout_frame(delta: float) -> void:
	player_checkout.update_checkout_controller_cursor(
		delta,
		is_multiplayer_authority(),
		gamepad_cursor_speed,
		checkout_controller_sensitivity
	)

	player_product_rotation.update_controller_product_rotation(delta)

	player_checkout.update_checkout_cursor_visual()

	var holding_checkout_product: bool = (
		held_item != null
		and held_item_origin == ItemOrigin.CHECKOUT_GRID
	)

	player_checkout.update_checkout_pointer(
		holding_checkout_product,
		player_product_rotation.rotating_held_product
	)

	player_checkout.update_checkout_hover()


# ============================================================
# PHYSICS PROCESS
# ============================================================

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_process_remote_player()
		return

	_update_spill_cleaning(delta)

	_update_camera_look(delta)
	_update_camera_zoom(delta)

	var raw_input: Vector2 = _get_movement_input()
	var move_direction: Vector3 = _get_movement_direction(raw_input)

	_update_movement_velocity(raw_input, move_direction, delta)
	_update_movement_animation()

	var is_starting_jump: bool = _update_jump()

	_update_landing_effect(delta)
	_apply_physics_movement(is_starting_jump, delta)

	_update_network_movement_state()
	_update_character_rotation(raw_input, move_direction, delta)
	_update_network_held_item_state()


# ============================================================
# REMOTE PLAYER PHYSICS
# ============================================================

func _process_remote_player() -> void:
	set_anim_tree()
	_update_remote_equipment_visuals()
	_record_network_state()
	_update_network_position()


func _record_network_state() -> void:
	# Detect a newly received network state.
	if not (
		not _network_position_initialized
		or network_position != _network_position_last_received
		or network_velocity != _network_velocity_last_received
		or network_rotation_y != _network_rotation_y_last_received
		or network_first_person != _network_first_person_last_received
	):
		return

	var current_time: float = Time.get_ticks_usec() / 1000000.0

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


# ============================================================
# CAMERA PHYSICS
# ============================================================

func _clear_camera_input() -> void:
	_camera_input_direction = Vector2.ZERO
	_mouse_input_direction = Vector2.ZERO
	_smoothed_mouse_velocity = Vector2.ZERO


func _get_gamepad_look_input() -> Vector2:
	var gamepad_look: Vector2 = Vector2.ZERO

	if can_process_gameplay_input():
		gamepad_look = Input.get_vector(
			"look_left",
			"look_right",
			"look_up",
			"look_down"
		)
	else:
		_clear_camera_input()

	var controller_rotating_product: bool = (
		held_item != null
		and (
			checkout_mode_active
			or Input.is_action_pressed("product_rotate")
		)
	)

	if (
		checkout_mode_active
		or player_product_rotation.rotating_held_product
		or controller_rotating_product
	):
		gamepad_look = Vector2.ZERO
		_clear_camera_input()

	return gamepad_look


func _update_camera_look(delta: float) -> void:
	var gamepad_look: Vector2 = _get_gamepad_look_input()

	_update_crouch_camera(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		_update_gamepad_ui_cursor(gamepad_look, delta)
	else:
		if gamepad_look.length() > 0.05:
			_camera_input_direction += (
				gamepad_look
				* gamepad_sensitivity
			)

	_update_mouse_smoothing(delta)

	var look_rotation: Vector2 = (
		_smoothed_mouse_velocity * delta
		+ _camera_input_direction * delta
	)

	_apply_camera_rotation(look_rotation)

	# Clear accumulated input after applying rotation.
	_camera_input_direction = Vector2.ZERO
	_mouse_input_direction = Vector2.ZERO


func _update_crouch_camera(delta: float) -> void:
	var target_camera_y: float = 1.308 if is_crouching else 1.708

	first_person_camera_pivot.position.y = lerp(
		first_person_camera_pivot.position.y,
		target_camera_y,
		1.0 - exp(-10.0 * delta)
	)


func _update_gamepad_ui_cursor(
	gamepad_look: Vector2,
	delta: float
) -> void:
	if gamepad_look.length() <= 0.05:
		return

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


func _update_mouse_smoothing(delta: float) -> void:
	# Convert accumulated mouse displacement into a rotation rate.
	var mouse_velocity: Vector2 = _mouse_input_direction / delta

	if mouse_smoothing <= 0.0:
		_smoothed_mouse_velocity = mouse_velocity
		return

	# Higher percentage = stronger smoothing.
	var smoothing_speed: float = lerpf(
		100.0,
		5.0,
		mouse_smoothing / 100.0
	)

	var smoothing_factor: float = (
		1.0 - exp(-smoothing_speed * delta)
	)

	_smoothed_mouse_velocity = _smoothed_mouse_velocity.lerp(
		mouse_velocity,
		smoothing_factor
	)


func _apply_camera_rotation(look_rotation: Vector2) -> void:
	if _first_person:
		rotation.y -= look_rotation.x
		first_person_camera_pivot.rotation.x -= look_rotation.y

		first_person_camera_pivot.rotation.x = clamp(
			first_person_camera_pivot.rotation.x,
			deg_to_rad(-80.0),
			deg_to_rad(80.0)
		)

	else:
		_spring_arm_pivot.rotation.x -= look_rotation.y

		_spring_arm_pivot.rotation.x = clamp(
			_spring_arm_pivot.rotation.x,
			deg_to_rad(-65.0),
			deg_to_rad(40.0)
		)

		_spring_arm_pivot.rotation.y -= look_rotation.x


func _update_camera_zoom(delta: float) -> void:
	if can_process_gameplay_input() and Input.is_action_pressed("zoom_in"):
		_target_zoom -= gamepad_zoom_speed * delta
		_target_zoom = clamp(
			_target_zoom,
			min_zoom,
			max_zoom
		)
	elif can_process_gameplay_input() and Input.is_action_pressed("zoom_out"):
		_target_zoom += gamepad_zoom_speed * delta
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


# ============================================================
# MOVEMENT INPUT
# ============================================================

func _get_movement_input() -> Vector2:
	var raw_input: Vector2 = Vector2.ZERO

	if can_process_gameplay_input() and not movement_locked:
		raw_input = Input.get_vector(
			"left",
			"right",
			"up",
			"down"
		)

	if block_movement_until_keys_released:
		raw_input = Vector2.ZERO
		velocity.x = 0.0
		velocity.z = 0.0

	if not (
		Input.is_action_pressed("left")
		or Input.is_action_pressed("right")
		or Input.is_action_pressed("up")
		or Input.is_action_pressed("down")
	):
		block_movement_until_keys_released = false

	return raw_input


func _get_movement_direction(raw_input: Vector2) -> Vector3:
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

	return (
		forward * raw_input.y
		+ right * raw_input.x
	).normalized()


# ============================================================
# MOVEMENT VELOCITY
# ============================================================

func _update_sprint_state(raw_input: Vector2) -> void:
	# Minigames can disable sprinting using this group.
	var sprint_allowed: bool = (
		not get_tree().has_group("disable_player_sprint")
	)

	is_sprinting = (
		Input.is_action_pressed("sprint")
		and not is_crouching
		and sprint_allowed
		and raw_input.length_squared() > 0.0
		and not (
			held_item != null
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		)
	)


func _get_target_movement_speed() -> float:
	if is_crouching:
		return crouch_speed

	if is_sprinting:
		return sprint_speed

	return walk_speed


func _update_movement_velocity(
	raw_input: Vector2,
	move_direction: Vector3,
	delta: float
) -> void:
	_update_sprint_state(raw_input)

	var target_move_speed: float = _get_target_movement_speed()

	var y_velocity: float = velocity.y
	velocity.y = 0.0

	var current_acceleration: float = (
		acceleration
		if is_on_floor()
		else air_acceleration
	)

	if movement_locked or not can_process_gameplay_input():
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity = velocity.move_toward(
			move_direction * target_move_speed,
			current_acceleration * delta
		)

	velocity.y = y_velocity + _gravity * delta


# ============================================================
# MOVEMENT ANIMATION
# ============================================================

func _update_movement_animation() -> void:
	var horizontal_speed: float = Vector3(
		velocity.x,
		0.0,
		velocity.z
	).length()

	var animation_speed: float = (
		crouch_speed
		if is_crouching
		else sprint_speed
	)

	network_anim_blend = horizontal_speed / animation_speed
	network_anim_blend = clamp(network_anim_blend, 0.0, 1.0)

	if horizontal_speed > 0.1:
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
	network_is_crouching = is_crouching
	network_is_pushing_cart = attached_cart != null

	set_anim_tree()


# ============================================================
# JUMPING AND LANDING
# ============================================================

func _update_jump() -> bool:
	var is_starting_jump: bool = (
		can_process_gameplay_input()
		and Input.is_action_just_pressed("jump")
		and not is_crouching
		and not movement_locked
		and is_on_floor()
	)

	if is_starting_jump:
		velocity.y = jump_strength

	# Releasing jump early cuts the upward velocity.
	if (
		can_process_gameplay_input()
		and Input.is_action_just_released("jump")
		and velocity.y > 0.0
	):
		velocity.y *= jump_release_multiplier

	return is_starting_jump


func _update_landing_effect(delta: float) -> void:
	if is_on_floor() and _was_airborne:
		body_mesh.position.y = _mesh_default_y - 0.3
		_was_airborne = false

	elif not is_on_floor():
		_was_airborne = true

	if body_mesh.position.y < _mesh_default_y:
		body_mesh.position.y = move_toward(
			body_mesh.position.y,
			_mesh_default_y,
			5.0 * delta
		)


# ============================================================
# CONVEYOR BELTS AND KNOCKBACK
# ============================================================

func _update_conveyor_velocity(is_starting_jump: bool) -> void:
	var belt: ConveyorBelt = null

	if has_meta("conveyor_belt"):
		belt = get_meta("conveyor_belt") as ConveyorBelt

	conveyor_velocity = Vector3.ZERO

	if is_instance_valid(belt) and is_on_floor() and not is_starting_jump:
		conveyor_velocity = belt.get_belt_velocity()


func _apply_physics_movement(
	is_starting_jump: bool,
	delta: float
) -> void:
	_update_conveyor_velocity(is_starting_jump)

	knockback_velocity = knockback_velocity.move_toward(
		Vector3.ZERO,
		knockback_decay * delta
	)

	velocity += conveyor_velocity
	velocity += knockback_velocity

	move_and_slide()

	velocity -= conveyor_velocity
	velocity -= knockback_velocity


# ============================================================
# CHARACTER ROTATION
# ============================================================

func _get_strafe_angle(raw_input: Vector2) -> float:
	if raw_input.x == 0.0:
		return 0.0

	return -raw_input.x * deg_to_rad(strafe_rotation)


func _update_character_rotation(
	raw_input: Vector2,
	move_direction: Vector3,
	delta: float
) -> void:
	if _first_person:
		_update_first_person_rotation(raw_input, delta)
	else:
		_update_third_person_rotation(
			raw_input,
			move_direction,
			delta
		)

	network_rotation_y = armature_node.global_rotation.y


func _update_first_person_rotation(
	raw_input: Vector2,
	delta: float
) -> void:
	var strafe_angle: float = _get_strafe_angle(raw_input)

	armature_node.rotation.y = lerp_angle(
		armature_node.rotation.y,
		strafe_angle,
		rotation_speed * delta
	)


func _update_third_person_rotation(
	raw_input: Vector2,
	move_direction: Vector3,
	delta: float
) -> void:
	if body_mesh:
		body_mesh.rotation.y = 0.0

	if attached_cart == null:
		_update_free_movement_rotation(move_direction, delta)
	else:
		_update_cart_movement_rotation(raw_input, delta)


func _update_free_movement_rotation(
	move_direction: Vector3,
	delta: float
) -> void:
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


func _update_cart_movement_rotation(
	raw_input: Vector2,
	delta: float
) -> void:
	var camera_yaw: float = _spring_arm_pivot.global_rotation.y

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

	var strafe_angle: float = _get_strafe_angle(raw_input)

	var target_angle: float = (
		target_camera_angle
		+ strafe_angle
	)

	armature_node.rotation.y = lerp_angle(
		armature_node.rotation.y,
		target_angle,
		rotation_speed * delta
	)


# ============================================================
# NETWORK PHYSICS STATE
# ============================================================

func _update_network_movement_state() -> void:
	network_position = global_position
	network_velocity = velocity

	network_on_moving_platform = (
		is_on_floor()
		and get_platform_velocity().length() > 0.1
	)


func _update_network_held_item_state() -> void:
	network_holding_item = held_item != null

	if held_item != null:
		network_held_item_path = held_item.resource_path
	else:
		network_held_item_path = ""
	

func set_anim_tree() -> void:
	# Get the delta time (use get_process_delta_time() or pass delta into this function)
	var dt = get_physics_process_delta_time()
	
	# Smoothly slide towards the network value. 
	# Adjust '24.0' higher for a snappier stop, or lower for a heavier, skidding stop.
	_smoothed_sprint_blend = lerp(_smoothed_sprint_blend,
		network_anim_blend,
		1.0 - exp(-24.0 * dt)
	)
	
	# 1. Target the BlendSpace1D using our smoothly interpolated value or network value
	anim_tree.set(
		"parameters/MovementState/BlendSpace1D/blend_position",
		_smoothed_sprint_blend
	)
	_smoothed_crouch_blend = lerp(
		_smoothed_crouch_blend,
		network_anim_blend,
		1.0 - exp(-10.0 * dt)
	)

	anim_tree.set(
		"parameters/CrouchingState/BlendSpace1D/blend_position",
		_smoothed_crouch_blend
	)
	
	# 2. Calculate the speed multiplier based on the SMOOTHED value
	var target_speed_scale := 1.0
	
	if _smoothed_sprint_blend <= 0.0:
		target_speed_scale = 1.0 
	elif _smoothed_sprint_blend <= 0.58:
		var t = remap(_smoothed_sprint_blend, 0.0, 0.58, 0.0, 1.0)
		target_speed_scale = lerp(1.0, 1.40, t)
	else:
		var t = remap(_smoothed_sprint_blend, 0.58, 1.0, 0.0, 1.0)
		target_speed_scale = lerp(1.40, 1.0, t)
	
	# Crouch animation speed blending
	var crouch_speed_scale := 1.0

	var crouch_blend: float = abs(network_anim_blend)

	if crouch_blend > 0.0:
		crouch_speed_scale = lerp(1.0, 1.45, crouch_blend)

	anim_tree.set(
		"parameters/CrouchingState/TimeScale/scale",
		crouch_speed_scale
	)
	# 3. Apply it to the TimeScale node
	anim_tree.set(
		"parameters/MovementState/TimeScale/scale",
		target_speed_scale
	)
		
	anim_tree.set(
		"parameters/conditions/is_falling",
		network_is_falling
	)

	anim_tree.set(
		"parameters/conditions/is_grounded",
		network_is_grounded
	)
	
	anim_tree.set(
		"parameters/conditions/is_crouching",
		network_is_crouching
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


func update_crouch_collision() -> void:
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D

	if capsule == null:
		return

	if is_crouching:
		capsule.radius = 0.4
		capsule.height = 1.6
		collision_shape.position.y = 0.8
	else:
		capsule.radius = 0.4
		capsule.height = 2.0
		collision_shape.position.y = 1.0


func _update_remote_equipment_visuals() -> void:
	# Product
	if (
		network_holding_item != _network_holding_item_last_received
		or network_held_item_path != _network_held_item_path_last_received
	):
		_network_holding_item_last_received = network_holding_item
		_network_held_item_path_last_received = network_held_item_path
		player_equipment.update_product_visual(
			network_holding_item,
			network_held_item_path
		)
	# Restock box
	if (
		network_holding_restock_box != _network_holding_restock_box_last_received
		or network_restock_box_product_path != _network_restock_box_product_path_last_received
		or network_restock_box_quantity != _network_restock_box_quantity_last_received
	):
		_network_holding_restock_box_last_received = network_holding_restock_box
		_network_restock_box_product_path_last_received = network_restock_box_product_path
		_network_restock_box_quantity_last_received = network_restock_box_quantity
		player_equipment.update_restock_box_visual(
			network_holding_restock_box,
			network_restock_box_product_path,
			network_restock_box_quantity
		)
	# Restock scanner
	if (
		network_holding_restock_scanner
		!= _network_holding_restock_scanner_last_received
	):
		_network_holding_restock_scanner_last_received = (
			network_holding_restock_scanner
		)
		player_equipment.update_scanner_visual(
			network_holding_restock_scanner
		)
	# Mop
	if network_holding_mop != _network_holding_mop_last_received:
		_network_holding_mop_last_received = network_holding_mop

		player_equipment.update_mop_visual(
			network_holding_mop
		)
	
	# Mop cleaning pose
	if (
		network_is_cleaning_spill
		!= _network_is_cleaning_spill_last_received
	):
		_network_is_cleaning_spill_last_received = network_is_cleaning_spill

		player_equipment.set_mop_cleaning(
			network_is_cleaning_spill
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


# A shared equipment check function to limit redundant checks

	

func try_pickup_restock_box(box: RestockBox) -> void:
	if not is_multiplayer_authority():
		return

	if not is_instance_valid(box):
		return

	if not can_pickup_equipment():
		return

	if box.product_data == null:
		return

	var box_path: NodePath = box.get_path()

	if multiplayer.is_server():
		_server_pickup_restock_box(
			box_path,
			get_multiplayer_authority()
		)
	else:
		request_pickup_restock_box.rpc_id(1, box_path)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup_restock_box(box_path: NodePath) -> void:
	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if not _is_valid_server_request(requesting_peer_id):
		return

	_server_pickup_restock_box(
		box_path,
		requesting_peer_id
	)


func _server_pickup_restock_box(
	box_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not server_restock_product_path.is_empty():
		return

	var box: RestockBox = get_node_or_null(box_path) as RestockBox

	if box == null:
		push_warning("Restock pickup: box not found: %s" % box_path)
		return

	if box.product_data == null:
		return

	var product_path: String = box.product_data.resource_path
	var box_quantity: int = box.quantity

	if product_path.is_empty():
		push_warning("Restock pickup: product has no resource path.")
		return

	# The server owns the box contents.
	server_restock_product_path = product_path
	server_restock_quantity = box_quantity

	# The delivery MultiplayerSpawner removes the world box
	# on connected peers when its server-side node is freed.
	var spawner: MultiplayerSpawner = (
		box.get_parent().get_node_or_null("MultiplayerSpawner")
		as MultiplayerSpawner
		)

	var is_spawned_box: bool = (
		spawner != null
		and box.get_scene_file_path().is_empty()
	)

	if not is_spawned_box:
		remove_placed_restock_box.rpc(box_path)

	box.remove_from_world.rpc()
	box.queue_free()

	# Only the player who picked it up receives the held box.
	if requesting_peer_id == multiplayer.get_unique_id():
		_receive_restock_box(product_path, box_quantity)
	else:
		receive_restock_box.rpc_id(
			requesting_peer_id,
			product_path,
			box_quantity
	)


@rpc("authority", "call_remote", "reliable")
func remove_placed_restock_box(box_path: NodePath) -> void:
	var box: RestockBox = get_node_or_null(box_path) as RestockBox

	if box != null:
		box.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func receive_restock_box(
	product_path: String,
	box_quantity: int
) -> void:
	if not _is_server_rpc():
		return

	if not is_multiplayer_authority():
		return

	_receive_restock_box(product_path, box_quantity)



func _receive_restock_box(
	product_path: String,
	box_quantity: int
) -> void:
	if held_restock_box != null:
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	held_restock_box = player_equipment.create_restock_box_visual(
		product,
		box_quantity,
		held_box_holder
	)

	if held_restock_box == null:
		return

	held_restock_box.scale = Vector3(0.8, 0.8, 0.8)

	network_holding_restock_box = true
	network_restock_box_product_path = product_path
	network_restock_box_quantity = box_quantity


# Mop pick up
func request_pickup_mop(mop: Node3D) -> void:
	if mop == null:
		return
		
	if not can_pickup_equipment():
		return

	var mop_path: NodePath = mop.get_path()

	if multiplayer.is_server():
		_server_pickup_mop(mop_path, get_multiplayer_authority())
	else:
		request_pickup_mop_rpc.rpc_id(1, mop_path)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup_mop_rpc(mop_path: NodePath) -> void:
	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if not _is_valid_server_request(requesting_peer_id):
		return

	_server_pickup_mop(mop_path, requesting_peer_id)


func _server_pickup_mop(
	mop_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not can_pickup_equipment():
		return

	var mop_node: Mop = get_node_or_null(mop_path) as Mop

	if mop_node == null:
		return

	if not mop_node.server_claim(requesting_peer_id):
		return

	server_holding_mop = true
	_grant_mop.rpc()


@rpc("any_peer", "call_local", "reliable")
func _grant_mop() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	# Only accept grants originating from the host.
	if sender_id != 0 and sender_id != 1:
		return

	# Only the owning player creates the held visual.
	if not is_multiplayer_authority():
		return

	if held_mop != null:
		return

	held_mop = player_equipment.create_local_mop_visual(
		held_item_holder,
		mop_hold_position,
		mop_hold_rotation
	)
	network_holding_mop = true


func request_return_mop(mop: Mop) -> void:
	if held_mop == null:
		return

	if mop == null:
		return

	if cleaning_spill != null:
		return

	var mop_path: NodePath = mop.get_path()

	if multiplayer.is_server():
		_server_return_mop(
			mop_path,
			get_multiplayer_authority()
		)
	else:
		_request_return_mop.rpc_id(1, mop_path)


@rpc("any_peer", "call_remote", "reliable")
func _request_return_mop(mop_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	_server_return_mop(
		mop_path,
		multiplayer.get_remote_sender_id()
	)


func _server_return_mop(
	mop_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not server_holding_mop:
		return

	if not server_cleaning_spill_path.is_empty():
		return

	var mop: Mop = get_node_or_null(mop_path) as Mop

	if mop == null:
		return

	var return_area: Area3D = (
		mop.get_node_or_null("ReturnArea") as Area3D
	)

	if return_area == null:
		return

	if global_position.distance_to(
		return_area.global_position
	) > 3.0:
		return

	if not mop.server_return(requesting_peer_id):
		return

	server_holding_mop = false
	_clear_mop.rpc()


@rpc("any_peer", "call_local", "reliable")
func _clear_mop() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	# Only accept removal commands from the host.
	if sender_id != 0 and sender_id != 1:
		return

	if not is_multiplayer_authority():
		return

	player_equipment.remove_equipment_visual(held_mop)
	held_mop = null
	network_holding_mop = false


func _start_spill_cleaning() -> bool:
	if held_mop == null:
		return false

	var spill: Spill = (
		interact_raycast_3d.current_interactable as Spill
	)

	if spill == null:
		return false

	cleaning_spill = spill
	cleaning_progress = 0.0
	cleaning_spill.start_target_movement()
	
	network_is_cleaning_spill = true

	if not inspection_camera_active:
		player_equipment.set_mop_cleaning(true)

	var spill_path: NodePath = spill.get_path()

	if multiplayer.is_server():
		_server_begin_spill_cleaning(
			spill_path,
			get_multiplayer_authority()
		)
	else:
		_request_begin_spill_cleaning.rpc_id(1, spill_path)

	return true



func _update_spill_cleaning(delta: float) -> void:
	
	if cleaning_spill == null:
		return

	if not is_instance_valid(cleaning_spill):
		_stop_spill_cleaning()
		return

	if not Input.is_action_pressed("interact"):
		_stop_spill_cleaning()
		return

	if held_mop == null:
		_stop_spill_cleaning()
		return

	if interact_raycast_3d.current_interactable != cleaning_spill:
		_stop_spill_cleaning()
		return

	if global_position.distance_to(
		cleaning_spill.global_position
	) > spill_cleaning_distance:
		_stop_spill_cleaning()
		return
		
	var target_hit: bool = (
		cleaning_spill.update_target_aim_feedback(
			_first_person_camera
		)
	)
	
	var cleaning_speed: float = 1.0

	if not target_hit:
		cleaning_speed = (
			cleaning_spill.missed_target_cleaning_multiplier
		)

	cleaning_progress += delta * cleaning_speed
	
	var visual_progress: float = clampf(
		cleaning_progress / cleaning_spill.cleaning_duration,
		0.0,
		1.0
	)

	cleaning_spill.update_cleaning_visual(visual_progress)

	if cleaning_progress >= cleaning_spill.cleaning_duration:
		var spill_path: NodePath = cleaning_spill.get_path()

		if multiplayer.is_server():
			_server_finish_spill_cleaning(
				spill_path,
				get_multiplayer_authority()
			)
		else:
			_request_finish_spill_cleaning.rpc_id(1, spill_path)

		_stop_spill_cleaning()



func _stop_spill_cleaning() -> void:
	if is_instance_valid(cleaning_spill):
		cleaning_spill.stop_target_movement()
		cleaning_spill.reset_cleaning_visual()

	if cleaning_spill != null:
		if multiplayer.is_server():
			_server_cancel_spill_cleaning(
				get_multiplayer_authority()
			)
		else:
			_request_cancel_spill_cleaning.rpc_id(1)

	cleaning_spill = null
	cleaning_progress = 0.0
	
	network_is_cleaning_spill = false

	if not inspection_camera_active:
		player_equipment.set_mop_cleaning(false)
	

@rpc("any_peer", "call_remote", "reliable")
func _request_begin_spill_cleaning(
	spill_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return

	_server_begin_spill_cleaning(
		spill_path,
		multiplayer.get_remote_sender_id()
	)


func _server_begin_spill_cleaning(
	spill_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not server_holding_mop:
		return

	var spill: Spill = get_node_or_null(spill_path) as Spill

	if not _server_can_clean_spill(spill):
		return

	# Reset any previous cleaning attempt.
	if not server_cleaning_spill_path.is_empty():
		var previous_spill: Spill = (
			get_node_or_null(server_cleaning_spill_path) as Spill
		)

		if is_instance_valid(previous_spill):
			previous_spill.stop_network_cleaning.rpc()

	server_cleaning_spill_path = spill_path
	server_cleaning_started_usec = Time.get_ticks_usec()

	# Start the shrinking effect for everyone.
	spill.start_network_cleaning.rpc()



@rpc("any_peer", "call_remote", "reliable")
func _request_finish_spill_cleaning(
	spill_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return

	_server_finish_spill_cleaning(
		spill_path,
		multiplayer.get_remote_sender_id()
	)


func _server_finish_spill_cleaning(
	spill_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if spill_path != server_cleaning_spill_path:
		return

	if server_cleaning_started_usec <= 0:
		return

	var elapsed_seconds: float = (
		float(Time.get_ticks_usec() - server_cleaning_started_usec)
		/ 1000000.0
	)

	var spill: Spill = get_node_or_null(spill_path) as Spill
	
	if not _server_can_clean_spill(spill):
		return
	
	if elapsed_seconds < spill.cleaning_duration - 0.1:
		return

	server_cleaning_spill_path = NodePath()
	server_cleaning_started_usec = 0

	# Play the completion effect on every peer.
	spill.finish_network_cleaning.rpc()

	# Remove the spill after the completion event is sent.
	spill.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func _request_cancel_spill_cleaning() -> void:
	if not multiplayer.is_server():
		return

	_server_cancel_spill_cleaning(
		multiplayer.get_remote_sender_id()
	)



func _server_cancel_spill_cleaning(
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not server_cleaning_spill_path.is_empty():
		var spill: Spill = (
			get_node_or_null(server_cleaning_spill_path) as Spill
		)

		if is_instance_valid(spill):
			spill.stop_network_cleaning.rpc()

	server_cleaning_spill_path = NodePath()
	server_cleaning_started_usec = 0



func _server_can_clean_spill(spill: Spill) -> bool:
	if not server_holding_mop:
		return false

	if not is_instance_valid(spill):
		return false

	if not spill.is_in_group("active_spills"):
		return false

	if global_position.distance_to(
		spill.global_position
	) > spill_cleaning_distance:
		return false

	return true


func request_pickup_restock_scanner(scanner: Node3D) -> void:
	if scanner == null:
		return

	if not can_pickup_equipment():
		return

	var scanner_path: NodePath = scanner.get_path()

	if multiplayer.is_server():
		_server_pickup_restock_scanner(
			scanner_path,
			get_multiplayer_authority()
		)
	else:
		request_pickup_restock_scanner_rpc.rpc_id(
			1,
			scanner_path
		)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup_restock_scanner_rpc(
	scanner_path: NodePath
) -> void:
	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if not _is_valid_server_request(requesting_peer_id):
		return

	_server_pickup_restock_scanner(
		scanner_path,
		requesting_peer_id
	)


func _server_pickup_restock_scanner(
	scanner_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if not can_pickup_equipment():
		return

	var scanner_node: Node = get_node_or_null(scanner_path)

	if scanner_node == null:
		return

	if not scanner_node.has_method("server_claim"):
		return

	if not scanner_node.server_claim():
		return

	held_restock_scanner_holder = scanner_node.get_parent() as Node3D

	_grant_restock_scanner.rpc()


func request_return_restock_scanner() -> void:
	if held_restock_scanner == null:
		return

	if multiplayer.is_server():
		_server_return_restock_scanner(
			get_multiplayer_authority()
		)
	else:
		request_return_restock_scanner_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_return_restock_scanner_rpc() -> void:
	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if not _is_valid_server_request(requesting_peer_id):
		return

	_server_return_restock_scanner(requesting_peer_id)


func _server_return_restock_scanner(requesting_peer_id: int) -> void:
	if not _is_valid_server_request(requesting_peer_id):
		return

	if held_restock_scanner_holder == null:
		return
	
	var scanner_node: Node3D = (
		held_restock_scanner_holder.get_node_or_null("RestockScanner")
		as Node3D
	)

	if scanner_node == null:
		return

	if not scanner_node.has_method("return_scanner_to_holder"):
		return

	scanner_node.return_scanner_to_holder.rpc(true)

	held_restock_scanner_holder = null
	
	_clear_restock_scanner.rpc()


@rpc("any_peer", "call_local", "reliable")
func _clear_restock_scanner() -> void:
	if not is_multiplayer_authority():
		return

	player_equipment.remove_equipment_visual(held_restock_scanner)
	held_restock_scanner = null

	network_holding_restock_scanner = false


@rpc("any_peer", "call_local", "reliable")
func _grant_restock_scanner() -> void:
	if not is_multiplayer_authority():
		return

	if held_restock_scanner != null:
		return

	held_restock_scanner = player_equipment.create_local_scanner_visual(
		held_item_holder
	)

	if held_restock_scanner == null:
		return

	network_holding_restock_scanner = true


func handle_restock_scanner_input(event: InputEvent) -> bool:
	if held_restock_scanner == null:
		return false

	var interact_pressed: bool = (
		Input.is_action_just_pressed_by_event("interact", event)
		or (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
	)

	if not held_restock_scanner.order_selection_active:
		if interact_pressed:
			var display: Node = held_restock_scanner.get_targeted_product_display(
				interact_raycast_3d
			)

			if display != null:
				var product_data: ProductData = display.get(
					"product_data"
				) as ProductData

				if product_data != null:
					var product_path: String = product_data.resource_path
					var pending_quantity: int = (
						StockOrderManager.get_pending_quantity(product_path)
					)

					if pending_quantity > 0:
						if multiplayer.is_server():
							StockOrderManager.set_pending_quantity(
								product_path,
								0
							)
						else:
							StockOrderManager.request_set_pending_quantity.rpc_id(
								1,
								product_path,
								0
							)

						return true

				held_restock_scanner.begin_order_selection(display)

				if held_restock_scanner.order_selection_active:
					return true

		return false

	if interact_pressed:
		held_restock_scanner.confirm_order_selection()
		return true

	if event.is_action_pressed("restock_increase"):
		if event is InputEventMouseButton:
			var current_time_usec: int = Time.get_ticks_usec()

			if current_time_usec - last_restock_wheel_time_usec < 150000:
				return true

			last_restock_wheel_time_usec = current_time_usec

		held_restock_scanner.adjust_order_quantity(1)
		return true

	if event.is_action_pressed("restock_decrease"):
		if event is InputEventMouseButton:
			var current_time_usec: int = Time.get_ticks_usec()

			if current_time_usec - last_restock_wheel_time_usec < 150000:
				return true

			last_restock_wheel_time_usec = current_time_usec

		held_restock_scanner.adjust_order_quantity(-1)
		return true

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event

		if (
			mouse_event.button_index == MOUSE_BUTTON_RIGHT
			and mouse_event.pressed
		):
			held_restock_scanner.cancel_order_selection()
			return true

	return false


func interact_with_item(item: Node3D) -> void:
	if item == null:
		return

	if item is RigidBody3D and item.has_method("grab_cart"):
		if is_holding_equipment():
			return
			
		try_grab_cart(item as RigidBody3D)
		return

	if item.has_method("request_interact"):
		item.request_interact(self)
	elif item.has_method("interact"):
		item.interact(self)


# Held item functions
func _clear_held_item() -> void:

	player_product_rotation.stop_held_product_rotation()

	# Stop any active product rotation.
	player_product_rotation.rotating_held_product = false

	# Remove checkout cursor preview.
	player_checkout.clear_checkout_cursor_visual()

	player_equipment.remove_local_product_visual(held_item_visual)
	held_item_visual = null

	held_item = null
	held_item_origin = ItemOrigin.NONE
	held_item_order_id = -1


func _clear_held_restock_box() -> void:
	player_equipment.remove_equipment_visual(held_restock_box)

	held_restock_box = null

	network_holding_restock_box = false
	network_restock_box_product_path = ""
	network_restock_box_quantity = 0


@rpc("any_peer", "call_remote", "reliable")
func clear_held_restock_box() -> void:
	if not _is_server_rpc():
		return

	_clear_held_restock_box()


@rpc("any_peer", "call_remote", "reliable")
func clear_held_item() -> void:
	if not _is_server_rpc():
		return

	_clear_held_item()


@rpc("any_peer", "call_remote", "reliable")
func receive_product(
	product_path: String,
	origin: ItemOrigin = ItemOrigin.NONE,
	order_id: int = -1
) -> void:
	# Only accept product deliveries from the server.
	if not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 1:
			return

	var loaded_resource: Resource = load(product_path)

	if not loaded_resource is ProductData:
		return

	held_item = loaded_resource as ProductData
	held_item_origin = origin
	held_item_order_id = order_id

	player_product_rotation.rotating_held_product = false

	player_equipment.remove_local_product_visual(held_item_visual)

	held_item_visual = player_equipment.create_local_product_visual(
		held_item,
		held_item_holder
	)

	if checkout_mode_active:
		player_checkout.create_checkout_cursor_visual()


@rpc("any_peer", "call_remote", "reliable")
func clear_cancelled_order_item(order_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	_clear_cancelled_order_item_local(order_id)


func _clear_cancelled_order_item_local(order_id: int) -> void:
	if not is_multiplayer_authority():
		return

	if held_item == null:
		return

	if held_item_origin != ItemOrigin.ORDER_GRID:
		return

	if held_item_order_id != order_id:
		return

	_clear_held_item()


func play_footstep() -> void:
	if not is_multiplayer_authority():
		return
	
	var current_time: int = Time.get_ticks_msec()

	if current_time - last_footstep_time < FOOTSTEP_COOLDOWN_MS:
		return

	last_footstep_time = current_time

	var target_volume: float = -18.0
	var min_pitch: float = 0.8
	var max_pitch: float = 1.1

	if is_sprinting:
		# If sprinting, use running pitches/volumes
		min_pitch = 0.9
		max_pitch = 1.2
		target_volume = 0.0
	elif is_crouching:
		# If walking but crouching, lower the volume
		target_volume = -20.0

	var chosen_pitch = randf_range(min_pitch, max_pitch)

	network_play_footstep.rpc(target_volume, chosen_pitch)


@rpc("any_peer", "call_local", "unreliable")
func network_play_footstep(volume: float, pitch: float) -> void:

	if footstep_player:
		footstep_player.volume_db = volume
		footstep_player.pitch_scale = pitch
		footstep_player.play()


func set_movement_locked(locked: bool) -> void:
	if checkout_mode_active and not locked:
		print("Movement unlock ignored: checkout is active")
		return
		
	movement_locked = locked
	
	if not locked:
		velocity.x = 0.0
		velocity.z = 0.0
		block_movement_until_keys_released = true

# Knockback during minigames
func receive_conveyor_knockback(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return

	knockback_velocity += impulse


@rpc("any_peer", "call_local", "reliable")
func apply_conveyor_knockback(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return

	if not _is_server_rpc():
		return

	knockback_velocity += impulse

# Inspector Camera Functions for hand target use.
func toggle_inspection_camera() -> void:
	if not is_multiplayer_authority():
		return

	inspection_camera_active = not inspection_camera_active

	if inspection_camera_active:
		# Show the local character.
		_set_alien_visible(true)

		# Enable mop inspection if holding one.
		_start_mop_inspection()

		inspection_camera.make_current()

	else:
		# Restore normal mop visuals.
		_stop_mop_inspection()

		# Restore character visibility.
		_update_alien_visibility()

		# Restore the previous camera.
		if _first_person:
			_first_person_camera.make_current()
		else:
			_third_person_camera.make_current()


func _start_mop_inspection() -> void:
	if not is_instance_valid(held_mop):
		return

	# Hide the first-person mop.
	held_mop.hide()

	# Create the third-person mop visual.
	player_equipment.update_mop_visual(true)

	# The current update_mop_visual() already enables
	# the cleaning pose for testing.


func _stop_mop_inspection() -> void:
	# Release the cleaning pose and wrist rotations.
	player_equipment.set_mop_cleaning(false)

	# Remove the temporary third-person mop.
	player_equipment.update_mop_visual(false)

	# Restore the first-person mop.
	if is_instance_valid(held_mop):
		held_mop.show()


# ============================================================
# CHECKOUT MODE INTERFACE
# ============================================================

func enter_checkout_mode(checkout: Checkout) -> void:
	player_checkout.enter_checkout_mode(checkout)


func _activate_checkout_mode(checkout: Checkout) -> void:
	player_checkout.activate_checkout_mode(checkout)


func exit_checkout_mode() -> void:
	player_checkout.exit_checkout_mode()


func get_checkout_cursor_screen_position() -> Vector2:
	return player_checkout.get_checkout_cursor_screen_position()


# ============================================================
# ALIEN HELPER FUNCTIONS
# ============================================================

func _set_alien_visible(visible_state: bool) -> void:
	body_mesh.visible = visible_state
	alien_head.visible = visible_state
	alien_top.visible = visible_state
	alien_bottom.visible = visible_state
	alien_feet.visible = visible_state


func _update_alien_visibility() -> void:
	var should_show: bool = true

	if is_multiplayer_authority():
		should_show = not _first_person or inspection_camera_active

	_set_alien_visible(should_show)
