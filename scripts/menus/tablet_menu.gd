extends Control



@onready var order_label: Label = $PanelContainer/OrderLabel



func _ready() -> void:
	visible = false
	
	OrderManager.order_generated.connect(_on_order_changed)
	OrderManager.order_updated.connect(_on_order_changed)


func _toggle_hud() -> void:
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	visible = not visible
	player.order_menu_open = visible

	if not visible:
		return

	var order: OrderData = OrderManager.current_order

	if order == null:
		visible = false
		player.order_menu_open = false
		return

	if order.state != OrderData.OrderState.ACTIVE:
		visible = false
		player.order_menu_open = false
		return

	_update_display(order)


func _process(_delta: float) -> void:
	if not visible:
		return

	var order: OrderData = OrderManager.current_order

	if order == null:
		visible = false
		return

	_update_display(order)


func _on_order_changed(order: OrderData) -> void:
	if visible:
		_update_display(order)


func _update_display(order: OrderData) -> void:
	if order == null:
		return

	if order.state != OrderData.OrderState.ACTIVE:
		order_label.text = ""
		return
	
	var text: String = "ORDER #%d\n\n" % order.order_id

	for item: OrderItem in order.items:
		var cart_quantity: int = _get_cart_quantity(item.product)

		if cart_quantity >= item.quantity:
			text += "%s    %d/%d\n" % [
				item.product.display_name,
				cart_quantity,
				item.quantity
			]
		else:
			text += "%s    %d/%d\n" % [
				item.product.display_name,
				cart_quantity,
				item.quantity
			]

	text += "\nORDER TOTAL: $%.2f" % order.current_profit

	var remaining_time: float = maxf(
		order.time_limit - order.elapsed_time,
		0.0
	)

	var minutes: int = int(remaining_time) / 60
	var seconds: int = int(remaining_time) % 60

	text += "\nTIME REMAINING: %02d:%02d" % [minutes, seconds]

	order_label.text = text


func _get_cart_quantity(product: ProductData) -> int:
	var cart_grid: CartGrid = get_tree().get_first_node_in_group("cart_grid")

	if cart_grid == null:
		return 0

	var count: int = 0

	for cart_product: ProductData in cart_grid.cart_items:
		if cart_product == product:
			count += 1

	return count
