
extends AnimatableBody3D
class_name ConveyorObstacle


@export var movement_enabled: bool = true

var conveyor_belt: ConveyorBelt = null
var is_rolling: bool = false

@export var rolling_speed: float = 3.0


func configure_product(product: ProductData, scale_multiplier: float = 10.0) -> void:
	if product == null or product.product_mesh == null:
		push_warning("CONVEYOR: Product has no mesh.")
		return

	var mesh_instance: MeshInstance3D = $MeshInstance3D
	var collision: CollisionShape3D = $CollisionShape3D

	var mesh: Mesh = product.product_mesh
	var bounds: AABB = mesh.get_aabb()

	if bounds.size.y <= 0.0:
		return

	var scale_factor: float = scale_multiplier
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


func _process(delta: float) -> void:
	if not is_rolling:
		return

	if not movement_enabled:
		return

	$MeshInstance3D.rotate_x(rolling_speed * delta)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not movement_enabled:
		return

	if not is_instance_valid(conveyor_belt):
		return

	global_position += conveyor_belt.get_belt_velocity() * delta
