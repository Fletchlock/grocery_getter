
extends Node


const SAVE_DIRECTORY: String = "user://saves"
const LEGACY_SAVE_PATH: String = "user://grocery_getter_save.json"
const SAVE_VERSION: int = 1
const MAX_SAVE_SLOTS: int = 5
const SAVE_PATH: String = LEGACY_SAVE_PATH
const SAVE_ENCRYPTION_KEY_HEX: String = "27248985251193d115ad1c8dc8ca62ee65c83baba2429b2805a7838b372c7df0"

var selected_slot: int = 1
var reset_creation_date_on_save: bool = false


func get_slot_path(slot: int) -> String:
	if slot < 1 or slot > MAX_SAVE_SLOTS:
		return ""

	return "%s/slot_%d.sav" % [SAVE_DIRECTORY, slot]


func select_slot(slot: int) -> bool:
	if slot < 1 or slot > MAX_SAVE_SLOTS:
		return false

	selected_slot = slot
	return true


func slot_has_save(slot: int) -> bool:
	var path: String = get_slot_path(slot)

	if path.is_empty():
		return false

	return FileAccess.file_exists(path)


func get_slot_info(slot: int) -> Dictionary:
	var path: String = get_slot_path(slot)

	if path.is_empty() or not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open_encrypted(
		path,
		FileAccess.READ,
		_get_encryption_key()
	)

	if file == null:
		return {}

	var json: JSON = JSON.new()
	var error: Error = json.parse(file.get_as_text())
	file.close()

	if error != OK or not json.data is Dictionary:
		return {}

	var data: Dictionary = json.data

	if int(data.get("save_version", 0)) != SAVE_VERSION:
		return {}

	var store_data: Dictionary = data.get("store", {})
	var day_data: Dictionary = data.get("day", {})

	return {
		"slot": slot,
		"created_at": str(data.get("updated_at", data.get("created_at", ""))),
		"day": int(day_data.get("current_day", 1)),
		"cash": float(store_data.get("store_cash", 0.0))
	}



func save_game() -> bool:
	if not multiplayer.is_server():
		return false
	
	var save_path: String = get_slot_path(selected_slot)

	if save_path.is_empty():
		return false

	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_DIRECTORY)
	)

	if error != OK:
		push_error("Failed to create save directory.")
		return false

	var existing_info: Dictionary = get_slot_info(selected_slot)
	var created_at: String = Time.get_datetime_string_from_system()

	if not reset_creation_date_on_save and not existing_info.is_empty():
		created_at = str(existing_info.get("created_at", created_at))

	var save_data: Dictionary = {
		"save_version": SAVE_VERSION,
		"created_at": created_at,
		"updated_at": Time.get_datetime_string_from_system(),
		"store": StoreManager.get_save_data(),
		"stock_orders": StockOrderManager.get_save_data(),
		"day": DayManager.get_save_data(),
		"reputation": ReputationManager.get_save_data()
	}

	var file: FileAccess = FileAccess.open_encrypted(
		save_path,
		FileAccess.WRITE,
		_get_encryption_key()
	)

	if file == null:
		push_error(
			"Failed to open save file: ",
			FileAccess.get_open_error()
		)
		return false

	file.store_string(
		JSON.stringify(save_data, "\t")
	)

	file.close()

	reset_creation_date_on_save = false

	print("GAME SAVED: ", save_path)
	return true


func load_game() -> bool:
	if not multiplayer.is_server():
		return false
	
	var save_path: String = get_slot_path(selected_slot)

	if save_path.is_empty():
		return false

	if not FileAccess.file_exists(save_path):
		return false

	var file: FileAccess = FileAccess.open_encrypted(
		save_path,
		FileAccess.READ,
		_get_encryption_key()
	)

	if file == null:
		push_error(
			"Failed to open save file: ",
			FileAccess.get_open_error()
		)
		return false

	var json: JSON = JSON.new()
	var error: Error = json.parse(file.get_as_text())

	file.close()

	if error != OK:
		push_error(
			"Failed to parse save file: ",
			json.get_error_message()
		)
		return false

	if not json.data is Dictionary:
		push_error("Invalid save file format.")
		return false

	var save_data: Dictionary = json.data

	if int(save_data.get("save_version", 0)) != SAVE_VERSION:
		push_error("Unsupported save file version.")
		return false

	StoreManager.load_save_data(
		save_data.get("store", {})
	)

	StockOrderManager.load_save_data(
		save_data.get("stock_orders", {})
	)

	DayManager.load_save_data(
		save_data.get("day", {})
	)
	
	ReputationManager.load_save_data(
		save_data.get("reputation", {})
	)

	StoreManager.sync_finances()

	print(
		"GAME LOADED: Day ",
		DayManager.current_day,
		" | Cash: $",
		StoreManager.store_cash
	)

	return true


func has_save() -> bool:
	return slot_has_save(selected_slot)


func migrate_legacy_save() -> bool:
	if slot_has_save(1):
		print("SAVE MIGRATION: Slot 1 already exists.")
		return true

	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		print("SAVE MIGRATION: No legacy save found.")
		return false

	var source: FileAccess = FileAccess.open(
		LEGACY_SAVE_PATH,
		FileAccess.READ
	)

	if source == null:
		push_error("SAVE MIGRATION: Cannot read legacy save.")
		return false

	var json: JSON = JSON.new()
	var error: Error = json.parse(source.get_as_text())
	source.close()

	if error != OK or not json.data is Dictionary:
		push_error("SAVE MIGRATION: Invalid legacy save.")
		return false

	var data: Dictionary = json.data

	if int(data.get("save_version", 0)) != SAVE_VERSION:
		push_error("SAVE MIGRATION: Unsupported save version.")
		return false

	# The old save has no original creation timestamp.
	# Record the migration date instead.
	data["created_at"] = Time.get_datetime_string_from_system()

	error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_DIRECTORY)
	)

	if error != OK:
		push_error("SAVE MIGRATION: Cannot create save directory.")
		return false

	var destination: FileAccess = FileAccess.open(
		get_slot_path(1),
		FileAccess.WRITE
	)

	if destination == null:
		push_error("SAVE MIGRATION: Cannot create Slot 1.")
		return false

	destination.store_string(JSON.stringify(data, "\t"))
	destination.close()

	print("SAVE MIGRATION: Legacy save copied to Slot 1.")
	return true

func _get_encryption_key() -> PackedByteArray:
	return SAVE_ENCRYPTION_KEY_HEX.hex_decode()
