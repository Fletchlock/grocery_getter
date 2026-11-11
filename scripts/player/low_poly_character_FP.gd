extends CharacterBody3D

# === Node References ===
@onready var _third_person_camera: Camera3D = $SpringArmPivot/SpringArm3D/Camera3D
@onready var _first_person_camera: Camera3D = $FirstPersonCameraPivot/FirstPersonCamera
@onready var first_person_camera_pivot: Node3D = $FirstPersonCameraPivot
@onready var _spring_arm: SpringArm3D = $SpringArmPivot/SpringArm3D

# Inspection Camera for setting hand targets etc.
@onready var inspection_camera: Camera3D = $InspectionCameraPivot/InspectionCamera
var inspection_camera_active: bool = false

@onready var interact_raycast_3d: RayCast3D = $FirstPersonCameraPivot/FirstPersonCamera/InteractRaycast3D
@onready var held_item_holder: Node3D = $FirstPersonCameraPivot/HeldItemHolder
@onready var held_box_holder: Node3D = $FirstPersonCameraPivot/HeldBoxHolder
@onready var _spring_arm_pivot: Node3D = $SpringArmPivot
@onready var _first_person_pivot: Node3D = $FirstPersonCameraPivot
@onready var armature_node: Node3D = $Armature
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var anim_tree = $AnimationTree
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var cart_pusher: RigidBody3D = $CartPusher
@onready var _mesh_default_y: float = $Armature.position.y
@onready var grocery_red: MeshInstance3D = $Armature/Skeleton3D/GroceryRed
@onready var grocery_blue: MeshInstance3D = $Armature/Skeleton3D/GroceryBlue
@onready var grocery_green: MeshInstance3D = $Armature/Skeleton3D/GroceryGreen
@onready var crosshair: Control = $FirstPersonCameraPivot/FirstPersonCamera/UI/Crosshair
@onready var player_equipment: PlayerEquipment = $PlayerEquipment

# Audio
@onready var footstep_player: AudioStreamPlayer3D = $FirstPersonCameraPivot/FirstPersonCamera/FootstepPlayer
@onready var audio_listener: AudioListener3D = $AudioListener3D
var last_footstep_time: int = 0
const FOOTSTEP_COOLDOWN_MS: int = 180


@export_group("Cart")
@export var strafe_rotation := 35.0
var nearby_carts: Array[RigidBody3D] = []
@export var attached_cart: RigidBody3D = null


# Cart IK refs
@onready var left_hand_ik: TwoBoneIK3D = $Armature/Skeleton3D/LeftTwoBoneIK3D
@onready var right_hand_ik: TwoBoneIK3D = $Armature/Skeleton3D/RightTwoBoneIK3D
@onready var left_hand_rot: CopyTransformModifier3D = $Armature/Skeleton3D/LeftHandRotationModifier
@onready var right_hand_rot: CopyTransformModifier3D = $Armature/Skeleton3D/RightHandRotatioinModifier


# === Configuration Properties ===
@export_group("Camera")
@export var cart_release_fade_alpha: float = 0.25
@export_range(0.0, 1.0, 0.0001) var mouse_sensitivity: float = 0.0017 ## Mouse camera sensitivity.
@export_range(0.0, 100.0, 1.0)
var mouse_smoothing: float = 25.0
@export var gamepad_sensitivty := 3.0 ## Gamepad camera sensitivity.
@export var zoom_speed := 1.0 ## Mouse camera zoom speed.
@export var gamepad_zoom_speed := 2.0 ## Gamepad camera zoom speed.
@export var min_zoom := 2.0 ## Minimum camera distance.
@export var max_zoom := 8.0 ## Maximum camera distance.


@export_group("Movement")
@export var walk_speed : float = 3.5 ## Speed while walking.
@export var sprint_speed : float = 6.0 ## Speed while sprinting
@export var crouch_speed: float = 2.0 ## Speed while crouching
@export var acceleration : float= 36.0 ## Ground movement acceleration.
@export var rotation_speed : float= 12.0 ## Character rotation speed.
@export var jump_strength : float= 10.0 ## Initial upward force when jumping.
@export_range(0.1, 1.0, 0.05)
var jump_release_multiplier: float = 0.40
@export var air_acceleration : float= 3.0 ## Movement acceleration while airborne.

var knockback_velocity: Vector3 = Vector3.ZERO

@export_group("Knockback")
@export var knockback_decay: float = 8.0

@export_group("Network Replication")
@export var network_position := Vector3.ZERO
@export var network_velocity := Vector3.ZERO
@export var network_rotation_y : float = 0.0
@export var network_anim_blend : float = 0.0
@export var network_is_falling : bool = false
@export var network_is_grounded : bool = true
@export var network_is_crouching: bool = false
@export var network_hat_visible : bool = true
@export var network_on_moving_platform : bool = false
@export var network_is_pushing_cart: bool = false
@export var network_first_person: bool = false

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
var _mouse_input_direction: Vector2 = Vector2.ZERO
var _smoothed_mouse_velocity: Vector2 = Vector2.ZERO
var _last_movement_direction := Vector3.FORWARD
var is_sprinting: bool = false
var is_crouching: bool = false
var _gravity := -30.0
var _was_airborne := false
var _target_zoom := 2.0
var _first_person: bool = true
var _smoothed_sprint_blend: float = 0.0
var _smoothed_crouch_blend: float = 0.0
var camera_fade_tween: Tween = null
var movement_locked: bool = false

# === Checkout mode ===

