
extends Control


# The focus button for gamepad, keyboard and mouse.
@onready var new_game_button: Button = $CenterContainer/VBoxContainer/NewGameButton
@onready var main_continue_button: Button = $CenterContainer/VBoxContainer/ContinueGameButton
@onready var main_join_button: Button = $CenterContainer/VBoxContainer/JoinButton

# Menu navigation
@onready var save_slot_back_button: Button = $SaveSlotPanel/MarginContainer/VBoxContainer/BackButton

@onready var play_mode_panel: PanelContainer = $PlayModePanel
@onready var single_player_button: Button = $PlayModePanel/VBoxContainer/HBoxContainer/SinglePlayButton
@onready var multiplayer_button: Button = $PlayModePanel/VBoxContainer/HBoxContainer/MultiplayerButton
@onready var play_mode_back_button: Button = $PlayModePanel/VBoxContainer/BackButton
@onready var menu_blur: ColorRect = $MenuBackBuffer/MenuBlur

var blur_tween: Tween = null

# Options
const OPTIONS_MENU: PackedScene = preload("res://scenes/menus/options_menu.tscn")

var options_menu: Control = null

# Focus dictonaries for button focus
var previous_focus_modes: Dictionary = {}
var save_slot_previous_focus_modes: Dictionary = {}
var privacy_previous_focus_modes: Dictionary = {}
var play_mode_previous_focus_modes: Dictionary = {}

@onready var main_options_button: Button = $CenterContainer/VBoxContainer/OptionsButton

# Continue game
@onready var continue_game_button: Button = $CenterContainer/VBoxContainer/ContinueGameButton

# Save games
@onready var save_slot_panel: PanelContainer = $SaveSlotPanel
@onready var slot_title: Label = $SaveSlotPanel/MarginContainer/VBoxContainer/TitleLabel

# Save Slots
@onready var slot_buttons: Array[Button] = [
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow1/Slot1,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow2/Slot2,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow3/Slot3,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow4/Slot4,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow5/Slot5
]

@onready var delete_buttons: Array[Button] = [
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow1/Delete1,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow2/Delete2,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow3/Delete3,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow4/Delete4,
	$SaveSlotPanel/MarginContainer/VBoxContainer/SlotRow5/Delete5
]

@onready var delete_confirmation: ConfirmationDialog = $DeleteConfirmation

var pending_delete_slot: int = -1

@onready var overwrite_confirmation: ConfirmationDialog = $OverwriteConfirmation

@onready var host_privacy_panel: PanelContainer = $HostPrivacyPanel
@onready var friends_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/FriendsButton
@onready var invite_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/InviteButton
@onready var privacy_back_button: Button = $HostPrivacyPanel/MarginContainer/VBoxContainer/BackButton

var pending_overwrite_slot: int = -1


