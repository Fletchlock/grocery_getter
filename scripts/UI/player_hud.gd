extends PanelContainer

@onready var player_hud: Control = self
@onready var scale_menu_button: MenuButton = \
	$ScannerScalesMenu/VBoxContainer/ScaleSelect
@onready var scale_preview_player: AudioStreamPlayer = $ScalePreviewPlayer

var player_hud_open := false
var player_hud_tween: Tween
var preview_generation := 0

const NOTE_INTERVAL := 0.15 # seconds between notes for the scale previews


func _ready() -> void:
	player_hud.position.x = size.x
	player_hud.visible = false

	var popup := scale_menu_button.get_popup()
	popup.clear()

	for scale_data in Scales.SCALE_OPTIONS:
		popup.add_check_item(scale_data["name"], scale_data["id"])

	popup.id_pressed.connect(_on_scale_selected)
	_update_scale_checkmark()


func _process(_delta: float) -> void:
	pass


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey \
	and event.pressed \
	and not event.echo \
	and event.keycode == KEY_TAB:
		toggle_player_hud()
		get_viewport().set_input_as_handled()


func toggle_player_hud() -> void:
	player_hud_open = not player_hud_open
	player_hud.visible = true

	if player_hud_tween and player_hud_tween.is_running():
		player_hud_tween.kill()

	var target_x := size.x - player_hud.size.x if player_hud_open else size.x

	player_hud_tween = create_tween()
	player_hud_tween.set_trans(Tween.TRANS_CUBIC)
	player_hud_tween.set_ease(Tween.EASE_OUT)
	player_hud_tween.tween_property(
		player_hud,
		"position:x",
		target_x,
		0.3
	)

	if not player_hud_open:
		player_hud_tween.tween_callback(func() -> void:
			player_hud.visible = false
		)
		


func _on_scale_selected(id: int) -> void:
	print("Scale menu ID: ", id)
	for scale_data in Scales.SCALE_OPTIONS:
		if scale_data["id"] == id:
			Scales.selected_scale_id = id
			Scales.selected_scale = scale_data["ratios"]
			_update_scale_checkmark()
			_play_scale_preview()
			return

	Scales.selected_scale_id = id
	_update_scale_checkmark()


func _update_scale_checkmark() -> void:
	var popup := scale_menu_button.get_popup()

	for i in range(popup.item_count):
		popup.set_item_checked(
			i,
			popup.get_item_id(i) == Scales.selected_scale_id
		)


func _play_scale_preview() -> void:
	preview_generation += 1
	var this_preview := preview_generation

	scale_preview_player.stop()

	# Play each scale degree, then the tonic one octave higher.
	var notes: Array = Scales.selected_scale.duplicate()
	notes.append(2.0)

	for ratio in notes:
		if this_preview != preview_generation:
			return

		scale_preview_player.stop()
		scale_preview_player.pitch_scale = ratio
		scale_preview_player.play()

		await get_tree().create_timer(NOTE_INTERVAL).timeout
