
extends Node

signal pending_order_updated(pending_orders: Dictionary)

# Product resource path -> quantity requested.
var pending_orders: Dictionary = {}

# Preserves the order in which products were added.
var pending_order_paths: Array[String] = []

# Product resource path -> quantity purchased, awaiting future delivery.
var confirmed_orders: Dictionary = {}
var last_processed_day: int = -1

const RESTOCK_BOX_SCENE: PackedScene = preload(
	"res://scenes/items/restock_box.tscn"
)
const DELIVERY_START_HOUR: int = 10
const DELIVERY_BOX_CAPACITY: int = 400
var last_delivery_day: int = -1
const DELIVERY_SPAWN_POINT_PATH: NodePath = NodePath(
	"/root/Main/ThirdPersonLevel/Deliveries/DeliverySpawnPoint"
)

@export_group("Delivery Stacking")
@export_range(1, 20, 1) var delivery_stack_height: int = 4
@export var delivery_horizontal_spacing: float = 0.12
@export var delivery_vertical_spacing: float = 0.25


func _ready() -> void:
	print(
		"STOCK MANAGER READY: instance_id=",
		get_instance_id(),
		" | path=",
		get_path()
	)
	if not DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.connect(_on_clock_updated)
	
	get_tree().node_added.connect(_on_node_added)

func set_pending_quantity(
	product_path: String,
	quantity: int
) -> void:
	if not multiplayer.is_server():
		return

	if product_path.is_empty():
		return

	if quantity < 0 or quantity > 400:
		return

	if not ResourceLoader.exists(product_path):
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	if quantity == 0:
		pending_orders.erase(product_path)
		pending_order_paths.erase(product_path)
	else:
		if not pending_orders.has(product_path):
			pending_order_paths.append(product_path)

		pending_orders[product_path] = quantity
		
		print(
			"ORDER SUBMITTED: paths=",
			pending_order_paths,
			" | pending=",
			pending_orders
		)

	_sync_pending_orders.rpc(pending_orders, pending_order_paths)


@rpc("any_peer", "call_remote", "reliable")
func request_set_pending_quantity(
	product_path: String,
	quantity: int
) -> void:
	if not multiplayer.is_server():
		return

	set_pending_quantity(product_path, quantity)


func get_pending_quantity(product_path: String) -> int:
	return int(pending_orders.get(product_path, 0))


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	if not multiplayer.is_server():
		return

	if hour == 20 and minute == 0 and last_processed_day != day:
		_process_pending_orders(day)

	if hour == DELIVERY_START_HOUR and minute == 0 and last_delivery_day != day:
		_spawn_delivery(day)


func _process_pending_orders(day: int) -> void:
	
	print(
	"PROCESS ENTRY: instance=",
	get_instance_id(),
	" | paths=",
	pending_order_paths,
	" | day=",
	day,
	" | last_processed_day=",
	last_processed_day
)
	
	print("PROCESSING STOCK ORDERS: day=", day, " pending=", pending_orders)
	
	var _stats: Node = get_tree().get_first_node_in_group("shopper_stats")
		
	last_processed_day = day

	var budget: float = maxf(0.0, StoreManager.store_cash)

	print("STORE CASH BEFORE RESTOCK: $", budget)


	# Process products in the order they were added.
	print("STOCK DEBUG: pending_order_paths=", pending_order_paths)
	for product_path in pending_order_paths:
		var requested_quantity: int = int(
			pending_orders.get(product_path, 0)
		)

		if requested_quantity <= 0:
			continue

		if not ResourceLoader.exists(product_path):
			print("STOCK ERROR: Resource does not exist: ", product_path)
			continue

		var product: ProductData = load(product_path) as ProductData

		if product == null:
			print("STOCK ERROR: Could not load ProductData: ", product_path)
			continue

		print(
			"STOCK CHECK: ",
			product_path,
			" | product=",
			product.display_name,
			" | reorder_cost=",
			product.reorder_cost
		)

		if product.reorder_cost <= 0.0:
			print("STOCK SKIPPED: Invalid reorder cost for ", product.display_name)
			continue

		var affordable_quantity: int = int(
			floor((budget + 0.000001) / product.reorder_cost)
		)

		var purchased_quantity: int = mini(
			requested_quantity,
			affordable_quantity
		)

		if purchased_quantity <= 0:
			continue

		var purchase_cost: float = (
			purchased_quantity * product.reorder_cost
		)

		budget = maxf(0.0, budget - purchase_cost)

		# Keep purchased quantities for the future delivery system.
		confirmed_orders[product_path] = (
			int(confirmed_orders.get(product_path, 0))
			+ purchased_quantity
		)
	
	# Deduct the total cost of purchased stock.
	var amount_spent: float = maxf(
		0.0,
		StoreManager.store_cash - budget
	)

	if amount_spent > 0.0:
		StoreManager.spend_cash(amount_spent)

	print(
		"RESTOCK SPENDING: $", amount_spent,
		" | Remaining cash: $", StoreManager.store_cash
	)

	# All unpurchased quantities are discarded.
	pending_orders.clear()
	pending_order_paths.clear()

	_sync_pending_orders.rpc(pending_orders, pending_order_paths)


