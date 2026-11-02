
extends Node3D
class_name Spill


@export_group("Spill Growth")
@export var growth_duration: float = 4.0
@export var initial_scale: float = 0.01

@export_group("Cleaning")
@export var cleaning_duration: float = 3.0
@export var prompt_height: float = 0.15

@onready var spill_mesh: MeshInstance3D = $SpillMesh

var shopping_point_path: NodePath = NodePath()
var cleaning_visual_active: bool = false
var cleaning_visual_scale: Vector3 = Vector3.ONE


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


func get_interaction_prompt_for_player(
	player: CharacterBody3D
) -> String:
	if player == null:
		return ""

	if player.get("held_mop") == null:
		return ""

	return "[Hold E] Clean Spill"


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
) -> Vector3:
	return collision_shape.global_position + Vector3.UP * prompt_height


func update_cleaning_visual(progress: float) -> void:
	if not cleaning_visual_active:
		cleaning_visual_active = true
		cleaning_visual_scale = spill_mesh.scale

	var amount: float = clampf(progress, 0.0, 1.0)

	spill_mesh.scale = cleaning_visual_scale.lerp(
		Vector3.ONE * 0.01,
		amount
	)


func reset_cleaning_visual() -> void:
	if not cleaning_visual_active:
		return

	spill_mesh.scale = cleaning_visual_scale
	cleaning_visual_active = false
