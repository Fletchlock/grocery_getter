
extends Area3D
class_name CartParkingArea


@onready var order_grid: OrderGrid = $"../OrderGrid"


func contains_cart(cart: RigidBody3D) -> bool:
	if cart == null:
		return false

	for body: Node3D in get_overlapping_bodies():
		if body == cart:
			return true

	return false


func unload_cart(cart: RigidBody3D, peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not contains_cart(cart):
		return

	var cart_grid: CartGrid = cart.get_node_or_null(
		"CartGrid"
	) as CartGrid

	if cart_grid == null:
		return

	if cart_grid.order_owner_peer_id != 0:
		if cart_grid.order_owner_peer_id != peer_id:
			return

	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null:
		return

	if not order.checkout_started:
		if not OrderManager.start_order_checkout(peer_id):
			return

	var transferred: int = 0

	while cart_grid.has_items():
		var product: ProductData = cart_grid.cart_items[0]

		if product == null:
			break

		# Only remove the product if it fits on OrderGrid.
		if not order_grid.add_item(product):
			break

		cart_grid.take_item_at_index(0)
		transferred += 1

	if transferred == 0:
		return

	# Synchronize both grids to all clients.
	order_grid.sync_cart_state.rpc(
		order_grid._get_product_paths()
	)

	cart_grid.sync_cart_state.rpc(
		cart_grid._get_product_paths()
	)

	print(
		"Online order checkout: transferred ",
		transferred,
		" products from ",
		cart.name,
		" for player ",
		peer_id
	)
