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
@onready var player_hud: Control = $PlayerHud

@export var available_order_scene: PackedScene
@export var active_order_scene: PackedScene
@export var online_order_list_scene: PackedScene
@export var barcode_hud_scene: PackedScene

@export_group("Product Unlock Notifications")
@export var product_unlock_notification_scene: PackedScene
@export var unlock_notification_interval: float = 1.0
@export var unlock_notification_duration: float = 3.0
@export var max_unlock_notifications: int = 3

var shopper_stats: Node3D = null
var available_notifications: Dictionary = {}
var active_notifications: Dictionary = {}
var unlock_notification_queue: Array[String] = []
var active_unlock_notifications: int = 0
var unlock_queue_running: bool = false
var current_order_list: OnlineOrderList = null
var active_order_cart: CartGrid = null
var barcode_hud: Control = null
var barcode_player: Node = null
var barcode_order_id: int = -1
var completed_barcode_code: String = ""
var barcode_checkout: Node = null
var saved_scan_combo: int = 0
var player_hud_open := false
var player_hud_tween: Tween
var player_hud_player: Node = null
var active_player_hud_submenu: Control = null
var player_hud_menu_history: Array[Control] = []

func _ready() -> void:
	LobbyManager.lobby_player_updated.connect(_on_lobby_player_updated)
	DayManager.clock_updated.connect(_on_clock_updated)
	ReputationManager.reputation_changed.connect(_update_reputation_stars)
	ProductUnlockManager.product_unlocked.connect(_on_product_unlocked)
	_update_reputation_stars(ReputationManager.store_reputation)
	
	# Display the current clock immediately, in case the clock
	# was synchronized before this HUD finished loading.
	_on_clock_updated(
		DayManager.current_day,
		DayManager.current_hour,
		DayManager.current_minute
	)
	
	OrderManager.orders_synced.connect(_update_order_notifications)
	OrderManager.orders_synced.connect(_check_barcode_order_status)
	_update_order_notifications()
	call_deferred("_connect_order_carts")
	
	call_deferred("_position_player_hud")

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
	if ProductUnlockManager.product_unlocked.is_connected(
		_on_product_unlocked
	):
		ProductUnlockManager.product_unlocked.disconnect(
			_on_product_unlocked
		)
	if OrderManager.orders_synced.is_connected(
		_check_barcode_order_status
	):
		OrderManager.orders_synced.disconnect(
			_check_barcode_order_status
		)


func _get_barcode_order() -> OrderData:
	if not is_instance_valid(barcode_checkout):
		return null

	var player: CharacterBody3D = (
		get_tree().get_first_node_in_group("local_player")
		as CharacterBody3D
	)

	if player == null:
		return null

	var order_grid: OrderGrid = (
		get_tree().get_first_node_in_group("online_order_grid")
		as OrderGrid
	)

	if order_grid == null:
		return null

	var peer_id: int = player.get_multiplayer_authority()

	return order_grid.get_checkout_order(peer_id)


func _on_lobby_player_updated(_peer_id: int) -> void:
	_update_active_notifications()

func _on_product_unlocked(
		_save_id: String,
		product_name: String
	) -> void:
	queue_product_unlock(product_name)

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


func queue_product_unlock(product_name: String) -> void:
	if product_name.is_empty():
		return

	unlock_notification_queue.append(product_name)

	if not unlock_queue_running:
		_process_unlock_queue()


func _process_unlock_queue() -> void:
	if unlock_queue_running:
		return

	unlock_queue_running = true

	while not unlock_notification_queue.is_empty():
		if active_unlock_notifications >= max_unlock_notifications:
			await get_tree().process_frame
			continue

		var product_name: String = unlock_notification_queue.pop_front()

		_show_product_unlock_notification(product_name)

		await get_tree().create_timer(
			unlock_notification_interval
		).timeout

	unlock_queue_running = false


func _show_product_unlock_notification(product_name: String) -> void:
	if product_unlock_notification_scene == null:
		push_warning("Product unlock notification scene is not assigned.")
		return

	var slot: Control = Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	orders_container.add_child(slot)

	var unlock_notification: ProductUnlockNotification = (
		product_unlock_notification_scene.instantiate()
		as ProductUnlockNotification
	)

	if unlock_notification == null:
		slot.queue_free()
		push_warning("Invalid product unlock notification scene.")
		return

	slot.add_child(unlock_notification)

	unlock_notification.setup(product_name)
	unlock_notification.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT
	)

	slot.custom_minimum_size = unlock_notification.get_combined_minimum_size()

	active_unlock_notifications += 1

	unlock_notification.slide_in()

	_remove_product_unlock_notification(slot, unlock_notification)


