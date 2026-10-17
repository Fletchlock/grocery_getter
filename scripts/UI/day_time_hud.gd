extends Control


@onready var clock_label: Label = $TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ClockLabel
@onready var panel_container_2: PanelContainer = $TopCenterContainer/VBoxContainer/PanelContainer2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var orders_container: VBoxContainer = $OrderNotifications/VBoxContainer
@onready var order_list_container: VBoxContainer = $OrderList/VBoxContainer
@onready var shopper_count: Label = $TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ShopperCount

@export var available_order_scene: PackedScene
@export var active_order_scene: PackedScene
@export var online_order_list_scene: PackedScene

var shopper_stats: Node3D = null
var available_notifications: Dictionary = {}
var active_notifications: Dictionary = {}
var current_order_list: OnlineOrderList = null
var active_order_cart: CartGrid = null

func _ready() -> void:
	LobbyManager.lobby_player_updated.connect(_on_lobby_player_updated)
	DayManager.clock_updated.connect(_on_clock_updated)

	# Display the current clock immediately, in case the clock
	# was synchronized before this HUD finished loading.
	_on_clock_updated(
		DayManager.current_day,
		DayManager.current_hour,
		DayManager.current_minute
	)
	
	OrderManager.orders_synced.connect(_update_order_notifications)
	_update_order_notifications()
	call_deferred("_connect_order_carts")

func _process(_delta: float) -> void:
	if shopper_stats == null or not is_instance_valid(shopper_stats):
		shopper_stats = get_tree().get_first_node_in_group("shopper_stats")
		if shopper_stats == null:
			return

	_update_clock_label()


func _exit_tree() -> void:
	if LobbyManager.lobby_player_updated.is_connected(_on_lobby_player_updated):
		LobbyManager.lobby_player_updated.disconnect(_on_lobby_player_updated)
	if DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.disconnect(_on_clock_updated)
	if OrderManager.orders_synced.is_connected(_update_order_notifications):
		OrderManager.orders_synced.disconnect(_update_order_notifications)


func _on_lobby_player_updated(_peer_id: int) -> void:
	_update_active_notifications()


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	_update_clock_label()
	_update_available_countdowns()
		
	# Turn the clock out panel visible when the day is done.
	panel_container_2.modulate.a = 1.0 if not DayManager.clock_running else 0.0

	# Show the restock banner when the ordering window opens.
	if hour == 18 and minute == 0:
		animation_player.play("restock banner in")

	# Hide the restock banner when the ordering window closes.
	elif hour == 20 and minute == 0:
		animation_player.play("restock banner out")


func _update_clock_label() -> void:
	var hour: int = DayManager.current_hour
	var period: String = "AM"
	var display_hour: int = hour

	if display_hour >= 12:
		period = "PM"

	if display_hour == 0:
		display_hour = 12
	elif display_hour > 12:
		display_hour -= 12

	var store_cash: float = 0.0

	if shopper_stats != null and is_instance_valid(shopper_stats):
		store_cash = shopper_stats.total_sales
	
	if shopper_stats != null and is_instance_valid(shopper_stats):
		shopper_count.text = str(shopper_stats.current_shoppers)
	else:
		shopper_count.text = "0"
	
	clock_label.text = "DAY: %02d    TIME: %02d:%02d %s    $%.2f" % [
		DayManager.current_day,
		display_hour,
		DayManager.current_minute,
		period,
		store_cash
	]


func _on_order_changed(_order: OrderData) -> void:
	pass


func _update_order_notifications() -> void:
	_update_available_notifications()
	_update_active_notifications()
	_update_personal_order_list()

func _update_available_notifications() -> void:
	var waiting_ids: Array[int] = []

	for order: OrderData in OrderManager.get_orders():
		if order.state != OrderData.OrderState.WAITING:
			continue

		waiting_ids.append(order.order_id)

		if available_notifications.has(order.order_id):
			continue

		_add_available_notification(order)

	for order_id: int in available_notifications.keys():
		if waiting_ids.has(order_id):
			continue

		_remove_available_notification(order_id)


func _update_available_countdowns() -> void:
	for order_id: int in available_notifications.keys():
		var slot: Control = available_notifications[order_id]

		if not is_instance_valid(slot):
			continue

		var notification: OrderNotification = (
			slot.get_child(0) as OrderNotification
		)

		notification.update_acceptance_countdown()


func _add_available_notification(order: OrderData) -> void:
	var slot: Control = Control.new()
	slot.name = "OrderSlot_%d" % order.order_id
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	orders_container.add_child(slot)

	var notification: OrderNotification = available_order_scene.instantiate() as OrderNotification
	slot.add_child(notification)

	notification.order_id = order.order_id
	notification.acceptance_deadline = int(
		OrderManager.waiting_order_deadlines.get(
			order.order_id,
			-1
		)
	)

	notification.update_acceptance_countdown()
	notification.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)

	# Reserve the notification's height in the VBoxContainer.
	var panel_size: Vector2 = notification.get_combined_minimum_size()
	slot.custom_minimum_size = panel_size

	available_notifications[order.order_id] = slot

	notification.slide_in()


