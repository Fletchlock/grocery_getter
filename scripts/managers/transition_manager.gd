
extends Node

signal all_peers_loaded(level_path: String)

const ORANGE_SURVIVAL_SCENE: String = "res://scenes/levels/orange_survival.tscn"
const CONVEYOR_SHOWDOWN_SCENE: String = "res://scenes/levels/conveyor_showdown.tscn"
const GROCERY_STORE_SCENE: String = "res://scenes/levels/third_person_level.tscn"

@onready var fade_rect: ColorRect = $CanvasLayer/ColorRect

var transitioning: bool = false
var transition_id: int = 0
var ready_peers: Dictionary = {}


func _ready() -> void:
	fade_rect.modulate.a = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if not multiplayer.is_server() or transitioning:
		return

	match event.keycode:
		KEY_F6:
			start_orange_survival()

		KEY_F7:
			start_conveyor_showdown()


func start_orange_survival() -> void:
	if not multiplayer.is_server() or transitioning:
		return

	StoreManager.capture_restock_boxes()
	_begin_coordinated_transition(ORANGE_SURVIVAL_SCENE)


func start_conveyor_showdown() -> void:
	if not multiplayer.is_server() or transitioning:
		return

	StoreManager.capture_restock_boxes()
	_begin_coordinated_transition(CONVEYOR_SHOWDOWN_SCENE)


func return_to_grocery_store() -> void:
	if not multiplayer.is_server() or transitioning:
		return

	await _begin_coordinated_transition(GROCERY_STORE_SCENE)

	if DayManager._day_transition_started:
		DayManager.complete_minigame_and_advance_day()


func _begin_coordinated_transition(level_path: String) -> void:
	transitioning = true
	transition_id += 1

	var id: int = transition_id

	# Stage 1: Prepare
	ready_peers.clear()
	_prepare_transition.rpc(id)
	await _wait_for_peers(id)

	# Stage 2: Unload old level
	ready_peers.clear()
	_unload_transition_level.rpc(id)
	await _wait_for_peers(id)

	# Stage 3: Load new level
	ready_peers.clear()
	_load_transition_level.rpc(id, level_path)
	await _wait_for_peers(id)

	print("TRANSITION: All peers loaded ", level_path)

	# The new level is now ready for gameplay.
	all_peers_loaded.emit(level_path)

	_finish_transition.rpc(id)


func _wait_for_peers(id: int) -> void:
	while id == transition_id:
		var all_ready: bool = true

		for peer_id: int in multiplayer.get_peers():
			if not ready_peers.has(peer_id):
				all_ready = false
				break

		if all_ready:
			return

		await get_tree().process_frame



@rpc("authority", "call_local", "reliable")
func _prepare_transition(id: int) -> void:
	transition_id = id
	transitioning = true
	fade_rect.modulate.a = 1.0

	# Stop player replication before unloading the level.
	var level: Node = LevelManager.current_level

	if is_instance_valid(level):
		var player_container: Node = level.get_node_or_null("Players")

		if player_container != null:
			for player: Node in player_container.get_children():
				var synchronizer: MultiplayerSynchronizer = player.get_node_or_null(
					"MultiplayerSyncronizer"
				) as MultiplayerSynchronizer

				if synchronizer != null:
					synchronizer.public_visibility = false

	# Allow multiplayer to process the visibility changes.
	await get_tree().process_frame
	await get_tree().process_frame

	_acknowledge_stage(id)



@rpc("authority", "call_local", "reliable")
func _unload_transition_level(id: int) -> void:
	LevelManager.unload_level()

	# Allow queued deletions to complete.
	await get_tree().process_frame
	await get_tree().process_frame

	_acknowledge_stage(id)


@rpc("authority", "call_local", "reliable")
func _load_transition_level(id: int, level_path: String) -> void:
	var success: bool = LevelManager.load_level(level_path)

	if not success:
		push_error("TRANSITION: Level failed to load.")
		return

	# Allow the new scene to initialize.
	await get_tree().process_frame

	# Wait for this peer's own character in Orange Survival.
	if level_path in [
		ORANGE_SURVIVAL_SCENE,
		CONVEYOR_SHOWDOWN_SCENE
	]:
		var level: Node = LevelManager.current_level
		var player_container: Node = level.get_node("Players")
		var local_id: String = str(multiplayer.get_unique_id())

		while (
			is_instance_valid(level)
			and not player_container.has_node(local_id)
		):
			await get_tree().process_frame

		if not is_instance_valid(level):
			return

	_acknowledge_stage(id)


func _acknowledge_stage(id: int) -> void:
	if multiplayer.is_server():
		return

	_receive_stage_ack.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _receive_stage_ack(id: int) -> void:
	if not multiplayer.is_server():
		return
	if id != transition_id:
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	ready_peers[peer_id] = true

	print("TRANSITION ACK: ", peer_id, " stage ", id)


@rpc("authority", "call_local", "reliable")
func _finish_transition(id: int) -> void:
	if id != transition_id:
		return

	fade_rect.modulate.a = 0.0
	transitioning = false

	if multiplayer.is_server():
		# Restore inventory after returning to the store.
		if LevelManager.current_level != null:
			if LevelManager.current_level.name == "ThirdPersonLevel":
				StockOrderManager.restore_saved_boxes()
