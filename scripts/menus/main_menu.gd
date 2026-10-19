
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

@onready var overwrite_confirmation: ConfirmationDialog = $OverwriteConfirmation

@onready var host_privacy_panel: PanelContainer = $HostPrivacyPanel
@onready var friends_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/FriendsButton
@onready var invite_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/InviteButton
@onready var privacy_back_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/BackButton

var pending_overwrite_slot: int = -1


func _ready() -> void:
	continue_game_button.disabled = not _any_save_exists()

	save_slot_panel.hide()
	host_privacy_panel.hide()

	friends_button.pressed.connect(_on_friends_button_pressed)
	invite_button.pressed.connect(_on_invite_button_pressed)
	privacy_back_button.pressed.connect(_on_privacy_back_button_pressed)

	overwrite_confirmation.add_theme_font_size_override("title_font_size", 26)
	overwrite_confirmation.get_label().add_theme_font_size_override("font_size", 24)
	overwrite_confirmation.get_ok_button().add_theme_font_size_override("font_size", 24)
	overwrite_confirmation.get_cancel_button().add_theme_font_size_override("font_size", 24)


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

	# Public lobbies only during development.
	NetworkManager.host_lobby()


func _on_join_button_pressed() -> void:
	print("MAIN: Opening lobby browser.")

	get_parent().get_parent().open_lobby_browser()


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
			button.disabled = (
				GameManager.game_start_mode
				== GameManager.GameStartMode.CONTINUE_GAME
			)
			continue

		button.disabled = false

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


func _on_slot_1_pressed() -> void:
	_select_save_slot(1)


func _on_slot_2_pressed() -> void:
	_select_save_slot(2)


func _on_slot_3_pressed() -> void:
	_select_save_slot(3)


func _on_slot_4_pressed() -> void:
	_select_save_slot(4)


func _on_slot_5_pressed() -> void:
	_select_save_slot(5)


func _select_save_slot(slot: int) -> void:
	var has_save: bool = SaveManager.slot_has_save(slot)

	match GameManager.game_start_mode:
		GameManager.GameStartMode.CONTINUE_GAME:
			if not has_save:
				return

		GameManager.GameStartMode.NEW_GAME:
			if has_save:
				pending_overwrite_slot = slot

				overwrite_confirmation.dialog_text = (
					"Slot %d already contains a saved game.\n\n"
					+ "Starting a new game in this slot will overwrite "
					+ "its existing progress when the new game is saved.\n\n"
					+ "Do you want to continue?"
				) % slot

				overwrite_confirmation.popup_centered()
				return

	if not SaveManager.select_slot(slot):
		return

	print("SELECTED SAVE SLOT: ", slot)
	_show_host_privacy()


func _on_overwrite_confirmation_confirmed() -> void:
	if pending_overwrite_slot < 1:
		return

	var slot: int = pending_overwrite_slot
	pending_overwrite_slot = -1

	if not SaveManager.select_slot(slot):
		return

	GameManager.game_start_mode = GameManager.GameStartMode.NEW_GAME

	print("NEW GAME: Overwrite approved for Slot ", slot)

	_show_host_privacy()


func _show_host_privacy() -> void:
	save_slot_panel.hide()
	host_privacy_panel.show()


func _on_friends_button_pressed() -> void:
	print("HOST: Creating PUBLIC lobby (development mode).")
	_host_game()


func _on_invite_button_pressed() -> void:
	print("HOST: Creating PUBLIC lobby (development mode).")
	_host_game()


func _on_privacy_back_button_pressed() -> void:
	host_privacy_panel.hide()
	save_slot_panel.show()
