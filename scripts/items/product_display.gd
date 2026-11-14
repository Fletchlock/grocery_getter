@tool
extends Node3D


@export_group("Persistence")
@export var save_id: String = ""


@export_group("Product")
@export var product_data: ProductData
@export var outline_material: Material


@export_group("Product Grid")
@export_range(1, 20, 1) var grid_columns: int = 5
@export_range(1, 20, 1) var grid_rows: int = 2
@export_range(1, 20, 1) var stack_height: int = 1
@export var product_gap: float = 0.02


@export_group("Random Variation")
@export_range(0.0, 0.25, 0.005) var position_variation: float = 0.0
@export_range(0.0, 45.0, 1.0) var rotation_variation: float = 0.0
@export var variation_seed: int = 12345


@export_group("Stock")
@export_range(0, 400, 1) var max_quantity: int = 10
@export_range(0, 400, 1) var quantity: int = 10


@export_group("Product Unlock")
@export var initially_locked: bool = false
@export_range(0.0, 5.0, 0.1) var unlock_rating: float = 1.0

var is_unlocked: bool = true
var _last_preview_locked: bool = false


var product_marker: Marker3D = null
var product_grid: Node3D = null
var mesh_outline: Node3D = null
var collision_shape: CollisionShape3D = null
var shelf_tag: ShelfTag = null

# MultiMeshInstance variables
var product_multimesh: MultiMeshInstance3D = null
var outline_multimesh: MultiMeshInstance3D = null
var _multimesh_layout_key: Array = []

var _last_marker_position: Vector3 = Vector3.INF
var _last_product_data: ProductData = null
var _last_grid_columns: int = -1
var _last_grid_rows: int = -1
var _last_stack_height: int = -1
var _last_product_gap: float = -1.0
var _last_position_variation: float = -1.0
var _last_rotation_variation: float = -1.0
var _last_variation_seed: int = 0
var _last_quantity: int = -1

# Networking
var _last_network_quantity: int = -1


func set_product_unlocked(unlocked: bool) -> void:
	if is_unlocked == unlocked:
		return

	is_unlocked = unlocked

	_update_product_display()
	_update_shelf_tag()


func is_available_for_restock_order() -> bool:
	return is_unlocked and product_data != null


func _ready() -> void:
	_ensure_save_id()
	_find_nodes()

	is_unlocked = not initially_locked

	quantity = clampi(quantity, 0, max_quantity)

	if not Engine.is_editor_hint():
		add_to_group("product_displays")

		# Restore inventory before registering the display.
		_restore_stock_quantity()

	_ensure_unique_collision_shape()
	_update_product_display()
	_update_interaction_zone()
	_update_shelf_tag()
	_last_network_quantity = quantity
	_cache_preview_state()

	if not Engine.is_editor_hint():
		# Apply the saved unlock state.
		ProductUnlockManager.register_display(self)

		# Preserve the restored stock quantity.
		_save_stock_quantity()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		ProductUnlockManager.unregister_display(self)


func _process(_delta: float) -> void:
	_find_nodes()

	if product_marker == null or product_grid == null:
		return

	if Engine.is_editor_hint():
		if _preview_needs_update():
			is_unlocked = not initially_locked

			_update_product_display()
			_update_interaction_zone()
			_update_shelf_tag()
			_cache_preview_state()

		return

	if quantity != _last_network_quantity:
		_last_network_quantity = quantity
		_update_product_display()
		_update_interaction_zone()
		_update_shelf_tag()
		_save_stock_quantity()


@rpc("any_peer", "call_remote", "reliable")
func request_restock_from_box(
	player_path: NodePath,
	_box_product_path: String,
	_box_quantity: int
) -> void:
	if not multiplayer.is_server():
		return

	var player: CharacterBody3D = (
		get_node_or_null(player_path) as CharacterBody3D
	)

	if player == null:
		return

	if player.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return

	_restock_from_box(player)


func _restock_from_box(player: CharacterBody3D) -> void:
	if not multiplayer.is_server():
		return

	if not is_unlocked or product_data == null:
		return

	var product_path: String = player.server_restock_product_path
	var box_quantity: int = player.server_restock_quantity

	if product_path != product_data.resource_path:
		return

	if box_quantity <= 0:
		return

	if quantity + box_quantity > max_quantity:
		return

	# Consume the server-held box before applying its contents.
	player.server_restock_product_path = ""
	player.server_restock_quantity = 0

	quantity += box_quantity

	var player_peer_id: int = player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_restock_box()
	else:
		player.clear_held_restock_box.rpc_id(player_peer_id)


