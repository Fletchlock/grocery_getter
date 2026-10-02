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


var current_order: OrderData
var next_order_id: int = 1
var next_order_timer: float = 0.0
var shopper_stats: Node3D


func _ready() -> void:
	shopper_stats = get_tree().get_first_node_in_group("shopper_stats")
	generate_order()


func _process(delta: float) -> void:
	update_timer(delta)
	
	if current_order == null:
		return

	if current_order.state == OrderData.OrderState.COMPLETED:
		next_order_timer -= delta

		if next_order_timer <= 0.0:
			generate_order()

func generate_order() -> void:
	current_order = OrderData.new()
	current_order.order_id = next_order_id
	next_order_id += 1
	
	var item_count: int = randi_range(min_products, max_products)
	
	var products: Array[ProductData] = available_products.duplicate()
	products.shuffle()
	
	item_count = mini(item_count, products.size())
	
	for i: int in item_count:
		var item: OrderItem = OrderItem.new()
		item.product = products[i]
		item.quantity = randi_range(min_items, max_items)
		
		current_order.items.append(item)
		
	current_order.initialize()
	
	order_generated.emit(current_order)

func accept_order(player: CharacterBody3D) -> void:
	if current_order == null:
		return
		
	if current_order.state != OrderData.OrderState.WAITING:
		return
		
	current_order.state = OrderData.OrderState.ACTIVE
	current_order.accepted_by_peer_id = player.get_multiplayer_authority()
	
	print(
		"Order #",
		current_order.order_id,
		" accepted by peer ",
		current_order.accepted_by_peer_id
	)
	
	
func submit_product(product: ProductData) -> bool:
	if current_order == null:
		return false
		
	if current_order.state != OrderData.OrderState.ACTIVE:
		return false
		
	for item: OrderItem in current_order.items:
		if item.product != product:
			continue
			
		if item.is_complete():
			return false
			
		item.quantity_fulfilled += 1
		
		order_updated.emit(current_order)
		
		if _is_order_complete():
			complete_order()
		
		return true

	return false
	
func update_timer(delta: float) -> void:
	if current_order == null:
		return
		
	if current_order.state != OrderData.OrderState.ACTIVE:
		return
		
	current_order.elapsed_time += delta
	
	if current_order.elapsed_time <= current_order.time_limit:
		current_order.current_profit = current_order.base_profit
		return
		
	var late_seconds: float = current_order.elapsed_time - current_order.time_limit
	var late_loss: float = current_order.base_profit * current_order.late_loss_per_second * late_seconds
	
	current_order.current_profit = maxf(
		current_order.base_profit - late_loss, 
		0.0
	)
	
	if current_order.current_profit <= 0.0:
		cancel_order()
	
func complete_order() -> void:
	if current_order == null:
		return
		
	if current_order.state != OrderData.OrderState.ACTIVE:
		return
		
	current_order.state = OrderData.OrderState.COMPLETED
	next_order_timer = next_order_delay
		
	shopper_stats.record_order(current_order.current_profit)
	order_updated.emit(current_order)
	
	
func cancel_order() -> void:
	pass
	

func _is_order_complete() -> bool:
	for item: OrderItem in current_order.items:
		if not item.is_complete():
			return false
			
	return  true	
