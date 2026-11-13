
extends Node3D
class_name OrderPickerDrone


@export_group("Flight Settings")
@export var flight_height: float = 3.0
@export var flight_speed: float = 3.5
@export var acceleration: float = 3.5
@export var braking_distance: float = 2.0
@export var rotation_speed: float = 4.0
@export var arrival_distance: float = 0.20
@export var pause_duration: float = 3.5

@export_group("Flight Sway")
@export var max_pitch: float = 15.0
@export var max_roll: float = 15.0
@export var sway_response: float = 4.0
@export var sway_damping: float = 2.0

@onready var drone_visual: Node3D = $DroneVisual
@onready var ride_platform: AnimatableBody3D = $RidePlatform

@export_group("Doorway Navigation")
@export var door_inside: Marker3D
@export var door_outside: Marker3D
@export var doorway_speed: float = 1.8
@export var doorway_arrival_distance: float = 0.25

enum TravelDirection {
	NONE,
	TO_STORE,
	FROM_STORE
}

var travel_direction: TravelDirection = TravelDirection.NONE
var doorway_stage: int = 0

@export_group("Tractor Beam")
@export var beam_activation_time: float = 0.35
@export var beam_deactivation_time: float = 0.40

@export var network_beam_active: bool = false

@onready var beam_cone: MeshInstance3D = $DroneVisual/TractorBeam/BeamCone
@onready var energy_rings: MeshInstance3D = $DroneVisual/TractorBeam/EnergyRings

var beam_extension: float = 0.0

@export_group("Product Pickup")
@export var pickup_duration: float = 1.7
@export var pickup_rotation_speed: float = 2.0
@export var pickup_end_scale: float = 0.15
@export_range(0.1, 0.8, 0.05) var pickup_centering_fraction: float = 0.30

@onready var tractor_beam: Node3D = $DroneVisual/TractorBeam

var pickup_product: MeshInstance3D = null
var pickup_elapsed: float = 0.0
var pickup_start_position: Vector3 = Vector3.ZERO
var pickup_started: bool = false
var route_displays: Array[Node3D] = []
var active_order_id: int = -1
var order_check_timer: float = 0.0

@export_group("Order Automation")
@export var order_check_interval: float = 1.0

@export_group("Multiplayer")
@export var interpolation_speed: float = 12.0

@export var network_position: Vector3 = Vector3.ZERO
@export var network_rotation_y: float = 0.0
@export var network_sway_pitch: float = 0.0
@export var network_sway_roll: float = 0.0

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

	network_position = global_position
	network_rotation_y = rotation.y

	order_check_timer = 0.0


func _physics_process(delta: float) -> void:
	var previous_position: Vector3 = global_position

	if multiplayer.is_server():
		match state:
			DroneState.FLYING, DroneState.RETURNING:
				_update_flight(delta)
				
			DroneState.IDLE:
				_check_for_order(delta)

			DroneState.PAUSED:
				pause_timer -= delta

				# Start lifting after the beam extends.
				#if not pickup_started:
					#if pause_timer <= pause_duration - beam_activation_time - 0.15:
						#pickup_started = true
						#_begin_test_pickup()

				if pause_timer <= beam_deactivation_time:
					network_beam_active = false

				if pause_timer <= 0.0:
					_next_target()

		# Publish the authoritative transform.
		network_position = global_position
		network_rotation_y = rotation.y
	else:
		# Smoothly follow the replicated transform.
		var weight: float = 1.0 - exp(
			-interpolation_speed * delta
		)

		global_position = global_position.lerp(
			network_position,
			weight
		)

		rotation.y = lerp_angle(
			rotation.y,
			network_rotation_y,
			weight
		)

	# Calculate local velocity for visual sway.
	var velocity: Vector3 = Vector3.ZERO

	if delta > 0.0:
		velocity = (global_position - previous_position) / delta

	if multiplayer.is_server():
		_update_sway(delta, velocity)

		network_sway_pitch = sway_pitch
		network_sway_roll = sway_roll
	else:
		var weight: float = 1.0 - exp(-interpolation_speed * delta)

		sway_pitch = lerpf(sway_pitch, network_sway_pitch, weight)
		sway_roll = lerpf(sway_roll, network_sway_roll, weight)

		drone_visual.rotation.x = sway_pitch
		drone_visual.rotation.z = sway_roll
		
	_update_tractor_beam(delta)
	_update_product_pickup(delta)
	_update_ride_platform_rotation()


