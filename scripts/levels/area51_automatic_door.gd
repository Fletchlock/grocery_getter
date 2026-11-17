
extends Node3D
class_name Area51AutomaticDoors


@export_group("Door Settings")
@export var close_delay: float = 1.5
@export var locked: bool = false

@export_group("Status Colors")
@export var unlocked_color: Color = Color("#0eff00")
@export var locked_color: Color = Color("#ff1010")


@onready var detection_area: Area3D = $DetectionArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var door_audio: AudioStreamPlayer3D = $DoorAudio
@onready var door_unlock_audio: AudioStreamPlayer3D = $DoorUnlockAudio
@onready var door_frame: Node3D = $area_51_door_frame


var bodies_inside: Array[Node3D] = []
var doors_open: bool = false
var close_timer: Timer
var status_material: StandardMaterial3D


func _ready() -> void:
	_setup_status_material()
	_update_status_color()

	close_timer = Timer.new()
	close_timer.one_shot = true
	close_timer.wait_time = close_delay
	add_child(close_timer)

	if multiplayer.is_server():
		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)
		close_timer.timeout.connect(_on_close_timeout)

		# Include any characters already inside the area.
		for body: Node3D in detection_area.get_overlapping_bodies():
			if _is_character(body):
				bodies_inside.append(body)

		if not locked and not bodies_inside.is_empty():
			_set_doors_open(true)

	else:
		_request_door_state.rpc_id(1)


# --------------------------------------------------
# STATUS MATERIAL
# --------------------------------------------------

func _setup_status_material() -> void:
	var frame_mesh: MeshInstance3D = _find_frame_mesh(door_frame)

	if frame_mesh == null:
		push_warning("Door frame MeshInstance3D not found.")
		return

	var original_material: Material = frame_mesh.get_active_material(1)

	if not original_material is StandardMaterial3D:
		push_warning("Door status material on surface 1 is not StandardMaterial3D.")
		return

	# Each door gets its own material instance.
	status_material = original_material.duplicate() as StandardMaterial3D
	frame_mesh.set_surface_override_material(1, status_material)


func _find_frame_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D

	for child: Node in node.get_children():
		var result: MeshInstance3D = _find_frame_mesh(child)

		if result != null:
			return result

	return null


func _update_status_color() -> void:
	if status_material == null:
		return

	var color: Color = locked_color if locked else unlocked_color

	status_material.emission_enabled = true
	status_material.emission = color


# --------------------------------------------------
# LOCK STATE
# --------------------------------------------------

func set_locked(value: bool) -> void:
	# The server controls door state.
	if not multiplayer.is_server():
		return

	if locked == value:
		return

	_apply_lock_state(value)
	_sync_lock_state.rpc(value)

	if locked:
		close_timer.stop()
		_set_doors_open(false)
	elif not bodies_inside.is_empty():
		_set_doors_open(true)


func _apply_lock_state(value: bool) -> void:
	if locked == value:
		return

	locked = value
	_update_status_color()

	door_unlock_audio.play()


@rpc("authority", "call_remote", "reliable")
func _sync_lock_state(value: bool) -> void:
	_apply_lock_state(value)


# --------------------------------------------------
# DETECTION
# --------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not _is_character(body):
		return

	if not bodies_inside.has(body):
		bodies_inside.append(body)

	if locked:
		return

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
	if bodies_inside.is_empty():
		_set_doors_open(false)


# --------------------------------------------------
# DOOR ANIMATION
# --------------------------------------------------

func _set_doors_open(open: bool) -> void:
	if not multiplayer.is_server():
		return

	if open and locked:
		return

	if doors_open == open:
		return

	_sync_door_animation.rpc(open)


@rpc("authority", "call_local", "reliable")
func _sync_door_animation(open: bool) -> void:
	doors_open = open

	if open:
		animation_player.play("door_open")
	else:
		animation_player.play_backwards("door_open")

	door_audio.play()


# --------------------------------------------------
# MULTIPLAYER STATE SYNC
# --------------------------------------------------

@rpc("any_peer", "reliable")
func _request_door_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	_receive_door_state.rpc_id(sender_id, doors_open, locked)


@rpc("authority", "reliable")
func _receive_door_state(open: bool, is_locked: bool) -> void:
	_apply_lock_state(is_locked)
	doors_open = open

	if open:
		animation_player.play("door_open")
		animation_player.seek(animation_player.current_animation_length, true)
	else:
		animation_player.play("door_open")
		animation_player.seek(0.0, true)
		animation_player.stop()
