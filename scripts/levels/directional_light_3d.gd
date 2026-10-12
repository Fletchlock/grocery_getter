
extends DirectionalLight3D

@export_group("Sun Rotation")
@export var total_rotation_degrees: float = 240.0

const START_HOUR: int = 7
const END_HOUR: int = 24

var starting_rotation: Vector3
var local_minute_timer: float = 0.0


func _ready() -> void:
	starting_rotation = rotation_degrees

	DayManager.clock_updated.connect(_on_clock_updated)

	_update_sun_rotation()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		local_minute_timer = DayManager._minute_timer
	elif DayManager.clock_running:
		local_minute_timer += delta

		if local_minute_timer >= DayManager.REAL_SECONDS_PER_GAME_MINUTE:
			local_minute_timer = fmod(
				local_minute_timer,
				DayManager.REAL_SECONDS_PER_GAME_MINUTE
			)

	_update_sun_rotation()


func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	if not multiplayer.is_server():
		local_minute_timer = 0.0


func _update_sun_rotation() -> void:
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

	var start_minutes: float = START_HOUR * 60.0
	var end_minutes: float = END_HOUR * 60.0

	var progress: float = clampf(
		(current_minutes - start_minutes) / (end_minutes - start_minutes),
		0.0,
		1.0
	)

	rotation_degrees.x = starting_rotation.x - total_rotation_degrees * progress
