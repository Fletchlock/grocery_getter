extends Node3D


@export_group("Interaction Area")
@export var interaction_top_padding: float = 0.0
@export var allow_orders: bool = true

@export_group("Checkout") #for differentiating the checkout and online order tills
@export var online_order_checkout: bool = false 

@onready var order_label: Label3D = $Label3D
@onready var order_scanner_beep_player: AudioStreamPlayer3D = $AcceptOrderArea/OrderScannerBeepPlayer


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
			
			var total_seconds: int = int(remaining_time)
			var minutes: int = floori(remaining_time / 60.0)
			var seconds: int = total_seconds % 60

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
	var peer_id: int = player.get_multiplayer_authority()

	if player.network_holding_item:
		var product: ProductData = player.held_item as ProductData

		if product == null:
			return ""

		var order: OrderData = OrderManager.get_player_order(peer_id)

		if order == null or not order.checkout_started:
			return ""

		if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
			return ""

		return "[E] Scan " + product.display_name

	# Players with an active order cannot accept another.
	if OrderManager.get_player_order(peer_id) != null:
		return ""

	if not allow_orders:
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
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if player.network_holding_item:
		var product: ProductData = player.held_item as ProductData

		if product == null:
			return

		var order: OrderData = OrderManager.get_player_order(peer_id)

		if order == null or not order.checkout_started:
			return

		if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
			return

		if product.product_category == "produce":
			_open_produce_code_hud(player, product)
			return

		if multiplayer.is_server():
			_submit_product(player)
		else:
			request_submit_product.rpc_id(
				1,
				player.get_path(),
				product.resource_path
			)

		return

	# Accepting an order is only allowed at an order board.
	if not allow_orders:
		return

	if OrderManager.get_player_order(peer_id) != null:
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

	if not allow_orders:
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

	var order: OrderData = OrderManager.get_player_order(
		requesting_peer_id
	)

	if order == null or not order.checkout_started:
		return

	if not player.network_holding_item:
		return

	if player.network_held_item_path != product_path:
		return

	if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	_submit_product_to_checkout(player, product)


func _submit_product_to_checkout(
	player: CharacterBody3D,
	product: ProductData
) -> bool:
	if not multiplayer.is_server():
		return false

	if player == null or product == null:
		return false

	var peer_id: int = player.get_multiplayer_authority()
	
	var order_grid: OrderGrid = (
		get_tree().get_first_node_in_group("online_order_grid")
		as OrderGrid
	)

	if order_grid == null:
		return false

	if not order_grid.can_use_checkout(peer_id):
		return false
	
	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null or not order.checkout_started:
		return false

	# Verify the item is actually held by this player.
	if not player.network_holding_item:
		return false

	if player.network_held_item_path != product.resource_path:
		return false

	# This origin was assigned by the server when the
	# product was taken from OrderGrid.
	if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
		return false

	if not OrderManager.record_checkout_scan(peer_id, product):
		return false

	# Product successfully scanned.
	player.held_item_origin = player.ItemOrigin.NONE

	if product.product_category == "produce":
		_set_barcode_hud_for_player(peer_id, false)

	if peer_id == multiplayer.get_unique_id():
		var hud: Node = get_tree().get_first_node_in_group(
			"day_time_hud"
		)

		if hud != null:
			hud.completed_barcode_code = ""
	else:
		_reset_completed_barcode_code.rpc_id(peer_id)

	if peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(peer_id)

	_play_order_scanner_beep.rpc()

	return true


@rpc("authority", "call_remote", "reliable")
func _close_barcode_hud() -> void:
	var hud := get_tree().get_first_node_in_group("day_time_hud")
	if hud != null:
		hud.close_barcode_hud()


@rpc("authority", "call_remote", "reliable")
func _reset_completed_barcode_code() -> void:
	var hud := get_tree().get_first_node_in_group("day_time_hud")
	if hud != null:
		hud.completed_barcode_code = ""


func _update_barcode_hud(product: ProductData) -> void:
	var day_time_hud = get_tree().get_first_node_in_group("day_time_hud")
	if day_time_hud == null:
		return

	if product != null:
		day_time_hud._update_barcode(product.product_code)
	else:
		day_time_hud._update_barcode("")


func _set_barcode_hud_for_player(
	player_peer_id: int,
	should_show: bool,
	product_code: String = ""
) -> void:
	if player_peer_id == multiplayer.get_unique_id():
		_apply_barcode_hud_state(should_show, product_code)
	else:
		_apply_barcode_hud_state.rpc_id(
			player_peer_id,
			should_show,
			product_code
		)


@rpc("authority", "call_remote", "reliable")
func _apply_barcode_hud_state(
	should_show: bool,
	product_code: String = ""
) -> void:
	var hud := get_tree().get_first_node_in_group("day_time_hud")
	if hud == null:
		push_warning("No DayTimeHud found in the day_time_hud group.")
		return

	if should_show:
		hud.set_barcode_checkout(self)
		hud.show_barcode_hud(product_code)
	else:
		hud.close_barcode_hud()


func _close_barcode_hud_for_player(player_peer_id: int) -> void:
	if player_peer_id == multiplayer.get_unique_id():
		_close_barcode_hud()
	else:
		_close_barcode_hud.rpc_id(player_peer_id)


func _open_produce_code_hud(
	player: CharacterBody3D,
	product: ProductData
) -> void:
	var player_peer_id := player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		var hud := get_tree().get_first_node_in_group("day_time_hud")
		if hud != null:
			hud.set_barcode_checkout(self)
			hud.show_barcode_hud(product.product_code)
	else:
		_apply_barcode_hud_state.rpc_id(
			player_peer_id,
			true,
			product.product_code
		)


func complete_produce_code(product_code: String) -> void:
	var player: CharacterBody3D = (
		get_tree().get_first_node_in_group("local_player")
		as CharacterBody3D
	)

	if player == null:
		return

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return

	if product.product_category != "produce":
		return

	if product.product_code != product_code:
		return

	if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
		return

	var peer_id: int = player.get_multiplayer_authority()
	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null or not order.checkout_started:
		return

	if multiplayer.is_server():
		_submit_product(player)
	else:
		request_submit_product.rpc_id(
			1,
			player.get_path(),
			product.resource_path
		)


@rpc("authority", "call_local", "reliable")
func _play_order_scanner_beep() -> void:
	if not is_instance_valid(order_scanner_beep_player):
		return

	order_scanner_beep_player.pitch_scale = randf_range(1.0, 1.05)
	order_scanner_beep_player.play()
