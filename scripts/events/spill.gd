extends Node3D
class_name Spill


@export_group("Spill Growth")
@export var growth_duration: float = 4.0
@export var initial_scale: float = 0.01

@onready var spill_mesh: MeshInstance3D = $SpillMesh

var shopping_point_path: NodePath = NodePath()


func _ready() -> void:
	add_to_group("active_spills")

	spill_mesh.scale = Vector3.ONE * initial_scale

	var tween: Tween = create_tween()
	tween.tween_property(
		spill_mesh,
		"scale",
		Vector3.ONE,
		growth_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
