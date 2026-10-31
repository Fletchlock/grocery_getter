@tool
extends Node3D
class_name ShelfTag


@onready var tag_mesh: MeshInstance3D = $TagMesh
@onready var sub_viewport: SubViewport = $SubViewport

@onready var product_name_label: Label = $SubViewport/PanelContainer/MarginContainer/VBoxContainer/ProductName
@onready var product_price_label: Label = $SubViewport/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ProductPrice
@onready var stock_status_label: Label = $SubViewport/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/StockStatus


const SCREEN_SURFACE: int = 1


func _ready() -> void:
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var material: StandardMaterial3D = tag_mesh.get_active_material(SCREEN_SURFACE) as StandardMaterial3D

	if material == null:
		push_error("ShelfTag: No StandardMaterial3D found on screen surface.")
		return

	material = material.duplicate() as StandardMaterial3D
	tag_mesh.set_surface_override_material(SCREEN_SURFACE, material)

	material.albedo_texture = sub_viewport.get_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func update_display(
	product: ProductData,
	stock_quantity: int,
	unlocked: bool = true
) -> void:
	if product == null or not unlocked:
		product_name_label.text = ""
		product_price_label.text = ""
		stock_status_label.text = ""
		return

	product_name_label.text = product.display_name
	product_price_label.text = "$%.2f" % product.product_price

	if stock_quantity <= 0:
		stock_status_label.text = "OUT OF STOCK"
	else:
		stock_status_label.text = ""
