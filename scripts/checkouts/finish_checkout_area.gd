
extends Area3D
class_name FinishCheckoutArea


@export var order_grid: OrderGrid


func get_interaction_prompt(player: CharacterBody3D) -> String:
	if player == null:
		return ""

	if player.network_holding_item:
		return ""

	if order_grid == null:
		return ""

	var peer_id: int = player.get_multiplayer_authority()
	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null:
		return ""

	if not order.checkout_started:
		return ""

	if not order_grid.can_use_checkout(peer_id):
		return ""

	if order_grid.has_items():
		return ""

	return "[E] Finish Checkout"


func interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if multiplayer.is_server():
		_finish_checkout(peer_id)
	else:
		request_finish_checkout.rpc_id(1, player.get_path())


@rpc("any_peer", "call_remote", "reliable")
func request_finish_checkout(player_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if player.get_multiplayer_authority() != peer_id:
		return

	_finish_checkout(peer_id)


func _finish_checkout(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if order_grid == null:
		return

	if not order_grid.can_use_checkout(peer_id):
		return

	if order_grid.has_items():
		return

	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null or not order.checkout_started:
		return

	if not OrderManager.finish_order_checkout(peer_id):
		return

	# Explicitly tell the checkout screen to show the results.
	var checkout_display: OnlineCheckoutDisplay = (
		get_parent().get_node_or_null(
			"CheckoutViewport/OnlineCheckoutUI"
		) as OnlineCheckoutDisplay
	)

	if checkout_display != null:
		checkout_display.show_finished_order.rpc(order.order_id)

	order_grid.release_checkout()

	print(
		"Online order checkout finished for player ",
		peer_id,
		" | Order #",
		order.order_id,
		" | Incorrect items: ",
		order.incorrect_item_count
	)
