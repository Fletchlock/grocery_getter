
extends Node3D
class_name Spill


@export_group("Spill Growth")
@export var growth_duration: float = 4.0
@export var initial_scale: float = 0.01

@export_group("Cleaning")
@export var cleaning_duration: float = 3.0
@export var prompt_height: float = 0.15

@export_group("Cleaning Target")
@export var target_move_speed: float = 0.18
@export var target_wander_radius_x: float = 0.25
@export var target_wander_radius_z: float = 0.15
@export var target_direction_interval_min: float = 0.7
@export var target_direction_interval_max: float = 1.2
@export var target_turn_speed: float = 4.0

@onready var spill_mesh: MeshInstance3D = $SpillMesh
@onready var cleaning_bubbles: GPUParticles3D = $CleaningBubbles
@onready var cleaning_target: Node3D = $CleaningTarget
@onready var target_sprite: Sprite3D = $CleaningTarget/TargetSprite

const CLEAN_SPARKLES_SCENE: PackedScene = preload(
	"res://scenes/events/clean_sparkles.tscn"
)

var shopping_point_path: NodePath = NodePath()
var spill_color: Color = Color.WHITE

var cleaning_visual_active: bool = false
var cleaning_visual_scale: Vector3 = Vector3.ONE
var cleaning_visual_elapsed: float = 0.0

var target_active: bool = false
var target_velocity: Vector3 = Vector3.ZERO
var target_desired_direction: Vector3 = Vector3.ZERO
var target_direction_timer: float = 0.0
var target_destination: Vector3 = Vector3.ZERO

var target_rng: RandomNumberGenerator = RandomNumberGenerator.new()

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
	
	start_target_movement()


func _process(delta: float) -> void:
	if target_active:
		_update_target_movement(delta)

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


# Sparkle particle emission
@rpc("authority", "call_local", "reliable")
func finish_network_cleaning() -> void:
	play_clean_sparkles()
	

func play_clean_sparkles() -> void:
	var sparkles: GPUParticles3D = (
		CLEAN_SPARKLES_SCENE.instantiate() as GPUParticles3D
	)

	get_tree().current_scene.add_child(sparkles)

	sparkles.global_position = global_position + Vector3.UP * 0.08


func start_target_movement() -> void:
	target_rng.randomize()

	target_active = true
	cleaning_target.position = Vector3(0.0, 0.05, 0.0)
	target_sprite.visible = true
	target_sprite.modulate = Color.RED

	target_velocity = Vector3.ZERO
	_choose_new_target_direction()


func stop_target_movement() -> void:
	target_active = false
	target_sprite.visible = false
	target_velocity = Vector3.ZERO


func _choose_new_target_direction() -> void:
	var angle: float = target_rng.randf_range(0.0, TAU)

	# Square root gives an even distribution across the ellipse's area.
	var radius: float = sqrt(target_rng.randf())

	target_destination = Vector3(
		cos(angle) * radius * target_wander_radius_x,
		0.05,
		sin(angle) * radius * target_wander_radius_z
	)

	target_direction_timer = target_rng.randf_range(
		target_direction_interval_min,
		target_direction_interval_max
	)


func _update_target_movement(delta: float) -> void:
	if not target_active:
		return

	target_direction_timer -= delta

	var current_position: Vector3 = cleaning_target.position
	var distance_to_destination: float = current_position.distance_to(
		target_destination
	)

	# Choose another destination when close enough or the timer expires.
	if distance_to_destination < 0.025 or target_direction_timer <= 0.0:
		_choose_new_target_direction()

	var direction: Vector3 = (
		target_destination - current_position
	).normalized()

	var desired_velocity: Vector3 = direction * target_move_speed

	target_velocity = target_velocity.lerp(
		desired_velocity,
		clampf(target_turn_speed * delta, 0.0, 1.0)
	)

	var next_position: Vector3 = current_position + target_velocity * delta

	# Keep the target inside the elliptical area.
	var radius_x: float = maxf(target_wander_radius_x, 0.001)
	var radius_z: float = maxf(target_wander_radius_z, 0.001)

	var normalized_x: float = next_position.x / radius_x
	var normalized_z: float = next_position.z / radius_z

	var boundary_distance: float = sqrt(
		normalized_x * normalized_x
		+ normalized_z * normalized_z
	)

	if boundary_distance > 1.0:
		next_position.x /= boundary_distance
		next_position.z /= boundary_distance
		target_velocity = Vector3.ZERO

	cleaning_target.position = next_position
