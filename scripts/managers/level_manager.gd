extends Node

# CURRENT LEVEL
# Keeps a reference to the level currently loaded into the game.
# If we load another level later, we can remove the old one first.
var current_level: Node = null

# LOAD LEVEL
# Loads a level into the Game node.

func load_level(level_path: String) -> void:
	var level_scene: PackedScene = load(level_path) as PackedScene

	if level_scene == null:
		push_error("Could not load level: " + level_path)
		return

	# Remove the previous level.
	if current_level != null:
		current_level.queue_free()
		current_level = null


	# Create and load the new level.
	current_level = level_scene.instantiate()

	var main: Node = get_tree().current_scene
	var game: Node = main.get_node("Game")

	game.add_child(current_level)

	# Minigames manage their own HUDs.
	if level_path == TransitionManager.ORANGE_SURVIVAL_SCENE:
		return

	# Normal grocery store HUD.
	var hud_scene: PackedScene = load(
		"res://scenes/UI/day_time_hud.tscn"
	) as PackedScene

	if hud_scene == null:
		push_error("Could not load DayTimeHUD scene.")
		return

	var hud: Control = hud_scene.instantiate() as Control
	current_level.add_child(hud)

	

func unload_level() -> void:
	if current_level:
		print("LevelManager: Unloading current level.")
		current_level.queue_free()
		current_level = null
