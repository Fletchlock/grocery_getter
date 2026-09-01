extends Node

const MAIN_MENU := "res://scenes/menus/main_menu.tscn"

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	
	var menu_scene := load(MAIN_MENU) as PackedScene
	
	if menu_scene == null:
		push_error("Could not load main menu")
		return
		
	var menu := menu_scene.instantiate()
	$UI.add_child(menu)
