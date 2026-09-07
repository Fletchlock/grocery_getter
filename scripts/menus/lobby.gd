extends Control

@onready var player_list: VBoxContainer = $PlayerList


func _ready() -> void:
	LobbyManager.lobby_player_added.connect(_on_player_changed)
	LobbyManager.lobby_player_removed.connect(_on_player_changed)
	LobbyManager.lobby_player_updated.connect(_on_player_changed)
	LobbyManager.lobby_state_changed.connect(_update_play_button)

	if multiplayer.multiplayer_peer == null:
		$PlayButton.hide()
	else:
		if not multiplayer.is_server():
			$PlayButton.hide()
		else:
			_update_play_button()

	if multiplayer.multiplayer_peer != null:
		_refresh_player_list()
	
	
func _on_player_changed(_peer_id: int) -> void:
	_refresh_player_list()
	
	
func _update_play_button() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server():
		return

	$PlayButton.disabled = not LobbyManager.all_players_ready()


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		if child.name != "Players":
			child.hide()

	var player_index := 0

	for peer_id in LobbyManager.get_players():
		if player_index >= 4:
			break

		var player_label := player_list.get_child(player_index + 1) as Label

		var ready_text := "Ready" if LobbyManager.is_ready(peer_id) else "Not Ready"
		player_label.text = "Player " + str(peer_id) + " - " + ready_text
		player_label.show()

		player_index += 1
		
		
func _on_play_button_pressed() -> void:
	if not multiplayer.is_server():
		return

	if not LobbyManager.all_players_ready():
		print("Cannot start: not all players are ready.")
		return

	GameManager.start_multiplayer_game()

func _on_ready_button_pressed() -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var new_ready_state := not LobbyManager.is_ready(my_peer_id)

	LobbyManager.request_set_ready(new_ready_state)
	
	$ReadyButton.text = "Unready" if new_ready_state else "Ready"


func _on_main_menu_button_pressed() -> void:
	print("Lobby: Returning to Main Menu")

	NetworkManager.disconnect_from_lobby()
	
	get_parent().get_parent().close_lobby()

	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
