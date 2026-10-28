@tool
extends Node3D
class_name CartGrid

signal cart_contents_changed(cart_grid: CartGrid)

# -------------------------------------------------------------------
# Inspector settings
# -------------------------------------------------------------------
@export_group("Cart Capacity")
@export_range(1, 100, 1) var max_items: int = 20

@export_group("Spacing")
@export var horizontal_spacing: float = 0.01
@export var vertical_spacing: float = 0.01
@export var depth_spacing: float = 0.01

@export_group("Display")
@export var item_scale: Vector3 = Vector3.ONE
@export_range(0.0, 15.0, 0.5) var rotation_variation_degrees: float = 3.0

@export_group("Auto Resize")
@export var allow_item_shrinking: bool = true
@export_range(0.25, 1.0, 0.05) var minimum_item_scale: float = 0.6
@export_range(0.01, 0.25, 0.01) var shrink_step: float = 0.05
@export_range(0.0, 0.3, 0.01) var allowed_overlap: float = 0.12

@export_group("Interaction Area")
@export var interaction_top_padding: float = 0.2
@export var item_target_distance: float = 8.0

@export_group("Outline")
@export var outline_material: Material

@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_collision: CollisionShape3D = $InteractionArea/CollisionShape3D

var cart_items: Array[ProductData] = []
var item_positions: Array[Vector3] = []
var item_scales: Array[float] = []
var item_visuals: Array[MeshInstance3D] = []

var cart_outline: MeshInstance3D = null
var outlined_visual: MeshInstance3D = null
var order_owner_peer_id: int = 0

var cached_fit_product: ProductData = null
var cached_fit_position: Vector3 = Vector3.INF
var cached_fit_scale: float = 1.0
var fit_cache_valid: bool = false
var _candidate_scale: float = 1.0


# -------------------------------------------------------------------
# Initialization and initial multiplayer state
# -------------------------------------------------------------------
func _ready() -> void:
	add_to_group("cart_grid")
	_rebuild_grid()
	if not Engine.is_editor_hint() and not multiplayer.is_server():
		call_deferred("_request_cart_state")


func _request_cart_state() -> void:
	if not multiplayer.is_server():
		request_cart_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_cart_state() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var paths: Array[String] = _get_product_paths()
	sync_cart_state.rpc_id(peer_id, paths)


# -------------------------------------------------------------------
# Cart contents and capacity
# -------------------------------------------------------------------
func add_item(product: ProductData) -> bool:
	if product == null or is_full():
		return false

	var placement: Vector3 = Vector3.INF
	var scale_factor: float = 1.0
	if fit_cache_valid and cached_fit_product == product:
		placement = cached_fit_position
		scale_factor = cached_fit_scale
	else:
		placement = _find_position_for_new_item(product)
		scale_factor = _candidate_scale

	if placement == Vector3.INF:
		return false

	cart_items.append(product)
	item_positions.append(placement)
	item_scales.append(scale_factor)
	_create_and_add_visual(product, placement, item_visuals.size())
	_invalidate_fit_cache()
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
	if item_index < item_scales.size():
		item_scales.remove_at(item_index)
	if item_index < item_visuals.size():
		var visual: MeshInstance3D = item_visuals[item_index]
		item_visuals.remove_at(item_index)
		if is_instance_valid(visual):
			visual.queue_free()

	if cart_items.is_empty():
		order_owner_peer_id = 0
	_clear_take_item_outline()
	_invalidate_fit_cache()
	return product


func has_items() -> bool:
	return not cart_items.is_empty()


func get_item_count() -> int:
	return cart_items.size()


func get_last_item() -> ProductData:
	if cart_items.is_empty():
		return null
	return cart_items.back()


func is_full() -> bool:
	return cart_items.size() >= max_items


