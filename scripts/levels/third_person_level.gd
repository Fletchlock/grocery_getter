extends Node3D

@onready var player_spawn_point: Marker3D = $PlayerSpawnPoint


func _ready() -> void:
	# Pass spawn information to the SpawnManager
	SpawnManager.setup_level(
		$Players,
		$MultiplayerSpawner,
		[player_spawn_point]
	)

	if multiplayer.is_server():
		# Spawn the host.
		SpawnManager.spawn_player(multiplayer.get_unique_id())

		# Spawn any clients that were already connected
		# before the level finished loading.
		for peer_id in multiplayer.get_peers():
			SpawnManager.spawn_player(peer_id)
