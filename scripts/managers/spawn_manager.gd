extends Node

const PLAYER_SCENE := preload("res://scenes/low_poly_character.tscn")

var players: Node3D
var multiplayer_spawner: MultiplayerSpawner
var spawn_points: Array[Marker3D] = []


func setup_level(
	players_node: Node3D,
	spawner: MultiplayerSpawner,
	points: Array[Marker3D]
) -> void:
	players = players_node
	multiplayer_spawner = spawner
	spawn_points = points

	multiplayer_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)

	print("SpawnManager: Level setup complete.")


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("SpawnManager: Peer connected: ", peer_id)
	spawn_player(peer_id)


func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("SpawnManager: Spawning player for peer ", peer_id)
	multiplayer_spawner.spawn(peer_id)


func _spawn_player(data: Variant) -> Node:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D

	if player == null:
		push_error("PLAYER_SCENE is not a CharacterBody3D!")
		return null

	var peer_id: int = data

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	if spawn_points.is_empty():
		push_error("SpawnManager: No spawn points available!")
		return player

	var spawn_point := spawn_points[0]

	#player.position = players.to_local(spawn_point.global_position)
	player.transform = spawn_point.global_transform

	print(
		"SpawnManager: Created player ",
		player.name,
		" authority=",
		player.get_multiplayer_authority()
	)

	return player 


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if players == null:
		return

	var player := players.get_node_or_null(str(peer_id))

	if player:
		print("SpawnManager: Removing player ", peer_id)
		player.queue_free()
