
extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

const DEFAULT_DISPLAY_MODE: int = Window.MODE_FULLSCREEN
const DEFAULT_RESOLUTION: Vector2i = Vector2i(1920, 1080)
const DEFAULT_MASTER_VOLUME: float = 1.0
const DEFAULT_MUSIC_VOLUME: float = 1.0
const DEFAULT_SFX_VOLUME: float = 1.0

var display_mode: int = DEFAULT_DISPLAY_MODE
var resolution: Vector2i = DEFAULT_RESOLUTION
var master_volume: float = DEFAULT_MASTER_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

const SFX_BUSES: Array[StringName] = [
	&"Footsteps",
	&"SFX",
	&"Rain",
	&"UI",
]


func _ready() -> void:
	load_settings()

	call_deferred("_apply_saved_settings")


func _apply_saved_settings() -> void:
	await get_tree().process_frame

	apply_display_settings()
	apply_audio_settings()

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

	master_volume = float(config.get_value(
		"audio",
		"master_volume",
		DEFAULT_MUSIC_VOLUME
	))
	music_volume = float(config.get_value(
		"audio",
		"music_volume",
		DEFAULT_MUSIC_VOLUME
	))
	sfx_volume = float(config.get_value(
		"audio",
		"sfx_volume",
		DEFAULT_SFX_VOLUME
	))

	master_volume = clampf(music_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)


func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()

	config.set_value("display", "mode", display_mode)
	config.set_value("display", "resolution", resolution)
	config.set_value("audio", "master_volume", music_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)

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


func apply_audio_settings() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)

	for bus_name in SFX_BUSES:
		_set_bus_volume(bus_name, sfx_volume)


func _set_bus_volume(bus_name: StringName, volume: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		push_warning("SettingsManager: Audio bus not found: %s" % bus_name)
		return

	AudioServer.set_bus_volume_linear(bus_index, clampf(volume, 0.0, 1.0))


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume(&"Master", master_volume)


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume(&"Music", music_volume)


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)

	for bus_name in SFX_BUSES:
		_set_bus_volume(bus_name, sfx_volume)
