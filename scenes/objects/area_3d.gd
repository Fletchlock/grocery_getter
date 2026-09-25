extends Area3D


@onready var product_display: Node3D = get_parent()


func interact() -> void:
	product_display.interact()
