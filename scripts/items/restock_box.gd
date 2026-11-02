
extends Node3D
class_name RestockBox


@export var outline_material: Material

@export_group("Contents")
@export var product_data: ProductData
@export_range(1, 400, 1) var quantity: int = 10

@onready var box_mesh: MeshInstance3D = $BoxMesh
@onready var mesh_outline: Node3D = $Area3D/MeshOutline

@onready var box_label_viewport: SubViewport = $BoxLabelViewport
@onready var front_label_mesh: MeshInstance3D = $FrontLabelMesh
@onready var back_label_mesh: MeshInstance3D = $BackLabelMesh

@onready var product_name_label: Label = $BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer/ProductNameLabel
@onready var quantity_label: Label = $BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer/QuantityLabel


func _ready() -> void:
	_create_outline()
	_setup_label_materials()
	_update_label()

	# Only register actual world boxes.
	if get_parent() != null and get_parent().name == "Deliveries":
		add_to_group("restock_boxes")


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


func _setup_label_materials() -> void:
	var viewport_texture: Texture2D = box_label_viewport.get_texture()

	var label_material: StandardMaterial3D = StandardMaterial3D.new()
	label_material.albedo_texture = viewport_texture
	label_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	label_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	front_label_mesh.material_override = label_material
	back_label_mesh.material_override = label_material


func _update_label() -> void:
	if product_data == null:
		product_name_label.text = "Unassigned Product"
	else:
		product_name_label.text = product_data.display_name

	quantity_label.text = "QTY: %d" % quantity


func get_interaction_prompt_for_player(_player: CharacterBody3D) -> String:
	return "Pick Up Restock Box"


func get_interaction_prompt_position(_collision_shape: CollisionShape3D) -> Vector3:
	return global_position + Vector3.UP * 0.35


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not player.has_method("try_pickup_restock_box"):
		return

	player.try_pickup_restock_box(self)
