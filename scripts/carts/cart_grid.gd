@tool
extends Node3D
class_name CartGrid

signal cart_contents_changed(cart_grid: CartGrid)

@export_group("Cart Capacity")
@export_range(1, 100, 1) var max_items: int = 20

@export_group("Spacing")
@export var horizontal_spacing: float = 0.05
@export var vertical_spacing: float = 0.05
@export var depth_spacing: float = 0.05

@export_group("Display")
@export var item_scale: Vector3 = Vector3.ONE
@export_range(0.0, 15.0, 0.5) var rotation_variation_degrees: float = 3.0

@export_group("Interaction Area")
@export var interaction_top_padding: float = 0.2
@export var item_target_distance: float = 8.0

@export_group("Outline")
@export var outline_material: Material

var cart_outline: MeshInstance3D = null
var outlined_visual: MeshInstance3D = null

@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_collision: CollisionShape3D = $InteractionArea/CollisionShape3D

var cart_items: Array[ProductData] = []
var item_positions: Array[Vector3] = []
var item_visuals: Array[MeshInstance3D] = []

var cached_fit_product: ProductData = null
var cached_fit_position: Vector3 = Vector3.INF
var fit_cache_valid: bool = false


func _ready() -> void:
	add_to_group("cart_grid")

	_rebuild_grid()

	if not Engine.is_editor_hint():
		if not multiplayer.is_server():
			call_deferred("_request_cart_state")


func _request_cart_state() -> void:
	if multiplayer.is_server():
		return

	request_cart_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_cart_state() -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var product_paths: Array[String] = []

	for product: ProductData in cart_items:
		if product == null:
			product_paths.append("")
		else:
			product_paths.append(product.resource_path)

	sync_cart_state.rpc_id(
		requesting_peer_id,
		product_paths
	)


func add_item(product: ProductData) -> bool:
	print(
		"ADD ITEM: ",
		product.display_name if product != null else "NULL",
		" | cart_items=",
		cart_items.size()
	)
	
	if product == null:
		return false

	if cart_items.size() >= max_items:
		return false

	var placement: Vector3 = Vector3.INF

	if fit_cache_valid and cached_fit_product == product:
		placement = cached_fit_position
	else:
		placement = _find_position_for_new_item(product)

	if placement == Vector3.INF:
		return false

	cart_items.append(product)
	item_positions.append(placement)

	_invalidate_fit_cache()

	_create_and_add_visual(
		product,
		placement,
		item_visuals.size()
	)

	return true


func take_last_item() -> ProductData:
	if cart_items.is_empty():
		return null

	return take_item_at_index(cart_items.size() - 1)


func take_item_at_index(item_index: int) -> ProductData:
	if item_index < 0 or item_index >= cart_items.size():
		return null

	var product: ProductData = cart_items[item_index]

	if product == null:
		return null

	cart_items.remove_at(item_index)

	if item_index < item_positions.size():
		item_positions.remove_at(item_index)

	if item_index < item_visuals.size():
		var visual: MeshInstance3D = item_visuals[item_index]
		item_visuals.remove_at(item_index)

		if is_instance_valid(visual):
			visual.queue_free()

	_invalidate_fit_cache()
	_clear_take_item_outline()

	return product


func has_items() -> bool:
	return not cart_items.is_empty()


func get_item_count() -> int:
	return cart_items.size()


func get_last_item() -> ProductData:
	if cart_items.is_empty():
		return null

	return cart_items[cart_items.size() - 1]


