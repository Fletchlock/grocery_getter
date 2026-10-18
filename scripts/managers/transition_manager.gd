
extends Node

const ORANGE_SURVIVAL_SCENE: String = "res://scenes/levels/orange_survival.tscn"
const GROCERY_STORE_SCENE: String = "res://scenes/levels/third_person_level.tscn"

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

	# Save all physical restock boxes before unloading the store.
	StoreManager.capture_restock_boxes()

	_load_level_on_all_peers.rpc(ORANGE_SURVIVAL_SCENE)


func return_to_grocery_store() -> void:
	if not multiplayer.is_server():
		return

	if transitioning:
		return

	transitioning = true
	_load_level_on_all_peers.rpc(GROCERY_STORE_SCENE)

	_complete_day_after_return()


func _complete_day_after_return() -> void:
	# Give the return transition time to finish locally.
	await get_tree().process_frame
	await get_tree().process_frame

	if DayManager._day_transition_started:
		DayManager.complete_minigame_and_advance_day()



@rpc("authority", "call_local", "reliable")
func _load_level_on_all_peers(level_path: String) -> void:
	_perform_transition(level_path)


func _perform_transition(level_path: String) -> void:
	transitioning = true

	fade_rect.modulate.a = 1.0

	# Allow the black overlay to render.
	await get_tree().process_frame

	LevelManager.load_level(level_path)

	await get_tree().process_frame

	fade_rect.modulate.a = 0.0
	transitioning = false
