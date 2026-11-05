
extends Node3D
class_name Spill


@export_group("Spill Growth")
@export var growth_duration: float = 4.0
@export var initial_scale: float = 0.01

@export_group("Cleaning")
@export var cleaning_duration: float = 3.0
@export var prompt_height: float = 0.15

@onready var spill_mesh: MeshInstance3D = $SpillMesh
@onready var cleaning_bubbles: GPUParticles3D = $CleaningBubbles

var shopping_point_path: NodePath = NodePath()
var spill_color: Color = Color.WHITE

var cleaning_visual_active: bool = false
var cleaning_visual_scale: Vector3 = Vector3.ONE
var cleaning_visual_elapsed: float = 0.0

var growth_tween: Tween = null


func _ready() -> void:
	add_to_group("active_spills")
	cleaning_bubbles.emitting = false
	
	# Give this spill its own material instance.
	var material: Material = spill_mesh.get_active_material(0)

	if material is StandardMaterial3D:
		var spill_material: StandardMaterial3D = (
			material.duplicate() as StandardMaterial3D
		)

		# Preserve the existing material transparency.
		var original_alpha: float = spill_material.albedo_color.a

		spill_material.albedo_color = Color(
			spill_color.r,
			spill_color.g,
			spill_color.b,
			original_alpha
		)

		spill_mesh.material_override = spill_material

	spill_mesh.scale = Vector3.ONE * initial_scale

	growth_tween = create_tween()
	growth_tween.tween_property(
		spill_mesh,
		"scale",
		Vector3.ONE,
		growth_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not cleaning_visual_active:
		return

	cleaning_visual_elapsed += delta

	var progress: float = clampf(
		cleaning_visual_elapsed / cleaning_duration,
		0.0,
		1.0
	)

	update_cleaning_visual(progress)


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
	var amount: float = clampf(progress, 0.0, 1.0)

	spill_mesh.scale = cleaning_visual_scale.lerp(
		Vector3.ONE * 0.01,
		amount
	)


func reset_cleaning_visual() -> void:
	cleaning_visual_active = false
	cleaning_visual_elapsed = 0.0
	spill_mesh.scale = cleaning_visual_scale
	cleaning_bubbles.emitting = false

@rpc("authority", "call_local", "reliable")
func start_network_cleaning() -> void:
	if cleaning_visual_active:
		return

	if growth_tween != null and growth_tween.is_running():
		growth_tween.kill()

	cleaning_visual_scale = spill_mesh.scale
	cleaning_visual_elapsed = 0.0
	cleaning_visual_active = true
	cleaning_bubbles.restart()
	cleaning_bubbles.emitting = true

@rpc("authority", "call_local", "reliable")
func stop_network_cleaning() -> void:
	if not cleaning_visual_active:
		return

	reset_cleaning_visual()
