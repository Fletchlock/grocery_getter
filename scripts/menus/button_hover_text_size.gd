extends Button

@export var normal_font_size: int = 36
@export var highlighted_font_size: int = 40


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_update_font_size)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_update_font_size)
	pressed.connect(_on_pressed)

	_update_font_size()


func _on_mouse_entered() -> void:
	if (
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
		and focus_mode != Control.FOCUS_NONE
		and not disabled
	):
		grab_focus()

	_update_font_size()
	UiSoundManager.play_hover()


func _on_focus_entered() -> void:
	_update_font_size()

	if not is_hovered():
		UiSoundManager.play_hover()


func _on_pressed() -> void:
	UiSoundManager.play_click()


func _update_font_size() -> void:
	var highlighted: bool = (
		(is_hovered() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
		or has_focus()
	)

	if highlighted:
		add_theme_font_size_override(
			"font_size",
			highlighted_font_size
		)
	else:
		add_theme_font_size_override(
			"font_size",
			normal_font_size
		)
