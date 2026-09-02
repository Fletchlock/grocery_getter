extends Node

const PLAYER_SCENE = preload("res://scenes/low_poly_character.tscn")

func _ready() -> void:
	#Spawns the player
	var player = PLAYER_SCENE.instantiate()
	player.global_position = $SpawnPoint.global_position
	add_child(player)