func request_interact(player: CharacterBody3D) -> void:
	if not is_unlocked:
		return
	if product_data == null:
		return

	if player == null:
		return
	
	# Holding a restock box means we are restocking the display.
	if player.held_restock_box != null:
		var box: RestockBox = player.held_restock_box

		if box.product_data != product_data:
			return

		if quantity + box.quantity > max_quantity:
			return

		if multiplayer.is_server():
			_restock_from_box(player)
		else:
			request_restock_from_box.rpc_id(
				1,
				player.get_path(),
				box.product_data.resource_path,
				box.quantity
			)

		return
	
	# Holding an item means we are trying to put it back.
	if player.held_item != null:
		if player.held_item != product_data:
			return

		if quantity >= max_quantity:
			return

		if multiplayer.is_server():
			_return_product(player)
		else:
			request_return_product.rpc_id(
				1,
				player.get_path(),
				product_data.resource_path
			)

		return
	
	# Only take a new product when hands are empty.
	if player.is_holding_equipment():
		return

	if quantity <= 0:
		return

	if multiplayer.is_server():
		_take_product(player)
	else:
		request_take_product.rpc_id(1, player.get_path())


@rpc("any_peer", "call_remote", "reliable")
func request_take_product(player_path: NodePath) -> void:
	if not is_unlocked:
		return
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

	_take_product(player)


func _take_product(player: CharacterBody3D) -> void:
	if not is_unlocked:
		return
	if product_data == null:
		return

	
	if quantity <= 0:
		return

	if player.is_holding_equipment():
		return

	quantity -= 1
	
	var peer_id: int = player.get_multiplayer_authority()
	var active_order: OrderData = OrderManager.get_player_order(peer_id)

	if active_order != null:
		OrderManager.record_order_stock_taken(
			active_order.order_id,
			product_data
		)

	var product_path: String = product_data.resource_path

	var origin: int = player.ItemOrigin.PRODUCT_DISPLAY
	player.held_item_origin = origin
	
	if player.get_multiplayer_authority() == multiplayer.get_unique_id():
		player.receive_product(product_path, origin)
	else:
		player.receive_product.rpc_id(
			player.get_multiplayer_authority(),
			product_path,
			origin
		)


@rpc("any_peer", "call_remote", "reliable")
func request_return_product(
	player_path: NodePath,
	product_path: String
	) -> void:
	if not is_unlocked:
		return
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

	if product_data == null:
		return

	if product_path != product_data.resource_path:
		return

	if quantity >= max_quantity:
		return

	_return_product(player)


func _return_product(player: CharacterBody3D) -> void:
	if not is_unlocked:
		return
	if product_data == null:
		return

	if player == null:
		return

	if quantity >= max_quantity:
		return

	quantity += 1
	var active_order: OrderData = OrderManager.get_player_order(
		player.get_multiplayer_authority()
	)

	if active_order != null:
		OrderManager.record_order_stock_returned(
			active_order.order_id,
			product_data
		)

	player.held_item_origin = player.ItemOrigin.NONE

	var player_peer_id: int = player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(player_peer_id)


func _find_nodes() -> void:
	if product_marker == null:
		product_marker = get_node_or_null("ProductMarker")

	if product_grid == null:
		product_grid = get_node_or_null("ProductGrid")

	if mesh_outline == null:
		mesh_outline = get_node_or_null("Area3D/MeshOutline")

	if collision_shape == null:
		collision_shape = get_node_or_null("Area3D/CollisionShape3D")
	
	if shelf_tag == null:
		shelf_tag = get_node_or_null("ShelfTag") as ShelfTag

func _get_product_mesh() -> Mesh:
	if product_data == null:
		return null

	return product_data.product_mesh


func _preview_needs_update() -> bool:
	if product_marker.position != _last_marker_position:
		return true

	if product_data != _last_product_data:
		return true

	if grid_columns != _last_grid_columns:
		return true

	if grid_rows != _last_grid_rows:
		return true

	if stack_height != _last_stack_height:
		return true

	if not is_equal_approx(product_gap, _last_product_gap):
		return true

	if not is_equal_approx(position_variation, _last_position_variation):
		return true

	if not is_equal_approx(rotation_variation, _last_rotation_variation):
		return true

	if variation_seed != _last_variation_seed:
		return true

	if quantity != _last_quantity:
		return true

	if initially_locked != _last_preview_locked:
		return true

	return false


func _cache_preview_state() -> void:
	if product_marker:
		_last_marker_position = product_marker.position

	_last_product_data = product_data
	_last_grid_columns = grid_columns
	_last_grid_rows = grid_rows
	_last_stack_height = stack_height
	_last_product_gap = product_gap
	_last_position_variation = position_variation
	_last_rotation_variation = rotation_variation
	_last_variation_seed = variation_seed
	_last_quantity = quantity
	_last_preview_locked = initially_locked


