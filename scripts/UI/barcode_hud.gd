extends PanelContainer

signal code_completed(product_code: String)

@onready var arrow_container: HBoxContainer = $ArrowContainer
@onready var correct_sound: AudioStreamPlayer = $CorrectSound
@onready var error_sound: AudioStreamPlayer = $ErrorSound

const ERROR_DISPLAY_TIME := 0.45
const ARROW_TEXTURES := {
	"U": {
		"default": preload("res://assets/images/scanCodeUp.png"),
		"active": preload("res://assets/images/scanCodeUpY.png"),
		"wrong": preload("res://assets/images/scanCodeUpR.png"),
		"complete": preload("res://assets/images/scanCodeUpG.png"),
	},
	"D": {
		"default": preload("res://assets/images/scanCodeDown.png"),
		"active": preload("res://assets/images/scanCodeDownY.png"),
		"wrong": preload("res://assets/images/scanCodeDownR.png"),
		"complete": preload("res://assets/images/scanCodeDownG.png"),
	},
	"L": {
		"default": preload("res://assets/images/scanCodeLeft.png"),
		"active": preload("res://assets/images/scanCodeLeftY.png"),
		"wrong": preload("res://assets/images/scanCodeLeftR.png"),
		"complete": preload("res://assets/images/scanCodeLeftG.png"),
	},
	"R": {
		"default": preload("res://assets/images/scanCodeRight.png"),
		"active": preload("res://assets/images/scanCodeRightY.png"),
		"wrong": preload("res://assets/images/scanCodeRightR.png"),
		"complete": preload("res://assets/images/scanCodeRightG.png"),
	},
}
#SCALE RATIOS
const LYDIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	45.0 / 32.0, # augmented fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	15.0 / 8.0 # major seventh
]
const IONIAN := [ #Major Scale
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	15.0 / 8.0 # major seventh
]
const MIXOLYDIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	9.0 / 5.0 # minor seventh
]
const DORIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	9.0 / 5.0 # minor seventh
]
const AEOLIAN := [ #Natural Minor Scale
	1.0,       # tonic
	9.0 / 8.0, # major second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]
const PHRYGIAN := [
	1.0,       # tonic
	16.0 / 15.0, # minor second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]
const LOCRIAN := [
	1.0,       # tonic
	16.0 / 15.0, # minor second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	45.0 / 32.0, # tritone
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]
const HALF_STEP_MULTIPLIER := 0.05946

var product_code := ""
var entered_count := 0
var showing_error := false
var error_timer: Timer
var completing_code := false
var root_note := 1
var scan_combo := 0
var musical_scale = IONIAN


func _ready() -> void:
	hide()
	correct_sound.stream = preload("res://assets/sounds/scan_code_scale.wav")
	error_sound.stream = preload("res://assets/sounds/scan_code_error.wav")

	correct_sound.finished.connect(_on_correct_sound_finished)

	error_timer = Timer.new()
	error_timer.one_shot = true
	error_timer.wait_time = ERROR_DISPLAY_TIME
	error_timer.timeout.connect(_on_error_timeout)
	add_child(error_timer)


func update_display(new_product_code: String) -> void:
	product_code = new_product_code.to_upper()
	entered_count = 0
	showing_error = false
	error_timer.stop()

	for child in arrow_container.get_children():
		child.queue_free()

	for _i in range(product_code.length()):
		var arrow := TextureRect.new()
		arrow.custom_minimum_size = Vector2(48, 48)
		arrow.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow_container.add_child(arrow)

	_update_arrows()
	visible = not product_code.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if showing_error or product_code.is_empty():
		return

	var direction := ""

	if event.is_action_pressed("up") and not event.is_echo():
		direction = "U"
	elif event.is_action_pressed("down") and not event.is_echo():
		direction = "D"
	elif event.is_action_pressed("left") and not event.is_echo():
		direction = "L"
	elif event.is_action_pressed("right") and not event.is_echo():
		direction = "R"

	if direction.is_empty():
		return

	get_viewport().set_input_as_handled()
	_check_direction(direction)


func _check_direction(direction: String) -> void:
	if entered_count >= product_code.length():
		return

	if direction == product_code.substr(entered_count, 1):
		var note_index := entered_count
		entered_count += 1

		if scan_combo == 0:
			correct_sound.stop()
			correct_sound.pitch_scale = musical_scale[note_index] 
			correct_sound.play()

			_update_arrows()

		else:
			correct_sound.stop()
			correct_sound.pitch_scale = (1 + scan_combo * HALF_STEP_MULTIPLIER) * musical_scale[note_index]
			correct_sound.play()

			_update_arrows()

		if entered_count == product_code.length():
			scan_combo += 1
			completing_code = true
			
	else:
		error_sound.stop()
		error_sound.pitch_scale = 1.0
		error_sound.play()

		showing_error = true
		_update_arrows()
		error_timer.start()
		scan_combo = 0


func _update_arrows() -> void:
	for i in range(product_code.length()):
		var direction := product_code.substr(i, 1)
		var state := "default"

		if showing_error:
			state = "wrong"
		elif i < entered_count:
			state = "complete"
		elif i == entered_count:
			state = "active"

		var arrow := arrow_container.get_child(i) as TextureRect
		arrow.texture = ARROW_TEXTURES[direction][state]


func _on_error_timeout() -> void:
	entered_count = 0
	showing_error = false
	_update_arrows()


func _on_correct_sound_finished() -> void:
	if completing_code:
		completing_code = false
		code_completed.emit(product_code)
