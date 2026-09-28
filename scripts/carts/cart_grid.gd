@tool
extends Node3D
class_name CartGrid


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


@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_collision: CollisionShape3D = $InteractionArea/CollisionShape3D


var cart_items: Array[ProductData] = []
var item_positions: Array[Vector3] = []
var item_visuals: Array[MeshInstance3D] = []


var cached_fit_product: ProductData = null
var cached_fit_position: Vector3 = Vector3.INF
var fit_cache_valid: bool = false


func _ready() -> void:
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

	var product: ProductData = cart_items.pop_back()

	if not item_positions.is_empty():
		item_positions.pop_back()

	if not item_visuals.is_empty():
		var visual: MeshInstance3D = item_visuals.pop_back()

		if is_instance_valid(visual):
			visual.queue_free()

	_invalidate_fit_cache()

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
		return ""

	if player.held_item != null:
		if is_full():
			return ""

		if not _can_fit_product(player.held_item):
			return ""

		if player.held_item.display_name.is_empty():
			return "[E] Place Item"

		return "[E] Place " + player.held_item.display_name

	if cart_items.is_empty():
		return ""

	var product: ProductData = cart_items[cart_items.size() - 1]

	if product == null:
		return "[E] Take Item"

	if product.display_name.is_empty():
		return "[E] Take Item"

	return "[E] Take " + product.display_name


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
	) -> Vector3:
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

	if fit_cache_valid and cached_fit_product == product:
		return cached_fit_position != Vector3.INF

	var placement: Vector3 = _find_fit_position(product)

	cached_fit_product = product
	cached_fit_position = placement
	fit_cache_valid = true

	return placement != Vector3.INF


func _find_fit_position(product: ProductData) -> Vector3:
	var product_bounds: AABB = _get_product_bounds(product)

	if product_bounds.size.x <= 0.0:
		return Vector3.INF

	if product_bounds.size.y <= 0.0:
		return Vector3.INF

	if product_bounds.size.z <= 0.0:
		return Vector3.INF

	var bounds: AABB = _get_cart_bounds()

	if not _product_can_fit_inside_cart(
		product_bounds.size,
		bounds
	):
		return Vector3.INF

	var candidate_x_values: Array[float] = []
	var candidate_z_values: Array[float] = []

	_build_candidate_x_values(
		candidate_x_values,
		product_bounds.size.x,
		bounds
	)

	_build_candidate_z_values(
		candidate_z_values,
		product_bounds.size.z,
		bounds
	)

	# First try to place directly on the cart floor.
	for candidate_z: float in candidate_z_values:
		for candidate_x: float in candidate_x_values:
			var candidate_position: Vector3 = Vector3(
				candidate_x,
				bounds.position.y
				+ product_bounds.size.y * 0.5,
				candidate_z
			)

			if not _position_fits_bounds(
				candidate_position,
				product_bounds.size,
				bounds
			):
				continue

			if _position_overlaps_items(
				candidate_position,
				product_bounds.size
			):
				continue

			return candidate_position

	# If the floor is full, try stacking.
	#
	# We intentionally return the first valid stacking position
	# instead of searching every possible position for the absolute
	# lowest one. This keeps placement fast as the cart fills.
	for candidate_z: float in candidate_z_values:
		for candidate_x: float in candidate_x_values:
			var candidate_position: Vector3 = Vector3(
				candidate_x,
				bounds.position.y
				+ product_bounds.size.y * 0.5,
				candidate_z
			)

			var support_height: float = _get_support_height(
				candidate_position,
				product_bounds.size,
				bounds
			)

			# This candidate does not have an item supporting it,
			# so it was already rejected as a floor placement.
			if is_equal_approx(
				support_height,
				bounds.position.y
			):
				continue

			candidate_position.y = (
				support_height
				+ product_bounds.size.y * 0.5
			)

			if not _position_fits_bounds(
				candidate_position,
				product_bounds.size,
				bounds
			):
				continue

			if _position_overlaps_items(
				candidate_position,
				product_bounds.size
			):
				continue

			return candidate_position

	return Vector3.INF


