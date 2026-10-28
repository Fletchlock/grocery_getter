
class_name OrderData
extends Resource


enum OrderState {
	WAITING,
	ACTIVE,
	COMPLETED,
	CANCELLED
}


@export var order_id: int = 0
@export var items: Array[OrderItem] = []

@export_group("Timing")
var time_limit: float = 0.0
@export var late_loss_per_second: float = 0.1


var elapsed_time: float = 0.0
var base_profit: float = 0.0
var current_profit: float = 0.0
var state: OrderState = OrderState.WAITING
var accepted_by_peer_id: int = 0


# New checkout system
# Key: ProductData resource path
# Value: Quantity scanned
var scanned_items: Dictionary = {}

var checkout_started: bool = false
var checkout_result: Dictionary = {}
var validated_profit: float = 0.0
var incorrect_item_count: int = 0


func initialize() -> void:
	elapsed_time = 0.0
	state = OrderState.WAITING

	scanned_items.clear()
	checkout_started = false
	checkout_result.clear()
	validated_profit = 0.0
	incorrect_item_count = 0

	base_profit = calculate_total_profit()
	current_profit = base_profit


func calculate_total_profit() -> float:
	var total: float = 0.0

	for item: OrderItem in items:
		if item.product == null:
			continue

		total += item.product.product_price * item.quantity

	return total


func record_scanned_product(product: ProductData) -> bool:
	if product == null:
		return false

	if state != OrderState.ACTIVE:
		return false

	if not checkout_started:
		return false

	var product_path: String = product.resource_path

	if product_path.is_empty():
		return false

	var current_quantity: int = int(
		scanned_items.get(product_path, 0)
	)

	scanned_items[product_path] = current_quantity + 1

	return true


func validate_checkout() -> Dictionary:
	var results: Dictionary = {}
	var requested_products: Dictionary = {}

	var correct_value: float = 0.0
	var mistakes: int = 0

	# Compare every requested product.
	for item: OrderItem in items:
		if item.product == null:
			continue

		var product_path: String = item.product.resource_path
		var requested: int = item.quantity
		var scanned: int = int(
			scanned_items.get(product_path, 0)
		)

		var correct: int = mini(requested, scanned)
		var missing: int = maxi(requested - scanned, 0)
		var excess: int = maxi(scanned - requested, 0)

		correct_value += (
			float(correct) * item.product.product_price
		)

		mistakes += missing + excess

		requested_products[product_path] = true

		results[product_path] = {
			"requested": requested,
			"scanned": scanned,
			"correct": correct,
			"missing": missing,
			"excess": excess,
			"unordered": false
		}

	# Find products not requested by the customer.
	for product_path: String in scanned_items:
		if requested_products.has(product_path):
			continue

		var scanned: int = int(scanned_items[product_path])

		mistakes += scanned

		results[product_path] = {
			"requested": 0,
			"scanned": scanned,
			"correct": 0,
			"missing": 0,
			"excess": scanned,
			"unordered": true
		}

	validated_profit = correct_value
	incorrect_item_count = mistakes
	checkout_result = results.duplicate(true)

	return checkout_result
