
extends Node3D

@export var stats_label: Label3D

var current_shoppers: int = 0:
	set(value):
		current_shoppers = value
		update_label()

var total_shoppers: int:
	get:
		return StoreManager.total_shoppers

var total_sales: float:
	get:
		return StoreManager.total_sales

var store_cash: float:
	get:
		return StoreManager.store_cash

var last_purchase: float:
	get:
		return StoreManager.last_purchase


func _ready() -> void:
	update_label()


func adjust_store_cash(amount: float) -> void:
	if not multiplayer.is_server():
		return

	if amount > 0.0:
		StoreManager.record_sale(amount)
	elif amount < 0.0:
		if not StoreManager.spend_cash(-amount):
			return

	update_label()


func record_purchase(purchase_total: float) -> void:
	if not multiplayer.is_server():
		return

	StoreManager.total_shoppers += 1
	adjust_store_cash(purchase_total)


func record_order(order_total: float) -> void:
	if not multiplayer.is_server():
		return

	adjust_store_cash(order_total)


func update_label() -> void:
	if stats_label == null:
		return

	stats_label.text = (
		"Shoppers in store: %d\n"
		+ "Total shopped: %d\n"
		+ "Total sales: $%.2f\n"
		+ "Store cash: $%.2f\n"
		+ "Last purchase: $%.2f"
	) % [
		current_shoppers,
		total_shoppers,
		total_sales,
		store_cash,
		last_purchase
	]


func _process(_delta: float) -> void:
	update_label()
