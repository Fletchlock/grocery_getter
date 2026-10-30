
extends Control
class_name OnlineCheckoutDisplay


@export_group("Display Settings")
@export_range(1.0, 30.0, 0.5)
var results_display_duration: float = 5.0

@export_range(12, 64, 1)
var item_font_size: int = 24

@export var correct_color: Color = Color("5af243")
@export var incorrect_color: Color = Color("ff6868")
@export var normal_color: Color = Color.WHITE


@onready var header_label: Label = $PanelContainer/VBoxContainer/HeaderLabel
@onready var scroll_container: ScrollContainer = $PanelContainer/VBoxContainer/ScrollContainer
@onready var item_list: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/ItemList
@onready var separator: HSeparator = $PanelContainer/VBoxContainer/HSeparator
@onready var subtotal_label: Label = $PanelContainer/VBoxContainer/SubtotalLabel
@onready var total_label: Label = $PanelContainer/VBoxContainer/TotalLabel

@onready var checkout_viewport: SubViewport = get_parent() as SubViewport
@onready var checkout_screen: MeshInstance3D = $"../../CheckoutScreen"
@onready var order_grid: OrderGrid = $"../../OrderGrid"


enum DisplayMode {
	STATUS,
	SCANNING,
	RESULTS
}


var display_mode: DisplayMode = DisplayMode.STATUS
var active_order_id: int = -1
var results_order_id: int = -1
var results_timer: Timer


func _ready() -> void:
	_setup_screen_material()

	results_timer = Timer.new()
	results_timer.one_shot = true
	add_child(results_timer)
	results_timer.timeout.connect(_on_results_timer_timeout)

	OrderManager.orders_synced.connect(_refresh_display)
	OrderManager.order_generated.connect(_on_order_changed)
	OrderManager.order_updated.connect(_on_order_changed)
	order_grid.checkout_owner_changed.connect(_refresh_display)
	
	_show_order_status()


func _setup_screen_material() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = checkout_viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	checkout_screen.material_override = material


func _on_order_changed(_order: OrderData) -> void:
	_refresh_display()


func _refresh_display() -> void:
	if display_mode == DisplayMode.RESULTS:
		return

	var owner_id: int = order_grid.order_owner_peer_id

	if owner_id != 0:
		var owned_order: OrderData = OrderManager.get_player_order_any_state(
			owner_id
		)

		if owned_order != null:
			if (
				owned_order.state == OrderData.OrderState.COMPLETED
				and owned_order.checkout_started
			):
				_show_checkout_results(owned_order)
				return

			if owned_order.state == OrderData.OrderState.ACTIVE:
				if owned_order.checkout_started:
					active_order_id = owned_order.order_id
					_show_scanning(owned_order)
					return

	# Also detect completion if ownership was already released.
	if active_order_id != -1:
		var previous_order: OrderData = OrderManager.get_order(
			active_order_id
		)

		if previous_order != null:
			if previous_order.state == OrderData.OrderState.COMPLETED:
				_show_checkout_results(previous_order)
				return

	active_order_id = -1
	_show_order_status()


func _show_order_status() -> void:
	display_mode = DisplayMode.STATUS

	_clear_items()

	header_label.text = "ONLINE ORDERS"
	separator.hide()
	subtotal_label.hide()
	total_label.hide()

	var orders: Array[OrderData] = OrderManager.get_orders()

	if orders.is_empty():
		_add_text_row("NO ORDERS", normal_color)
		return

	for order: OrderData in orders:
		_add_text_row(_get_order_summary(order), normal_color)


func _show_scanning(order: OrderData) -> void:
	display_mode = DisplayMode.SCANNING

	_clear_items()

	header_label.text = "ORDER #%02d - CHECKOUT" % order.order_id

	var scanned_total: float = 0.0

	for product_path: String in order.scanned_items:
		var quantity: int = int(order.scanned_items[product_path])
		var product: ProductData = load(product_path) as ProductData

		if product == null:
			continue

		var price: float = product.product_price * float(quantity)
		scanned_total += price

		_add_text_row(
			"%s x%d    $%.2f" % [
				product.display_name,
				quantity,
				price
			],
			normal_color
		)

	if order.scanned_items.is_empty():
		_add_text_row("READY TO SCAN", normal_color)

	separator.show()
	subtotal_label.show()
	total_label.show()

	subtotal_label.text = "SCANNED TOTAL:"
	total_label.text = "$%.2f" % scanned_total


func _show_checkout_results(order: OrderData) -> void:
	if results_order_id == order.order_id:
		return

	display_mode = DisplayMode.RESULTS
	results_order_id = order.order_id
	active_order_id = -1

	_clear_items()

	header_label.text = "ORDER #%02d - RESULTS" % order.order_id

	for product_path: String in order.checkout_result:
		var result: Dictionary = order.checkout_result[product_path]
		var product: ProductData = load(product_path) as ProductData

		if product == null:
			continue

		var requested: int = int(result.get("requested", 0))
		var scanned: int = int(result.get("scanned", 0))
		var missing: int = int(result.get("missing", 0))
		var excess: int = int(result.get("excess", 0))
		var unordered: bool = bool(result.get("unordered", false))

		var row_text: String = ""
		var row_color: Color = correct_color

		if unordered:
			row_text = "%s x%d - UNORDERED" % [
				product.display_name,
				scanned
			]
			row_color = incorrect_color

		elif missing > 0:
			row_text = "%s %d/%d - MISSING %d" % [
				product.display_name,
				scanned,
				requested,
				missing
			]
			row_color = incorrect_color

		elif excess > 0:
			row_text = "%s %d/%d - EXCESS %d" % [
				product.display_name,
				scanned,
				requested,
				excess
			]
			row_color = incorrect_color

		else:
			row_text = "%s %d/%d - CORRECT" % [
				product.display_name,
				scanned,
				requested
			]

		_add_text_row(row_text, row_color)

	separator.show()
	subtotal_label.show()
	total_label.show()

	subtotal_label.text = "INCORRECT ITEMS: %d" % order.incorrect_item_count

	var final_payout: float = (
		order.current_profit * (1.0 + OrderManager.completion_bonus)
	)

	total_label.text = "PAYOUT: $%.2f" % final_payout

	results_timer.start(results_display_duration)


@rpc("authority", "call_local", "reliable")
func show_finished_order(order_id: int) -> void:
	var order: OrderData = OrderManager.get_order(order_id)

	if order == null:
		return

	if order.state != OrderData.OrderState.COMPLETED:
		return

	_show_checkout_results(order)


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

			var remaining: float = maxf(
				order.time_limit - order.elapsed_time,
				0.0
			)

			var minutes: int = floori(remaining / 60.0)
			var seconds: int = int(remaining) % 60

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


func _add_text_row(value: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", item_font_size)
	label.add_theme_color_override("font_color", color)

	item_list.add_child(label)


func _clear_items() -> void:
	for child: Node in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()

	scroll_container.scroll_vertical = 0


func _on_results_timer_timeout() -> void:
	results_order_id = -1
	display_mode = DisplayMode.STATUS
	_refresh_display()