@rpc("authority", "call_local", "reliable")
func _sync_pending_orders(data: Dictionary, order_paths: Array) -> void:
	var paths_copy: Array = order_paths.duplicate()

	pending_orders = data.duplicate(true)

	pending_order_paths.clear()
	for product_path in paths_copy:
		pending_order_paths.append(str(product_path))

	pending_order_updated.emit(pending_orders)


func _spawn_delivery(day: int) -> void:
	if confirmed_orders.is_empty():
		return

	var level: Node = get_tree().root.get_node_or_null(
		"Main/Game/ThirdPersonLevel"
	)

	if level == null:
		push_warning("Could not find ThirdPersonLevel.")
		return

	var delivery_spawn_point: Marker3D = level.get_node_or_null(
		"Deliveries/DeliverySpawnPoint"
	) as Marker3D

	if delivery_spawn_point == null:
		push_warning("Could not find DeliverySpawnPoint.")
		return

	var box_index: int = 0

	for product_path: String in confirmed_orders:
		var remaining_quantity: int = int(confirmed_orders[product_path])

		var product: ProductData = load(product_path) as ProductData

		if product == null:
			continue

		while remaining_quantity > 0:
			var box_quantity: int = mini(
				remaining_quantity,
				DELIVERY_BOX_CAPACITY
			)

			var deliveries: Node3D = level.get_node_or_null("Deliveries") as Node3D

			if deliveries == null:
				return

			var spawner: MultiplayerSpawner = deliveries.get_node_or_null(
				"MultiplayerSpawner"
			) as MultiplayerSpawner

			if spawner == null:
				return

			var box_width: float = 0.5
			var box_height: float = 0.5

			var stack_column: int = floori(float(box_index) / float(delivery_stack_height))
			var stack_row: int = box_index % delivery_stack_height

			var local_offset: Vector3 = Vector3(
				float(stack_column) * (box_width + delivery_horizontal_spacing),
				float(stack_row) * (box_height + delivery_vertical_spacing),
				0.0
			)

			var box_transform: Transform3D = (
				delivery_spawn_point.global_transform
				* Transform3D(Basis.IDENTITY, local_offset)
			)

			var spawn_position: Vector3 = deliveries.to_local(
				box_transform.origin
			)

			var spawn_rotation: Vector3 = (
				deliveries.global_transform.basis.inverse()
				* box_transform.basis
			).get_euler()

			spawner.spawn({
				"product_path": product_path,
				"quantity": box_quantity,
				"position": spawn_position,
				"rotation": spawn_rotation
			})

			remaining_quantity -= box_quantity
			box_index += 1

	last_delivery_day = day
	confirmed_orders.clear()


func _create_delivery_box(data: Variant) -> Node:
	var product_path: String = str(data["product_path"])
	var quantity: int = int(data["quantity"])
	var position: Vector3 = data["position"]

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return null

	var box: RestockBox = RESTOCK_BOX_SCENE.instantiate() as RestockBox

	box.product_data = product
	box.quantity = quantity
	box.position = position
	box.rotation = data["rotation"]

	return box


func _on_node_added(node: Node) -> void:
	if node.name != "MultiplayerSpawner":
		return

	if str(node.get_parent().name) != "Deliveries":
		return

	var spawner: MultiplayerSpawner = node as MultiplayerSpawner

	if spawner == null:
		return

	spawner.spawn_function = _create_delivery_box


func restore_saved_boxes() -> void:
	if not multiplayer.is_server():
		return

	if StoreManager.restock_boxes.is_empty():
		return

	var level: Node = get_tree().root.get_node_or_null(
		"Main/Game/ThirdPersonLevel"
	)

	if level == null:
		push_warning("Cannot restore restock boxes: store level not found.")
		return

	var deliveries: Node3D = level.get_node_or_null(
		"Deliveries"
	) as Node3D

	if deliveries == null:
		return

	var spawner: MultiplayerSpawner = deliveries.get_node_or_null(
		"MultiplayerSpawner"
	) as MultiplayerSpawner

	if spawner == null:
		return

	var restored_count: int = 0

	for box_data: Dictionary in StoreManager.restock_boxes:
		var position_data: Array = box_data["position"]
		var rotation_data: Array = box_data["rotation"]

		var global_position: Vector3 = Vector3(
			float(position_data[0]),
			float(position_data[1]),
			float(position_data[2])
		)

		var global_rotation: Vector3 = Vector3(
			float(rotation_data[0]),
			float(rotation_data[1]),
			float(rotation_data[2])
		)

		var global_basis: Basis = Basis.from_euler(global_rotation)

		var global_box_transform: Transform3D = Transform3D(
			global_basis,
			global_position
		)

		var local_box_transform: Transform3D = (
			deliveries.global_transform.affine_inverse()
			* global_box_transform
		)

		spawner.spawn({
			"product_path": str(box_data["product_path"]),
			"quantity": int(box_data["quantity"]),
			"position": local_box_transform.origin,
			"rotation": local_box_transform.basis.get_euler()
		})

		restored_count += 1

	print("RESTOCK BOXES RESTORED: ", restored_count)
