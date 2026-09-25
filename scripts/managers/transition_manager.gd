extends Node


@onready var fade_rect: ColorRect = $CanvasLayer/ColorRect


func _ready() -> void:
	fade_rect.modulate.a = 0.0
