
extends Area3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Only the host initiates level transitions.
	if not multiplayer.is_server():
		return

	# Only react to players.
	if not body.is_in_group("player"):
		return

	# Prevent duplicate transitions.
	if TransitionManager.transitioning:
		return

	TransitionManager.return_to_grocery_store()
