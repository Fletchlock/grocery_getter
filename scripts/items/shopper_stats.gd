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
		print(
		"CURRENT SHOPPERS SET: ",
		value,
		" | PEER: ",
		multiplayer.get_unique_id()
	)
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
	
	
func record_purchase(purchase_total: float) -> void:
	if not multiplayer.is_server():
		return
		
	_total_shoppers += 1
	_total_sales += purchase_total
	_last_purchase = purchase_total

	update_label()


func record_order(order_total: float) -> void:
	if not multiplayer.is_server():
		return
		
	_total_sales += order_total
	_last_purchase = order_total	
	
	print(
		"RECORD ORDER: AFTER TOTAL: $",
		_total_sales,
		" | LAST: $",
		_last_purchase
	)
	
	update_label()
	
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
	
