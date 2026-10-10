
extends Node3D

@onready var display: Label3D = $Label3D


func _ready() -> void:
	if not DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.connect(_on_clock_updated)

	if not DayManager.punch_out_state_changed.is_connected(_on_punch_out_state_changed):
		DayManager.punch_out_state_changed.connect(_on_punch_out_state_changed)

	if not LobbyManager.lobby_state_changed.is_connected(_on_lobby_state_changed):
		LobbyManager.lobby_state_changed.connect(_on_lobby_state_changed)

	if not LobbyManager.lobby_player_removed.is_connected(_on_lobby_player_changed):
		LobbyManager.lobby_player_removed.connect(_on_lobby_player_changed)

	if not LobbyManager.lobby_player_added.is_connected(_on_lobby_player_changed):
		LobbyManager.lobby_player_added.connect(_on_lobby_player_changed)

	_refresh_display()


# --- Interaction ---

func get_interaction_prompt_for_player(_player: Node3D) -> String:
	var peer_id: int = multiplayer.get_unique_id()

	if DayManager.is_player_punched_out(peer_id):
		return "Already Punched Out"

	var reason: String = _get_punch_out_block_reason()
	if not reason.is_empty():
		return reason

	return "Punch Out"


func request_interact(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_try_punch_out(multiplayer.get_unique_id())
	else:
		_request_punch_out.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_punch_out() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_server_try_punch_out(sender_id)


func _server_try_punch_out(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not LobbyManager.get_players().has(peer_id):
		return

	if DayManager.is_player_punched_out(peer_id):
		return

	if not _get_punch_out_block_reason().is_empty():
		return

	DayManager.set_player_punched_out(peer_id, true)


func _get_punch_out_block_reason() -> String:
	if DayManager.current_hour < DayManager.STORE_CLOSE_HOUR:
		return "Store Is Still Open"

	if not get_tree().get_nodes_in_group("shopper_in_store").is_empty():
		return "Shoppers Still In Store"

	for order: OrderData in OrderManager.get_orders():
		if order.state == OrderData.OrderState.ACTIVE:
			return "Orders Still In Progress"

	return ""


# --- Display ---

func _on_clock_updated(_day: int, _hour: int, _minute: int) -> void:
	_refresh_display()


func _on_punch_out_state_changed() -> void:
	_refresh_display()


func _on_lobby_state_changed() -> void:
	_refresh_display()


func _on_lobby_player_changed(_peer_id: int) -> void:
	_refresh_display()


func _refresh_display() -> void:
	var day: int = DayManager.current_day
	var hour: int = DayManager.current_hour
	var minute: int = DayManager.current_minute

	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12

	var period: String = "AM" if hour < 12 else "PM"

	var lines: PackedStringArray = []
	lines.append("DAY %02d  |  %02d:%02d %s" % [
		day,
		display_hour,
		minute,
		period
	])

	lines.append("")

	var players: Dictionary = LobbyManager.get_players()
	var player_ids: Array = players.keys()
	player_ids.sort()

	for peer_id: int in player_ids:
		var player_name: String = LobbyManager.get_player_name(peer_id)

		if player_name.is_empty():
			player_name = "Player %s" % str(peer_id)

		var status: String = "OUT" if DayManager.is_player_punched_out(peer_id) else "IN"
		lines.append("%s: %s" % [player_name, status])

	display.text = "\n".join(lines)
