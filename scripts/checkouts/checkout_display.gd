
extends Control
class_name CheckoutDisplay


@export_group("Display Settings")
@export_range(1.0, 30.0, 0.5)
var sale_complete_delay: float = 5.0

@export_range(12, 64, 1)
var item_font_size: int = 26

@export_range(12, 64, 1)
var price_font_size: int = 26


@onready var header_label: Label = $PanelContainer/VBoxContainer/HeaderLabel
@onready var scroll_container: ScrollContainer = $PanelContainer/VBoxContainer/ScrollContainer
@onready var item_list: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/ItemList
@onready var separator: HSeparator = $PanelContainer/VBoxContainer/HSeparator
@onready var subtotal_label: Label = $PanelContainer/VBoxContainer/SubtotalLabel
@onready var total_label: Label = $PanelContainer/VBoxContainer/TotalLabel


var subtotal: float = 0.0
var sale_complete_timer: Timer


func _ready() -> void:
	# Create the timer automatically.
	sale_complete_timer = Timer.new()
	sale_complete_timer.one_shot = true
	sale_complete_timer.autostart = false

	add_child(sale_complete_timer)

	sale_complete_timer.timeout.connect(
		_on_sale_complete_timer_timeout
	)

	reset_display()


func reset_display() -> void:
	# Cancel any previous sale timer.
	sale_complete_timer.stop()

	subtotal = 0.0

	_clear_item_list()
	scroll_container.scroll_vertical = 0
	
	header_label.text = "WELCOME"
	subtotal_label.text = ""
	total_label.text = ""

	separator.hide()
	subtotal_label.hide()


func start_checkout() -> void:
	reset_display()

	header_label.text = "READY TO SCAN"
	subtotal_label.text = "SUBTOTAL: $0.00"
	total_label.text = "TOTAL: $0.00"

	separator.show()
	subtotal_label.show()


func add_scanned_item(
	product_name: String,
	price: float
) -> void:
	# A new scan cancels any pending reset.
	sale_complete_timer.stop()

	var item_row: HBoxContainer = HBoxContainer.new()
	item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_child(item_row)

	# Product name.
	var name_label: Label = Label.new()
	name_label.text = product_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(
		"font_size",
		item_font_size
	)

	item_row.add_child(name_label)

	# Product price.
	var price_label: Label = Label.new()
	price_label.text = "$%.2f" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override(
		"font_size",
		price_font_size
	)

	item_row.add_child(price_label)

	# Update totals.
	subtotal += price

	header_label.text = "CHECKOUT"
	subtotal_label.text = "SUBTOTAL: $%.2f" % subtotal
	total_label.text = "TOTAL: $%.2f" % subtotal

	separator.show()
	subtotal_label.show()
	_scroll_to_latest_item.call_deferred()

func complete_sale() -> void:
	header_label.text = "SALE COMPLETE"
	total_label.text = "TOTAL: $%.2f" % subtotal

	separator.hide()
	subtotal_label.hide()

	# Keep scanned items visible until the timer expires.
	sale_complete_timer.start(sale_complete_delay)


func _on_sale_complete_timer_timeout() -> void:
	reset_display()


func _scroll_to_latest_item() -> void:
	if not is_inside_tree():
		return

	scroll_container.scroll_vertical = int(
		scroll_container.get_v_scroll_bar().max_value
	)


func _clear_item_list() -> void:
	for child: Node in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
