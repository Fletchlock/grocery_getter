
extends Node3D

@export_group("Orange Rotation")
@export var starting_rotation_speed: float = 0.20
@export var maximum_rotation_speed: float = 0.80
@export var speed_increase: float = 0.05
@export var speed_increase_interval: float = 10.0

@export_group("Direction Changes")
@export var minimum_direction_time: float = 3.0
@export var maximum_direction_time: float = 6.0
@export var reverse_chance: float = 0.75

@export_group("Game Start")
@export var rotation_start_delay: float = 3.0

@onready var orange: AnimatableBody3D = $Orange
@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

@onready var spawn_points: Array[Marker3D] = [
	$SpawnPoints/SpawnPoint1,
	$SpawnPoints/SpawnPoint2,
	$SpawnPoints/SpawnPoint3,
	$SpawnPoints/SpawnPoint4
]

var orange_rotating: bool = false
var current_rotation_speed: float = 0.0
var current_rotation_axis: Vector3 = Vector3.FORWARD

var speed_timer: float = 0.0
var direction_timer: float = 0.0
var next_direction_change: float = 0.0


func _ready() -> void:
	SpawnManager.setup_level(
		players,
		multiplayer_spawner,
		spawn_points
	)

	if not multiplayer.is_server():
		return

	for peer_id: int in LobbyManager.get_players():
		SpawnManager.spawn_player(peer_id)

	current_rotation_speed = starting_rotation_speed
	next_direction_change = randf_range(
		minimum_direction_time,
		maximum_direction_time
	)

	_start_orange_rotation.rpc()


func _process(_delta: float) -> void:
	var local_player: CharacterBody3D = players.get_node_or_null(
		str(multiplayer.get_unique_id())
	) as CharacterBody3D

	if local_player == null:
		return

	if local_player._first_person:
		local_player._set_perspective(false)


func _physics_process(delta: float) -> void:
	if not orange_rotating:
		return

	orange.rotate(
		current_rotation_axis,
		current_rotation_speed * delta
	)

	if not multiplayer.is_server():
		return

	speed_timer += delta
	direction_timer += delta

	if speed_timer >= speed_increase_interval:
		speed_timer = 0.0

		current_rotation_speed = minf(
			current_rotation_speed + speed_increase,
			maximum_rotation_speed
		)

		_sync_rotation_state.rpc(
			current_rotation_axis,
			current_rotation_speed
		)

	if direction_timer >= next_direction_change:
		direction_timer = 0.0

		next_direction_change = randf_range(
			minimum_direction_time,
			maximum_direction_time
		)

		_change_rotation_direction()


func _change_rotation_direction() -> void:
	if randf() < reverse_chance:
		current_rotation_axis = -current_rotation_axis
	else:
		var angle: float = randf_range(0.0, TAU)

		current_rotation_axis = Vector3(
			cos(angle),
			0.0,
			sin(angle)
		).normalized()

	_sync_rotation_state.rpc(
		current_rotation_axis,
		current_rotation_speed
	)


@rpc("authority", "call_local", "reliable")
func _start_orange_rotation() -> void:
	await get_tree().create_timer(rotation_start_delay).timeout

	if not is_inside_tree():
		return

	orange_rotating = true


@rpc("authority", "call_local", "reliable")
func _sync_rotation_state(
	axis: Vector3,
	speed: float
) -> void:
	current_rotation_axis = axis
	current_rotation_speed = speed
