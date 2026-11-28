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
const HALF_STEP_MULTIPLIER := 0.05946
const KEYPRESS_SOUNDS := [
	preload("res://assets/sounds/keypress1.wav"),
	preload("res://assets/sounds/keypress2.wav"),
	preload("res://assets/sounds/keypress3.wav"),
	preload("res://assets/sounds/keypress4.wav"),
	preload("res://assets/sounds/keypress5.wav"),
]
const KEYPRESS_VOLUME_DB := -15.0

var product_code := ""
var entered_count := 0
var showing_error := false
var error_timer: Timer
var completing_code := false
var root_note := 1
var scan_combo := 0


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

	for i in range(product_code.length()):
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(48, 48)
		arrow_container.add_child(slot)

		var arrow := TextureRect.new()
		arrow.custom_minimum_size = Vector2(48, 48)
		arrow.size = Vector2(500, 500)
		arrow.position = Vector2(-226, 300) # Start just below its slot
		arrow.modulate.a = 0.0
		arrow.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(arrow)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(arrow, "position:y", 0.0, 0.12)\
			.set_delay(i * 0.04)\
			.set_trans(Tween.TRANS_CUBIC)\
			.set_ease(Tween.EASE_OUT)

		tween.tween_property(arrow, "modulate:a", 1.0, 0.12)\
			.set_delay(i * 0.04)

	_update_arrows()
	visible = not product_code.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if showing_error or product_code.is_empty():
		return

	var direction := ""

	if event.is_action_pressed("barcode_up") and not event.is_echo():
		direction = "U"
	elif event.is_action_pressed("barcode_down") and not event.is_echo():
		direction = "D"
	elif event.is_action_pressed("barcode_left") and not event.is_echo():
		direction = "L"
	elif event.is_action_pressed("barcode_right") and not event.is_echo():
		direction = "R"

	if direction.is_empty():
		return

	get_viewport().set_input_as_handled()
	_check_direction(direction)


func _check_direction(direction: String) -> void:
	if entered_count >= product_code.length():
		return

	_play_random_keypress()

	if direction == product_code.substr(entered_count, 1):
		var note_index := entered_count

		# Animate the correctly entered arrow.
		_animate_arrow_press(note_index, true)

		entered_count += 1

		correct_sound.stop()

		if scan_combo == 0:
			correct_sound.pitch_scale = Scales.selected_scale[note_index]
		else:
			correct_sound.pitch_scale = (1 + scan_combo * HALF_STEP_MULTIPLIER) * Scales.selected_scale[note_index]

		correct_sound.play()
		_update_arrows()

		if entered_count == product_code.length():
			scan_combo += 1
			completing_code = true

	else:
		# Animate the current arrow, returning it to its original height.
		_animate_arrow_press(entered_count, false)

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

		var arrow := arrow_container.get_child(i).get_child(0) as TextureRect
		arrow.texture = ARROW_TEXTURES[direction][state]


func _on_error_timeout() -> void:
	entered_count = 0
	showing_error = false
	_update_arrows()


func _on_correct_sound_finished() -> void:
	if completing_code:
		completing_code = false
		code_completed.emit(product_code)


func _play_random_keypress() -> void:
	var sound_player := AudioStreamPlayer.new()
	sound_player.stream = KEYPRESS_SOUNDS.pick_random()
	sound_player.volume_db = KEYPRESS_VOLUME_DB
	sound_player.bus = "SFX"

	add_child(sound_player)

	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play()


func _animate_arrow_press(index: int, correct: bool) -> void:
	if index >= arrow_container.get_child_count():
		return

	var arrow := arrow_container.get_child(index).get_child(0) as TextureRect

	# Stop any existing press animation on this arrow.
	if arrow.has_meta("press_tween"):
		var previous_tween := arrow.get_meta("press_tween") as Tween
		if previous_tween and previous_tween.is_running():
			previous_tween.kill()

	# Correct inputs stay slightly depressed.
	var resting_position := 10.0 if correct else 0.0

	var tween := arrow.create_tween()
	arrow.set_meta("press_tween", tween)

	# Quick downward press.
	tween.tween_property(arrow, "position:y", 20.0, 0.045)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)

	# Slower release back to resting position.
	tween.tween_property(arrow, "position:y", resting_position, 0.10)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
