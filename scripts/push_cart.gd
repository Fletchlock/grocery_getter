extends RigidBody3D

var pushing_player: CharacterBody3D = null

@onready var push_joint: Generic6DOFJoint3D = $PushJoint


func start_pushing(player: CharacterBody3D) -> void:
	if pushing_player != null:
		return

	var push_body := player.get_node_or_null("PushBody") as RigidBody3D

	if push_body == null:
		push_warning("SHOPPING CART: Player has no PushBody")
		return

	pushing_player = player

	# Connect the joint to the dynamically spawned player's PushBody.
	push_joint.node_a = push_joint.get_path_to(push_body)

	# Connect the other side of the joint to this cart.
	push_joint.node_b = push_joint.get_path_to(self)

	print("SHOPPING CART: Joint connected to ", player.name)


func stop_pushing() -> void:
	push_joint.node_a = NodePath()
	push_joint.node_b = NodePath()

	pushing_player = null

	print("SHOPPING CART: Joint disconnected")
