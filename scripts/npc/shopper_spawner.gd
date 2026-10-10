extends Node3D


@export_group("Shopper Spawning")
@export var shopper_scenes: Array[PackedScene]
@export var max_shoppers: int = 10
@export var spawn_interval_min: float = 30.0
@export var spawn_interval_max: float = 60.0
@export var spawn_points: Array[Marker3D]

@onready var multiplayer_shopper_spawner: MultiplayerSpawner = $"../MultiplayerShopperSpawner"
@onready var shopper_stats: Node3D = $"../ShopperStats"


var last_spawn_point: Marker3D = null
var shopper_scene_pool: Array[PackedScene] = []
var spawn_timer: float = 0.0


func _ready() -> void:
	randomize()

	multiplayer_shopper_spawner.spawn_function = _spawn_shopper

	shopper_scene_pool = shopper_scenes.duplicate()
	shopper_scene_pool.shuffle()

	set_next_spawn_timer()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	#Check if store open before spawning shoppers.
	if not DayManager.store_open:
		return
	
	# Check if rush hour
	if DayManager.rush_hour:
		spawn_interval_min = 5
		spawn_interval_max = 10
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


func spawn_shopper() -> void:
	if shopper_scene_pool.is_empty():
		shopper_scene_pool = shopper_scenes.duplicate()
		shopper_scene_pool.shuffle()

	if spawn_points.is_empty():
		return

	var available_spawn_points: Array[Marker3D] = spawn_points.duplicate()

	if last_spawn_point != null and available_spawn_points.size() > 1:
		available_spawn_points.erase(last_spawn_point)

	var spawn_point: Marker3D = available_spawn_points.pick_random()
	last_spawn_point = spawn_point

	var shopper_scene: PackedScene = shopper_scene_pool.pop_back()

	if shopper_scene == null:
		return

	var shopper_index: int = shopper_scenes.find(shopper_scene)

	if shopper_index < 0:
		return

	var shopper: Node3D = multiplayer_shopper_spawner.spawn(shopper_index) as Node3D

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
	var shopper_index: int = int(data)

	if shopper_index < 0 or shopper_index >= shopper_scenes.size():
		return null

	return shopper_scenes[shopper_index].instantiate()


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
	print("SHOPPER ENTERED | PEER: ", multiplayer.get_unique_id())
	if multiplayer.is_server():
		shopper_stats.current_shoppers += 1
	else:
		shopper_stats._current_shoppers += 1
