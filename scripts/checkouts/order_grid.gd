
@tool
extends CartGrid
class_name OrderGrid

signal checkout_owner_changed

func can_use_checkout(peer_id: int) -> bool:
	if order_owner_peer_id == 0:
		return false

	if order_owner_peer_id != peer_id:
		return false

	return OrderManager.get_player_order(peer_id) != null


func claim_checkout(peer_id: int) -> bool:
	if not multiplayer.is_server():
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
