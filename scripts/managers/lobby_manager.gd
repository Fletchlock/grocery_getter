extends Node

signal lobby_player_added(peer_id: int)
signal lobby_player_removed(peer_id: int)

var players: Dictionary = {}


func add_player(peer_id: int) -> void:
	if players.has(peer_id):
		return

	players[peer_id] = {
		"peer_id": peer_id,
		"character": "",
		"ready": false
	}

	print("LobbyManager: Player added: ", peer_id)
	lobby_player_added.emit(peer_id)


func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	players.erase(peer_id)

	print("LobbyManager: Player removed: ", peer_id)
	lobby_player_removed.emit(peer_id)


func get_players() -> Dictionary:
	return players
	
	
func set_character(peer_id: int, character: String) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["character"] = character

	print(
		"LobbyManager: Player ",
		peer_id,
		" selected character: ",
		character
	)
	

func set_ready(peer_id: int, player_is_ready: bool) -> void:
	if not players.has(peer_id):
		return

	players[peer_id]["ready"] = player_is_ready

	print(
		"LobbyManager: Player ",
		peer_id,
		" ready: ",
		ready
	)


func get_character(peer_id: int) -> String:
	if not players.has(peer_id):
		return ""

	return players[peer_id]["character"]


func is_ready(peer_id: int) -> bool:
	if not players.has(peer_id):
		return false

	return players[peer_id]["ready"]
	
