
extends Node

signal finances_updated

# Financial state
var store_cash: float = 0.0
var total_sales: float = 0.0
var total_shoppers: int = 0
var last_purchase: float = 0.0

# Product display identifier -> quantity
var product_quantities: Dictionary = {}

# Physical restock boxes
var restock_boxes: Array[Dictionary] = []


func reset_store() -> void:
	if not multiplayer.is_server():
		return

	store_cash = 0.0
	total_sales = 0.0
	total_shoppers = 0
	last_purchase = 0.0

	product_quantities.clear()
	restock_boxes.clear()


func get_save_data() -> Dictionary:
	return {
		"store_cash": store_cash,
		"total_sales": total_sales,
		"total_shoppers": total_shoppers,
		"last_purchase": last_purchase,
		"product_quantities": product_quantities.duplicate(true),
		"restock_boxes": restock_boxes.duplicate(true)
	}


func load_save_data(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	store_cash = float(data.get("store_cash", 0.0))
	total_sales = float(data.get("total_sales", 0.0))
	total_shoppers = int(data.get("total_shoppers", 0))
	last_purchase = float(data.get("last_purchase", 0.0))

	product_quantities = (
		data.get("product_quantities", {}) as Dictionary
	).duplicate(true)

	restock_boxes.clear()

	for box_data: Dictionary in data.get("restock_boxes", []):
		restock_boxes.append(box_data.duplicate(true))



func record_sale(amount: float) -> void:
	if not multiplayer.is_server():
		return

	if amount <= 0.0:
		return

	store_cash += amount
	total_sales += amount
	last_purchase = amount
	sync_finances()

func spend_cash(amount: float) -> bool:
	if not multiplayer.is_server():
		return false

	if amount <= 0.0:
		return false

	if amount > store_cash:
		return false

	store_cash -= amount
	sync_finances()
	return true

##################
# Signal functions
##################


func sync_finances() -> void:
	if not multiplayer.is_server():
		return

	_receive_finances.rpc(
		store_cash,
		total_sales,
		total_shoppers,
		last_purchase
	)

	finances_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_finances(
	cash: float,
	sales: float,
	shoppers: int,
	purchase: float
) -> void:
	store_cash = cash
	total_sales = sales
	total_shoppers = shoppers
	last_purchase = purchase

	finances_updated.emit()


func request_finances() -> void:
	if multiplayer.is_server():
		return

	_request_finances.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_finances() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	_receive_finances.rpc_id(
		peer_id,
		store_cash,
		total_sales,
		total_shoppers,
		last_purchase
	)
