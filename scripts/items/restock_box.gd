extends Node3D
class_name RestockBox


@export_group("Contents")
@export var product_data: ProductData
@export_range(1, 400, 1) var quantity: int = 10

@onready var product_label: Label3D = $ProductLabel


func _ready() -> void:
	_update_label()


func _update_label() -> void:
	if product_data == null:
		product_label.text = "Unassigned Product\nQty: %d" % quantity
		return

	product_label.text = "%s\nQty: %d" % [
		product_data.display_name,
		quantity
	]


func get_interaction_prompt_for_player( _player: CharacterBody3D) -> String:
	return "Pick Up Restock Box"
	

func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not player.has_method("try_pickup_restock_box"):
		return

	player.try_pickup_restock_box(self)
