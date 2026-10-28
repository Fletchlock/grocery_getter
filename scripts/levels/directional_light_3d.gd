
extends DirectionalLight3D

@export_group("Sun Rotation")
@export var total_rotation_degrees: float = 240.0

@export_group("Day/Night Cycle")
@export var sunset_start: float = 20.0
@export var sunset_end: float = 22.0
@export var night_start: float = 23.0
@export var night_sun_energy: float = 0.02
@export var night_ambient_energy: float = 0.10

@export_group("Rain Schedule")
@export_range(0.0, 1.0) var rain_chance: float = 0.2
@export var rain_min_hours: float = 6.0
@export var rain_max_hours: float = 8.0
@export var rain_transition_minutes: float = 30.0
@export var cloud_buildup_minutes: float = 60.0

@export_group("Rainy Weather")
@export_range(0.0, 1.0) var rain_sun_multiplier: float = 0.3
@export_range(0.0, 1.0) var rain_ambient_multiplier: float = 0.7
@export_range(0.0, 1.0) var rain_shadow_opacity: float = 0.25
@export var maximum_rain_particles: int = 3000
@export var rain_top_color: Color = Color("#647583")
@export var rain_horizon_color: Color = Color("#88969E")

@export_group("Rain Fog")
@export var rain_fog_density: float = 0.025
@export var rain_fog_color: Color = Color("#8796A3")

@export_group("Sunset Colors")
@export var sunset_top_color: Color = Color("#654C91")
@export var sunset_horizon_color: Color = Color("#F28C55")

@export_group("Night Colors")
@export var night_top_color: Color = Color("#071329")
@export var night_horizon_color: Color = Color("#182844")

@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"
@onready var rain_particles: GPUParticles3D = $"../RainEffect/RainParticles"

@export_group("Rain Audio")
@export_range(-40.0, 0.0) var rain_max_volume_db: float = -8.0

@onready var rain_audio: AudioStreamPlayer = $"../RainEffect/RainAudio"

@export_group("Indoor Rain Audio")
@export var indoor_rain_volume_db: float = -24.0
@export var indoor_rain_cutoff_hz: float = 2500.0
@export var outdoor_rain_cutoff_hz: float = 20000.0
@export var indoor_audio_transition: float = 1.2

var player_indoors: bool = false
var indoor_audio_blend: float = 0.0

@export_group("Door Rain Audio")
@export var automatic_doors: AutomaticDoors
@export var door_audio_distance: float = 5.0
@export var door_rain_cutoff_hz: float = 8000.0
@export var door_audio_transition: float = 0.1
@export var door_closed_position: float = 0.0
@export var door_open_position: float = 1.0

var door_audio_blend: float = 0.0


const START_HOUR: int = 7
const END_HOUR: int = 24

var starting_rotation: Vector3
var starting_sun_energy: float
var starting_ambient_energy: float
var starting_shadow_opacity: float

var sky_material: ProceduralSkyMaterial
var daytime_top_color: Color
var daytime_horizon_color: Color

var rain_start_minute: int = -1
var rain_end_minute: int = -1
var rain_intensity: float = 0.0
var local_minute_timer: float = 0.0
var scheduled_day: int = -1


func _ready() -> void:
	starting_rotation = rotation_degrees
	starting_sun_energy = light_energy
	starting_shadow_opacity = shadow_opacity

	# Keep environment changes local to this scene.
	world_environment.environment = world_environment.environment.duplicate(true)

	var environment: Environment = world_environment.environment
	starting_ambient_energy = environment.ambient_light_energy

	environment.fog_enabled = true
	environment.fog_density = 0.0
	environment.fog_sky_affect = 0.0

	var sky: Sky = environment.sky
	sky_material = sky.sky_material as ProceduralSkyMaterial

	if sky_material == null:
		push_error("SunController requires a ProceduralSkyMaterial.")
		set_process(false)
		return

	daytime_top_color = sky_material.sky_top_color
	daytime_horizon_color = sky_material.sky_horizon_color

	rain_particles.amount = maximum_rain_particles
	rain_particles.amount_ratio = 0.0
	rain_particles.emitting = false
	rain_audio.volume_db = -80.0
	rain_audio.finished.connect(_on_rain_audio_finished)
	rain_audio.play()	
	
	print("RAIN AUDIO STREAM: ", rain_audio.stream)
	print("RAIN AUDIO PLAYING: ", rain_audio.playing)
	print("RAIN AUDIO BUS: ", rain_audio.bus)
	
	DayManager.clock_updated.connect(_on_clock_updated)
	DayManager.day_started.connect(_on_day_started)

	if multiplayer.is_server():
		_schedule_daily_rain()
	else:
		_request_rain_schedule.rpc_id(1)

	_update_rain_intensity()
	_update_sun()
	_update_weather_fog()
	_update_rain()
	_update_rain_audio(0.0)

