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
	if NetworkManager.steam_initialized:
		Steam.avatar_loaded.connect(_on_avatar_loaded)


func get_player_avatar(peer_id: int) -> Texture2D:
	if player_avatars.has(peer_id):
		return player_avatars[peer_id]

	if not NetworkManager.steam_initialized:
		return null

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
		"ready": false,
		"appearance": {}
	}
	
	# Check for single player
	if (
		peer_id == multiplayer.get_unique_id()
		and not NetworkManager.is_single_player
		and NetworkManager.steam_initialized
	):
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


func clear_players() -> void:
	players.clear()
	lobby_state_changed.emit()
	

func set_ready(peer_id: int, player_is_ready: bool) -> void:
	if not multiplayer.is_server():
		return

	if not players.has(peer_id):
		return

	players[peer_id]["ready"] = player_is_ready

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()

	sync_player_state.rpc(peer_id, player_is_ready)

	print(
		"LobbyManager: Player ",
		peer_id,
		" ready: ",
		player_is_ready
	)

	# Normal pregame lobby behavior remains unchanged.
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# Late joiners enter the active store only after clicking Ready.
	if not player_is_ready:
		return

	SpawnManager.spawn_ready_player(peer_id)


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
func sync_player_state(peer_id: int, player_is_ready: bool) -> void:
	if not players.has(peer_id):
		return

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

	if multiplayer.is_server():
		# Use the save-slot appearance for single-player,
		# and for the host continuing that save as multiplayer.
		var should_use_slot_appearance: bool = (
			NetworkManager.is_single_player
			or (
				peer_id == multiplayer.get_unique_id()
				and GameManager.game_start_mode
				== GameManager.GameStartMode.CONTINUE_GAME
			)
		)

		var restored_slot_appearance: bool = false

		if should_use_slot_appearance:
			var saved_appearance: Dictionary = (
				SaveManager.get_single_player_appearance()
			)

			if not saved_appearance.is_empty():
				players[peer_id]["appearance"] = (
					saved_appearance.duplicate(true)
				)

				sync_player_appearance.rpc(
					peer_id,
					saved_appearance
				)

				restored_slot_appearance = true

				print(
					"LOBBY PLAYER DATA: Restored save-slot appearance for peer ",
					peer_id
				)

		# If no slot appearance was available, or this is another
		# multiplayer player, use their normal Steam-ID record.
		if not restored_slot_appearance and not NetworkManager.is_single_player:
			var saved_player: PlayerData = SaveManager.get_player(steam_id)

			if saved_player == null:
				print(
					"LOBBY PLAYER DATA: NEW PLAYER | ",
					player_name,
					" | Player ID: ",
					steam_id
				)
			else:
				print(
					"LOBBY PLAYER DATA: RETURNING PLAYER | ",
					player_name,
					" | Player ID: ",
					steam_id
				)

				if saved_player.appearance != null:
					_set_player_appearance(
						peer_id,
						saved_player.appearance.to_dict()
					)

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


func get_saved_player(peer_id: int) -> PlayerData:
	if not multiplayer.is_server():
		return null

	var steam_id: int = get_player_steam_id(peer_id)

	return SaveManager.get_player(steam_id)


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


func get_player_appearance(peer_id: int) -> AlienAppearanceData:
	if not players.has(peer_id):
		return null

	var data: Dictionary = players[peer_id].get("appearance", {})

	if data.is_empty():
		return null

	return AlienAppearanceData.from_dict(data)


func request_set_appearance(appearance: AlienAppearanceData) -> void:
	if appearance == null:
		return

	var data: Dictionary = appearance.to_dict()

	if multiplayer.is_server():
		_set_player_appearance(multiplayer.get_unique_id(), data, true)
	else:
		request_appearance_change.rpc_id(1, data)

func _set_player_appearance(
		peer_id: int,
		data: Dictionary,
		save_to_disk: bool = false
	) -> void:
	if not multiplayer.is_server():
		return

	if not players.has(peer_id):
		return

	if players[peer_id]["ready"]:
		return

	var appearance: AlienAppearanceData = (
		AlienAppearanceData.from_dict(data)
	)

	var validated_data: Dictionary = appearance.to_dict()

	players[peer_id]["appearance"] = validated_data

	if NetworkManager.is_single_player:
		# Single-player: save against the selected save slot.
		SaveManager.set_single_player_appearance(validated_data)

		if save_to_disk:
			SaveManager.save_single_player_appearance(validated_data)
	else:
		# Multiplayer: retain the existing Steam-ID player records.
		var steam_id: int = get_player_steam_id(peer_id)
		var player_data: PlayerData = SaveManager.get_player(steam_id)

		if player_data == null:
			player_data = PlayerData.new()
			player_data.steam_id = steam_id
			SaveManager.add_player(player_data)

		player_data.appearance = (
			appearance.duplicate(true) as AlienAppearanceData
		)

		if save_to_disk:
			SaveManager.save_player_appearance(steam_id)

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()

	sync_player_appearance.rpc(peer_id, validated_data)


@rpc("any_peer", "reliable")
func request_appearance_change(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	_set_player_appearance(peer_id, data, true)


@rpc("authority", "reliable")
func sync_player_appearance(peer_id: int, data: Dictionary) -> void:
	if multiplayer.is_server():
		return

	if not players.has(peer_id):
		return

	players[peer_id]["appearance"] = data.duplicate(true)

	lobby_player_updated.emit(peer_id)
	lobby_state_changed.emit()
