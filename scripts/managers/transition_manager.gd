
extends Node

const ORANGE_SURVIVAL_SCENE: String = "res://scenes/levels/orange_survival.tscn"

@onready var fade_rect: ColorRect = $CanvasLayer/ColorRect

var transitioning: bool = false


func _ready() -> void:
	fade_rect.modulate.a = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	if event.keycode != KEY_F6:
		return

	if not multiplayer.is_server():
		return

	if transitioning:
		return

	start_orange_survival()


func start_orange_survival() -> void:
	if not multiplayer.is_server():
		return

	if transitioning:
		return

	transitioning = true
	_load_orange_survival.rpc()


@rpc("authority", "call_local", "reliable")
func _load_orange_survival() -> void:
	_perform_transition()


func _perform_transition() -> void:
	fade_rect.modulate.a = 1.0

	# Wait for the black overlay to render.
	await get_tree().process_frame

	LevelManager.load_level(ORANGE_SURVIVAL_SCENE)

	await get_tree().process_frame

	fade_rect.modulate.a = 0.0
	transitioning = false
