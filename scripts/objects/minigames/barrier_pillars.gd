
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


@onready var beam_visual: MeshInstance3D = $BeamVisual
@onready var beam_collision: CollisionShape3D = $BeamBody/CollisionShape3D


func _ready() -> void:
	_setup_barrier()


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

	# Pillar meshes are centered at Y = 0.
	# Their bottom is at Y = -3.0.
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
