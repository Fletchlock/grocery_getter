@tool
extends Node3D


@export_group("Product")
@export var cereal_mesh: Mesh
@export var outline_material: Material


@export_group("Product Grid")
@export_range(1, 20, 1) var grid_columns: int = 5
@export_range(1, 20, 1) var grid_rows: int = 2
@export var horizontal_spacing: float = 0.25
@export var vertical_spacing: float = 0.15


@export_group("Stock")
@export_range(0, 400, 1) var max_quantity: int = 10
@export_range(0, 400, 1) var quantity: int = 10

var product_marker: Marker3D = null
var product_grid: Node3D = null
var mesh_outline: Node3D = null
var collision_shape: CollisionShape3D = null

var _last_marker_position: Vector3 = Vector3.INF
var _last_cereal_mesh: Mesh = null
var _last_grid_columns: int = -1
var _last_grid_rows: int = -1
var _last_horizontal_spacing: float = -1.0
var _last_vertical_spacing: float = -1.0
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

	if cereal_mesh != _last_cereal_mesh:
		return true

	if grid_columns != _last_grid_columns:
		return true

	if grid_rows != _last_grid_rows:
		return true

	if not is_equal_approx(horizontal_spacing, _last_horizontal_spacing):
		return true

	if not is_equal_approx(vertical_spacing, _last_vertical_spacing):
		return true

	if quantity != _last_quantity:
		return true

	return false


func _cache_preview_state() -> void:
	if product_marker:
		_last_marker_position = product_marker.position

	_last_cereal_mesh = cereal_mesh
	_last_grid_columns = grid_columns
	_last_grid_rows = grid_rows
	_last_horizontal_spacing = horizontal_spacing
	_last_vertical_spacing = vertical_spacing
	_last_quantity = quantity
	
func _update_product_display() -> void:
	if product_grid == null or product_marker == null:
		return

	_clear_product_display()

	product_grid.position = product_marker.position

	if mesh_outline:
		mesh_outline.position = product_marker.position

	if cereal_mesh == null:
		return

	var display_capacity: int = grid_columns * grid_rows
	var products_to_display: int = mini(quantity, display_capacity)

	for product_index: int in products_to_display:
		var column: int = product_index % grid_columns
		var row: int = floori(float(product_index) / float(grid_columns))

		var product_position: Vector3 = Vector3(
			column * horizontal_spacing,
			0.0,
			row * vertical_spacing
		)

		_create_product(product_position)
		_create_outline(product_position)


func _create_product(product_position: Vector3) -> void:
	var product_instance: MeshInstance3D = MeshInstance3D.new()

	product_instance.mesh = cereal_mesh
	product_instance.position = product_position
	product_instance.set_meta("generated_product", true)

	product_grid.add_child(product_instance)


func _create_outline(product_position: Vector3) -> void:
	if mesh_outline == null:
		return

	if outline_material == null:
		return

	var outline_instance: MeshInstance3D = MeshInstance3D.new()

	outline_instance.mesh = cereal_mesh
	outline_instance.position = product_position
	outline_instance.scale = Vector3(1.05, 1.05, 1.05)
	outline_instance.material_override = outline_material
	outline_instance.set_meta("generated_product_outline", true)

	mesh_outline.add_child(outline_instance)


func _update_interaction_zone() -> void:
	if collision_shape == null or product_marker == null:
		return

	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		return

	var grid_width: float = float(grid_columns) * horizontal_spacing
	var grid_depth: float = float(grid_rows) * vertical_spacing
	var interaction_height: float = 0.35

	box_shape.size = Vector3(
		grid_width,
		interaction_height,
		grid_depth
	)

	var grid_center: Vector3 = Vector3(
		(grid_width - horizontal_spacing) * 0.5,
		interaction_height * 0.5,
		(grid_depth - vertical_spacing) * 0.5
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