func get_interaction_prompt_for_player(
	player: CharacterBody3D
	) -> String:
	if player == null:
		_clear_take_item_outline()
		return ""

	if player.held_item != null:
		_clear_take_item_outline()

		if is_full():
			return ""

		if not _can_fit_product(player.held_item):
			return ""

		if player.held_item.display_name.is_empty():
			return "[E] Place Item"

		return "[E] Place " + player.held_item.display_name

	if cart_items.is_empty():
		_clear_take_item_outline()
		return ""

	var take_index: int = _get_take_item_index(player)

	if take_index < 0:
		_clear_take_item_outline()
		return ""

	_update_take_item_outline(take_index)

	var product: ProductData = cart_items[take_index]

	if product == null:
		return "[E] Take Item"

	if product.display_name.is_empty():
		return "[E] Take Item"

	return "[E] Take " + product.display_name


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
	) -> Vector3:
	# If an item is currently being targeted, place the prompt
	# above that item instead of above the entire interaction area.
	if is_instance_valid(outlined_visual):
		var product_size: Vector3 = Vector3.ZERO

		var item_index: int = item_visuals.find(outlined_visual)

		if item_index >= 0 and item_index < cart_items.size():
			var product: ProductData = cart_items[item_index]

			if product != null:
				product_size = _get_product_size(product)

		if product_size.y > 0.0:
			return (
				outlined_visual.global_position
				+ Vector3.UP * (
					product_size.y * 0.5
					+ interaction_top_padding
				)
			)

		# Fallback if we couldn't get the product size.
		return (
			outlined_visual.global_position
			+ Vector3.UP * interaction_top_padding
		)

	# No item targeted — use the normal grid-bound position.
	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		return collision_shape.global_position

	return (
		collision_shape.global_position
		+ Vector3.UP * (
			box_shape.size.y * 0.5
			+ interaction_top_padding
		)
	)


func is_full() -> bool:
	return cart_items.size() >= max_items


func _can_fit_product(product: ProductData) -> bool:
	if product == null:
		return false

	if cart_items.size() >= max_items:
		return false

	var placement: Vector3 = _find_position_for_new_item(product)

	cached_fit_product = product
	cached_fit_position = placement
	fit_cache_valid = true

	return placement != Vector3.INF


# -------------------------------------------------------------------
# Item targeting
# -------------------------------------------------------------------

func _get_take_item_index(player: CharacterBody3D) -> int:
	if player == null:
		return -1

	if cart_items.is_empty():
		return -1

	var camera: Camera3D = player.get_viewport().get_camera_3d()

	if camera == null:
		return -1

	var ray_origin: Vector3 = camera.global_position
	var ray_direction: Vector3 = -camera.global_transform.basis.z

	var closest_distance: float = item_target_distance
	var closest_index: int = -1

	var item_count: int = mini(
		cart_items.size(),
		item_visuals.size()
	)

	for index: int in range(item_count):
		var visual: MeshInstance3D = item_visuals[index]

		if not is_instance_valid(visual):
			continue

		if visual.mesh == null:
			continue

		var hit_distance: float = _get_ray_mesh_distance(
			ray_origin,
			ray_direction,
			visual
		)

		if hit_distance < 0.0:
			continue

		if hit_distance < closest_distance:
			closest_distance = hit_distance
			closest_index = index

	return closest_index


func _get_ray_mesh_distance(
	ray_origin: Vector3,
	ray_direction: Vector3,
	visual: MeshInstance3D
	) -> float:
	if visual == null:
		return -1.0

	if visual.mesh == null:
		return -1.0

	var inverse_transform: Transform3D = (
		visual.global_transform.affine_inverse()
	)

	var local_origin: Vector3 = (
		inverse_transform * ray_origin
	)

	var local_direction: Vector3 = (
		inverse_transform.basis * ray_direction
	)

	if local_direction.length_squared() <= 0.000001:
		return -1.0

	local_direction = local_direction.normalized()

	var bounds: AABB = visual.mesh.get_aabb()

	var local_distance: float = _ray_aabb_distance(
		local_origin,
		local_direction,
		bounds
	)

	if local_distance < 0.0:
		return -1.0

	var local_hit: Vector3 = (
		local_origin
		+ local_direction * local_distance
	)

	var world_hit: Vector3 = (
		visual.global_transform * local_hit
	)

	return ray_origin.distance_to(world_hit)


