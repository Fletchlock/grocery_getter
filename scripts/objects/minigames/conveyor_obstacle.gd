
extends AnimatableBody3D
class_name ConveyorObstacle


@export var movement_enabled: bool = true

var conveyor_belt: ConveyorBelt = null


func configure_product(product: ProductData, target_height: float = 2.5) -> void:
	if product == null or product.product_mesh == null:
		push_warning("CONVEYOR: Product has no mesh.")
		return

	var mesh_instance: MeshInstance3D = $MeshInstance3D
	var collision: CollisionShape3D = $CollisionShape3D

	var mesh: Mesh = product.product_mesh
	var bounds: AABB = mesh.get_aabb()

	if bounds.size.y <= 0.0:
		return

	var scale_factor: float = target_height / bounds.size.y
	var scaled_size: Vector3 = bounds.size * scale_factor

	# Use the existing mesh, but scale and center it.
	mesh_instance.mesh = mesh
	mesh_instance.scale = Vector3.ONE * scale_factor
	mesh_instance.position = Vector3(
		-bounds.get_center().x * scale_factor,
		-bounds.position.y * scale_factor,
		-bounds.get_center().z * scale_factor
	)

	# Each obstacle needs its own collision shape.
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = scaled_size

	collision.shape = box_shape
	collision.position = Vector3(0.0, scaled_size.y * 0.5, 0.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not movement_enabled:
		return

	if not is_instance_valid(conveyor_belt):
		return

	global_position += conveyor_belt.get_belt_velocity() * delta
