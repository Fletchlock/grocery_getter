
extends Node3D


@export_group("Shopper Spawning")
@export var shopper_scene: PackedScene
@export var shopper_meshes: Array[Mesh]
@export var max_shoppers: int = 10
@export var spawn_interval_min: float = 30.0
@export var spawn_interval_max: float = 60.0
@export var spawn_points: Array[Marker3D]

@onready var multiplayer_shopper_spawner: MultiplayerSpawner = $"../MultiplayerShopperSpawner"
@onready var shopper_stats: Node3D = $"../ShopperStats"


var last_spawn_point: Marker3D = null
var shopper_mesh_pool: Array[int] = []
var spawn_timer: float = 0.0


func _ready() -> void:
	randomize()

	multiplayer_shopper_spawner.spawn_function = _spawn_shopper

	refill_mesh_pool()
	set_next_spawn_timer()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Check if store open before spawning shoppers.
	if not DayManager.store_open:
		return

	# Check if rush hour.
	if DayManager.rush_hour:
		spawn_interval_min = 10
		spawn_interval_max = 20
	else:
		spawn_interval_min = 20
		spawn_interval_max = 50

	spawn_timer -= delta

	if spawn_timer <= 0.0:
		if get_spawned_shopper_count() < max_shoppers:
			spawn_shopper()

		set_next_spawn_timer()


func set_next_spawn_timer() -> void:
	spawn_timer = randf_range(
		spawn_interval_min,
		spawn_interval_max
	)


func get_active_shopper_count() -> int:
	return get_tree().get_nodes_in_group("shopper_in_store").size()


func get_spawned_shopper_count() -> int:
	return get_tree().get_nodes_in_group("shopper_ai").size()


func refill_mesh_pool() -> void:
	shopper_mesh_pool.clear()

	for i: int in range(shopper_meshes.size()):
		if shopper_meshes[i] != null:
			shopper_mesh_pool.append(i)

	shopper_mesh_pool.shuffle()


func spawn_shopper() -> void:
	if shopper_scene == null or shopper_meshes.is_empty():
		return

	if shopper_mesh_pool.is_empty():
		refill_mesh_pool()

	if shopper_mesh_pool.is_empty():
		return

	if spawn_points.is_empty():
		return

	var available_spawn_points: Array[Marker3D] = spawn_points.duplicate()

	if last_spawn_point != null and available_spawn_points.size() > 1:
		available_spawn_points.erase(last_spawn_point)

	var spawn_point: Marker3D = available_spawn_points.pick_random()
	last_spawn_point = spawn_point

	var mesh_index: int = shopper_mesh_pool.pop_back()

	var shopper: Node3D = multiplayer_shopper_spawner.spawn(
		mesh_index
	) as Node3D

	if shopper == null:
		return

	shopper.global_position = spawn_point.global_position

	if shopper.has_signal("reached_enter_point"):
		shopper.reached_enter_point.connect(
			_on_shopper_reached_enter_point
		)

	if shopper.has_signal("finished_shopping"):
		shopper.finished_shopping.connect(
			_on_shopper_finished_shopping
		)

	if shopper.has_signal("checkout_completed"):
		shopper.checkout_completed.connect(
			_on_shopper_checkout_completed
		)


func _spawn_shopper(data: Variant) -> Node:
	var mesh_index: int = int(data)

	if shopper_scene == null:
		return null

	if mesh_index < 0 or mesh_index >= shopper_meshes.size():
		return null

	var shopper: ShopperAI = shopper_scene.instantiate() as ShopperAI

	if shopper == null:
		return null

	shopper.set_shopper_mesh(shopper_meshes[mesh_index])

	return shopper


func _on_shopper_checkout_completed(
	purchase_total: float
) -> void:
	if not multiplayer.is_server():
		return

	shopper_stats.record_purchase(purchase_total)


func _on_shopper_finished_shopping() -> void:
	if not multiplayer.is_server():
		return

	shopper_stats.current_shoppers -= 1


func _on_shopper_reached_enter_point() -> void:
	if multiplayer.is_server():
		shopper_stats.current_shoppers += 1
	else:
		shopper_stats._current_shoppers += 1