func _ready() -> void:
	# Menu music
	MusicManager.player.stream = MusicManager.intro
	MusicManager.player.play()
	
	# Focus on this button
	new_game_button.grab_focus.call_deferred()
	
	# Options
	
	single_player_button.pressed.connect(_on_single_player_button_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	
	continue_game_button.visible = _any_save_exists()

	#Save game slots
	save_slot_panel.hide()
	host_privacy_panel.hide()
	
	# Menu navigation
	play_mode_panel.hide()

	save_slot_back_button.pressed.connect(_on_save_slot_back_pressed)
	play_mode_back_button.pressed.connect(_on_play_mode_back_pressed)
	
	friends_button.pressed.connect(_on_friends_button_pressed)
	invite_button.pressed.connect(_on_invite_button_pressed)
	privacy_back_button.pressed.connect(_on_privacy_back_button_pressed)

	overwrite_confirmation.add_theme_font_size_override("title_font_size", 26)
	overwrite_confirmation.get_label().add_theme_font_size_override("font_size", 24)
	overwrite_confirmation.get_ok_button().add_theme_font_size_override("font_size", 24)
	overwrite_confirmation.get_cancel_button().add_theme_font_size_override("font_size", 24)
	
	var submenu_panels: Array[Control] = [
		save_slot_panel,
		play_mode_panel,
		host_privacy_panel
	]

	for panel: Control in submenu_panels:
		panel.visibility_changed.connect(_on_submenu_visibility_changed)

	menu_blur.modulate.a = 1.0

	var shader_material: ShaderMaterial = menu_blur.material as ShaderMaterial

	if shader_material != null:
		shader_material.set_shader_parameter("blur_amount", 0.0)
		shader_material.set_shader_parameter("darkness", 0.0)

	menu_blur.show()
	menu_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for i: int in range(delete_buttons.size()):
		var slot: int = i + 1
		delete_buttons[i].pressed.connect(_on_delete_slot_pressed.bind(slot))

	delete_confirmation.confirmed.connect(_on_delete_confirmation_confirmed)
	delete_confirmation.canceled.connect(_on_delete_confirmation_canceled)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if event.is_echo():
		return

	if delete_confirmation.visible or overwrite_confirmation.visible:
		return

	if host_privacy_panel.visible:
		_on_privacy_back_button_pressed()
	elif play_mode_panel.visible:
		_on_play_mode_back_pressed()
	elif save_slot_panel.visible:
		_on_save_slot_back_pressed()
	else:
		return

	get_viewport().set_input_as_handled()


func _set_main_menu_focus_enabled(enabled: bool) -> void:
	var buttons: Array[Node] = find_children("*", "BaseButton", true, false)

	for node: Node in buttons:
		var button: BaseButton = node as BaseButton

		if button == null:
			continue

		if is_instance_valid(options_menu) and options_menu.is_ancestor_of(button):
			continue

		if not enabled:
			previous_focus_modes[button] = button.focus_mode
			button.focus_mode = Control.FOCUS_NONE
		elif previous_focus_modes.has(button):
			button.focus_mode = previous_focus_modes[button]

	if enabled:
		previous_focus_modes.clear()


func _update_menu_blur() -> void:
	var should_blur: bool = (
		save_slot_panel.visible
		or play_mode_panel.visible
		or host_privacy_panel.visible
		or is_instance_valid(options_menu)
	)
	
	menu_blur.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if should_blur
		else Control.MOUSE_FILTER_IGNORE
	)

	if blur_tween != null:
		blur_tween.kill()

	var shader_material: ShaderMaterial = menu_blur.material as ShaderMaterial

	if shader_material == null:
		return

	# Keep the overlay visible so the shader can animate.
	menu_blur.show()
	menu_blur.modulate.a = 1.0

	blur_tween = create_tween()
	blur_tween.set_parallel(true)
	blur_tween.set_trans(Tween.TRANS_SINE)
	blur_tween.set_ease(Tween.EASE_IN_OUT)

	blur_tween.tween_method(
		func(value: float) -> void:
			shader_material.set_shader_parameter("blur_amount", value),
		float(shader_material.get_shader_parameter("blur_amount")),
		2.5 if should_blur else 0.0,
		0.4
	)

	blur_tween.tween_method(
		func(value: float) -> void:
			shader_material.set_shader_parameter("darkness", value),
		float(shader_material.get_shader_parameter("darkness")),
		0.25 if should_blur else 0.0,
		0.4
	)


func _on_submenu_visibility_changed() -> void:
	_update_menu_blur()


func _any_save_exists() -> bool:
	for slot: int in range(1, SaveManager.MAX_SAVE_SLOTS + 1):
		if SaveManager.slot_has_save(slot):
			return true

	return false


func _on_save_slot_back_pressed() -> void:
	save_slot_panel.hide()

	_set_save_slot_focus_isolated(false)

	if GameManager.game_start_mode == GameManager.GameStartMode.CONTINUE_GAME:
		if continue_game_button.visible and not continue_game_button.disabled:
			continue_game_button.grab_focus.call_deferred()
		else:
			new_game_button.grab_focus.call_deferred()
	else:
		new_game_button.grab_focus.call_deferred()


func _on_play_mode_back_pressed() -> void:
	play_mode_panel.hide()
	_set_play_mode_focus_isolated(false)

	save_slot_panel.show()
	_set_save_slot_focus_isolated(true)
	_focus_first_save_slot()


func _on_host_button_pressed() -> void:
	GameManager.game_start_mode = GameManager.GameStartMode.NEW_GAME

	slot_title.text = "SELECT SLOT FOR NEW GAME"
	save_slot_panel.show()
	_refresh_save_slots()
	_set_save_slot_focus_isolated(true)
	_focus_first_save_slot()


