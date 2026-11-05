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
	var window: Window = get_window()

	match window.mode:
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			mode_option.select(DisplayMode.FULLSCREEN)

		Window.MODE_FULLSCREEN:
			mode_option.select(DisplayMode.BORDERLESS)

		Window.MODE_WINDOWED, Window.MODE_MAXIMIZED:
			mode_option.select(DisplayMode.WINDOWED)

	_update_resolution_availability()

	var current_size: Vector2i = window.size

	for i: int in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == current_size:
			resolution_option.select(i)
			return

	resolution_option.select(3)


func _on_mode_selected(_index: int) -> void:
	_update_resolution_availability()


func _update_resolution_availability() -> void:
	resolution_option.disabled = (
		mode_option.get_selected_id() != DisplayMode.WINDOWED
	)


func _on_apply_pressed() -> void:
	var window: Window = get_window()
	var selected_mode: int = mode_option.get_selected_id()

	match selected_mode:
		DisplayMode.FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN

		DisplayMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false

			var resolution: Vector2i = RESOLUTIONS[
				resolution_option.selected
			]

			var screen: int = window.current_screen
			var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen)

			if resolution.x >= usable_rect.size.x or resolution.y >= usable_rect.size.y:
				window.mode = Window.MODE_MAXIMIZED
			else:
				window.size = resolution
				var centered_position: Vector2 = (
					Vector2(usable_rect.position)
					+ Vector2(usable_rect.size - window.size) / 2.0
				)

				window.position = Vector2i(centered_position.round())

		DisplayMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN

	_sync_current_settings()
