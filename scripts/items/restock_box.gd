extends Node3D
class_name RestockBox


@export var outline_material: Material

@onready var box_mesh: MeshInstance3D = $BoxMesh
@onready var mesh_outline: Node3D = $Area3D/MeshOutline


@export_group("Contents")
@export var product_data: ProductData
@export_range(1, 400, 1) var quantity: int = 10

@onready var product_label: Label3D = $ProductLabel
@onready var product_label_back: Label3D = $ProductLabelBack


func _ready() -> void:
	_create_outline()
	_update_label()


func _create_outline() -> void:
	if box_mesh.mesh == null:
		return

	if outline_material == null:
		return

	var outline_instance: MeshInstance3D = MeshInstance3D.new()

	outline_instance.mesh = box_mesh.mesh
	outline_instance.transform = box_mesh.transform
	outline_instance.scale = Vector3(1.02, 1.02, 1.02)
	outline_instance.material_override = outline_material

	mesh_outline.add_child(outline_instance)


func _update_label() -> void:
	var label_text: String

	if product_data == null:
		label_text = "Unassigned Product\nQty: %d" % quantity
	else:
		label_text = "%s\nQty: %d" % [
			product_data.display_name,
			quantity
		]

	product_label.text = label_text
	product_label_back.text = label_text


func get_interaction_prompt_for_player( _player: CharacterBody3D) -> String:
	return "Pick Up Restock Box"
	

func get_interaction_prompt_position(_collision_shape: CollisionShape3D) -> Vector3:
	return global_position + Vector3.UP * .35


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not player.has_method("try_pickup_restock_box"):
		return

	player.try_pickup_restock_box(self)