func _on_single_player_button_pressed() -> void:
	print("MainMenu: Starting single player.")
	print("MainMenu: Selected save slot: ", SaveManager.selected_slot)

	NetworkManager.start_single_player()
	GameManager.start_game()


func _on_multiplayer_button_pressed() -> void:
	play_mode_panel.hide()
	_show_host_privacy()


func _on_continue_game_button_pressed() -> void:
	GameManager.game_start_mode = GameManager.GameStartMode.CONTINUE_GAME

	slot_title.text = "SELECT SLOT TO LOAD"
	save_slot_panel.show()
	_refresh_save_slots()
	_set_save_slot_focus_isolated(true)
	_focus_first_save_slot()


func _host_game() -> void:
	get_parent().get_parent().open_lobby()
	GameManager.set_game_state(GameManager.GameState.LOBBY)

	# Public lobbies only during development.
	NetworkManager.host_lobby()


func _on_join_button_pressed() -> void:
	print("MAIN: Opening lobby browser.")

	get_parent().get_parent().open_lobby_browser()


func focus_join_button() -> void:
	print("MAIN MENU: focus_join_button called")

	main_join_button.focus_mode = Control.FOCUS_ALL
	main_join_button.grab_focus.call_deferred()
	

# Options
func _on_options_button_pressed() -> void:
	if is_instance_valid(options_menu):
		return

	save_slot_panel.hide()
	host_privacy_panel.hide()

	options_menu = OPTIONS_MENU.instantiate() as Control
	add_child(options_menu)

	options_menu.back_requested.connect(_on_options_menu_back_requested)
	options_menu.visibility_changed.connect(_on_submenu_visibility_changed)

	_set_main_menu_focus_enabled(false)
	_update_menu_blur()


func _on_options_menu_back_requested() -> void:
	if is_instance_valid(options_menu):
		options_menu.queue_free()
		options_menu = null

	_set_main_menu_focus_enabled(true)
	main_options_button.grab_focus.call_deferred()
	_update_menu_blur()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _focus_first_save_slot() -> void:
	for button: Button in slot_buttons:
		if not button.disabled:
			button.grab_focus.call_deferred()
			return

	save_slot_back_button.grab_focus.call_deferred()


func _refresh_save_slots() -> void:
	for i: int in range(slot_buttons.size()):
		var slot: int = i + 1
		var button: Button = slot_buttons[i]
		var info: Dictionary = SaveManager.get_slot_info(slot)
		delete_buttons[i].disabled = not SaveManager.slot_has_save(slot)
		delete_buttons[i].focus_mode = (
			Control.FOCUS_NONE if delete_buttons[i].disabled
			else Control.FOCUS_ALL
		)

		if info.is_empty():
			button.text = "SLOT %d\nEmpty Slot" % slot
			button.disabled = (
				GameManager.game_start_mode
				== GameManager.GameStartMode.CONTINUE_GAME
			)
			button.focus_mode = (
				Control.FOCUS_NONE if button.disabled
				else Control.FOCUS_ALL
			)
			continue

		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL

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
	_show_play_mode()


func _set_save_slot_focus_isolated(isolated: bool) -> void:
	var buttons: Array[Node] = find_children("*", "BaseButton", true, false)

	for node: Node in buttons:
		var button: BaseButton = node as BaseButton

		if button == null:
			continue

		# Keep Save Slot buttons focusable.
		if save_slot_panel.is_ancestor_of(button):
			continue

		# Keep confirmation dialog buttons focusable.
		if delete_confirmation.is_ancestor_of(button):
			continue

		if overwrite_confirmation.is_ancestor_of(button):
			continue

		if isolated:
			if not save_slot_previous_focus_modes.has(button):
				save_slot_previous_focus_modes[button] = button.focus_mode

			button.focus_mode = Control.FOCUS_NONE

		elif save_slot_previous_focus_modes.has(button):
			button.focus_mode = save_slot_previous_focus_modes[button]

	if not isolated:
		save_slot_previous_focus_modes.clear()


func _on_overwrite_confirmation_confirmed() -> void:
	if pending_overwrite_slot < 1:
		return

	var slot: int = pending_overwrite_slot
	pending_overwrite_slot = -1

	if not SaveManager.select_slot(slot):
		return

	GameManager.game_start_mode = GameManager.GameStartMode.NEW_GAME

	print("NEW GAME: Overwrite approved for Slot ", slot)

	_show_play_mode()


