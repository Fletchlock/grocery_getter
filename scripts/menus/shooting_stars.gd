extends Node3D

@export_group("Timing")
@export var minimum_interval: float = 8.0
@export var maximum_interval: float = 20.0

@export_group("Movement")
@export var travel_duration: float = 1.0
@export var travel_distance: float = 76.0
@export var travel_height: float = 12.0

@onready var shooting_star: MeshInstance3D = $ShootingStar
@onready var spawn_timer: Timer = $SpawnTimer


func _ready() -> void:
	shooting_star.visible = false
	spawn_timer.timeout.connect(_launch_shooting_star)

	_schedule_next_star()


func _schedule_next_star() -> void:
	spawn_timer.wait_time = randf_range(
		minimum_interval,
		maximum_interval
	)

	spawn_timer.start()


func _launch_shooting_star() -> void:
	# Randomly choose the side the shooting star enters from
	var moving_right: bool = randf() < 0.5

	# Choose a random downward angle between 15 and 60 degrees
	var downward_angle: float = deg_to_rad(
		randf_range(15.0, 60.0)
	)

	# Determine horizontal direction based on the chosen side
	var direction_x: float = 1.0 if moving_right else -1.0

	# Calculate movement using the randomized angle
	var movement = Vector3(
		cos(downward_angle) * direction_x,
		-sin(downward_angle),
		0.0
	) * travel_distance

	# Spawn just outside the corresponding screen edge
	var start_position = Vector3(
		-38.0 if moving_right else 38.0,
		randf_range(-12.0, 12.0),
		-40.0
	)

	var end_position = start_position + movement

	# Position and orient the shooting star
	shooting_star.position = start_position
	shooting_star.rotation.z = atan2(
		movement.y,
		movement.x
	)

	shooting_star.visible = true

	# Animate the shooting star
	var tween = create_tween()

	tween.tween_property(
		shooting_star,
		"position",
		end_position,
		travel_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await tween.finished

	shooting_star.visible = false

	_schedule_next_star()
