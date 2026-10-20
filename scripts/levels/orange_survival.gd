
extends Node3D


# ============================================================
# EXPORTS
# ============================================================

@export_group("Orange Rotation")
@export var starting_rotation_speed: float = 0.30
@export var maximum_rotation_speed: float = 0.90
@export var speed_increase: float = 0.10
@export var speed_increase_interval: float = 10.0

@export_group("Direction Changes")
@export var minimum_direction_time: float = 2.5
@export var maximum_direction_time: float = 4.0
@export var reverse_chance: float = 0.50

@export_group("Game Start")
@export var intro_delay: float = 1.0
@export var intro_fade_in: float = 1.0
@export var intro_hold: float = 2.0
@export var intro_fade_out: float = 1.0
@export var screen_fade_out: float = 0.2
@export var countdown_interval: float = 1.0
@export var go_display_duration: float = 0.6

@export_group("Elimination")
@export var elimination_height: float = -15.0

@export_group("Survival Timer")
@export var round_duration: float = 60.0

@export_group("Spectator Camera")
@export var spectator_follow_offset: Vector3 = Vector3(0.0, 4.0, 8.0)
@export var spectator_follow_speed: float = 5.0

@export_group("Results")
@export var results_duration: float = 10.0

# ============================================================
# NODE REFERENCES
# ============================================================

@onready var orange: AnimatableBody3D = $Orange
@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var spectator_camera: Camera3D = $SpectatorCamera

@onready var survival_hud: Control = $CanvasLayer/SurvivalHUD
@onready var results_ui: Control = $CanvasLayer/ResultsUI
@onready var results_title: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/TitleLabel
@onready var results_label: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/ResultsLabel
@onready var continue_label: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/ContinueLabel
@onready var black_screen: ColorRect = $IntroLayer/BlackScreen
@onready var intro_label: Label = $IntroLayer/IntroLabel
@onready var countdown_label: Label = $IntroLayer/CountdownLabel

@onready var timer_label: Label = $CanvasLayer/SurvivalHUD/PanelContainer/VBoxContainer/TimerLabel
@onready var players_label: Label = $CanvasLayer/SurvivalHUD/PanelContainer/VBoxContainer/PlayersLabel

@onready var spawn_points: Array[Marker3D] = [
	$SpawnPoints/SpawnPoint1,
	$SpawnPoints/SpawnPoint2,
	$SpawnPoints/SpawnPoint3,
	$SpawnPoints/SpawnPoint4
]


# ============================================================
# ROTATION STATE
# ============================================================

var orange_rotating: bool = false
var current_rotation_speed: float = 0.0
var current_rotation_axis: Vector3 = Vector3.FORWARD

var speed_timer: float = 0.0
var direction_timer: float = 0.0
var next_direction_change: float = 0.0


# ============================================================
# ROUND STATE
# ============================================================

var round_time_remaining: float = 0.0
var round_active: bool = false
var round_finished: bool = false

var round_players: Array[int] = []
var eliminated_players: Dictionary = {}

var last_synced_second: int = -1


# ============================================================
# SPECTATOR STATE
# ============================================================

var spectating_player_id: int = -1
var spectator_targets: Array[int] = []

var original_spectator_transform: Transform3D

# ============================================================
# RESULTS STATE
# ============================================================

var results_time_remaining: float = 0.0
var results_countdown_active: bool = false
var last_results_second: int = -1


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	black_screen.color = Color.BLACK
	black_screen.modulate.a = 1.0
	black_screen.show()

	intro_label.modulate.a = 0.0
	intro_label.show()

	countdown_label.text = ""
	countdown_label.modulate.a = 0.0
	countdown_label.show()

	survival_hud.hide()
	
	original_spectator_transform = spectator_camera.global_transform

	round_time_remaining = round_duration

	_update_survival_hud(
		round_time_remaining,
		0,
		0
	)

	SpawnManager.setup_level(
		players,
		multiplayer_spawner,
		spawn_points
	)
	# Both host and clients connect.
	if not TransitionManager.all_peers_loaded.is_connected(
		_on_all_peers_loaded
	):
		TransitionManager.all_peers_loaded.connect(
			_on_all_peers_loaded
		)
	
	if not multiplayer.is_server():
		return

	for peer_id: int in LobbyManager.get_players():
		round_players.append(peer_id)
		SpawnManager.spawn_player(peer_id)
	
	_broadcast_survival_hud()

	current_rotation_speed = starting_rotation_speed

	next_direction_change = randf_range(
		minimum_direction_time,
		maximum_direction_time
	)


