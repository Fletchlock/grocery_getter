@tool
extends CartGrid
class_name CheckoutGrid


func take_last_item() -> ProductData:
	if cart_items.is_empty():
		return null

	return take_item_at_index(0)