func _check_for_order(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if state != DroneState.IDLE:
		return

	if active_order_id >= 0:
		return

	# Do not accept another order while the previous
	# drone assignment is still held.
	if OrderManager.drone_order_id >= 0:
		return

	order_check_timer -= delta

	if order_check_timer > 0.0:
		return

	order_check_timer = order_check_interval

	var available_order: OrderData = OrderManager.get_available_order()

	if available_order == null:
		return

	if not DayManager.store_open:
		return

	if door_inside == null or door_outside == null:
		return

	# Build and validate the route before claiming the order.
	if not _build_order_route(available_order):
		return

	var accepted_order: OrderData = OrderManager.accept_drone_order()

	if accepted_order == null:
		return

	active_order_id = accepted_order.order_id

	print(
		"ORDER DRONE: Starting route for order #",
		active_order_id,
		" | Displays: ",
		route_displays.size()
	)

	start_route()


func _build_order_route(order: OrderData) -> bool:
	product_points.clear()
	route_displays.clear()

	if order == null:
		return false

	var displays: Array[Node] = get_tree().get_nodes_in_group(
		"product_displays"
	)

	for item: OrderItem in order.items:
		if item.product == null:
			return false

		var found_display: Node3D = null

		for node: Node in displays:
			var display: Node3D = node as Node3D

			if display == null:
				continue

			if not bool(display.get("is_unlocked")):
				continue

			var data: ProductData = (
				display.get("product_data") as ProductData
			)

			if data == null:
				continue

			if data.resource_path != item.product.resource_path:
				continue

			var shopper_point: Marker3D = (
				display.get_node_or_null("AIShopperPoint") as Marker3D
			)

			if shopper_point == null:
				continue

			found_display = display
			break

		if found_display == null:
			push_warning(
				"ORDER DRONE: No display found for "
				+ item.product.resource_path
			)

			product_points.clear()
			route_displays.clear()
			return false

		var marker: Marker3D = (
			found_display.get_node("AIShopperPoint") as Marker3D
		)

		var destination: Vector3 = marker.global_position
		destination.y = flight_height

		product_points.append(destination)
		route_displays.append(found_display)

		print(
			"ORDER DRONE: ",
			item.product.display_name,
			" x",
			item.quantity
		)

	return not product_points.is_empty()


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

		var product_position: Vector3 = shopper_point.global_position
		product_position.y = flight_height

		product_points.append(product_position)


func start_route() -> void:
	if not multiplayer.is_server():
		return

	if product_points.is_empty():
		return

	if door_inside == null or door_outside == null:
		push_warning("Drone doorway markers are not assigned.")
		return

	current_target_index = 0
	current_speed = 0.0

	travel_direction = TravelDirection.TO_STORE
	doorway_stage = 0

	target_position = door_inside.global_position
	state = DroneState.FLYING


func _advance_doorway_route() -> void:
	if travel_direction == TravelDirection.TO_STORE:
		if doorway_stage == 0:
			doorway_stage = 1
			target_position = door_outside.global_position
		else:
			travel_direction = TravelDirection.NONE
			target_position = product_points[current_target_index]

	elif travel_direction == TravelDirection.FROM_STORE:
		if doorway_stage == 0:
			doorway_stage = 1
			target_position = door_inside.global_position
		else:
			travel_direction = TravelDirection.NONE
			target_position = home_position
			state = DroneState.RETURNING


func _update_ride_platform_rotation() -> void:
	ride_platform.global_rotation = Vector3.ZERO


func _update_flight(delta: float) -> void:
	var direction: Vector3 = target_position - global_position
	var distance: float = direction.length()

	var using_doorway: bool = (
		travel_direction != TravelDirection.NONE
	)

	# Doorway markers are pass-through waypoints.
	# No need to slow to a complete stop.
	if using_doorway and distance <= doorway_arrival_distance:
		_advance_doorway_route()
		return

	# Product displays and home still require a full stop.
	if not using_doorway:
		if distance <= arrival_distance and current_speed <= 0.08:
			current_speed = 0.0

			if state == DroneState.RETURNING:
				state = DroneState.IDLE
				return

			pause_timer = pause_duration
			state = DroneState.PAUSED
			network_beam_active = true
			pickup_started = false
			return

	if distance <= 0.0001:
		return

	direction = direction.normalized()

	var desired_speed: float = flight_speed

	if using_doorway:
		# Maintain a controlled speed through the doorway.
		desired_speed = doorway_speed
	else:
		# Existing smooth braking for product displays and home.
		var braking_factor: float = clampf(
			distance / maxf(braking_distance, 0.001),
			0.0,
			1.0
		)

		braking_factor = smoothstep(0.0, 1.0, braking_factor)
		desired_speed = flight_speed * braking_factor

	current_speed = move_toward(
		current_speed,
		desired_speed,
		acceleration * delta
	)

	var movement: float = minf(current_speed * delta, distance)
	global_position += direction * movement

	var horizontal_direction: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	)

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
		travel_direction = TravelDirection.FROM_STORE
		doorway_stage = 0

		target_position = door_outside.global_position
		state = DroneState.FLYING
		return

	target_position = product_points[current_target_index]
	state = DroneState.FLYING