func _find_position_for_new_item(
	product: ProductData
	) -> Vector3:
	return _find_fit_position(product)


func _build_candidate_x_values(
	candidates: Array[float],
	product_width: float,
	bounds: AABB
	) -> void:
	var half_width: float = product_width * 0.5

	# Cart edges first.
	_add_candidate_value(
		candidates,
		bounds.position.x + half_width
	)

	_add_candidate_value(
		candidates,
		bounds.end.x - half_width
	)

	# Then positions based on existing items.
	for index: int in range(item_positions.size()):
		var existing_position: Vector3 = item_positions[index]
		var existing_size: Vector3 = _get_product_size(
			cart_items[index]
		)

		var existing_min_x: float = (
			existing_position.x
			- existing_size.x * 0.5
		)

		var existing_max_x: float = (
			existing_position.x
			+ existing_size.x * 0.5
		)

		# Immediately beside the existing item.
		_add_candidate_value(
			candidates,
			existing_max_x
			+ horizontal_spacing
			+ half_width
		)

		_add_candidate_value(
			candidates,
			existing_min_x
			- horizontal_spacing
			- half_width
		)

		# Directly above the existing item.
		_add_candidate_value(
			candidates,
			existing_position.x
		)


func _build_candidate_z_values(
	candidates: Array[float],
	product_depth: float,
	bounds: AABB
	) -> void:
	var half_depth: float = product_depth * 0.5

	# Cart edges first.
	_add_candidate_value(
		candidates,
		bounds.position.z + half_depth
	)

	_add_candidate_value(
		candidates,
		bounds.end.z - half_depth
	)

	# Then positions based on existing items.
	for index: int in range(item_positions.size()):
		var existing_position: Vector3 = item_positions[index]
		var existing_size: Vector3 = _get_product_size(
			cart_items[index]
		)

		var existing_min_z: float = (
			existing_position.z
			- existing_size.z * 0.5
		)

		var existing_max_z: float = (
			existing_position.z
			+ existing_size.z * 0.5
		)

		# Immediately beside the existing item.
		_add_candidate_value(
			candidates,
			existing_max_z
			+ depth_spacing
			+ half_depth
		)

		_add_candidate_value(
			candidates,
			existing_min_z
			- depth_spacing
			- half_depth
		)

		# Directly above the existing item.
		_add_candidate_value(
			candidates,
			existing_position.z
		)


