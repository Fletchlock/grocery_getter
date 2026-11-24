
extends Resource
class_name PlayerData


# Player identity
@export var steam_id: int = 0

# Character appearance
@export var appearance: AlienAppearanceData = AlienAppearanceData.new()

# Personal progression (for future use)
@export var reputation: int = 0
@export var money: int = 0

# Cosmetics (for future use)
@export var unlocked_cosmetics: Array[String] = []
@export var purchased_cosmetics: Array[String] = []


func get_save_data() -> Dictionary:
	return {
		"steam_id": steam_id,
		"appearance": _get_appearance_save_data(),
		"reputation": reputation,
		"money": money,
		"unlocked_cosmetics": unlocked_cosmetics.duplicate(),
		"purchased_cosmetics": purchased_cosmetics.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	steam_id = int(data.get("steam_id", 0))
	reputation = int(data.get("reputation", 0))
	money = int(data.get("money", 0))

	unlocked_cosmetics.clear()
	for cosmetic: Variant in data.get("unlocked_cosmetics", []):
		unlocked_cosmetics.append(str(cosmetic))

	purchased_cosmetics.clear()
	for cosmetic: Variant in data.get("purchased_cosmetics", []):
		purchased_cosmetics.append(str(cosmetic))

	var appearance_dict: Dictionary = data.get("appearance", {})
	_load_appearance_save_data(appearance_dict)


func _get_appearance_save_data() -> Dictionary:
	return {
		"body_weight": appearance.body_weight,
		"skin_color": appearance.skin_color.to_html(),
		"pattern_color": appearance.pattern_color.to_html(),
		"pattern_index": appearance.pattern_index,
		"pupil_color": appearance.pupil_color.to_html(),
		"lips_use_skin_color": appearance.lips_use_skin_color,
		"lip_color": appearance.lip_color.to_html(),
		"eyelashes_enabled": appearance.eyelashes_enabled,
		"head_style": appearance.head_style,
		"top_style": appearance.top_style,
		"bottom_style": appearance.bottom_style,
		"feet_style": appearance.feet_style,
		"top_color": appearance.top_color,
		"bottom_color": appearance.bottom_color,
		"feet_color": appearance.feet_color,
		"sole_color": appearance.sole_color
	}


func _load_appearance_save_data(data: Dictionary) -> void:
	appearance = AlienAppearanceData.new()

	appearance.body_weight = float(data.get("body_weight", appearance.body_weight))
	appearance.skin_color = Color.html(str(data.get("skin_color", appearance.skin_color.to_html())))
	appearance.pattern_color = Color.html(str(data.get("pattern_color", appearance.pattern_color.to_html())))
	appearance.pattern_index = int(data.get("pattern_index", appearance.pattern_index))
	appearance.pupil_color = Color.html(str(data.get("pupil_color", appearance.pupil_color.to_html())))
	appearance.lips_use_skin_color = bool(data.get("lips_use_skin_color", appearance.lips_use_skin_color))
	appearance.lip_color = Color.html(str(data.get("lip_color", appearance.lip_color.to_html())))
	appearance.eyelashes_enabled = bool(data.get("eyelashes_enabled", appearance.eyelashes_enabled))
	appearance.head_style = int(data.get("head_style", appearance.head_style))
	appearance.top_style = int(data.get("top_style", appearance.top_style))
	appearance.bottom_style = int(data.get("bottom_style", appearance.bottom_style))
	appearance.feet_style = int(data.get("feet_style", appearance.feet_style))
	appearance.top_color = int(data.get("top_color", appearance.top_color))
	appearance.bottom_color = int(data.get("bottom_color", appearance.bottom_color))
	appearance.feet_color = int(data.get("feet_color", appearance.feet_color))
	appearance.sole_color = int(data.get("sole_color", appearance.sole_color))
