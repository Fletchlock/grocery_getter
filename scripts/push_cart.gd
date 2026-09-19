extends RigidBody3D

# === Exported Physics Configuration ===
@export_group("Cart Tuning")
@export var attach_distance: float = 1.0
@export var position_follow_speed: float = 55.0
@export var rotation_swing_speed: float = 5.5
@export var rotation_align_speed: float = 22.0

# === Internal State Variables ===
# @export this so the MultiplayerSynchronizer replicates the state toggle to other clients!
@export var is_being_pushed: bool = false
var player_character: CharacterBody3D = null

var cart_contents: Array[RigidBody3D] = []
var content_transforms: Dictionary = {}

# Caches to handle direction processing and tracking memory
var last_valid_forward: Vector3 = Vector3.FORWARD
var current_smoothed_forward: Vector3 = Vector3.FORWARD


func is_cart() -> bool:
	return true


# This function must run on the SERVER side in a multiplayer match
@rpc("any_peer", "call_local")
func update_cart_authority(peer_id: int, state: bool) -> void:
	set_multiplayer_authority(peer_id)
	is_being_pushed = state
	
	if state == true:
		gravity_scale = 0.0
		
		# What the cart IS to the world: 
		# Turning off Layer 1 stops the active pusher from colliding with it
		set_collision_layer_value(1, false)
		
		# What the cart CAN SCAN/COLLIDE WITH:
		# Keep Box 1 checked so the cart still collides with walls, floors, 
		# and all other non-pushing players naturally.
		set_collision_mask_value(1, true)
		
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		# Restore standard physical presence in the world when dropped
		gravity_scale = 1.0
		
		set_collision_layer_value(1, true)
		set_collision_mask_value(1, true)
		
		#With the below removed the cart will drift after release.
		
		#linear_velocity = Vector3.ZERO
		#angular_velocity = Vector3.ZERO


func grab_cart(player_node: CharacterBody3D) -> void:
	player_character = player_node

	# Request the server to distribute multiplayer authority of this body to us
	update_cart_authority.rpc(multiplayer.get_unique_id(), true)
	
	# Preserve the cart's current facing direction when grabbed.
	last_valid_forward = -global_transform.basis.z.normalized()
	current_smoothed_forward = last_valid_forward
	
	for item: RigidBody3D in cart_contents:
		if is_instance_valid(item):
			var relative_transform: Transform3D = global_transform.affine_inverse() * item.global_transform
			content_transforms[item] = relative_transform
			
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			item.freeze = true
			item.set_collision_mask_value(1, false)
			
			item.global_transform = global_transform * relative_transform

func release_cart() -> void:
	for item: RigidBody3D in cart_contents:
		if is_instance_valid(item) and content_transforms.has(item):
			item.global_transform = global_transform * content_transforms[item]
			item.freeze = false
			item.set_collision_mask_value(1, true)
			item.linear_velocity = linear_velocity
			item.angular_velocity = Vector3.ZERO

	content_transforms.clear()
	cart_contents.clear()
	player_character = null
	
	update_cart_authority.rpc(1, false)


func _physics_process(delta: float) -> void:
	# ============================================================
	# MULTIPLAYER JITTER COMPENSATION (REMOTE CLIENTS)
	# ============================================================
	if not is_multiplayer_authority():
		if is_being_pushed:
			# If the network says a remote player is pushing this cart, turn off world gravity
			# and let its synchronized velocities glide it forward organically between network packets!
			gravity_scale = 0.0
			
			# Minor position snap correction: If network delay causes the cart to drift 
			# slightly away from its synchronized vector, softly nudge it back into place
			# without causing a violent visual snap.
			#var net_pos = get_node("../" + str(get_multiplayer_authority())).global_position
		else:
			gravity_scale = 1.0
		return # Exit out so remote clients don't run the pusher's target path calculations!

	# ============================================================
	# CONTROLLING PLAYER AUTHORITY MOVEMENTS (LOCAL PUSHER)
	# ============================================================
	if not is_being_pushed or player_character == null:
		return
		
	# 1. Capture camera look direction from the controlling player character
	var camera_pivot = player_character.get_node_or_null("SpringArmPivot")
	if camera_pivot:
		var camera_yaw = camera_pivot.global_rotation.y
		last_valid_forward = Vector3.FORWARD.rotated(Vector3.UP, camera_yaw).normalized()
		
	# 2. Smoothly calculate the rotation swing lag
	current_smoothed_forward = current_smoothed_forward.lerp(
		last_valid_forward, 
		rotation_swing_speed * delta
	).normalized()
		
	# 3. Position calculations (physics safe velocity translation)
	var target_position = player_character.global_position + (current_smoothed_forward * attach_distance)
	var distance_vector = target_position - global_position
	
	var desired_velocity = distance_vector * position_follow_speed
	linear_velocity = linear_velocity.lerp(desired_velocity, 15.0 * delta)
			
	# 4. Final rotation matrix alignment
	var target_look = global_position + current_smoothed_forward
	var current_transform = global_transform
	
	if current_smoothed_forward.length_squared() > 0.001:
		current_transform = current_transform.looking_at(target_look, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(
			current_transform.basis, 
			rotation_align_speed * delta
		)
		
	for item: RigidBody3D in cart_contents:
		if is_instance_valid(item) and content_transforms.has(item):
			var relative_transform: Transform3D = content_transforms[item]
			item.global_transform = global_transform * relative_transform	


func _on_contents_area_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		var item: RigidBody3D = body
		if not cart_contents.has(item):
			cart_contents.append(item)


func _on_contents_area_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		var item: RigidBody3D = body
		
		if not is_being_pushed:
			cart_contents.erase(item)
			content_transforms.erase(item)