func _on_delete_slot_pressed(slot: int) -> void:
	if not SaveManager.slot_has_save(slot):
		return

	pending_delete_slot = slot

	delete_confirmation.dialog_text = (
		"Are you sure you want to permanently delete Slot %d?\n\n"
		+ "This cannot be undone."
	) % slot

	delete_confirmation.popup_centered()
	delete_confirmation.get_cancel_button().grab_focus.call_deferred()


func _on_delete_confirmation_confirmed() -> void:
	var slot: int = pending_delete_slot
	pending_delete_slot = -1

	if slot < 1:
		return

	if not SaveManager.delete_slot(slot):
		push_warning("Could not delete save slot %d." % slot)
		slot_buttons[slot - 1].grab_focus.call_deferred()
		return

	_refresh_save_slots()
	continue_game_button.visible = _any_save_exists()

	if not slot_buttons[slot - 1].disabled:
		slot_buttons[slot - 1].grab_focus.call_deferred()
	else:
		_focus_first_save_slot()


func _on_delete_confirmation_canceled() -> void:
	var slot: int = pending_delete_slot
	pending_delete_slot = -1

	if slot < 1:
		return

	if not delete_buttons[slot - 1].disabled:
		delete_buttons[slot - 1].grab_focus.call_deferred()
	else:
		_focus_first_save_slot()


func _show_host_privacy() -> void:
	save_slot_panel.hide()
	play_mode_panel.hide()

	_set_play_mode_focus_isolated(false)
	_set_save_slot_focus_isolated(false)

	host_privacy_panel.show()
	_set_privacy_focus_isolated(true)

	friends_button.grab_focus.call_deferred()


func _show_play_mode() -> void:
	save_slot_panel.hide()
	_set_save_slot_focus_isolated(false)

	play_mode_panel.show()
	_set_play_mode_focus_isolated(true)

	_focus_play_mode_button()


func _focus_play_mode_button() -> void:
	single_player_button.grab_focus.call_deferred()


func _set_play_mode_focus_isolated(isolated: bool) -> void:
	var buttons: Array[Node] = find_children("*", "BaseButton", true, false)

	for node: Node in buttons:
		var button: BaseButton = node as BaseButton

		if button == null:
			continue

		if play_mode_panel.is_ancestor_of(button):
			continue

		if isolated:
			if not play_mode_previous_focus_modes.has(button):
				play_mode_previous_focus_modes[button] = button.focus_mode

			button.focus_mode = Control.FOCUS_NONE

		elif play_mode_previous_focus_modes.has(button):
			button.focus_mode = play_mode_previous_focus_modes[button]

	if not isolated:
		play_mode_previous_focus_modes.clear()


func _set_privacy_focus_isolated(isolated: bool) -> void:
	var buttons: Array[Node] = find_children("*", "BaseButton", true, false)

	for node: Node in buttons:
		var button: BaseButton = node as BaseButton

		if button == null:
			continue

		if host_privacy_panel.is_ancestor_of(button):
			continue

		if isolated:
			if not privacy_previous_focus_modes.has(button):
				privacy_previous_focus_modes[button] = button.focus_mode

			button.focus_mode = Control.FOCUS_NONE

		elif privacy_previous_focus_modes.has(button):
			button.focus_mode = privacy_previous_focus_modes[button]

	if not isolated:
		privacy_previous_focus_modes.clear()


func focus_host_privacy_button() -> void:
	if not host_privacy_panel.visible:
		return

	_set_privacy_focus_isolated(true)
	friends_button.grab_focus.call_deferred()


func _on_friends_button_pressed() -> void:
	print("HOST: Creating PUBLIC lobby (development mode).")
	_host_game()


func _on_invite_button_pressed() -> void:
	print("HOST: Creating PUBLIC lobby (development mode).")
	_host_game()


func _on_privacy_back_button_pressed() -> void:
	host_privacy_panel.hide()
	_set_privacy_focus_isolated(false)

	play_mode_panel.show()
	_set_play_mode_focus_isolated(true)

	multiplayer_button.grab_focus.call_deferred()
