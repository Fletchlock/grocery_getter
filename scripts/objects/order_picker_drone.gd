
extends Node3D
class_name OrderPickerDrone


@export_group("Flight Settings")
@export var flight_height: float = 3.0
@export var flight_speed: float = 3.5
@export var acceleration: float = 3.0
@export var rotation_speed: float = 4.0
@export var arrival_distance: float = 0.03
@export var pause_duration: float = 2.0

@export_group("Flight Sway")
@export var max_pitch: float = 8.0
@export var max_roll: float = 10.0
@export var sway_response: float = 4.0
@export var sway_damping: float = 3.0

@onready var drone_visual: Node3D = $DroneVisual

var sway_pitch: float = 0.0
var sway_roll: float = 0.0
var pitch_velocity: float = 0.0
var roll_velocity: float = 0.0
var previous_velocity: Vector3 = Vector3.ZERO

@export_group("Testing")
@export var auto_start: bool = true

enum DroneState {
	IDLE,
	FLYING,
	PAUSED,
	RETURNING
}

var state: DroneState = DroneState.IDLE

var home_position: Vector3
var target_position: Vector3
var product_points: Array[Vector3] = []

var current_target_index: int = 0
var current_speed: float = 0.0
var pause_timer: float = 0.0


func _ready() -> void:
	home_position = global_position
	_collect_product_points()

	if auto_start and multiplayer.is_server():
		start_route()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	var previous_position: Vector3 = global_position

	match state:
		DroneState.FLYING, DroneState.RETURNING:
			_update_flight(delta)

		DroneState.PAUSED:
			pause_timer -= delta

			if pause_timer <= 0.0:
				_next_target()

	var velocity: Vector3 = Vector3.ZERO

	if delta > 0.0:
		velocity = (global_position - previous_position) / delta

	_update_sway(delta, velocity)


func _update_sway(delta: float, velocity: Vector3) -> void:
	if delta <= 0.0:
		return

	var acceleration_vector: Vector3 = (velocity - previous_velocity) / delta
	previous_velocity = velocity

	var local_acceleration: Vector3 = global_basis.inverse() * acceleration_vector

	var target_pitch: float = clampf(
		local_acceleration.z * 0.065,
		-deg_to_rad(max_pitch),
		deg_to_rad(max_pitch)
	)

	var target_roll: float = clampf(
		local_acceleration.x * 0.065,
		-deg_to_rad(max_roll),
		deg_to_rad(max_roll)
	)

	pitch_velocity += (target_pitch - sway_pitch) * sway_response * delta
	roll_velocity += (target_roll - sway_roll) * sway_response * delta

	pitch_velocity *= exp(-sway_damping * delta)
	roll_velocity *= exp(-sway_damping * delta)

	sway_pitch += pitch_velocity * delta
	sway_roll += roll_velocity * delta

	drone_visual.rotation.x = sway_pitch
	drone_visual.rotation.z = sway_roll


func _collect_product_points() -> void:
	product_points.clear()

	var displays: Array[Node] = get_tree().get_nodes_in_group("product_displays")

	for display: Node in displays:
		var shopper_point: Marker3D = display.get_node_or_null("AIShopperPoint") as Marker3D

		if shopper_point == null:
			continue

		var position: Vector3 = shopper_point.global_position
		position.y = flight_height

		product_points.append(position)


func start_route() -> void:
	if product_points.is_empty():
		return

	current_target_index = 0
	current_speed = 0.0

	target_position = product_points[current_target_index]
	state = DroneState.FLYING


func _update_flight(delta: float) -> void:
	var direction: Vector3 = target_position - global_position
	var distance: float = direction.length()

	if distance <= arrival_distance:
		global_position = target_position
		current_speed = 0.0

		if state == DroneState.RETURNING:
			state = DroneState.IDLE
		else:
			pause_timer = pause_duration
			state = DroneState.PAUSED

		return

	direction = direction.normalized()

	# Calculate braking speed based on remaining distance.
	var braking_speed: float = sqrt(2.0 * acceleration * distance)
	var desired_speed: float = minf(flight_speed, braking_speed)

	# Smoothly accelerate or decelerate.
	current_speed = move_toward(
		current_speed,
		desired_speed,
		acceleration * delta
	)

	# Prevent overshooting the destination.
	var movement: float = minf(current_speed * delta, distance)
	global_position += direction * movement

	# Smoothly rotate toward the flight direction.
	var horizontal_direction: Vector3 = Vector3(direction.x, 0.0, direction.z)

	if horizontal_direction.length_squared() > 0.001:
		var target_yaw: float = atan2(
			-horizontal_direction.x,
			-horizontal_direction.z
		)

		rotation.y = lerp_angle(
			rotation.y,
			target_yaw,
			minf(rotation_speed * delta, 1.0)
		)


func _next_target() -> void:
	current_target_index += 1

	if current_target_index >= product_points.size():
		target_position = home_position
		state = DroneState.RETURNING
		return

	target_position = product_points[current_target_index]
	state = DroneState.FLYING
