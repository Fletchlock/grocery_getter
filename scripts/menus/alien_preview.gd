extends Node3D

@export var rotation_speed: float = 0.5

@onready var character_pivot: Node3D = $CharacterPivot
@onready var alien_appearance: AlienAppearance = $CharacterPivot/AlienPreviewCharacter/AlienAppearance
@onready var weight_slider: HSlider = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/WeightSlider
@onready var skin_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/SkinColorPalette
@onready var pattern_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/PatternColorPalette
@onready var pupil_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/PupilColorPalette
@onready var match_skin_color: CheckButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/HBoxContainer/MatchSkinColor
@onready var lip_color_label: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/HBoxContainer/LipColorLabel
@onready var lip_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/LipColorPalette
@onready var eyelashes_toggle: CheckButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/EyelashesToggle


func _ready() -> void:
	if alien_appearance.appearance_data != null:
		weight_slider.set_value_no_signal(
			alien_appearance.appearance_data.body_weight
		)
	skin_color_palette.select_color(alien_appearance.skin_color)
	pattern_color_palette.select_color(alien_appearance.pattern_color)
	pupil_color_palette.select_color(alien_appearance.pupil_color)
	match_skin_color.set_pressed_no_signal(alien_appearance.lips_use_skin_color)
	lip_color_palette.select_color(alien_appearance.lip_color)
	eyelashes_toggle.set_pressed_no_signal(alien_appearance.eyelashes_enabled)

	_update_lip_controls()

func set_character_rotation(value: float) -> void:
	character_pivot.rotation_degrees.y = value

func _on_weight_slider_value_changed(value: float) -> void:
	print("Weight slider changed: ", value)
	alien_appearance.set_body_weight(value)
	print("Alien body weight: ", alien_appearance.body_weight)

func _on_rotation_slider_value_changed(value: float) -> void:
	set_character_rotation(value)

func _on_skin_color_palette_color_selected(color: Color) -> void:
	alien_appearance.set_skin_color(color)
	
func _on_pattern_color_palette_color_selected(color: Color) -> void:
	alien_appearance.set_pattern_color(color)

func _on_pupil_color_palette_color_selected(color: Color) -> void:
	alien_appearance.set_pupil_color(color)

func _on_match_skin_color_toggled(enabled: bool) -> void:
	alien_appearance.set_lips_use_skin_color(enabled)
	_update_lip_controls()

func _on_lip_color_palette_color_selected(color: Color) -> void:
	alien_appearance.set_lip_color(color)

func _update_lip_controls() -> void:
	var use_skin_color: bool = alien_appearance.lips_use_skin_color

	lip_color_label.modulate.a = 0.4 if use_skin_color else 1.0
	lip_color_palette.modulate.a = 0.4 if use_skin_color else 1.0
	lip_color_palette.mouse_filter = Control.MOUSE_FILTER_IGNORE if use_skin_color else Control.MOUSE_FILTER_STOP

	for button: Node in lip_color_palette.grid.get_children():
		if button is Button:
			var swatch: Button = button as Button
			swatch.disabled = use_skin_color


func _on_eyelashes_toggle_toggled(enabled: bool) -> void:
	alien_appearance.set_eyelashes_enabled(enabled)