func _ray_aabb_distance(
	ray_origin: Vector3,
	ray_direction: Vector3,
	bounds: AABB
	) -> float:
	var t_min: float = 0.0
	var t_max: float = INF

	var min_bound: Vector3 = bounds.position
	var max_bound: Vector3 = bounds.end

	for axis: int in range(3):
		var origin_value: float = ray_origin[axis]
		var direction_value: float = ray_direction[axis]

		if absf(direction_value) < 0.000001:
			if (
				origin_value < min_bound[axis]
				or origin_value > max_bound[axis]
			):
				return -1.0

			continue

		var inverse_direction: float = 1.0 / direction_value

		var t1: float = (
			min_bound[axis] - origin_value
		) * inverse_direction

		var t2: float = (
			max_bound[axis] - origin_value
		) * inverse_direction

		if t1 > t2:
			var temp: float = t1
			t1 = t2
			t2 = temp

		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)

		if t_min > t_max:
			return -1.0

	return t_min


# -------------------------------------------------------------------
# Simplified placement
# -------------------------------------------------------------------

func _find_position_for_new_item(
	product: ProductData
	) -> Vector3:
	var product_size: Vector3 = _get_product_size(product)

	if product_size.x <= 0.0:
		return Vector3.INF

	if product_size.y <= 0.0:
		return Vector3.INF

	if product_size.z <= 0.0:
		return Vector3.INF

	var bounds: AABB = _get_cart_bounds()

	if not _product_can_fit_inside_cart(product_size, bounds):
		return Vector3.INF

	var bottom_y: float = (
		bounds.position.y
		+ product_size.y * 0.5
	)

	# Empty grid
	if item_positions.is_empty():
		var first_position: Vector3 = Vector3(
			bounds.position.x + product_size.x * 0.5,
			bottom_y,
			bounds.position.z + product_size.z * 0.5
		)

		if _position_fits_bounds(
			first_position,
			product_size,
			bounds
		):
			return first_position

		return Vector3.INF

	# Bottom level: positions beside existing items, all at bottom.
	for index: int in range(item_positions.size()):
		var existing_product: ProductData = cart_items[index]

		if existing_product == null:
			continue

		var existing_size: Vector3 = _get_product_size(
			existing_product
		)

		var existing_position: Vector3 = item_positions[index]

		# Right
		var right_position: Vector3 = Vector3(
			existing_position.x
			+ existing_size.x * 0.5
			+ horizontal_spacing
			+ product_size.x * 0.5,
			bottom_y,
			existing_position.z
		)

		if (
			_position_fits_bounds(
				right_position,
				product_size,
				bounds
			)
			and not _position_overlaps_items(
				right_position,
				product_size
			)
		):
			return right_position

		# Left
		var left_position: Vector3 = Vector3(
			existing_position.x
			- existing_size.x * 0.5
			- horizontal_spacing
			- product_size.x * 0.5,
			bottom_y,
			existing_position.z
		)

		if (
			_position_fits_bounds(
				left_position,
				product_size,
				bounds
			)
			and not _position_overlaps_items(
				left_position,
				product_size
			)
		):
			return left_position

		# Behind
		var back_position: Vector3 = Vector3(
			existing_position.x,
			bottom_y,
			existing_position.z
			+ existing_size.z * 0.5
			+ depth_spacing
			+ product_size.z * 0.5
		)

		if (
			_position_fits_bounds(
				back_position,
				product_size,
				bounds
			)
			and not _position_overlaps_items(
				back_position,
				product_size
			)
		):
			return back_position

		# In front
		var front_position: Vector3 = Vector3(
			existing_position.x,
			bottom_y,
			existing_position.z
			- existing_size.z * 0.5
			- depth_spacing
			- product_size.z * 0.5
		)

		if (
			_position_fits_bounds(
				front_position,
				product_size,
				bounds
			)
			and not _position_overlaps_items(
				front_position,
				product_size
			)
		):
			return front_position

	# Bottom-level fallback scan.
	var scan_step_x: float = (
		product_size.x + horizontal_spacing
	)

	var scan_step_z: float = (
		product_size.z + depth_spacing
	)

	var max_x: float = (
		bounds.end.x
		- product_size.x * 0.5
	)

	var max_z: float = (
		bounds.end.z
		- product_size.z * 0.5
	)

	var scan_x: float = (
		bounds.position.x
		+ product_size.x * 0.5
	)

	while scan_x <= max_x:
		var scan_z: float = (
			bounds.position.z
			+ product_size.z * 0.5
		)

		while scan_z <= max_z:
			var scan_position: Vector3 = Vector3(
				scan_x,
				bottom_y,
				scan_z
			)

			if not _position_overlaps_items(
				scan_position,
				product_size
			):
				return scan_position

			scan_z += scan_step_z

		scan_x += scan_step_x

	# Vertical stacking only after bottom-level options.
	for index: int in range(item_positions.size()):
		var existing_product: ProductData = cart_items[index]

		if existing_product == null:
			continue

		var existing_size: Vector3 = _get_product_size(
			existing_product
		)

		var existing_position: Vector3 = item_positions[index]

		var stack_position: Vector3 = Vector3(
			existing_position.x,
			existing_position.y
			+ existing_size.y * 0.5
			+ vertical_spacing
			+ product_size.y * 0.5,
			existing_position.z
		)

		if not _position_fits_bounds(
			stack_position,
			product_size,
			bounds
		):
			continue

		if _position_overlaps_items(
			stack_position,
			product_size
		):
			continue

		return stack_position

	return Vector3.INF
	
	