func _process(delta: float) -> void:
	if multiplayer.is_server():
		local_minute_timer = DayManager._minute_timer
	elif DayManager.clock_running:
		local_minute_timer = fmod(
			local_minute_timer + delta,
			DayManager.REAL_SECONDS_PER_GAME_MINUTE
		)

	_update_rain_intensity()
	_update_sun()
	_update_weather_fog()
	_update_rain()
	_update_rain_audio(delta)

func _get_current_game_minutes() -> float:
	var minute_fraction: float = 0.0

	if DayManager.clock_running:
		minute_fraction = clampf(
			local_minute_timer / DayManager.REAL_SECONDS_PER_GAME_MINUTE,
			0.0,
			1.0
		)

	return float(
		DayManager.current_hour * 60 + DayManager.current_minute
	) + minute_fraction


func _get_door_audio_influence() -> float:
	if not player_indoors:
		return 0.0

	if automatic_doors == null:
		return 0.0

	var audio_point: Marker3D = automatic_doors.get_node_or_null("AudioPoint") as Marker3D

	if audio_point == null:
		return 0.0

	var local_player: CharacterBody3D = null

	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is CharacterBody3D and player.is_multiplayer_authority():
			local_player = player as CharacterBody3D
			break

	if local_player == null:
		return 0.0

	var player_pos: Vector2 = Vector2(
		local_player.global_position.x,
		local_player.global_position.z
	)

	var door_pos: Vector2 = Vector2(
		audio_point.global_position.x,
		audio_point.global_position.z
	)

	var distance: float = player_pos.distance_to(door_pos)

	var distance_influence: float = 1.0 - smoothstep(
		0.0,
		maxf(door_audio_distance, 0.01),
		distance
	)

	# Calculate opening from actual door positions.
	var left_door: Node3D = automatic_doors.get_node_or_null("DoorLeft") as Node3D
	var right_door: Node3D = automatic_doors.get_node_or_null("DoorRight") as Node3D

	if left_door == null or right_door == null:
		return 0.0

	var current_separation: float = left_door.position.distance_to(right_door.position)

	var open_amount: float = inverse_lerp(
		door_closed_position,
		door_open_position,
		current_separation
	)

	open_amount = clampf(open_amount, 0.0, 1.0)

	return distance_influence * open_amount


func _update_sun() -> void:
	var current_minutes: float = _get_current_game_minutes()
	var time_hours: float = current_minutes / 60.0

	# Rotate sun throughout the day.
	var progress: float = clampf(
		(current_minutes - START_HOUR * 60.0) /
		((END_HOUR - START_HOUR) * 60.0),
		0.0,
		1.0
	)

	rotation_degrees.x = starting_rotation.x - total_rotation_degrees * progress

	var sunset_blend: float = smoothstep(
		sunset_start,
		sunset_end,
		time_hours
	)

	var night_blend: float = smoothstep(
		sunset_end,
		night_start,
		time_hours
	)

	# Normal day/night sky colors.
	var top_color: Color = daytime_top_color.lerp(
		sunset_top_color,
		sunset_blend
	)

	var horizon_color: Color = daytime_horizon_color.lerp(
		sunset_horizon_color,
		sunset_blend
	)

	top_color = top_color.lerp(night_top_color, night_blend)
	horizon_color = horizon_color.lerp(night_horizon_color, night_blend)

	# Rain clouds gradually darken the sky before rain begins.
	var sky_rain_blend: float = _get_rain_sky_intensity()
	sky_rain_blend *= 1.0 - sunset_blend

	sky_material.sky_top_color = top_color.lerp(
		rain_top_color,
		sky_rain_blend
	)

	sky_material.sky_horizon_color = horizon_color.lerp(
		rain_horizon_color,
		sky_rain_blend
	)

	# Normal day/night lighting.
	var sun_energy: float = lerpf(
		starting_sun_energy,
		night_sun_energy,
		sunset_blend
	)

	var ambient_energy: float = lerpf(
		starting_ambient_energy,
		night_ambient_energy,
		sunset_blend
	)

	# Dim lighting as storm clouds build.
	var lighting_rain_blend: float = sky_rain_blend

	light_energy = sun_energy * lerpf(
		1.0,
		rain_sun_multiplier,
		lighting_rain_blend
	)

	world_environment.environment.ambient_light_energy = ambient_energy * lerpf(
		1.0,
		rain_ambient_multiplier,
		lighting_rain_blend
	)

	shadow_opacity = lerpf(
		starting_shadow_opacity,
		rain_shadow_opacity,
		lighting_rain_blend
	)