func _can_fit_product(product: ProductData) -> bool:
	if product == null or is_full():
		return false
	var placement: Vector3 = _find_position_for_new_item(product)
	cached_fit_product = product
	cached_fit_position = placement
	cached_fit_scale = _candidate_scale
	fit_cache_valid = true
	return placement != Vector3.INF


func _invalidate_fit_cache() -> void:
	cached_fit_product = null
	cached_fit_position = Vector3.INF
	cached_fit_scale = 1.0
	fit_cache_valid = false


# -------------------------------------------------------------------
# Placement: full size, controlled overlap, then progressive shrink
# -------------------------------------------------------------------
func _find_position_for_new_item(product: ProductData) -> Vector3:
	_candidate_scale = 1.0
	if product == null:
		return Vector3.INF

	var base_size: Vector3 = _get_product_size(product)
	if base_size.x <= 0.0 or base_size.y <= 0.0 or base_size.z <= 0.0:
		return Vector3.INF

	var bounds: AABB = _get_cart_bounds()
	var minimum: float = clampf(minimum_item_scale, 0.25, 1.0)
	var step: float = maxf(shrink_step, 0.01)
	var scale_factor: float = 1.0

	while true:
		var product_size: Vector3 = base_size * scale_factor
		# Prefer strict placement first; overlap is only a fallback.
		var placement: Vector3 = _find_position_at_size(product_size, bounds, 0.0)
		if placement == Vector3.INF and allowed_overlap > 0.0:
			placement = _find_position_at_size(product_size, bounds, allowed_overlap)
		if placement != Vector3.INF:
			_candidate_scale = scale_factor
			return placement

		if not allow_item_shrinking or scale_factor <= minimum + 0.0001:
			break
		scale_factor = maxf(minimum, scale_factor - step)

	return Vector3.INF


func _find_position_at_size(product_size: Vector3, bounds: AABB, overlap: float) -> Vector3:
	if not _product_can_fit_inside_cart(product_size, bounds):
		return Vector3.INF

	var bottom_y: float = bounds.position.y + product_size.y * 0.5
	if item_positions.is_empty():
		return Vector3(
			bounds.position.x + product_size.x * 0.5,
			bottom_y,
			bounds.position.z + product_size.z * 0.5
		)

	# Try beside existing items on the basket floor.
	for index: int in range(item_positions.size()):
		if index >= cart_items.size() or cart_items[index] == null:
			continue
		var existing_size: Vector3 = _get_placed_item_size(index)
		var existing_position: Vector3 = item_positions[index]
		var dx: float = (existing_size.x + product_size.x) * 0.5 * (1.0 - overlap) + horizontal_spacing
		var dz: float = (existing_size.z + product_size.z) * 0.5 * (1.0 - overlap) + depth_spacing
		var candidates: Array[Vector3] = [
			Vector3(existing_position.x + dx, bottom_y, existing_position.z),
			Vector3(existing_position.x - dx, bottom_y, existing_position.z),
			Vector3(existing_position.x, bottom_y, existing_position.z + dz),
			Vector3(existing_position.x, bottom_y, existing_position.z - dz)
		]
		for candidate: Vector3 in candidates:
			if _position_fits_bounds(candidate, product_size, bounds) and not _position_overlaps_items(candidate, product_size, overlap):
				return candidate

	# Scan gaps on the bottom before building a stack.
	var scan_step: float = 0.04
	var x: float = bounds.position.x + product_size.x * 0.5
	var max_x: float = bounds.end.x - product_size.x * 0.5
	var max_z: float = bounds.end.z - product_size.z * 0.5
	while x <= max_x + 0.0001:
		var z: float = bounds.position.z + product_size.z * 0.5
		while z <= max_z + 0.0001:
			var candidate: Vector3 = Vector3(x, bottom_y, z)
			if not _position_overlaps_items(candidate, product_size, overlap):
				return candidate
			z += scan_step
		x += scan_step

	# Stack only when floor placement is unavailable.
	for index: int in range(item_positions.size()):
		if index >= cart_items.size() or cart_items[index] == null:
			continue
		var existing_size: Vector3 = _get_placed_item_size(index)
		var existing_position: Vector3 = item_positions[index]
		var candidate: Vector3 = Vector3(
			existing_position.x,
			existing_position.y + existing_size.y * 0.5 + vertical_spacing + product_size.y * 0.5 * (1.0 - overlap),
			existing_position.z
		)
		if _position_fits_bounds(candidate, product_size, bounds) and not _position_overlaps_items(candidate, product_size, overlap):
			return candidate

	return Vector3.INF


