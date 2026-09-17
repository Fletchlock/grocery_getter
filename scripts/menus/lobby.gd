extends Control

@onready var player_list: VBoxContainer = $CanvasLayer/PlayerList
@onready var play_button: Button = $CanvasLayer/PlayButton
@onready var ready_button: Button = $CanvasLayer/ReadyButton
@onready var main_menu_button: Button = $CanvasLayer/MainMenuButton

@onready var player_displays = [
	$SubViewportContainer/SubViewport/Player1,
	$SubViewportContainer/SubViewport/Player2,
	$SubViewportContainer/SubViewport/Player3,
	$SubViewportContainer/SubViewport/Player4	
]

@onready var player_name_labels: Array[Label3D] = [
	$SubViewportContainer/SubViewport/Player1/PlayerNameLabel,
	$SubViewportContainer/SubViewport/Player2/PlayerNameLabel,
	$SubViewportContainer/SubViewport/Player3/PlayerNameLabel,
	$SubViewportContainer/SubViewport/Player4/PlayerNameLabel
]


func _ready() -> void:
	LobbyManager.lobby_player_added.connect(_on_player_changed)
	LobbyManager.lobby_player_removed.connect(_on_player_changed)
	LobbyManager.lobby_player_updated.connect(_on_player_changed)
	LobbyManager.lobby_state_changed.connect(_update_play_button)
	LobbyManager.player_avatar_loaded.connect(_on_player_avatar_loaded)

	if multiplayer.multiplayer_peer == null:
		play_button.hide()
	else:
		if not multiplayer.is_server():
			play_button.hide()
		else:
			_update_play_button()

	if multiplayer.multiplayer_peer != null:
		_refresh_player_list()
	
	_update_character_displays()
	
func _on_player_changed(_peer_id: int) -> void:
	_refresh_player_list()
	_update_character_displays()
	
	
func _update_play_button() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server():
		return

	play_button.disabled = not LobbyManager.all_players_ready()


func _refresh_player_list() -> void:
	print("REFRESH PLAYER LIST")
	for child in player_list.get_children():
		if child.name != "Players":
			child.hide()

	var player_index := 0

	for peer_id in LobbyManager.get_players():
		print("REFRESHING PLAYER: ", peer_id)
		if player_index >= 4:
			break

		var player_label := player_list.get_child(player_index + 1) as Label
		var avatar: TextureRect = player_label.get_node("Avatar") as TextureRect

		var player_name := LobbyManager.get_player_name(peer_id)
		var ready_text := "Ready" if LobbyManager.is_ready(peer_id) else "Not Ready"

		player_label.text = player_name + " - " + ready_text
		player_label.show()
		
		var avatar_texture: Texture2D = LobbyManager.get_player_avatar(peer_id)

		if avatar_texture != null:
			avatar.texture = avatar_texture
			avatar.show()
		else:
			avatar.hide()
		
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
	ready_button.text = "Unready" if new_ready_state else "Ready"


func _on_main_menu_button_pressed() -> void:
	print("Lobby: Returning to Main Menu")

	await GameManager.leave_lobby()


func _on_red_button_pressed() -> void:
	LobbyManager.request_set_character("red")


func _on_green_button_pressed() -> void:
	LobbyManager.request_set_character("green")


func _on_blue_button_pressed() -> void:
	LobbyManager.request_set_character("blue")


func _update_character_displays() -> void:
	var players: Dictionary = LobbyManager.get_players()

	for i in range(4):
		var display: Node3D = player_displays[i]
		var name_label: Label3D = player_name_labels[i]

		# Player slots are 1-based, peer IDs are not necessarily 1-4.
		if i < players.size():
			var peer_id: int = players.keys()[i]
			
			display.visible = true
			name_label.visible = true
			name_label.text = LobbyManager.get_player_name(peer_id)
			
			if LobbyManager.is_ready(peer_id):
				name_label.modulate = Color(0.0, 0.997, 0.209)
			else:
				name_label.modulate = Color(1.0, 1.0, 1.0)
				
			display.set_character(LobbyManager.get_character(peer_id))
		else:
			display.visible = false
			name_label.visible = false


func _on_player_avatar_loaded(
	peer_id: int,
	avatar_texture: Texture2D
) -> void:
	var players: Dictionary = LobbyManager.get_players()

	var player_index: int = players.keys().find(peer_id)

	if player_index < 0 or player_index >= 4:
		return

	var player_label: Label = player_list.get_child(
		player_index + 1
	) as Label

	var avatar: TextureRect = player_label.get_node(
		"Avatar"
	) as TextureRect

	avatar.texture = avatar_texture
	avatar.show()
