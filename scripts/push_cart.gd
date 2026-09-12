extends RigidBody3D

var pushing_player: CharacterBody3D = null

@export_group("Pushing")
@export var push_spring_strength := 900.0
@export var push_damping := 80.0
@export var steering_strength := 500.0
@export var max_push_force := 1200.0


@onready var handle_point: Marker3D = $HandlePoint


func start_pushing(player: CharacterBody3D) -> void:
	if pushing_player != null:
		return

	pushing_player = player

	print("SHOPPING CART: Being pushed by ", player.name)


func stop_pushing() -> void:
	pushing_player = null

	print("SHOPPING CART: Released")


func _physics_process(_delta: float) -> void:
	if pushing_player == null:
		return

	var push_point: Node3D = pushing_player.get_node("PushPoint")

	# Where the cart handle should ideally be.
	var target_position := push_point.global_position

	# Difference between where the handle is and where we want it.
	var position_error := target_position - handle_point.global_position

	# Ignore vertical positioning.
	position_error.y = 0.0

	# Current velocity at the handle.
	var handle_velocity := linear_velocity

	# Spring force pulls the cart toward the player's PushPoint.
	var force := position_error * push_spring_strength

	# Damping prevents the cart from oscillating wildly.
	force -= handle_velocity * push_damping

	# Don't allow the spring to generate an insane force.
	if force.length() > max_push_force:
		force = force.normalized() * max_push_force

	# Apply the force at the handle.
	apply_force(force, handle_point.global_position - global_position)

	# -------------------------------------------------
	# Steering
	# -------------------------------------------------

	var player_velocity := pushing_player.velocity
	player_velocity.y = 0.0

	if player_velocity.length() > 0.1:
		var movement_direction := player_velocity.normalized()

		# Cart's current forward direction.
		var cart_forward := -global_transform.basis.z
		cart_forward.y = 0.0
		cart_forward = cart_forward.normalized()

		# Calculate how much the cart needs to rotate.
		var cross := cart_forward.cross(movement_direction)
		var steering_torque := cross.y * steering_strength

		apply_torque(Vector3.UP * steering_torque)
