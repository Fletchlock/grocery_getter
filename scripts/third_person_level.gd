extends Node3D

@onready var player_spawn_point: Marker3D = $PlayerSpawnPoint


func _ready() -> void:
	#Pass spawn information to the SpawnManager
	SpawnManager.setup_level(
		$Players,
		$MultiplayerSpawner,
		[player_spawn_point]
	)
	# The server immediately spawns its own Player.
	if multiplayer.is_server():
		SpawnManager.spawn_player(multiplayer.get_unique_id())
