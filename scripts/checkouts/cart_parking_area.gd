
extends Area3D
class_name CartParkingArea


@onready var order_grid: OrderGrid = $"../OrderGrid"


func _ready() -> void:
	monitoring = true

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	if not body.has_method("release_cart"):
		return

	print("Cart entered online order parking area: ", body.name)


func _on_body_exited(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	if not body.has_method("release_cart"):
		return

	print("Cart left online order parking area: ", body.name)
