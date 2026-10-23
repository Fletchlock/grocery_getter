
extends RigidBody3D


# === Exported Physics Configuration ===
@export_group("Cart Tuning")
@export var attach_distance: float = 0.5
@export var position_follow_speed: float = 55.0
@export var rotation_swing_speed: float = 5.5
@export var rotation_align_speed: float = 22.0


# === Internal State Variables ===
@export var is_being_pushed: bool = false

var player_character: CharacterBody3D = null

var last_valid_forward: Vector3 = Vector3.FORWARD
var current_smoothed_forward: Vector3 = Vector3.FORWARD

# Server tracks who is actually using the cart.
var _cart_owner_id: int = 0

# Prevent duplicate local requests.
var _request_pending: bool = false

# Track the latest authority change on each peer.
var _authority_sequence: int = 0


func is_cart() -> bool:
	return true


# ============================================================
# MULTIPLAYER AUTHORITY
# ============================================================

# All authority requests go to the host.
# The host validates and applies the change BEFORE notifying clients.
@rpc("any_peer", "call_local", "reliable")
func request_cart_authority(state: bool) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# Validate the request.
	if state:
		# Nobody else can grab an occupied cart.
		if _cart_owner_id != 0:
			_reject_cart_request(sender_id)
			return
	else:
		# Only the player pushing the cart can release it.
		if _cart_owner_id != sender_id:
			_reject_cart_request(sender_id)
			return

	var new_authority: int = sender_id if state else 1

	_cart_owner_id = sender_id if state else 0
	_authority_sequence += 1

	# STEP 1: Host changes authority locally.
	_apply_cart_authority(new_authority, state)

	# STEP 2: Host sends the change to all clients.
	# This RPC is reliable and runs remotely only.
	receive_cart_authority.rpc(
		new_authority,
		state,
		_authority_sequence
	)

	_request_pending = false


# Reject invalid requests without changing authority.
func _reject_cart_request(peer_id: int) -> void:
	if peer_id == 1:
		_request_pending = false
	else:
		cart_request_rejected.rpc_id(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func cart_request_rejected() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	_request_pending = false
	player_character = null

	push_warning("Cart authority request rejected by host.")


# Clients receive authority changes from the host.
@rpc("any_peer", "call_remote", "reliable")
func receive_cart_authority(
	peer_id: int,
	state: bool,
	sequence: int
) -> void:
	# Only the host may authorize authority changes.
	if multiplayer.get_remote_sender_id() != 1:
		return

	# Ignore outdated or duplicate authority changes.
	if sequence <= _authority_sequence:
		return

	_authority_sequence = sequence

	# STEP 3: Client changes authority only after host approval.
	_apply_cart_authority(peer_id, state)

	_request_pending = false


# Apply the authority and physical state locally.
func _apply_cart_authority(peer_id: int, state: bool) -> void:
	print(
		"CART AUTHORITY CHANGE | Local peer: ",
		multiplayer.get_unique_id(),
		" | Old authority: ",
		get_multiplayer_authority(),
		" | New authority: ",
		peer_id,
		" | Pushing: ",
		state
	)

	set_multiplayer_authority(peer_id)
	is_being_pushed = state

	if state:
		gravity_scale = 0.0

		set_collision_layer_value(1, false)
		set_collision_mask_value(1, true)

		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		gravity_scale = 1.0

		set_collision_layer_value(1, true)
		set_collision_mask_value(1, true)

		# Preserve the original release velocity behavior.


# ============================================================
# GRAB / RELEASE
# ============================================================

func grab_cart(player_node: CharacterBody3D) -> void:
	if _request_pending:
		return

	player_character = player_node

	# Preserve the cart's current facing direction.
	last_valid_forward = -global_transform.basis.z.normalized()
	current_smoothed_forward = last_valid_forward

	_request_pending = true

	# Ask the host. Do not change authority locally.
	request_cart_authority.rpc_id(1, true)


func release_cart() -> void:
	if _request_pending:
		return

	player_character = null

	_request_pending = true

	# Ask the host to restore authority to peer 1.
	request_cart_authority.rpc_id(1, false)


# ============================================================
# CART PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:
	# ============================================================
	# MULTIPLAYER JITTER COMPENSATION (REMOTE CLIENTS)
	# ============================================================
	if not is_multiplayer_authority():
		if is_being_pushed:
			gravity_scale = 0.0
		else:
			gravity_scale = 1.0

		return

	# ============================================================
	# CONTROLLING PLAYER AUTHORITY MOVEMENTS (LOCAL PUSHER)
	# ============================================================
	if not is_being_pushed or player_character == null:
		return

	# 1. Capture the controlling player's camera direction.
	var camera_forward: Vector3 = player_character.get_camera_forward()

	if camera_forward.length_squared() > 0.001:
		last_valid_forward = camera_forward.normalized()

	# 2. Smoothly calculate the rotation swing lag.
	current_smoothed_forward = current_smoothed_forward.lerp(
		last_valid_forward,
		rotation_swing_speed * delta
	).normalized()

	# 3. Position calculations.
	var target_position: Vector3 = (
		player_character.global_position
		+ current_smoothed_forward * attach_distance
	)

	var distance_vector: Vector3 = target_position - global_position

	var desired_velocity: Vector3 = (
		distance_vector * position_follow_speed
	)

	linear_velocity = linear_velocity.lerp(
		desired_velocity,
		15.0 * delta
	)

	# 4. Final rotation alignment.
	var target_look: Vector3 = global_position + current_smoothed_forward
	var current_transform: Transform3D = global_transform

	if current_smoothed_forward.length_squared() > 0.001:
		current_transform = current_transform.looking_at(
			target_look,
			Vector3.UP
		)

		global_transform.basis = global_transform.basis.slerp(
			current_transform.basis,
			rotation_align_speed * delta
		)


# ============================================================
# INTERACTION PROMPT
# ============================================================

func get_interaction_prompt(player: CharacterBody3D) -> String:
	if player.network_holding_item:
		return ""

	if player.held_restock_box != null:
		return ""

	if player_character != null:
		return "[E] Release cart"

	return "[E] Grab cart"


# ============================================================
# INTERACTION
# ============================================================

func interact(player: CharacterBody3D) -> void:
	if player != null:
		if player.has_method("try_release_cart"):
			player.try_release_cart()

		return

	var players: Array[Node] = get_tree().get_nodes_in_group("player")

	if players.is_empty():
		return

	var closest_player: CharacterBody3D = null
	var closest_distance: float = INF

	for node: Node in players:
		if node is CharacterBody3D:
			var candidate: CharacterBody3D = node as CharacterBody3D

			var distance: float = global_position.distance_squared_to(
				candidate.global_position
			)

			if distance < closest_distance:
				closest_distance = distance
				closest_player = candidate

	if closest_player != null and closest_player.has_method("try_grab_cart"):
		closest_player.try_grab_cart(self)
