
extends Node


signal order_generated(order: OrderData)
signal order_updated(order: OrderData)
signal orders_synced


@export_group("Order Generation")
@export var available_products: Array[ProductData] = []
@export var min_products: int = 2
@export var max_products: int = 5
@export var min_items: int = 1
@export var max_items: int = 3

@export_group("Order Completion Time")
@export var seconds_per_item: float = 25.0
@export var minimum_completion_time: float = 60.0
@export var time_reduction_per_day: float = 0.03
@export var maximum_time_reduction: float = 0.40

@export_group("Order Financial Rules")
@export var acceptance_time_limit: int = 240
@export var completion_bonus: float = 0.25
@export var active_closing_penalty: float = 0.25
@export var unaccepted_closing_penalty: float = 0.50

@export_group("Dynamic Order Director")
@export_range(0, 23) var order_start_hour: int = 8
@export_range(1, 24) var order_end_hour: int = 21

@export_group("Base Order Traffic")
@export var order_interval_min: float = 60.0
@export var order_interval_max: float = 90.0
@export var minimum_order_gap: float = 20.0
@export var completion_recovery: float = 60.0

@export_group("Day Scaling")
@export var day_growth_rate: float = 0.10
@export var max_day_traffic_multiplier: float = 2.0

@export_group("Player Scaling")
@export var traffic_increase_per_player: float = 0.20
@export var extra_orders_per_player: int = 1

@export_group("Order Capacity")
@export var starting_max_orders: int = 1
@export var extra_orders_every_n_days: int = 3
@export var max_outstanding_orders: int = 10

@export_group("Time Of Day")
@export_range(0, 23) var morning_end_hour: int = 11
@export_range(0, 23) var lunch_end_hour: int = 14
@export_range(0, 23) var afternoon_end_hour: int = 17
@export_range(0, 23) var evening_end_hour: int = 19

@export var morning_multiplier: float = 0.70
@export var lunch_multiplier: float = 1.40
@export var afternoon_multiplier: float = 1.0
@export var evening_multiplier: float = 1.50
@export var closing_multiplier: float = 0.60


var orders: Array[OrderData] = []
var next_order_id: int = 1
var order_spawn_timer: float = 0.0
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

	order_spawn_timer = 0.0
	recovery_timer = 0.0
	order_director_running = true

	set_next_order_timer()

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
				# Let accepted orders continue after closing.
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

	# Active orders continue running after store closing.
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
	if recovery_timer > 0.0:
		recovery_timer = maxf(recovery_timer - delta, 0.0)

	if not DayManager.store_open:
		return

	var hour: int = DayManager.current_hour

	if hour < order_start_hour or hour >= order_end_hour:
		return

	if recovery_timer > 0.0:
		return

	if _get_outstanding_order_count() >= get_current_max_orders():
		return

	order_spawn_timer -= delta

	if order_spawn_timer > 0.0:
		return

	if available_products.is_empty():
		set_next_order_timer()
		return

	_create_order()
	_sync_orders()

	set_next_order_timer()

	print(
		"ORDER DIRECTOR: Generated order. Outstanding: ",
		_get_outstanding_order_count(),
		"/",
		get_current_max_orders()
	)


func get_player_count() -> int:
	return clampi(multiplayer.get_peers().size() + 1, 1, 4)


func get_day_traffic_multiplier() -> float:
	var days_elapsed: int = maxi(0, DayManager.current_day - 1)

	return minf(
		1.0 + day_growth_rate * float(days_elapsed),
		max_day_traffic_multiplier
	)


func get_player_traffic_multiplier() -> float:
	var additional_players: int = get_player_count() - 1

	return 1.0 + float(additional_players) * traffic_increase_per_player


func get_time_of_day_multiplier() -> float:
	var hour: int = DayManager.current_hour

	if hour < morning_end_hour:
		return morning_multiplier

	if hour < lunch_end_hour:
		return lunch_multiplier

	if hour < afternoon_end_hour:
		return afternoon_multiplier

	if hour < evening_end_hour:
		return evening_multiplier

	return closing_multiplier


func get_order_traffic_multiplier() -> float:
	return maxf(
		0.01,
		get_day_traffic_multiplier()
		* get_player_traffic_multiplier()
		* get_time_of_day_multiplier()
		* ReputationManager.get_traffic_multiplier()
	)


func get_current_max_orders() -> int:
	var days_elapsed: int = maxi(0, DayManager.current_day - 1)

	var day_bonus: int = 0

	if extra_orders_every_n_days > 0:
		day_bonus = floori(
			float(days_elapsed) / float(extra_orders_every_n_days)
		)

	var player_bonus: int = (
		(get_player_count() - 1) * extra_orders_per_player
	)

	return clampi(
		starting_max_orders + day_bonus + player_bonus,
		1,
		maxi(1, max_outstanding_orders)
	)


func set_next_order_timer() -> void:
	var multiplier: float = get_order_traffic_multiplier()

	var minimum: float = maxf(
		minimum_order_gap,
		order_interval_min / multiplier
	)

	var maximum: float = maxf(
		minimum,
		order_interval_max / multiplier
	)

	order_spawn_timer = randf_range(minimum, maximum)


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
	order.time_limit = _calculate_order_time_limit(order)

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


func _calculate_order_time_limit(order: OrderData) -> float:
	var total_items: int = 0

	for item: OrderItem in order.items:
		total_items += item.quantity

	var days_elapsed: int = maxi(
		0,
		DayManager.current_day - 1
	)

	var reduction: float = clampf(
		float(days_elapsed) * time_reduction_per_day,
		0.0,
		maximum_time_reduction
	)

	var base_time: float = (
		float(total_items) * seconds_per_item
	)

	return maxf(
		minimum_completion_time,
		base_time * (1.0 - reduction)
	)


func complete_order(order: OrderData) -> void:
	if not multiplayer.is_server():
		return

	if order.state != OrderData.OrderState.ACTIVE:
		return

	order.state = OrderData.OrderState.COMPLETED

	recovery_timer = completion_recovery

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
	waiting_order_deadlines.clear()

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
