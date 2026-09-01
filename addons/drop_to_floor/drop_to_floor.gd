@tool
extends EditorPlugin

var drop_button: Button


func _enter_tree() -> void:
	drop_button = Button.new()
	drop_button.text = "Drop to Floor"
	drop_button.tooltip_text = "Drop selected 3D nodes onto the floor"
	drop_button.icon = get_editor_interface().get_base_control().get_theme_icon("Snap", "EditorIcons")
	drop_button.pressed.connect(_drop_selected_to_floor)

	add_control_to_container(
		CONTAINER_SPATIAL_EDITOR_MENU,
		drop_button
	)


func _exit_tree() -> void:
	if drop_button:
		drop_button.queue_free()


func _drop_selected_to_floor() -> void:
	var selection := get_editor_interface().get_selection()
	var selected_nodes := selection.get_selected_nodes()

	if selected_nodes.is_empty():
		return

	for node in selected_nodes:
		if node is Node3D:
			_drop_node_to_floor(node)


func _drop_node_to_floor(node: Node3D) -> void:
	var world := node.get_world_3d()

	if world == null:
		return

	var space_state := world.direct_space_state

	var start := node.global_position
	var end := start + Vector3.DOWN * 1000.0

	var query := PhysicsRayQueryParameters3D.create(
		start,
		end
	)

	query.collide_with_areas = false

	# Don't hit the object we're trying to move.
	if node is CollisionObject3D:
		query.exclude = [node.get_rid()]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		print("No floor found below: ", node.name)
		return

	var floor_position: Vector3 = result["position"]

	node.global_position.y = floor_position.y

	print("Dropped ", node.name, " to floor.")
