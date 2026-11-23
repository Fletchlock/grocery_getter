extends VBoxContainer
class_name AlienColorPalette


signal color_selected(color: Color)


@export var colors: Array[Color] = [
	Color("#4cb361"),
	Color("#78c85a"),
	Color("#31b5a4"),
	Color("#4387d4"),
	Color("#8a60c9"),
	Color("#d67ac4"),
	Color("#e2ad63"),
	Color("#d8794c"),
	Color("#a5a5a5"),
	Color("#e7d8b9"),
	Color("#c9d94c"),
	Color("#4e8791")
]

@export var swatch_size: Vector2 = Vector2(40.0, 40.0)
@export var corner_radius: int = 8

@onready var grid: GridContainer = $GridContainer

var selected_index: int = -1
var button_group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	_create_swatches()


func _create_swatches() -> void:
	for child: Node in grid.get_children():
		child.queue_free()

	for i: int in range(colors.size()):
		var button: Button = Button.new()

		button.custom_minimum_size = swatch_size
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = button_group

		var normal_style: StyleBoxFlat = StyleBoxFlat.new()
		normal_style.bg_color = colors[i]
		normal_style.set_corner_radius_all(corner_radius)

		var selected_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
		selected_style.border_color = Color.WHITE
		selected_style.set_border_width_all(3)

		var focus_style: StyleBoxFlat = StyleBoxFlat.new()
		focus_style.bg_color = Color.TRANSPARENT
		focus_style.border_color = Color.YELLOW
		focus_style.set_border_width_all(2)
		focus_style.set_corner_radius_all(corner_radius)

		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", normal_style)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		button.add_theme_stylebox_override("focus", focus_style)

		button.pressed.connect(_on_swatch_pressed.bind(i))

		grid.add_child(button)


func _on_swatch_pressed(index: int) -> void:
	selected_index = index
	color_selected.emit(colors[index])


func select_color(color: Color) -> void:
	var target_hex: String = color.to_html(false)

	print("Looking for color: ", target_hex)

	for i: int in range(colors.size()):
		var swatch_hex: String = colors[i].to_html(false)

		print("Swatch ", i, ": ", swatch_hex)

		if swatch_hex == target_hex:
			selected_index = i

			var button: Button = grid.get_child(i) as Button
			button.button_pressed = true

			print("Matched swatch: ", i)
			return

	print("No matching swatch found.")
