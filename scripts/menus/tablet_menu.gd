extends Control


@onready var order_label: Label = $MarginContainer/PanelContainer/OrderLabel


var displayed_order: OrderData
var active_cart: CartGrid


func _ready() -> void:
	visible = false

	OrderManager.order_generated.connect(_on_order_changed)
	OrderManager.order_updated.connect(_on_order_changed)
	
	for candidate: Node in get_tree().get_nodes_in_group("cart_grid"):
		var cart_grid: CartGrid = candidate as CartGrid

		if cart_grid == null:
			continue

		cart_grid.cart_contents_changed.connect(_on_cart_contents_changed)

func _toggle_hud() -> void:
	var player: CharacterBody3D = _get_local_player()

	if player == null:
		return

	visible = not visible
	player.order_menu_open = visible

	if not visible:
		return

	_update_local_order()

	if displayed_order == null:
		visible = false
		player.order_menu_open = false
		return

	_update_display(displayed_order)


func _process(_delta: float) -> void:
	if not visible:
		return

	_update_local_order()

	if displayed_order == null:
		visible = false

		var player: CharacterBody3D = _get_local_player()

		if player != null:
			player.order_menu_open = false

		return

	_update_display(displayed_order)


func _on_order_changed(_order: OrderData) -> void:
	_update_local_order()

	if not visible:
		return

	if displayed_order == null:
		return

	_update_display(displayed_order)


func _get_local_player() -> CharacterBody3D:
	var local_peer_id: int = multiplayer.get_unique_id()

	for candidate: Node in get_tree().get_nodes_in_group("player"):
		var character: CharacterBody3D = candidate as CharacterBody3D

		if character == null:
			continue

		if character.get_multiplayer_authority() == local_peer_id:
			return character

	return null


func _update_local_order() -> void:
	var local_peer_id: int = multiplayer.get_unique_id()

	displayed_order = OrderManager.get_player_order(local_peer_id)


func _update_display(order: OrderData) -> void:
	if order == null:
		return

	var text: String = "ORDER #%d\n\n" % order.order_id

	for item: OrderItem in order.items:
		var cart_quantity: int = _get_cart_quantity(item.product)

		var display_quantity: int = (
			item.quantity_fulfilled
			+ cart_quantity
		)

		display_quantity = mini(
			display_quantity,
			item.quantity
		)

		text += "%s    %d/%d\n" % [
			item.product.display_name,
			display_quantity,
			item.quantity
		]

	text += "\nORDER TOTAL: $%.2f" % order.current_profit

	if order.state == OrderData.OrderState.ACTIVE:
		var remaining_time: float = maxf(
			order.time_limit - order.elapsed_time,
			0.0
		)

		var minutes: int = int(remaining_time) / 60
		var seconds: int = int(remaining_time) % 60

		text += "\nTIME REMAINING: %02d:%02d" % [
			minutes,
			seconds
		]

	elif order.state == OrderData.OrderState.COMPLETED:
		text += "\n\n*** ORDER COMPLETE ***"

		if order.elapsed_time > order.time_limit:
			text += "\nTHE ORDER WAS LATE!"
		else:
			text += "\nGOOD JOB!"

	order_label.text = text


func _get_cart_quantity(product: ProductData) -> int:
	if active_cart == null:
		return 0

	var count: int = 0

	for cart_product: ProductData in active_cart.cart_items:
		if cart_product == product:
			count += 1

	return count


func _on_cart_contents_changed(cart_grid: CartGrid) -> void:
	var player: CharacterBody3D = _get_local_player()

	if player == null:
		return

	print(
		"Tablet ",
		multiplayer.get_unique_id(),
		" | incoming: ",
		cart_grid.get_parent().name,
		" | attached: ",
		player.attached_cart.name if player.attached_cart else "NONE"
	)
	
	active_cart = cart_grid

	if not visible:
		return

	if displayed_order == null:
		return

	_update_display(displayed_order)
