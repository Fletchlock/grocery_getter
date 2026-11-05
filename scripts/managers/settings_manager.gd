
extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

const DEFAULT_DISPLAY_MODE: int = Window.MODE_FULLSCREEN
const DEFAULT_RESOLUTION: Vector2i = Vector2i(1920, 1080)

var display_mode: int = DEFAULT_DISPLAY_MODE
var resolution: Vector2i = DEFAULT_RESOLUTION


func _ready() -> void:
	load_settings()

	call_deferred("_apply_saved_settings")


func _apply_saved_settings() -> void:
	await get_tree().process_frame

	apply_display_settings()

	print("SETTINGS LOADED:")
	print("  Display Mode: ", display_mode)
	print("  Resolution: ", resolution)
	print("  Actual Window Mode: ", get_tree().root.mode)
	print("  Actual Window Size: ", get_tree().root.size)
	print("  Screen Size: ", DisplayServer.screen_get_size())
	print("  Usable Screen: ", DisplayServer.screen_get_usable_rect())


func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SETTINGS_PATH)

	if error != OK:
		return

	display_mode = int(config.get_value(
		"display",
		"mode",
		DEFAULT_DISPLAY_MODE
	))

	resolution = config.get_value(
		"display",
		"resolution",
		DEFAULT_RESOLUTION
	)

	if display_mode not in [
		Window.MODE_FULLSCREEN,
		Window.MODE_EXCLUSIVE_FULLSCREEN,
		Window.MODE_WINDOWED,
		Window.MODE_MAXIMIZED
	]:
		display_mode = DEFAULT_DISPLAY_MODE

	if resolution.x < 640 or resolution.y < 480:
		resolution = DEFAULT_RESOLUTION


func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()

	config.set_value("display", "mode", display_mode)
	config.set_value("display", "resolution", resolution)

	var error: Error = config.save(SETTINGS_PATH)

	if error != OK:
		push_error("SettingsManager: Failed to save settings: %s" % error_string(error))


func apply_display_settings() -> void:
	var window: Window = get_tree().root

	match display_mode:
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN

		Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_FULLSCREEN

		Window.MODE_WINDOWED, Window.MODE_MAXIMIZED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false

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
