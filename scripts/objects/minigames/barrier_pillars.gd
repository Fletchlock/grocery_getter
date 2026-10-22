extends Node3D
class_name BarrierPillars


enum BarrierType {
	HIGH,
	LOW,
	FULL
}


@export var barrier_type: BarrierType = BarrierType.FULL

@export var beam_width: float = 3.7
@export var beam_thickness: float = 0.05

@export var low_height: float = 0.00
@export var high_bottom: float = 2.0
@export var full_height: float = 4.0


@onready var beam_visual: MeshInstance3D = $BeamVisual
@onready var beam_body: StaticBody3D = $BeamBody
@onready var beam_collision: CollisionShape3D = $BeamBody/CollisionShape3D


func _ready() -> void:
	_setup_barrier()


func _setup_barrier() -> void:
	var height: float = 0.0
	var center_y: float = 0.0

	match barrier_type:
		BarrierType.LOW:
			height = low_height
			center_y = height * 0.5

		BarrierType.HIGH:
			height = maxf(full_height - high_bottom, 0.05)
			center_y = high_bottom + height * 0.5

		BarrierType.FULL:
			height = full_height
			center_y = height * 0.5

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
	beam_body.position.y = center_y
