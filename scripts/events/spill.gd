extends Node3D
class_name Spill


var shopping_point_path: NodePath = NodePath()


func _ready() -> void:
	add_to_group("active_spills")
