extends PanelContainer
class_name OnlineOrderList

@export_group("Appearance")
@export var completed_color: Color = Color("5af243ff")
@export var incomplete_color: Color = Color.WHITE

@export_group("Animation")
@export var slide_duration: float = 0.35
@export var slide_distance: float = 500.0

var animation_tween: Tween = null
var is_removing: bool = false

@onready var order_title: Label = $MarginContainer/VBoxContainer/TitleRow/OrderTitle
@onready var time_remaining: Label = $MarginContainer/VBoxContainer/TitleRow/TimeRemaining
@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer

var order_id: int = -1
var item_rows: Dictionary = {}
var active_cart: CartGrid = null

func setup_order(order: OrderData) -> void:
	order_id = order.order_id
	order_title.text = "ORDER #%02d" % order_id

	_clear_items()

	for item: OrderItem in order.items:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 80)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var product_label: Label = Label.new()
		product_label.text = item.product.display_name
		product_label.add_theme_font_size_override("font_size", 22)
		product_label.add_theme_color_override("font_outline_color", Color.BLACK)
		product_label.add_theme_constant_override("outline_size", 6)
		product_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var quantity_label: Label = Label.new()
		quantity_label.add_theme_font_size_override("font_size", 22)
		quantity_label.add_theme_color_override("font_outline_color", Color.BLACK)
		quantity_label.add_theme_constant_override("outline_size", 6)
		quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		row.add_child(product_label)
		row.add_child(quantity_label)

		items_container.add_child(row)

		item_rows[item.product.resource_path] = {
			"name": product_label,
			"quantity": quantity_label
		}

	update_order(order)


func update_order(order: OrderData) -> void:
	if order.order_id != order_id:
		return

	_update_remaining_time(order)

	for item: OrderItem in order.items:
		if item.product == null:
			continue

		var product_path: String = item.product.resource_path

		if not item_rows.has(product_path):
			continue

		var row: Dictionary = item_rows[product_path]

		var product_label: Label = row["name"]
		var quantity_label: Label = row["quantity"]

		# Always show the original requested quantity.
		# Picking and scanning do not change this value.
		quantity_label.text = "x%d" % item.quantity

		# Keep the order list neutral until checkout is finished.
		product_label.add_theme_color_override(
			"font_color",
			incomplete_color
		)

		quantity_label.add_theme_color_override(
			"font_color",
			incomplete_color
		)


func _update_remaining_time(order: OrderData) -> void:
	var remaining: float = maxf(
		order.time_limit - order.elapsed_time,
		0.0
	)
	
	var total_seconds: int = int(remaining)
	var minutes: int = floori(remaining / 60.0)
	var seconds: int = total_seconds % 60

	time_remaining.text = "   %dm%02ds" % [
		minutes,
		seconds
	]


func _clear_items() -> void:
	item_rows.clear()

	for child: Node in items_container.get_children():
		items_container.remove_child(child)
		child.queue_free()


func set_active_cart(cart_grid: CartGrid) -> void:
	active_cart = cart_grid


func _get_cart_quantity(product: ProductData) -> int:
	if active_cart == null or not is_instance_valid(active_cart):
		return 0

	var count: int = 0

	for cart_product: ProductData in active_cart.cart_items:
		if cart_product == product:
			count += 1

	return count


func slide_in() -> void:
	if animation_tween != null:
		animation_tween.kill()

	offset_transform_enabled = true
	offset_transform_position.x = -slide_distance

	animation_tween = create_tween()
	animation_tween.set_trans(Tween.TRANS_CUBIC)
	animation_tween.set_ease(Tween.EASE_OUT)

	animation_tween.tween_property(
		self,
		"offset_transform_position:x",
		0.0,
		slide_duration
	)


func slide_out() -> void:
	if is_removing:
		return

	is_removing = true

	if animation_tween != null:
		animation_tween.kill()

	animation_tween = create_tween()
	animation_tween.set_trans(Tween.TRANS_CUBIC)
	animation_tween.set_ease(Tween.EASE_IN)

	animation_tween.tween_property(
		self,
		"offset_transform_position:x",
		-slide_distance,
		slide_duration
	)

	await animation_tween.finished