func _score_candidate_position(
	candidate: Vector3,
	product_size: Vector3,
	bounds: AABB
	) -> float:
	var score: float = 0.0

	# Prefer positions that stay close to the bottom of the basket.
	score += (
		candidate.y - bounds.position.y
	) * 10.0

	# Prefer positions toward the front/starting area.
	score += (
		candidate.z - bounds.position.z
	) * 2.0

	# Slight preference toward the left side.
	score += (
		candidate.x - bounds.position.x
	)

	return score


func _find_new_row_position(
	product_size: Vector3,
	bounds: AABB
	) -> Vector3:
	var x: float = (
		bounds.position.x
		+ product_size.x * 0.5
	)

	var z: float = (
		bounds.position.z
		+ product_size.z * 0.5
	)

	var highest_z: float = bounds.position.z

	for index: int in range(item_positions.size()):
		var existing_product: ProductData = cart_items[index]

		if existing_product == null:
			continue

		var existing_size: Vector3 = _get_product_size(
			existing_product
		)

		var existing_position: Vector3 = item_positions[index]

		highest_z = maxf(
			highest_z,
			existing_position.z
			+ existing_size.z * 0.5
		)

	z = highest_z + depth_spacing + product_size.z * 0.5

	var candidate: Vector3 = Vector3(
		x,
		bounds.position.y + product_size.y * 0.5,
		z
	)

	if not _position_fits_bounds(
		candidate,
		product_size,
		bounds
	):
		return Vector3.INF

	if _position_overlaps_items(
		candidate,
		product_size
	):
		return Vector3.INF

	return candidate


func _product_can_fit_inside_cart(
	product_size: Vector3,
	bounds: AABB
	) -> bool:
	return (
		product_size.x <= bounds.size.x
		and product_size.y <= bounds.size.y
		and product_size.z <= bounds.size.z
	)


func _position_fits_bounds(
	item_position: Vector3,
	product_size: Vector3,
	bounds: AABB
	) -> bool:
	var half_size: Vector3 = product_size * 0.5

	var item_min: Vector3 = (
		item_position - half_size
	)

	var item_max: Vector3 = (
		item_position + half_size
	)

	var tolerance: float = 0.0001

	return (
		item_min.x >= bounds.position.x - tolerance
		and item_max.x <= bounds.end.x + tolerance
		and item_min.y >= bounds.position.y - tolerance
		and item_max.y <= bounds.end.y + tolerance
		and item_min.z >= bounds.position.z - tolerance
		and item_max.z <= bounds.end.z + tolerance
	)