var checkout_mode_active: bool = false
var active_checkout: Checkout = null
var checkout_previous_camera: Camera3D = null
var checkout_previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var checkout_previous_movement_locked: bool = false
var checkout_previous_raycast_enabled: bool = true
var checkout_previous_held_item_visibility: bool = true
var held_item: ProductData = null
var held_item_visual: MeshInstance3D = null
var held_item_origin: ItemOrigin = ItemOrigin.NONE
var checkout_cursor_visual: MeshInstance3D = null
var checkout_cursor_last_safe_position: Vector3 = Vector3.ZERO
var checkout_cursor_has_safe_position: bool = false
var checkout_cursor_sensor: Area3D = null
var rotating_held_product: bool = false
var held_product_base_rotation: Vector3 = Vector3.ZERO
var held_product_rotation_offset: Vector2 = Vector2.ZERO
var checkout_rotation_mouse_position: Vector2 = Vector2.ZERO
var checkout_last_mouse_position: Vector2 = Vector2.ZERO
var checkout_rotation_previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var held_product_center_local: Vector3 = Vector3.ZERO
var held_product_center_parent: Vector3 = Vector3.ZERO
var checkout_scanned_product_path: String = ""

func can_process_gameplay_input() -> bool:
	return (
		is_multiplayer_authority()
		and GameManager.current_state == GameManager.GameState.PLAYING
	)

var block_movement_until_keys_released := false


# Conveyor Belt Testing
var conveyor_velocity: Vector3 = Vector3.ZERO

# === Held Item Variables ===
enum ItemOrigin {
	NONE,
	PRODUCT_DISPLAY,
	CART_GRID,
	CHECKOUT_GRID,
	ORDER_GRID
}

@export_group("Checkout Cursor Item")
@export var checkout_cursor_offset: Vector2 = Vector2(0.0, 0.0)
@export var checkout_cursor_depth: float = 1.0
var checkout_cursor_collision_offset: Vector2 = Vector2.ZERO

@export_group("Held Product Rotation")
@export var held_product_rotation_sensitivity: float = 0.008

# === Held Restock Box Variables ===
var held_restock_box: RestockBox = null
# Server-authoritative contents of the carried box.
var server_restock_product_path: String = ""
var server_restock_quantity: int = 0

# === Held Restock Scanner Variables ===
@export var network_holding_restock_scanner: bool = false
var held_restock_scanner: Node3D = null
var held_restock_scanner_holder: Node3D = null
var last_restock_wheel_time_usec: int = 0
var _network_holding_restock_scanner_last_received: bool = false

# === Held Mop Variables
@export_group("Held Mop")
@export var mop_hold_position: Vector3 = Vector3(0.25, 0.00, 0.00)
@export var mop_hold_rotation: Vector3 = Vector3(110.0, 0.0, -25.0)
@export var network_holding_mop: bool = false
@export var network_is_cleaning_spill: bool = false

var _network_is_cleaning_spill_last_received: bool = false
var _network_holding_mop_last_received: bool = false
var held_mop: Node3D = null

@export_group("Spill Cleaning")
@export var spill_cleaning_distance: float = 3.0

var cleaning_spill: Spill = null
var cleaning_progress: float = 0.0
var server_holding_mop: bool = false
var server_cleaning_spill_path: NodePath = NodePath()
var server_cleaning_started_usec: int = 0

@onready var held_item_hand_target: Node3D = $Armature/HeldItemHandTarget
@onready var held_item_target: Node3D = $Armature/HeldItemTarget
@onready var held_item_network_visual: MeshInstance3D = $Armature/HeldItemTarget/HeldItemNetworkVisual
@onready var held_box_hand_target_right: Node3D = $Armature/HeldBoxHandTargetRight
@onready var held_box_hand_target_left: Node3D = $Armature/HeldBoxHandTargetLeft


@export var network_holding_item: bool = false
@export var network_held_item_path: String = ""

var _network_holding_item_last_received: bool = false
var _network_held_item_path_last_received: String = ""

@export var network_holding_restock_box: bool = false
@export var network_restock_box_product_path: String = ""
@export var network_restock_box_quantity: int = 0

var _network_holding_restock_box_last_received: bool = false
var _network_restock_box_product_path_last_received: String = ""
var _network_restock_box_quantity_last_received: int = 0


# === Player Scene Reference ===
const PLAYER_SCENE = preload(
	"res://scenes/player/low_poly_character_FP.tscn"
	
)


