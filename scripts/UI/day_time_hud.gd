extends Control

@onready var ui_audio_player: AudioStreamPlayer = $AudioStreamPlayer

const audio_order_canceled = preload("res://assets/sounds/836449__feraly__simple-or-cute-ui-ux-interface-cancel-sound.wav")
const audio_order_available = preload("res://assets/sounds/836451__feraly__simple-or-cute-ui-ux-interface-hover-sound.wav") 
const audio_order_accepted = preload("res://assets/sounds/836450__feraly__simple-or-cute-ui-ux-interface-confirm-sound.wav")


@onready var clock_label: Label = $TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ClockLabel
@onready var panel_container_2: PanelContainer = $TopCenterContainer/VBoxContainer/PanelContainer2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var orders_container: VBoxContainer = $OrderNotifications/VBoxContainer
@onready var order_list_container: VBoxContainer = $OrderList/VBoxContainer
@onready var shopper_count: Label = $TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ShopperCount
@onready var reputation_stars: Array[TextureProgressBar] = [
	$TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ReputationContainer/StarsContainer/Star1,
	$TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ReputationContainer/StarsContainer/Star2,
	$TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ReputationContainer/StarsContainer/Star3,
	$TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ReputationContainer/StarsContainer/Star4,
	$TopCenterContainer/VBoxContainer/PanelContainer/HBoxContainer/ReputationContainer/StarsContainer/Star5
]

@export var available_order_scene: PackedScene
@export var active_order_scene: PackedScene
@export var online_order_list_scene: PackedScene
@export var barcode_hud_scene: PackedScene

var shopper_stats: Node3D = null
var available_notifications: Dictionary = {}
var active_notifications: Dictionary = {}
var current_order_list: OnlineOrderList = null
var active_order_cart: CartGrid = null
var barcode_hud: Control = null
var barcode_player: Node = null
var completed_barcode_code: String = ""
var barcode_checkout: Node = null
var saved_scan_combo: int = 0

func _ready() -> void:
	LobbyManager.lobby_player_updated.connect(_on_lobby_player_updated)
	DayManager.clock_updated.connect(_on_clock_updated)
	ReputationManager.reputation_changed.connect(_update_reputation_stars)
	_update_reputation_stars(ReputationManager.store_reputation)
	
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
	if ReputationManager.reputation_changed.is_connected(_update_reputation_stars):
		ReputationManager.reputation_changed.disconnect(_update_reputation_stars)

func _on_lobby_player_updated(_peer_id: int) -> void:
	_update_active_notifications()


func _on_clock_updated(
	_day: int,
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
		store_cash = shopper_stats.store_cash
	
	if shopper_stats != null and is_instance_valid(shopper_stats):
		shopper_count.text = str(shopper_stats.current_shoppers)
	else:
		shopper_count.text = "0"
	
	clock_label.text = "DAY: %02d      %02d:%02d %s      $%.2f" % [
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
		play_ui_sounds(audio_order_available)
		
	for order_id: int in available_notifications.keys():
		if waiting_ids.has(order_id):
			continue

		_remove_available_notification(order_id)


func _update_available_countdowns() -> void:
	for order_id: int in available_notifications.keys():
		var slot: Control = available_notifications[order_id]

		if not is_instance_valid(slot):
			continue

		var notification_text: OrderNotification = (
			slot.get_child(0) as OrderNotification
		)

		notification_text.update_acceptance_countdown()


func _update_reputation_stars(rating: float) -> void:
	for i: int in range(reputation_stars.size()):
		var fill_amount: float = clampf(
			rating - float(i),
			0.0,
			1.0
		)

		reputation_stars[i].value = fill_amount * 100.0


func _add_available_notification(order: OrderData) -> void:
	var slot: Control = Control.new()
	slot.name = "OrderSlot_%d" % order.order_id
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	orders_container.add_child(slot)

	var notification_text: OrderNotification = available_order_scene.instantiate() as OrderNotification
	slot.add_child(notification_text)

	notification_text.order_id = order.order_id
	notification_text.acceptance_deadline = int(
		OrderManager.waiting_order_deadlines.get(
			order.order_id,
			-1
		)
	)

	notification_text.update_acceptance_countdown()
	notification_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)

	# Reserve the notification's height in the VBoxContainer.
	var panel_size: Vector2 = notification_text.get_combined_minimum_size()
	slot.custom_minimum_size = panel_size

	available_notifications[order.order_id] = slot

	notification_text.slide_in()


func _remove_available_notification(order_id: int) -> void:
	if not available_notifications.has(order_id):
		return

	var slot: Control = available_notifications[order_id]
	available_notifications.erase(order_id)

	var notification_text: OrderNotification = slot.get_child(0) as OrderNotification

	notification_text.slide_out()
	await notification_text.removal_finished

	if not is_instance_valid(slot):
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		slot,
		"custom_minimum_size:y",
		0.0,
		notification_text.collapse_duration
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
				var notification_text: OrderNotification = (
					slot.get_child(0) as OrderNotification
				)

				notification_text.update_active_order(order)
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
			var notification_text: OrderNotification = (
				slot.get_child(0) as OrderNotification
			)

			if not notification_text.result_displayed:
				notification_text.show_order_result(order)
				_finish_active_notification(order_id)

	# Handle orders that disappear from the synchronized list.
	for order_id: int in active_notifications.keys():
		if existing_ids.has(order_id):
			continue

		var slot: Control = active_notifications[order_id]
		var notification_text: OrderNotification = (
			slot.get_child(0) as OrderNotification
		)

		if notification_text.result_displayed:
			continue

		_remove_active_notification(order_id)


func _add_active_notification(order: OrderData) -> void:
	var slot: Control = Control.new()
	slot.name = "ActiveOrderSlot_%d" % order.order_id
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	orders_container.add_child(slot)

	var notification_text: OrderNotification = (
		active_order_scene.instantiate() as OrderNotification
	)

	slot.add_child(notification_text)

	notification_text.order_id = order.order_id
	notification_text.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT
	)

	var panel_size: Vector2 = notification_text.get_combined_minimum_size()
	slot.custom_minimum_size = panel_size

	active_notifications[order.order_id] = slot

	notification_text.update_active_order(order)
	notification_text.slide_in()
	
	play_ui_sounds(audio_order_accepted)

