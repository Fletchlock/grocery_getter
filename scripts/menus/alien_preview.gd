extends Node3D

signal customization_confirmed(appearance: AlienAppearanceData)

@export var rotation_speed: float = 0.5

@onready var character_pivot: Node3D = $CharacterPivot
@onready var alien_appearance: AlienAppearance = $CharacterPivot/AlienPreviewCharacter/AlienAppearance
@onready var weight_slider: HSlider = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/WeightSlider
@onready var skin_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/SkinColorPalette
@onready var pattern_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/PatternColorPalette
@onready var skin_pattern_value: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Body/SkinPatternRow/SkinPatternValue
@onready var pupil_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/PupilColorPalette
@onready var match_skin_color: CheckButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/HBoxContainer/MatchSkinColor
@onready var lip_color_label: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/HBoxContainer/LipColorLabel
@onready var lip_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/LipColorPalette
@onready var eyelashes_toggle: CheckButton = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/EyelashesToggle
@onready var head_style_value: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Head/HeadStyleRow/HeadStyleValue
@onready var top_style_value: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/HBoxContainer/TopStyleRow/TopStyleValue
@onready var top_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/TopColorPalette
@onready var bottom_style_value: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/HBoxContainer2/BottomStyleRow/BottomStyleValue
@onready var bottom_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/BottomColorPalette
@onready var feet_style_value: Label = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/HBoxContainer3/FeetStyleRow/FeetStyleValue
@onready var feet_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/FeetColorPalette
@onready var sole_color_palette: AlienColorPalette = $CanvasLayer/CustomizationPanel/VBoxContainer/TabContainer/Clothing/SoleColorPalette

var current_feet_style: int = 0
var current_bottom_style: int = 0
var current_top_style: int = 0
var current_head_style: int = 0

var initial_appearance: AlienAppearanceData = null


func _ready() -> void:
	
	if initial_appearance != null:
		alien_appearance.appearance_data = initial_appearance.duplicate(true) as AlienAppearanceData
		alien_appearance.apply_appearance(alien_appearance.appearance_data)

	if alien_appearance.appearance_data != null:
		weight_slider.set_value_no_signal(
			alien_appearance.appearance_data.body_weight
		)
		current_head_style = alien_appearance.appearance_data.head_style
		current_top_style = alien_appearance.appearance_data.top_style
		current_bottom_style = alien_appearance.appearance_data.bottom_style
		current_feet_style = alien_appearance.appearance_data.feet_style
		
	skin_color_palette.select_color(alien_appearance.skin_color)
	pattern_color_palette.select_color(alien_appearance.pattern_color)
	pupil_color_palette.select_color(alien_appearance.pupil_color)
	match_skin_color.set_pressed_no_signal(alien_appearance.lips_use_skin_color)
	lip_color_palette.select_color(alien_appearance.lip_color)
	eyelashes_toggle.set_pressed_no_signal(alien_appearance.eyelashes_enabled)

	_update_lip_controls()
	_update_skin_pattern_display()
	_update_head_style_display()
	_update_top_style_display()
	_update_bottom_style_display()
	_update_feet_style_display()
	
	top_color_palette.select_color(
		AlienAppearance.CLOTHING_COLORS[alien_appearance.top_color]
	)
	bottom_color_palette.select_color(
		AlienAppearance.CLOTHING_COLORS[alien_appearance.bottom_color]
	)
	feet_color_palette.select_color(
		AlienAppearance.CLOTHING_COLORS[alien_appearance.feet_color]
	)

	sole_color_palette.select_color(
		AlienAppearance.CLOTHING_COLORS[alien_appearance.sole_color]
	)

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


func _on_previous_pattern_pressed() -> void:
	_change_skin_pattern(-1)


func _on_next_pattern_pressed() -> void:
	_change_skin_pattern(1)


func _change_skin_pattern(direction: int) -> void:
	var pattern_count: int = alien_appearance.skin_patterns.size()

	if pattern_count == 0:
		return

	var index: int = wrapi(
		alien_appearance.skin_pattern + direction,
		0,
		pattern_count
	)

	alien_appearance.set_skin_pattern(index)
	_update_skin_pattern_display()


func _update_skin_pattern_display() -> void:
	var pattern_count: int = alien_appearance.skin_patterns.size()

	if pattern_count == 0:
		skin_pattern_value.text = "No Patterns"
		return

	skin_pattern_value.text = "%d / %d" % [
		alien_appearance.skin_pattern + 1,
		pattern_count
	]


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

func _on_previous_head_pressed() -> void:
	_change_head_style(-1)

func _on_next_head_pressed() -> void:
	_change_head_style(1)

func _change_head_style(direction: int) -> void:
	var style_count: int = alien_appearance.head_meshes.size()

	if style_count == 0:
		return

	current_head_style = wrapi(
		current_head_style + direction + 1,
		0,
		style_count + 1
	) - 1

	alien_appearance.set_head_style(current_head_style)
	_update_head_style_display()

func _update_head_style_display() -> void:
	var style_count: int = alien_appearance.head_meshes.size()

	if current_head_style == -1:
		head_style_value.text = "None"
	else:
		head_style_value.text = "%d / %d" % [
			current_head_style + 1,
			style_count
		]

