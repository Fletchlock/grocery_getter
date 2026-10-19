extends Control


@onready var continue_game_button: Button = $CenterContainer/VBoxContainer/ContinueGameButton


func _ready() -> void:
	continue_game_button.disabled = not SaveManager.has_save()


func _on_play_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	queue_free()
	LevelManager.load_level("res://scenes/levels/third_person_level.tscn")
	
	

func _on_host_button_pressed() -> void:
	GameManager.game_start_mode = GameManager.GameStartMode.NEW_GAME
	_host_game()


func _on_continue_game_button_pressed() -> void:
	if not SaveManager.has_save():
		return

	GameManager.game_start_mode = GameManager.GameStartMode.CONTINUE_GAME
	_host_game()


func _host_game() -> void:
	get_parent().get_parent().open_lobby()
	GameManager.set_game_state(GameManager.GameState.LOBBY)
	NetworkManager.host_lobby()



func _on_join_button_pressed() -> void:
	print("MAIN: Searching for a game.")
	get_parent().get_parent().open_lobby()
	GameManager.set_game_state(GameManager.GameState.LOBBY)
	NetworkManager.find_and_join_lobby()
	#get_parent().get_parent().open_lobby_browser()


func _on_options_button_pressed() -> void:
	print("Options Pressed")
	
	
func _on_quit_button_pressed() -> void:
	get_tree().quit()
