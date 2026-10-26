
extends Node3D
class_name BarrierPillars


enum BarrierType {
	HIGH,
	LOW,
	FULL
}


@export var barrier_type: BarrierType = BarrierType.FULL

@export_group("Beam")
@export var beam_width: float = 16.22
@export var beam_thickness: float = 0.005

@export_group("Low Barrier")
@export var low_start: float = 0.5
@export var low_height: float = 1.5

@export_group("High Barrier")
@export var high_start: float = 2.7
@export var high_height: float = 2.0

@export_group("Full Barrier")
@export var full_start: float = 0.5
@export var full_height: float = 5.5

@export_group("Animation")
@export var extension_time: float = 0.15
@export var active_duration: float = 4.0
@export var retraction_time: float = 0.15

@export_group("Timing")
@export var minimum_interval: float = 1.5
@export var maximum_interval: float = 4.5


@onready var beam_visual: MeshInstance3D = $BeamVisual
@onready var beam_collision: CollisionShape3D = $BeamBody/CollisionShape3D


var barrier_enabled: bool = false
var running: bool = false
var interval_timer: float = 0.0
var beam_tween: Tween
var activation_id: int = 0


func _ready() -> void:
	_setup_barrier()
	_reset_beam()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not barrier_enabled or not running:
		return

	interval_timer -= delta

	if interval_timer <= 0.0:
		running = false
		_activate_beam.rpc()


func _setup_barrier() -> void:
	var start: float = 0.0
	var height: float = 0.0

	match barrier_type:
		BarrierType.LOW:
			start = low_start
			height = low_height

		BarrierType.HIGH:
			start = high_start
			height = high_height

		BarrierType.FULL:
			start = full_start
			height = full_height

	# Pillars are 6m tall, centered at Y = 0.
	var center_y: float = -3.0 + start + height * 0.5

	var beam_size: Vector3 = Vector3(
		beam_width,
		height,
		beam_thickness
	)

	var visual_mesh: BoxMesh = beam_visual.mesh.duplicate() as BoxMesh
	visual_mesh.size = beam_size
	beam_visual.mesh = visual_mesh

	var collision_shape: BoxShape3D = beam_collision.shape.duplicate() as BoxShape3D
	collision_shape.size = beam_size
	beam_collision.shape = collision_shape

	beam_visual.position.y = center_y
	beam_collision.position.y = center_y


func start_barrier() -> void:
	if not multiplayer.is_server():
		return

	if barrier_enabled:
		return

	barrier_enabled = true
	running = true
	_schedule_next_activation()


func _schedule_next_activation() -> void:
	interval_timer = randf_range(
		minimum_interval,
		maximum_interval
	)


@rpc("authority", "call_local", "reliable")
func _activate_beam() -> void:
	activation_id += 1
	var current_activation: int = activation_id

	if beam_tween and beam_tween.is_running():
		beam_tween.kill()

	_reset_beam()

	# Extend from left to right.
	beam_tween = create_tween()
	beam_tween.set_parallel(true)

	beam_tween.tween_property(
		beam_visual,
		"scale:x",
		1.0,
		extension_time
	)

	beam_tween.tween_property(
		beam_visual,
		"position:x",
		0.0,
		extension_time
	)

	await beam_tween.finished

	if not is_inside_tree() or current_activation != activation_id:
		return

	beam_collision.set_deferred("disabled", false)

	await get_tree().create_timer(active_duration).timeout

	if not is_inside_tree() or current_activation != activation_id:
		return

	beam_collision.set_deferred("disabled", true)

	# Retract toward the right pillar.
	beam_tween = create_tween()
	beam_tween.set_parallel(true)

	beam_tween.tween_property(
		beam_visual,
		"scale:x",
		0.001,
		retraction_time
	)

	beam_tween.tween_property(
		beam_visual,
		"position:x",
		beam_width * 0.5,
		retraction_time
	)

	await beam_tween.finished

	if not is_inside_tree() or current_activation != activation_id:
		return

	# Only the host schedules the next activation.
	if multiplayer.is_server() and barrier_enabled:
		running = true
		_schedule_next_activation()


func _reset_beam() -> void:
	beam_visual.scale.x = 0.001
	beam_visual.position.x = -beam_width * 0.5
	beam_collision.set_deferred("disabled", true)


func stop_barrier() -> void:
	barrier_enabled = false
	running = false
	activation_id += 1

	if beam_tween and beam_tween.is_running():
		beam_tween.kill()

	_reset_beam()
