
extends Node
class_name PlayerCheckout


# ============================================================
# CONSTANTS
# ============================================================

const CHECKOUT_POINTER_TEXTURE: Texture2D = preload(
	"res://assets/images/hand_pointer_32px.png"
)

# ============================================================
# NODE REFERENCES
# ============================================================

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D

# ============================================================
# VIRTUAL CURSOR STATE
# ============================================================

var checkout_virtual_mouse_position: Vector2 = Vector2.ZERO
var checkout_virtual_mouse_initialized: bool = false
var checkout_last_mouse_position: Vector2 = Vector2.ZERO
var checkout_using_controller_cursor: bool = false

# ============================================================
# CHECKOUT POINTER STATE
# ============================================================

var checkout_pointer_layer: CanvasLayer = null
var checkout_pointer: Sprite2D = null

# ============================================================
# 3D PRODUCT CURSOR STATE
# ============================================================

var checkout_cursor_visual: MeshInstance3D = null
var checkout_cursor_sensor: Area3D = null
var checkout_cursor_last_safe_position: Vector3 = Vector3.ZERO
var checkout_cursor_has_safe_position: bool = false

# ============================================================
# CHECKOUT INTERACTION STATE
# ============================================================

var checkout_scanned_product_path: String = ""
var checkout_auto_bag_hover_active: bool = false

# ============================================================
# CURSOR INITIALIZATION
# ============================================================

func initialize_cursor() -> void:
	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	checkout_virtual_mouse_position = viewport_size * 0.5
	checkout_last_mouse_position = checkout_virtual_mouse_position
	checkout_virtual_mouse_initialized = true
	checkout_using_controller_cursor = false


func ensure_cursor_initialized() -> void:
	if checkout_virtual_mouse_initialized:
		return

	checkout_virtual_mouse_position = (
		get_viewport().get_mouse_position()
	)

	checkout_virtual_mouse_initialized = true


# ============================================================
# SHARED CURSOR MOVEMENT
# ============================================================

func _move_cursor(cursor_delta: Vector2) -> void:
	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	checkout_virtual_mouse_position += cursor_delta

	checkout_virtual_mouse_position = (
		checkout_virtual_mouse_position.clamp(
			Vector2.ZERO,
			viewport_size
		)
	)

	checkout_last_mouse_position = checkout_virtual_mouse_position


# ============================================================
# MOUSE CURSOR INPUT
# ============================================================

func handle_mouse_motion(
	event: InputEventMouseMotion,
	rotating_held_product: bool,
	mouse_sensitivity: float
) -> void:
	if rotating_held_product:
		return

	var mouse_delta: Vector2 = (
		event.screen_relative * mouse_sensitivity
	)

	if mouse_delta.length_squared() <= 0.0:
		return

	checkout_using_controller_cursor = false

	_move_cursor(mouse_delta)


func update_checkout_mouse_cursor(
	checkout_mode_active: bool
) -> void:
	if not checkout_mode_active:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	checkout_virtual_mouse_initialized = true


# ============================================================
# CONTROLLER CURSOR INPUT
# ============================================================

func update_checkout_controller_cursor(
	delta: float,
	is_local_player: bool,
	checkout_mode_active: bool,
	cursor_speed: float,
	controller_sensitivity: float
) -> void:
	if not is_local_player:
		return

	if not checkout_mode_active:
		return

	var stick_input: Vector2 = Input.get_vector(
		"checkout_cursor_left",
		"checkout_cursor_right",
		"checkout_cursor_up",
		"checkout_cursor_down"
	)

	if stick_input.length() < 0.15:
		return

	checkout_using_controller_cursor = true

	var cursor_delta: Vector2 = (
		stick_input
		* cursor_speed
		* controller_sensitivity
		* delta
	)

	_move_cursor(cursor_delta)

	checkout_virtual_mouse_initialized = true


# ============================================================
# CHECKOUT POINTER
# ============================================================

func create_checkout_pointer() -> void:
	if is_instance_valid(checkout_pointer_layer):
		return

	checkout_pointer_layer = CanvasLayer.new()
	checkout_pointer_layer.layer = 100
	add_child(checkout_pointer_layer)

	checkout_pointer = Sprite2D.new()
	checkout_pointer.texture = CHECKOUT_POINTER_TEXTURE
	checkout_pointer.centered = false
	checkout_pointer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	checkout_pointer_layer.add_child(checkout_pointer)


