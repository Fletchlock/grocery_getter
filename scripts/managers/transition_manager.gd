
extends Node

const ORANGE_SURVIVAL_SCENE: String = "res://scenes/levels/orange_survival.tscn"
const GROCERY_STORE_SCENE: String = "res://scenes/levels/third_person_level.tscn"

@onready var fade_rect: ColorRect = $CanvasLayer/ColorRect

var transitioning: bool = false
var transition_ready_peers: Dictionary = {}
var pending_transition_scene: String = ""


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

	# Capture inventory before the store unloads.
	StoreManager.capture_restock_boxes()

	# Prepare all peers before changing levels.
	_begin_coordinated_transition(ORANGE_SURVIVAL_SCENE)


func return_to_grocery_store() -> void:
	if not multiplayer.is_server():
		return

	if transitioning:
		return

	transitioning = true

	# Prepare all peers before changing levels.
	await _begin_coordinated_transition(GROCERY_STORE_SCENE)
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

	# Allow the new level and its MultiplayerSpawner to initialize.
	await get_tree().process_frame

	# Only the host restores physical inventory.
	if multiplayer.is_server() and level_path == GROCERY_STORE_SCENE:
		StockOrderManager.restore_saved_boxes()

	fade_rect.modulate.a = 0.0
	transitioning = false


@rpc("any_peer", "call_remote", "reliable")
func _acknowledge_transition_ready() -> void:
	if not multiplayer.is_server():
		return

	if not transitioning:
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	transition_ready_peers[peer_id] = true

	print("TRANSITION READY: peer ", peer_id)




@rpc("authority", "call_local", "reliable")
func _prepare_level_transition() -> void:
	# Show the transition overlay.
	fade_rect.modulate.a = 1.0

	# Allow the overlay to render.
	await get_tree().process_frame

	# Clients acknowledge preparation.
	if not multiplayer.is_server():
		_acknowledge_transition_ready.rpc_id(1)




func _begin_coordinated_transition(level_path: String) -> void:
	if not multiplayer.is_server():
		return

	pending_transition_scene = level_path
	transition_ready_peers.clear()

	# Ask every peer to prepare for the transition.
	_prepare_level_transition.rpc()

	# Wait for every connected client to acknowledge.
	while true:
		var all_ready: bool = true

		for peer_id: int in multiplayer.get_peers():
			if not transition_ready_peers.has(peer_id):
				all_ready = false
				break

		if all_ready:
			break

		await get_tree().process_frame

	print("TRANSITION: All clients ready.")

	# We'll replace this with the coordinated loading step later.
	_load_level_on_all_peers.rpc(pending_transition_scene)
