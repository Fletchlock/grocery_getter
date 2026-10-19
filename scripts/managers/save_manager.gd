
extends Node

const SAVE_PATH: String = "user://grocery_getter_save.json"
const SAVE_VERSION: int = 1


func save_game() -> bool:
	if not multiplayer.is_server():
		return false

	var save_data: Dictionary = {
		"save_version": SAVE_VERSION,
		"store": StoreManager.get_save_data(),
		"stock_orders": StockOrderManager.get_save_data(),
		"day": DayManager.get_save_data()
	}

	var file: FileAccess = FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
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

	print("GAME SAVED: ", SAVE_PATH)
	return true


func load_game() -> bool:
	if not multiplayer.is_server():
		return false

	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file: FileAccess = FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
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

	StoreManager.sync_finances()

	print(
		"GAME LOADED: Day ",
		DayManager.current_day,
		" | Cash: $",
		StoreManager.store_cash
	)

	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
