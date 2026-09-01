extends Node

const MAIN_MENU := "res://scenes/menus/main_menu.tscn"
const PAUSE_MENU := "res://scenes/menus/pause_menu.tscn"

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	
	var menu_scene := load(MAIN_MENU) as PackedScene
	
	if menu_scene == null:
		push_error("Could not load main menu")
		return
		
	var menu := menu_scene.instantiate()
	$UI.add_child(menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameManager.current_state == GameManager.GameState.PLAYING:
			_open_pause_menu()
			

func _open_pause_menu() -> void:
	var pause_scene := load(PAUSE_MENU) as PackedScene
	
	if pause_scene == null:
		push_error("Could not load pause menu")
		return
		
	var pause_menu := pause_scene.instantiate()
	
	$UI.add_child(pause_menu)
	
	GameManager.set_game_state(GameManager.GameState.PAUSED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
