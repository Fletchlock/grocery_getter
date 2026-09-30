extends Node3D


@export_group("Debug Display")
@export var stats_label: Label3D

var total_shoppers_shopped: int = 0
var stats_update_timer: float = 0.0


@export_group("Shopper Spawning")
@export var shopper_scenes: Array[PackedScene]
@export var max_shoppers: int = 10
@export var spawn_interval_min: float = 10.0
@export var spawn_interval_max: float = 30.0
@export var spawn_points: Array[Marker3D]

@onready var multiplayer_shopper_spawner: MultiplayerSpawner = $"../MultiplayerShopperSpawner"


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


func _spawn_shopper(data: Variant) -> Node:
	var shopper_index: int = int(data)

	if shopper_index < 0 or shopper_index >= shopper_scenes.size():
		return null

	return shopper_scenes[shopper_index].instantiate()


func _on_shopper_reached_enter_point() -> void:
	update_stats_label()


func _on_shopper_finished_shopping() -> void:
	total_shoppers_shopped += 1
	update_stats_label()


func update_stats_label() -> void:
	if stats_label == null:
		return

	var current_shoppers: int = get_active_shopper_count()

	stats_label.text = (
		"SHOPPERS IN STORE: "
		+ str(current_shoppers)
		+ " / "
		+ str(max_shoppers)
		+ "\nTOTAL SHOPPED: "
		+ str(total_shoppers_shopped)
	)
