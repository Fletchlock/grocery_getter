extends Node

const STARTING_LEVEL := "res://scenes/third_person_level.tscn"

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	LevelManager.load_level(STARTING_LEVEL)
