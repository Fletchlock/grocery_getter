extends Node


@export_group("Spill Events")
@export_range(0.0, 100.0, 1.0) var spill_chance: float = 10.0
@export var spill_cooldown: float = 0.0
@export var max_active_spills: int = 20

const SPILL_SCENE: PackedScene = preload(
	"res://scenes/events/spill.tscn"
)

var spill_cooldown_remaining: float = 0.0

var events_container: Node3D = null
var event_spawner: MultiplayerSpawner = null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if spill_cooldown_remaining > 0.0:
		spill_cooldown_remaining = maxf(
			spill_cooldown_remaining - delta,
			0.0
		)


func setup_level(
	container: Node3D,
	spawner: MultiplayerSpawner
) -> void:
	events_container = container
	event_spawner = spawner

	event_spawner.spawn_function = _spawn_event

	print("EVENT MANAGER: Level setup complete.")


func _spawn_event(data: Variant) -> Node:
	var event_data: Dictionary = data as Dictionary

	var spill: Spill = SPILL_SCENE.instantiate() as Spill

	if spill == null:
		return null

	spill.position = event_data["position"]
	spill.rotation.y = float(event_data["rotation_y"])
	spill.shopping_point_path = NodePath(
		event_data["shopping_point_path"]
	)
	spill.spill_color = event_data["spill_color"]

	return spill


func on_shopper_at_point(
	shopper: ShopperAI,
	shopping_point: Node3D,
	product: ProductData
) -> void:
	if not multiplayer.is_server():
		return

	if not DayManager.store_open:
		return

	if not is_instance_valid(shopper):
		return

	if not is_instance_valid(shopping_point):
		return

	if not is_instance_valid(event_spawner):
		return

	if spill_cooldown_remaining > 0.0:
		return

	if get_active_spill_count() >= max_active_spills:
		return

	if has_spill_at_point(shopping_point):
		return

	if randf() * 100.0 >= spill_chance:
		return
	
	if product == null:
		return
	# Calculate the shopper's facing direction.
	var forward: Vector3 = Vector3(
		sin(shopper.target_rotation),
		0.0,
		cos(shopper.target_rotation)
	)

	# Spawn 30 cm in front of the shopper.
	var spill_position: Vector3 = (
		shopper.global_position + forward * 0.3
	)

	# Find the floor directly beneath the shopper.
	var space_state: PhysicsDirectSpaceState3D = (
		shopper.get_world_3d().direct_space_state
	)

	var ray_query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			spill_position + Vector3.UP * 0.5,
			spill_position + Vector3.DOWN * 2.0
		)
	)

	# Exclude the shopper's own collision body.
	ray_query.exclude = [shopper.get_rid()]

	var result: Dictionary = space_state.intersect_ray(ray_query)

	if result.is_empty():
		return

	spill_position = result["position"]

	# Convert world position into the Events container's local space.
	var local_position: Vector3 = (
		events_container.to_local(spill_position)
	)

	var spawn_data: Dictionary = {
		"position": local_position,
		"rotation_y": randf_range(0.0, TAU),
		"shopping_point_path": str(shopping_point.get_path()),
		"spill_color": product.spill_color
	}

	var spill: Node = event_spawner.spawn(spawn_data)

	if spill == null:
		return

	spill_cooldown_remaining = spill_cooldown

	print(
		"EVENT MANAGER: Spill spawned at ",
		shopping_point.name,
		" | Position: ",
		spill_position
	)


func get_active_spill_count() -> int:
	return get_tree().get_nodes_in_group("active_spills").size()


func has_spill_at_point(shopping_point: Node3D) -> bool:
	var point_path: NodePath = shopping_point.get_path()

	for node: Node in get_tree().get_nodes_in_group("active_spills"):
		var spill: Spill = node as Spill

		if spill == null:
			continue

		if spill.shopping_point_path == point_path:
			return true

	return false
