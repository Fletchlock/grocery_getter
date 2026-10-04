@tool
extends CartGrid
class_name CheckoutGrid


func _get_take_item_index() -> int:
	if cart_items.is_empty():
		return -1

	return 0


func take_last_item() -> ProductData:
	if cart_items.is_empty():
		return null

	var product: ProductData = cart_items[0]

	cart_items.remove_at(0)

	if not item_positions.is_empty():
		item_positions.remove_at(0)

	if not item_visuals.is_empty():
		var visual: MeshInstance3D = item_visuals[0]

		if is_instance_valid(visual):
			visual.queue_free()

		item_visuals.remove_at(0)

	_invalidate_fit_cache()
	_update_take_item_outline()

	return product
