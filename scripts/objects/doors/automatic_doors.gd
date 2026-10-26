
extends Node3D
class_name AutomaticDoors


@export var close_delay: float = 1.5

@onready var detection_area: Area3D = $DetectionArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var door_audio: AudioStreamPlayer3D = $DoorAudio


var bodies_inside: Array[Node3D] = []
var doors_open: bool = false
var close_timer: Timer


func _ready() -> void:
	close_timer = Timer.new()
	close_timer.one_shot = true
	close_timer.wait_time = close_delay
	add_child(close_timer)

	if multiplayer.is_server():
		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)
		close_timer.timeout.connect(_on_close_timeout)

	# Clients request the current state when joining.
	if not multiplayer.is_server():
		_request_door_state.rpc_id(1)


func _on_body_entered(body: Node3D) -> void:
	if not _is_character(body):
		return

	if not bodies_inside.has(body):
		bodies_inside.append(body)

	close_timer.stop()
	_set_doors_open(true)


func _on_body_exited(body: Node3D) -> void:
	if not _is_character(body):
		return

	bodies_inside.erase(body)

	if bodies_inside.is_empty():
		close_timer.start(close_delay)


func _is_character(body: Node3D) -> bool:
	return body is CharacterBody3D


func _on_close_timeout() -> void:
	# Recheck in case someone entered during the delay.
	if bodies_inside.is_empty():
		_set_doors_open(false)


func _set_doors_open(open: bool) -> void:
	if doors_open == open:
		return

	doors_open = open
	_sync_door_animation.rpc(open)


@rpc("authority", "call_local", "reliable")
func _sync_door_animation(open: bool) -> void:
	doors_open = open

	if open:
		animation_player.play("open")
	else:
		animation_player.play_backwards("open")

	# Play the door motor sound when movement begins.
	door_audio.play()


@rpc("any_peer", "reliable")
func _request_door_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_receive_door_state.rpc_id(sender_id, doors_open)


@rpc("authority", "reliable")
func _receive_door_state(open: bool) -> void:
	doors_open = open

	if open:
		animation_player.play("open")
		animation_player.seek(animation_player.current_animation_length, true)
	else:
		animation_player.play("open")
		animation_player.seek(0.0, true)
		animation_player.stop()
