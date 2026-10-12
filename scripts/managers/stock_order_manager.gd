
extends Node

signal pending_order_updated(pending_orders: Dictionary)

# Product resource path -> quantity requested.
var pending_orders: Dictionary = {}

# Preserves the order in which products were added.
var pending_order_paths: Array[String] = []

# Product resource path -> quantity purchased, awaiting future delivery.
var confirmed_orders: Dictionary = {}

var last_processed_day: int = -1


func _ready() -> void:
	print(
		"STOCK MANAGER READY: instance_id=",
		get_instance_id(),
		" | path=",
		get_path()
	)
	if not DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.connect(_on_clock_updated)


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

	if hour != 20 or minute != 0:
		return

	if last_processed_day == day:
		return

	_process_pending_orders(day)


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
	
	var stats: Node = get_tree().get_first_node_in_group("shopper_stats")
	
	print("SHOPPER STATS NODE: ", stats)
	if stats != null:
		print("TOTAL SALES BEFORE ORDER: ", stats.get("total_sales"))
	
	if stats == null:
		return

	if not stats.get("total_sales") is float and not stats.get("total_sales") is int:
		return

	last_processed_day = day

	var budget: float = maxf(0.0, float(stats.get("total_sales")))

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

	# Deduct spending from the current store funds.
	stats.set("total_sales", budget)
	print("STOCK ORDERS PROCESSED: remaining budget=$", budget, " confirmed orders=", confirmed_orders)
	
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
