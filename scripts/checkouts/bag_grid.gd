
@tool
extends CartGrid
class_name BagGrid


func _find_position_for_new_item(
	product: ProductData
	) -> Vector3:
	var product_size: Vector3 = _get_product_size(product)
	var bounds: AABB = _get_cart_bounds()

	var scale_factor: float = (
		_get_bag_item_scale(product).x / item_scale.x
	)

	product_size *= scale_factor

	var half_size: Vector3 = product_size * 0.5

	var min_position: Vector3 = bounds.position + half_size
	var max_position: Vector3 = bounds.end - half_size

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(str(cart_items.size()) + product.resource_path)

	return Vector3(
		rng.randf_range(min_position.x, max_position.x),
		rng.randf_range(min_position.y, max_position.y),
		rng.randf_range(min_position.z, max_position.z)
	)


func _create_product_visual(
	product: ProductData,
	target_center: Vector3,
	item_index: int
	) -> MeshInstance3D:
	var visual: MeshInstance3D = super._create_product_visual(
		product,
		target_center,
		item_index
	)

	if visual == null:
		return null

	var new_scale: Vector3 = _get_bag_item_scale(product)
	visual.scale = new_scale

	var mesh_bounds: AABB = product.product_mesh.get_aabb()

	var scaled_position: Vector3 = Vector3(
		mesh_bounds.position.x * new_scale.x,
		mesh_bounds.position.y * new_scale.y,
		mesh_bounds.position.z * new_scale.z
	)

	var scaled_size: Vector3 = Vector3(
		mesh_bounds.size.x * absf(new_scale.x),
		mesh_bounds.size.y * absf(new_scale.y),
		mesh_bounds.size.z * absf(new_scale.z)
	)

	visual.position = (
		target_center
		- scaled_position
		- scaled_size * 0.5
	)

	visual.rotation.y = 0.0

	return visual


func _get_bag_item_scale(product: ProductData) -> Vector3:
	var product_size: Vector3 = _get_product_size(product)
	var bounds: AABB = _get_cart_bounds()

	if product_size.x <= 0.0 or product_size.y <= 0.0 or product_size.z <= 0.0:
		return item_scale

	var scale_factor: float = minf(
		1.0,
		minf(
			bounds.size.x / product_size.x,
			minf(
				bounds.size.y / product_size.y,
				bounds.size.z / product_size.z
			)
		)
	)

	return item_scale * scale_factor


func get_interaction_prompt_for_player(
	_player: CharacterBody3D
) -> String:
	_clear_take_item_outline()
	return ""


func request_interact(_player: CharacterBody3D) -> void:
	return