func _position_overlaps_items(
	item_position: Vector3,
	product_size: Vector3
	) -> bool:
	var product_min: Vector3 = (
		item_position - product_size * 0.5
	)

	var product_max: Vector3 = (
		item_position + product_size * 0.5
	)

	for index: int in range(item_positions.size()):
		var existing_position: Vector3 = item_positions[index]

		var existing_size: Vector3 = _get_product_size(
			cart_items[index]
		)

		var existing_min: Vector3 = (
			existing_position - existing_size * 0.5
		)

		var existing_max: Vector3 = (
			existing_position + existing_size * 0.5
		)

		if (
			product_min.x < existing_max.x
			and product_max.x > existing_min.x
			and product_min.y < existing_max.y
			and product_max.y > existing_min.y
			and product_min.z < existing_max.z
			and product_max.z > existing_min.z
		):
			return true

	return false


# -------------------------------------------------------------------
# Cart bounds / product bounds
# -------------------------------------------------------------------

func _get_cart_bounds() -> AABB:
	if interaction_collision == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)

	var box_shape: BoxShape3D = (
		interaction_collision.shape as BoxShape3D
	)

	if box_shape == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)

	var size: Vector3 = box_shape.size

	var bounds_position: Vector3 = (
		interaction_collision.position
		- size * 0.5
	)

	return AABB(
		bounds_position,
		size
	)


func _get_product_size(product: ProductData) -> Vector3:
	var product_bounds: AABB = _get_product_bounds(product)

	return product_bounds.size


func _get_product_bounds(product: ProductData) -> AABB:
	if product == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)

	if product.product_mesh == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)

	var mesh_bounds: AABB = (
		product.product_mesh.get_aabb()
	)

	var scaled_position: Vector3 = Vector3(
		mesh_bounds.position.x * item_scale.x,
		mesh_bounds.position.y * item_scale.y,
		mesh_bounds.position.z * item_scale.z
	)

	var scaled_size: Vector3 = Vector3(
		mesh_bounds.size.x * absf(item_scale.x),
		mesh_bounds.size.y * absf(item_scale.y),
		mesh_bounds.size.z * absf(item_scale.z)
	)

	return AABB(
		scaled_position,
		scaled_size
	)


# -------------------------------------------------------------------
# Visuals
# -------------------------------------------------------------------

func _create_and_add_visual(
	product: ProductData,
	target_center: Vector3,
	item_index: int
	) -> void:
	var visual: MeshInstance3D = _create_product_visual(
		product,
		target_center,
		item_index
	)

	if visual == null:
		return

	add_child(visual)
	item_visuals.append(visual)


func _create_product_visual(
	product: ProductData,
	target_center: Vector3,
	item_index: int
	) -> MeshInstance3D:
	if product == null:
		return null

	if product.product_mesh == null:
		return null

	var visual: MeshInstance3D = MeshInstance3D.new()

	visual.mesh = product.product_mesh
	visual.scale = item_scale
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var product_bounds: AABB = _get_product_bounds(product)

	visual.position = (
		target_center
		- product_bounds.position
		- product_bounds.size * 0.5
	)

	var rotation_seed: float = (
		float(item_index) * 37.0
		+ target_center.x * 13.0
		+ target_center.z * 17.0
	)

	var normalized_rotation: float = (
		fmod(absf(rotation_seed), 100.0) / 100.0
	)

	var rotation_amount: float = (
		(normalized_rotation * 2.0 - 1.0)
		* deg_to_rad(rotation_variation_degrees)
	)

	visual.rotation.y = rotation_amount

	return visual


func _clear_visuals() -> void:
	_clear_take_item_outline()

	for visual: MeshInstance3D in item_visuals:
		if is_instance_valid(visual):
			visual.queue_free()

	item_visuals.clear()


