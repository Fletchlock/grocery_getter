@tool
extends Node3D

@export var product_data: ProductData:
	set(value):
		product_data = value
		_update_product_mesh()

@onready var product_mesh: MeshInstance3D = $ProductMesh
@onready var barcode_marker: Marker3D = $BarcodeMarker


func _ready() -> void:
	_update_product_mesh()


func _update_product_mesh() -> void:
	if not is_node_ready():
		return

	if product_data == null:
		product_mesh.mesh = null
		return

	product_mesh.mesh = product_data.product_mesh


@export_tool_button("Save Barcode Transform")
var save_transform_button: Callable = save_barcode_transform


func save_barcode_transform() -> void:
	if product_data == null:
		push_warning("No ProductData selected.")
		return

	if not is_node_ready():
		return

	product_data.barcode_transform = (
		product_mesh.global_transform.affine_inverse()
		* barcode_marker.global_transform
	)

	var error: Error = ResourceSaver.save(
		product_data,
		product_data.resource_path
	)

	if error != OK:
		push_error("Failed to save barcode transform.")
		return

	print("Saved barcode transform for: ", product_data.display_name)


@export_tool_button("Load Barcode Transform")
var load_transform_button: Callable = load_barcode_transform


func load_barcode_transform() -> void:
	if product_data == null:
		push_warning("No ProductData selected.")
		return

	if not is_node_ready():
		return

	barcode_marker.transform = (
		product_mesh.transform
		* product_data.barcode_transform
	)

	print("Loaded barcode transform for: ", product_data.display_name)