func remove_checkout_pointer() -> void:
	if is_instance_valid(checkout_pointer_layer):
		checkout_pointer_layer.queue_free()

	checkout_pointer_layer = null
	checkout_pointer = null

	checkout_using_controller_cursor = false


func update_checkout_pointer(
	checkout_mode_active: bool,
	holding_checkout_product: bool,
	rotating_held_product: bool
) -> void:
	if not checkout_mode_active:
		return

	if not is_instance_valid(checkout_pointer):
		return

	checkout_pointer.visible = (
		not holding_checkout_product
		and not rotating_held_product
	)

	checkout_pointer.position = checkout_virtual_mouse_position


# ============================================================
# 3D PRODUCT CURSOR
# ============================================================

func create_checkout_cursor_visual() -> void:
	if not player.is_multiplayer_authority():
		return

	if not player.checkout_mode_active:
		return

	if player.held_item == null:
		return

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return

	if not is_instance_valid(player.active_checkout):
		return

	var camera: Camera3D = player.active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return

	clear_checkout_cursor_visual()
	ensure_cursor_initialized()

	if player.held_item_visual == null:
		return

	checkout_cursor_visual = (
		player.held_item_visual.duplicate() as MeshInstance3D
	)

	if checkout_cursor_visual == null:
		return

	checkout_cursor_visual.name = "CheckoutCursorProduct"

	camera.add_child(checkout_cursor_visual)

	create_checkout_cursor_sensor()

	checkout_cursor_visual.rotation = player.held_item_visual.rotation

	var mouse_position: Vector2 = (
		checkout_virtual_mouse_position
		+ player.checkout_cursor_offset
	)

	var initial_position: Vector3 = (
		get_checkout_cursor_centered_position(
			camera,
			mouse_position
		)
	)

	var spawn_world_position: Vector3 = (
		camera.to_global(initial_position)
		+ Vector3.UP * 0.2
	)

	var spawn_position: Vector3 = (
		camera.to_local(spawn_world_position)
	)

	checkout_cursor_visual.position = spawn_position

	if not is_checkout_cursor_position_clear(spawn_position):
		if not find_checkout_cursor_safe_position(spawn_position):
			clear_checkout_cursor_visual()
			return
	else:
		checkout_cursor_last_safe_position = spawn_position
		checkout_cursor_has_safe_position = true


func update_checkout_cursor_visual() -> void:
	update_checkout_mouse_cursor(player.checkout_mode_active)

	if not player.checkout_mode_active:
		return

	if player.held_item == null:
		clear_checkout_cursor_visual()
		return

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		clear_checkout_cursor_visual()
		return

	if not is_instance_valid(checkout_cursor_visual):
		create_checkout_cursor_visual()

	if not is_instance_valid(checkout_cursor_visual):
		return

	if not is_instance_valid(player.active_checkout):
		return

	var camera: Camera3D = player.active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return

	var mouse_position: Vector2 = (
		player.checkout_rotation_mouse_position
		if player.rotating_held_product
		else checkout_virtual_mouse_position
	)

	if not player.rotating_held_product:
		checkout_last_mouse_position = mouse_position

	mouse_position += player.checkout_cursor_offset

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	mouse_position = mouse_position.clamp(
		Vector2.ZERO,
		viewport_size
	)

	var target_position: Vector3 = (
		get_checkout_cursor_centered_position(
			camera,
			mouse_position
		)
	)

	var result_position: Vector3 = (
		get_checkout_cursor_collision_position(target_position)
	)

	checkout_cursor_visual.position = result_position

	if is_checkout_cursor_position_clear(result_position):
		checkout_cursor_last_safe_position = result_position
		checkout_cursor_has_safe_position = true

		if (
			player.is_multiplayer_authority()
			and player.held_item != null
			and player.held_item_origin == player.ItemOrigin.CHECKOUT_GRID
			and is_instance_valid(player.active_checkout)
			and is_instance_valid(checkout_cursor_visual)
		):
			var product: ProductData = player.held_item as ProductData

			if (
				product != null
				and product.product_category != "produce"
				and checkout_scanned_product_path != product.resource_path
				and player.active_checkout.is_barcode_aligned(
					product,
					checkout_cursor_visual
				)
			):
				player.active_checkout.interact(player)


func clear_checkout_cursor_visual() -> void:
	if is_instance_valid(checkout_cursor_visual):
		checkout_cursor_visual.queue_free()

	checkout_cursor_visual = null
	checkout_cursor_sensor = null
	checkout_cursor_last_safe_position = Vector3.ZERO
	checkout_cursor_has_safe_position = false


