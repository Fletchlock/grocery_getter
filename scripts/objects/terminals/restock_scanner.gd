extends Node3D

@export var outline_material: Material

var is_available: bool = true

var order_window_open_hour: int = 18
var order_window_close_hour: int = 20

var order_selection_active: bool = false
var selected_product_display: Node = null
var selected_order_quantity: int = 0
var selected_max_quantity: int = 0

@onready var scanner_mesh: MeshInstance3D = $ScannerMesh
@onready var mesh_outline: Node3D = $Area3D/MeshOutline


func _ready() -> void:
	_create_outline()


func _create_outline() -> void:
	if scanner_mesh.mesh == null:
		return

	if outline_material == null:
		return

	var outline_instance: MeshInstance3D = MeshInstance3D.new()

	outline_instance.mesh = scanner_mesh.mesh
	outline_instance.transform = scanner_mesh.transform
	outline_instance.scale = Vector3(1.03, 1.03, 1.03)
	outline_instance.material_override = outline_material

	mesh_outline.add_child(outline_instance)


func get_product_display_from_target(target: Object) -> Node:
	var current: Node = target as Node

	while current != null:
		if (
			current.get("product_data") != null
			and current.get("quantity") != null
			and current.get("max_quantity") != null
		):
			return current

		current = current.get_parent()

	return null


func get_missing_stock(display: Node) -> int:
	if display == null:
		return 0

	var current_quantity: int = int(display.get("quantity"))
	var maximum_quantity: int = int(display.get("max_quantity"))

	return maxi(0, maximum_quantity - current_quantity)


func begin_order_selection(display: Node) -> void:
	if display == null:
		return

	if not is_ordering_window_open():
		return

	var missing: int = get_missing_stock(display)

	if missing <= 0:
		return

	selected_product_display = display
	selected_max_quantity = missing
	selected_order_quantity = missing
	order_selection_active = true


func adjust_order_quantity(direction: int) -> void:
	if not order_selection_active:
		return

	if direction < 0:
		if selected_order_quantity <= 10:
			selected_order_quantity = 0
		else:
			selected_order_quantity = int(
				floor(float(selected_order_quantity - 1) / 10.0)
			) * 10

	elif direction > 0:
		if selected_order_quantity == 0:
			selected_order_quantity = mini(
				10,
				selected_max_quantity
			)
		else:
			selected_order_quantity = mini(
				selected_max_quantity,
				(int(selected_order_quantity / 10) + 1) * 10
			)


func get_order_selection_prompt() -> String:
	if not order_selection_active:
		return ""

	if selected_product_display == null:
		return ""

	var product_data: ProductData = selected_product_display.get(
		"product_data"
	) as ProductData

	if product_data == null:
		return ""

	if selected_order_quantity == 0:
		return "[E] Cancel Order - %s" % product_data.display_name

	return "[E] Place Order %d %s (Scroll +/-)" % [
		selected_order_quantity,
		product_data.display_name
	]


func confirm_order_selection() -> void:
	if not order_selection_active:
		return

	if selected_order_quantity <= 0:
		cancel_order_selection()
		return

	var product_data: ProductData = selected_product_display.get(
		"product_data"
	) as ProductData

	if product_data == null:
		cancel_order_selection()
		return

	if multiplayer.is_server():
		StockOrderManager.set_pending_quantity(
			product_data.resource_path,
			selected_order_quantity
		)
	else:
		StockOrderManager.request_set_pending_quantity.rpc_id(
			1,
			product_data.resource_path,
			selected_order_quantity
		)

	cancel_order_selection()


func cancel_order_selection() -> void:
	order_selection_active = false
	selected_product_display = null
	selected_order_quantity = 0
	selected_max_quantity = 0


func get_targeted_product_display(
	raycast: RayCast3D
) -> Node:
	if raycast == null:
		return null

	raycast.force_raycast_update()

	if not raycast.is_colliding():
		return null

	var target: Object = raycast.get_collider()

	return get_product_display_from_target(target)


func get_stock_order_prompt(display: Node) -> String:
	if display == null:
		return ""
	
	if not is_ordering_window_open():
		return "Stock ordering opens at 6 PM"
	
	var product_data: ProductData = display.get(
		"product_data"
	) as ProductData

	if product_data == null:
		return ""

	var missing: int = get_missing_stock(display)

	if missing <= 0:
		return "%s - Fully Stocked" % product_data.display_name

	return "%s - Missing %d" % [
		product_data.display_name,
		missing
	]


func get_interaction_prompt_for_player(_player: CharacterBody3D) -> String:
	if not is_available:
		return ""

	return "[E] Pick Up Restock Scanner"


func get_interaction_prompt_position(
	collision_shape: CollisionShape3D
) -> Vector3:
	return collision_shape.global_position + Vector3.UP * 0.25


func request_interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not is_available:
		return

	if not player.has_method("request_pickup_restock_scanner"):
		return

	player.request_pickup_restock_scanner(self)


func server_claim() -> bool:
	if not multiplayer.is_server():
		return false

	if not is_available:
		return false

	is_available = false
	return_scanner_to_holder.rpc(false)

	return true


@rpc("authority", "call_local", "reliable")
func return_scanner_to_holder(available: bool) -> void:
	is_available = available
	visible = available

	var area: Area3D = get_node_or_null("Area3D") as Area3D

	if area != null:
		area.monitoring = available
		area.monitorable = available

		var collision_shape: CollisionShape3D = (
			area.get_node_or_null("CollisionShape3D")
			as CollisionShape3D
		)

		if collision_shape != null:
			collision_shape.set_deferred("disabled", not available)


func is_ordering_window_open() -> bool:
	return (
		DayManager.current_hour >= order_window_open_hour
		and DayManager.current_hour < order_window_close_hour
	)
