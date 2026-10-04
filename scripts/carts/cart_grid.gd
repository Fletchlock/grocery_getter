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
	_update_take_item_outline()

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

	_update_take_item_outline()

	var take_index: int = _get_take_item_index()

	if take_index < 0:
		return ""

	var product: ProductData = cart_items[take_index]

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

	var placement: Vector3 = _find_position_for_new_item(product)

	cached_fit_product = product
	cached_fit_position = placement
	fit_cache_valid = true

	return placement != Vector3.INF


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

	# The cart is treated as a series of simple horizontal
	# rows/layers. We only test positions immediately after
	# existing items instead of generating many candidate
	# coordinates and testing every combination.
	#
	# This makes placement substantially cheaper as the cart fills.

	var candidate_positions: Array[Vector3] = []

	# First item.
	if item_positions.is_empty():
		candidate_positions.append(
			Vector3(
				bounds.position.x + product_size.x * 0.5,
				bounds.position.y + product_size.y * 0.5,
				bounds.position.z + product_size.z * 0.5
			)
		)
	else:
		# Try extending each existing row.
		for index: int in range(item_positions.size()):
			var existing_product: ProductData = cart_items[index]

			if existing_product == null:
				continue

			var existing_size: Vector3 = _get_product_size(
				existing_product
			)

			var existing_position: Vector3 = item_positions[index]

			# Continue to the right.
			candidate_positions.append(
				Vector3(
					existing_position.x
					+ existing_size.x * 0.5
					+ horizontal_spacing
					+ product_size.x * 0.5,
					bounds.position.y + product_size.y * 0.5,
					existing_position.z
				)
			)

			# Continue toward the back.
			candidate_positions.append(
				Vector3(
					existing_position.x,
					bounds.position.y + product_size.y * 0.5,
					existing_position.z
					+ existing_size.z * 0.5
					+ depth_spacing
					+ product_size.z * 0.5
				)
			)

			# Stack directly above.
			candidate_positions.append(
				Vector3(
					existing_position.x,
					existing_position.y
					+ existing_size.y * 0.5
					+ vertical_spacing
					+ product_size.y * 0.5,
					existing_position.z
				)
			)

	# Test the small number of generated candidates.
	for candidate: Vector3 in candidate_positions:
		if not _position_fits_bounds(
			candidate,
			product_size,
			bounds
		):
			continue

		if _position_overlaps_items(
			candidate,
			product_size
		):
			continue

		return candidate

	# If the direct candidates failed, find a new row.
	var row_position: Vector3 = _find_new_row_position(
		product_size,
		bounds
	)

	if row_position != Vector3.INF:
		return row_position

	return Vector3.INF


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

	# Determine the next available row from the existing
	# item's Z extents.
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
func request_take_item(player_path: NodePath) -> void:
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

	_take_item_for_player(player)


func _take_item_for_player(
	player: CharacterBody3D
	) -> void:
	if player == null:
		return

	if player.held_item != null:
		return

	var product: ProductData = take_last_item()

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
	# If the incoming state is simply an addition or removal from
	# the end, preserve all existing positions and visuals.
	#
	# This is the common path during normal cart interaction.

	if _matches_existing_prefix(product_paths):
		_apply_incremental_cart_state(product_paths)
		return

	# A completely different state was received.
	# This is primarily used for initial synchronization.
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

	# Remove items from the end if necessary.
	while cart_items.size() > target_count:
		cart_items.pop_back()

		if not item_positions.is_empty():
			item_positions.pop_back()

		if not item_visuals.is_empty():
			var visual: MeshInstance3D = item_visuals.pop_back()

			if is_instance_valid(visual):
				visual.queue_free()

	# Add newly synchronized items.
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
			# This should not normally happen because the server
			# already validated the placement.
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

# outline functions
func _get_take_item_index() -> int:
	if cart_items.is_empty():
		return -1

	return cart_items.size() - 1
	

func _update_take_item_outline() -> void:
	var take_index: int = _get_take_item_index()

	if take_index < 0:
		_clear_take_item_outline()
		return

	if take_index >= item_visuals.size():
		_clear_take_item_outline()
		return

	if outline_material == null:
		_clear_take_item_outline()
		return

	var visual: MeshInstance3D = item_visuals[take_index]

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
