extends Node

# CURRENT LEVEL
# Keeps a reference to the level currently loaded into the game.
# If we load another level later, we can remove the old one first.
var current_level: Node = null

# LOAD LEVEL
# Loads a level into the Game node.
func load_level(level_path: String) -> void:

	# Remove the currently loaded level, if there is one.
	if current_level:
		current_level.queue_free()
		current_level = null


	# Load the requested level scene.
	var level_scene := load(level_path) as PackedScene


	# Make sure the level actually loaded.

	if level_scene == null:
		push_error("Could not load level: " + level_path)
		return


	# Create an instance of the level.
	# At this point the level exists in memory, but isn't yet part of the
	# running scene tree.
	current_level = level_scene.instantiate()


	# Find our Game node.
	# Your current project structure has the loaded level placed underneath
	# the Game node.
	var main := get_tree().current_scene
	var game := main.get_node("Game")


	# Add the level to the Game node.
	game.add_child(current_level)


func unload_level() -> void:
	if current_level:
		print("LevelManager: Unloading current level.")
		current_level.queue_free()
		current_level = null