# ============================================================
# PROCESS
# ============================================================

func _process(delta: float) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()
	
	if not round_active:
		_set_local_player_movement_locked(true)
	else:
		_set_local_player_movement_locked(false)
	
	# Spectator mode takes priority over normal camera handling.
	if eliminated_players.has(local_peer_id):
		_update_spectator_camera(delta)
		return


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	_update_results_countdown(delta)

	if not orange_rotating:
		return
	
	if not orange_rotating:
		return

	orange.rotate(
		current_rotation_axis,
		current_rotation_speed * delta
	)

	speed_timer += delta
	direction_timer += delta

	if speed_timer >= speed_increase_interval:
		speed_timer = 0.0

		current_rotation_speed = minf(
			current_rotation_speed + speed_increase,
			maximum_rotation_speed
		)

	if direction_timer >= next_direction_change:
		direction_timer = 0.0

		next_direction_change = randf_range(
			minimum_direction_time,
			maximum_direction_time
		)

		_change_rotation_direction()

	_check_player_eliminations()
	_update_round_timer(delta)


# ============================================================
# ORANGE ROTATION
# ============================================================

func _change_rotation_direction() -> void:
	if randf() < reverse_chance:
		current_rotation_axis = -current_rotation_axis
	else:
		var angle: float = randf_range(0.0, TAU)

		current_rotation_axis = Vector3(
			cos(angle),
			0.0,
			sin(angle)
		).normalized()


# ============================================================
# PLAYER ELIMINATION
# ============================================================

func _check_player_eliminations() -> void:
	if not multiplayer.is_server():
		return

	for player: Node in players.get_children():
		if not player is CharacterBody3D:
			continue

		var peer_id: int = player.name.to_int()

		if eliminated_players.has(peer_id):
			continue

		if player.global_position.y < elimination_height:
			_eliminate_player(peer_id)


func _eliminate_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if eliminated_players.has(peer_id):
		return

	eliminated_players[peer_id] = true

	print(
		"ORANGE SURVIVAL: Player ",
		peer_id,
		" eliminated!"
	)

	_sync_eliminated_players.rpc(eliminated_players)
	_broadcast_survival_hud()


@rpc("authority", "call_local", "reliable")
func _sync_eliminated_players(state: Dictionary) -> void:
	eliminated_players = state.duplicate(true)

	print(
		"ORANGE SURVIVAL: Eliminated players: ",
		eliminated_players
	)

	var local_peer_id: int = multiplayer.get_unique_id()

	if eliminated_players.has(local_peer_id):
		_activate_spectator_camera()


# ============================================================
# ROUND TIMER
# ============================================================

