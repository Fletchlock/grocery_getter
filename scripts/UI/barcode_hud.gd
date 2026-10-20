extends PanelContainer

signal code_completed(product_code: String)

@onready var label: Label = $Label

var product_code: String = ""
var entered_count: int = 0


func _ready() -> void:
	hide()
	_update_label()


func update_display(new_value: String) -> void:
	var new_code := new_value.strip_edges().to_upper()

	# Preserve progress if the prompt refreshes with the same code.
	# Reset it if a different product code appears.
	if new_code != product_code:
		product_code = new_code
		entered_count = 0

	_update_label()


func _process(_delta: float) -> void:
	if product_code.is_empty():
		return

	var entered_direction := ""

	if Input.is_action_just_pressed("up"):
		entered_direction = "U"
	elif Input.is_action_just_pressed("down"):
		entered_direction = "D"
	elif Input.is_action_just_pressed("right"):
		entered_direction = "R"
	elif Input.is_action_just_pressed("left"):
		entered_direction = "L"

	if entered_direction.is_empty():
		return

	_check_direction(entered_direction)


func _check_direction(entered_direction: String) -> void:
	var expected_direction := product_code.substr(entered_count, 1)

	if entered_direction != expected_direction:
		entered_count = 0
		_update_label()
		return

	entered_count += 1
	_update_label()

	if entered_count == product_code.length():
		code_completed.emit(product_code)


func _update_label() -> void:
	label.text = "Enter product code: " + product_code
	visible = not product_code.is_empty()
