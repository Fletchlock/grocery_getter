extends Node3D
class_name Mop


@export_group("Visuals")
@export var outline_material: Material

@export_group("Interaction")
@export var prompt_height: float = 0.25

var is_available: bool = true

@onready var mop_mesh: MeshInstance3D = $MopMesh
@onready var mesh_outline: Node3D = $Area3D/MeshOutline


func _ready() -> void:
	_create_outline()


func _create_outline() -> void:
	if mop_mesh.mesh == null:
		return

	if outline_material == null:
		return

	var outline_instance: MeshInstance3D = MeshInstance3D.new()

	outline_instance.mesh = mop_mesh.mesh
	outline_instance.transform = mop_mesh.transform
	outline_instance.scale = Vector3(1.03, 1.03, 1.03)
	outline_instance.material_override = outline_material

	mesh_outline.add_child(outline_instance)


func get_interaction_prompt_for_player(
	_player: CharacterBody3D
) -> String:
	if not is_available:
		return ""

	return "[E] Pick Up Mop"


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
) -> Vector3:
	return collision_shape.global_position + Vector3.UP * prompt_height


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not is_available:
		return

	if not player.has_method("request_pickup_mop"):
		return

	player.request_pickup_mop(self)


func server_claim() -> bool:
	if not multiplayer.is_server():
		return false

	if not is_available:
		return false

	is_available = false
	set_mop_available.rpc(false)

	return true


@rpc("authority", "call_local", "reliable")
func set_mop_available(available: bool) -> void:
	is_available = available
	visible = available

	var area: Area3D = get_node_or_null("Area3D") as Area3D

	if area != null:
		area.monitoring = available
		area.monitorable = available

		var collision_shape: CollisionShape3D = (
			area.get_node_or_null("CollisionShape3D")
			as CollisionShape3D
		)

		if collision_shape != null:
			collision_shape.set_deferred("disabled", not available)
