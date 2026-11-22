extends Node3D

signal warp_departure_finished

@export_group("Floating")
@export var float_height: float = 0.2
@export var float_speed: float = 0.8

@export_group("Rotation")
@export var rotation_speed: float = 5.0
@export var rotation_fade_duration: float = 5.0
@export var rotation_fade_exponent: float = 5.0

@export_group("Drifting")
@export var drift_distance: float = 0.15
@export var drift_speed: float = 0.4

@export_group("Warp Departure")
@export var warp_delay: float = 0.2
@export var charge_duration: float = 0.3
@export var charge_recoil_distance: float = 1.5
@export var warp_duration: float = 0.8
@export var warp_distance: float = 300.0
@export var warp_light_fade_exponent: float = 5.0
@export var charge_light_multiplier: float = 2.5
@export var charge_light_radius_multiplier: float = 1.01
@export var warp_flash_multiplier: float = 4.0
@export var warp_flash_duration: float = 0.6
@export var warp_flash_color: Color = Color(0.85, 0.80, 1.0)

var minimum_warp_angle: float = 5.625
var maximum_warp_angle: float = 16.875


var starting_position: Vector3
var elapsed_time: float = 0.0
var rotation_fade_time: float = 0.0
var is_departing: bool = false

@onready var light_fade_in: Node = $LightFadeIn


func _ready() -> void:
	starting_position = position


func _process(delta: float) -> void:
	if is_departing:
		return

	elapsed_time += delta
	rotation_fade_time += delta

	# Gentle vertical floating
	position.y = (
		starting_position.y
		+ sin(elapsed_time * float_speed) * float_height
	)

	# Very subtle side-to-side drifting
	position.x = (
		starting_position.x
		+ sin(elapsed_time * drift_speed) * drift_distance
	)

	# Exponential rotation fade-in
	var fade_progress: float = clampf(
		rotation_fade_time / rotation_fade_duration,
		0.0,
		1.0
	)

	var rotation_multiplier: float = pow(
		fade_progress,
		rotation_fade_exponent
	)

	# Gradually reach the normal rotation speed
	rotate_y(
		deg_to_rad(rotation_speed * rotation_multiplier * delta)
	)


func begin_warp_departure() -> void:
	if is_departing:
		return

	is_departing = true

	# Stop any unfinished lighting fade-in
	light_fade_in.call("stop_fade")

	# Brief pause before charging
	await get_tree().create_timer(warp_delay).timeout

	# Randomly choose left or right
	var horizontal_direction: float = (
		-1.0 if randf() < 0.5 else 1.0
	)

	# Choose a random diagonal angle
	var warp_angle: float = deg_to_rad(
		randf_range(minimum_warp_angle, maximum_warp_angle)
	)

	# Build a direction exclusively along the X and Z axes
	var warp_direction: Vector3 = Vector3(
		horizontal_direction * sin(warp_angle),
		0.0,
		-cos(warp_angle)
	).normalized()

	# Recoil in the exact opposite direction
	var charge_position: Vector3 = (
		global_position - warp_direction * charge_recoil_distance
	)

	_swell_charge_lights()

	var charge_tween: Tween = create_tween()

	charge_tween.tween_property(
		self,
		"global_position",
		charge_position,
		charge_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await charge_tween.finished

	# Launch in the randomized direction
	var departure_start: Vector3 = global_position
	var departure_end: Vector3 = (
		departure_start + warp_direction * warp_distance
	)

	var warp_tween: Tween = create_tween()

	warp_tween.tween_property(
		self,
		"global_position",
		departure_end,
		warp_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# Flash and fade the designated underside lights
	_flash_and_fade_warp_lights()

	await warp_tween.finished

	warp_departure_finished.emit()


func _set_warp_position(
	progress: float,
	start_position: Vector3,
	end_position: Vector3
) -> void:
	global_position = start_position.lerp(
		end_position,
		progress
	)


func _set_warp_light_energy(
	progress: float,
	light: Light3D,
	starting_energy: float
) -> void:
	var brightness: float = 1.0 - pow(
		progress,
		warp_light_fade_exponent
	)

	light.light_energy = starting_energy * brightness


func _collect_lights(node: Node, lights: Array[Light3D]) -> void:
	if node is Light3D:
		lights.append(node)

	for child in node.get_children():
		_collect_lights(child, lights)


func _flash_and_fade_warp_lights() -> void:
	var flash_lights: Array[Node] = get_tree().get_nodes_in_group(
		"warp_flash_lights"
	)

	for light in flash_lights:
		if not light is Light3D:
			continue

		var original_energy: float = light.light_energy
		var original_color: Color = light.light_color
		var original_range: float = light.omni_range

		var flash_tween: Tween = create_tween()

		# Initial bright purple-white flash
		flash_tween.set_parallel(true)

		flash_tween.tween_property(
			light,
			"light_energy",
			original_energy * warp_flash_multiplier,
			warp_flash_duration
		)

		flash_tween.tween_property(
			light,
			"light_color",
			warp_flash_color,
			warp_flash_duration
		)

		flash_tween.tween_property(
			light,
			"omni_range",
			original_range,
			0.15
		)

		# After the flash, fade the light completely out
		flash_tween.set_parallel(false)

		flash_tween.tween_property(
			light,
			"light_energy",
			0.0,
			maxf(warp_duration - warp_flash_duration, 0.01)
		)

		# Restore its original color while it fades
		flash_tween.set_parallel(true)

		flash_tween.tween_property(
			light,
			"light_color",
			original_color,
			0.15
		)


func _swell_charge_lights() -> void:
	var flash_lights: Array[Node] = get_tree().get_nodes_in_group(
		"warp_flash_lights"
	)

	for light in flash_lights:
		if not light is OmniLight3D:
			continue

		var starting_energy: float = light.light_energy
		var starting_range: float = light.omni_range

		var charge_tween: Tween = create_tween()
		charge_tween.set_parallel(true)

		# Gradually increase brightness
		charge_tween.tween_property(
			light,
			"light_energy",
			starting_energy * charge_light_multiplier,
			charge_duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

		# Gradually expand the light radius
		charge_tween.tween_property(
			light,
			"omni_range",
			starting_range * charge_light_radius_multiplier,
			charge_duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
