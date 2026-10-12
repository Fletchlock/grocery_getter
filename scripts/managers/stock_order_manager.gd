
extends Node

signal pending_order_updated(pending_orders: Dictionary)

# Product resource path -> quantity requested.
var pending_orders: Dictionary = {}


func set_pending_quantity(
	product_path: String,
	quantity: int
) -> void:
	if not multiplayer.is_server():
		return

	if product_path.is_empty():
		return

	if quantity < 0 or quantity > 400:
		return

	if not ResourceLoader.exists(product_path):
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	if quantity == 0:
		pending_orders.erase(product_path)
	else:
		pending_orders[product_path] = quantity
	
	print("Pending Stock Orders: ", pending_orders)
	
	_sync_pending_orders.rpc(pending_orders)


@rpc("any_peer", "call_remote", "reliable")
func request_set_pending_quantity(
	product_path: String,
	quantity: int
) -> void:
	if not multiplayer.is_server():
		return

	set_pending_quantity(product_path, quantity)


func get_pending_quantity(product_path: String) -> int:
	return int(pending_orders.get(product_path, 0))


@rpc("authority", "call_local", "reliable")
func _sync_pending_orders(data: Dictionary) -> void:
	pending_orders = data.duplicate(true)
	pending_order_updated.emit(pending_orders)
