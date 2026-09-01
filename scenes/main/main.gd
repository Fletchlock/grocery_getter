extends Node

const STARTING_LEVEL := "res://scenes/third_person_level.tscn"

func _ready() -> void:
	LevelManager.load_level(STARTING_LEVEL)
