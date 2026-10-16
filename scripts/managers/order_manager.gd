extends Node


signal order_generated(order: OrderData)
signal order_updated(order: OrderData)
signal orders_synced

@export_group("Order Generation")
@export var available_products: Array[ProductData] = []
@export var min_products: int = 4
@export var max_products: int = 6
@export var min_items: int = 1
@export var max_items: int = 2

@export_group("Dynamic Order Director")
@export_range(0, 23) var order_start_hour: int = 8
@export_range(0, 23) var order_end_hour: int = 21

@export var max_outstanding_orders: int = 2

@export var order_check_interval: float = 30.0
@export var minimum_order_gap: float = 30.0
@export var completion_recovery: float = 90.0

@export_range(0.0, 1.0, 0.05) var quiet_order_chance: float = 1.00
@export_range(0.0, 1.0, 0.05) var normal_order_chance: float = 0.30
@export_range(0.0, 1.0, 0.05) var rush_order_chance: float = 0.60

@export_group("Order Financial Rules")
@export var acceptance_time_limit: int = 240
@export var completion_bonus: float = 0.20
@export var active_closing_penalty: float = 0.25
@export var unaccepted_closing_penalty: float = 0.50

var orders: Array[OrderData] = []
var next_order_id: int = 1
var order_check_timer: float = 0.0
var time_since_last_order: float = 0.0
var recovery_timer: float = 0.0
var order_director_running: bool = false
var waiting_order_deadlines: Dictionary = {}
var pending_order_penalties: Dictionary = {}
var last_settled_day: int = -1

var timer_sync_accumulator: float = 0.0
const TIMER_SYNC_INTERVAL: float = 0.1


func _ready() -> void:
	DayManager.day_started.connect(_on_day_started)
	DayManager.clock_updated.connect(_on_clock_updated)

func initialize_orders() -> void:
	if not multiplayer.is_server():
		return

	_initialize_orders()


func _initialize_orders() -> void:
	orders.clear()
	waiting_order_deadlines.clear()
	pending_order_penalties.clear()
	
	order_check_timer = 0.0
	time_since_last_order = 0.0
	recovery_timer = 0.0
	order_director_running = true

	_sync_orders()

	print("ORDER DIRECTOR: Initialized")


func _on_day_started(_day: int) -> void:
	if not multiplayer.is_server():
		return

	_initialize_orders()


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	if not multiplayer.is_server():
		return

	if not order_director_running:
		return

	var current_game_minute: int = hour * 60 + minute

	if hour >= DayManager.STORE_CLOSE_HOUR:
		if last_settled_day != day:
			_settle_closing_orders(day)
		return

	_check_waiting_order_expiration(current_game_minute)


func _settle_closing_orders(day: int) -> void:
	if not multiplayer.is_server():
		return

	if last_settled_day == day:
		return

	var total_penalty: float = 0.0

	# Include orders that expired earlier in the day.
	for penalty: float in pending_order_penalties.values():
		total_penalty += penalty

	# Resolve any orders still outstanding at closing.
	for order: OrderData in orders:
		var penalty: float = 0.0

		match order.state:
			OrderData.OrderState.WAITING:
				penalty = (
					_get_order_reorder_cost(order)
					* unaccepted_closing_penalty
				)

			OrderData.OrderState.ACTIVE:
				penalty = (
					_get_order_reorder_cost(order)
					* active_closing_penalty
				)

			_:
				continue

		total_penalty += penalty
		order.state = OrderData.OrderState.CANCELLED

		waiting_order_deadlines.erase(order.order_id)
		order_updated.emit(order)

		print(
			"ORDER CLOSING: Cancelled #",
			order.order_id,
			" | Penalty $",
			snappedf(penalty, 0.01)
		)

	# Only mark settlement complete after processing the orders.
	last_settled_day = day
	pending_order_penalties.clear()

	var stats: Node3D = get_tree().get_first_node_in_group(
		"shopper_stats"
	)

	if stats != null and total_penalty > 0.0:
		stats.adjust_store_cash(-total_penalty)

	_sync_orders()

	print(
		"ORDER CLOSING: Day ",
		day,
		" | Total penalties $",
		snappedf(total_penalty, 0.01)
	)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Preserve existing active-order timers.
	if DayManager.store_open:
		for order: OrderData in orders:
			if order.state != OrderData.OrderState.ACTIVE:
				continue

			_update_order_timer(order, delta)

	# Run the dynamic director.
	if order_director_running and DayManager.clock_running:
		_update_order_director(delta)

	# Preserve existing multiplayer timer synchronization.
	timer_sync_accumulator += delta

	if timer_sync_accumulator >= TIMER_SYNC_INTERVAL:
		timer_sync_accumulator = 0.0
		_sync_orders()


