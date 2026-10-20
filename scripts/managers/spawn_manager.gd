
extends Node

const PLAYER_SCENE := preload("res://scenes/player/low_poly_character_FP.tscn")

var players: Node3D
var multiplayer_spawner: MultiplayerSpawner
var spawn_points: Array[Marker3D] = []

# Peer ID -> spawn point index.
var assigned_spawn_points: Dictionary[int, int] = {}


func setup_level(
		players_node: Node3D,
		spawner: MultiplayerSpawner,
		points: Array[Marker3D]
	) -> void:
	players = players_node
	multiplayer_spawner = spawner
	spawn_points = points

	assigned_spawn_points.clear()

	multiplayer_spawner.spawn_function = _spawn_player

	if not multiplayer_spawner.spawned.is_connected(_on_player_spawned):
		multiplayer_spawner.spawned.connect(_on_player_spawned)

	if multiplayer.is_server() and NetworkManager.peer != null:
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

	print("SpawnManager: Level setup complete.")


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	print("SpawnManager: Late joining peer connected: ", peer_id)


func spawn_ready_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if not LobbyManager.get_players().has(peer_id):
		return

	if not LobbyManager.is_ready(peer_id):
		return

	var character: String = LobbyManager.get_character(peer_id)

	if character not in ["red", "blue", "green"]:
		return

	print(
		"SpawnManager: Spawning ready player ",
		peer_id,
		" with character ",
		character
	)

	spawn_player(peer_id)


func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if players == null or multiplayer_spawner == null:
		return

	# Don't spawn a player that already exists.
	if players.has_node(str(peer_id)):
		return

	var spawn_index: int = _get_available_spawn_index()

	if spawn_index == -1:
		push_warning("SpawnManager: No free spawn points for peer %d" % peer_id)
		return

	assigned_spawn_points[peer_id] = spawn_index

	print(
		"SpawnManager: Spawning player ",
		peer_id,
		" at spawn point ",
		spawn_index + 1
	)

	# Send the chosen index to every client.
	multiplayer_spawner.spawn({
		"peer_id": peer_id,
		"spawn_index": spawn_index
	})


func _get_available_spawn_index() -> int:
	var available: Array[int] = []

	for i: int in range(spawn_points.size()):
		if not assigned_spawn_points.values().has(i):
			available.append(i)

	if available.is_empty():
		return -1

	return available.pick_random()


func _spawn_player(data: Variant) -> Node:
	var spawn_data: Dictionary = data
	var peer_id: int = int(spawn_data["peer_id"])
	var spawn_index: int = int(spawn_data["spawn_index"])

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D

	if player == null:
		push_error("PLAYER_SCENE is not a CharacterBody3D!")
		return null

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	if spawn_index < 0 or spawn_index >= spawn_points.size():
		push_error("SpawnManager: Invalid spawn index!")
		player.free()
		return null

	var spawn_point: Marker3D = spawn_points[spawn_index]

	# Player will be added under the Players node.
	player.transform = players.global_transform.affine_inverse() * spawn_point.global_transform

	print(
		"SpawnManager: Created player ",
		player.name,
		" authority=",
		player.get_multiplayer_authority(),
		" spawn=",
		spawn_point.name
	)

	return player


func _on_player_spawned(node: Node) -> void:
	if multiplayer.is_server():
		return

	if not GameManager.is_late_joining:
		return

	if node.name != str(multiplayer.get_unique_id()):
		return

	print("SpawnManager: Late-joining player spawned: ", node.name)

	GameManager.complete_late_join()


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if assigned_spawn_points.has(peer_id):
		assigned_spawn_points.erase(peer_id)

	if players == null:
		return

	var player: Node = players.get_node_or_null(str(peer_id))

	if player:
		print("SpawnManager: Removing player ", peer_id)
		player.queue_free()
