extends Control

func _on_resume_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
	
func _on_options_button_pressed() -> void:
	print("Options Pressed")
	
	
func _on_main_menu_button_pressed() -> void:
	print("Main Menu pressed")
	
	#get_tree().paused = false
	#GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	#LevelManager.load_level("res://scenes/menus/main_menu.tscn")
	#queue_free()