func _enter_tree() -> void:
	# Convert your node's string name (e.g. "933642306") into its real integer peer ID 
	# and claim network authority BEFORE any child nodes initialize!
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	audio_listener.current = is_multiplayer_authority()
	
	if not is_multiplayer_authority():
		crosshair.hide()
	
	print(
		"PLAYER READY: ",
		name,
		" authority=",
		get_multiplayer_authority(),
		" local_id=",
		multiplayer.get_unique_id()
	)
	
	if is_multiplayer_authority():
		add_to_group("local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	
	blink_timer = randf_range(blink_min_time, blink_max_time)
	
	# Initialize the AnimationTree.
	anim_tree.advance_expression_base_node = get_path()
	anim_tree.active = true
		
	# Apply the current selection and listen for late lobby updates.
	LobbyManager.lobby_player_updated.connect(_on_lobby_player_updated)
	LobbyManager.lobby_state_changed.connect(_refresh_character_selection)

	_refresh_character_selection()

	if is_multiplayer_authority():
		var orange_survival: bool = (
			get_parent().get_parent().name in [
				"OrangeSurvival",
				"ConveyorShowdown"
				]
		)
				
		_set_perspective(not orange_survival)
		
		if orange_survival:
			_target_zoom = max_zoom
			_spring_arm.spring_length = max_zoom

	_network_position_last_received = network_position
	_network_velocity_last_received = network_velocity
	_network_rotation_y_last_received = network_rotation_y
	_network_velocity_received_time = (Time.get_ticks_usec() / 1000000.0)
	_network_position_initialized = false

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


func _on_lobby_player_updated(peer_id: int) -> void:
	if peer_id != get_multiplayer_authority():
		return

	_refresh_character_selection()


func _refresh_character_selection() -> void:
	var character: String = LobbyManager.get_character(
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
			
	# Keep the local player's body hidden in first-person.
	if is_multiplayer_authority() and _first_person:
		grocery_red.visible = false
		grocery_blue.visible = false
		grocery_green.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not can_process_gameplay_input():
		return
	
	# Handle local held-product rotation before other input.
	if _handle_held_product_rotation_input(event):
		return
	
	if checkout_mode_active:
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
		if (
			event.is_action_pressed("interact")
			and not (event is InputEventKey and event.echo)
		):
			handle_checkout_interaction()
			get_viewport().set_input_as_handled()
			return

		# Left mouse button performs the same interaction.
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			handle_checkout_interaction()
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
		
	if event.is_action_pressed("interact") and Input.is_action_just_pressed("interact"):
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
		
	grocery_red.visible = false
	grocery_blue.visible = false
	grocery_green.visible = false

	if _first_person:
		rotation.y = _spring_arm_pivot.global_rotation.y
		_first_person_pivot.rotation.x = _spring_arm_pivot.rotation.x
		_first_person_camera.make_current()
		if interact_raycast_3d:
			interact_raycast_3d.enabled = true

	else:
		_spring_arm_pivot.global_rotation.y = rotation.y
		_spring_arm_pivot.rotation.x = _first_person_pivot.rotation.x
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

		if interact_raycast_3d:
			interact_raycast_3d.enabled = false

	network_first_person = _first_person
	
	crosshair.visible = is_multiplayer_authority() and _first_person
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _process(delta: float) -> void:
	# Blink
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
				blink_timer = double_blink_delay
			elif randf() < double_blink_chance:
				double_blink_pending = true
				blink_timer = double_blink_delay
			else:
				blink_timer = randf_range(blink_min_time, blink_max_time)

	update_idle_look(delta)
	player_equipment.update_hand_targets(delta, network_is_crouching)
	player_equipment.update_mop_right_hand_target(delta)
	update_checkout_cursor_visual()

	# Update checkout hover outlines.
	if checkout_mode_active and is_instance_valid(active_checkout):
		var mouse_position: Vector2 = (
			get_viewport().get_mouse_position()
		)

		# Products can only be highlighted when we're not holding anything.
		var can_hover_products: bool = (
			held_item == null
			and not is_holding_equipment()
		)

		# Keep bag detection aligned with the held product's actual position.
		if (
			held_item != null
			and held_item_origin == ItemOrigin.CHECKOUT_GRID
		):
			if rotating_held_product:
				mouse_position = checkout_rotation_mouse_position

			mouse_position += (
				checkout_cursor_offset
				+ checkout_cursor_collision_offset
			)

		active_checkout.update_checkout_hover_outline(
			mouse_position,
			can_hover_products
		)


func _physics_process(delta: float) -> void:

	# ============================================================
	# REMOTE PLAYER
	# ============================================================

	if not is_multiplayer_authority():
		set_anim_tree()

		var hat = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible
		
		_update_remote_equipment_visuals()
		
		# Detect a new received network state...
		if (
			not _network_position_initialized
			or network_position != _network_position_last_received
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
	
	_update_spill_cleaning(delta)
	
	# === 1. Camera / Look ===

	var gamepad_look: Vector2 = Vector2.ZERO

	if can_process_gameplay_input():
		gamepad_look = Input.get_vector(
			"look_left",
			"look_right",
			"look_up",
			"look_down"
		)
	else:
		_camera_input_direction = Vector2.ZERO
		_mouse_input_direction = Vector2.ZERO
		_smoothed_mouse_velocity = Vector2.ZERO

	if checkout_mode_active or rotating_held_product:
		gamepad_look = Vector2.ZERO
		_camera_input_direction = Vector2.ZERO
		_mouse_input_direction = Vector2.ZERO
		_smoothed_mouse_velocity = Vector2.ZERO

	# First person camera pivot move when crouching
	var target_camera_y: float = 1.308 if is_crouching else 1.708
	
	first_person_camera_pivot.position.y = lerp(
		first_person_camera_pivot.position.y,
		target_camera_y,
		1.0 - exp(-10.0 * delta)
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

	# Convert accumulated mouse displacement into a rotation rate.
	var mouse_velocity: Vector2 = _mouse_input_direction / delta

	if mouse_smoothing <= 0.0:
		# No smoothing: immediate mouse response.
		_smoothed_mouse_velocity = mouse_velocity
	else:
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

	# Combine mouse and gamepad rotation.
	var look_rotation: Vector2 = (
		_smoothed_mouse_velocity * delta
		+ _camera_input_direction * delta
	)

	if _first_person:
		rotation.y -= look_rotation.x

		_first_person_pivot.rotation.x -= look_rotation.y

		# First person look up/down limits
		_first_person_pivot.rotation.x = clamp(
			_first_person_pivot.rotation.x,
			deg_to_rad(-80.0),
			deg_to_rad(80.0)
		)

	else:
		_spring_arm_pivot.rotation.x -= look_rotation.y

		# Third person look up/down limits
		_spring_arm_pivot.rotation.x = clamp(
			_spring_arm_pivot.rotation.x,
			deg_to_rad(-65.0),
			deg_to_rad(40.0)
		)

		_spring_arm_pivot.rotation.y -= look_rotation.x

	# Clear accumulated input after applying camera rotation.
	_camera_input_direction = Vector2.ZERO
	_mouse_input_direction = Vector2.ZERO

	# Camera Zoom for TPP
	
		
	if can_process_gameplay_input() and Input.is_action_pressed("zoom_in"):
		_target_zoom -= gamepad_zoom_speed * delta

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


	# === 2. Directional Movement ===

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
	
	# This checks whether a scene/node is in the group disable_player_sprint.
	# If so, it disables sprint. This is currently used in mini games.
	var sprint_allowed: bool = not get_tree().has_group("disable_player_sprint")

	is_sprinting = (
		Input.is_action_pressed("sprint")
		and not is_crouching
		and sprint_allowed
		and raw_input.length_squared() > 0.0
	)
		
	var target_move_speed: float = (
		crouch_speed
		if is_crouching
		else sprint_speed
		if is_sprinting
		else walk_speed
	)
	
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


	# === 4. Animation State ===

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
	network_is_pushing_cart = (
		attached_cart != null
	)

	set_anim_tree()


	# === 5. Variable Height Jump ===

	var is_starting_jump: bool = (
		can_process_gameplay_input()
		and Input.is_action_just_pressed("jump")
		and not is_crouching
		and not movement_locked
		and is_on_floor()
	)

	if is_starting_jump:
		velocity.y = jump_strength

	# Releasing Jump early cuts the upward velocity.
	if (
		can_process_gameplay_input()
		and Input.is_action_just_released("jump")
		and velocity.y > 0.0
	):
		velocity.y *= jump_release_multiplier


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

	if can_process_gameplay_input() and Input.is_action_just_pressed("toggle_hat"):

		network_hat_visible = (
			not network_hat_visible
		)

		var hat: Node3D = body_mesh.get_node("Hat")
		hat.visible = network_hat_visible


	# === 8. Movement ===
	
	
# ============================================================
# CONVEYOR BELT MOVEMENT
# ============================================================
	
	var belt: ConveyorBelt = null

	if has_meta("conveyor_belt"):
		belt = get_meta("conveyor_belt") as ConveyorBelt

	conveyor_velocity = Vector3.ZERO

	if is_instance_valid(belt) and is_on_floor() and not is_starting_jump:
		conveyor_velocity = belt.get_belt_velocity()

	knockback_velocity = knockback_velocity.move_toward(
		Vector3.ZERO,
		knockback_decay * delta
	)

	velocity += conveyor_velocity
	velocity += knockback_velocity

	move_and_slide()

	velocity -= conveyor_velocity
	velocity -= knockback_velocity

	
	
	network_position = global_position
	network_velocity = velocity

	network_on_moving_platform = (
		is_on_floor()
		and get_platform_velocity().length() > 0.1
	)


	# === 9. Character Rotation ===

	if _first_person:
		var strafe_angle: float = 0.0

		if raw_input.x != 0.0:
			strafe_angle = (
				-raw_input.x
				* deg_to_rad(strafe_rotation)
			)

		armature_node.rotation.y = lerp_angle(
			armature_node.rotation.y,
			strafe_angle,
			rotation_speed * delta
		)

		network_rotation_y = armature_node.global_rotation.y

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

	# Network held item visual
	network_holding_item = held_item != null

	if held_item != null:
		network_held_item_path = held_item.resource_path
	else:
		network_held_item_path = ""
	


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
func is_holding_equipment() -> bool:
	return (
		held_item != null
		or held_restock_box != null
		or held_restock_scanner != null
		or held_mop != null
	)
	

func try_pickup_restock_box(box: RestockBox) -> void:
	if not is_multiplayer_authority():
		return

	if not is_instance_valid(box):
		return

	if is_holding_equipment():
		return

	if attached_cart != null:
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
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if get_multiplayer_authority() != requesting_peer_id:
		return

	_server_pickup_restock_box(
		box_path,
		requesting_peer_id
	)


func _server_pickup_restock_box(
	box_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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
	if multiplayer.get_remote_sender_id() != 1:
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
		
	if is_holding_equipment():
		return
	
	if attached_cart != null:
		return

	var mop_path: NodePath = mop.get_path()

	if multiplayer.is_server():
		_server_pickup_mop(mop_path, get_multiplayer_authority())
	else:
		request_pickup_mop_rpc.rpc_id(1, mop_path)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup_mop_rpc(mop_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if get_multiplayer_authority() != requesting_peer_id:
		return

	_server_pickup_mop(mop_path, requesting_peer_id)


func _server_pickup_mop(
	mop_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
		return

	if is_holding_equipment():
		return

	if attached_cart != null:
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
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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

	cleaning_progress += delta

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
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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

	if is_holding_equipment():
		return

	if attached_cart != null:
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
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if get_multiplayer_authority() != requesting_peer_id:
		return

	_server_pickup_restock_scanner(
		scanner_path,
		requesting_peer_id
	)


func _server_pickup_restock_scanner(
	scanner_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
		return

	if is_holding_equipment():
		return

	if attached_cart != null:
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
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	if get_multiplayer_authority() != requesting_peer_id:
		return

	_server_return_restock_scanner(requesting_peer_id)


func _server_return_restock_scanner(requesting_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() != requesting_peer_id:
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

	if not held_restock_scanner.order_selection_active:
		if event.is_action_pressed("interact"):
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

	if event.is_action_pressed("interact"):
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
		if held_item != null:
			return
		
		if held_restock_box != null:
			return
		
		try_grab_cart(item as RigidBody3D)
		return

	if item.has_method("request_interact"):
		item.request_interact(self)
	elif item.has_method("interact"):
		item.interact(self)


# Held item functions
func _clear_held_item() -> void:

	_stop_held_product_rotation()

	# Stop any active product rotation.
	rotating_held_product = false
	held_product_rotation_offset = Vector2.ZERO
	held_product_base_rotation = Vector3.ZERO
	held_product_center_local = Vector3.ZERO
	held_product_center_parent = Vector3.ZERO

	# Remember where the product preview was on screen.
	var restore_mouse_position := false
	var last_product_screen_position: Vector2 = Vector2.ZERO

	if is_instance_valid(checkout_cursor_visual):
		if is_instance_valid(active_checkout):
			var camera: Camera3D = active_checkout.checkout_camera

			if is_instance_valid(camera):
				var product_bounds: AABB = (
					checkout_cursor_visual.get_aabb()
				)

				var product_center: Vector3 = (
					checkout_cursor_visual.global_position
					+ checkout_cursor_visual.global_transform.basis
					* product_bounds.get_center()
				)

				last_product_screen_position = (
					camera.unproject_position(product_center)
				)

				restore_mouse_position = true

	# Remove checkout cursor preview.
	clear_checkout_cursor_visual()

	# Snap the actual mouse pointer to the last preview position.
	if restore_mouse_position:
		Input.warp_mouse(last_product_screen_position)
		checkout_last_mouse_position = last_product_screen_position

	player_equipment.remove_local_product_visual(held_item_visual)
	held_item_visual = null

	held_item = null
	held_item_origin = ItemOrigin.NONE


func _clear_held_restock_box() -> void:
	player_equipment.remove_equipment_visual(held_restock_box)

	held_restock_box = null

	network_holding_restock_box = false
	network_restock_box_product_path = ""
	network_restock_box_quantity = 0


func create_checkout_cursor_visual() -> void:

	# Only create this for the local player.
	if not is_multiplayer_authority():
		return

	if not checkout_mode_active:
		return

	if held_item == null:
		return

	if held_item_origin != ItemOrigin.CHECKOUT_GRID:
		return

	if active_checkout == null:
		return

	if not is_instance_valid(active_checkout.checkout_camera):
		return

	# Remove any previous preview.
	clear_checkout_cursor_visual()

	# Start each new product with a fresh mouse position.
	checkout_cursor_collision_offset = Vector2.ZERO

	if held_item_visual == null:
		return

	# Duplicate the existing local product visual.
	# This leaves the original held item untouched.
	checkout_cursor_visual = held_item_visual.duplicate() as MeshInstance3D

	if checkout_cursor_visual == null:
		return

	checkout_cursor_visual.name = "CheckoutCursorProduct"

	active_checkout.checkout_camera.add_child(checkout_cursor_visual)

	# Attach a collision sensor to the product preview.
	create_checkout_cursor_sensor()

	# Match the currently held product's rotation.
	checkout_cursor_visual.rotation = held_item_visual.rotation

	# Calculate the initial cursor position.
	var mouse_position: Vector2 = (
		get_viewport().get_mouse_position()
		+ checkout_cursor_offset
	)

	var initial_position: Vector3 = (
		get_checkout_cursor_centered_position(
			active_checkout.checkout_camera,
			mouse_position
		)
	)

	# Raise the initial position by 20 cm in world space.
	var spawn_world_position: Vector3 = (
		active_checkout.checkout_camera.to_global(initial_position)
		+ Vector3.UP * 0.2
	)

	var spawn_position: Vector3 = (
		active_checkout.checkout_camera.to_local(
			spawn_world_position
		)
	)

	checkout_cursor_visual.position = spawn_position

	# Find a clear position if the product overlaps the desk.
	if not is_checkout_cursor_position_clear(spawn_position):
		if not find_checkout_cursor_safe_position(spawn_position):
			clear_checkout_cursor_visual()
			return
	else:
		checkout_cursor_last_safe_position = spawn_position
		checkout_cursor_has_safe_position = true


func update_checkout_cursor_visual() -> void:

	update_checkout_mouse_cursor()

	if not checkout_mode_active:
		return

	if held_item == null:
		clear_checkout_cursor_visual()
		return

	if held_item_origin != ItemOrigin.CHECKOUT_GRID:
		clear_checkout_cursor_visual()
		return

	if not is_instance_valid(checkout_cursor_visual):
		create_checkout_cursor_visual()

	if not is_instance_valid(checkout_cursor_visual):
		return

	if active_checkout == null:
		return

	var camera: Camera3D = active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return

	var mouse_position: Vector2

	if rotating_held_product:
		mouse_position = checkout_rotation_mouse_position
	else:
		mouse_position = get_viewport().get_mouse_position()
		checkout_last_mouse_position = mouse_position

	var raw_mouse_position: Vector2 = mouse_position

	mouse_position += (
		checkout_cursor_offset
		+ checkout_cursor_collision_offset
	)

	# Calculate the desired position.
	var target_position: Vector3 = (
		get_checkout_cursor_centered_position(
			camera,
			mouse_position
		)
	)

	# Move the product while respecting collisions.
	var result_position: Vector3 = (
		get_checkout_cursor_collision_position(target_position)
	)

	checkout_cursor_visual.position = result_position

	# Remember the latest position that is free of collisions.
	if is_checkout_cursor_position_clear(result_position):
		checkout_cursor_last_safe_position = result_position
		checkout_cursor_has_safe_position = true

	# Re-anchor the mouse if collision prevented the product
	# from reaching its desired position.
	if (
		not rotating_held_product
		and result_position.distance_to(target_position) > 0.001
	):
		var product_bounds: AABB = checkout_cursor_visual.get_aabb()

		var product_center: Vector3 = (
			checkout_cursor_visual.global_position
			+ checkout_cursor_visual.global_transform.basis
			* product_bounds.get_center()
		)

		var actual_screen_position: Vector2 = (
			camera.unproject_position(product_center)
		)

		checkout_cursor_collision_offset = (
			actual_screen_position
			- raw_mouse_position
			- checkout_cursor_offset
		)


func create_checkout_cursor_sensor() -> void:

	if not is_instance_valid(checkout_cursor_visual):
		return

	if not is_instance_valid(active_checkout):
		return

	if not is_instance_valid(active_checkout.scan_area):
		return

	# Use the product mesh bounds for the collision shape.
	var product_bounds: AABB = checkout_cursor_visual.get_aabb()

	if product_bounds.size.is_zero_approx():
		return

	checkout_cursor_sensor = Area3D.new()
	checkout_cursor_sensor.name = "CheckoutProductSensor"

	# Detect the scanner, but don't act as a target for other areas.
	checkout_cursor_sensor.collision_layer = 0
	checkout_cursor_sensor.collision_mask = (
		active_checkout.scan_area.collision_layer
	)

	checkout_cursor_sensor.monitoring = true
	checkout_cursor_sensor.monitorable = false

	# Create a box matching the product's mesh bounds.
	var new_collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()

	box_shape.size = product_bounds.size
	new_collision_shape.shape = box_shape
	new_collision_shape.position = product_bounds.get_center()

	checkout_cursor_sensor.add_child(new_collision_shape)
	checkout_cursor_visual.add_child(checkout_cursor_sensor)

	# Listen for physical contact with the scanner.
	checkout_cursor_sensor.area_entered.connect(
		_on_checkout_product_sensor_area_entered
	)


func _on_checkout_product_sensor_area_entered(area: Area3D) -> void:

	if not checkout_mode_active:
		return

	if not is_instance_valid(active_checkout):
		return

	if area != active_checkout.scan_area:
		return

	if held_item == null:
		return

	if held_item_origin != ItemOrigin.CHECKOUT_GRID:
		return

	# Reuse the existing checkout scanning logic.
	active_checkout.interact(self)


func clear_checkout_cursor_visual() -> void:

	if is_instance_valid(checkout_cursor_visual):
		checkout_cursor_visual.queue_free()

	checkout_cursor_visual = null
	checkout_cursor_last_safe_position = Vector3.ZERO
	checkout_cursor_has_safe_position = false


func get_checkout_cursor_centered_position(
	camera: Camera3D,
	mouse_position: Vector2
) -> Vector3:

	var world_position: Vector3 = camera.project_position(
		mouse_position,
		checkout_cursor_depth
	)

	var target_position: Vector3 = camera.to_local(world_position)

	# Find the visual center of the product mesh.
	var mesh_center: Vector3 = checkout_cursor_visual.get_aabb().get_center()

	# Account for the product's rotation and scale.
	var center_offset: Vector3 = (
		checkout_cursor_visual.transform.basis * mesh_center
	)

	# Position the origin so the visual center sits at the cursor.
	return target_position - center_offset


func get_checkout_cursor_shape_query(
		candidate_position: Vector3
) -> PhysicsShapeQueryParameters3D:

	if not is_instance_valid(checkout_cursor_visual):
		return null

	var product_bounds: AABB = checkout_cursor_visual.get_aabb()

	if product_bounds.size.is_zero_approx():
		return null

	var camera: Camera3D = active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return null

	# Match the collision box to the product's size.
	var shape := BoxShape3D.new()
	shape.size = product_bounds.size * checkout_cursor_visual.scale.abs()

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.01

	# Ignore the player.
	query.exclude = [get_rid()]

	# Account for the product's rotation and mesh center.
	var product_center: Vector3 = (
		candidate_position
		+ checkout_cursor_visual.transform.basis
		* product_bounds.get_center()
	)

	query.transform = Transform3D(
		checkout_cursor_visual.global_transform.basis.orthonormalized(),
		camera.to_global(product_center)
	)

	return query


func is_checkout_cursor_position_clear(
		candidate_position: Vector3
) -> bool:

	var query := get_checkout_cursor_shape_query(candidate_position)

	if query == null:
		return false

	var space_state := get_world_3d().direct_space_state
	var overlaps: Array[Dictionary] = (
		space_state.intersect_shape(query, 1)
	)

	return overlaps.is_empty()


func find_checkout_cursor_safe_position(
		start_position: Vector3
) -> bool:

	if not is_instance_valid(checkout_cursor_visual):
		return false

	if not is_instance_valid(active_checkout):
		return false

	var camera: Camera3D = active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return false

	var candidate_world: Vector3 = camera.to_global(start_position)

	# Search upward in world space until the product is clear.
	for attempt in range(100):
		var candidate_local: Vector3 = camera.to_local(candidate_world)

		checkout_cursor_visual.position = candidate_local

		if is_checkout_cursor_position_clear(candidate_local):
			checkout_cursor_last_safe_position = candidate_local
			checkout_cursor_has_safe_position = true
			return true

		candidate_world += Vector3.UP * 0.025

	return false


func get_checkout_cursor_collision_position(
		target_position: Vector3
) -> Vector3:

	if not is_instance_valid(checkout_cursor_visual):
		return target_position

	if not is_instance_valid(active_checkout):
		return target_position

	var camera: Camera3D = active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return target_position

	var current_position: Vector3 = checkout_cursor_visual.position

	# Recover if the current position is overlapping.
	if not is_checkout_cursor_position_clear(current_position):
		if (
			checkout_cursor_has_safe_position
			and is_checkout_cursor_position_clear(
				checkout_cursor_last_safe_position
			)
		):
			current_position = checkout_cursor_last_safe_position
			checkout_cursor_visual.position = current_position
		else:
			if not find_checkout_cursor_safe_position(current_position):
				return current_position

			current_position = checkout_cursor_visual.position

	var current_world: Vector3 = camera.to_global(current_position)
	var target_world: Vector3 = camera.to_global(target_position)

	var remaining_motion: Vector3 = target_world - current_world

	# Process vertical movement first, independently of horizontal
	# movement. This allows the product to lift away from the desk
	# even when its previous horizontal path was blocked.
	var movement_axes: Array[Vector3] = [
		Vector3.UP,
		Vector3.RIGHT,
		Vector3.BACK
	]

	for axis in movement_axes:
		var axis_motion: Vector3 = axis * remaining_motion.dot(axis)
		var distance: float = axis_motion.length()

		if distance < 0.0001:
			continue

		var direction: Vector3 = axis_motion.normalized()
		var steps: int = maxi(1, ceili(distance / 0.025))

		var last_clear_distance: float = 0.0
		var blocked_distance: float = distance
		var found_collision: bool = false

		for step in range(1, steps + 1):
			var test_distance: float = (
				distance * float(step) / float(steps)
			)

			var test_world: Vector3 = (
				current_world + direction * test_distance
			)

			var test_local: Vector3 = camera.to_local(test_world)

			if not is_checkout_cursor_position_clear(test_local):
				blocked_distance = test_distance
				found_collision = true
				break

			last_clear_distance = test_distance

		# Refine the last clear point near the collision surface.
		if found_collision:
			for iteration in range(8):
				var middle_distance: float = (
					last_clear_distance + blocked_distance
				) * 0.5

				var test_world: Vector3 = (
					current_world + direction * middle_distance
				)

				var test_local: Vector3 = camera.to_local(test_world)

				if is_checkout_cursor_position_clear(test_local):
					last_clear_distance = middle_distance
				else:
					blocked_distance = middle_distance

		# Apply the movement that was possible along this axis.
		var applied_motion: Vector3 = (
			direction * last_clear_distance
		)

		current_world += applied_motion

		# Remove only the component handled by this axis.
		remaining_motion -= axis_motion

	var result_position: Vector3 = camera.to_local(current_world)

	if is_checkout_cursor_position_clear(result_position):
		checkout_cursor_last_safe_position = result_position
		checkout_cursor_has_safe_position = true

	return result_position


@rpc("any_peer", "call_remote", "reliable")
func clear_held_restock_box() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	_clear_held_restock_box()


@rpc("any_peer", "call_remote", "reliable")
func clear_held_item() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	_clear_held_item()


@rpc("any_peer", "call_remote", "reliable")
func receive_product(
	product_path: String,
	origin: ItemOrigin = ItemOrigin.NONE
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

	# Reset rotation for the newly picked-up product.
	rotating_held_product = false
	held_product_rotation_offset = Vector2.ZERO

	player_equipment.remove_local_product_visual(held_item_visual)

	held_item_visual = player_equipment.create_local_product_visual(
		held_item,
		held_item_holder
	)

	# Remember the product's original orientation and center.
	if is_instance_valid(held_item_visual):
		held_product_base_rotation = held_item_visual.rotation

		held_product_center_local = (
			held_item_visual.get_aabb().get_center()
		)

		held_product_center_parent = (
			held_item_visual.transform * held_product_center_local
		)
	
	# Create cursor preview if we're currently in checkout mode.
	if checkout_mode_active:
		create_checkout_cursor_visual()


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

	if multiplayer.get_remote_sender_id() != 1:
		return

	knockback_velocity += impulse

# Inspector Camera Functions for hand target use.
func toggle_inspection_camera() -> void:
	if not is_multiplayer_authority():
		return

	inspection_camera_active = not inspection_camera_active

	if inspection_camera_active:
		# Show the local character.
		if body_mesh:
			body_mesh.visible = true

		# Enable mop inspection if holding one.
		_start_mop_inspection()

		inspection_camera.make_current()

	else:
		# Restore normal mop visuals.
		_stop_mop_inspection()

		# Restore character visibility.
		if body_mesh:
			body_mesh.visible = not _first_person

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


# CHECKOUT MODE

func enter_checkout_mode(checkout: Checkout) -> void:
	if not is_multiplayer_authority():
		return

	if checkout_mode_active:
		return

	if checkout == null:
		return

	if checkout.checkout_camera == null:
		push_warning("Checkout has no CheckoutCamera!")
		return

	checkout_mode_active = true
	active_checkout = checkout

	# Remember the current state.
	checkout_previous_camera = get_viewport().get_camera_3d()
	checkout_previous_mouse_mode = Input.mouse_mode
	checkout_previous_movement_locked = movement_locked
	checkout_previous_raycast_enabled = interact_raycast_3d.enabled

	# Lock player movement.
	movement_locked = true

	# Hide the first-person held item during checkout mode.
	checkout_previous_held_item_visibility = held_item_holder.visible
	held_item_holder.hide()

	# Disable normal first-person interaction.
	interact_raycast_3d.enabled = false

	# Hide the normal crosshair.
	crosshair.hide()

	# Show the mouse cursor.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Activate the checkout camera.
	checkout.checkout_camera.make_current()

	# Show instructions/controls UI
	checkout.show_checkout_instructions()

	# Show cursor-held item if one is already in hand.
	create_checkout_cursor_visual()


func exit_checkout_mode() -> void:
	if not checkout_mode_active:
		return

	_stop_held_product_rotation()

	if is_instance_valid(active_checkout):
		active_checkout.clear_checkout_hover_outlines()
		active_checkout.hide_checkout_instructions()

	checkout_mode_active = false

	# Restore the previous camera.
	if is_instance_valid(checkout_previous_camera):
		checkout_previous_camera.make_current()
	else:
		_first_person_camera.make_current()

	# Restore player movement state.
	movement_locked = checkout_previous_movement_locked

	# Restore normal interaction.
	interact_raycast_3d.enabled = checkout_previous_raycast_enabled

	# Restore first-person held item visibility.
	held_item_holder.visible = checkout_previous_held_item_visibility

	# Restore mouse state.
	Input.mouse_mode = checkout_previous_mouse_mode

	# Restore crosshair.
	crosshair.visible = is_multiplayer_authority() and _first_person

	active_checkout = null

	checkout_previous_camera = null

	clear_checkout_cursor_visual()


func handle_checkout_interaction() -> void:
	if not checkout_mode_active:
		return

	if active_checkout == null:
		return

	var mouse_position: Vector2 = get_viewport().get_mouse_position()

	if held_item != null:
		if held_item_origin != ItemOrigin.CHECKOUT_GRID:
			return

		# Match the mouse position used by the cursor visual
		# and checkout hover outline.
		if rotating_held_product:
			mouse_position = checkout_rotation_mouse_position

		mouse_position += (
			checkout_cursor_offset
			+ checkout_cursor_collision_offset
		)

		if active_checkout.is_mouse_over_scanner(mouse_position):
			active_checkout.interact(self)
			return

		if active_checkout.is_mouse_over_bag(mouse_position):
			active_checkout.bag_grid.request_interact(self)
			return

		return

	if is_holding_equipment():
		return

	active_checkout.checkout_grid.request_take_item_at_mouse(
		self,
		mouse_position
	)


func _handle_held_product_rotation_input(event: InputEvent) -> bool:

	# Only products can be rotated.
	if held_item == null:
		if rotating_held_product:
			_stop_held_product_rotation()
		return false

	# Handle right mouse button press and release.
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if event.pressed:
			# Start rotating only while right mouse is held.
			rotating_held_product = true

			# Freeze the checkout cursor position while rotating.
			if checkout_mode_active:
				checkout_rotation_mouse_position = checkout_last_mouse_position
				checkout_rotation_previous_mouse_mode = Input.mouse_mode
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

			# Clear any pending camera movement.
			_mouse_input_direction = Vector2.ZERO
			_smoothed_mouse_velocity = Vector2.ZERO
			_camera_input_direction = Vector2.ZERO

		else:
			# Stop immediately when right mouse is released.
			_stop_held_product_rotation()

		get_viewport().set_input_as_handled()
		return true

	# Rotate the product only while right mouse is held.
	if event is InputEventMouseMotion and rotating_held_product:

		var mouse_delta: Vector2 = event.screen_relative

		# Apply rotation relative to the active camera's axes.
		_apply_held_product_rotation(mouse_delta)

		get_viewport().set_input_as_handled()
		return true

	return false


func update_checkout_mouse_cursor() -> void:

	if not checkout_mode_active:
		return

	# Don't interfere with the captured mouse during rotation.
	if rotating_held_product:
		return

	var holding_checkout_product: bool = (
		held_item != null
		and held_item_origin == ItemOrigin.CHECKOUT_GRID
	)

	if holding_checkout_product:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_product_rotation_around_center(
	product_mesh: MeshInstance3D,
	rotation_camera: Camera3D,
	mouse_delta: Vector2,
	center_position: Vector3
) -> void:

	if not is_instance_valid(product_mesh):
		return

	var parent_node: Node3D = product_mesh.get_parent() as Node3D

	if parent_node == null:
		return

	# Get the camera's right and up directions in the mesh
	# parent's local coordinate system.
	var camera_basis: Basis = rotation_camera.global_basis.orthonormalized()
	var parent_basis: Basis = parent_node.global_basis.orthonormalized()

	var local_right: Vector3 = (
		parent_basis.inverse() * camera_basis.x
	).normalized()

	var local_up: Vector3 = (
		parent_basis.inverse() * camera_basis.y
	).normalized()

	# Rotate around the camera's vertical and horizontal axes.
	var horizontal_rotation: Quaternion = Quaternion(
		local_up,
		mouse_delta.x * held_product_rotation_sensitivity
	)

	var vertical_rotation: Quaternion = Quaternion(
		local_right,
		mouse_delta.y * held_product_rotation_sensitivity
	)

	# Apply both rotations to the product's current orientation.
	product_mesh.quaternion = (
		horizontal_rotation
		* vertical_rotation
		* product_mesh.quaternion
	)

	# Keep the visual center stationary while rotating.
	var center_offset: Vector3 = (
		product_mesh.transform.basis
		* product_mesh.get_aabb().get_center()
	)

	product_mesh.position = center_position - center_offset


func _apply_held_product_rotation(mouse_delta: Vector2) -> void:

	var rotation_camera: Camera3D = get_viewport().get_camera_3d()

	if not is_instance_valid(rotation_camera):
		rotation_camera = _first_person_camera

	if not is_instance_valid(rotation_camera):
		return

	# Rotate the first-person held product around its center.
	if is_instance_valid(held_item_visual):
		_set_product_rotation_around_center(
			held_item_visual,
			rotation_camera,
			mouse_delta,
			held_product_center_parent
		)

	# Rotate the checkout cursor preview around its center.
	if is_instance_valid(checkout_cursor_visual):
		var cursor_center_position: Vector3 = (
			checkout_cursor_visual.position
			+ (
				checkout_cursor_visual.transform.basis
				* checkout_cursor_visual.get_aabb().get_center()
			)
		)

		_set_product_rotation_around_center(
			checkout_cursor_visual,
			rotation_camera,
			mouse_delta,
			cursor_center_position
		)


func _stop_held_product_rotation() -> void:

	# Only restore the mouse if rotation was actually active.
	# This prevents scanning an item from using an old position.
	if not rotating_held_product:
		return

	rotating_held_product = false

	# Restore the mouse when leaving product rotation in checkout mode.
	if checkout_mode_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		# Return the cursor to where the product was when rotation began.
		get_viewport().warp_mouse(checkout_rotation_mouse_position)

		# Restore the previous mouse visibility state.
		Input.mouse_mode = checkout_rotation_previous_mouse_mode

	# Clear any pending camera movement.
	_mouse_input_direction = Vector2.ZERO
	_smoothed_mouse_velocity = Vector2.ZERO
	_camera_input_direction = Vector2.ZERO
