extends Node

signal lobby_player_added(peer_id: int)
signal lobby_player_removed(peer_id: int)
signal lobby_player_updated(peer_id: int)
signal lobby_state_changed
signal player_avatar_loaded(peer_id: int, texture: Texture2D)

var players: Dictionary = {}
var player_avatars: Dictionary = {}
var avatar_requests: Dictionary = {}


func _ready() -> void:
	Steam.avatar_loaded.connect(_on_avatar_loaded)


func get_player_avatar(peer_id: int) -> Texture2D:
	if player_avatars.has(peer_id):
		return player_avatars[peer_id]

	if avatar_requests.has(peer_id):
		return null

	var steam_id: int = get_player_steam_id(peer_id)

	if steam_id == 0:
		return null

	print(
		"REQUESTING AVATAR: Peer ",
		peer_id,
		" -> Steam ID ",
		steam_id
	)

	avatar_requests[peer_id] = steam_id

	Steam.getPlayerAvatar(
		Steam.AVATAR_MEDIUM,
		steam_id
	)

	return null


func _on_avatar_loaded(
	user_id: int,
	avatar_size: int,
	avatar_buffer: PackedByteArray
) -> void:
	print(
		"AVATAR LOADED: ",
		user_id,
		" SIZE: ",
		avatar_size,
		" BUFFER: ",
		avatar_buffer.size()
	)

	if avatar_buffer.is_empty():
		return

	var avatar_image: Image = Image.create_from_data(
		avatar_size,
		avatar_size,
		false,
		Image.FORMAT_RGBA8,
		avatar_buffer
	)

	var avatar_texture: ImageTexture = ImageTexture.create_from_image(
		avatar_image
	)

	for peer_id in avatar_requests:
		var requested_steam_id: int = avatar_requests[peer_id]

		if requested_steam_id == user_id:
			player_avatars[peer_id] = avatar_texture
			avatar_requests.erase(peer_id)

			player_avatar_loaded.emit(
				peer_id,
				avatar_texture
			)

			return

func add_player(peer_id: int) -> void:
	if players.has(peer_id):
		return

	players[peer_id] = {
		"peer_id": peer_id,
		"name": "",
		"steam_id": 0,
		"character": "red",
		"ready": false
	}

	if peer_id == multiplayer.get_unique_id():
		players[peer_id]["steam_id"] = Steam.getSteamID()

	print("LobbyManager: Player added: ", peer_id)

	lobby_player_added.emit(peer_id)
	lobby_state_changed.emit()

	# Host sends the complete lobby state to the newly connected player.
	if multiplayer.is_server() and peer_id != multiplayer.get_unique_id():
		sync_lobby_state.rpc_id(peer_id, players)


func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	players.erase(peer_id)

	print("LobbyManager: Player removed: ", peer_id)
	lobby_player_removed.emit(peer_id)


func get_players() -> Dictionary:
	return players


#func get_player_name(peer_id: int) -> String:
	#return Steam.getFriendPersonaName(peer_id)
	
	
func set_character(peer_id: int, character: String) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["character"] = character
	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()
	
	if multiplayer.is_server():
		sync_player_state.rpc(peer_id, character, players[peer_id]["ready"])

	print(
		"LobbyManager: Player ",
		peer_id,
		" selected character: ",
		character
	)


func clear_players() -> void:
	players.clear()
	lobby_state_changed.emit()
	

func set_ready(peer_id: int, player_is_ready: bool) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["ready"] = player_is_ready
	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()
	
	if multiplayer.is_server():
		sync_player_state.rpc(peer_id, players[peer_id]["character"], player_is_ready)

	print(
		"LobbyManager: Player ",
		peer_id,
		" ready: ",
		player_is_ready
	)


func get_character(peer_id: int) -> String:
	if not players.has(peer_id):
		return ""

	return players[peer_id]["character"]


func is_ready(peer_id: int) -> bool:
	if not players.has(peer_id):
		return false

	return players[peer_id]["ready"]

# Called when the Host clicks Play from the lobby. The GameManager starts the game.
func all_players_ready() -> bool:
	if players.is_empty():
		return false
		
	for player in players.values():
		if not player["ready"]:
			return false
			
	return true
	
# RPC Section **********

#Host request character change (Select Character in Lobby UI)
@rpc("any_peer", "reliable")
func request_character_change(character: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	set_character(peer_id, character)


#Client request Host character change
func request_set_character(character: String) -> void:
	if multiplayer.is_server():
		set_character(multiplayer.get_unique_id(), character)
		return

	request_character_change.rpc_id(1, character)
	
	
# Host request ready change (Ready up in lobby UI)
@rpc("any_peer", "reliable")
func request_ready_change(player_is_ready: bool) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	set_ready(peer_id, player_is_ready)
	

# Client request the Host change ready via rpc
func request_set_ready(player_is_ready: bool) -> void:
	if multiplayer.is_server():
		set_ready(multiplayer.get_unique_id(), player_is_ready)
		return
		
	request_ready_change.rpc_id(1, player_is_ready)


# Host will call to have players receive the requested changes in state.
@rpc("authority", "reliable")
func sync_player_state(peer_id: int, character: String, player_is_ready: bool) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["character"] = character
	players[peer_id]["ready"] = player_is_ready

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()


@rpc("authority", "reliable")
func sync_lobby_state(player_state: Dictionary) -> void:
	if multiplayer.is_server():
		return

	players = player_state.duplicate(true)

	print("LobbyManager: Received lobby state from host.")

	for peer_id in players:
		lobby_player_updated.emit(peer_id)

	lobby_state_changed.emit()


func set_player_name(
	peer_id: int,
	player_name: String,
	steam_id: int
) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["name"] = player_name
	players[peer_id]["steam_id"] = steam_id

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()

	if multiplayer.is_server():
		sync_player_info.rpc(peer_id, player_name, steam_id)

	print(
		"LobbyManager: Player ",
		peer_id,
		" Name: ",
		player_name,
		" Steam ID: ",
		steam_id
	)


func get_player_name(peer_id: int) -> String:
	if not players.has(peer_id):
		return ""

	return players[peer_id]["name"]


func get_player_steam_id(peer_id: int) -> int:
	if not players.has(peer_id):
		return 0

	return players[peer_id]["steam_id"]


@rpc("any_peer", "reliable")
func request_set_player_name(
	player_name: String,
	steam_id: int
) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	set_player_name(peer_id, player_name, steam_id)


@rpc("authority", "reliable")
func sync_player_info(
	peer_id: int,
	player_name: String,
	steam_id: int
) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["name"] = player_name
	players[peer_id]["steam_id"] = steam_id

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()