# ============================================================
# PRODUCT SCANNER SENSOR
# ============================================================

func create_checkout_cursor_sensor() -> void:
	if not is_instance_valid(checkout_cursor_visual):
		return

	if not is_instance_valid(player.active_checkout):
		return

	if not is_instance_valid(player.active_checkout.scan_area):
		return

	var product_bounds: AABB = checkout_cursor_visual.get_aabb()

	if product_bounds.size.is_zero_approx():
		return

	checkout_cursor_sensor = Area3D.new()
	checkout_cursor_sensor.name = "CheckoutProductSensor"

	# Detect the scanner without becoming a target.
	checkout_cursor_sensor.collision_layer = 0
	checkout_cursor_sensor.collision_mask = (
		player.active_checkout.scan_area.collision_layer
	)

	checkout_cursor_sensor.monitoring = true
	checkout_cursor_sensor.monitorable = false

	var new_collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()

	box_shape.size = product_bounds.size
	new_collision_shape.shape = box_shape
	new_collision_shape.position = product_bounds.get_center()

	checkout_cursor_sensor.add_child(new_collision_shape)
	checkout_cursor_visual.add_child(checkout_cursor_sensor)

	checkout_cursor_sensor.area_entered.connect(
		_on_checkout_product_sensor_area_entered
	)


func _on_checkout_product_sensor_area_entered(area: Area3D) -> void:
	if not player.checkout_mode_active:
		return

	if not is_instance_valid(player.active_checkout):
		return

	if area != player.active_checkout.scan_area:
		return

	if player.held_item == null:
		return

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return

	player.active_checkout.interact(player)


# ============================================================
# PRODUCT CURSOR POSITIONING
# ============================================================

func get_checkout_cursor_centered_position(
	camera: Camera3D,
	mouse_position: Vector2
) -> Vector3:

	var world_position: Vector3 = camera.project_position(
		mouse_position,
		player.checkout_cursor_depth
	)

	var target_position: Vector3 = camera.to_local(world_position)

	# Find the visual center of the product mesh.
	var mesh_center: Vector3 = checkout_cursor_visual.get_aabb().get_center()

	# Account for rotation and scale.
	var center_offset: Vector3 = (
		checkout_cursor_visual.transform.basis * mesh_center
	)

	return target_position - center_offset


func get_checkout_cursor_screen_position() -> Vector2:
	if not is_instance_valid(checkout_cursor_visual):
		return checkout_virtual_mouse_position

	if not is_instance_valid(player.active_checkout):
		return checkout_virtual_mouse_position

	var camera: Camera3D = player.active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return checkout_virtual_mouse_position

	var product_bounds: AABB = checkout_cursor_visual.get_aabb()

	var product_center: Vector3 = (
		checkout_cursor_visual.global_position
		+ checkout_cursor_visual.global_transform.basis
		* product_bounds.get_center()
	)

	return camera.unproject_position(product_center)


# ============================================================
# PRODUCT CURSOR COLLISION QUERIES
# ============================================================

func get_checkout_cursor_shape_query(
	candidate_position: Vector3
) -> PhysicsShapeQueryParameters3D:

	if not is_instance_valid(checkout_cursor_visual):
		return null

	var product_bounds: AABB = checkout_cursor_visual.get_aabb()

	if product_bounds.size.is_zero_approx():
		return null

	if not is_instance_valid(player.active_checkout):
		return null

	var camera: Camera3D = player.active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return null

	# Match the collision box to the product's size.
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = product_bounds.size * checkout_cursor_visual.scale.abs()

	var query: PhysicsShapeQueryParameters3D = (
		PhysicsShapeQueryParameters3D.new()
	)

	query.shape = shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.01

	# Ignore the player.
	query.exclude = [player.get_rid()]

	# Account for rotation and mesh center.
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

	var query: PhysicsShapeQueryParameters3D = (
		get_checkout_cursor_shape_query(candidate_position)
	)

	if query == null:
		return false

	var space_state: PhysicsDirectSpaceState3D = (
		player.get_world_3d().direct_space_state
	)

	var overlaps: Array[Dictionary] = (
		space_state.intersect_shape(query, 64)
	)

	for overlap: Dictionary in overlaps:
		var collider: Object = overlap.get("collider")

		# Ignore other player characters, but retain collisions
		# with counters and other physical objects.
		var player_collider: CharacterBody3D = (
			collider as CharacterBody3D
		)

		if (
			player_collider != null
			and player_collider.get_script() == player.get_script()
		):
			continue

		return false

	return true


