extends Node3D

@export var rotation_speed: float = 0.5

@onready var character_pivot: Node3D = $CharacterPivot


func set_character_rotation(value: float) -> void:
	character_pivot.rotation_degrees.y = value


func _on_h_slider_value_changed(value: float) -> void:
	set_character_rotation(value)
