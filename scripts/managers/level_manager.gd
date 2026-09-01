extends Node

var current_level: Node = null


func load_level(level_path: String) -> void:
	if current_level:
		current_level.queue_free()
		current_level = null

	var level_scene := load(level_path) as PackedScene
	
	if level_scene == null:
		push_error("Could not load level: " + level_path)
		return

	current_level = level_scene.instantiate()

	var main := get_tree().current_scene
	var game := main.get_node("Game")

	game.add_child(current_level)
