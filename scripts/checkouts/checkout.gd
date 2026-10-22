
extends Node3D
class_name Checkout


@onready var checkout_point: Marker3D = $CheckoutPoint
@onready var waiting_points: Array[Marker3D] = [
	$WaitingPoints/WaitingPoint1,
	$WaitingPoints/WaitingPoint2,
	$WaitingPoints/WaitingPoint3
]

@onready var checkout_grid: CheckoutGrid = $CheckoutGrid
@onready var bag_grid: CartGrid = $BagGrid
@onready var bag_point: Marker3D = $BagPoint
@onready var bag_mesh: MeshInstance3D = $BagGrid/BagMesh

# AI Checkout Scanner
@onready var scan_area: Area3D = $ScanArea
@onready var scanner_beep_player: AudioStreamPlayer3D = $ScannerBeepPlayer


# Customers
var checkout_customer: ShopperAI = null
var waiting_customers: Array[ShopperAI] = []
var unscanned_items: Array[ProductData] = []

# Desk Bell
@onready var desk_bell: AudioStreamPlayer3D = $DeskBellPlayer
const BELL_WAIT_MINUTES: int = 10
var last_scan_game_minute: int = 0
var checkout_active: bool = false


func _ready() -> void:
	add_to_group("checkout")
	bag_mesh.hide()


func _process(_delta: float) -> void:
	if multiplayer.is_server():
		_check_checkout_bell()


func get_interaction_prompt(player: CharacterBody3D) -> String:
	if not player.network_holding_item:
		return ""

	if player.held_item == null:
		return ""

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return ""

	return "[E] Scan " + product.display_name


func interact(player: CharacterBody3D) -> void:
	if player == null or player.held_item == null:
		return

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return

	if product.product_category == "produce":
		_open_produce_code_hud(player, product)
		return

	_request_ai_scan(player, product)


func request_checkout(customer: ShopperAI) -> Marker3D:
	if customer == checkout_customer:
		return checkout_point

	if waiting_customers.has(customer):
		var index: int = waiting_customers.find(customer)
		return waiting_points[index]

	if checkout_customer == null:
		checkout_customer = customer
		return checkout_point

	if waiting_customers.size() >= waiting_points.size():
		return null

	waiting_customers.append(customer)

	return waiting_points[waiting_customers.size() - 1]


func _request_ai_scan(
	player: CharacterBody3D,
	product: ProductData,
	entered_code: String = ""
) -> void:
	if multiplayer.is_server():
		_server_scan_ai_product(player, product, entered_code)
	else:
		request_scan_ai_product.rpc_id(
			1,
			player.get_path(),
			product.resource_path,
			entered_code
		)


@rpc("any_peer", "call_remote", "reliable")
func request_scan_ai_product(
	player_path: NodePath,
	product_path: String,
	entered_code: String = ""
) -> void:
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

	if not player.network_holding_item:
		return

	if player.network_held_item_path != product_path:
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	_server_scan_ai_product(player, product, entered_code)


func _server_scan_ai_product(
	player: CharacterBody3D,
	product: ProductData,
	entered_code: String = ""
) -> void:
	if not multiplayer.is_server():
		return

	if player == null or product == null:
		return

	if not player.network_holding_item:
		return

	if player.network_held_item_path != product.resource_path:
		return

	# Produce must have the correct code before scanning.
	if product.product_category == "produce":
		if entered_code.is_empty():
			return

		if entered_code != product.product_code:
			return

	if not scan_ai_product(product):
		return

	var peer_id: int = player.get_multiplayer_authority()

	# Close and reset the barcode HUD after a successful produce scan.
	if product.product_category == "produce":
		if peer_id == multiplayer.get_unique_id():
			_apply_barcode_hud_state(false)
			_reset_completed_barcode_code()
		else:
			_apply_barcode_hud_state.rpc_id(peer_id, false)
			_reset_completed_barcode_code.rpc_id(peer_id)

	# Remove the scanned product from the player's hand.
	if peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(peer_id)


