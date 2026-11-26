extends Control

@onready var player_list: VBoxContainer = $CanvasLayer/PlayerList

@onready var play_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/PlayButton
@onready var ready_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/ReadyButton
@onready var main_menu_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/MainMenuButton
@onready var customize_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/CustomizeButton

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

const ALIEN_PREVIEW_SCENE: PackedScene = preload(
	"res://scenes/menus/alien_preview.tscn"
)

var customization_scene: Node3D = null
var hidden_lobby_3d_nodes: Array[Node3D] = []
var local_alien_appearance: AlienAppearanceData = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LobbyManager.lobby_player_added.connect(_on_player_changed)
	LobbyManager.lobby_player_removed.connect(_on_player_changed)
	LobbyManager.lobby_player_updated.connect(_on_player_changed)
	LobbyManager.lobby_state_changed.connect(_update_play_button)
	LobbyManager.player_avatar_loaded.connect(_on_player_avatar_loaded)
	NetworkManager.lobby_joined.connect(_on_network_lobby_joined)

	
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
	if customization_scene != null:
		return
	
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
	_ensure_lobby_focus()


func _update_play_button() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server():
		return

	play_button.disabled = not LobbyManager.all_players_ready()

	_setup_lobby_focus()

	if play_button.disabled and play_button.has_focus():
		ready_button.grab_focus.call_deferred()
		
	_ensure_lobby_focus()


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


func _setup_lobby_focus() -> void:
	var buttons: Array[Button] = [
		play_button,
		ready_button,
		customize_button,
		main_menu_button
	]

	var available_buttons: Array[Button] = []

	for button: Button in buttons:
		button.focus_neighbor_top = NodePath("")
		button.focus_neighbor_bottom = NodePath("")
		button.focus_neighbor_left = NodePath("")
		button.focus_neighbor_right = NodePath("")

		if button.disabled or not button.visible:
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.focus_mode = Control.FOCUS_ALL
			available_buttons.append(button)

	for i: int in range(available_buttons.size()):
		var button: Button = available_buttons[i]

		if i > 0:
			button.focus_neighbor_top = button.get_path_to(
				available_buttons[i - 1]
			)

		if i < available_buttons.size() - 1:
			button.focus_neighbor_bottom = button.get_path_to(
				available_buttons[i + 1]
			)
		
		
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
				
			var appearance: AlienAppearanceData = LobbyManager.get_player_appearance(peer_id)

			if appearance != null:
				display.set_appearance(appearance)
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

	ready_button.text = "Unready" if is_ready else "Ready"
	ready_button.disabled = is_ready and _is_late_join_waiting()

	customize_button.disabled = is_ready

	_setup_lobby_focus()


func _ensure_lobby_focus() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return

	var focused_control: Control = get_viewport().gui_get_focus_owner()

	if focused_control != null:
		return

	_focus_primary_action()


func _on_network_lobby_joined(_lobby_id: int) -> void:
	pass


func _on_invite_friends_button_pressed() -> void:
	var lobby_id: int = NetworkManager.current_lobby_id

	if lobby_id == 0:
		print("Lobby: No Steam lobby available for invitations.")
		return

	print("Lobby: Opening Steam invitation overlay.")

	Steam.activateGameOverlayInviteDialog(lobby_id)


func _on_customize_button_pressed() -> void:
	var peer_id: int = multiplayer.get_unique_id()

	if LobbyManager.is_ready(peer_id):
		return

	if customization_scene != null:
		return

	customization_scene = ALIEN_PREVIEW_SCENE.instantiate() as Node3D

	if customization_scene == null:
		push_error("LOBBY: Failed to instantiate alien customization.")
		return
		
	var current_appearance: AlienAppearanceData = LobbyManager.get_player_appearance(peer_id)

	if current_appearance != null:
		customization_scene.initial_appearance = current_appearance.duplicate(true)
		
	customization_scene.customization_confirmed.connect(
		_on_customization_confirmed
	)
	customization_scene.customization_cancelled.connect(
		_on_customization_cancelled
	)

	_hide_lobby_3d()

	get_tree().root.add_child(customization_scene)

	hide()
	$CanvasLayer.hide()
	$SubViewportContainer.hide()

	print("LOBBY: Alien customization opened.")


func _on_customization_confirmed(appearance: AlienAppearanceData) -> void:
	print(
		"LOBBY: Alien confirmed | Skin: ",
		appearance.skin_color.to_html(),
		" | Weight: ",
		appearance.body_weight
	)
	
	local_alien_appearance = appearance.duplicate(true) as AlienAppearanceData
	LobbyManager.request_set_appearance(local_alien_appearance)

	
	var display: Node3D = _get_local_player_display()

	if display != null:
		display.set_appearance(local_alien_appearance)
	else:
		push_warning("LOBBY: Could not find local player display.")

	
	if customization_scene != null:
		customization_scene.queue_free()
		customization_scene = null

	_restore_lobby_3d()

	show()
	$CanvasLayer.show()
	$SubViewportContainer.show()

	_update_ready_button()
	_focus_primary_action()


func _on_customization_cancelled() -> void:
	if customization_scene != null:
		customization_scene.queue_free()
		customization_scene = null

	_restore_lobby_3d()

	show()
	$CanvasLayer.show()
	$SubViewportContainer.show()

	_update_ready_button()
	customize_button.grab_focus.call_deferred()


func _hide_lobby_3d() -> void:
	hidden_lobby_3d_nodes.clear()

	for child: Node in get_children():
		if child is Node3D:
			var node_3d: Node3D = child as Node3D

			if node_3d.visible:
				node_3d.hide()
				hidden_lobby_3d_nodes.append(node_3d)


func _restore_lobby_3d() -> void:
	for node_3d: Node3D in hidden_lobby_3d_nodes:
		if is_instance_valid(node_3d):
			node_3d.show()

	hidden_lobby_3d_nodes.clear()


func _get_local_player_display() -> Node3D:
	var peer_id: int = multiplayer.get_unique_id()
	var players: Dictionary = LobbyManager.get_players()
	var player_index: int = players.keys().find(peer_id)

	if player_index < 0 or player_index >= player_displays.size():
		return null

	return player_displays[player_index]
