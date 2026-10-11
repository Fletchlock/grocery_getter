extends Node3D


func get_interaction_prompt_for_player(
	player: CharacterBody3D
) -> String:
	if player == null:
		return ""

	if player.get("held_restock_scanner") == null:
		return ""

	return "[E] Return Restock Scanner"


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if player.get("held_restock_scanner") == null:
		return

	if player.has_method("request_return_restock_scanner"):
		player.request_return_restock_scanner()
