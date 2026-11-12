extends Node3D


@onready var door_animation_player: AnimationPlayer = $delivery_truck_door_baked/AnimationPlayer

@export var door_trigger: Area3D

const DOOR_ANIMATION: String = "door_open"

var players_in_area: Array[Node3D] = []
var door_is_open: bool = false


func _ready() -> void:
	if door_trigger == null:
		push_error("DeliveryTruck: Door Trigger has not been assigned!")
		return

	if door_animation_player == null:
		push_error("DeliveryTruck: Door Animation Player has not been assigned!")
		return

	if multiplayer.is_server():
		if not door_trigger.body_entered.is_connected(_on_body_entered):
			door_trigger.body_entered.connect(_on_body_entered)

		if not door_trigger.body_exited.is_connected(_on_body_exited):
			door_trigger.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if not body.is_in_group("player"):
		return

	if players_in_area.has(body):
		return

	players_in_area.append(body)

	if not door_is_open:
		_set_door_open(true)


func _on_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if not body.is_in_group("player"):
		return

	players_in_area.erase(body)

	if players_in_area.is_empty() and door_is_open:
		_set_door_open(false)


func _set_door_open(open: bool) -> void:
	if not multiplayer.is_server():
		return

	door_is_open = open
	_sync_door_state.rpc(open)


@rpc("authority", "call_local", "reliable")
func _sync_door_state(open: bool) -> void:
	door_is_open = open

	if open:
		door_animation_player.play(DOOR_ANIMATION)
	else:
		door_animation_player.play_backwards(DOOR_ANIMATION)
