
extends Node

var current_level: Node = null


func unload_level() -> void:
	if current_level == null:
		return

	print("LevelManager: Unloading ", current_level.name)

	var old_level: Node = current_level
	current_level = null

	# Remove it from the scene tree immediately.
	# Actual deletion remains deferred.
	old_level.get_parent().remove_child(old_level)
	old_level.queue_free()


func load_level(level_path: String) -> bool:
	if current_level != null:
		push_error("LevelManager: Unload the old level first.")
		return false

	var level_scene: PackedScene = load(level_path) as PackedScene

	if level_scene == null:
		push_error("Could not load level: " + level_path)
		return false

	var main: Node = get_tree().current_scene
	var game: Node = main.get_node_or_null("Game")

	if game == null:
		push_error("LevelManager: Game node not found.")
		return false

	current_level = level_scene.instantiate()
	game.add_child(current_level)

	if level_path == TransitionManager.ORANGE_SURVIVAL_SCENE:
		return true

	var hud_scene: PackedScene = load(
		"res://scenes/UI/day_time_hud.tscn"
	) as PackedScene

	if hud_scene == null:
		push_error("Could not load DayTimeHUD scene.")
		return false

	var hud: Control = hud_scene.instantiate() as Control
	current_level.add_child(hud)

	return true
