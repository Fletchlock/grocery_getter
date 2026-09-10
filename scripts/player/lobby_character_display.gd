extends Node3D

@onready var character_blue: MeshInstance3D = $Armature/Skeleton3D/character_blue
@onready var character_blue_hat: MeshInstance3D = $Armature/Skeleton3D/character_blue_hat
@onready var character_green: MeshInstance3D = $Armature/Skeleton3D/character_green
@onready var character_green_hat: MeshInstance3D = $Armature/Skeleton3D/character_green__hat
@onready var character_red: MeshInstance3D = $Armature/Skeleton3D/character_red
@onready var character_red_hat: MeshInstance3D = $Armature/Skeleton3D/character_red_hat


func _ready() -> void:
	set_character("red")


func set_character(character: String) -> void:
	character_blue.visible = false
	character_blue_hat.visible = false
	character_green.visible = false
	character_green_hat.visible = false
	character_red.visible = false
	character_red_hat.visible = false

	match character:
		"red":
			character_red.visible = true
			character_red_hat.visible = true

		"green":
			character_green.visible = true
			character_green_hat.visible = true

		"blue":
			character_blue.visible = true
			character_blue_hat.visible = true
