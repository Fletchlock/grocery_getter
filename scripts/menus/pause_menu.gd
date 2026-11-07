extends Control


@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton


func _ready() -> void:
	$CenterContainer/VBoxContainer/ResumeButton.grab_focus.call_deferred()


func focus_default_button() -> void:
	resume_button.grab_focus.call_deferred()
	
	
func _on_resume_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
	
func _on_options_button_pressed() -> void:
	print("Options Pressed")
	
	
func _on_main_menu_button_pressed() -> void:
	print("Main Menu pressed")

	await GameManager.return_to_main_menu()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	queue_free()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