func _remove_active_notification(order_id: int) -> void:
	if not active_notifications.has(order_id):
		return

	var slot: Control = active_notifications[order_id]
	active_notifications.erase(order_id)

	var notification_text: OrderNotification = (
		slot.get_child(0) as OrderNotification
	)

	notification_text.slide_out()
	await notification_text.removal_finished

	if not is_instance_valid(slot):
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		slot,
		"custom_minimum_size:y",
		0.0,
		notification_text.collapse_duration
	)

	await tween.finished

	if is_instance_valid(slot):
		slot.queue_free()


func _finish_active_notification(order_id: int) -> void:
	if not active_notifications.has(order_id):
		return

	var slot: Control = active_notifications[order_id]
	var notification_text: OrderNotification = (
		slot.get_child(0) as OrderNotification
	)

	await get_tree().create_timer(
		notification_text.result_display_duration
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
			play_ui_sounds(audio_order_canceled)
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

		if cart_grid is CheckoutGrid:
			continue

		if cart_grid.get_parent() is Checkout:
			continue

		if cart_grid.cart_contents_changed.is_connected(
			_on_order_cart_contents_changed
		):
			continue

		cart_grid.cart_contents_changed.connect(
			_on_order_cart_contents_changed
		)


func _on_order_cart_contents_changed(cart_grid: CartGrid) -> void:
	if cart_grid is CheckoutGrid:
		return

	if cart_grid.get_parent() is Checkout:
		return

	active_order_cart = cart_grid

	if not is_instance_valid(current_order_list):
		return

	current_order_list.set_active_cart(active_order_cart)

	var order: OrderData = OrderManager.get_player_order(
		multiplayer.get_unique_id()
	)

	if order != null:
		current_order_list.update_order(order)


func show_barcode_hud(product_code: String) -> void:
	if not is_instance_valid(barcode_hud):
		if barcode_hud_scene == null:
			push_warning("Barcode HUD scene has not been assigned.")
			return

		barcode_hud = barcode_hud_scene.instantiate() as Control
		barcode_hud.scan_combo = saved_scan_combo
		if barcode_hud == null:
			push_warning("Barcode HUD scene root must be a Control node.")
			return

		barcode_player = get_tree().get_first_node_in_group("local_player")
		if is_instance_valid(barcode_player):
			barcode_player.set_movement_locked(true)
		else:
			push_warning("No local_player found; movement was not locked.")

		add_child(barcode_hud)
		barcode_hud.tree_exited.connect(_on_barcode_hud_exited)
		barcode_hud.code_completed.connect(_on_barcode_code_completed)

	_update_barcode(product_code)


func _update_barcode(product_code: String) -> void:
	if not is_instance_valid(barcode_hud):
		return

	if barcode_hud.has_method("update_display"):
		barcode_hud.update_display(product_code)
	else:
		push_warning("Barcode HUD has no update_display() method.")


func _on_barcode_hud_exited() -> void:
	if is_instance_valid(barcode_player):
		barcode_player.velocity.x = 0.0
		barcode_player.velocity.z = 0.0
		barcode_player.set_movement_locked(false)

	barcode_hud = null
	barcode_player = null

func close_barcode_hud() -> void:
	if is_instance_valid(barcode_hud):
		barcode_hud.queue_free()


func _on_barcode_code_completed(product_code: String) -> void:
	if is_instance_valid(barcode_hud):
		saved_scan_combo = barcode_hud.scan_combo

	if not is_instance_valid(barcode_checkout):
		push_warning("No valid checkout is associated with the barcode HUD.")
		return

	barcode_checkout.complete_produce_code(product_code)


func set_barcode_checkout(checkout: Node) -> void:
	barcode_checkout = checkout


# Audio
func play_ui_sounds(stream : AudioStream) -> void:
	ui_audio_player.stream = stream
	ui_audio_player.play()
