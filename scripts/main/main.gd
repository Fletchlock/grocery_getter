extends Node

const MAIN_MENU := "res://scenes/menus/main_menu.tscn"
const LOBBY := "res://scenes/menus/lobby.tscn"
const PAUSE_MENU := "res://scenes/menus/pause_menu.tscn"

var main_menu: Control
var lobby: Control
var lobby_browser: Control

func _ready() -> void:
	
	GameManager.game_state_changed.connect(_on_game_state_changed)

	var menu_scene := load(MAIN_MENU) as PackedScene

	if menu_scene == null:
		push_error("Could not load main menu")
		return

	main_menu = menu_scene.instantiate() as Control
	$UI.add_child(main_menu)

	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	print("MAIN: Game state changed to: ", new_state)

	if new_state == GameManager.GameState.MAIN_MENU:
		print("MAIN: Returning to main menu.")
		
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		if is_instance_valid(lobby):
			lobby.queue_free()
			lobby = null

		if not is_instance_valid(main_menu):
			var menu_scene := load(MAIN_MENU) as PackedScene

			if menu_scene == null:
				push_error("Could not load main menu")
				return

			main_menu = menu_scene.instantiate() as Control
			$UI.add_child(main_menu)

		main_menu.show()

	if new_state == GameManager.GameState.LOBBY:
		print("MAIN: Opening lobby")

		if is_instance_valid(main_menu):
			print("MAIN: Hiding main menu")
			main_menu.hide()

		if not is_instance_valid(lobby):
			open_lobby()

	if new_state == GameManager.GameState.PLAYING:
		if is_instance_valid(main_menu):
			print("MAIN: Removing main menu")
			main_menu.queue_free()
			main_menu = null

		if is_instance_valid(lobby):
			print("MAIN: Removing lobby")
			lobby.queue_free()
			lobby = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		if GameManager.current_state == GameManager.GameState.PLAYING:
			_open_pause_menu()
		elif GameManager.current_state == GameManager.GameState.PAUSED:
			_close_pause_menu()
			

func _open_pause_menu() -> void:
	var pause_scene := load(PAUSE_MENU) as PackedScene
	
	if pause_scene == null:
		push_error("Could not load pause menu")
		return
		
	var pause_menu := pause_scene.instantiate()
	
	$UI.add_child(pause_menu)
	
	GameManager.set_game_state(GameManager.GameState.PAUSED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#get_tree().paused = true


func _close_pause_menu() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	#get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pause_menu = get_node("UI/PauseMenu")
	pause_menu.queue_free()


func open_lobby() -> void:

	var lobby_scene := load(LOBBY) as PackedScene

	if lobby_scene == null:

		push_error("Could not load lobby")

		return

	lobby = lobby_scene.instantiate() as Control
	$UI.add_child(lobby)


func close_lobby() -> void:
	if is_instance_valid(lobby):
		print("MAIN: Removing lobby")
		lobby.queue_free()
		lobby = null

	if is_instance_valid(main_menu):
		print("MAIN: Showing main menu")
		main_menu.show()


func open_lobby_browser() -> void:
	var browser_scene := load("res://scenes/menus/lobby_browser.tscn") as PackedScene

	if browser_scene == null:
		push_error("Could not load lobby browser")
		return

	lobby_browser = browser_scene.instantiate() as Control
	$UI.add_child(lobby_browser)

	main_menu.hide()
