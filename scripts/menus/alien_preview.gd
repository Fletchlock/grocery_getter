extends Node3D

@export var rotation_speed: float = 0.5

@onready var character_pivot: Node3D = $CharacterPivot
@onready var alien_appearance: AlienAppearance = $CharacterPivot/AlienPreviewCharacter/AlienAppearance
@onready var weight_slider: HSlider = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/WeightSlider
@onready var skin_color_picker: ColorPickerButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/SkinColorPicker
@onready var pattern_color_picker: ColorPickerButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/PatternColorPicker

func _ready() -> void:
	if alien_appearance.appearance_data != null:
		weight_slider.set_value_no_signal(
			alien_appearance.appearance_data.body_weight
		)
	skin_color_picker.color = alien_appearance.skin_color
	pattern_color_picker.color = alien_appearance.pattern_color

func set_character_rotation(value: float) -> void:
	character_pivot.rotation_degrees.y = value

func _on_weight_slider_value_changed(value: float) -> void:
	print("Weight slider changed: ", value)
	alien_appearance.set_body_weight(value)
	print("Alien body weight: ", alien_appearance.body_weight)

func _on_rotation_slider_value_changed(value: float) -> void:
	set_character_rotation(value)

func _on_skin_color_picker_color_changed(color: Color) -> void:
	alien_appearance.set_skin_color(color)

func _on_pattern_color_picker_color_changed(color: Color) -> void:
	alien_appearance.set_pattern_color(color)