func _on_previous_top_pressed() -> void:
	_change_top_style(-1)


func _on_next_top_pressed() -> void:
	_change_top_style(1)

func _change_top_style(direction: int) -> void:
	var style_count: int = alien_appearance.top_meshes.size()

	if style_count == 0:
		return

	current_top_style = wrapi(
		current_top_style + direction + 1,
		0,
		style_count + 1
	) - 1

	alien_appearance.set_top_style(current_top_style)
	_update_top_style_display()

func _update_top_style_display() -> void:
	var style_count: int = alien_appearance.top_meshes.size()

	if current_top_style == -1:
		top_style_value.text = "None"
	elif style_count == 0:
		top_style_value.text = "No Styles"
	else:
		top_style_value.text = "%d / %d" % [
			current_top_style + 1,
			style_count
		]
	
func _on_top_color_palette_color_selected(color: Color) -> void:
	print("Selected top color: ", color.to_html(false))

	for i: int in range(AlienAppearance.CLOTHING_COLORS.size()):
		var available_color: Color = AlienAppearance.CLOTHING_COLORS[i]

		if available_color.to_html(false) == color.to_html(false):
			print("Matched clothing color index: ", i)
			alien_appearance.set_top_color(i)
			return

	print("No matching clothing color found!")

func _on_previous_bottom_pressed() -> void:
	_change_bottom_style(-1)

func _on_next_bottom_pressed() -> void:
	_change_bottom_style(1)

func _change_bottom_style(direction: int) -> void:
	var style_count: int = alien_appearance.bottom_meshes.size()

	if style_count == 0:
		return

	current_bottom_style = wrapi(
		current_bottom_style + direction + 1,
		0,
		style_count + 1
	) - 1

	alien_appearance.set_bottom_style(current_bottom_style)
	_update_bottom_style_display()

func _update_bottom_style_display() -> void:
	var style_count: int = alien_appearance.bottom_meshes.size()

	if current_bottom_style == -1:
		bottom_style_value.text = "None"
	elif style_count == 0:
		bottom_style_value.text = "No Styles"
	else:
		bottom_style_value.text = "%d / %d" % [
			current_bottom_style + 1,
			style_count
		]

func _on_bottom_color_palette_color_selected(color: Color) -> void:
	for i: int in range(AlienAppearance.CLOTHING_COLORS.size()):
		if AlienAppearance.CLOTHING_COLORS[i].to_html(false) == color.to_html(false):
			alien_appearance.set_bottom_color(i)
			return

func _on_previous_feet_pressed() -> void:
	_change_feet_style(-1)


func _on_next_feet_pressed() -> void:
	_change_feet_style(1)

func _change_feet_style(direction: int) -> void:
	var style_count: int = alien_appearance.feet_meshes.size()

	if style_count == 0:
		return

	current_feet_style = wrapi(
		current_feet_style + direction + 1,
		0,
		style_count + 1
	) - 1

	alien_appearance.set_feet_style(current_feet_style)
	_update_feet_style_display()

func _update_feet_style_display() -> void:
	var style_count: int = alien_appearance.feet_meshes.size()

	if current_feet_style == -1:
		feet_style_value.text = "None"
	elif style_count == 0:
		feet_style_value.text = "No Styles"
	else:
		feet_style_value.text = "%d / %d" % [
			current_feet_style + 1,
			style_count
		]

func _on_feet_color_palette_color_selected(color: Color) -> void:
	for i: int in range(AlienAppearance.CLOTHING_COLORS.size()):
		if AlienAppearance.CLOTHING_COLORS[i].to_html(false) == color.to_html(false):
			alien_appearance.set_feet_color(i)
			return

func _on_sole_color_palette_color_selected(color: Color) -> void:
	for i: int in range(AlienAppearance.CLOTHING_COLORS.size()):
		if AlienAppearance.CLOTHING_COLORS[i].to_html(false) == color.to_html(false):
			alien_appearance.set_sole_color(i)
			return

func get_current_appearance() -> AlienAppearanceData:
	var data: AlienAppearanceData = AlienAppearanceData.new()

	data.body_weight = alien_appearance.body_weight
	data.skin_color = alien_appearance.skin_color
	data.pattern_color = alien_appearance.pattern_color

	data.pupil_color = alien_appearance.pupil_color
	data.lips_use_skin_color = alien_appearance.lips_use_skin_color
	data.lip_color = alien_appearance.lip_color
	data.eyelashes_enabled = alien_appearance.eyelashes_enabled

	data.head_style = current_head_style
	data.top_style = current_top_style
	data.bottom_style = current_bottom_style
	data.feet_style = current_feet_style

	data.top_color = alien_appearance.top_color
	data.bottom_color = alien_appearance.bottom_color
	data.feet_color = alien_appearance.feet_color
	data.sole_color = alien_appearance.sole_color

	if alien_appearance.appearance_data != null:
		data.pattern_index = alien_appearance.skin_pattern

	return data


func confirm_customization() -> void:
	var appearance: AlienAppearanceData = get_current_appearance()
	customization_confirmed.emit(appearance)


func _on_confirm_button_pressed() -> void:
	confirm_customization()

	print("ALIEN CUSTOMIZATION: Character confirmed.")
