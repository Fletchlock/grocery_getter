extends Node3D

@onready var music_sources: Array[AudioStreamPlayer3D] = [
	$Speaker1,
	$Speaker2,
]


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
	
	EventManager.setup_level(
		$NavigationRegion3D/Events,
		$NavigationRegion3D/MultiplayerEventSpawner
	)
	
	# Changed to support single player
	#if multiplayer.is_server() and NetworkManager.peer != null:
	if multiplayer.is_server():
		# Spawn the host.
		SpawnManager.spawn_player(multiplayer.get_unique_id())

		# Spawn any clients that were already connected
		# before the level finished loading.
		for peer_id in multiplayer.get_peers():
			SpawnManager.spawn_player(peer_id)

	MusicManager.player.stop()

	for source in music_sources:
		source.play()


#for SHIFT F5 F6 testing shortcuts
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	if not event.shift_pressed:
		return

	if event.physical_keycode == KEY_F5:
		if not multiplayer.is_server():
			return

		var shopper_spawner: Node = get_tree().get_first_node_in_group(
			"shopper_spawner"
		)

		if shopper_spawner != null:
			shopper_spawner.spawn_shopper()
			get_viewport().set_input_as_handled()

	elif event.physical_keycode == KEY_F6:
		if not multiplayer.is_server():
			return

		OrderManager.debug_spawn_order()
		get_viewport().set_input_as_handled()
