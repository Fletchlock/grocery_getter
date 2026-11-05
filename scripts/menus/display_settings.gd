extends PanelContainer


@onready var mode_option: OptionButton = $MarginContainer/VBoxContainer/DisplayModeContainer/ModeOption
@onready var resolution_option: OptionButton = $MarginContainer/VBoxContainer/ResolutionContainer/ResolutionOption
@onready var apply_button: Button = $MarginContainer/VBoxContainer/ApplyButton


enum DisplayMode {
	FULLSCREEN,
	WINDOWED,
	BORDERLESS
}


const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]


func _ready() -> void:
	_populate_display_modes()
	_populate_resolutions()

	mode_option.item_selected.connect(_on_mode_selected)
	apply_button.pressed.connect(_on_apply_pressed)

	_sync_current_settings()


func _populate_display_modes() -> void:
	mode_option.clear()

	mode_option.add_item("Fullscreen", DisplayMode.FULLSCREEN)
	mode_option.add_item("Windowed", DisplayMode.WINDOWED)
	mode_option.add_item("Borderless Fullscreen", DisplayMode.BORDERLESS)


func _populate_resolutions() -> void:
	resolution_option.clear()

	for resolution: Vector2i in RESOLUTIONS:
		resolution_option.add_item(
			"%d x %d" % [resolution.x, resolution.y]
		)


func _sync_current_settings() -> void:
	match SettingsManager.display_mode:
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			mode_option.select(DisplayMode.FULLSCREEN)

		Window.MODE_FULLSCREEN:
			mode_option.select(DisplayMode.BORDERLESS)

		Window.MODE_WINDOWED, Window.MODE_MAXIMIZED:
			mode_option.select(DisplayMode.WINDOWED)

		_:
			mode_option.select(DisplayMode.BORDERLESS)

	var saved_resolution: Vector2i = SettingsManager.resolution
	var resolution_index: int = -1

	for i: int in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == saved_resolution:
			resolution_index = i
			break

	if resolution_index >= 0:
		resolution_option.select(resolution_index)
	else:
		resolution_option.select(-1)

	_update_resolution_availability()


func _on_mode_selected(_index: int) -> void:
	_update_resolution_availability()


func _update_resolution_availability() -> void:
	var is_windowed: bool = (
		mode_option.get_selected_id() == DisplayMode.WINDOWED
	)

	resolution_option.disabled = not is_windowed

	if is_windowed:
		# Restore the preferred windowed resolution.
		var saved_resolution: Vector2i = SettingsManager.resolution

		for i: int in range(RESOLUTIONS.size()):
			if RESOLUTIONS[i] == saved_resolution:
				resolution_option.select(i)
				return

	else:
		# Display the actual fullscreen resolution.
		var screen: int = get_window().current_screen
		var screen_size: Vector2i = DisplayServer.screen_get_size(screen)

		# Check whether the resolution is already listed.
		for i: int in range(RESOLUTIONS.size()):
			if RESOLUTIONS[i] == screen_size:
				resolution_option.select(i)
				return

		# Add it if the monitor uses a resolution not in our list.
		resolution_option.add_item(
			"%d x %d" % [screen_size.x, screen_size.y]
		)

		resolution_option.select(resolution_option.item_count - 1)


func _on_apply_pressed() -> void:
	var selected_mode: int = mode_option.get_selected_id()

	match selected_mode:
		DisplayMode.FULLSCREEN:
			SettingsManager.display_mode = Window.MODE_EXCLUSIVE_FULLSCREEN

		DisplayMode.BORDERLESS:
			SettingsManager.display_mode = Window.MODE_FULLSCREEN

		DisplayMode.WINDOWED:
			SettingsManager.display_mode = Window.MODE_WINDOWED

	if selected_mode == DisplayMode.WINDOWED:
		if resolution_option.selected >= 0:
			if resolution_option.selected < RESOLUTIONS.size():
				SettingsManager.resolution = RESOLUTIONS[resolution_option.selected]

	SettingsManager.apply_display_settings()
	SettingsManager.save_settings()

	_sync_current_settings()

	print("DISPLAY SETTINGS SAVED")