func _remove_available_notification(order_id: int) -> void:
	if not available_notifications.has(order_id):
		return

	var slot: Control = available_notifications[order_id]
	available_notifications.erase(order_id)

	var notification: OrderNotification = slot.get_child(0) as OrderNotification

	notification.slide_out()
	await notification.removal_finished

	if not is_instance_valid(slot):
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		slot,
		"custom_minimum_size:y",
		0.0,
		notification.collapse_duration
	)

	await tween.finished

	if is_instance_valid(slot):
		slot.queue_free()


func _update_active_notifications() -> void:
	var existing_ids: Array[int] = []

	for order: OrderData in OrderManager.get_orders():
		var order_id: int = order.order_id

		if order.state == OrderData.OrderState.ACTIVE:
			existing_ids.append(order_id)

			if active_notifications.has(order_id):
				var slot: Control = active_notifications[order_id]
				var notification: OrderNotification = (
					slot.get_child(0) as OrderNotification
				)

				notification.update_active_order(order)
			else:
				_add_active_notification(order)

		elif (
			order.state == OrderData.OrderState.COMPLETED
			or order.state == OrderData.OrderState.CANCELLED
		):
			if not active_notifications.has(order_id):
				continue

			existing_ids.append(order_id)

			var slot: Control = active_notifications[order_id]
			var notification: OrderNotification = (
				slot.get_child(0) as OrderNotification
			)

			if not notification.result_displayed:
				notification.show_order_result(order)
				_finish_active_notification(order_id)

	# Handle orders that disappear from the synchronized list.
	for order_id: int in active_notifications.keys():
		if existing_ids.has(order_id):
			continue

		var slot: Control = active_notifications[order_id]
		var notification: OrderNotification = (
			slot.get_child(0) as OrderNotification
		)

		if notification.result_displayed:
			continue

		_remove_active_notification(order_id)


func _add_active_notification(order: OrderData) -> void:
	var slot: Control = Control.new()
	slot.name = "ActiveOrderSlot_%d" % order.order_id
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	orders_container.add_child(slot)

	var notification: OrderNotification = (
		active_order_scene.instantiate() as OrderNotification
	)

	slot.add_child(notification)

	notification.order_id = order.order_id
	notification.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT
	)

	var panel_size: Vector2 = notification.get_combined_minimum_size()
	slot.custom_minimum_size = panel_size

	active_notifications[order.order_id] = slot

	notification.update_active_order(order)
	notification.slide_in()


func _remove_active_notification(order_id: int) -> void:
	if not active_notifications.has(order_id):
		return

	var slot: Control = active_notifications[order_id]
	active_notifications.erase(order_id)

	var notification: OrderNotification = (
		slot.get_child(0) as OrderNotification
	)

	notification.slide_out()
	await notification.removal_finished

	if not is_instance_valid(slot):
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		slot,
		"custom_minimum_size:y",
		0.0,
		notification.collapse_duration
	)

	await tween.finished

	if is_instance_valid(slot):
		slot.queue_free()


func _finish_active_notification(order_id: int) -> void:
	if not active_notifications.has(order_id):
		return

	var slot: Control = active_notifications[order_id]
	var notification: OrderNotification = (
		slot.get_child(0) as OrderNotification
	)

	await get_tree().create_timer(
		notification.result_display_duration
	).timeout

	if not is_instance_valid(slot):
		return

	if not active_notifications.has(order_id):
		return

	_remove_active_notification(order_id)


func _update_personal_order_list() -> void:
	var peer_id: int = multiplayer.get_unique_id()
	var order: OrderData = OrderManager.get_player_order(peer_id)

	if order == null:
		if current_order_list != null:
			var old_list: OnlineOrderList = current_order_list
			current_order_list = null

			old_list.slide_out()
			await old_list.animation_tween.finished

			if is_instance_valid(old_list):
				old_list.queue_free()

		return

	if current_order_list != null:
		if current_order_list.order_id == order.order_id:
			current_order_list.set_active_cart(active_order_cart)
			current_order_list.update_order(order)
			return

		current_order_list.queue_free()
		current_order_list = null

	current_order_list = (
		online_order_list_scene.instantiate() as OnlineOrderList
	)

	order_list_container.add_child(current_order_list)
	current_order_list.set_active_cart(active_order_cart)
	current_order_list.setup_order(order)
	current_order_list.slide_in()


func _connect_order_carts() -> void:
	for candidate: Node in get_tree().get_nodes_in_group("cart_grid"):
		var cart_grid: CartGrid = candidate as CartGrid

		if cart_grid == null:
			continue

		if not cart_grid.cart_contents_changed.is_connected(
			_on_order_cart_contents_changed
		):
			cart_grid.cart_contents_changed.connect(
				_on_order_cart_contents_changed
			)


func _on_order_cart_contents_changed(cart_grid: CartGrid) -> void:
	active_order_cart = cart_grid

	if current_order_list == null:
		return

	if not is_instance_valid(current_order_list):
		return

	current_order_list.set_active_cart(active_order_cart)

	var order: OrderData = OrderManager.get_player_order(
		multiplayer.get_unique_id()
	)

	if order != null:
		current_order_list.update_order(order)
