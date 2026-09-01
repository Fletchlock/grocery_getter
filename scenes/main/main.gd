extends Node

const STARTING_LEVEL := "res://scenes/levels/TestLevel.tscn"

func _ready() -> void:
	LevelManager.load_level(STARTING_LEVEL)