func _schedule_daily_rain() -> void:
	if not multiplayer.is_server():
		return

	# Only generate one schedule per day.
	if scheduled_day == DayManager.current_day:
		return

	scheduled_day = DayManager.current_day
	rain_start_minute = -1
	rain_end_minute = -1

	if randf() < rain_chance:
		var duration: int = randi_range(
			roundi(rain_min_hours * 60.0),
			roundi(rain_max_hours * 60.0)
		)

		var earliest_start: int = START_HOUR * 60
		var latest_start: int = 23 * 60 - duration

		if latest_start >= earliest_start:
			rain_start_minute = randi_range(
				earliest_start,
				latest_start
			)
			rain_end_minute = rain_start_minute + duration

	_sync_rain_schedule.rpc(
		scheduled_day,
		rain_start_minute,
		rain_end_minute
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_rain_schedule() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	_sync_rain_schedule.rpc_id(
		sender_id,
		scheduled_day,
		rain_start_minute,
		rain_end_minute
	)


@rpc("authority", "call_local", "reliable")
func _sync_rain_schedule(
	day: int,
	start_minute: int,
	end_minute: int
) -> void:
	if day < scheduled_day:
		return

	scheduled_day = day
	rain_start_minute = start_minute
	rain_end_minute = end_minute

	_update_rain_intensity()
	_update_sun()
	_update_weather_fog()
	_update_rain()
	_update_rain_audio(0.0)


func _update_rain_intensity() -> void:
	rain_intensity = 0.0

	if rain_start_minute < 0:
		return

	if scheduled_day != DayManager.current_day:
		return

	var current_minutes: float = _get_current_game_minutes()
	var fade: float = maxf(rain_transition_minutes, 0.01)

	var fade_in: float = smoothstep(
		float(rain_start_minute),
		float(rain_start_minute) + fade,
		current_minutes
	)

	var fade_out: float = 1.0 - smoothstep(
		float(rain_end_minute) - fade,
		float(rain_end_minute),
		current_minutes
	)

	rain_intensity = clampf(fade_in * fade_out, 0.0, 1.0)


func _get_rain_sky_intensity() -> float:
	if rain_start_minute < 0:
		return 0.0

	if scheduled_day != DayManager.current_day:
		return 0.0

	var current_minutes: float = _get_current_game_minutes()

	var fade_in: float = smoothstep(
		float(rain_start_minute) - maxf(cloud_buildup_minutes, 0.01),
		float(rain_start_minute),
		current_minutes
	)

	var fade_out: float = 1.0 - smoothstep(
		float(rain_end_minute) - maxf(rain_transition_minutes, 0.01),
		float(rain_end_minute),
		current_minutes
	)

	return clampf(fade_in * fade_out, 0.0, 1.0)


func _update_weather_fog() -> void:
	var environment: Environment = world_environment.environment

	environment.fog_density = lerpf(
		0.0,
		1.0,
		rain_intensity
	)

	environment.fog_sky_affect = lerpf(
		0.0,
		0.75,
		rain_intensity
	)


func _update_rain() -> void:
	var active: bool = rain_intensity > 0.001

	if rain_particles.emitting != active:
		rain_particles.emitting = active

	if active:
		rain_particles.amount_ratio = rain_intensity
	else:
		rain_particles.amount_ratio = 0.0


func _update_rain_audio(delta: float) -> void:
	var target_blend: float = 1.0 if player_indoors else 0.0

	indoor_audio_blend = move_toward(
		indoor_audio_blend,
		target_blend,
		delta / maxf(indoor_audio_transition, 0.01)
	)

	var indoor_volume: float = lerpf(
		1.0,
		db_to_linear(indoor_rain_volume_db),
		indoor_audio_blend
	)

	rain_audio.volume_linear = (
		rain_intensity
		* db_to_linear(rain_max_volume_db)
		* indoor_volume
	)

	# Smoothly blend the doorway rain influence.
	var target_door_blend: float = _get_door_audio_influence()

	door_audio_blend = move_toward(
		door_audio_blend,
		target_door_blend,
		delta / maxf(door_audio_transition, 0.01)
	)

	var bus_index: int = AudioServer.get_bus_index("Rain")

	if bus_index < 0:
		return

	var filter: AudioEffectLowPassFilter = (
		AudioServer.get_bus_effect(bus_index, 0)
		as AudioEffectLowPassFilter
	)

	if filter != null:
		var normal_cutoff: float = lerpf(
			outdoor_rain_cutoff_hz,
			indoor_rain_cutoff_hz,
			indoor_audio_blend
		)

		var door_influence: float = door_audio_blend * indoor_audio_blend

		filter.cutoff_hz = lerpf(
			normal_cutoff,
			door_rain_cutoff_hz,
			door_influence
		)


func _on_indoor_audio_area_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return

	if not body.is_in_group("player"):
		return

	if not body.is_multiplayer_authority():
		return

	player_indoors = true


func _on_indoor_audio_area_body_exited(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return

	if not body.is_in_group("player"):
		return

	if not body.is_multiplayer_authority():
		return

	player_indoors = false


func _on_rain_audio_finished() -> void:
	rain_audio.play()


func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	if not multiplayer.is_server():
		local_minute_timer = 0.0

		if scheduled_day != DayManager.current_day:
			_request_rain_schedule.rpc_id(1)


func _on_day_started(_day: int) -> void:
	rain_intensity = 0.0

	if multiplayer.is_server():
		_schedule_daily_rain()
