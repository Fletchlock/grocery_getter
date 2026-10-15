extends Node3D


@export var stats_label: Label3D

var _current_shoppers: int = 0
var _total_shoppers: int = 0
var _total_sales: float = 0.0
var _last_purchase: float = 0.0

@export var current_shoppers: int:
	get:
		return _current_shoppers
	set(value):
		_current_shoppers = value
		update_label()

@export var total_shoppers: int:
	get:
		return _total_shoppers
	set(value):
		_total_shoppers = value
		update_label()

@export var total_sales: float:
	get:
		return _total_sales
	set(value):
		_total_sales = value
		update_label()

@export var last_purchase: float:
	get:
		return _last_purchase
	set(value):
		_last_purchase = value
		update_label()
		
func _ready() -> void:
	update_label()


func adjust_store_cash(amount: float) -> void:
	if not multiplayer.is_server():
		return

	total_sales += amount

	print(
		"STORE CASH: Change $",
		snappedf(amount, 0.01),
		" | Balance $",
		snappedf(total_sales, 0.01)
	)
	
	
func record_purchase(purchase_total: float) -> void:
	if not multiplayer.is_server():
		return

	total_shoppers += 1
	last_purchase = purchase_total

	adjust_store_cash(purchase_total)


func record_order(order_total: float) -> void:
	if not multiplayer.is_server():
		return

	last_purchase = order_total

	adjust_store_cash(order_total)
	
func update_label() -> void:
	if stats_label == null:
		return
	
	stats_label.text = (
		"Shoppers in store: "
		+ str(current_shoppers)
		+ "\nTotal shopped: "
		+ str(total_shoppers)
		+ "\nTotal sales: $"
		+ ("%.2f" % total_sales)
		+ "\nLast purchase: $"
		+ ("%.2f" % last_purchase)
	)
	