func _open_produce_code_hud(
	player: CharacterBody3D,
	product: ProductData
) -> void:
	if player == null or product == null:
		return

	var player_peer_id: int = player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		_apply_barcode_hud_state(true, product.product_code)
	else:
		_apply_barcode_hud_state.rpc_id(
			player_peer_id,
			true,
			product.product_code
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

	if player == null or player.held_item == null:
		return

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return

	if product.product_category != "produce":
		return

	if product.product_code != product_code:
		return

	_request_ai_scan(player, product, product_code)


@rpc("authority", "call_remote", "reliable")
func _reset_completed_barcode_code() -> void:
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud != null:
		hud.completed_barcode_code = ""


# Called when the active shopper reaches CheckoutPoint.
func customer_arrived_at_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return
	
	if customer != checkout_customer:
		return
	
	unscanned_items = customer.purchased_items.duplicate()

	_clear_grid(checkout_grid)

	for product: ProductData in customer.purchased_items:
		if product == null:
			continue

		if not checkout_grid.add_item(product):
			push_warning(
				"CheckoutGrid could not fit product: "
				+ product.display_name
			)

	_sync_grid_to_clients(checkout_grid)
	# Show the checkout bag when the shopper places their items.
	set_bag_visible.rpc(not checkout_grid.cart_items.is_empty())
	
	if not unscanned_items.is_empty():
		_start_checkout_wait()
	else:
		_stop_checkout_wait()


func customer_arrived_at_bag_point(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return

	if customer != checkout_customer:
		return
	
	_stop_checkout_wait()
	
	# Shopper collects their bag.
	_clear_grid(bag_grid)
	_sync_grid_to_clients(bag_grid)

	# Release checkout for the next shopper.
	checkout_customer = null

	if waiting_customers.is_empty():
		return

	# Promote the first waiting shopper.
	checkout_customer = waiting_customers.pop_front()

	_move_customer(
		checkout_customer,
		checkout_point
	)

	# Move remaining shoppers forward in the queue.
	for i: int in range(waiting_customers.size()):
		_move_customer(
			waiting_customers[i],
			waiting_points[i]
		)



func can_scan_ai_product(product: ProductData) -> bool:
	if not multiplayer.is_server():
		return false

	if checkout_customer == null or product == null:
		return false

	for unscanned_product: ProductData in unscanned_items:
		if unscanned_product.resource_path == product.resource_path:
			return true

	return false


func scan_ai_product(product: ProductData) -> bool:
	if not can_scan_ai_product(product):
		return false

	if not bag_grid.add_item(product):
		return false

	for i: int in range(unscanned_items.size()):
		if unscanned_items[i].resource_path == product.resource_path:
			unscanned_items.remove_at(i)
			break

	_sync_grid_to_clients(bag_grid)
	_play_scanner_beep.rpc()
	_reset_checkout_wait()

	if unscanned_items.is_empty() and checkout_customer != null:
		_stop_checkout_wait()
		checkout_customer.checkout_scanning_completed()

	return true


func _clear_grid(grid: CartGrid) -> void:
	while grid.has_items():
		grid.take_item_at_index(0)

	if grid == bag_grid and multiplayer.is_server():
		set_bag_visible.rpc(false)


func _sync_grid_to_clients(grid: CartGrid) -> void:
	if not multiplayer.is_server():
		return

	var product_paths: Array[String] = []

	for product: ProductData in grid.cart_items:
		if product == null:
			product_paths.append("")
		else:
			product_paths.append(product.resource_path)

	grid.sync_cart_state.rpc(product_paths)



func customer_finished_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return

	if customer != checkout_customer:
		return
	
	_stop_checkout_wait()
	
	# Shopper walks to BagPoint to collect their products.
	customer.set_navigation_target(bag_point.global_position)
	customer.state = customer.State.BAGGING

	# Clear the checkout grid, but leave BagGrid untouched.
	_clear_grid(checkout_grid)
	_sync_grid_to_clients(checkout_grid)

	unscanned_items.clear()

	# Do not advance the queue yet.
	# The shopper must collect their bag first.



func _move_customer(
		customer: ShopperAI,
		target_point: Marker3D
	) -> void:
	if not is_instance_valid(customer):
		return

	customer.set_navigation_target(target_point.global_position)

	if target_point == checkout_point:
		customer.state = customer.State.CHECKOUT
	else:
		customer.state = customer.State.CHECKOUT_LINEUP



@rpc("authority", "call_local", "reliable")
func set_bag_visible(should_show: bool) -> void:
	bag_mesh.visible = should_show


# Bell functions
func _get_game_minutes() -> int:
	return (
		DayManager.current_day * 1440
		+ DayManager.current_hour * 60
		+ DayManager.current_minute
	)


func _start_checkout_wait() -> void:
	if not multiplayer.is_server():
		return

	checkout_active = true
	last_scan_game_minute = _get_game_minutes()


func _reset_checkout_wait() -> void:
	if not multiplayer.is_server():
		return

	last_scan_game_minute = _get_game_minutes()


func _stop_checkout_wait() -> void:
	checkout_active = false


func _check_checkout_bell() -> void:
	if not multiplayer.is_server():
		return

	if not checkout_active:
		return

	if checkout_customer == null:
		return

	if _get_game_minutes() - last_scan_game_minute < BELL_WAIT_MINUTES:
		return

	_reset_checkout_wait()
	_play_desk_bell.rpc()


@rpc("authority", "call_local", "reliable")
func _play_desk_bell() -> void:
	desk_bell.play()


@rpc("authority", "call_local", "reliable")
func _play_scanner_beep() -> void:
	if not is_instance_valid(scanner_beep_player):
		return

	scanner_beep_player.pitch_scale = randf_range(1.0, 1.05)
	scanner_beep_player.play()