func _invalidate_fit_cache() -> void:
	cached_fit_product = null
	cached_fit_position = Vector3.INF
	fit_cache_valid = false


# -------------------------------------------------------------------
# Multiplayer interaction
# -------------------------------------------------------------------

func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	# Holding an item → try to place it in the cart.
	if player.held_item != null:
		var product_path: String = player.held_item.resource_path

		if multiplayer.is_server():
			_add_item_from_player(player, product_path)
		else:
			request_add_item.rpc_id(
				1,
				player.get_path(),
				product_path
			)

		return

	# Empty hands → take the item currently under the crosshair.
	if has_items():
		var take_index: int = _get_take_item_index(player)

		if take_index < 0:
			return

		if multiplayer.is_server():
			_take_item_for_player(
				player,
				take_index
			)
		else:
			request_take_item.rpc_id(
				1,
				player.get_path(),
				take_index
			)


@rpc("any_peer", "call_remote", "reliable")
func request_add_item(
	player_path: NodePath,
	product_path: String
	) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = (
		multiplayer.get_remote_sender_id()
	)

	var player_node: Node = get_node_or_null(player_path)

	if player_node == null:
		return

	if not player_node is CharacterBody3D:
		return

	var player: CharacterBody3D = (
		player_node as CharacterBody3D
	)

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	_add_item_from_player(
		player,
		product_path
	)


func _add_item_from_player(
	player: CharacterBody3D,
	product_path: String
	) -> void:
	if player == null:
		return

	if product_path.is_empty():
		return

	var product: ProductData = (
		load(product_path) as ProductData
	)

	if product == null:
		return

	if not add_item(product):
		return

	_clear_player_held_item(player)

	_broadcast_cart_state()


@rpc("any_peer", "call_remote", "reliable")
func request_take_item(
	player_path: NodePath,
	item_index: int
	) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = (
		multiplayer.get_remote_sender_id()
	)

	var player_node: Node = get_node_or_null(player_path)

	if player_node == null:
		return

	if not player_node is CharacterBody3D:
		return

	var player: CharacterBody3D = (
		player_node as CharacterBody3D
	)

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	_take_item_for_player(
		player,
		item_index
	)


func _take_item_for_player(
	player: CharacterBody3D,
	item_index: int
	) -> void:
	if player == null:
		return

	if player.held_item != null:
		return

	var product: ProductData = take_item_at_index(item_index)

	if product == null:
		return

	_give_product_to_player(
		player,
		product
	)

	_broadcast_cart_state()


func _give_product_to_player(
	player: CharacterBody3D,
	product: ProductData
	) -> void:
	if player == null:
		return

	if product == null:
		return

	var player_peer_id: int = (
		player.get_multiplayer_authority()
	)

	var product_path: String = (
		product.resource_path
	)

	if player_peer_id == multiplayer.get_unique_id():
		player.receive_product(product_path)
	else:
		player.receive_product.rpc_id(
			player_peer_id,
			product_path
		)


func _clear_player_held_item(
	player: CharacterBody3D
	) -> void:
	if player == null:
		return

	var player_peer_id: int = (
		player.get_multiplayer_authority()
	)

	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(
			player_peer_id
		)


# -------------------------------------------------------------------
# Multiplayer cart synchronization
# -------------------------------------------------------------------

func _broadcast_cart_state() -> void:
	if not multiplayer.is_server():
		return

	var product_paths: Array[String] = []

	for product: ProductData in cart_items:
		if product == null:
			product_paths.append("")
		else:
			product_paths.append(product.resource_path)

	_apply_cart_state(product_paths)

	sync_cart_state.rpc(product_paths)

	cart_contents_changed.emit(self)


@rpc("authority", "call_remote", "reliable")
func sync_cart_state(
	product_paths: Array[String]
	) -> void:
	_apply_cart_state(product_paths)

	cart_contents_changed.emit(self)


