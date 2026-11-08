extends Control


const OPTIONS_MENU: PackedScene = preload("res://scenes/menus/options_menu.tscn")

var options_menu: Control = null
var previous_focus_modes: Dictionary = {}

@onready var options_button: Button = $CenterContainer/VBoxContainer/OptionsButton
@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton


func _ready() -> void:
	$CenterContainer/VBoxContainer/ResumeButton.grab_focus.call_deferred()


func _set_pause_menu_focus_enabled(enabled: bool) -> void:
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


func focus_default_button() -> void:
	resume_button.grab_focus.call_deferred()
	
	
func _on_resume_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()

	
func _on_options_button_pressed() -> void:
	if is_instance_valid(options_menu):
		return

	options_menu = OPTIONS_MENU.instantiate() as Control
	add_child(options_menu)

	options_menu.back_requested.connect(_on_options_menu_back_requested)

	_set_pause_menu_focus_enabled(false)


func _on_options_menu_back_requested() -> void:
	if is_instance_valid(options_menu):
		options_menu.queue_free()
		options_menu = null

	_set_pause_menu_focus_enabled(true)
	options_button.grab_focus.call_deferred()
	
	
func _on_main_menu_button_pressed() -> void:
	print("Main Menu pressed")

	await GameManager.return_to_main_menu()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	queue_free()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
