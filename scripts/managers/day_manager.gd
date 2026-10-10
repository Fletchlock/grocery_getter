extends Node

signal clock_updated(day: int, hour: int, minute: int)
signal day_started(day: int)
signal punch_out_state_changed


const START_HOUR: int = 7
const STORE_CLOSE_HOUR: int = 22
const END_OF_DAY_HOUR: int = 24
const REAL_SECONDS_PER_GAME_MINUTE: float = 1.0

var current_day: int = 1
var current_hour: int = START_HOUR
var current_minute: int = 0

var clock_running: bool = false
var store_open: bool:
	get: return (current_hour >= 8 and current_hour < STORE_CLOSE_HOUR)
var rush_hour: bool: 
	get: return (current_hour >= 11 and current_hour <= 13) or (current_hour >= 16 and current_hour <= 18)



var _minute_timer: float = 0.0
var punched_out_players: Dictionary = {}
var _day_transition_started: bool = false

func _ready() -> void:
	if not LobbyManager.lobby_player_added.is_connected(_on_lobby_player_added):
		LobbyManager.lobby_player_added.connect(_on_lobby_player_added)

	if not LobbyManager.lobby_player_removed.is_connected(_on_lobby_player_removed):
		LobbyManager.lobby_player_removed.connect(_on_lobby_player_removed)

	if multiplayer.is_server():
		for peer_id: int in LobbyManager.get_players():
			punched_out_players[peer_id] = false

		_sync_punch_out_state.rpc(punched_out_players)


func _on_lobby_player_added(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	punched_out_players[peer_id] = false
	_sync_punch_out_state.rpc(punched_out_players)


func _on_lobby_player_removed(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	punched_out_players.erase(peer_id)
	_sync_punch_out_state.rpc(punched_out_players)


func set_player_punched_out(peer_id: int, punched_out: bool) -> void:
	if not multiplayer.is_server():
		return

	if not LobbyManager.get_players().has(peer_id):
		return

	punched_out_players[peer_id] = punched_out
	_sync_punch_out_state.rpc(punched_out_players)

	if punched_out and are_all_players_punched_out():
		_try_advance_day()


func is_player_punched_out(peer_id: int) -> bool:
	return punched_out_players.get(peer_id, false)


func are_all_players_punched_out() -> bool:
	var players: Dictionary = LobbyManager.get_players()

	if players.is_empty():
		return false

	for peer_id: int in players:
		if not is_player_punched_out(peer_id):
			return false

	return true


func _try_advance_day() -> void:
	if not multiplayer.is_server():
		return

	if _day_transition_started:
		return

	if not are_all_players_punched_out():
		return

	_day_transition_started = true
	_begin_next_day()


func _begin_next_day() -> void:
	if not multiplayer.is_server():
		return

	current_day += 1
	current_hour = START_HOUR
	current_minute = 0
	_minute_timer = 0.0
	clock_running = true

	for peer_id: int in LobbyManager.get_players():
		punched_out_players[peer_id] = false

	_sync_punch_out_state.rpc(punched_out_players)
	_sync_clock.rpc(current_day, current_hour, current_minute, clock_running)

	_day_transition_started = false
	day_started.emit(current_day)
	clock_updated.emit(current_day, current_hour, current_minute)


@rpc("authority", "call_local", "reliable")
func _sync_punch_out_state(state: Dictionary) -> void:
	punched_out_players = state.duplicate(true)
	punch_out_state_changed.emit()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
		
	if not clock_running:
		return
		
	_minute_timer += delta
	
	while _minute_timer >= REAL_SECONDS_PER_GAME_MINUTE:
		_minute_timer -= REAL_SECONDS_PER_GAME_MINUTE
		_advance_game_minute()
		
func start_day() -> void:
	if not multiplayer.is_server():
		return
		
	current_hour = START_HOUR
	current_minute = 0
	_minute_timer = 0.0
	clock_running = true
	
	_sync_clock.rpc(
		current_day,
		current_hour,
		current_minute, 
		clock_running
	)
	
	day_started.emit(current_day)
	clock_updated.emit(current_day, current_hour, current_minute)
	
func _advance_game_minute() -> void:
	current_minute += 1
	
	if current_minute >= 60:
		current_minute = 0
		current_hour += 1
		
	if current_hour >= END_OF_DAY_HOUR:
		current_hour = END_OF_DAY_HOUR
		current_minute = 0
		clock_running = false
	
	_sync_clock.rpc(
		current_day,
		current_hour,
		current_minute, 
		clock_running
	)
	
@rpc("authority", "call_local", "reliable")
func _sync_clock(
	day: int,
	hour: int,
	minute: int,
	running: bool
	) -> void:
	
	current_day = day
	current_hour = hour
	current_minute = minute
	clock_running = running
	
	clock_updated.emit(current_day, current_hour, current_minute)
	
