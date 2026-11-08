extends Control

@onready var player_list: VBoxContainer = $CanvasLayer/PlayerList

@onready var play_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/PlayButton
@onready var ready_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/ReadyButton
@onready var main_menu_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/MainMenuButton
@onready var invite_friends_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/InviteFriendsButton

@onready var red_button: Button = $VBoxContainer/CharacterSelection/RedButton
@onready var green_button: Button = $VBoxContainer/CharacterSelection/GreenButton
@onready var blue_button: Button = $VBoxContainer/CharacterSelection/BlueButton

@onready var lobby_viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var lobby_camera: Camera3D = $SubViewportContainer/SubViewport/Camera3D

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LobbyManager.lobby_player_added.connect(_on_player_changed)
	LobbyManager.lobby_player_removed.connect(_on_player_changed)
	LobbyManager.lobby_player_updated.connect(_on_player_changed)
	LobbyManager.lobby_state_changed.connect(_update_play_button)
	LobbyManager.player_avatar_loaded.connect(_on_player_avatar_loaded)
	NetworkManager.host_created.connect(_update_invite_button)
	NetworkManager.lobby_joined.connect(_on_network_lobby_joined)
		
	invite_friends_button.pressed.connect(_on_invite_friends_button_pressed)
	
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
	_update_ready_button()
	lobby_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	lobby_camera.make_current()
	_setup_lobby_focus()
	ready_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if event.is_echo():
		return

	get_viewport().set_input_as_handled()
	_on_main_menu_button_pressed()


func _on_player_changed(_peer_id: int) -> void:
	_refresh_player_list()
	_update_character_displays()
	_update_ready_button()


func _update_play_button() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server():
		return

	play_button.disabled = not LobbyManager.all_players_ready()

	_setup_lobby_focus()

	if play_button.disabled and play_button.has_focus():
		ready_button.grab_focus.call_deferred()


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


func _get_primary_action_button() -> Button:
	if play_button.visible and not play_button.disabled:
		return play_button

	return ready_button


func _focus_primary_action() -> void:
	_get_primary_action_button().grab_focus.call_deferred()


func _focus_first_character() -> void:
	for button: Button in [red_button, green_button, blue_button]:
		if not button.disabled:
			button.grab_focus.call_deferred()
			return

	_focus_primary_action()


func _setup_lobby_focus() -> void:
	var buttons: Array[Button] = [
		play_button,
		ready_button,
		invite_friends_button,
		main_menu_button,
		red_button,
		green_button,
		blue_button
	]

	for button: Button in buttons:
		button.focus_mode = (
			Control.FOCUS_NONE if button.disabled
			else Control.FOCUS_ALL
		)

	# Clear any existing manual focus neighbours.
	for button: Button in buttons:
		button.focus_neighbor_top = NodePath("")
		button.focus_neighbor_bottom = NodePath("")
		button.focus_neighbor_left = NodePath("")
		button.focus_neighbor_right = NodePath("")

	# Character selection: horizontal movement only.
	red_button.focus_neighbor_right = red_button.get_path_to(green_button)
	green_button.focus_neighbor_left = green_button.get_path_to(red_button)
	green_button.focus_neighbor_right = green_button.get_path_to(blue_button)
	blue_button.focus_neighbor_left = blue_button.get_path_to(green_button)

	# Character selection returns to the primary action.
	for button: Button in [red_button, green_button, blue_button]:
		button.focus_neighbor_bottom = button.get_path_to(_get_primary_action_button())

	# Up from Ready or Play enters character selection at Alex.
	if play_button.visible and not play_button.disabled:
		ready_button.focus_neighbor_top = ready_button.get_path_to(play_button)
	else:
		ready_button.focus_neighbor_top = ready_button.get_path_to(red_button)

	play_button.focus_neighbor_top = play_button.get_path_to(red_button)
		
		
func _on_play_button_pressed() -> void:
	if not multiplayer.is_server():
		return

	if not LobbyManager.all_players_ready():
		print("Cannot start: not all players are ready.")
		return

	GameManager.start_game()

func _on_ready_button_pressed() -> void:
	var my_peer_id: int = multiplayer.get_unique_id()
	var new_ready_state: bool = not LobbyManager.is_ready(my_peer_id)

	LobbyManager.request_set_ready(new_ready_state)


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


func _is_late_join_waiting() -> bool:
	return GameManager.current_state == GameManager.GameState.LATE_JOIN_WAITING


func _update_ready_button() -> void:
	var peer_id: int = multiplayer.get_unique_id()
	var is_ready: bool = LobbyManager.is_ready(peer_id)
	var selection_locked: bool = is_ready and _is_late_join_waiting()

	ready_button.text = "Unready" if is_ready else "Ready"
	ready_button.disabled = selection_locked

	red_button.disabled = selection_locked
	green_button.disabled = selection_locked
	blue_button.disabled = selection_locked
	_setup_lobby_focus()


func _update_invite_button() -> void:
	invite_friends_button.visible = (
		multiplayer.is_server()
		and NetworkManager.peer != null
		and NetworkManager.current_lobby_id != 0
	)


func _on_network_lobby_joined(_lobby_id: int) -> void:
	_update_invite_button()


func _on_invite_friends_button_pressed() -> void:
	var lobby_id: int = NetworkManager.current_lobby_id

	if lobby_id == 0:
		print("Lobby: No Steam lobby available for invitations.")
		return

	print("Lobby: Opening Steam invitation overlay.")

	Steam.activateGameOverlayInviteDialog(lobby_id)
