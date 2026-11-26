
extends Node
class_name PlayerProductRotation


# ============================================================
# NODE REFERENCES
# ============================================================

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D


# ============================================================
# ROTATION STATE
# ============================================================

var rotating_held_product: bool = false
var checkout_rotation_mouse_position: Vector2 = Vector2.ZERO
var checkout_rotation_previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


# ============================================================
# MOUSE ROTATION INPUT
# ============================================================

func handle_held_product_rotation_input(
	event: InputEvent
) -> bool:

	# Only products can be rotated.
	if player.held_item == null:
		if rotating_held_product:
			stop_held_product_rotation()

		return false

	# Handle right mouse button press and release.
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if event.pressed:
			start_held_product_rotation()
		else:
			stop_held_product_rotation()

		get_viewport().set_input_as_handled()
		return true

	# Rotate the product while right mouse is held.
	if event is InputEventMouseMotion and rotating_held_product:
		apply_held_product_rotation(
			event.screen_relative,
			event.shift_pressed
		)

		get_viewport().set_input_as_handled()
		return true

	return false


# ============================================================
# ROTATION STATE MANAGEMENT
# ============================================================

func start_held_product_rotation() -> void:
	rotating_held_product = true

	# Freeze the checkout cursor while rotating.
	if player.checkout_mode_active:
		checkout_rotation_mouse_position = (
			player.checkout_last_mouse_position
		)

		checkout_rotation_previous_mouse_mode = Input.mouse_mode

		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_clear_pending_camera_movement()


func stop_held_product_rotation() -> void:
	if not rotating_held_product:
		return

	rotating_held_product = false

	# Restore the mouse when leaving checkout rotation.
	if player.checkout_mode_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		get_viewport().warp_mouse(
			checkout_rotation_mouse_position
		)

		Input.mouse_mode = checkout_rotation_previous_mouse_mode

	_clear_pending_camera_movement()


func _clear_pending_camera_movement() -> void:
	player._mouse_input_direction = Vector2.ZERO
	player._smoothed_mouse_velocity = Vector2.ZERO
	player._camera_input_direction = Vector2.ZERO


# ============================================================
# ROTATION CAMERA
# ============================================================

func _get_rotation_camera() -> Camera3D:
	var rotation_camera: Camera3D = null

	# Use the checkout camera while scanning.
	if (
		player.checkout_mode_active
		and is_instance_valid(player.active_checkout)
		and is_instance_valid(player.active_checkout.checkout_camera)
	):
		rotation_camera = player.active_checkout.checkout_camera
	else:
		rotation_camera = get_viewport().get_camera_3d()

	# Fall back to the first-person camera.
	if not is_instance_valid(rotation_camera):
		rotation_camera = player._first_person_camera

	return rotation_camera


# ============================================================
# PRODUCT ROTATION
# ============================================================

func apply_held_product_rotation(
	mouse_delta: Vector2,
	roll_rotation: bool = false
) -> void:

	var rotation_camera: Camera3D = _get_rotation_camera()

	if not is_instance_valid(rotation_camera):
		return

	# Rotate the first-person held product.
	if is_instance_valid(player.held_item_visual):
		_set_product_rotation_around_center(
			player.held_item_visual,
			rotation_camera,
			mouse_delta,
			roll_rotation
		)

	# Rotate the checkout cursor preview.
	if is_instance_valid(player.checkout_cursor_visual):
		_set_product_rotation_around_center(
			player.checkout_cursor_visual,
			rotation_camera,
			mouse_delta,
			roll_rotation
		)


func _set_product_rotation_around_center(
	product_mesh: MeshInstance3D,
	rotation_camera: Camera3D,
	mouse_delta: Vector2,
	roll_rotation: bool = false
) -> void:

	if not is_instance_valid(product_mesh):
		return

	var sensitivity: float = player.held_product_rotation_sensitivity

	# Use the camera's fixed world-space directions.
	var camera_basis: Basis = (
		rotation_camera.global_basis.orthonormalized()
	)

	# Vertical movement controls pitch.
	var vertical_rotation: Quaternion = Quaternion(
		camera_basis.x,
		mouse_delta.y * sensitivity
	)

	var horizontal_axis: Vector3 = camera_basis.y

	# Roll modifier changes horizontal rotation from yaw to roll.
	if roll_rotation:
		horizontal_axis = -camera_basis.z

	var horizontal_rotation: Quaternion = Quaternion(
		horizontal_axis,
		mouse_delta.x * sensitivity
	)

	var world_rotation: Quaternion = (
		horizontal_rotation * vertical_rotation
	)

	# Preserve the visual center while rotating.
	var product_transform: Transform3D = product_mesh.global_transform
	var mesh_center: Vector3 = product_mesh.get_aabb().get_center()
	var world_center: Vector3 = product_transform * mesh_center

	product_transform.basis = (
		Basis(world_rotation) * product_transform.basis
	)

	product_transform.origin = (
		world_center - product_transform.basis * mesh_center
	)

	product_mesh.global_transform = product_transform


# ============================================================
# CONTROLLER ROTATION
# ============================================================

func update_controller_product_rotation(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	if not player.can_process_gameplay_input():
		return

	if player.held_item == null:
		return

	if (
		not player.checkout_mode_active
		and not Input.is_action_pressed("product_rotate")
	):
		return

	var stick_input: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	if stick_input.length() < 0.15:
		return

	var rotation_delta: Vector2 = stick_input * 500.0 * delta

	var roll_rotation: bool = (
		Input.is_action_pressed("product_rotate")
		if player.checkout_mode_active
		else Input.is_action_pressed("product_roll")
	)

	apply_held_product_rotation(
		rotation_delta,
		roll_rotation
	)
