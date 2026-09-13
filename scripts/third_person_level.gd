extends Node3D

@onready var player_spawn_point: Marker3D = $PlayerSpawnPoint
@onready var thing_platform: Node3D = $ThingPlatform
@onready var platform_animation_player: AnimationPlayer = (
	$ThingPlatform/AnimationPlayer
)

const PLATFORM_ANIMATION := &"move"
const PLATFORM_ANIMATION_LENGTH := 12.0

var _platform_sync_request_time := 0


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

		# Tell clients where the platform animation currently is.
		_sync_platform_animation.rpc(
			platform_animation_player.current_animation_position
		)
	else:
		# Ask the server for the current animation position.
		_platform_sync_request_time = Time.get_ticks_msec()
		_request_platform_animation.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_platform_animation() -> void:
	if not multiplayer.is_server():
		return

	var requesting_peer := multiplayer.get_remote_sender_id()

	_sync_platform_animation.rpc_id(
		requesting_peer,
		platform_animation_player.current_animation_position
	)


@rpc("authority", "reliable")
func _sync_platform_animation(animation_position: float) -> void:
	if multiplayer.is_server():
		return

	var round_trip_time := (
		Time.get_ticks_msec()
		- _platform_sync_request_time
	)

	var one_way_time := (
		float(round_trip_time) / 2000.0
	)

	var corrected_position := (
		animation_position + one_way_time
	)

	corrected_position = fmod(
		corrected_position,
		PLATFORM_ANIMATION_LENGTH
	)

	platform_animation_player.seek(
		corrected_position,
		true
	)

	if not platform_animation_player.is_playing():
		platform_animation_player.play(
			PLATFORM_ANIMATION
		)
