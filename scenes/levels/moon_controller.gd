
extends MeshInstance3D

@export_group("Moon")
@export var follow_camera_rotation: bool = true
@export var total_rotation_degrees: float = 45.0

@export_group("Moon Visibility")
@export var fade_start_hour: float = 20.0
@export var fade_end_hour: float = 21.0
@export var arc_height: float = 100.0
@export var end_height_offset: float = -120.0

const START_HOUR: float = 20.0
const END_HOUR: float = 24.0

var starting_position: Vector3
var local_minute_timer: float = 0.0
var moon_material: ShaderMaterial


func _ready() -> void:
	starting_position = position

	moon_material = get_surface_override_material(0).duplicate() as ShaderMaterial
	set_surface_override_material(0, moon_material)

	DayManager.clock_updated.connect(_on_clock_updated)

	_update_moon()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		local_minute_timer = DayManager._minute_timer
	elif DayManager.clock_running:
		local_minute_timer = fmod(
			local_minute_timer + delta,
			DayManager.REAL_SECONDS_PER_GAME_MINUTE
		)

	_update_moon()


func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	if not multiplayer.is_server():
		local_minute_timer = 0.0


func _update_moon() -> void:
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

	# Fade moon in between 8 PM and 9 PM.
	var visibility: float = smoothstep(
		fade_start_hour,
		fade_end_hour,
		time_hours
	)

	moon_material.set_shader_parameter("moon_visibility", visibility)

	
	# Move moon along a gentle arc across the sky.
	var progress: float = clampf(
		(time_hours - START_HOUR) / (END_HOUR - START_HOUR),
		0.0,
		1.0
	)

	var angle: float = deg_to_rad(total_rotation_degrees * progress)

	var distance: float = starting_position.length()
	var direction: Vector3 = starting_position.normalized()

	var new_direction: Vector3 = direction.rotated(Vector3.UP, angle)

	# Rise during the first half, then descend.
	var height_offset: float = sin(progress * PI) * arc_height

	# Gradually lower the moon toward the horizon.
	height_offset += end_height_offset * progress

	position = new_direction * distance
	position.y += height_offset


	# Always face the active player's camera.
	if follow_camera_rotation:
		var camera: Camera3D = get_viewport().get_camera_3d()

		if camera != null:
			look_at(camera.global_position, Vector3.UP, true)