func _get_placed_item_size(index: int) -> Vector3:
	if index < 0 or index >= cart_items.size() or cart_items[index] == null:
		return Vector3.ZERO
	var factor: float = item_scales[index] if index < item_scales.size() else 1.0
	return _get_product_size(cart_items[index]) * factor


func _product_can_fit_inside_cart(product_size: Vector3, bounds: AABB) -> bool:
	return product_size.x <= bounds.size.x and product_size.y <= bounds.size.y and product_size.z <= bounds.size.z


func _position_fits_bounds(i_position: Vector3, size: Vector3, bounds: AABB) -> bool:
	var minimum: Vector3 = i_position - size * 0.5
	var maximum: Vector3 = i_position + size * 0.5
	return minimum.x >= bounds.position.x - 0.0001 and maximum.x <= bounds.end.x + 0.0001 \
		and minimum.y >= bounds.position.y - 0.0001 and maximum.y <= bounds.end.y + 0.0001 \
		and minimum.z >= bounds.position.z - 0.0001 and maximum.z <= bounds.end.z + 0.0001


func _position_overlaps_items(i_position: Vector3, size: Vector3, overlap: float = 0.0) -> bool:
	for index: int in range(item_positions.size()):
		var existing_size: Vector3 = _get_placed_item_size(index)
		if existing_size == Vector3.ZERO:
			continue
		var delta: Vector3 = i_position - item_positions[index]
		var limits: Vector3 = (size + existing_size) * 0.5 * (1.0 - overlap)
		if absf(delta.x) < limits.x and absf(delta.y) < limits.y and absf(delta.z) < limits.z:
			return true
	return false


# -------------------------------------------------------------------
# Cart and product bounds
# -------------------------------------------------------------------
func _get_cart_bounds() -> AABB:
	if interaction_collision == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var shape: BoxShape3D = interaction_collision.shape as BoxShape3D
	if shape == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return AABB(interaction_collision.position - shape.size * 0.5, shape.size)


func _get_product_size(product: ProductData) -> Vector3:
	return _get_product_bounds(product).size


func _get_product_bounds(product: ProductData) -> AABB:
	if product == null or product.product_mesh == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var mesh_bounds: AABB = product.product_mesh.get_aabb()
	var i_position: Vector3 = mesh_bounds.position * item_scale
	var size: Vector3 = mesh_bounds.size * item_scale.abs()
	return AABB(i_position, size)


# -------------------------------------------------------------------
# Visuals and per-item scales
# -------------------------------------------------------------------
func _create_and_add_visual(product: ProductData, target_center: Vector3, item_index: int) -> void:
	var visual: MeshInstance3D = _create_product_visual(product, target_center, item_index)
	if visual == null:
		return
	add_child(visual)
	item_visuals.append(visual)


func _create_product_visual(product: ProductData, target_center: Vector3, item_index: int) -> MeshInstance3D:
	if product == null or product.product_mesh == null:
		return null
	var factor: float = item_scales[item_index] if item_index < item_scales.size() else 1.0
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = product.product_mesh
	visual.scale = item_scale * factor
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh_bounds: AABB = product.product_mesh.get_aabb()
	var scaled_position: Vector3 = mesh_bounds.position * visual.scale
	var scaled_size: Vector3 = mesh_bounds.size * visual.scale.abs()
	visual.position = target_center - scaled_position - scaled_size * 0.5
	var rotation_seed: float = float(item_index) * 37.0 + target_center.x * 13.0 + target_center.z * 17.0
	var normalized: float = fmod(absf(rotation_seed), 100.0) / 100.0
	visual.rotation.y = (normalized * 2.0 - 1.0) * deg_to_rad(rotation_variation_degrees)
	return visual


