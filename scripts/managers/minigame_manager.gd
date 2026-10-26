
extends Node

const MINIGAMES: Array[Dictionary] = [
	{
		"id": "orange_survival",
		"scene_path": "res://scenes/levels/orange_survival.tscn",
		"minimum_day": 1,
		"enabled": true
	},
	{
		"id": "conveyor_showdown",
		"scene_path": "res://scenes/levels/conveyor_showdown.tscn",
		"minimum_day": 1,
		"enabled": true
	}
]

var rotation_queue: Array[String] = []
var last_minigame: String = ""


func is_minigame_scene(scene_path: String) -> bool:
	for game: Dictionary in MINIGAMES:
		if str(game["scene_path"]) == scene_path:
			return true

	return false


func get_eligible_minigames(day: int) -> Array[String]:
	var eligible: Array[String] = []

	for game: Dictionary in MINIGAMES:
		if not bool(game["enabled"]):
			continue

		if day < int(game["minimum_day"]):
			continue

		var scene_path: String = str(game["scene_path"])

		if not ResourceLoader.exists(scene_path):
			push_warning("Missing minigame scene: " + scene_path)
			continue

		eligible.append(str(game["id"]))

	return eligible


func get_next_minigame(day: int) -> String:
	if not multiplayer.is_server():
		return ""

	var eligible: Array[String] = get_eligible_minigames(day)

	if eligible.is_empty():
		push_warning("No eligible minigames for day %d" % day)
		return ""

	# Discard games that are no longer eligible.
	var filtered_queue: Array[String] = []

	for id: String in rotation_queue:
		if eligible.has(id):
			filtered_queue.append(id)

	rotation_queue = filtered_queue

	# Refill the rotation only when exhausted.
	if rotation_queue.is_empty():
		rotation_queue = eligible.duplicate()
		rotation_queue.shuffle()

		# Avoid repeating the last game at the boundary.
		if rotation_queue.size() > 1:
			if rotation_queue[0] == last_minigame:
				var temp: String = rotation_queue[0]
				rotation_queue[0] = rotation_queue[1]
				rotation_queue[1] = temp

	var selected_id: String = rotation_queue.pop_front()
	last_minigame = selected_id

	for game: Dictionary in MINIGAMES:
		if str(game["id"]) == selected_id:
			return str(game["scene_path"])

	return ""
