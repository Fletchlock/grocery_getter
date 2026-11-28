extends Control
class_name SnakeGame


const GRID_COLUMNS: int = 28
const GRID_ROWS: int = 18

const BACKGROUND_COLOR: Color = Color("#07140f")
const BOARD_COLOR: Color = Color("#0b2118")
const GRID_COLOR: Color = Color("#153b29")
const SNAKE_COLOR: Color = Color("#70e090")
const SNAKE_HEAD_COLOR: Color = Color("#c5ffd1")
const FOOD_COLOR: Color = Color("#ff665e")
const TEXT_COLOR: Color = Color("#b8e8c7")


var snake_body: Array[Vector2i] = []
var food_position: Vector2i = Vector2i.ZERO
var score: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func set_game_state(
	new_body: Array[Vector2i],
	new_food_position: Vector2i,
	new_score: int
) -> void:
	snake_body = new_body.duplicate()
	food_position = new_food_position
	score = new_score
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)

	var font: Font = get_theme_default_font()
	if font == null:
		return

	draw_string(
		font,
		Vector2(24.0, 34.0),
		"SNAKE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		25,
		SNAKE_HEAD_COLOR
	)

	draw_string(
		font,
		Vector2(size.x - 250.0, 32.0),
		"SCORE  %03d" % score,
		HORIZONTAL_ALIGNMENT_RIGHT,
		210.0,
		18,
		TEXT_COLOR
	)

	var available_width: float = size.x - 48.0
	var available_height: float = size.y - 92.0
	var cell_size: float = floorf(
		minf(
			available_width / float(GRID_COLUMNS),
			available_height / float(GRID_ROWS)
		)
	)

	var board_size := Vector2(
		cell_size * GRID_COLUMNS,
		cell_size * GRID_ROWS
	)

	var board_origin := Vector2(
		(size.x - board_size.x) * 0.5,
		58.0 + (available_height - board_size.y) * 0.5
	)

	var board_rect := Rect2(board_origin, board_size)
	draw_rect(board_rect, BOARD_COLOR, true)
	draw_rect(board_rect, GRID_COLOR, false, 2.0)

	for column in range(1, GRID_COLUMNS):
		var x: float = board_origin.x + float(column) * cell_size
		draw_line(
			Vector2(x, board_origin.y),
			Vector2(x, board_origin.y + board_size.y),
			GRID_COLOR,
			1.0
		)

	for row in range(1, GRID_ROWS):
		var y: float = board_origin.y + float(row) * cell_size
		draw_line(
			Vector2(board_origin.x, y),
			Vector2(board_origin.x + board_size.x, y),
			GRID_COLOR,
			1.0
		)

	var food_center := board_origin + (
		Vector2(food_position) + Vector2(0.5, 0.5)
	) * cell_size

	draw_circle(food_center, cell_size * 0.34, FOOD_COLOR)

	for i in range(snake_body.size()):
		var segment: Vector2i = snake_body[i]
		var segment_rect := Rect2(
			board_origin + Vector2(segment) * cell_size + Vector2(2.0, 2.0),
			Vector2(cell_size - 4.0, cell_size - 4.0)
		)

		var segment_color: Color = (
			SNAKE_HEAD_COLOR if i == 0 else SNAKE_COLOR
		)

		draw_rect(segment_rect, segment_color, true)

	draw_string(
		font,
		Vector2(size.x * 0.5, size.y - 12.0),
		"ESC OR Q TO EXIT",
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		14,
		TEXT_COLOR
	)
