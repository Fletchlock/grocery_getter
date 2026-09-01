extends Node

enum GameState {
	MAIN_MENU,
	PLAYING,
	PAUSED,
	GAME_OVER
}

var current_state: GameState = GameState.MAIN_MENU


func set_game_state(new_state: GameState) -> void:
	current_state = new_state