func _update_product_display() -> void:
	if product_grid == null or product_marker == null:
		return

	product_grid.position = product_marker.position

	if mesh_outline:
		mesh_outline.position = product_marker.position

	var mesh: Mesh = _get_product_mesh()

	if mesh == null:
		_clear_product_display()
		return

	var layer_capacity: int = grid_columns * grid_rows
	var display_capacity: int = layer_capacity * stack_height
	var instance_capacity: int = mini(max_quantity, display_capacity)

	var layout_key: Array = [
		mesh,
		instance_capacity,
		grid_columns,
		grid_rows,
		stack_height,
		product_gap,
		position_variation,
		rotation_variation,
		variation_seed,
		outline_material,
		mesh_outline
	]

	var needs_rebuild: bool = (
		product_multimesh == null
		or not is_instance_valid(product_multimesh)
		or product_multimesh.multimesh == null
		or _multimesh_layout_key != layout_key
	)

	if not needs_rebuild and mesh_outline != null and outline_material != null:
		needs_rebuild = (
			outline_multimesh == null
			or not is_instance_valid(outline_multimesh)
			or outline_multimesh.multimesh == null
		)

	if needs_rebuild:
		_rebuild_product_multimeshes(
			mesh,
			instance_capacity
		)
		_multimesh_layout_key = layout_key

	var visible_count: int = 0

	if is_unlocked:
		visible_count = mini(quantity, instance_capacity)

	if product_multimesh != null:
		product_multimesh.multimesh.visible_instance_count = visible_count

	if outline_multimesh != null:
		outline_multimesh.multimesh.visible_instance_count = visible_count


func _rebuild_product_multimeshes(
	mesh: Mesh,
	instance_capacity: int
) -> void:
	_clear_product_display()

	var product_mesh_data: MultiMesh = MultiMesh.new()
	product_mesh_data.transform_format = MultiMesh.TRANSFORM_3D
	product_mesh_data.mesh = mesh
	product_mesh_data.instance_count = instance_capacity

	product_multimesh = MultiMeshInstance3D.new()
	product_multimesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	product_multimesh.multimesh = product_mesh_data
	product_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	product_multimesh.set_meta("generated_product", true)

	product_grid.add_child(product_multimesh)

	var outline_mesh_data: MultiMesh = null

	if mesh_outline != null and outline_material != null:
		outline_mesh_data = MultiMesh.new()
		outline_mesh_data.transform_format = MultiMesh.TRANSFORM_3D
		outline_mesh_data.mesh = mesh
		outline_mesh_data.instance_count = instance_capacity

		outline_multimesh = MultiMeshInstance3D.new()
		outline_multimesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		outline_multimesh.multimesh = outline_mesh_data
		outline_multimesh.material_override = outline_material
		outline_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline_multimesh.set_meta("generated_product_outline", true)

		mesh_outline.add_child(outline_multimesh)

	var product_size: Vector3 = mesh.get_aabb().size

	var horizontal_spacing: float = product_size.x + product_gap
	var depth_spacing: float = product_size.z + product_gap
	var stack_spacing: float = product_size.y

	var layer_capacity: int = grid_columns * grid_rows

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = variation_seed

	for product_index: int in instance_capacity:
		var stack_layer: int = floori(float(product_index) / float(layer_capacity))
		var layer_index: int = product_index % layer_capacity

		var column: int = layer_index % grid_columns
		var row: int = floori(float(layer_index) / float(grid_columns))

		var base_position: Vector3 = Vector3(
			column * horizontal_spacing,
			stack_layer * stack_spacing,
			row * depth_spacing
		)

		var variation_position: Vector3 = Vector3(
			rng.randf_range(-position_variation, position_variation),
			0.0,
			rng.randf_range(-position_variation, position_variation)
		)

		var variation_rotation: Vector3 = Vector3(
			deg_to_rad(rng.randf_range(-rotation_variation, rotation_variation)),
			deg_to_rad(rng.randf_range(-rotation_variation, rotation_variation)),
			deg_to_rad(rng.randf_range(-rotation_variation, rotation_variation))
		)

		var product_position: Vector3 = base_position + variation_position

		var product_transform: Transform3D = Transform3D(
			Basis.from_euler(variation_rotation),
			product_position
		)

		product_mesh_data.set_instance_transform(
			product_index,
			product_transform
		)

		if outline_mesh_data != null:
			var outline_transform: Transform3D = product_transform.scaled_local(
				Vector3(1.03, 1.03, 1.03)
			)

			outline_mesh_data.set_instance_transform(
				product_index,
				outline_transform
			)


func _update_shelf_tag() -> void:
	if shelf_tag == null:
		return

	shelf_tag.update_display(
		product_data,
		quantity,
		is_unlocked
	)
	