func _apply_cart_state(
	product_paths: Array[String]
	) -> void:
	if _matches_existing_prefix(product_paths):
		_apply_incremental_cart_state(product_paths)
		return

	_rebuild_from_paths(product_paths)


func _matches_existing_prefix(
	product_paths: Array[String]
	) -> bool:
	var shared_count: int = mini(
		product_paths.size(),
		cart_items.size()
	)

	for index: int in range(shared_count):
		var existing_product: ProductData = cart_items[index]

		if existing_product == null:
			if not product_paths[index].is_empty():
				return false

			continue

		if existing_product.resource_path != product_paths[index]:
			return false

	return true


func _apply_incremental_cart_state(
	product_paths: Array[String]
	) -> void:
	var target_count: int = product_paths.size()

	while cart_items.size() > target_count:
		cart_items.pop_back()

		if not item_positions.is_empty():
			item_positions.pop_back()

		if not item_visuals.is_empty():
			var visual: MeshInstance3D = item_visuals.pop_back()

			if is_instance_valid(visual):
				visual.queue_free()

	while cart_items.size() < target_count:
		var index: int = cart_items.size()

		var path: String = product_paths[index]

		if path.is_empty():
			cart_items.append(null)
			continue

		var product: ProductData = (
			load(path) as ProductData
		)

		if product == null:
			cart_items.append(null)
			continue

		var placement: Vector3 = (
			_find_position_for_new_item(product)
		)

		if placement == Vector3.INF:
			cart_items.append(product)
			item_positions.append(Vector3.ZERO)
			continue

		cart_items.append(product)
		item_positions.append(placement)

		_create_and_add_visual(
			product,
			placement,
			item_visuals.size()
		)

	_invalidate_fit_cache()


func _rebuild_from_paths(
	product_paths: Array[String]
	) -> void:
	_clear_visuals()

	cart_items.clear()
	item_positions.clear()

	for path: String in product_paths:
		if path.is_empty():
			continue

		var product: ProductData = (
			load(path) as ProductData
		)

		if product != null:
			cart_items.append(product)

	_rebuild_grid()


func _rebuild_grid() -> void:
	_clear_visuals()

	item_positions.clear()

	if cart_items.is_empty():
		_invalidate_fit_cache()
		return

	for product: ProductData in cart_items:
		if product == null:
			continue

		var placement: Vector3 = (
			_find_position_for_new_item(product)
		)

		if placement == Vector3.INF:
			continue

		item_positions.append(placement)

		_create_and_add_visual(
			product,
			placement,
			item_visuals.size()
		)

	_invalidate_fit_cache()


# -------------------------------------------------------------------
# Item outline
# -------------------------------------------------------------------

func _update_take_item_outline(item_index: int) -> void:
	if item_index < 0:
		_clear_take_item_outline()
		return

	if item_index >= item_visuals.size():
		_clear_take_item_outline()
		return

	if outline_material == null:
		_clear_take_item_outline()
		return

	var visual: MeshInstance3D = item_visuals[item_index]

	if not is_instance_valid(visual):
		_clear_take_item_outline()
		return

	if visual.mesh == null:
		_clear_take_item_outline()
		return

	# The correct item is already outlined.
	if outlined_visual == visual and is_instance_valid(cart_outline):
		return

	_clear_take_item_outline()

	cart_outline = MeshInstance3D.new()
	cart_outline.mesh = visual.mesh
	cart_outline.position = visual.position
	cart_outline.rotation = visual.rotation
	cart_outline.scale = Vector3(1.04, 1.02, 1.04)
	cart_outline.material_override = outline_material
	cart_outline.set_meta("generated_cart_outline", true)

	visual.get_parent().add_child(cart_outline)

	outlined_visual = visual


func _clear_take_item_outline() -> void:
	if is_instance_valid(cart_outline):
		cart_outline.queue_free()

	cart_outline = null
	outlined_visual = null
