
extends Node3D
class_name Checkout


@onready var checkout_point: Marker3D = $CheckoutPoint
@onready var waiting_points: Array[Marker3D] = [
	$WaitingPoints/WaitingPoint1,
	$WaitingPoints/WaitingPoint2,
	$WaitingPoints/WaitingPoint3
]

@onready var checkout_grid: CheckoutGrid = $CheckoutGrid
@onready var bag_grid: CartGrid = $BagGrid
@onready var bag_point: Marker3D = $BagPoint


# Customers
var checkout_customer: ShopperAI = null
var waiting_customers: Array[ShopperAI] = []
var unscanned_items: Array[ProductData] = []


func _ready() -> void:
	add_to_group("checkout")


func request_checkout(customer: ShopperAI) -> Marker3D:
	if customer == checkout_customer:
		return checkout_point

	if waiting_customers.has(customer):
		var index: int = waiting_customers.find(customer)
		return waiting_points[index]

	if checkout_customer == null:
		checkout_customer = customer
		return checkout_point

	if waiting_customers.size() >= waiting_points.size():
		return null

	waiting_customers.append(customer)

	return waiting_points[waiting_customers.size() - 1]


# Called when the active shopper reaches CheckoutPoint.
func customer_arrived_at_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return
	
	if customer != checkout_customer:
		return
	
	unscanned_items = customer.purchased_items.duplicate()

	_clear_grid(checkout_grid)

	for product: ProductData in customer.purchased_items:
		if product == null:
			continue

		if not checkout_grid.add_item(product):
			push_warning(
				"CheckoutGrid could not fit product: "
				+ product.display_name
			)

	_sync_grid_to_clients(checkout_grid)


func can_scan_ai_product(product: ProductData) -> bool:
	if not multiplayer.is_server():
		return false

	if checkout_customer == null or product == null:
		return false

	for unscanned_product: ProductData in unscanned_items:
		if unscanned_product.resource_path == product.resource_path:
			return true

	return false


func scan_ai_product(product: ProductData) -> bool:
	if not can_scan_ai_product(product):
		return false

	if not bag_grid.add_item(product):
		return false

	for i: int in range(unscanned_items.size()):
		if unscanned_items[i].resource_path == product.resource_path:
			unscanned_items.remove_at(i)
			break

	_sync_grid_to_clients(bag_grid)

	if unscanned_items.is_empty() and checkout_customer != null:
		checkout_customer.checkout_scanning_completed()

	return true


func _clear_grid(grid: CartGrid) -> void:
	while grid.has_items():
		grid.take_item_at_index(0)


func _sync_grid_to_clients(grid: CartGrid) -> void:
	if not multiplayer.is_server():
		return

	var product_paths: Array[String] = []

	for product: ProductData in grid.cart_items:
		if product == null:
			product_paths.append("")
		else:
			product_paths.append(product.resource_path)

	grid.sync_cart_state.rpc(product_paths)


func customer_finished_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return

	if customer != checkout_customer:
		return

	# The shopper leaves the checkout and walks to the bag point.
	customer.set_navigation_target(bag_point.global_position)
	customer.state = customer.State.BAGGING

	# Clear the previous shopper's items before the next shopper scans.
	_clear_grid(bag_grid)
	_sync_grid_to_clients(bag_grid)

	_clear_grid(checkout_grid)
	_sync_grid_to_clients(checkout_grid)

	unscanned_items.clear()
	checkout_customer = null

	if waiting_customers.is_empty():
		return

	# Promote the first waiting shopper.
	checkout_customer = waiting_customers.pop_front()

	_move_customer(
		checkout_customer,
		checkout_point
	)

	# Move the remaining shoppers forward in the queue.
	for i: int in range(waiting_customers.size()):
		_move_customer(
			waiting_customers[i],
			waiting_points[i]
		)


func _move_customer(
		customer: ShopperAI,
		target_point: Marker3D
	) -> void:
	if not is_instance_valid(customer):
		return

	customer.set_navigation_target(target_point.global_position)

	if target_point == checkout_point:
		customer.state = customer.State.CHECKOUT
	else:
		customer.state = customer.State.CHECKOUT_LINEUP
