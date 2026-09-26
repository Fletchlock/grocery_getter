@tool
extends Node3D


@export_group("Product")
@export var product_mesh: Mesh
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


var product_marker: Marker3D = null
var product_grid: Node3D = null
var mesh_outline: Node3D = null
var collision_shape: CollisionShape3D = null

var _last_marker_position: Vector3 = Vector3.INF
var _last_product_mesh: Mesh = null
var _last_grid_columns: int = -1
var _last_grid_rows: int = -1
var _last_stack_height: int = -1
var _last_product_gap: float = -1.0
var _last_position_variation: float = -1.0
var _last_rotation_variation: float = -1.0
var _last_variation_seed: int = 0
var _last_quantity: int = -1


func _ready() -> void:
	_find_nodes()

	quantity = clampi(quantity, 0, max_quantity)

	_ensure_unique_collision_shape()
	_update_product_display()
	_update_interaction_zone()
	_cache_preview_state()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	_find_nodes()

	if product_marker == null or product_grid == null:
		return

	if _preview_needs_update():
		_update_product_display()
		_update_interaction_zone()
		_cache_preview_state()


func interact() -> void:
	if quantity <= 0:
		return

	quantity -= 1

	_update_product_display()
	_update_interaction_zone()


func _find_nodes() -> void:
	if product_marker == null:
		product_marker = get_node_or_null("ProductMarker")

	if product_grid == null:
		product_grid = get_node_or_null("ProductGrid")

	if mesh_outline == null:
		mesh_outline = get_node_or_null("Area3D/MeshOutline")

	if collision_shape == null:
		collision_shape = get_node_or_null("Area3D/CollisionShape3D")


func _preview_needs_update() -> bool:
	if product_marker.position != _last_marker_position:
		return true

	if product_mesh != _last_product_mesh:
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

	return false


func _cache_preview_state() -> void:
	if product_marker:
		_last_marker_position = product_marker.position

	_last_product_mesh = product_mesh
	_last_grid_columns = grid_columns
	_last_grid_rows = grid_rows
	_last_stack_height = stack_height
	_last_product_gap = product_gap
	_last_position_variation = position_variation
	_last_rotation_variation = rotation_variation
	_last_variation_seed = variation_seed
	_last_quantity = quantity


func _update_product_display() -> void:
	if product_grid == null or product_marker == null:
		return

	_clear_product_display()

	product_grid.position = product_marker.position

	if mesh_outline:
		mesh_outline.position = product_marker.position

	if product_mesh == null:
		return

	var product_size: Vector3 = product_mesh.get_aabb().size

	var horizontal_spacing: float = product_size.x + product_gap
	var depth_spacing: float = product_size.z + product_gap
	var stack_spacing: float = product_size.y

	var layer_capacity: int = grid_columns * grid_rows
	var display_capacity: int = layer_capacity * stack_height
	var products_to_display: int = mini(quantity, display_capacity)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = variation_seed

	for product_index: int in products_to_display:
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

		_create_product(
			product_position,
			variation_rotation
		)

		_create_outline(
			product_position,
			variation_rotation
		)


func _create_product(
	product_position: Vector3,
	product_rotation: Vector3
) -> void:
	var product_instance: MeshInstance3D = MeshInstance3D.new()

	product_instance.mesh = product_mesh
	product_instance.position = product_position
	product_instance.rotation = product_rotation
	product_instance.set_meta("generated_product", true)

	product_grid.add_child(product_instance)


func _create_outline(
	product_position: Vector3,
	product_rotation: Vector3
) -> void:
	if mesh_outline == null:
		return

	if outline_material == null:
		return

	var outline_instance: MeshInstance3D = MeshInstance3D.new()

	outline_instance.mesh = product_mesh
	outline_instance.position = product_position
	outline_instance.rotation = product_rotation
	outline_instance.scale = Vector3(1.04, 1.02, 1.04)
	outline_instance.material_override = outline_material
	outline_instance.set_meta("generated_product_outline", true)

	mesh_outline.add_child(outline_instance)


func _update_interaction_zone() -> void:
	if collision_shape == null or product_marker == null:
		return

	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		return

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


func get_interaction_prompt() -> String:
	if quantity <= 0:
		return ""

	return "[E] Take one"
