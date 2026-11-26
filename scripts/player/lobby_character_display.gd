extends Node3D

@onready var alien_appearance: AlienAppearance = $AlienCharacter/AlienAppearance


func set_appearance(data: AlienAppearanceData) -> void:
	if data == null:
		return

	alien_appearance.apply_appearance(data)
