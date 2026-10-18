extends PanelContainer

# Reference the Label node
@onready var label: Label = $Label

var product_code: String = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()
	label.text = "Enter product code: " + product_code


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func update_display(new_value: String):
	var code := new_value.strip_edges()
	label.text = "Enter product code: " + code
	visible = not code.is_empty()
