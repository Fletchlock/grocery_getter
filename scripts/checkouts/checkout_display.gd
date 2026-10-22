
extends Control
class_name CheckoutDisplay

@export var sale_complete_delay: float = 5.0

var _display_version: int = 0

@onready var header_label: Label = $PanelContainer/VBoxContainer/HeaderLabel
@onready var item_list: VBoxContainer = $PanelContainer/VBoxContainer/ItemList
@onready var separator: HSeparator = $PanelContainer/VBoxContainer/HSeparator
@onready var subtotal_label: Label = $PanelContainer/VBoxContainer/SubtotalLabel
@onready var total_label: Label = $PanelContainer/VBoxContainer/TotalLabel

var subtotal: float = 0.0


func _ready() -> void:
	reset_display()


func reset_display() -> void:
	_display_version += 1
	subtotal = 0.0

	for child: Node in item_list.get_children():
		child.queue_free()

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
	var item_row: HBoxContainer = HBoxContainer.new()
	item_list.add_child(item_row)

	var name_label: Label = Label.new()
	name_label.text = product_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_row.add_child(name_label)

	var price_label: Label = Label.new()
	price_label.text = "$%.2f" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	item_row.add_child(price_label)

	subtotal += price

	header_label.text = "CHECKOUT"
	subtotal_label.text = "SUBTOTAL: $%.2f" % subtotal
	total_label.text = "TOTAL: $%.2f" % subtotal


func complete_sale() -> void:
	for child: Node in item_list.get_children():
		child.queue_free()

	header_label.text = "SALE COMPLETE"
	total_label.text = "TOTAL: $%.2f" % subtotal

	separator.hide()
	subtotal_label.hide()

	_display_version += 1
	var version: int = _display_version

	await get_tree().create_timer(sale_complete_delay).timeout

	if not is_inside_tree():
		return

	if version != _display_version:
		return

	reset_display()
