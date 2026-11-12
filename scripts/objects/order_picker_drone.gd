
extends Node3D
class_name OrderPickerDrone


@export_group("Flight Settings")
@export var flight_height: float = 2.5
@export var flight_speed: float = 3.5
@export var acceleration: float = 3.0
@export var rotation_speed: float = 4.0
@export var arrival_distance: float = 0.05
@export var pause_duration: float = 2.0

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

	match state:
		DroneState.FLYING, DroneState.RETURNING:
			_update_flight(delta)

		DroneState.PAUSED:
			pause_timer -= delta

			if pause_timer <= 0.0:
				_next_target()


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

	var desired_speed: float = minf(flight_speed, sqrt(2.0 * acceleration * distance))
	current_speed = move_toward(current_speed, desired_speed, acceleration * delta)

	var movement: float = minf(current_speed * delta, distance)
	global_position += direction * movement

	var horizontal_direction: Vector3 = Vector3(direction.x, 0.0, direction.z)

	if horizontal_direction.length_squared() > 0.001:
		var target_yaw: float = atan2(-horizontal_direction.x, -horizontal_direction.z)

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
