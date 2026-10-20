extends Node3D



func _ready() -> void:
	# Collect spawn points in level
	var spawn_points: Array[Marker3D] = []
	
	for child: Node in $PlayerSpawnPoints.get_children():
		if child is Marker3D:
			spawn_points.append(child)
	
	# Pass spawn information to the SpawnManager
	SpawnManager.setup_level(
		$Players,
		$MultiplayerSpawner,
		spawn_points
	)

	if multiplayer.is_server() and NetworkManager.peer != null:
		# Spawn the host.
		SpawnManager.spawn_player(multiplayer.get_unique_id())

		# Spawn any clients that were already connected
		# before the level finished loading.
		for peer_id in multiplayer.get_peers():
			SpawnManager.spawn_player(peer_id)
