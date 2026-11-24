extends Node3D

@export_group("Product Resources")
@export_dir var product_directory: String = "res://resources/products"

@export_group("Spawning")
@export var maximum_products: int = 8
@export var minimum_spawn_interval: float = 2.5
@export var maximum_spawn_interval: float = 4.0
@export var initial_product_count: int = 2

@export_group("Product Size")
@export var minimum_product_size: float = 0.2
@export var maximum_product_size: float = 0.5

@export_group("Movement")
@export var minimum_speed: float = 0.7
@export var maximum_speed: float = 1.5
@export var minimum_rotation_speed: float = 10.0
@export var maximum_rotation_speed: float = 40.0

@export_group("Camera")
@export var base_spawn_depth: float = 22.8
@export var depth_variation: float = 10.0
@export var spawn_margin: float = 2.0

@export_group("UFO Avoidance")
@export var ufo_exclusion_radius: float = 7.0
@export var path_check_attempts: int = 40

var product_resources: Array[ProductData] = []
var active_products: Array[Dictionary] = []

var spawn_timer: Timer

@onready var camera: Camera3D = get_node_or_null(
	"../Camera3D"
) as Camera3D

@onready var ufo: Node3D = get_node_or_null(
	"../UFOFloat"
) as Node3D


func _ready() -> void:
	randomize()

	if camera == null:
		push_error("ProductSpawner: Camera3D not found.")
		return

	if ufo == null:
		push_error("ProductSpawner: UFOFloat not found.")
		return

	_load_product_resources()

	if product_resources.is_empty():
		push_error("ProductSpawner: No valid product resources found.")
		return

	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	add_child(spawn_timer)

	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	var starting_count: int = mini(
		initial_product_count,
		maximum_products
	)

	for i in range(starting_count):
		_spawn_product()

	_schedule_next_spawn()


func _process(delta: float) -> void:
	for i in range(active_products.size() - 1, -1, -1):
		var product_data: Dictionary = active_products[i]

		var product: MeshInstance3D = product_data["node"]

		if not is_instance_valid(product):
			active_products.remove_at(i)
			continue

		var velocity: Vector3 = product_data["velocity"]
		var angular_velocity: Vector3 = product_data["angular_velocity"]

		product.global_position += velocity * delta

		product.rotate_x(angular_velocity.x * delta)
		product.rotate_y(angular_velocity.y * delta)
		product.rotate_z(angular_velocity.z * delta)

		var camera_position: Vector3 = camera.to_local(
			product.global_position
		)

		var half_extents: Vector2 = product_data["half_extents"]

		var inside_view: bool = (
			absf(camera_position.x) <= half_extents.x
			and absf(camera_position.y) <= half_extents.y
		)

		if inside_view:
			product_data["has_entered_view"] = true

		if not product_data["has_entered_view"]:
			continue

		var outside_view: bool = (
			absf(camera_position.x) > half_extents.x + spawn_margin * 2.0
			or absf(camera_position.y) > half_extents.y + spawn_margin * 2.0
		)

		if outside_view:
			product.queue_free()
			active_products.remove_at(i)


func _load_product_resources() -> void:
	product_resources.clear()

	var files: PackedStringArray = ResourceLoader.list_directory(
		product_directory
	)

	for file_name in files:
		if not file_name.ends_with(".tres") \
		and not file_name.ends_with(".res"):
			continue

		var resource_path: String = product_directory.path_join(
			file_name
		)

		var product_data: ProductData = load(
			resource_path
		) as ProductData

		if product_data == null:
			continue

		if product_data.product_mesh == null:
			continue

		product_resources.append(product_data)

	product_resources.sort_custom(
		func(a: ProductData, b: ProductData) -> bool:
			return a.item_id < b.item_id
	)

	print(
		"ProductSpawner: Loaded ",
		product_resources.size(),
		" product resources."
	)


func _on_spawn_timer_timeout() -> void:
	if active_products.size() < maximum_products:
		_spawn_product()

	_schedule_next_spawn()


func _schedule_next_spawn() -> void:
	spawn_timer.wait_time = randf_range(
		minimum_spawn_interval,
		maximum_spawn_interval
	)

	spawn_timer.start()


