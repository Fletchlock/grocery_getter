extends Node

signal host_created
signal lobby_joined(lobby_id: int)
signal host_disconnected

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

var peer: SteamMultiplayerPeer
var current_lobby_id: int = 0


func _ready() -> void:
	
	Steam.initRelayNetworkAccess()
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func _process(_delta: float) -> void:

	Steam.run_callbacks()


func host_lobby() -> void:
	print("NetworkManager: Starting host process.")

	# Make sure any previous lobby/network connection is completely closed.
	if current_lobby_id != 0 or multiplayer.multiplayer_peer != null:
		print("NetworkManager: Cleaning up previous lobby before hosting.")
		await disconnect_from_lobby()

	# Create the new Steam lobby.
	print("NetworkManager: Creating new Steam lobby.")
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func _on_lobby_created(connected: int, lobby_id: int) -> void:

	if connected != Steam.RESULT_OK:
		print("Failed to create Steam lobby. Result: ", connect)
		return

	print("Steam lobby created: ", lobby_id)
	
	current_lobby_id = lobby_id

	if peer != null:
		print("NetworkManager: Existing peer found. Closing it.")
		peer.close()
		peer = null

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var error := peer.create_host()

	if error != OK:
		print("Failed to create Steam host. Error: ", error)
		peer = null
		return

	multiplayer.multiplayer_peer = peer

	# Host registers with the lobby
	var my_peer_id := multiplayer.get_unique_id()
	LobbyManager.add_player(my_peer_id)
	LobbyManager.set_player_name(my_peer_id, Steam.getFriendPersonaName(Steam.getSteamID()))
	
	debug_lobby_members()
	
	print("NetworkManager: Host peer status: ", peer.get_connection_status())
	print("NetworkManager: Host Steam ID: ", Steam.getSteamID())
	
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
	
	current_lobby_id = lobby_id

	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		return

	var host_steam_id := Steam.getLobbyOwner(lobby_id)

	print("NetworkManager: Lobby owner Steam ID: ", host_steam_id)
	print("NetworkManager: My Steam ID: ", Steam.getSteamID())

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var client_result := peer.create_client(host_steam_id)

	print("NetworkManager: create_client result: ", client_result)
	print("NetworkManager: Peer status after create_client: ", peer.get_connection_status())

	multiplayer.multiplayer_peer = peer

	print("NetworkManager: Client peer status after assignment: ", peer.get_connection_status())
	print("NetworkManager: Multiplayer peer assigned.")
	print("NetworkManager: My multiplayer ID: ", multiplayer.get_unique_id())

	debug_lobby_members()

	lobby_joined.emit(lobby_id)


func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	print("STEAM INVITE RECEIVED! Lobby ID: ", lobby_id)
	Steam.joinLobby(lobby_id)


func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: ", peer_id)
	LobbyManager.add_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected: ", peer_id)

	LobbyManager.remove_player(peer_id)
	SpawnManager.remove_player(peer_id)
	
	#Peer 1 is always the host.
	if peer_id == 1 and not multiplayer.is_server():
		print("NewtorkManager: Host Disconnected!")
		host_disconnected.emit()


func _on_lobby_chat_update(
	_lobby_id: int,
	_changed_id: int,
	_making_change_id: int,
	_chat_state: int
) -> void:
	pass


func _on_connected_to_server() -> void:
	print("NetworkManager: CONNECTED TO SERVER!")
	print("NetworkManager: My peer ID: ", multiplayer.get_unique_id())

	var my_peer_id := multiplayer.get_unique_id()

	LobbyManager.add_player(my_peer_id)

	var my_name := Steam.getFriendPersonaName(Steam.getSteamID())
	LobbyManager.request_set_player_name.rpc_id(1, my_name)


func _on_connection_failed() -> void:
	print("NetworkManager: CONNECTION FAILED!")


func disconnect_from_lobby() -> void:
	print("NetworkManager: Disconnecting from lobby")

	if multiplayer.multiplayer_peer != null:
		print(
			"NetworkManager: Peer status before close: ",
			multiplayer.multiplayer_peer.get_connection_status()
		)

		var old_peer = multiplayer.multiplayer_peer

		old_peer.close()
		
		print(
			"NetworkManager: Peer status after close: ",
			old_peer.get_connection_status()
			)

		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		print("NetworkManager: Multiplayer peer replaced with OfflineMultiplayerPeer")
		peer = null
		old_peer = null

	if current_lobby_id != 0:
		Steam.leaveLobby(current_lobby_id)
		print("Steam lobby removed: ", current_lobby_id)
		current_lobby_id = 0

	# Give Steam a frame to finish releasing the networking socket.
	await get_tree().process_frame


func debug_lobby_members() -> void:
	print("=== STEAM LOBBY MEMBERS ===")

	var member_count := Steam.getNumLobbyMembers(current_lobby_id)

	for i in range(member_count):
		var steam_id := Steam.getLobbyMemberByIndex(current_lobby_id, i)
		var player_name := Steam.getFriendPersonaName(steam_id)

		print(
			"Member ",
			i,
			": Steam ID = ",
			steam_id,
			" Name = ",
			player_name
		)
