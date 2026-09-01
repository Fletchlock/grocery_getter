extends Control

func _on_new_game_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	queue_free()
	LevelManager.load_level("res://scenes/third_person_level.tscn")
	
	
func _on_options_button_pressed() -> void:
	print("Options Pressed")
	
	
func _on_quit_button_pressed() -> void:
	get_tree().quit()