func _spawn_product() -> void:
	if product_resources.is_empty():
		return

	if active_products.size() >= maximum_products:
		return

	var product_data: ProductData = product_resources.pick_random()

	var target_size: float = randf_range(
		minimum_product_size,
		maximum_product_size
	)

	var valid_path: bool = false
	var start_position: Vector3
	var end_position: Vector3
	var half_extents: Vector2

	for attempt in range(path_check_attempts):
		# Randomize depth independently for every trajectory.
		var depth: float = base_spawn_depth + randf_range(
			-depth_variation,
			depth_variation
		)

		if depth <= camera.near:
			continue

		var half_height: float = depth * tan(
			deg_to_rad(camera.fov * 0.5)
		)

		var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
		var aspect_ratio: float = viewport_size.x / viewport_size.y

		half_extents = Vector2(
			half_height * aspect_ratio,
			half_height
		)

		var start_edge: int = randi_range(0, 3)
		var end_edge: int = randi_range(0, 2)

		if end_edge >= start_edge:
			end_edge += 1

		var start_2d: Vector2 = _get_edge_position(
			start_edge,
			half_extents
		)

		var end_2d: Vector2 = _get_edge_position(
			end_edge,
			half_extents
		)

		# Convert screen-plane positions into actual 3D positions.
		start_position = camera.global_transform * Vector3(
			start_2d.x,
			start_2d.y,
			-depth
		)

		end_position = camera.global_transform * Vector3(
			end_2d.x,
			end_2d.y,
			-depth
		)

		# Check the entire 3D trajectory against the UFO.
		var exclusion_radius: float = (
			ufo_exclusion_radius + target_size * 0.5
		)

		if _path_avoids_ufo(
			start_position,
			end_position,
			ufo.global_position,
			exclusion_radius
		):
			valid_path = true
			break

	if not valid_path:
		return

	var world_velocity: Vector3 = (
		end_position - start_position
	).normalized() * randf_range(
		minimum_speed,
		maximum_speed
	)

	var product: MeshInstance3D = MeshInstance3D.new()
	product.mesh = product_data.product_mesh

	var mesh_size: Vector3 = product.mesh.get_aabb().size

	var largest_dimension: float = maxf(
		mesh_size.x,
		maxf(mesh_size.y, mesh_size.z)
	)

	if largest_dimension <= 0.0:
		return

	var product_scale: float = target_size / largest_dimension
	product.scale = Vector3.ONE * product_scale

	product.rotation = Vector3(
		randf_range(-PI, PI),
		randf_range(-PI, PI),
		randf_range(-PI, PI)
	)

	add_child(product)
	product.global_position = start_position

	var angular_velocity := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	angular_velocity *= deg_to_rad(
		randf_range(
			minimum_rotation_speed,
			maximum_rotation_speed
		)
	)

	active_products.append({
		"node": product,
		"velocity": world_velocity,
		"angular_velocity": angular_velocity,
		"half_extents": half_extents,
		"has_entered_view": false
	})

	print(
		"ProductSpawner: Spawned ",
		product_data.display_name
	)


func _get_edge_position(
	edge: int,
	half_extents: Vector2
) -> Vector2:
	var margin: float = spawn_margin

	match edge:
		0:
			return Vector2(
				-half_extents.x - margin,
				randf_range(-half_extents.y, half_extents.y)
			)

		1:
			return Vector2(
				half_extents.x + margin,
				randf_range(-half_extents.y, half_extents.y)
			)

		2:
			return Vector2(
				randf_range(-half_extents.x, half_extents.x),
				half_extents.y + margin
			)

		3:
			return Vector2(
				randf_range(-half_extents.x, half_extents.x),
				-half_extents.y - margin
			)

	return Vector2.ZERO


func _path_avoids_ufo(
	start: Vector3,
	finish: Vector3,
	center: Vector3,
	radius: float
) -> bool:
	var segment: Vector3 = finish - start
	var segment_length_squared: float = segment.length_squared()

	if segment_length_squared <= 0.0:
		return false

	var progress: float = clampf(
		(center - start).dot(segment) / segment_length_squared,
		0.0,
		1.0
	)

	var closest_point: Vector3 = start + segment * progress

	return closest_point.distance_to(center) > radius
