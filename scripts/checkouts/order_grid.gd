
@tool
extends CartGrid
class_name OrderGrid

signal checkout_owner_changed

var drone_checkout_order_id: int = -1


func has_drone_checkout() -> bool:
	if drone_checkout_order_id < 0:
		return false

	var order: OrderData = OrderManager.get_order(
		drone_checkout_order_id
	)

	return (
		order != null
		and order.state == OrderData.OrderState.ACTIVE
	)


@rpc("authority", "call_local", "reliable")
func sync_drone_checkout(order_id: int) -> void:
	drone_checkout_order_id = order_id
	checkout_owner_changed.emit()


func can_use_checkout(peer_id: int) -> bool:
	if peer_id <= 0:
		return false

	if has_drone_checkout():
		return true

	if order_owner_peer_id == 0:
		return false

	if order_owner_peer_id != peer_id:
		return false

	return OrderManager.get_player_order(peer_id) != null


func get_checkout_order(peer_id: int) -> OrderData:
	if has_drone_checkout():
		return OrderManager.get_order(drone_checkout_order_id)

	if not can_use_checkout(peer_id):
		return null

	return OrderManager.get_player_order(peer_id)


func claim_checkout(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	
	if has_drone_checkout():
		return false
	
	if peer_id <= 0:
		return false

	if order_owner_peer_id != 0:
		return can_use_checkout(peer_id)

	if OrderManager.get_player_order(peer_id) == null:
		return false

	order_owner_peer_id = peer_id
	sync_checkout_owner.rpc(order_owner_peer_id)

	return true


func release_checkout() -> void:
	if not multiplayer.is_server():
		return

	order_owner_peer_id = 0
	sync_checkout_owner.rpc(0)


@rpc("authority", "call_local", "reliable")
func sync_checkout_owner(peer_id: int) -> void:
	order_owner_peer_id = peer_id
	checkout_owner_changed.emit()


func take_last_item() -> ProductData:
	if cart_items.is_empty():
		return null

	return take_item_at_index(0)


func take_item_at_index(item_index: int) -> ProductData:
	var owner_id: int = order_owner_peer_id
	var product: ProductData = super.take_item_at_index(item_index)

	# CartGrid normally releases ownership when empty.
	# OrderGrid must remain reserved during checkout.
	order_owner_peer_id = owner_id

	return product


func _add_item_from_player(
	player: CharacterBody3D,
	product_path: String
) -> void:
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if not can_use_checkout(peer_id):
		return

	super._add_item_from_player(player, product_path)


func _take_item_for_player(
	player: CharacterBody3D,
	item_index: int
) -> void:
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if not can_use_checkout(peer_id):
		return

	super._take_item_for_player(player, item_index)


# -------------------------------------------------------------------
# UFO drone delivery
# -------------------------------------------------------------------
func add_drone_product(product: ProductData) -> bool:
	if not multiplayer.is_server():
		return false

	if product == null:
		return false

	# Only accept deliveries for the drone's active order.
	var drone_order: OrderData = OrderManager.get_drone_order()

	if drone_order == null:
		return false

	# Do not mix drone deliveries with player checkouts.
	if order_owner_peer_id != 0:
		return false

	# Do not mix deliveries from different drone orders.
	if (
		drone_checkout_order_id >= 0
		and drone_checkout_order_id != drone_order.order_id
	):
		return false

	# Confirm this product belongs to the drone's order.
	var requested: bool = false

	for item: OrderItem in drone_order.items:
		if item.product == null:
			continue

		if item.product.resource_path == product.resource_path:
			requested = true
			break

	if not requested:
		return false
	
	var placement_preview: Dictionary = get_next_item_placement(product)

	if placement_preview.is_empty():
		return false

	print(
		"ORDER DRONE: Planned placement for ",
		product.display_name,
		" at ",
		placement_preview["position"]
	)
	
	# Use the existing CartGrid packing system.
	if not add_item(product):
		return false
	
	if drone_checkout_order_id < 0:
		if not OrderManager.start_drone_checkout(
			drone_order.order_id
		):
			# Roll back the item if checkout cannot start.
			take_item_at_index(cart_items.size() - 1)
			return false

		sync_drone_checkout.rpc(drone_order.order_id)

		print(
			"ORDER DRONE: Checkout assigned to order #",
			drone_order.order_id
		)
	
	# Synchronize the new grid contents to all clients.
	sync_cart_state.rpc(
		_get_product_paths(),
		item_positions.duplicate(),
		item_scales.duplicate(),
		_get_item_rotations()
	)

	cart_contents_changed.emit(self)

	print(
		"ORDER DRONE: Delivered ",
		product.display_name,
		" | Grid items: ",
		get_item_count()
	)

	return true


func release_drone_checkout() -> void:
	if not multiplayer.is_server():
		return

	sync_drone_checkout.rpc(-1)


func get_interaction_prompt_for_player(
	player: CharacterBody3D
) -> String:
	if player == null:
		return ""

	if has_drone_checkout():
		_clear_take_item_outline()

		if has_items():
			return "UFO ORDER - Awaiting Checkout"

		return "UFO ORDER - Preparing Delivery"

	return super.get_interaction_prompt_for_player(player)
