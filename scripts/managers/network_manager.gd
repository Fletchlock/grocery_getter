extends Node

signal host_created
signal lobby_joined(lobby_id: int)

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

var peer: SteamMultiplayerPeer


func _ready() -> void:
	
	Steam.initRelayNetworkAccess()
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	
	multiplayer.peer_connected.connect(_on_peer_connected)


func _process(_delta: float) -> void:

	Steam.run_callbacks()


func host_lobby() -> void:

	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func _on_lobby_created(connected: int, lobby_id: int) -> void:

	if connected != Steam.RESULT_OK:
		print("Failed to create Steam lobby. Result: ", connect)
		return

	print("Steam lobby created: ", lobby_id)
	peer = SteamMultiplayerPeer.new()
	
	print("SteamMultiplayerPeer methods:")
	for method in peer.get_method_list():
		print(method.name)

	
	peer.server_relay = true
	peer.create_host()
	multiplayer.multiplayer_peer = peer
	#Host registers with the lobby
	LobbyManager.add_player(multiplayer.get_unique_id())
	host_created.emit()


func _on_lobby_joined(
	lobby_id: int,
	_permission: int,
	_locked: bool,
	response: int
) -> void:

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Failed to join Steam lobby. Response: ", response)
		return

	print("Joined Steam lobby: ", lobby_id)

	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		return

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer
	lobby_joined.emit(lobby_id)


func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	Steam.joinLobby(lobby_id)


func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: ", peer_id)
	LobbyManager.add_player(peer_id)


func _on_lobby_chat_update(
	_lobby_id: int,
	changed_id: int,
	_making_change_id: int,
	chat_state: int
) -> void:
	print("NEW CALLBACK RUNNING")
	print("Steam ID: ", changed_id)
	print("Chat state: ", chat_state)

	if chat_state == 2 and peer != null:
		var peer_id: int = peer.get_peer_id_for_steam_id(changed_id)

		print("Converted Steam ID ", changed_id, " to Peer ID ", peer_id)
