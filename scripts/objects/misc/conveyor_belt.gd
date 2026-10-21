extends Node3D
class_name ConveyorBelt

@export var belt_speed: float = 2.0
@export var belt_direction: Vector3 = Vector3.FORWARD

@onready var conveyor_area: Area3D = $ConveyorArea


func _ready() -> void:
	conveyor_area.body_entered.connect(_on_body_entered)
	conveyor_area.body_exited.connect(_on_body_exited)


func get_belt_velocity() -> Vector3:
	return belt_direction.normalized() * belt_speed


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.set_meta("conveyor_belt", self)


func _on_body_exited(body: Node3D) -> void:
	if not body.has_meta("conveyor_belt"):
		return

	if body.get_meta("conveyor_belt") == self:
		body.remove_meta("conveyor_belt")