func _remove_product_unlock_notification(
		slot: Control,
		unlock_notification: ProductUnlockNotification
	) -> void:
	await get_tree().create_timer(
		unlock_notification_duration
	).timeout

	if not is_instance_valid(unlock_notification):
		active_unlock_notifications = maxi(
			0,
			active_unlock_notifications - 1
		)
		return

	unlock_notification.slide_out()
	await unlock_notification.removal_finished

	if not is_instance_valid(slot):
		active_unlock_notifications = maxi(
			0,
			active_unlock_notifications - 1
		)
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		slot,
		"custom_minimum_size:y",
		0.0,
		unlock_notification.collapse_duration
	)

	await tween.finished

	if is_instance_valid(slot):
		slot.queue_free()

	active_unlock_notifications = maxi(
		0,
		active_unlock_notifications - 1
	)


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
		if barcode_hud == null:
			push_warning("Barcode HUD scene root must be a Control node.")
			return

		barcode_hud.scan_combo = saved_scan_combo
		barcode_player = get_tree().get_first_node_in_group("local_player")

		if is_instance_valid(barcode_player):
			barcode_player.set_movement_locked(true)
		else:
			push_warning("No local_player found; movement was not locked.")

		add_child(barcode_hud)
		barcode_hud.tree_exited.connect(_on_barcode_hud_exited)
		barcode_hud.code_completed.connect(_on_barcode_code_completed)
	
	var order: OrderData = _get_barcode_order()

	if order != null:
		barcode_order_id = order.order_id
		
	_update_barcode(product_code)


func _check_barcode_order_status() -> void:
	if not is_instance_valid(barcode_hud):
		return

	if barcode_order_id < 0:
		return

	var order: OrderData = OrderManager.get_order(barcode_order_id)

	if order == null or order.state != OrderData.OrderState.ACTIVE:
		print(
			"BARCODE HUD: Order #",
			barcode_order_id,
			" is no longer active. Closing barcode HUD."
		)

		close_barcode_hud()


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
	barcode_order_id = -1
	barcode_checkout = null
	completed_barcode_code = ""

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


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_TAB:
		toggle_player_hud()
		get_viewport().set_input_as_handled()

	elif event.keycode == KEY_ESCAPE and player_hud_open:
		go_back_in_player_hud()
		get_viewport().set_input_as_handled()


func toggle_player_hud() -> void:
	player_hud_open = not player_hud_open

	if player_hud_open:
		reset_player_hud_menu()

	if not is_instance_valid(player_hud_player):
		player_hud_player = get_tree().get_first_node_in_group("local_player")

	if is_instance_valid(player_hud_player):
		player_hud_player.set_movement_locked(player_hud_open)

	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if player_hud_open
		else Input.MOUSE_MODE_CAPTURED
	)

	player_hud.visible = true

	if player_hud_tween and player_hud_tween.is_running():
		player_hud_tween.kill()

	var target_x: float
	if player_hud_open:
		target_x = (size.x - player_hud.size.x) / 2.0
	else:
		target_x = size.x

	player_hud_tween = create_tween()
	player_hud_tween.set_trans(Tween.TRANS_CUBIC)
	player_hud_tween.set_ease(Tween.EASE_OUT)
	player_hud_tween.tween_property(
		player_hud,
		"position:x",
		target_x,
		0.3
	)

	if not player_hud_open:
		player_hud_tween.tween_callback(func() -> void:
			player_hud.visible = false
		)


func _position_player_hud() -> void:
	player_hud.position = Vector2(
		size.x,
		(size.y - player_hud.size.y) / 2.0
	)
	player_hud.visible = false


# Audio
func play_ui_sounds(stream : AudioStream) -> void:
	ui_audio_player.stream = stream
	ui_audio_player.play()


func _on_customize_pressed() -> void:
	open_player_hud_submenu($PlayerHud/CustomizeMenu)


func _on_scanner_scales_pressed() -> void:
	open_player_hud_submenu(
		$PlayerHud/ScannerScalesMenu
	)


func open_player_hud_submenu(submenu: Control) -> void:
	if is_instance_valid(active_player_hud_submenu):
		if active_player_hud_submenu == submenu:
			return

		player_hud_menu_history.append(active_player_hud_submenu)

		# Keep the current menu visible when opening one nested inside it.
		if not active_player_hud_submenu.is_ancestor_of(submenu):
			active_player_hud_submenu.hide()
	else:
		$PlayerHud/VBoxContainer.hide()

	active_player_hud_submenu = submenu
	active_player_hud_submenu.show()


func go_back_in_player_hud() -> void:
	if is_instance_valid(active_player_hud_submenu):
		active_player_hud_submenu.hide()

	while not player_hud_menu_history.is_empty():
		var previous_menu: Control = player_hud_menu_history.pop_back()
		if is_instance_valid(previous_menu):
			active_player_hud_submenu = previous_menu
			active_player_hud_submenu.show()
			return

	active_player_hud_submenu = null

	if $PlayerHud/VBoxContainer.visible:
		toggle_player_hud()
	else:
		$PlayerHud/VBoxContainer.show()


func reset_player_hud_menu() -> void:
	if is_instance_valid(active_player_hud_submenu):
		active_player_hud_submenu.hide()

	for menu: Control in player_hud_menu_history:
		if is_instance_valid(menu):
			menu.hide()

	player_hud_menu_history.clear()
	active_player_hud_submenu = null
	$PlayerHud/VBoxContainer.show()


# TEST FUNCTION

func test_product_unlock_notifications() -> void:
	queue_product_unlock("Bread")
	queue_product_unlock("Cereal")
	queue_product_unlock("Cola")
	queue_product_unlock("Sugar")
	queue_product_unlock("Peas")
