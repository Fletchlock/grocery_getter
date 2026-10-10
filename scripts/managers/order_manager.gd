extends Node


signal order_generated(order: OrderData)
signal order_updated(order: OrderData)


@export_group("Order Generation")
@export var available_products: Array[ProductData] = []
@export var min_products: int = 4
@export var max_products: int = 6
@export var min_items: int = 1
@export var max_items: int = 2
@export var next_order_delay: float = 30.0


var orders: Array[OrderData] = []
var next_order_id: int = 1
var shopper_stats: Node3D

var timer_sync_accumulator: float = 0.0

const TIMER_SYNC_INTERVAL: float = 0.1


func _ready() -> void:
	#shopper_stats = get_tree().get_first_node_in_group("shopper_stats")
	pass

func initialize_orders() -> void:
	if not multiplayer.is_server():
		return

	_initialize_orders()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if DayManager.store_open:
		for order: OrderData in orders:
			if order.state != OrderData.OrderState.ACTIVE:
				continue

			_update_order_timer(order, delta)



	_sync_completed_orders()

	timer_sync_accumulator += delta

	if timer_sync_accumulator >= TIMER_SYNC_INTERVAL:
		timer_sync_accumulator = 0.0
		_sync_orders()


func _initialize_orders() -> void:
	orders.clear()

	var player_count: int = LobbyManager.get_players().size()

	print("ORDER MANAGER: Initializing orders")
	print("ORDER MANAGER: Lobby players = ", player_count)

	for i: int in player_count:
		var order: OrderData = _create_order()
		print("ORDER MANAGER: Created order #", order.order_id)

	_sync_orders()

	print("ORDER MANAGER: Total orders = ", orders.size())


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
	if order.state != OrderData.OrderState.ACTIVE:
		return

	order.state = OrderData.OrderState.COMPLETED
	
	var _shopper_stats: Node3D = get_tree().get_first_node_in_group("shopper_stats")
	
	if _shopper_stats != null:
		_shopper_stats.record_order(
			order.current_profit
		)

	order_updated.emit(order)
	_sync_orders()


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


func _sync_completed_orders() -> void:
	var needs_sync: bool = false

	for order: OrderData in orders:
		if (
			order.state != OrderData.OrderState.COMPLETED
			and order.state != OrderData.OrderState.CANCELLED
		):
			continue

		if not order.has_meta("replacement_created"):
			order.set_meta(
				"replacement_created",
				true
			)

			needs_sync = true

			get_tree().create_timer(
				next_order_delay
			).timeout.connect(
				_create_replacement_order.bind(order.order_id)
			)

	if needs_sync:
		_sync_orders()


func _create_replacement_order(
	completed_order_id: int
	) -> void:
	if not multiplayer.is_server():
		return
	
	if not DayManager.store_open:
		return
	
	if DayManager.current_hour >= DayManager.STORE_CLOSE_HOUR:
		return
	
	var completed_order: OrderData = get_order(
		completed_order_id
	)

	if completed_order == null:
		return

	if (
		completed_order.state != OrderData.OrderState.COMPLETED
		and completed_order.state != OrderData.OrderState.CANCELLED
		):
		return

	var index: int = orders.find(completed_order)

	if index == -1:
		return

	var new_order: OrderData = _build_order()

	orders[index] = new_order

	order_generated.emit(new_order)
	_sync_orders()


func _build_order() -> OrderData:
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

	return order


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
