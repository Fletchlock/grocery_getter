extends Node3D
class_name  Checkout

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


func _ready() -> void:
	add_to_group("checkout")


# Checkout available? Yes goto CheckoutPoint, No goto available WaitingPoint
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


func customer_finished_checkout() -> void:
	checkout_customer = null

	if waiting_customers.is_empty():
		return

	checkout_customer = waiting_customers.pop_front()

	# Promote the next customer to the checkout.
	_move_customer(
		checkout_customer,
		checkout_point
	)

	# Move the remaining customers forward in the queue.
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
		customer.state = customer.State.CHECKOUT_WAITING
	
