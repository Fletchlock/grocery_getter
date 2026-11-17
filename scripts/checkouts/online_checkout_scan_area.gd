
extends Area3D
class_name OnlineCheckoutScanArea


@export_group("Interaction Area")
@export var interaction_top_padding: float = 0.0
@export var allow_orders: bool = true

@onready var order_grid: OrderGrid = $"../OrderGrid"
@onready var order_scanner_beep_player: AudioStreamPlayer3D = $OrderScannerBeepPlayer


# ============================================================
# ORDER LOOKUP
# ============================================================

func _get_checkout_order(peer_id: int) -> OrderData:
	if order_grid == null:
		return null

	return order_grid.get_checkout_order(peer_id)


# ============================================================
# INTERACTION PROMPTS
# ============================================================

func get_interaction_prompt(player: CharacterBody3D) -> String:
	if player == null:
		return ""

	var peer_id: int = player.get_multiplayer_authority()

	if player.network_holding_item:
		var product: ProductData = player.held_item as ProductData

		if product == null:
			return ""

		if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
			return ""

		var order: OrderData = _get_checkout_order(peer_id)

		if order == null or not order.checkout_started:
			return ""

		return "[E] Scan " + product.display_name

	if not allow_orders:
		return ""

	if OrderManager.get_player_order(peer_id) != null:
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


# ============================================================
# PLAYER INTERACTION
# ============================================================

func interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if player.network_holding_item:
		var product: ProductData = player.held_item as ProductData

		if product == null:
			return

		var order: OrderData = _get_checkout_order(peer_id)

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

	if not allow_orders:
		return

	if OrderManager.get_player_order(peer_id) != null:
		return

	if OrderManager.get_available_order() == null:
		return

	if multiplayer.is_server():
		OrderManager.accept_order(player)
	else:
		request_accept_order.rpc_id(
			1,
			player.get_path()
		)


# ============================================================
# ORDER ACCEPTANCE
# ============================================================

@rpc("any_peer", "call_remote", "reliable")
func request_accept_order(player_path: NodePath) -> void:
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


# ============================================================
# PRODUCT SCANNING
# ============================================================

func _submit_product(player: CharacterBody3D) -> void:
	if player.held_item == null:
		return

	_submit_product_to_checkout(player, player.held_item)


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

	var order: OrderData = _get_checkout_order(
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

	if order_grid == null:
		return false

	var peer_id: int = player.get_multiplayer_authority()

	if not order_grid.can_use_checkout(peer_id):
		return false

	var order: OrderData = _get_checkout_order(peer_id)

	if order == null or not order.checkout_started:
		return false

	# Verify that the player actually holds this product.
	if not player.network_holding_item:
		return false

	if player.network_held_item_path != product.resource_path:
		return false

	if player.held_item_origin != player.ItemOrigin.ORDER_GRID:
		return false

	var scan_successful: bool = false

	if order_grid.has_drone_checkout():
		scan_successful = OrderManager.record_drone_checkout_scan(
			order_grid.drone_checkout_order_id,
			product
		)
	else:
		scan_successful = OrderManager.record_checkout_scan(
			peer_id,
			product
		)

	if not scan_successful:
		return false

	# The server has accepted the scan.
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

	# Clear the held product on its owning player.
	if peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(peer_id)

	# Play the scanner beep for everyone.
	_play_order_scanner_beep.rpc()

	return true


# ============================================================
# PRODUCE BARCODE HUD
# ============================================================

func _open_produce_code_hud(
	player: CharacterBody3D,
	product: ProductData
) -> void:
	var peer_id: int = player.get_multiplayer_authority()

	_set_barcode_hud_for_player(
		peer_id,
		true,
		product.product_code
	)


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
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud == null:
		push_warning("No DayTimeHud found in the day_time_hud group.")
		return

	if should_show:
		hud.set_barcode_checkout(self)
		hud.show_barcode_hud(product_code)
	else:
		hud.close_barcode_hud()


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
	var order: OrderData = _get_checkout_order(peer_id)

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


@rpc("authority", "call_remote", "reliable")
func _close_barcode_hud() -> void:
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud != null:
		hud.close_barcode_hud()


@rpc("authority", "call_remote", "reliable")
func _reset_completed_barcode_code() -> void:
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud != null:
		hud.completed_barcode_code = ""


# ============================================================
# SCANNER AUDIO
# ============================================================

@rpc("authority", "call_local", "reliable")
func _play_order_scanner_beep() -> void:
	if not is_instance_valid(order_scanner_beep_player):
		return

	order_scanner_beep_player.pitch_scale = randf_range(1.0, 1.05)
	order_scanner_beep_player.play()
