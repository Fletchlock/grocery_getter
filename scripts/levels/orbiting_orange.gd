
extends AnimatableBody3D
class_name OrbitingOrange


@export_group("Orbit Trail")
@export var trail_duration: float = 4.0
@export var trail_width: float = 0.15
@export var trail_color: Color = Color(1.0, 0.45, 0.05, 1.0)

@onready var orbit_trail: MeshInstance3D = $OrbitTrail

@export_group("Orange Rotation")
@export var spin_speed: float = 3.0

var spin_axis: Vector3 = Vector3.UP

var trail_points: Array[Vector3] = []
var trail_times: Array[float] = []
var trail_mesh: ImmediateMesh
var trail_material: StandardMaterial3D
var trail_elapsed: float = 0.0

var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 15.0
var orange_radius: float = 1.0
var orbit_duration: float = 6.67
var orbit_plane_angle: float = 0.0

var knockback_sideways: float = 2.0
var knockback_upward: float = 14.0
var knockback_cooldown: float = 0.8

var orbit_angle: float = 0.0
var movement_enabled: bool = false

var _last_hit_times: Dictionary = {}

@onready var mesh_instance: MeshInstance3D = $SpinPivot/MeshInstance3D
@onready var spin_pivot: Node3D = $SpinPivot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func configure(
	center: Vector3,
	path_radius: float,
	size_radius: float,
	duration: float,
	sideways: float,
	upward: float,
	cooldown: float
) -> void:
	orbit_center = center
	orbit_radius = path_radius
	orange_radius = size_radius
	orbit_duration = maxf(duration, 0.01)

	knockback_sideways = sideways
	knockback_upward = upward
	knockback_cooldown = cooldown


func _ready() -> void:
	var sphere_mesh: SphereMesh = mesh_instance.mesh as SphereMesh
	var sphere_shape: SphereShape3D = SphereShape3D.new()

	if sphere_mesh != null:
		sphere_mesh = sphere_mesh.duplicate() as SphereMesh
		sphere_mesh.radius = orange_radius
		sphere_mesh.height = orange_radius * 2.0
		mesh_instance.mesh = sphere_mesh

	sphere_shape.radius = orange_radius
	collision_shape.shape = sphere_shape
	
	spin_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	if spin_axis.length_squared() < 0.001:
		spin_axis = Vector3.UP
	
	_update_orbit_position()
	
	# Orbit Trail Lines
	trail_mesh = ImmediateMesh.new()
	orbit_trail.mesh = trail_mesh
	orbit_trail.top_level = true
	orbit_trail.global_transform = Transform3D.IDENTITY

	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.vertex_color_use_as_albedo = true
	trail_material.no_depth_test = false
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.emission_enabled = true
	trail_material.emission = trail_color
	trail_material.emission_energy_multiplier = 4.0

func _physics_process(delta: float) -> void:
	if not movement_enabled:
		return

	orbit_angle = fposmod(
		orbit_angle + TAU / orbit_duration * delta,
		TAU
	)

	_update_orbit_position()
	
	spin_pivot.rotate_object_local(spin_axis, spin_speed * delta)
	
	_update_trail(delta)

	if multiplayer.is_server():
		_check_player_collisions()


func _update_orbit_position() -> void:
	var orbit_direction: Vector3 = Vector3(
		sin(orbit_angle) * sin(orbit_plane_angle),
		-cos(orbit_angle),
		sin(orbit_angle) * cos(orbit_plane_angle)
	)

	global_position = orbit_center + orbit_direction * orbit_radius


func _check_player_collisions() -> void:
	var space_state: PhysicsDirectSpaceState3D = (
		get_world_3d().direct_space_state
	)

	var query: PhysicsShapeQueryParameters3D = (
		PhysicsShapeQueryParameters3D.new()
	)

	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	var results: Array[Dictionary] = space_state.intersect_shape(
		query,
		16
	)

	var now: float = Time.get_ticks_msec() / 1000.0

	for result: Dictionary in results:
		var player: CharacterBody3D = (
			result["collider"] as CharacterBody3D
		)

		if player == null:
			continue

		if not player.has_method("receive_conveyor_knockback"):
			continue

		var peer_id: int = player.get_multiplayer_authority()
		var last_hit: float = float(_last_hit_times.get(peer_id, -100.0))

		if now - last_hit < knockback_cooldown:
			continue

		_last_hit_times[peer_id] = now

		# Direction away from the small orange.
		var direction: Vector3 = (
			player.global_position - global_position
		)

		# Use the surface normal for "up" on the large orange.
		var surface_up: Vector3 = (
			player.global_position - orbit_center
		).normalized()

		if surface_up.length_squared() < 0.001:
			surface_up = Vector3.UP

		var sideways: Vector3 = (
			direction - surface_up * direction.dot(surface_up)
		)

		if sideways.length_squared() < 0.001:
			sideways = Vector3.UP.cross(surface_up)

		if sideways.length_squared() < 0.001:
			sideways = Vector3.FORWARD

		sideways = sideways.normalized()

		var impulse: Vector3 = (
			sideways * knockback_sideways
			+ surface_up * knockback_upward
		)

		if peer_id == 1:
			player.receive_conveyor_knockback(impulse)
		else:
			player.apply_conveyor_knockback.rpc_id(peer_id, impulse)

func _update_trail(delta: float) -> void:
	trail_elapsed += delta

	trail_points.append(global_position)
	trail_times.append(trail_elapsed)

	while not trail_times.is_empty() and trail_elapsed - trail_times[0] > trail_duration:
		trail_times.remove_at(0)
		trail_points.remove_at(0)

	_rebuild_trail()


func _rebuild_trail() -> void:
	trail_mesh.clear_surfaces()

	if trail_points.size() < 2:
		return

	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, trail_material)

	for i: int in range(trail_points.size() - 1):
		var current: Vector3 = trail_points[i]
		var next: Vector3 = trail_points[i + 1]

		var direction: Vector3 = (next - current).normalized()
		var outward: Vector3 = (current - orbit_center).normalized()
		var side: Vector3 = direction.cross(outward).normalized() * trail_width * 0.5

		var age_a: float = trail_elapsed - trail_times[i]
		var age_b: float = trail_elapsed - trail_times[i + 1]

		var alpha_a: float = clampf(1.0 - age_a / trail_duration, 0.0, 1.0)
		var alpha_b: float = clampf(1.0 - age_b / trail_duration, 0.0, 1.0)

		var color_a: Color = trail_color
		color_a.a = alpha_a

		var color_b: Color = trail_color
		color_b.a = alpha_b

		var a_left: Vector3 = current - side
		var a_right: Vector3 = current + side
		var b_left: Vector3 = next - side
		var b_right: Vector3 = next + side

		trail_mesh.surface_set_color(color_a)
		trail_mesh.surface_add_vertex(a_left)

		trail_mesh.surface_set_color(color_b)
		trail_mesh.surface_add_vertex(b_left)

		trail_mesh.surface_set_color(color_a)
		trail_mesh.surface_add_vertex(a_right)

		trail_mesh.surface_set_color(color_a)
		trail_mesh.surface_add_vertex(a_right)

		trail_mesh.surface_set_color(color_b)
		trail_mesh.surface_add_vertex(b_left)

		trail_mesh.surface_set_color(color_b)
		trail_mesh.surface_add_vertex(b_right)

	trail_mesh.surface_end()
