extends RayCast3D

@export var player_character: CharacterBody3D
@export var interact_raycast_3d: RayCast3D
@export var interaction_prompt: Node3D

var current_interactable: Node3D = null
var current_outline_mesh: Node3D = null


func _process(_delta: float) -> void:
	if not is_colliding():
		_clear_interaction()
		return

	interact_raycast_3d.force_raycast_update()

	var collider: Node3D = get_collider() as Node3D

	if collider == null:
		_clear_interaction()
		return

	var interactable: Node3D = _get_interactable(collider)

	if interactable == null:
		_clear_interaction()
		return

	if current_interactable != interactable:
		_hide_prompt()

		if current_outline_mesh:
			current_outline_mesh.visible = false
			current_outline_mesh = null

		current_interactable = interactable

		current_outline_mesh = interactable.get_node_or_null(
			"Area3D/MeshOutline"
		) as Node3D

		if current_outline_mesh:
			current_outline_mesh.visible = true

	_update_interaction_prompt(collider, interactable)


func interact() -> void:
	if current_interactable == null:
		return

	var item: Node3D = current_interactable

	_clear_interaction()

	if player_character == null:
		return

	if player_character.has_method("interact_with_item"):
		player_character.interact_with_item(item)


func _get_interactable(collider: Node3D) -> Node3D:
	var node: Node = collider

	while node != null:
		if node.has_method("get_interaction_prompt"):
			return node as Node3D

		if node.has_method("interact") and node is not Area3D:
			return node as Node3D

		node = node.get_parent()

	return null


func _get_collision_shape(collider: Node3D) -> CollisionShape3D:
	if collider is CollisionShape3D:
		return collider as CollisionShape3D

	var collision_shape: CollisionShape3D = collider.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

	if collision_shape:
		return collision_shape

	for child: Node in collider.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D

	return null


func _update_interaction_prompt(
	collider: Node3D,
	interactable: Node3D
	) -> void:
	if interaction_prompt == null:
		return

	if not interactable.has_method("get_interaction_prompt"):
		_hide_prompt()
		return

	var prompt_text: String = interactable.get_interaction_prompt()

	if prompt_text.is_empty():
		_hide_prompt()
		return

	var collision_shape: CollisionShape3D = _get_collision_shape(collider)

	if collision_shape == null:
		_hide_prompt()
		return

	var label: Label3D = interaction_prompt.get_node_or_null(
		"Label3D"
	) as Label3D

	if label == null:
		_hide_prompt()
		return

	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		_hide_prompt()
		return

	label.text = prompt_text
	label.visible = true

	var prompt_position: Vector3 = (
		collision_shape.global_position
		+ Vector3.UP * 0.1
	)

	var camera_position: Vector3 = global_position

	var local_camera_position: Vector3 = (
		collision_shape.global_transform.affine_inverse()
		* camera_position
	)

	var half_width: float = box_shape.size.x * 0.5
	var half_depth: float = box_shape.size.z * 0.5

	var local_offset: Vector3 = Vector3.ZERO

	var x_distance: float = absf(local_camera_position.x)
	var z_distance: float = absf(local_camera_position.z)

	if x_distance > z_distance:
		local_offset.x = signf(local_camera_position.x) * half_width
	else:
		local_offset.z = signf(local_camera_position.z) * half_depth

	var world_offset: Vector3 = (
		collision_shape.global_transform.basis
		* local_offset
	)

	prompt_position += world_offset

	interaction_prompt.visible = false
	interaction_prompt.global_position = prompt_position
	interaction_prompt.visible = true


func _hide_prompt() -> void:
	if interaction_prompt:
		var label: Label3D = interaction_prompt.get_node_or_null(
			"Label3D"
		) as Label3D

		if label:
			label.visible = false

		interaction_prompt.visible = false


func _clear_interaction() -> void:
	if current_outline_mesh:
		current_outline_mesh.visible = false
		current_outline_mesh = null

	current_interactable = null

	_hide_prompt()


func set_interaction_enabled(enabled: bool) -> void:
	set_process(enabled)

	if not enabled:
		force_raycast_update()
		_clear_interaction()
