extends Node

var using_controller: bool = false

const JOYPAD_DEADZONE: float = 0.25
const MOUSE_MOVEMENT_THRESHOLD: float = 2.0


func _ready() -> void:
	GameManager.game_state_changed.connect(_on_game_state_changed)


func _input(event: InputEvent) -> void:
	# Track the controller even outside menus.
	if event is InputEventJoypadButton:
		if event.pressed:
			_set_controller_active()

	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) >= JOYPAD_DEADZONE:
			_set_controller_active()

	elif event is InputEventMouseMotion:
		if event.relative.length() >= MOUSE_MOVEMENT_THRESHOLD:
			_set_mouse_active()

	elif event is InputEventMouseButton:
		if event.pressed:
			_set_mouse_active()


func _is_menu_active() -> bool:
	return (
		GameManager.current_state == GameManager.GameState.MAIN_MENU
		or GameManager.current_state == GameManager.GameState.LOBBY
		or GameManager.current_state == GameManager.GameState.PAUSED
	)


func _set_controller_active() -> void:
	using_controller = true

	if _is_menu_active():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _set_mouse_active() -> void:
	# Ignore mouse movement while captured in gameplay.
	if not _is_menu_active():
		return

	using_controller = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_game_state_changed(_new_state: GameManager.GameState) -> void:
	if not _is_menu_active():
		return

	# Apply the last-used input device immediately.
	if using_controller:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
