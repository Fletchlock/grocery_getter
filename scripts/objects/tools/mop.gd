extends Node3D
class_name Mop


@export_group("Visuals")
@export var outline_material: Material
@export var outline_scale: Vector3 = Vector3(1.06, 1.01, 1.06)

@export_group("Interaction")
@export var prompt_height: float = 0.25

var is_available: bool = true
var holder_peer_id: int = 0

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
	outline_instance.material_override = outline_material

	mesh_outline.add_child(outline_instance)

	# Match the mop's position and rotation.
	outline_instance.global_transform = mop_mesh.global_transform

	# Scale each axis independently.
	outline_instance.scale *= outline_scale


func get_interaction_prompt_for_player(
	_player: CharacterBody3D
) -> String:
	if not is_available:
		return ""
	if _player.has_method("is_holding_equipment"):
		if _player.is_holding_equipment():
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



func server_claim(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if not is_available:
		return false

	holder_peer_id = peer_id
	set_mop_available.rpc(false, peer_id)

	return true


func server_return(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if is_available:
		return false

	if holder_peer_id != peer_id:
		return false

	holder_peer_id = 0
	set_mop_available.rpc(true, 0)

	return true


@rpc("authority", "call_local", "reliable")
func set_mop_available(
	available: bool,
	peer_id: int
) -> void:
	is_available = available
	holder_peer_id = peer_id

	mop_mesh.visible = available

	var pickup_area: Area3D = $Area3D
	pickup_area.monitoring = available
	pickup_area.monitorable = available

	var collision_shape: CollisionShape3D = (
		pickup_area.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)

	if collision_shape != null:
		collision_shape.set_deferred("disabled", not available)

	if mesh_outline != null:
		mesh_outline.visible = false