func _update_round_timer(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not round_active:
		return

	round_time_remaining = maxf(
		round_time_remaining - delta,
		0.0
	)

	var current_second: int = ceili(round_time_remaining)

	if current_second != last_synced_second:
		last_synced_second = current_second
		_broadcast_survival_hud()

	if _are_all_players_eliminated():
		_finish_round()
		return

	if round_time_remaining <= 0.0:
		_finish_round()


func _are_all_players_eliminated() -> bool:
	if round_players.is_empty():
		return false

	for peer_id: int in round_players:
		if not eliminated_players.has(peer_id):
			return false

	return true


# ============================================================
# ROUND COMPLETION
# ============================================================

func _finish_round() -> void:
	if not multiplayer.is_server():
		return

	if round_finished:
		return

	round_finished = true
	round_active = false
	orange_rotating = false

	var winners: Array[int] = []

	if round_time_remaining <= 0.0:
		for peer_id: int in round_players:
			if not eliminated_players.has(peer_id):
				winners.append(peer_id)

	_sync_round_finished.rpc(winners)
	
	results_time_remaining = results_duration
	results_countdown_active = true
	last_results_second = -1

	_broadcast_results_countdown()

@rpc("authority", "call_local", "reliable")
func _sync_round_finished(winners: Array[int]) -> void:
	round_finished = true
	round_active = false
	orange_rotating = false

	if winners.is_empty():
		print(
			"ORANGE SURVIVAL: Everyone eliminated! No winners."
		)
	else:
		print("ORANGE SURVIVAL: Round complete!")
		print("ORANGE SURVIVAL: Winners: ", winners)
	
	_show_round_results(winners)

# ============================================================
# RESULTS HUD
# ============================================================

func _show_round_results(winners: Array[int]) -> void:
	survival_hud.hide()
	results_ui.show()

	var local_peer_id: int = multiplayer.get_unique_id()

	if winners.has(local_peer_id):
		results_title.text = "YOU SURVIVED!"
	else:
		results_title.text = "ELIMINATED!"

	if winners.is_empty():
		results_label.text = "Nobody survived the orange!"
	else:
		var result_text: String = "Survivors:\n"

		for peer_id: int in winners:
			result_text += str(peer_id) + "\n"

		results_label.text = result_text

	continue_label.text = "Waiting to continue..."



func _update_results_countdown(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not results_countdown_active:
		return

	results_time_remaining = maxf(
		results_time_remaining - delta,
		0.0
	)

	var current_second: int = ceili(results_time_remaining)

	if current_second != last_results_second:
		last_results_second = current_second
		_broadcast_results_countdown()

	if results_time_remaining <= 0.0:
		results_countdown_active = false
		_on_results_countdown_finished()


func _broadcast_results_countdown() -> void:
	if not multiplayer.is_server():
		return

	_sync_results_countdown.rpc(
		ceili(results_time_remaining)
	)


@rpc("authority", "call_local", "reliable")
func _sync_results_countdown(seconds: int) -> void:
	continue_label.text = "Continuing in %d..." % seconds



func _on_results_countdown_finished() -> void:
	if not multiplayer.is_server():
		return

	print("ORANGE SURVIVAL: Returning to grocery store.")

	TransitionManager.return_to_grocery_store()


# ============================================================
# SURVIVAL HUD
# ============================================================

func _update_survival_hud(
	time_remaining: float,
	remaining: int,
	total: int
) -> void:
	var seconds: int = ceili(time_remaining)
	var minutes: int = floori(float(seconds) / 60.0)
	var leftover_seconds: int = seconds % 60

	timer_label.text = "%02d:%02d" % [
		minutes,
		leftover_seconds
	]

	players_label.text = (
		"Players Remaining: %d / %d"
		% [remaining, total]
	)


func _get_remaining_player_count() -> int:
	var remaining: int = 0

	for peer_id: int in round_players:
		if not eliminated_players.has(peer_id):
			remaining += 1

	return remaining


@rpc("authority", "call_local", "reliable")
func _sync_survival_hud(
	time_remaining: float,
	remaining: int,
	total: int
) -> void:
	_update_survival_hud(
		time_remaining,
		remaining,
		total
	)


func _broadcast_survival_hud() -> void:
	if not multiplayer.is_server():
		return

	_sync_survival_hud.rpc(
		round_time_remaining,
		_get_remaining_player_count(),
		round_players.size()
	)


# ============================================================
# SPECTATOR CAMERA
# ============================================================

func _activate_spectator_camera() -> void:
	spectating_player_id = -1

	# Restore the camera's editor-defined position and rotation.
	spectator_camera.global_transform = original_spectator_transform

	spectator_camera.make_current()

	print("ORANGE SURVIVAL: Spectator camera activated.")


func _refresh_spectator_targets() -> void:
	spectator_targets.clear()

	for player: Node in players.get_children():
		if not player is CharacterBody3D:
			continue

		var peer_id: int = player.name.to_int()

		if eliminated_players.has(peer_id):
			continue

		spectator_targets.append(peer_id)

	# Keep the cycling order consistent.
	spectator_targets.sort()


func _cycle_spectator_target(direction: int) -> void:
	_refresh_spectator_targets()

	# -1 represents the fixed overview camera.
	var targets: Array[int] = [-1]
	targets.append_array(spectator_targets)

	var index: int = targets.find(spectating_player_id)

	if index == -1:
		index = 0

	index = posmod(
		index + direction,
		targets.size()
	)

	spectating_player_id = targets[index]

	if spectating_player_id == -1:
		spectator_camera.global_transform = original_spectator_transform
		print("ORANGE SURVIVAL: Spectating overview.")
	else:
		print(
			"ORANGE SURVIVAL: Spectating player ",
			spectating_player_id
		)


func _update_spectator_camera(delta: float) -> void:
	if spectating_player_id == -1:
		return

	var target: CharacterBody3D = players.get_node_or_null(
		str(spectating_player_id)
	) as CharacterBody3D

	# Return to overview if the target is gone or eliminated.
	if target == null or eliminated_players.has(spectating_player_id):
		spectating_player_id = -1
		spectator_camera.global_transform = original_spectator_transform
		return

	var target_position: Vector3 = (
		target.global_position + spectator_follow_offset
	)

	spectator_camera.global_position = spectator_camera.global_position.lerp(
		target_position,
		clampf(spectator_follow_speed * delta, 0.0, 1.0)
	)

	# Aim toward the player while following.
	var look_target: Vector3 = (
		target.global_position + Vector3.UP * 1.5
	)

	if spectator_camera.global_position.distance_squared_to(look_target) > 0.0001:
		spectator_camera.look_at(
			look_target,
			Vector3.UP
		)


# ============================================================
# SPECTATOR INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	# Only eliminated players can switch spectator cameras.
	if not eliminated_players.has(multiplayer.get_unique_id()):
		return

	if event.is_action_pressed("next_spectator_camera"):
		_cycle_spectator_target(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("previous_spectator_camera"):
		_cycle_spectator_target(-1)
		get_viewport().set_input_as_handled()


# ============================================================
# INTRODUCTION / COUNTDOWN
# ============================================================

func _start_intro_sequence() -> void:
	if not multiplayer.is_server():
		return

	# Start the introduction on every peer.
	_play_intro.rpc()

	# Wait for the complete introduction.
	var intro_duration: float = (
		intro_delay
		+ intro_fade_in
		+ intro_hold
		+ intro_fade_out
		+ screen_fade_out
	)

	await get_tree().create_timer(intro_duration).timeout

	if not is_inside_tree() or round_finished:
		return

	# Server controls the countdown.
	for number: int in [3, 2, 1]:
		_show_countdown.rpc(str(number))

		await get_tree().create_timer(countdown_interval).timeout

		if not is_inside_tree() or round_finished:
			return

	# GO! and rotation start together.
	_start_round.rpc()

	_broadcast_survival_hud()

	print("ORANGE SURVIVAL: Round started!")

	await get_tree().create_timer(go_display_duration).timeout

	if not is_inside_tree():
		return

	_hide_countdown.rpc()


@rpc("authority", "call_local", "reliable")
func _play_intro() -> void:
	_play_intro_animation()


func _play_intro_animation() -> void:
	black_screen.modulate.a = 1.0
	black_screen.show()

	intro_label.modulate.a = 0.0
	intro_label.show()

	countdown_label.text = ""
	countdown_label.modulate.a = 0.0

	# Wait before displaying the message.
	await get_tree().create_timer(intro_delay).timeout

	if not is_inside_tree():
		return

	# Fade the text in.
	var tween_in: Tween = create_tween()
	tween_in.tween_property(
		intro_label,
		"modulate:a",
		1.0,
		intro_fade_in
	)

	await tween_in.finished

	if not is_inside_tree():
		return

	# Hold the text on screen.
	await get_tree().create_timer(intro_hold).timeout

	if not is_inside_tree():
		return

	# Fade the text out.
	var tween_out: Tween = create_tween()
	tween_out.tween_property(
		intro_label,
		"modulate:a",
		0.0,
		intro_fade_out
	)

	await tween_out.finished

	if not is_inside_tree():
		return

	# Reveal the level.
	var screen_tween: Tween = create_tween()
	screen_tween.tween_property(
		black_screen,
		"modulate:a",
		0.0,
		screen_fade_out
	)

	await screen_tween.finished

	if not is_inside_tree():
		return

	black_screen.hide()
	intro_label.hide()
	survival_hud.show()


@rpc("authority", "call_local", "reliable")
func _show_countdown(value: String) -> void:
	countdown_label.text = value
	countdown_label.modulate.a = 1.0


@rpc("authority", "call_local", "reliable")
func _hide_countdown() -> void:
	countdown_label.modulate.a = 0.0
	countdown_label.text = ""


@rpc("authority", "call_local", "reliable")
func _set_players_movement_locked(locked: bool) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()

	var player: CharacterBody3D = players.get_node_or_null(
		str(local_peer_id)
	) as CharacterBody3D

	if player == null:
		return

	player.movement_locked = locked


@rpc("authority", "call_local", "reliable")
func _start_round() -> void:
	round_active = true
	_show_countdown("GO!")

	if multiplayer.is_server():
		orange_rotating = true


func _set_local_player_movement_locked(locked: bool) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()

	var player: Node = players.get_node_or_null(str(local_peer_id))

	if player == null:
		return

	player.movement_locked = locked

func _on_all_peers_loaded(level_path: String) -> void:
	if level_path != TransitionManager.ORANGE_SURVIVAL_SCENE:
		return

	if not multiplayer.is_server():
		return

	_start_intro_sequence()