func _clear_visuals() -> void:
	_clear_take_item_outline()
	for visual: MeshInstance3D in item_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	item_visuals.clear()


# -------------------------------------------------------------------
# Item targeting and interaction prompts
# -------------------------------------------------------------------
func get_interaction_prompt_for_player(player: CharacterBody3D) -> String:
	if player == null:
		_clear_take_item_outline()
		return ""
	if player.held_item != null:
		_clear_take_item_outline()
		if not _can_fit_product(player.held_item):
			return ""
		if player.held_item.display_name.is_empty():
			return "[E] Place Item"
		return "[E] Place " + player.held_item.display_name
	if cart_items.is_empty():
		_clear_take_item_outline()
		return ""
	var index: int = _get_take_item_index(player)
	if index < 0:
		_clear_take_item_outline()
		return ""
	_update_take_item_outline(index)
	var product: ProductData = cart_items[index]
	if product == null or product.display_name.is_empty():
		return "[E] Take Item"
	return "[E] Take " + product.display_name


func get_interaction_prompt_position(collision_shape: CollisionShape3D) -> Vector3:
	if is_instance_valid(outlined_visual):
		var index: int = item_visuals.find(outlined_visual)
		var height: float = _get_placed_item_size(index).y if index >= 0 else 0.0
		return outlined_visual.global_position + Vector3.UP * (height * 0.5 + interaction_top_padding)
	var shape: BoxShape3D = collision_shape.shape as BoxShape3D
	if shape == null:
		return collision_shape.global_position
	return collision_shape.global_position + Vector3.UP * (shape.size.y * 0.5 + interaction_top_padding)


func _get_take_item_index(player: CharacterBody3D) -> int:
	if player == null or cart_items.is_empty():
		return -1
	var camera: Camera3D = player.get_viewport().get_camera_3d()
	if camera == null:
		return -1
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z
	var closest: float = item_target_distance
	var chosen: int = -1
	for index: int in range(mini(cart_items.size(), item_visuals.size())):
		var visual: MeshInstance3D = item_visuals[index]
		if not is_instance_valid(visual) or visual.mesh == null:
			continue
		var distance: float = _get_ray_mesh_distance(origin, direction, visual)
		if distance >= 0.0 and distance < closest:
			closest = distance
			chosen = index
	return chosen


func _get_ray_mesh_distance(origin: Vector3, direction: Vector3, visual: MeshInstance3D) -> float:
	if visual == null or visual.mesh == null:
		return -1.0
	var inverse: Transform3D = visual.global_transform.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	if local_direction.length_squared() <= 0.000001:
		return -1.0
	local_direction = local_direction.normalized()
	var distance: float = _ray_aabb_distance(local_origin, local_direction, visual.mesh.get_aabb())
	if distance < 0.0:
		return -1.0
	return origin.distance_to(visual.global_transform * (local_origin + local_direction * distance))


func _ray_aabb_distance(origin: Vector3, direction: Vector3, bounds: AABB) -> float:
	var t_min: float = 0.0
	var t_max: float = INF
	for axis: int in range(3):
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]:
				return -1.0
			continue
		var t1: float = (bounds.position[axis] - origin[axis]) / direction[axis]
		var t2: float = (bounds.end[axis] - origin[axis]) / direction[axis]
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
# Multiplayer interaction requests (server authoritative)
# -------------------------------------------------------------------
func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return
	if player.held_item != null:
		var path: String = player.held_item.resource_path
		if multiplayer.is_server():
			_add_item_from_player(player, path)
		else:
			request_add_item.rpc_id(1, player.get_path(), path)
		return
	if has_items():
		var index: int = _get_take_item_index(player)
		if index < 0:
			return
		if multiplayer.is_server():
			_take_item_for_player(player, index)
		else:
			request_take_item.rpc_id(1, player.get_path(), index)


