extends RayCast3D

@export var interact_raycast_3d: RayCast3D

@export var interaction_prompt: Node3D

var current_interactable: Node3D = null
var current_outline_mesh: Node3D = null


func _process(_delta: float) -> void:
	if not is_colliding():
		_clear_interaction()
		return
	interact_raycast_3d.force_raycast_update()
	var collider: Node3D = get_collider()

	if collider == null or not collider.is_in_group("interactable_items"):
		_clear_interaction()
		return

	if current_interactable != collider:
		_hide_prompt()

		if current_outline_mesh:
			current_outline_mesh.visible = false
			current_outline_mesh = null

		current_interactable = collider

		current_outline_mesh = collider.get_node_or_null("MeshOutline") as Node3D

		if current_outline_mesh:
			current_outline_mesh.visible = true

	_update_interaction_prompt(collider)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and current_interactable:
		var item: Node3D = current_interactable

		_clear_interaction()

		if item.has_method("interact"):
			item.interact()
		else:
			item.queue_free()


func _update_interaction_prompt(collider: Node3D) -> void:
	if interaction_prompt == null:
		return

	var product_display: Node = collider.get_parent()

	if product_display == null:
		_hide_prompt()
		return

	if not product_display.has_method("get_interaction_prompt"):
		_hide_prompt()
		return

	var prompt_text: String = product_display.get_interaction_prompt()

	if prompt_text.is_empty():
		_hide_prompt()
		return

	var collision_shape: CollisionShape3D = collider.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

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

	# Get the camera position relative to the rotated interaction zone.
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

	# Choose whichever horizontal face is closest to the camera.
	if x_distance > z_distance:
		local_offset.x = signf(local_camera_position.x) * half_width
	else:
		local_offset.z = signf(local_camera_position.z) * half_depth

	# Convert the local face position into world space.
	var world_offset: Vector3 = (
		collision_shape.global_transform.basis
		* local_offset
	)

	prompt_position += world_offset

	# Make sure the prompt is hidden while changing to the new position.
	interaction_prompt.visible = false
	
	# Set the final position before making it visible.
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
