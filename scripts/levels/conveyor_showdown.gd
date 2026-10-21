
extends Node3D


# ============================================================
# EXPORTS
# ============================================================

@export_group("Game Start")
@export var intro_delay: float = 1.0
@export var intro_fade_in: float = 1.0
@export var intro_hold: float = 2.0
@export var intro_fade_out: float = 1.0
@export var screen_fade_out: float = 0.2
@export var countdown_interval: float = 1.0
@export var go_display_duration: float = 0.6


# ============================================================
# NODE REFERENCES
# ============================================================

@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

@onready var survival_hud: Control = $CanvasLayer/SurvivalHUD
@onready var black_screen: ColorRect = $IntroLayer/BlackScreen
@onready var intro_label: Label = $IntroLayer/IntroLabel
@onready var countdown_label: Label = $IntroLayer/CountdownLabel

@onready var spawn_points: Array[Marker3D] = [
	$Environment/StartingArea/PlayerSpawnPoints/SpawnPoint1,
	$Environment/StartingArea/PlayerSpawnPoints/SpawnPoint2,
	$Environment/StartingArea/PlayerSpawnPoints/SpawnPoint3,
	$Environment/StartingArea/PlayerSpawnPoints/SpawnPoint4
]

@onready var finish_line: Area3D = $Environment/FinishArea/FinishLine

@onready var conveyor_belt: ConveyorBelt = $Environment/ConveyorBelt

# ============================================================
# RACE STATE
# ============================================================

var race_active: bool = false
var race_finished: bool = false

var race_players: Array[int] = []

var race_elapsed_time: float = 0.0
var finished_players: Dictionary = {}
var finish_order: Array[int] = []

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

	SpawnManager.setup_level(
		players,
		multiplayer_spawner,
		spawn_points
	)

	if not TransitionManager.all_peers_loaded.is_connected(
		_on_all_peers_loaded
	):
		TransitionManager.all_peers_loaded.connect(
			_on_all_peers_loaded
		)
	
	if not multiplayer.is_server():
		return
	
	if multiplayer.is_server():
		finish_line.body_entered.connect(_on_finish_line_body_entered)
	
	for peer_id: int in LobbyManager.get_players():
		race_players.append(peer_id)
		SpawnManager.spawn_player(peer_id)


# ============================================================
# PROCESS
# ============================================================

func _process(_delta: float) -> void:
	_set_local_player_movement_locked(not race_active)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not race_active or race_finished:
		return

	race_elapsed_time += delta


# ============================================================
# INTRODUCTION / COUNTDOWN
# ============================================================

func _start_intro_sequence() -> void:
	if not multiplayer.is_server():
		return

	_play_intro.rpc()

	var intro_duration: float = (
		intro_delay
		+ intro_fade_in
		+ intro_hold
		+ intro_fade_out
		+ screen_fade_out
	)

	await get_tree().create_timer(intro_duration).timeout

	if not is_inside_tree() or race_finished:
		return

	for number: int in [3, 2, 1]:
		_show_countdown.rpc(str(number))

		await get_tree().create_timer(countdown_interval).timeout

		if not is_inside_tree() or race_finished:
			return

	_start_race.rpc()

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

	await get_tree().create_timer(intro_delay).timeout

	if not is_inside_tree():
		return

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

	await get_tree().create_timer(intro_hold).timeout

	if not is_inside_tree():
		return

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


# ============================================================
# RACE START
# ============================================================

@rpc("authority", "call_local", "reliable")
func _start_race() -> void:
	race_active = true
	_show_countdown("GO!")

	print("CONVEYOR SHOWDOWN: Race started!")


func _set_local_player_movement_locked(locked: bool) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()

	var player: Node = players.get_node_or_null(
		str(local_peer_id)
	)

	if player == null:
		return

	player.movement_locked = locked


# ============================================================
# FINISH LINE
# ============================================================

func _on_finish_line_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if not race_active or race_finished:
		return

	if not body is CharacterBody3D:
		return

	if body.get_parent() != players:
		return

	var peer_id: int = body.get_multiplayer_authority()

	if not race_players.has(peer_id):
		return

	if finished_players.has(peer_id):
		return

	_finish_player(peer_id)


func _finish_player(peer_id: int) -> void:
	var finish_time: float = race_elapsed_time

	finished_players[peer_id] = finish_time
	finish_order.append(peer_id)

	var finish_position: int = finish_order.size()

	print(
		"CONVEYOR SHOWDOWN: Player ",
		peer_id,
		" finished in position ",
		finish_position,
		" with time ",
		"%.2f" % finish_time,
		" seconds"
	)


# ============================================================
# MULTIPLAYER TRANSITION
# ============================================================

func _on_all_peers_loaded(level_path: String) -> void:
	if level_path != TransitionManager.CONVEYOR_SHOWDOWN_SCENE:
		return

	if not multiplayer.is_server():
		return

	_start_intro_sequence()