# ============================================================
# PRODUCT CURSOR COLLISION RECOVERY
# ============================================================

func find_checkout_cursor_safe_position(
	start_position: Vector3
) -> bool:

	if not is_instance_valid(checkout_cursor_visual):
		return false

	if not is_instance_valid(player.active_checkout):
		return false

	var camera: Camera3D = player.active_checkout.checkout_camera

	if not is_instance_valid(camera):
		return false

	var candidate_world: Vector3 = camera.to_global(start_position)

	# Search upward until the product is clear.
	for attempt in range(100):
		var candidate_local: Vector3 = camera.to_local(candidate_world)

		checkout_cursor_visual.position = candidate_local

		if is_checkout_cursor_position_clear(candidate_local):
			checkout_cursor_last_safe_position = candidate_local
			checkout_cursor_has_safe_position = true
			return true

		candidate_world += Vector3.UP * 0.025

	return false


# ============================================================
# PRODUCT CURSOR COLLISION RESOLUTION
# ============================================================

func get_checkout_cursor_collision_position(
	target_position: Vector3
) -> Vector3:

	if not is_instance_valid(checkout_cursor_visual):
		return target_position

	if not is_instance_valid(player.active_checkout):
		return target_position

	var camera: Camera3D = player.active_checkout.checkout_camera

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

	# Process vertical movement first so products can lift
	# away from the counter when horizontal movement is blocked.
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

		# Apply the movement possible along this axis.
		var applied_motion: Vector3 = (
			direction * last_clear_distance
		)

		current_world += applied_motion

		remaining_motion -= axis_motion

	var result_position: Vector3 = camera.to_local(current_world)

	if is_checkout_cursor_position_clear(result_position):
		checkout_cursor_last_safe_position = result_position
		checkout_cursor_has_safe_position = true

	return result_position


# ============================================================
# CHECKOUT HOVER
# ============================================================

func update_checkout_hover() -> void:
	if not player.checkout_mode_active:
		return

	if not is_instance_valid(player.active_checkout):
		return

	var mouse_position: Vector2 = (
		_get_checkout_hover_position()
	)

	player.active_checkout.update_checkout_hover_outline(
		mouse_position,
		not player.is_holding_equipment()
	)

	_update_checkout_auto_bag(mouse_position)


func _get_checkout_hover_position() -> Vector2:
	# Align hover detection with the held product's actual position.
	if (
		player.held_item != null
		and player.held_item_origin == player.ItemOrigin.CHECKOUT_GRID
	):
		return get_checkout_cursor_screen_position()

	return checkout_virtual_mouse_position


# ============================================================
# AUTOMATIC BAGGING
# ============================================================

func _can_auto_bag_checkout_product(
	mouse_position: Vector2
) -> bool:

	if not player.is_multiplayer_authority():
		return false

	if player.held_item == null:
		return false

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return false

	if not player.active_checkout.is_mouse_over_bag(mouse_position):
		return false

	return (
		checkout_scanned_product_path
		== player.held_item.resource_path
	)


func _update_checkout_auto_bag(
	mouse_position: Vector2
) -> void:

	var should_auto_bag: bool = (
		_can_auto_bag_checkout_product(mouse_position)
	)

	if should_auto_bag and not checkout_auto_bag_hover_active:
		checkout_auto_bag_hover_active = true

		player.active_checkout.bag_grid.request_interact(
			player
		)

	elif not should_auto_bag:
		checkout_auto_bag_hover_active = false


# ============================================================
# CHECKOUT INTERACTION
# ============================================================

func handle_checkout_interaction() -> void:
	if not player.checkout_mode_active:
		return

	if not is_instance_valid(player.active_checkout):
		return

	var mouse_position: Vector2 = (
		checkout_virtual_mouse_position
	)

	# Handle a product already held by the player.
	if player.held_item != null:
		if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
			return

		mouse_position = get_checkout_cursor_screen_position()

		# Interact with the scanner.
		if player.active_checkout.is_mouse_over_scanner(mouse_position):
			player.active_checkout.interact(player)
			return

		# Interact with the bagging area.
		if player.active_checkout.is_mouse_over_bag(mouse_position):
			player.active_checkout.bag_grid.request_interact(
				player
			)
			return

		return

	# Prevent picking up products while holding equipment.
	if player.is_holding_equipment():
		return

	# Pick up the targeted checkout product.
	player.active_checkout.checkout_grid.request_take_item_at_mouse(
		player,
		mouse_position
	)