func _get_support_height(
	item_position: Vector3,
	product_size: Vector3,
	bounds: AABB
	) -> float:
	var support_height: float = bounds.position.y

	var product_half_x: float = product_size.x * 0.5
	var product_half_z: float = product_size.z * 0.5

	var product_min_x: float = (
		item_position.x - product_half_x
	)

	var product_max_x: float = (
		item_position.x + product_half_x
	)

	var product_min_z: float = (
		item_position.z - product_half_z
	)

	var product_max_z: float = (
		item_position.z + product_half_z
	)

	for index: int in range(item_positions.size()):
		var existing_position: Vector3 = item_positions[index]
		var existing_size: Vector3 = _get_product_size(
			cart_items[index]
		)

		var existing_min_x: float = (
			existing_position.x
			- existing_size.x * 0.5
		)

		var existing_max_x: float = (
			existing_position.x
			+ existing_size.x * 0.5
		)

		var existing_min_z: float = (
			existing_position.z
			- existing_size.z * 0.5
		)

		var existing_max_z: float = (
			existing_position.z
			+ existing_size.z * 0.5
		)

		var overlaps_x: bool = (
			product_min_x < existing_max_x
			and product_max_x > existing_min_x
		)

		var overlaps_z: bool = (
			product_min_z < existing_max_z
			and product_max_z > existing_min_z
		)

		if not overlaps_x or not overlaps_z:
			continue

		var existing_top: float = (
			existing_position.y
			+ existing_size.y * 0.5
		)

		support_height = maxf(
			support_height,
			existing_top + vertical_spacing
		)

	return support_height


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

	var item_min: Vector3 = item_position - half_size
	var item_max: Vector3 = item_position + half_size

	return (
		item_min.x >= bounds.position.x
		and item_max.x <= bounds.end.x
		and item_min.y >= bounds.position.y
		and item_max.y <= bounds.end.y
		and item_min.z >= bounds.position.z
		and item_max.z <= bounds.end.z
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


func _add_candidate_value(
	candidates: Array[float],
	value: float
	) -> void:
	for existing: float in candidates:
		if is_equal_approx(existing, value):
			return

	candidates.append(value)


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


func _rebuild_grid() -> void:
	_clear_visuals()

	item_positions.clear()

	if cart_items.is_empty():
		_invalidate_fit_cache()
		return

	for product: ProductData in cart_items:
		if product == null:
			continue

		var placement: Vector3 = _find_position_for_new_item(
			product
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
	for visual: MeshInstance3D in item_visuals:
		if is_instance_valid(visual):
			visual.queue_free()

	item_visuals.clear()


func _invalidate_fit_cache() -> void:
	cached_fit_product = null
	cached_fit_position = Vector3.INF
	fit_cache_valid = false


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

	# Empty hands → take the last item from the cart.
	if has_items():
		if multiplayer.is_server():
			_take_item_for_player(player)
		else:
			request_take_item.rpc_id(
				1,
				player.get_path()
			)


@rpc("any_peer", "call_remote", "reliable")
func request_add_item(
	player_path: NodePath,
	product_path: String
	) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var player_node: Node = get_node_or_null(player_path)

	if player_node == null:
		return

	if not player_node is CharacterBody3D:
		return

	var player: CharacterBody3D = player_node as CharacterBody3D

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	_add_item_from_player(player, product_path)


func _add_item_from_player(
	player: CharacterBody3D,
	product_path: String
	) -> void:
	if player == null:
		return

	if product_path.is_empty():
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	if not add_item(product):
		return

	_clear_player_held_item(player)

	_broadcast_cart_state()


@rpc("any_peer", "call_remote", "reliable")
func request_take_item(player_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var player_node: Node = get_node_or_null(player_path)

	if player_node == null:
		return

	if not player_node is CharacterBody3D:
		return

	var player: CharacterBody3D = player_node as CharacterBody3D

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	_take_item_for_player(player)


func _take_item_for_player(player: CharacterBody3D) -> void:
	if player == null:
		return

	if player.held_item != null:
		return

	var product: ProductData = take_last_item()

	if product == null:
		return

	_give_product_to_player(player, product)

	_broadcast_cart_state()
	
	
func _give_product_to_player(
	player: CharacterBody3D,
	product: ProductData
	) -> void:
	if player == null:
		return

	if product == null:
		return

	var player_peer_id: int = player.get_multiplayer_authority()
	var product_path: String = product.resource_path

	if player_peer_id == multiplayer.get_unique_id():
		player.receive_product(product_path)
	else:
		player.receive_product.rpc_id(
			player_peer_id,
			product_path
		)


func _clear_player_held_item(player: CharacterBody3D) -> void:
	if player == null:
		return

	var player_peer_id: int = player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(
			player_peer_id
		)
		

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


@rpc("authority", "call_remote", "reliable")
func sync_cart_state(product_paths: Array[String]) -> void:
	_apply_cart_state(product_paths)


func _apply_cart_state(product_paths: Array[String]) -> void:
	cart_items.clear()

	for path: String in product_paths:
		if path.is_empty():
			continue

		var product: ProductData = load(path) as ProductData

		if product != null:
			cart_items.append(product)

	_rebuild_grid()
