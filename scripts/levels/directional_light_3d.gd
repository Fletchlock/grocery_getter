
extends DirectionalLight3D

@export_group("Sun Rotation")
@export var total_rotation_degrees: float = 240.0

@export_group("Day/Night Cycle")
@export var sunset_start: float = 20.0
@export var sunset_end: float = 22.0
@export var night_start: float = 23.0
@export var night_sun_energy: float = 0.02
@export var night_ambient_energy: float = 0.10

@export_group("Sunset Colors")
@export var sunset_top_color: Color = Color("#654C91")
@export var sunset_horizon_color: Color = Color("#F28C55")

@export_group("Night Colors")
@export var night_top_color: Color = Color("#071329")
@export var night_horizon_color: Color = Color("#182844")

@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"

const START_HOUR: int = 7
const END_HOUR: int = 24

var starting_rotation: Vector3
var starting_sun_energy: float
var starting_ambient_energy: float

var sky_material: ProceduralSkyMaterial
var daytime_top_color: Color
var daytime_horizon_color: Color


func _ready() -> void:
	starting_rotation = rotation_degrees
	starting_sun_energy = light_energy

	# Duplicate resources so we don't modify shared originals.
	world_environment.environment = world_environment.environment.duplicate(true)
	starting_ambient_energy = world_environment.environment.ambient_light_energy
	DayManager.clock_updated.connect(_on_clock_updated)
	
	var sky: Sky = world_environment.environment.sky
	sky_material = sky.sky_material as ProceduralSkyMaterial

	if sky_material == null:
		push_error("SunController requires a ProceduralSkyMaterial.")
		set_process(false)
		return

	daytime_top_color = sky_material.sky_top_color
	daytime_horizon_color = sky_material.sky_horizon_color

	_update_sun()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		local_minute_timer = DayManager._minute_timer
	elif DayManager.clock_running:
		local_minute_timer = fmod(
			local_minute_timer + delta,
			DayManager.REAL_SECONDS_PER_GAME_MINUTE
		)

	_update_sun()


var local_minute_timer: float = 0.0


func _update_sun() -> void:
	var minute_fraction: float = 0.0

	if DayManager.clock_running:
		minute_fraction = clampf(
			local_minute_timer / DayManager.REAL_SECONDS_PER_GAME_MINUTE,
			0.0,
			1.0
		)

	var current_minutes: float = (
		float(DayManager.current_hour * 60 + DayManager.current_minute)
		+ minute_fraction
	)

	var time_hours: float = current_minutes / 60.0

	# Sun rotation
	var progress: float = clampf(
		(current_minutes - START_HOUR * 60.0) /
		((END_HOUR - START_HOUR) * 60.0),
		0.0,
		1.0
	)

	rotation_degrees.x = starting_rotation.x - total_rotation_degrees * progress

	# Sunset transition
	var sunset_blend: float = smoothstep(
		sunset_start,
		sunset_end,
		time_hours
	)

	# Night transition
	var night_blend: float = smoothstep(
		sunset_end,
		night_start,
		time_hours
	)

	var top_color: Color = daytime_top_color.lerp(
		sunset_top_color,
		sunset_blend
	)

	var horizon_color: Color = daytime_horizon_color.lerp(
		sunset_horizon_color,
		sunset_blend
	)

	sky_material.sky_top_color = top_color.lerp(
		night_top_color,
		night_blend
	)

	sky_material.sky_horizon_color = horizon_color.lerp(
		night_horizon_color,
		night_blend
	)

	# Fade sunlight during sunset and dusk
	light_energy = lerpf(
		starting_sun_energy,
		night_sun_energy,
		sunset_blend
	)
	
	# Gradually reduce ambient lighting as night approaches.
	world_environment.environment.ambient_light_energy = lerpf(
		starting_ambient_energy,
		night_ambient_energy,
		sunset_blend
	)

func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	if not multiplayer.is_server():
		local_minute_timer = 0.0
