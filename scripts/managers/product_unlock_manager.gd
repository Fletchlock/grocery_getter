
extends Node

signal product_unlocked(
	save_id: String,
	product_name: String
)

signal unlock_state_changed

var unlocked_products: Dictionary = {}
var todays_unlocks: Array[Dictionary] = []

var last_evaluated_day: int = 0
var _registered_displays: Dictionary = {}


func _ready() -> void:
	DayManager.clock_updated.connect(_on_clock_updated)

	if not multiplayer.is_server():
		multiplayer.connected_to_server.connect(
			_on_connected_to_server
		)


func register_display(display: Node3D) -> void:
	var display_id: String = str(display.get("save_id"))

	if display_id.is_empty():
		push_warning("ProductUnlockManager: Display missing save_id.")
		return

	_registered_displays[display_id] = weakref(display)

	_apply_display_state(display)


func unregister_display(display: Node3D) -> void:
	var display_id: String = str(display.get("save_id"))

	if not _registered_displays.has(display_id):
		return

	var reference: WeakRef = _registered_displays[display_id]
	if reference.get_ref() == display:
		_registered_displays.erase(display_id)


func is_product_unlocked(save_id: String) -> bool:
	return unlocked_products.has(save_id)


func _apply_display_state(display: Node3D) -> void:
	var display_id: String = str(display.get("save_id"))
	var initially_locked: bool = bool(display.get("initially_locked"))

	var unlocked: bool = (
		not initially_locked
		or is_product_unlocked(display_id)
	)

	display.set_product_unlocked(unlocked)


func _apply_all_displays() -> void:
	for display_id: String in _registered_displays.keys():
		var reference: WeakRef = _registered_displays[display_id]
		var display: Node3D = reference.get_ref() as Node3D

		if display == null:
			_registered_displays.erase(display_id)
			continue

		_apply_display_state(display)


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	if not multiplayer.is_server():
		return

	if hour != DayManager.STORE_CLOSE_HOUR or minute != 0:
		return

	evaluate_unlocks(day)


func evaluate_unlocks(day: int) -> void:
	if not multiplayer.is_server():
		return

	if day <= last_evaluated_day:
		return

	last_evaluated_day = day
	todays_unlocks.clear()

	var rating: float = ReputationManager.store_reputation

	print(
		"PRODUCT UNLOCKS: Evaluating day %d at rating %.3f"
		% [day, rating]
	)

	for display_id: String in _registered_displays.keys():
		var reference: WeakRef = _registered_displays[display_id]
		var display: Node3D = reference.get_ref() as Node3D

		if display == null:
			_registered_displays.erase(display_id)
			continue

		if not bool(display.get("initially_locked")):
			continue

		if is_product_unlocked(display_id):
			continue

		var required_rating: float = float(
			display.get("unlock_rating")
		)

		if rating < required_rating:
			continue

		var product: ProductData = display.get("product_data") as ProductData

		if product == null:
			continue

		unlocked_products[display_id] = true

		var unlock_info: Dictionary = {
			"save_id": display_id,
			"product_name": product.display_name
		}

		todays_unlocks.append(unlock_info)

		print(
			"PRODUCT UNLOCKED: %s (required %.1f)"
			% [product.display_name, required_rating]
		)

	_apply_all_displays()
	_sync_unlock_state.rpc(
		unlocked_products,
		todays_unlocks,
		last_evaluated_day
	)

	for info: Dictionary in todays_unlocks:
		var save_id: String = str(info["save_id"])
		var product_name: String = str(info["product_name"])

		product_unlocked.emit(save_id, product_name)

		_receive_unlock_notification.rpc(
			save_id,
			product_name
		)

	unlock_state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_unlock_state(
	unlocked: Dictionary,
	new_unlocks: Array[Dictionary],
	evaluated_day: int
) -> void:
	unlocked_products = unlocked.duplicate(true)
	todays_unlocks = new_unlocks.duplicate(true)
	last_evaluated_day = evaluated_day

	_apply_all_displays()
	unlock_state_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _receive_unlock_notification(
	save_id: String,
	product_name: String
) -> void:
	product_unlocked.emit(save_id, product_name)

func _on_connected_to_server() -> void:
	_request_unlock_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_unlock_state() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	_sync_unlock_state.rpc_id(
		peer_id,
		unlocked_products,
		todays_unlocks,
		last_evaluated_day
	)


func get_save_data() -> Dictionary:
	return {
		"unlocked_products": unlocked_products.duplicate(true),
		"last_evaluated_day": last_evaluated_day
	}


func load_save_data(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	unlocked_products = (
		data.get("unlocked_products", {}) as Dictionary
	).duplicate(true)

	last_evaluated_day = int(
		data.get("last_evaluated_day", 0)
	)

	todays_unlocks.clear()

	_apply_all_displays()

	_sync_unlock_state.rpc(
		unlocked_products,
		todays_unlocks,
		last_evaluated_day
	)


func reset_unlocks() -> void:
	if not multiplayer.is_server():
		return

	unlocked_products.clear()
	todays_unlocks.clear()
	last_evaluated_day = 0

	_apply_all_displays()

	_sync_unlock_state.rpc(
		unlocked_products,
		todays_unlocks,
		last_evaluated_day
	)