func _update_order_director(delta: float) -> void:
	# Recovery counts down in real time.
	if recovery_timer > 0.0:
		recovery_timer = maxf(recovery_timer - delta, 0.0)

	var hour: int = DayManager.current_hour

	# No new orders outside the generation window.
	if hour < order_start_hour or hour >= order_end_hour:
		order_check_timer = 0.0
		time_since_last_order = 0.0
		return

	order_check_timer += delta
	time_since_last_order += delta

	if order_check_timer < order_check_interval:
		return

	order_check_timer = 0.0

	# Don't generate during recovery.
	if recovery_timer > 0.0:
		return

	# Enforce minimum spacing between orders.
	if time_since_last_order < minimum_order_gap:
		return

	# Don't exceed the outstanding order limit.
	if _get_outstanding_order_count() >= max_outstanding_orders:
		return

	var chance: float = _get_order_arrival_chance(hour)

	if randf() > chance:
		return

	_create_order()
	_sync_orders()

	time_since_last_order = 0.0

	print(
		"ORDER DIRECTOR: Generated order. Outstanding: ",
		_get_outstanding_order_count()
	)


func _get_outstanding_order_count() -> int:
	var count: int = 0

	for order: OrderData in orders:
		if (
			order.state == OrderData.OrderState.WAITING
			or order.state == OrderData.OrderState.ACTIVE
		):
			count += 1

	return count


func _check_waiting_order_expiration(
	current_game_minute: int
) -> void:
	for order: OrderData in orders:
		if order.state != OrderData.OrderState.WAITING:
			continue

		if not waiting_order_deadlines.has(order.order_id):
			continue

		var deadline: int = int(
			waiting_order_deadlines[order.order_id]
		)

		if current_game_minute < deadline:
			continue

		_expire_waiting_order(order)


func _expire_waiting_order(order: OrderData) -> void:
	if not multiplayer.is_server():
		return

	if order.state != OrderData.OrderState.WAITING:
		return

	var reorder_cost: float = _get_order_reorder_cost(order)

	var penalty: float = (
		reorder_cost * unaccepted_closing_penalty
	)

	pending_order_penalties[order.order_id] = penalty

	waiting_order_deadlines.erase(order.order_id)

	order.state = OrderData.OrderState.CANCELLED

	order_updated.emit(order)
	_sync_orders()

	print(
		"ORDER DIRECTOR: Customer cancelled order #",
		order.order_id,
		" | Pending penalty: $",
		snappedf(penalty, 0.01)
	)


func _get_order_reorder_cost(order: OrderData) -> float:
	var total: float = 0.0

	for item: OrderItem in order.items:
		if item.product == null:
			continue

		total += (
			item.product.reorder_cost
			* item.quantity
		)

	return total


func _get_order_arrival_chance(hour: int) -> float:
	if (
		(hour >= 11 and hour < 13)
		or (hour >= 16 and hour < 18)
	):
		return rush_order_chance

	if hour < 10 or hour >= 20:
		return quiet_order_chance

	return normal_order_chance


func _create_order() -> OrderData:
	var order: OrderData = OrderData.new()

	order.order_id = next_order_id
	next_order_id += 1

	var item_count: int = randi_range(
		min_products,
		max_products
	)

	var products: Array[ProductData] = available_products.duplicate()
	products.shuffle()

	item_count = mini(
		item_count,
		products.size()
	)

	for i: int in item_count:
		var item: OrderItem = OrderItem.new()

		item.product = products[i]
		item.quantity = randi_range(
			min_items,
			max_items
		)

		order.items.append(item)

	order.initialize()

	var current_game_minute: int = (
		DayManager.current_hour * 60
		+ DayManager.current_minute
	)

	waiting_order_deadlines[order.order_id] = (
		current_game_minute + acceptance_time_limit
	)

	orders.append(order)

	order_generated.emit(order)

	return order


func get_orders() -> Array[OrderData]:
	return orders


func get_order(order_id: int) -> OrderData:
	for order: OrderData in orders:
		if order.order_id == order_id:
			return order

	return null


func get_player_order(peer_id: int) -> OrderData:
	for order: OrderData in orders:
		if order.accepted_by_peer_id != peer_id:
			continue

		if order.state == OrderData.OrderState.ACTIVE:
			return order

	return null


func get_player_order_any_state(peer_id: int) -> OrderData:
	for order: OrderData in orders:
		if order.accepted_by_peer_id == peer_id:
			return order

	return null


func get_available_order() -> OrderData:
	for order: OrderData in orders:
		if order.state == OrderData.OrderState.WAITING:
			return order

	return null


