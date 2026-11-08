
extends Control

signal back_requested

@onready var options_panel: PanelContainer = $OptionsPanel
@onready var display_settings: PanelContainer = $DisplaySettings
@onready var audio_settings: Control = $AudioSettings

@onready var display_button: Button = $OptionsPanel/MarginContainer/VBoxContainer/DisplayButton
@onready var graphics_button: Button = $OptionsPanel/MarginContainer/VBoxContainer/GraphicsButton
@onready var controls_button: Button = $OptionsPanel/MarginContainer/VBoxContainer/ControlsButton
@onready var audio_button: Button = $OptionsPanel/MarginContainer/VBoxContainer/AudioButton
@onready var options_back_button: Button = $OptionsPanel/MarginContainer/VBoxContainer/BackButton

@onready var display_back_button: Button = $DisplaySettings/MarginContainer/VBoxContainer/BackButton
@onready var audio_back_button: Button = $AudioSettings/MarginContainer/VBoxContainer/BackButton

@onready var display_first_control: Control = $DisplaySettings/MarginContainer/VBoxContainer/DisplayModeContainer/ModeOption
@onready var audio_first_control: Control = $AudioSettings/MarginContainer/VBoxContainer/MasterContainer/MasterSlider


func _ready() -> void:
	display_button.pressed.connect(_open_display)
	audio_button.pressed.connect(_open_audio)
	graphics_button.pressed.connect(_on_graphics_pressed)
	controls_button.pressed.connect(_on_controls_pressed)

	options_back_button.pressed.connect(_request_back)
	display_back_button.pressed.connect(_close_display)
	audio_back_button.pressed.connect(_close_audio)

	options_panel.show()
	display_settings.hide()
	audio_settings.hide()

	display_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return

	get_viewport().set_input_as_handled()

	if display_settings.visible:
		_close_display()
	elif audio_settings.visible:
		_close_audio()
	else:
		_request_back()


func _open_display() -> void:
	options_panel.hide()
	display_settings.show()
	display_first_control.grab_focus.call_deferred()


func _close_display() -> void:
	display_settings.hide()
	options_panel.show()
	display_button.grab_focus.call_deferred()


func _open_audio() -> void:
	options_panel.hide()
	audio_settings.show()
	audio_first_control.grab_focus.call_deferred()


func _close_audio() -> void:
	audio_settings.hide()
	options_panel.show()
	audio_button.grab_focus.call_deferred()


func _request_back() -> void:
	back_requested.emit()


func _on_graphics_pressed() -> void:
	print("Graphics Settings")


func _on_controls_pressed() -> void:
	print("Controls Settings")
