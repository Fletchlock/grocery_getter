extends Control


@onready var continue_game_button: Button = $CenterContainer/VBoxContainer/ContinueGameButton

@onready var save_slot_panel: PanelContainer = $SaveSlotPanel
@onready var slot_title: Label = $SaveSlotPanel/MarginContainer/VBoxContainer/TitleLabel

@onready var slot_buttons: Array[Button] = [
	$SaveSlotPanel/MarginContainer/VBoxContainer/Slot1,
	$SaveSlotPanel/MarginContainer/VBoxContainer/Slot2,
	$SaveSlotPanel/MarginContainer/VBoxContainer/Slot3,
	$SaveSlotPanel/MarginContainer/VBoxContainer/Slot4,
	$SaveSlotPanel/MarginContainer/VBoxContainer/Slot5
]




func _ready() -> void:
	continue_game_button.disabled = not _any_save_exists()
	save_slot_panel.hide()


func _any_save_exists() -> bool:
	for slot: int in range(1, SaveManager.MAX_SAVE_SLOTS + 1):
		if SaveManager.slot_has_save(slot):
			return true

	return false


func _on_play_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	queue_free()
	LevelManager.load_level("res://scenes/levels/third_person_level.tscn")
	

func _on_host_button_pressed() -> void:
	GameManager.game_start_mode = GameManager.GameStartMode.NEW_GAME

	slot_title.text = "SELECT SLOT FOR NEW GAME"
	save_slot_panel.show()
	_refresh_save_slots()


func _on_continue_game_button_pressed() -> void:
	GameManager.game_start_mode = GameManager.GameStartMode.CONTINUE_GAME

	slot_title.text = "SELECT SLOT TO LOAD"
	save_slot_panel.show()
	_refresh_save_slots()


func _host_game() -> void:
	get_parent().get_parent().open_lobby()
	GameManager.set_game_state(GameManager.GameState.LOBBY)
	NetworkManager.host_lobby()



func _on_join_button_pressed() -> void:
	print("MAIN: Searching for a game.")
	get_parent().get_parent().open_lobby()
	GameManager.set_game_state(GameManager.GameState.LOBBY)
	NetworkManager.find_and_join_lobby()
	#get_parent().get_parent().open_lobby_browser()


func _on_options_button_pressed() -> void:
	print("Options Pressed")
	
	
func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _refresh_save_slots() -> void:
	for i: int in range(slot_buttons.size()):
		var slot: int = i + 1
		var button: Button = slot_buttons[i]
		var info: Dictionary = SaveManager.get_slot_info(slot)

		if info.is_empty():
			button.text = "SLOT %d\nEmpty Slot" % slot
			continue

		var created_at: String = _format_save_date(str(info.get("created_at", "")))
		var day: int = int(info.get("day", 1))
		var cash: float = float(info.get("cash", 0.0))

		button.text = (
			"SLOT %d\n%s\nDay %d  |  Cash: $%.2f"
			% [slot, created_at, day, cash]
		)


func _format_save_date(date_string: String) -> String:
	if date_string.is_empty():
		return "Unknown Date"

	var parts: PackedStringArray = date_string.split("T")

	if parts.size() != 2:
		return date_string

	var date_parts: PackedStringArray = parts[0].split("-")
	var time_parts: PackedStringArray = parts[1].split(":")

	if date_parts.size() != 3 or time_parts.size() < 2:
		return date_string

	var months: Array[String] = [
		"January", "February", "March", "April",
		"May", "June", "July", "August",
		"September", "October", "November", "December"
	]

	var year: int = int(date_parts[0])
	var month: int = int(date_parts[1])
	var day: int = int(date_parts[2])
	var hour: int = int(time_parts[0])
	var minute: int = int(time_parts[1])

	if month < 1 or month > 12:
		return date_string

	var period: String = "AM" if hour < 12 else "PM"
	var display_hour: int = hour % 12

	if display_hour == 0:
		display_hour = 12

	return "%s %d, %d - %d:%02d %s" % [
		months[month - 1],
		day,
		year,
		display_hour,
		minute,
		period
	]