func accept_order(player: CharacterBody3D) -> void:
	if not multiplayer.is_server():
		return
	
	if not DayManager.store_open:
		return
	
	var peer_id: int = player.get_multiplayer_authority()

	# A player can only own one active order.
	if get_player_order(peer_id) != null:
		return

	for order: OrderData in orders:
		if order.state != OrderData.OrderState.WAITING:
			continue

		order.state = OrderData.OrderState.ACTIVE
		order.accepted_by_peer_id = peer_id
		waiting_order_deadlines.erase(order.order_id)
		
		order_updated.emit(order)
		_sync_orders()

		return


func submit_product(
	player: CharacterBody3D,
	product: ProductData
) -> bool:
	if not multiplayer.is_server():
		return false

	var peer_id: int = player.get_multiplayer_authority()
	var order: OrderData = get_player_order(peer_id)

	if order == null:
		return false

	for item: OrderItem in order.items:
		if item.product != product:
			continue

		if item.is_complete():
			return false

		item.quantity_fulfilled += 1

		order_updated.emit(order)

		if _is_order_complete(order):
			complete_order(order)
		else:
			_sync_orders()

		return true

	return false


func _update_order_timer(
	order: OrderData,
	delta: float
) -> void:
	order.elapsed_time += delta

	if order.elapsed_time <= order.time_limit:
		order.current_profit = order.base_profit
		return

	var late_seconds: float = (
		order.elapsed_time
		- order.time_limit
	)

	var late_loss: float = (
		order.base_profit
		* order.late_loss_per_second
		* late_seconds
	)

	order.current_profit = maxf(
		order.base_profit - late_loss,
		0.0
	)

	if order.current_profit <= 0.0:
		cancel_order(order)


func complete_order(order: OrderData) -> void:
	if not multiplayer.is_server():
		return

	if order.state != OrderData.OrderState.ACTIVE:
		return

	order.state = OrderData.OrderState.COMPLETED

	recovery_timer = completion_recovery
	order_check_timer = 0.0

	var _shopper_stats: Node3D = get_tree().get_first_node_in_group(
		"shopper_stats"
	)

	if _shopper_stats != null:
		var payout: float = order.current_profit * (1.0 + completion_bonus)
		_shopper_stats.record_order(payout)

	order_updated.emit(order)
	_sync_orders()

	print(
		"ORDER DIRECTOR: Order completed. Recovery: ",
		completion_recovery,
		" seconds"
	)


func cancel_order(order: OrderData) -> void:
	if order.state != OrderData.OrderState.ACTIVE:
		return

	order.state = OrderData.OrderState.CANCELLED

	order_updated.emit(order)
	_sync_orders()


func _is_order_complete(order: OrderData) -> bool:
	for item: OrderItem in order.items:
		if not item.is_complete():
			return false

	return true


func _sync_orders() -> void:
	if not multiplayer.is_server():
		return

	var data: Array[Dictionary] = []

	for order: OrderData in orders:
		var order_data: Dictionary = {
			"order_id": order.order_id,
			"state": order.state,
			"accepted_by_peer_id": order.accepted_by_peer_id,
			"elapsed_time": order.elapsed_time,
			"time_limit": order.time_limit,
			"base_profit": order.base_profit,
			"current_profit": order.current_profit,
			"acceptance_deadline": int(
				waiting_order_deadlines.get(order.order_id, -1)
			),
			"items": []
		}

		for item: OrderItem in order.items:
			order_data["items"].append({
				"product_path": item.product.resource_path,
				"quantity": item.quantity,
				"quantity_fulfilled": item.quantity_fulfilled
			})

		data.append(order_data)

	sync_orders.rpc(data)
	orders_synced.emit()


@rpc("authority", "reliable")
func sync_orders(
	data: Array[Dictionary]
) -> void:
	if multiplayer.is_server():
		return

	orders.clear()

	for order_data: Dictionary in data:
		var order: OrderData = OrderData.new()

		order.order_id = order_data["order_id"]
		var deadline: int = int(order_data["acceptance_deadline"])

		if deadline >= 0:
			waiting_order_deadlines[order.order_id] = deadline
		order.state = order_data["state"]
		order.accepted_by_peer_id = (
			order_data["accepted_by_peer_id"]
		)
		order.elapsed_time = order_data["elapsed_time"]
		order.time_limit = order_data["time_limit"]
		order.base_profit = order_data["base_profit"]
		order.current_profit = order_data["current_profit"]

		for item_data: Dictionary in order_data["items"]:
			var item: OrderItem = OrderItem.new()

			var product: ProductData = load(
				item_data["product_path"]
			) as ProductData

			item.product = product
			item.quantity = item_data["quantity"]
			item.quantity_fulfilled = (
				item_data["quantity_fulfilled"]
			)

			order.items.append(item)
		
		orders.append(order)
		order_updated.emit(order)
	
	orders_synced.emit()
