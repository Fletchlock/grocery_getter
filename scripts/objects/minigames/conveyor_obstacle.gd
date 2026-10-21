
extends AnimatableBody3D
class_name ConveyorObstacle


@export var movement_enabled: bool = true

var conveyor_belt: ConveyorBelt = null


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not movement_enabled:
		return

	if not is_instance_valid(conveyor_belt):
		return

	global_position += conveyor_belt.get_belt_velocity() * delta
