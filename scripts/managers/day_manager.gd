extends Node

signal clock_updated(day: int, hour: int, minute: int)
signal day_started(day: int)

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
	
