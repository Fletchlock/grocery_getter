
extends Node

signal synchronized

const SERVER_PEER_ID: int = 1
const SYNC_INTERVAL: float = 3.0
const REQUEST_TIMEOUT: float = 2.0
const OFFSET_SMOOTHING: float = 0.2

var is_synchronized: bool = false
var round_trip_time_ms: float = 0.0
var clock_offset_ms: float = 0.0

var _clock_offset: float = 0.0
var _sync_timer: float = 0.0
var _request_sequence: int = 0
var _pending_sequence: int = -1
var _pending_sent_time: float = 0.0

var _debug_timer: float = 0.0

func _ready() -> void:
	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)

	multiplayer.server_disconnected.connect(
		_on_server_disconnected
	)


func _process(delta: float) -> void:
	_debug_timer += delta

	if _debug_timer >= 5.0:
		_debug_timer = 0.0

		if not multiplayer.is_server():
			print(
				"NETWORK CLOCK | Synced: ", is_synchronized,
				" | RTT: ", snappedf(round_trip_time_ms, 0.1), "ms",
				" | Offset: ", snappedf(clock_offset_ms, 0.1), "ms",
				" | Time: ", snappedf(get_time(), 0.001)
			)
	if multiplayer.is_server():
		return

	if multiplayer.get_unique_id() <= SERVER_PEER_ID:
		return

	var now: float = _local_time()

	# Allow a lost synchronization request to time out.
	if _pending_sequence >= 0:
		if now - _pending_sent_time >= REQUEST_TIMEOUT:
			_pending_sequence = -1

	_sync_timer -= delta

	if _sync_timer > 0.0:
		return

	if _pending_sequence >= 0:
		return

	_sync_timer = SYNC_INTERVAL
	_request_time_sync()


func get_time() -> float:
	var local_time: float = _local_time()

	if multiplayer.is_server():
		return local_time

	return local_time + _clock_offset


func get_time_usec() -> int:
	return roundi(get_time() * 1000000.0)


func has_valid_time() -> bool:
	return multiplayer.is_server() or is_synchronized


func _local_time() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _request_time_sync() -> void:
	_request_sequence += 1
	_pending_sequence = _request_sequence
	_pending_sent_time = _local_time()

	_receive_time_request.rpc_id(
		SERVER_PEER_ID,
		_pending_sequence,
		_pending_sent_time
	)


@rpc("any_peer", "call_remote", "unreliable")
func _receive_time_request(
	sequence: int,
	client_sent_time: float
) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	if sender_id <= SERVER_PEER_ID:
		return

	var host_time: float = _local_time()

	_receive_time_response.rpc_id(
		sender_id,
		sequence,
		client_sent_time,
		host_time
	)


@rpc("authority", "call_remote", "unreliable")
func _receive_time_response(
	sequence: int,
	client_sent_time: float,
	host_time: float
) -> void:
	if multiplayer.is_server():
		return

	if sequence != _pending_sequence:
		return

	_pending_sequence = -1

	var client_received_time: float = _local_time()
	var rtt: float = client_received_time - client_sent_time

	if rtt < 0.0:
		return

	# Estimate host time at the midpoint of the exchange.
	var client_midpoint: float = (
		client_sent_time + client_received_time
	) * 0.5

	var measured_offset: float = host_time - client_midpoint

	round_trip_time_ms = rtt * 1000.0

	if not is_synchronized:
		_clock_offset = measured_offset
		is_synchronized = true
		synchronized.emit()
	else:
		_clock_offset = lerpf(
			_clock_offset,
			measured_offset,
			OFFSET_SMOOTHING
		)

	clock_offset_ms = _clock_offset * 1000.0


func _on_connected_to_server() -> void:
	_reset_clock()
	_sync_timer = 0.0


func _on_server_disconnected() -> void:
	_reset_clock()


func _reset_clock() -> void:
	is_synchronized = false
	round_trip_time_ms = 0.0
	clock_offset_ms = 0.0

	_clock_offset = 0.0
	_sync_timer = 0.0
	_pending_sequence = -1
	_pending_sent_time = 0.0
