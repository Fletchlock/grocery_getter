extends Node3D


@export_group("Interaction Area")
@export var interaction_top_padding: float = 0.0

@onready var order_label: Label3D = $Label3D
@onready var scanner_beep_player: AudioStreamPlayer3D = $AcceptOrderArea/ScannerBeepPlayer


func _ready() -> void:
	OrderManager.order_generated.connect(_on_order_generated)
	OrderManager.order_updated.connect(_on_order_updated)

	_update_board_display()


func _process(_delta: float) -> void:
	_update_board_display()


func _on_order_generated(_order: OrderData) -> void:
	_update_board_display()


func _on_order_updated(_order: OrderData) -> void:
	_update_board_display()


func _update_board_display() -> void:
	var orders: Array[OrderData] = OrderManager.get_orders()

	if orders.is_empty():
		order_label.text = "NO ORDERS"
		return

	var text: String = ""

	for i: int in orders.size():
		var order: OrderData = orders[i]

		if i > 0:
			text += "\n\n"

		text += _get_order_summary(order)

	order_label.text = text


func _get_order_summary(order: OrderData) -> String:
	match order.state:
		OrderData.OrderState.WAITING:
			return "NEW ORDER"

		OrderData.OrderState.ACTIVE:
			var player_name: String = LobbyManager.get_player_name(
				order.accepted_by_peer_id
			)

			if player_name.is_empty():
				player_name = "Player"

			var remaining_time: float = maxf(
				order.time_limit - order.elapsed_time,
				0.0
			)

			var minutes: int = int(remaining_time) / 60
			var seconds: int = int(remaining_time) % 60

			return "ORDER %d %s - ACTIVE - %02d:%02d" % [
				order.order_id,
				player_name,
				minutes,
				seconds
			]

		OrderData.OrderState.COMPLETED:
			var player_name: String = LobbyManager.get_player_name(
				order.accepted_by_peer_id
			)

			if player_name.is_empty():
				player_name = "Player"

			var completion_text: String = "On time"

			if order.elapsed_time > order.time_limit:
				completion_text = "Late"

			return "ORDER %d %s - COMPLETED - %s" % [
				order.order_id,
				player_name,
				completion_text
			]

		OrderData.OrderState.CANCELLED:
			var player_name: String = LobbyManager.get_player_name(
				order.accepted_by_peer_id
			)

			if player_name.is_empty():
				player_name = "Player"

			return "ORDER %d %s - CANCELLED" % [
				order.order_id,
				player_name
			]

	return ""


func get_interaction_prompt(player: CharacterBody3D) -> String:
	if player.network_holding_item:
		if player.held_item == null:
			return ""

		var player_peer_id: int = player.get_multiplayer_authority()

		# Preserve online-order checkout when the player owns an order.
		if OrderManager.get_player_order(player_peer_id) != null:
			return "[E] Checkout " + player.held_item.display_name

		# Otherwise, allow scanning for the active AI shopper.
		var checkout: Checkout = (
			get_tree().get_first_node_in_group("checkout")
			as Checkout
		)

		if checkout != null:
			if not multiplayer.is_server():
				return "[E] Scan " + player.held_item.display_name

			if checkout.can_scan_ai_product(player.held_item):
				return "[E] Scan " + player.held_item.display_name

		return ""

	if OrderManager.get_player_order(
		player.get_multiplayer_authority()
	) != null:
		return ""

	if OrderManager.get_available_order() == null:
		return ""

	return "[E] Accept Order"


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
	) -> Vector3:
	var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D

	if box_shape == null:
		return collision_shape.global_position

	return (
		collision_shape.global_position
		+ Vector3.UP * (
			box_shape.size.y * 0.5
			+ interaction_top_padding
		)
	)


func interact(player: CharacterBody3D) -> void:
	if player.network_holding_item:
		if player.held_item == null:
			return

		if multiplayer.is_server():
			_submit_product(player)

		else:
			request_submit_product.rpc_id(
				1,
				player.get_path(),
				player.held_item.resource_path
			)

		return

	if multiplayer.is_server():
		OrderManager.accept_order(player)

	else:
		request_accept_order.rpc_id(
			1,
			player.get_path()
		)


func _submit_product(player: CharacterBody3D) -> void:
	if player.held_item == null:
		return

	_submit_product_to_checkout(player, player.held_item)


@rpc("any_peer", "call_remote", "reliable")
func request_accept_order(
	player_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	OrderManager.accept_order(player)


@rpc("any_peer", "call_remote", "reliable")
func request_submit_product(
	player_path: NodePath,
	product_path: String
) -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	if player.held_item == null:
		return

	if not player.network_holding_item:
		return

	# Verify the requested product matches the replicated held item.
	if player.network_held_item_path != product_path:
		return

	var loaded_resource: Resource = load(product_path)

	if loaded_resource == null:
		return

	if not loaded_resource is ProductData:
		return

	var product: ProductData = loaded_resource as ProductData

	_submit_product_to_checkout(player, product)


func _submit_product_to_checkout(
	player: CharacterBody3D,
	product: ProductData
) -> bool:
	var player_peer_id: int = player.get_multiplayer_authority()
	var player_order: OrderData = OrderManager.get_player_order(
		player_peer_id
	)

	var submitted: bool = false

	if player_order != null:
		# Existing online-order flow.
		submitted = OrderManager.submit_product(player, product)
	else:
		# AI shopper checkout flow.
		var checkout: Checkout = (
			get_tree().get_first_node_in_group("checkout")
			as Checkout
		)

		if checkout != null:
			submitted = checkout.scan_ai_product(product)

	if not submitted:
		return false

	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(player_peer_id)

	_play_scanner_beep.rpc()

	return true


@rpc("authority", "call_local", "reliable")
func _play_scanner_beep() -> void:
	scanner_beep_player.pitch_scale = randf_range(
		1.0,
		1.05
	)
	scanner_beep_player.play()
