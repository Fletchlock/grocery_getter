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

@export_group("Profit")


@export_group("Timing")
@export var time_limit: float = 0.0 ##Order time limit in seconds. Leave at 0.0 and set using time_per_product.
@export var time_per_product: int = 15 ##Seconds per product. Multiplies the time limit per product.
@export var late_loss_per_second: float = 0.01 ##Percent lost per second that the order is late.

var elapsed_time: float = 0.0
var base_profit: float = 0.0
var current_profit: float
var state: OrderState = OrderState.WAITING
var accepted_by_peer_id: int = 0

func initialize() -> void:
	elapsed_time = 0.0
	state = OrderState.WAITING
	time_limit = items.size() * time_per_product
	base_profit = calculate_total_profit()
	current_profit = base_profit

func calculate_total_profit() -> float:
	var total: float = 0.0

	for item: OrderItem in items:
		total += item.product.product_price * item.quantity

	return total