func _update_tractor_beam(delta: float) -> void:
	var target_extension: float = 1.0 if network_beam_active else 0.0

	var duration: float = (
		beam_activation_time
		if network_beam_active
		else beam_deactivation_time
	)

	var step: float = delta / maxf(duration, 0.001)

	beam_extension = move_toward(
		beam_extension,
		target_extension,
		step
	)

	var cutoff: float = 1.0 - beam_extension

	beam_cone.set_instance_shader_parameter(
		"beam_cutoff",
		cutoff
	)

	energy_rings.set_instance_shader_parameter(
		"beam_cutoff",
		cutoff
	)


func _begin_test_pickup() -> void:
	if not multiplayer.is_server():
		return

	var displays: Array[Node] = get_tree().get_nodes_in_group(
		"product_displays"
	)

	var valid_displays: Array[Node3D] = []

	for display: Node in displays:
		var shopper_point: Marker3D = (
			display.get_node_or_null("AIShopperPoint") as Marker3D
		)

		if shopper_point != null:
			valid_displays.append(display as Node3D)

	if current_target_index >= valid_displays.size():
		return

	var display: Node3D = valid_displays[current_target_index]

	var data: ProductData = display.get("product_data") as ProductData

	if data == null or data.product_mesh == null:
		return

	if data.resource_path.is_empty():
		return

	var product_grid: Node3D = (
		display.get_node_or_null("ProductGrid") as Node3D
	)

	if product_grid == null:
		return

	# Approximate the centre of a product on the shelf.
	var mesh_bounds: AABB = data.product_mesh.get_aabb()

	var start_position: Vector3 = product_grid.to_global(
		mesh_bounds.get_center()
	)

	_start_product_pickup.rpc(
		data.resource_path,
		start_position
	)


@rpc("authority", "call_local", "reliable")
func _start_product_pickup(
	product_path: String,
	start_world_position: Vector3
) -> void:
	if pickup_product != null:
		pickup_product.queue_free()
		pickup_product = null

	var data: ProductData = load(product_path) as ProductData

	if data == null or data.product_mesh == null:
		return

	pickup_product = MeshInstance3D.new()
	pickup_product.mesh = data.product_mesh
	pickup_product.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pickup_product.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	tractor_beam.add_child(pickup_product)

	# Convert the shelf position into the beam's local space.
	pickup_start_position = tractor_beam.to_local(start_world_position)

	pickup_product.position = pickup_start_position
	pickup_product.rotation = Vector3.ZERO
	pickup_product.scale = Vector3.ONE

	pickup_elapsed = 0.0


func _update_product_pickup(delta: float) -> void:
	if pickup_product == null:
		return

	pickup_elapsed += delta

	var progress: float = clampf(
		pickup_elapsed / maxf(pickup_duration, 0.001),
		0.0,
		1.0
	)

	var centered_position: Vector3 = Vector3(
		0.0,
		pickup_start_position.y,
		0.0
	)

	if progress < pickup_centering_fraction:
		# Stage 1: Pull the product horizontally
		# toward the centre of the tractor beam.
		var center_progress: float = clampf(
			progress / pickup_centering_fraction,
			0.0,
			1.0
		)

		center_progress = smoothstep(
			0.0,
			1.0,
			center_progress
		)

		pickup_product.position = pickup_start_position.lerp(
			centered_position,
			center_progress
		)

	else:
		# Stage 2: Lift the product straight up
		# through the centre of the beam.
		var lift_progress: float = clampf(
			(progress - pickup_centering_fraction)
			/ (1.0 - pickup_centering_fraction),
			0.0,
			1.0
		)

		lift_progress = smoothstep(
			0.0,
			1.0,
			lift_progress
		)

		pickup_product.position = centered_position.lerp(
			Vector3.ZERO,
			lift_progress
		)

	# Keep the product gently rotating throughout.
	pickup_product.rotation.x += pickup_rotation_speed * delta

	# Shrink near the end of the upward movement.
	var shrink_progress: float = smoothstep(
		0.70,
		1.0,
		progress
	)

	var product_scale: float = lerpf(
		1.0,
		pickup_end_scale,
		shrink_progress
	)

	pickup_product.scale = Vector3.ONE * product_scale

	if progress >= 1.0:
		_finish_product_pickup()


func _finish_product_pickup() -> void:
	if pickup_product == null:
		return

	pickup_product.queue_free()
	pickup_product = null
