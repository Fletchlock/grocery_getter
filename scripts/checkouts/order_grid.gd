
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
