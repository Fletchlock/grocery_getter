extends Node3D


@export_group("Debug Display")
@export var stats_label: Label3D

var total_shoppers_shopped: int = 0
var stats_update_timer: float = 0.0

@export_group("Shopper Spawning")
@export var shopper_scene: PackedScene
@export var max_shoppers: int = 10
@export var spawn_interval_min: float = 10.0
@export var spawn_interval_max: float = 30.0
@export var spawn_point: Marker3D

var spawn_timer: float = 0.0


func _ready() -> void:
	set_next_spawn_timer()


func _process(delta: float) -> void:
	spawn_timer -= delta

	if spawn_timer <= 0.0:
		if get_active_shopper_count() < max_shoppers:
			spawn_shopper()

		set_next_spawn_timer()

	stats_update_timer -= delta

	if stats_update_timer <= 0.0:
		update_stats_label()
		stats_update_timer = 0.25


func set_next_spawn_timer() -> void:
	spawn_timer = randf_range(
		spawn_interval_min,
		spawn_interval_max
	)


func get_active_shopper_count() -> int:
	var count: int = 0

	for child: Node in get_parent().get_children():
		if not is_instance_valid(child):
			continue

		if child.scene_file_path == shopper_scene.resource_path:
			count += 1

	return count


func spawn_shopper() -> void:
	if shopper_scene == null:
		return

	if spawn_point == null:
		return

	var shopper: Node3D = shopper_scene.instantiate() as Node3D

	if shopper == null:
		return

	get_parent().add_child(shopper)
	shopper.global_position = spawn_point.global_position
	
	if shopper.has_signal("finished_shopping"):
		shopper.finished_shopping.connect(_on_shopper_finished_shopping)
		
	update_stats_label()


func _on_shopper_finished_shopping() -> void:
	total_shoppers_shopped += 1
	
	
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