func _update_interaction_zone() -> void:
	if collision_shape == null or product_marker == null:
		return

	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		return

	var product_mesh: Mesh = _get_product_mesh()

	if product_mesh == null:
		return

	var product_size: Vector3 = product_mesh.get_aabb().size

	var horizontal_spacing: float = product_size.x + product_gap
	var depth_spacing: float = product_size.z + product_gap
	var stack_spacing: float = product_size.y

	var grid_width: float = (
		product_size.x
		+ float(grid_columns - 1) * horizontal_spacing
	)

	var grid_depth: float = (
		product_size.z
		+ float(grid_rows - 1) * depth_spacing
	)

	var grid_height: float = (
		stack_spacing
		* float(stack_height)
	)

	box_shape.size = Vector3(
		grid_width,
		grid_height,
		grid_depth
	)

	var grid_center: Vector3 = Vector3(
		grid_width * 0.5 - product_size.x * 0.5,
		grid_height * 0.5,
		grid_depth * 0.5 - product_size.z * 0.5
	)

	collision_shape.position = product_marker.position + grid_center


func _clear_product_display() -> void:
	if product_grid:
		for child: Node in product_grid.get_children():
			if child.has_meta("generated_product"):
				child.free()

	if mesh_outline:
		for child: Node in mesh_outline.get_children():
			if child.has_meta("generated_product_outline"):
				child.free()

	product_multimesh = null
	outline_multimesh = null
	_multimesh_layout_key.clear()


func _ensure_unique_collision_shape() -> void:
	if collision_shape == null:
		return

	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		box_shape = BoxShape3D.new()
		box_shape.resource_local_to_scene = true
		collision_shape.shape = box_shape

	elif not box_shape.resource_local_to_scene:
		box_shape = box_shape.duplicate() as BoxShape3D
		box_shape.resource_local_to_scene = true
		collision_shape.shape = box_shape


func get_interaction_prompt_for_player(
		player: CharacterBody3D
	) -> String:
	if not is_unlocked:
		return ""
	if player == null:
		return ""

	if product_data == null:
		return ""
	
	# Player is holding a restock box.
	if player.held_restock_box != null:
		var box: RestockBox = player.held_restock_box
		
		if box.product_data != product_data:
			return ""
			
		if quantity + box. quantity > max_quantity:
			return ""
			
		if product_data.display_name.is_empty():
			return "[E] Restock Product"
			
		return "[E] Restock" + product_data.display_name
	
	# Player is holding something.
	if player.held_item != null:
		# Wrong product.
		if player.held_item != product_data:
			return ""

		# Display is already full.
		if quantity >= max_quantity:
			return ""

		if product_data.display_name.is_empty():
			return "[E] Place Item"

		return "[E] Place " + product_data.display_name

	# Only offer a new product when hands are empty.
	if player.is_holding_equipment():
		return ""

	if quantity <= 0:
		return ""

	if product_data.display_name.is_empty():
		return "[E] Take Item"

	return "[E] Take " + product_data.display_name


# === AI Functions ===
func ai_take_product() -> ProductData:
	if not is_unlocked:
		return
	if not multiplayer.is_server():
		return

	if quantity <= 0:
		return

	quantity -= 1
	return product_data


func ai_spill_product() -> bool:
	if not multiplayer.is_server():
		return false

	if not is_unlocked or product_data == null:
		return false

	if quantity <= 0:
		return false

	quantity -= 1

	return true


func _ensure_save_id() -> void:
	if not Engine.is_editor_hint():
		return

	if not is_inside_tree():
		return

	if owner == null:
		return

	if save_id.is_empty():
		save_id = ResourceUID.id_to_text(
			ResourceUID.create_id()
		)

		print("PRODUCT DISPLAY ID GENERATED: ", name, " -> ", save_id)

		return

	# Check for duplicate IDs in the current scene.
	var scene_root: Node = owner

	while scene_root.owner != null:
		scene_root = scene_root.owner

	var displays: Array[Node] = scene_root.find_children(
		"*",
		"",
		true,
		false
	)

	for node: Node in displays:
		if node == self:
			continue

		if node.get_script() != get_script():
			continue

		if node.get("save_id") == save_id:
			push_warning(
				"Duplicate ProductDisplay save_id detected: "
				+ save_id
				+ " on "
				+ str(get_path())
				+ " and "
				+ str(node.get_path())
			)

			return


func _save_stock_quantity() -> void:
	if Engine.is_editor_hint():
		return

	if not multiplayer.is_server():
		return

	if save_id.is_empty():
		push_warning(
			"ProductDisplay missing save_id: " + str(get_path())
		)
		return

	StoreManager.product_quantities[save_id] = quantity


func _restore_stock_quantity() -> void:
	if Engine.is_editor_hint():
		return

	if not multiplayer.is_server():
		return

	if save_id.is_empty():
		return

	if not StoreManager.product_quantities.has(save_id):
		return

	quantity = clampi(
		int(StoreManager.product_quantities[save_id]),
		0,
		max_quantity
	)
