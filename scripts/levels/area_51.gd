
extends Node3D


@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var player_spawn_points: Node3D = $PlayerSpawnPoints

@export_group("Door Testing")
@export var enable_door_timer: bool = true
@export var door_toggle_interval: float = 10.0


var door_timer: Timer
var doors: Array[Area51AutomaticDoors] = []


func _ready() -> void:
	var spawn_points: Array[Marker3D] = []

	for child: Node in player_spawn_points.get_children():
		if child is Marker3D:
			spawn_points.append(child as Marker3D)

	SpawnManager.setup_level(
		players,
		multiplayer_spawner,
		spawn_points
	)

	if multiplayer.is_server():
		SpawnManager.spawn_player(multiplayer.get_unique_id())

		for peer_id: int in multiplayer.get_peers():
			SpawnManager.spawn_player(peer_id)

	_setup_door_timer()


func _setup_door_timer() -> void:
	for child: Node in get_children():
		if child is Area51AutomaticDoors:
			doors.append(child)

	if not multiplayer.is_server():
		return

	if not enable_door_timer:
		return

	door_timer = Timer.new()
	door_timer.wait_time = maxf(door_toggle_interval, 0.01)
	door_timer.one_shot = false
	door_timer.timeout.connect(_on_door_timer_timeout)
	add_child(door_timer)
	door_timer.start()


func _on_door_timer_timeout() -> void:
	for door: Area51AutomaticDoors in doors:
		door.set_locked(not door.locked)
