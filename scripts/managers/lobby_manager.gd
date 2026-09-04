extends Node

signal lobby_player_added(peer_id: int)
signal lobby_player_removed(peer_id: int)

var players: Dictionary = {}


func add_player(peer_id: int) -> void:
	if players.has(peer_id):
		return

	players[peer_id] = {
		"peer_id": peer_id
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
