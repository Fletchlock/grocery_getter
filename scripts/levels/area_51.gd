
extends Node3D


@export_group("Door Testing")
@export var enable_door_timer: bool = true
@export var door_toggle_interval: float = 10.0


var door_timer: Timer
var doors: Array[Area51AutomaticDoors] = []


func _ready() -> void:
	# Collect all doors in the level.
	for child: Node in get_children():
		if child is Area51AutomaticDoors:
			doors.append(child)

	# Only the server controls door states.
	if not multiplayer.is_server():
		return

	if not enable_door_timer:
		return

	door_timer = Timer.new()
	door_timer.wait_time = maxf(door_toggle_interval, 0.01)
	door_timer.one_shot = false
	door_timer.timeout.connect(_on_door_timer_timeout)
	add_child(door_timer)
	door_timer.start()


func _on_door_timer_timeout() -> void:
	for door: Area51AutomaticDoors in doors:
		door.set_locked(not door.locked)
