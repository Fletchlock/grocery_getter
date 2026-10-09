extends Resource
class_name ProductData


@export_group("Product")
@export var item_id: String = ""
@export var display_name: String = ""
@export var product_category: String = ""
@export var product_mesh: Mesh
@export var product_price: float = 0.00
@export var reorder_cost: float = 0.00

@export_group("Held Item")
@export var hand_position: Vector3 = Vector3.ZERO
@export var hand_rotation: Vector3 = Vector3.ZERO
@export var hand_scale: Vector3 = Vector3.ONE
