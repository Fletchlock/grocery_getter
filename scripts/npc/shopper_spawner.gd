extends Node3D


@export_group("Shopper Spawning")
@export var shopper_scene: PackedScene
@export var shopper_meshes: Array[Mesh]
@export var spawn_points: Array[Marker3D]

@export_group("Base Traffic")
@export var spawn_interval_min: float = 60.0
@export var spawn_interval_max: float = 85.0
@export var minimum_spawn_interval: float = 12.0

@export_group("Day Scaling")
@export var day_growth_rate: float = 0.05
@export var max_day_traffic_multiplier: float = 2.0

@export_group("Player Scaling")
@export var traffic_increase_per_player: float = 0.20
@export var extra_shoppers_per_player: int = 2

@export_group("Shopper Capacity")
@export var starting_max_shoppers: int = 3
@export var extra_shoppers_every_n_days: int = 3
@export var max_shoppers: int = 20

@export_group("Rush Hour")
@export var rush_hour_multiplier: float = 1.35

@onready var multiplayer_shopper_spawner: MultiplayerSpawner = $"../MultiplayerShopperSpawner"
@onready var shopper_stats: Node3D = $"../ShopperStats"

var last_spawn_point: Marker3D = null
var shopper_mesh_pool: Array[int] = []
var spawn_timer: float = 0.0
var last_open_day: int = 0
var current_max_shoppers: int = 1


func _ready() -> void:
	randomize()

	multiplayer_shopper_spawner.spawn_function = _spawn_shopper
	
	refill_mesh_pool()
	set_next_spawn_timer()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not DayManager.store_open:
		return

	current_max_shoppers = get_current_max_shoppers()

	# Spawn the first shopper immediately each day.
	if last_open_day != DayManager.current_day:
		last_open_day = DayManager.current_day

		if get_spawned_shopper_count() < current_max_shoppers:
			spawn_shopper()

		set_next_spawn_timer()
		return

	spawn_timer -= delta

	if spawn_timer <= 0.0:
		if get_spawned_shopper_count() < current_max_shoppers:
			spawn_shopper()

		set_next_spawn_timer()


func set_next_spawn_timer() -> void:
	var traffic_multiplier: float = maxf(
		1.0,
		get_traffic_multiplier()
	)

	var minimum: float = maxf(
		minimum_spawn_interval,
		spawn_interval_min / traffic_multiplier
	)

	var maximum: float = maxf(
		minimum,
		spawn_interval_max / traffic_multiplier
	)

	spawn_timer = randf_range(minimum, maximum)


# Traffic functions

func get_player_count() -> int:
	return clampi(multiplayer.get_peers().size() + 1, 1, 4)


func get_day_traffic_multiplier() -> float:
	var days_elapsed: int = maxi(0, DayManager.current_day - 1)

	return minf(
		1.0 + day_growth_rate * float(days_elapsed),
		max_day_traffic_multiplier
	)


func get_player_traffic_multiplier() -> float:
	var additional_players: int = get_player_count() - 1

	return 1.0 + float(additional_players) * traffic_increase_per_player


func get_traffic_multiplier() -> float:
	var multiplier: float = (
		get_day_traffic_multiplier()
		* get_player_traffic_multiplier()
	)

	if DayManager.rush_hour:
		multiplier *= rush_hour_multiplier

	return multiplier


func get_current_max_shoppers() -> int:
	var days_elapsed: int = maxi(0, DayManager.current_day - 1)

	var day_bonus: int = 0

	if extra_shoppers_every_n_days > 0:
		day_bonus = days_elapsed / extra_shoppers_every_n_days

	var player_bonus: int = (
		(get_player_count() - 1) * extra_shoppers_per_player
	)

	return clampi(
		starting_max_shoppers + day_bonus + player_bonus,
		1,
		max_shoppers
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

	shopper_stats.current_shoppers = maxi(
		0,
		shopper_stats.current_shoppers - 1
	)


func _on_shopper_reached_enter_point() -> void:
	if multiplayer.is_server():
		shopper_stats.current_shoppers += 1
	else:
		shopper_stats._current_shoppers += 1
