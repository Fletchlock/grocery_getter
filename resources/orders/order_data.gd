
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


func initialize() -> void:
	elapsed_time = 0.0
	state = OrderState.WAITING

	base_profit = calculate_total_profit()
	current_profit = base_profit


func calculate_total_profit() -> float:
	var total: float = 0.0

	for item: OrderItem in items:
		if item.product == null:
			continue

		total += item.product.product_price * item.quantity

	return total