@rpc("any_peer", "call_remote", "reliable")
func request_add_item(player_path: NodePath, product_path: String) -> void:
	if not multiplayer.is_server():
		return
	var player: CharacterBody3D = get_node_or_null(player_path) as CharacterBody3D
	if player == null or player.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	_add_item_from_player(player, product_path)


func _add_item_from_player(player: CharacterBody3D, product_path: String) -> void:
	if player == null or product_path.is_empty():
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	var peer_id: int = player.get_multiplayer_authority()
	var player_order: OrderData = OrderManager.get_player_order(peer_id)

	# Keep carts assigned to an active order protected
	# from other players.
	if order_owner_peer_id != 0:
		var owner_order: OrderData = OrderManager.get_player_order(
			order_owner_peer_id
		)

		if owner_order != null and peer_id != order_owner_peer_id:
			return

		# Release ownership from an inactive order.
		if owner_order == null:
			order_owner_peer_id = 0

	# Any product can now be placed into the cart.
	# No order-list or quantity validation.
	if not add_item(product):
		return

	# Assign the cart when an order picker first uses it.
	if order_owner_peer_id == 0 and player_order != null:
		order_owner_peer_id = peer_id

	_clear_player_held_item(player)
	_broadcast_cart_state(player)


@rpc("any_peer", "call_remote", "reliable")
func request_take_item(player_path: NodePath, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var player: CharacterBody3D = get_node_or_null(player_path) as CharacterBody3D
	if player == null or player.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	_take_item_for_player(player, item_index)


func _take_item_for_player(player: CharacterBody3D, item_index: int) -> void:
	if player == null or player.held_item != null:
		return
	var product: ProductData = take_item_at_index(item_index)
	if product == null:
		return
	_give_product_to_player(player, product)
	_broadcast_cart_state(player)


func _give_product_to_player(player: CharacterBody3D, product: ProductData) -> void:
	if player == null or product == null:
		return
	var peer_id: int = player.get_multiplayer_authority()
	var origin: int = player.ItemOrigin.CART_GRID
	if self is CheckoutGrid:
		origin = player.ItemOrigin.CHECKOUT_GRID
	player.held_item_origin = origin
	if peer_id == multiplayer.get_unique_id():
		player.receive_product(product.resource_path, origin)
	else:
		player.receive_product.rpc_id(peer_id, product.resource_path, origin)


func _clear_player_held_item(player: CharacterBody3D) -> void:
	if player == null:
		return
	player.held_item_origin = player.ItemOrigin.NONE
	var peer_id: int = player.get_multiplayer_authority()
	if peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(peer_id)


# -------------------------------------------------------------------
# Multiplayer state synchronization and deterministic rebuilding
# -------------------------------------------------------------------
func _get_product_paths() -> Array[String]:
	var paths: Array[String] = []
	for product: ProductData in cart_items:
		paths.append(product.resource_path if product != null else "")
	return paths


func _broadcast_cart_state(player: CharacterBody3D) -> void:
	if not multiplayer.is_server():
		return
	var paths: Array[String] = _get_product_paths()
	_apply_cart_state(paths)
	sync_cart_state.rpc(paths)
	if player.get_multiplayer_authority() == multiplayer.get_unique_id():
		cart_contents_changed.emit(self)
	else:
		notify_cart_changed.rpc_id(player.get_multiplayer_authority())


@rpc("authority", "call_remote", "reliable")
func sync_cart_state(product_paths: Array[String]) -> void:
	_apply_cart_state(product_paths)


@rpc("authority", "call_remote", "reliable")
func notify_cart_changed() -> void:
	cart_contents_changed.emit(self)


func _apply_cart_state(product_paths: Array[String]) -> void:
	if _matches_existing_prefix(product_paths):
		_apply_incremental_cart_state(product_paths)
	else:
		_rebuild_from_paths(product_paths)


func _matches_existing_prefix(product_paths: Array[String]) -> bool:
	var shared: int = mini(product_paths.size(), cart_items.size())
	for index: int in range(shared):
		var product: ProductData = cart_items[index]
		if product == null:
			if not product_paths[index].is_empty():
				return false
		elif product.resource_path != product_paths[index]:
			return false
	return true


func _apply_incremental_cart_state(product_paths: Array[String]) -> void:
	while cart_items.size() > product_paths.size():
		cart_items.pop_back()
		if not item_positions.is_empty():
			item_positions.pop_back()
		if not item_scales.is_empty():
			item_scales.pop_back()
		if not item_visuals.is_empty():
			var visual: MeshInstance3D = item_visuals.pop_back()
			if is_instance_valid(visual):
				visual.queue_free()

	while cart_items.size() < product_paths.size():
		var index: int = cart_items.size()
		var path: String = product_paths[index]
		var product: ProductData = load(path) as ProductData if not path.is_empty() else null
		if product == null:
			_rebuild_from_paths(product_paths)
			return
		var placement: Vector3 = _find_position_for_new_item(product)
		if placement == Vector3.INF:
			_rebuild_from_paths(product_paths)
			return
		cart_items.append(product)
		item_positions.append(placement)
		item_scales.append(_candidate_scale)
		_create_and_add_visual(product, placement, item_visuals.size())
	_invalidate_fit_cache()


func _rebuild_from_paths(product_paths: Array[String]) -> void:
	_clear_visuals()
	cart_items.clear()
	item_positions.clear()
	item_scales.clear()
	for path: String in product_paths:
		if path.is_empty():
			continue
		var product: ProductData = load(path) as ProductData
		if product != null:
			cart_items.append(product)
	_rebuild_grid()


func _rebuild_grid() -> void:
	_clear_visuals()
	var products: Array[ProductData] = cart_items.duplicate()
	cart_items.clear()
	item_positions.clear()
	item_scales.clear()
	for product: ProductData in products:
		if product == null:
			continue
		var placement: Vector3 = _find_position_for_new_item(product)
		if placement == Vector3.INF:
			continue
		cart_items.append(product)
		item_positions.append(placement)
		item_scales.append(_candidate_scale)
		_create_and_add_visual(product, placement, item_visuals.size())
	_invalidate_fit_cache()


# -------------------------------------------------------------------
# Outline follows each item's actual visual transform and scale
# -------------------------------------------------------------------
func _update_take_item_outline(item_index: int) -> void:
	if item_index < 0 or item_index >= item_visuals.size() or outline_material == null:
		_clear_take_item_outline()
		return
	var visual: MeshInstance3D = item_visuals[item_index]
	if not is_instance_valid(visual) or visual.mesh == null:
		_clear_take_item_outline()
		return
	if outlined_visual == visual and is_instance_valid(cart_outline):
		return
	_clear_take_item_outline()
	cart_outline = MeshInstance3D.new()
	cart_outline.mesh = visual.mesh
	cart_outline.position = visual.position
	cart_outline.rotation = visual.rotation
	cart_outline.scale = visual.scale * Vector3(1.04, 1.02, 1.04)
	cart_outline.material_override = outline_material
	cart_outline.set_meta("generated_cart_outline", true)
	visual.get_parent().add_child(cart_outline)
	outlined_visual = visual


func _clear_take_item_outline() -> void:
	if is_instance_valid(cart_outline):
		cart_outline.queue_free()
	cart_outline = null
	outlined_visual = null
