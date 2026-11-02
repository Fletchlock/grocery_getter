
extends Area3D
class_name MopReturnArea


@export var prompt_height: float = 0.25


func _ready() -> void:
	add_to_group("interactable_items")


func get_interaction_prompt_for_player(
	player: CharacterBody3D
) -> String:
	var mop: Mop = get_parent() as Mop

	if mop == null or player == null:
		return ""

	if mop.is_available:
		return ""

	if player.get_multiplayer_authority() != mop.holder_peer_id:
		return ""

	if player.get("held_mop") == null:
		return ""

	return "[E] Return Mop"


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
) -> Vector3:
	return collision_shape.global_position + Vector3.UP * prompt_height


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	var mop: Mop = get_parent() as Mop

	if mop == null:
		return

	if player.has_method("request_return_mop"):
		player.request_return_mop(mop)
