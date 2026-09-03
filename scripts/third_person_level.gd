extends Node3D


# ============================================================================
# PLAYER SCENE
# ============================================================================
# MultiplayerSpawner will create this scene whenever the server spawns a
# player.
# ============================================================================

const PLAYER_SCENE := preload("res://scenes/low_poly_character.tscn")


# ============================================================================
# NODE REFERENCES
# ============================================================================

@onready var player_spawn_point: Marker3D = $PlayerSpawnPoint
@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner


# ============================================================================
# READY
# ============================================================================

func _ready() -> void:

	# Tell the MultiplayerSpawner which function to use when it needs
	# to create a Player.
	multiplayer_spawner.spawn_function = _spawn_player

	# The server needs to know when another peer connects so it can
	# spawn a Player for that peer.
	multiplayer.peer_connected.connect(_on_peer_connected)

	# The server immediately spawns its own Player.
	if multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())


# ============================================================================
# PEER CONNECTED
# ============================================================================

func _on_peer_connected(peer_id: int) -> void:

	# Only the server is responsible for spawning Players.
	if not multiplayer.is_server():
		return

	print("LEVEL: Peer connected: ", peer_id)

	spawn_player(peer_id)


# ============================================================================
# PLAYER SPAWNING
# ============================================================================

func spawn_player(peer_id: int) -> void:

	# Only the server should request a spawn.
	if not multiplayer.is_server():
		return

	print("LEVEL: Spawning player for peer ", peer_id)

	# Send the peer ID as spawn data.
	#
	# MultiplayerSpawner will call _spawn_player() on the server
	# and on the remote peers.
	multiplayer_spawner.spawn(peer_id)


# ============================================================================
# CUSTOM SPAWN FUNCTION
# ============================================================================

func _spawn_player(data: Variant) -> Node:

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D

	if player == null:
		push_error("PLAYER_SCENE is not a CharacterBody3D!")
		return null

	var peer_id: int = data

	player.name = str(peer_id)

	# Give the Player authority to the peer that owns it.
	player.set_multiplayer_authority(peer_id)

	# Position the player before it enters the tree.
	player.global_transform = player_spawn_point.global_transform

	print(
		"LEVEL: Created player ",
		player.name,
		" authority=",
		player.get_multiplayer_authority()
	)

	return player
