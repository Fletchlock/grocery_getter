
extends MeshInstance3D

@export_group("Star Visibility")
@export var fade_start_hour: float = 21.0
@export var fade_end_hour: float = 22.0

var star_material: ShaderMaterial
var local_minute_timer: float = 0.0




func _ready() -> void:
	star_material = get_surface_override_material(0).duplicate() as ShaderMaterial
	set_surface_override_material(0, star_material)

	DayManager.clock_updated.connect(_on_clock_updated)

	_update_stars()




func _process(delta: float) -> void:
	if multiplayer.is_server():
		local_minute_timer = DayManager._minute_timer
	elif DayManager.clock_running:
		local_minute_timer = fmod(
			local_minute_timer + delta,
			DayManager.REAL_SECONDS_PER_GAME_MINUTE
		)

	_update_stars()


func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	if not multiplayer.is_server():
		local_minute_timer = 0.0


func _update_stars() -> void:
	var minute_fraction: float = 0.0

	if DayManager.clock_running:
		minute_fraction = clampf(
			local_minute_timer / DayManager.REAL_SECONDS_PER_GAME_MINUTE,
			0.0,
			1.0
		)

	var time_hours: float = (
		float(DayManager.current_hour)
		+ (float(DayManager.current_minute) + minute_fraction) / 60.0
	)

	var visibility: float = smoothstep(
		fade_start_hour,
		fade_end_hour,
		time_hours
	)

	star_material.set_shader_parameter("star_visibility", visibility)
