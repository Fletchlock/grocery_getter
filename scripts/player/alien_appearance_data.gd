
extends Resource
class_name AlienAppearanceData

# Body
@export_range(0.0, 1.0, 0.01) var body_weight: float = 0.5
@export var skin_color: Color = Color("#40bf59")
@export var pattern_color: Color = Color("#0d401a")
@export var pattern_index: int = 0

# Face
@export var pupil_color: Color = Color("#240c38")
@export var lips_use_skin_color: bool = true
@export var lip_color: Color = Color("#c95b86")
@export var eyelashes_enabled: bool = false

# Equipment styles
@export var head_style: int = 0
@export var top_style: int = 0
@export var bottom_style: int = 0
@export var feet_style: int = 0

# Equipment colors
@export var top_color: int = 7
@export var bottom_color: int = 3
@export var feet_color: int = 0
@export var sole_color: int = 7


func to_dict() -> Dictionary:
	return {
		"body_weight": body_weight,
		"skin_color": skin_color.to_html(),
		"pattern_color": pattern_color.to_html(),
		"pattern_index": pattern_index,
		"pupil_color": pupil_color.to_html(),
		"lips_use_skin_color": lips_use_skin_color,
		"lip_color": lip_color.to_html(),
		"eyelashes_enabled": eyelashes_enabled,
		"head_style": head_style,
		"top_style": top_style,
		"bottom_style": bottom_style,
		"feet_style": feet_style,
		"top_color": top_color,
		"bottom_color": bottom_color,
		"feet_color": feet_color,
		"sole_color": sole_color
	}


static func from_dict(data: Dictionary) -> AlienAppearanceData:
	var appearance: AlienAppearanceData = AlienAppearanceData.new()

	appearance.body_weight = clampf(
		float(data.get("body_weight", appearance.body_weight)),
		0.0,
		1.0
	)

	appearance.skin_color = Color.html(
		str(data.get("skin_color", appearance.skin_color.to_html()))
	)
	appearance.pattern_color = Color.html(
		str(data.get("pattern_color", appearance.pattern_color.to_html()))
	)
	appearance.pattern_index = int(data.get("pattern_index", appearance.pattern_index))

	appearance.pupil_color = Color.html(
		str(data.get("pupil_color", appearance.pupil_color.to_html()))
	)
	appearance.lips_use_skin_color = bool(
		data.get("lips_use_skin_color", appearance.lips_use_skin_color)
	)
	appearance.lip_color = Color.html(
		str(data.get("lip_color", appearance.lip_color.to_html()))
	)
	appearance.eyelashes_enabled = bool(
		data.get("eyelashes_enabled", appearance.eyelashes_enabled)
	)

	appearance.head_style = int(data.get("head_style", appearance.head_style))
	appearance.top_style = int(data.get("top_style", appearance.top_style))
	appearance.bottom_style = int(data.get("bottom_style", appearance.bottom_style))
	appearance.feet_style = int(data.get("feet_style", appearance.feet_style))

	appearance.top_color = int(data.get("top_color", appearance.top_color))
	appearance.bottom_color = int(data.get("bottom_color", appearance.bottom_color))
	appearance.feet_color = int(data.get("feet_color", appearance.feet_color))
	appearance.sole_color = int(data.get("sole_color", appearance.sole_color))

	return appearance
