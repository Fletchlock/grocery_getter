
extends Node3D


const CONVEYOR_OBSTACLE_SCENE: PackedScene = preload(
	"res://scenes/objects/minigames/ConveyorObstacle.tscn"
)


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

@export_group("Race Timer")
@export var race_duration: float = 90.0

@export_group("Obstacle Spawning")
@export var minimum_spawn_interval: float = 2.0
@export var maximum_spawn_interval: float = 4.0
@export var maximum_active_obstacles: int = 12
@export var obstacle_cleanup_z: float = 50.0
@export var obstacle_products: Array[ProductData] = []
@export var obstacle_scale: float = 12.0
@export var obstacle_spawn_half_width: float = 8.0
@export var rolling_obstacle_products: Array[ProductData] = []

@export_group("Player Respawning")
@export var respawn_y: float = -20.0

@export_group("Results")
@export var results_duration: float = 10.0

@export_group("Spectator Camera")
@export var spectator_follow_offset: Vector3 = Vector3(0.0, 4.0, 8.0)
@export var spectator_follow_speed: float = 5.0


# ============================================================
# NODE REFERENCES
# ============================================================

@onready var players: Node3D = $Players
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var spectator_camera: Camera3D = $SpectatorCamera

@onready var timer_label: Label = $CanvasLayer/SurvivalHUD/PanelContainer/VBoxContainer/TimerLabel
@onready var survival_hud: Control = $CanvasLayer/SurvivalHUD
@onready var results_ui: Control = $CanvasLayer/ResultsUI
@onready var results_title: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/TitleLabel
@onready var results_label: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/ResultsLabel
@onready var continue_label: Label = $CanvasLayer/ResultsUI/PanelContainer/VBoxContainer/ContinueLabel

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
@onready var products: Node3D = $Products
@onready var product_spawner: MultiplayerSpawner = $MultiplayerProductSpawner
@onready var product_spawn_point: Marker3D = $Environment/ProductSpawnPoint

# Barrier Reference
@onready var pillars: Node3D = $Environment/Pillars

# ============================================================
# RACE STATE
# ============================================================

var race_time_remaining: float = 0.0
var last_synced_second: int = -1

var race_active: bool = false
var race_finished: bool = false

var race_players: Array[int] = []
var race_elapsed_time: float = 0.0

var finished_players: Dictionary = {}
var finish_order: Array[int] = []


# ============================================================
# SPECTATOR STATE
# ============================================================

var spectator_active: bool = false
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
# OBSTACLE STATE
# ============================================================

var obstacle_spawn_timer: float = 0.0


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
	results_ui.hide()
	
	race_time_remaining = race_duration
	_update_race_hud(race_time_remaining)
	
	original_spectator_transform = spectator_camera.global_transform

	SpawnManager.setup_level(
		players,
		multiplayer_spawner,
		spawn_points
	)

	product_spawner.spawn_function = _spawn_conveyor_obstacle

	if not TransitionManager.all_peers_loaded.is_connected(
		_on_all_peers_loaded
	):
		TransitionManager.all_peers_loaded.connect(
			_on_all_peers_loaded
		)

	if not multiplayer.is_server():
		return

	finish_line.body_entered.connect(
		_on_finish_line_body_entered
	)

	for peer_id: int in LobbyManager.get_players():
		race_players.append(peer_id)
		SpawnManager.spawn_player(peer_id)


# ============================================================
# PROCESS
# ============================================================


func _process(delta: float) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()
	var has_finished: bool = finished_players.has(local_peer_id)

	_set_local_player_movement_locked(
		not race_active or has_finished
	)

	# Each player checks their own fall.
	if race_active and not race_finished and not has_finished:
		_check_local_player_fall()

	# Finished players can spectate.
	if has_finished and not race_finished:
		_update_spectator_camera(delta)



func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_update_results_countdown(delta)

	if not race_active or race_finished:
		return
		
	race_elapsed_time += delta
	_update_race_timer(delta)

	if race_finished:
		return

	# Spawn obstacles at randomized intervals.
	obstacle_spawn_timer -= delta

	if obstacle_spawn_timer <= 0.0:
		if products.get_child_count() < maximum_active_obstacles:
			_spawn_random_obstacle()

		obstacle_spawn_timer = randf_range(
			minimum_spawn_interval,
			maximum_spawn_interval
		)

	# Remove obstacles that have passed the starting area.
	for child: Node in products.get_children():
		if not child is ConveyorObstacle:
			continue

		var obstacle: ConveyorObstacle = child as ConveyorObstacle

		if obstacle.global_position.z > obstacle_cleanup_z:
			obstacle.queue_free()


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
	
	# Spawn the first obstacle before the countdown.
	_spawn_random_obstacle()	
	
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
# CONVEYOR OBSTACLE SPAWNING
# ============================================================

func _spawn_random_obstacle() -> void:
	if not multiplayer.is_server():
		return

	if obstacle_products.is_empty():
		push_warning("CONVEYOR: No obstacle products assigned.")
		return

	var valid_products: Array[ProductData] = []

	for product: ProductData in obstacle_products:
		if product == null:
			continue

		if product.product_mesh == null:
			continue

		if product.resource_path.is_empty():
			continue

		valid_products.append(product)

	if valid_products.is_empty():
		push_warning("CONVEYOR: No valid obstacle products found.")
		return

	# The server chooses which product everyone will see.
	var selected_product: ProductData = valid_products.pick_random()
	var should_roll: bool = rolling_obstacle_products.has(
		selected_product
	)

	var spawn_position: Vector3 = product_spawn_point.global_position
	var rotation_y: float = randf_range(0.0, TAU)

	var bounds: AABB = selected_product.product_mesh.get_aabb()
	var scaled_size: Vector3 = bounds.size * obstacle_scale

	# Account for the width occupied after Y rotation.
	var rotated_half_width: float = (
		absf(cos(rotation_y)) * scaled_size.x
		+ absf(sin(rotation_y)) * scaled_size.z
	) * 0.5

	var available_half_width: float = maxf(
		0.0,
		obstacle_spawn_half_width - rotated_half_width
	)

	spawn_position.x = product_spawn_point.global_position.x + randf_range(
		-available_half_width,
		available_half_width
	)

	spawn_position.y = 0.5

	product_spawner.spawn({
		"position": spawn_position,
		"product_path": selected_product.resource_path,
		"scale": obstacle_scale,
		"rotation_y": rotation_y,
		"rolling": should_roll
	})


func _spawn_conveyor_obstacle(data: Variant) -> Node:
	var spawn_data: Dictionary = data

	var spawn_position: Vector3 = spawn_data["position"]
	var product_path: String = spawn_data["product_path"]
	var scale_multiplier: float = spawn_data["scale"]
	var rotation_y: float = spawn_data["rotation_y"]
	var should_roll: bool = spawn_data["rolling"]

	var obstacle: ConveyorObstacle = (
		CONVEYOR_OBSTACLE_SCENE.instantiate() as ConveyorObstacle
	)

	if obstacle == null:
		push_error("CONVEYOR: Failed to instantiate obstacle.")
		return null

	var product: ProductData = load(product_path) as ProductData

	if product == null or product.product_mesh == null:
		push_error("CONVEYOR: Invalid product: " + product_path)
		obstacle.free()
		return null

	obstacle.position = products.to_local(spawn_position)
	obstacle.rotation.y = rotation_y
	obstacle.conveyor_belt = conveyor_belt
	obstacle.is_rolling = should_roll

	obstacle.configure_product(product, scale_multiplier)

	return obstacle


# ============================================================
# RACE START
# ============================================================


@rpc("authority", "call_local", "reliable")
func _start_race() -> void:
	race_active = true
	race_time_remaining = race_duration
	race_elapsed_time = 0.0
	last_synced_second = -1
	_update_race_hud(race_time_remaining)
	_show_countdown("GO!")

	if multiplayer.is_server():
		for barrier: Node in pillars.get_children():
			if barrier is BarrierPillars:
				barrier.start_barrier()
		
		_sync_race_players.rpc(race_players)
		
		obstacle_spawn_timer = randf_range(
			minimum_spawn_interval,
			maximum_spawn_interval
		)

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
# PLAYER RESPAWNING
# ============================================================

func _check_local_player_fall() -> void:
	var peer_id: int = multiplayer.get_unique_id()

	var player: CharacterBody3D = players.get_node_or_null(
		str(peer_id)
	) as CharacterBody3D

	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	if player.global_position.y > respawn_y:
		return

	_respawn_local_player(player, peer_id)


func _respawn_local_player(
	player: CharacterBody3D,
	peer_id: int
) -> void:
	var spawn_index: int = race_players.find(peer_id)

	if spawn_index < 0 or spawn_index >= spawn_points.size():
		return

	player.global_transform = spawn_points[spawn_index].global_transform
	player.velocity = Vector3.ZERO

	# Clear remaining knockback and conveyor forces.
	player.set("knockback_velocity", Vector3.ZERO)
	player.set("conveyor_velocity", Vector3.ZERO)

	print("CONVEYOR SHOWDOWN: Player ", peer_id, " respawned.")


# ============================================================
# RACE TIMER
# ============================================================

func _update_race_timer(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not race_active or race_finished:
		return

	race_time_remaining = maxf(
		race_time_remaining - delta,
		0.0
	)

	var current_second: int = ceili(race_time_remaining)

	if current_second != last_synced_second:
		last_synced_second = current_second
		_sync_race_timer.rpc(race_time_remaining)

	if race_time_remaining <= 0.0:
		_finish_race()


@rpc("authority", "call_local", "reliable")
func _sync_race_timer(time_remaining: float) -> void:
	race_time_remaining = time_remaining
	_update_race_hud(time_remaining)


@rpc("authority", "call_local", "reliable")
func _sync_race_players(participants: Array[int]) -> void:
	race_players = participants.duplicate()


func _update_race_hud(time_remaining: float) -> void:
	var seconds: int = ceili(time_remaining)
	var minutes: int = floori(float(seconds) / 60.0)
	var leftover_seconds: int = seconds % 60

	timer_label.text = "%02d:%02d" % [
		minutes,
		leftover_seconds
	]



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

	# Tell all peers that this player has finished.
	_sync_finished_players.rpc(finished_players)

	if finish_order.size() >= race_players.size():
		_finish_race()


@rpc("authority", "call_local", "reliable")
func _sync_finished_players(state: Dictionary) -> void:
	finished_players = state.duplicate(true)

	var local_peer_id: int = multiplayer.get_unique_id()

	if (
		finished_players.has(local_peer_id)
		and not spectator_active
		and not race_finished
	):
		_set_local_player_movement_locked(true)
		_activate_spectator_camera()


# ============================================================
# RACE COMPLETION
# ============================================================

func _finish_race() -> void:
	if not multiplayer.is_server():
		return

	if race_finished:
		return

	race_finished = true
	race_active = false

	_sync_race_finished.rpc(
		finish_order,
		finished_players,
		race_players
	)

	results_time_remaining = results_duration
	results_countdown_active = true
	last_results_second = -1

	_broadcast_results_countdown()



@rpc("authority", "call_local", "reliable")
func _sync_race_finished(
	positions: Array[int],
	times: Dictionary,
	participants: Array[int]
) -> void:
	race_finished = true
	race_active = false

	for barrier: Node in pillars.get_children():
		if barrier is BarrierPillars:
			barrier.stop_barrier()

	finish_order = positions.duplicate()
	finished_players = times.duplicate(true)
	race_players = participants.duplicate()

	_show_race_results()


# ============================================================
# RESULTS UI
# ============================================================


func _show_race_results() -> void:
	survival_hud.hide()
	results_ui.show()

	var local_peer_id: int = multiplayer.get_unique_id()

	if finish_order.is_empty():
		results_title.text = "NO WINNERS!"
	elif finish_order[0] == local_peer_id:
		results_title.text = "1st PLACE!"
	elif finish_order[1] == local_peer_id:
		results_title.text = "2nd PLACE!"
	elif finish_order[2] == local_peer_id:
		results_title.text = "3rd PLACE!"
	elif finish_order[3] == local_peer_id:
		results_title.text = "4th PLACE!"
	else:
		results_title.text = "ELIMINATED!"

	var result_text: String = "FINAL RESULTS\n\n"

	# Players who crossed the finish line.
	for i: int in finish_order.size():
		var peer_id: int = finish_order[i]
		var finish_time: float = float(finished_players[peer_id])
		var player_name: String = _get_player_display_name(peer_id)
		
		var minutes: int = floori(finish_time / 60.0)
		var seconds: float = fposmod(finish_time, 60.0)

		result_text += "%d. %s - %02d:%05.2f\n" % [
			i + 1,
			player_name,
			minutes,
			seconds
		]

	# Players who failed to finish before the time limit.
	for peer_id: int in race_players:
		if finished_players.has(peer_id):
			continue

		result_text += "%s - ELIMINATED\n" % _get_player_display_name(peer_id)

	results_label.text = result_text
	continue_label.text = "Waiting to continue..."


func _get_player_display_name(peer_id: int) -> String:
	var player_name: String = LobbyManager.get_player_name(peer_id)

	if player_name.is_empty():
		return "Player %d" % peer_id

	return player_name
	

# ============================================================
# RESULTS COUNTDOWN
# ============================================================

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

	print("CONVEYOR SHOWDOWN: Returning to grocery store.")

	TransitionManager.return_to_grocery_store()


# ============================================================
# SPECTATOR CAMERA
# ============================================================

func _activate_spectator_camera() -> void:
	spectator_active = true
	spectating_player_id = -1

	# Restore the camera's original overview position.
	spectator_camera.global_transform = original_spectator_transform

	spectator_camera.make_current()

	print("CONVEYOR SHOWDOWN: Spectator camera activated.")


func _refresh_spectator_targets() -> void:
	spectator_targets.clear()

	for player: Node in players.get_children():
		if not player is CharacterBody3D:
			continue

		var peer_id: int = player.name.to_int()

		# Only spectate players who are still racing.
		if finished_players.has(peer_id):
			continue

		spectator_targets.append(peer_id)

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

		print("CONVEYOR SHOWDOWN: Spectating overview.")
	else:
		print(
			"CONVEYOR SHOWDOWN: Spectating player ",
			spectating_player_id
		)


func _update_spectator_camera(delta: float) -> void:
	if spectating_player_id == -1:
		return

	var target: CharacterBody3D = players.get_node_or_null(
		str(spectating_player_id)
	) as CharacterBody3D

	# Return to overview if the target is gone or has finished.
	if target == null or finished_players.has(spectating_player_id):
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
	if race_finished or not spectator_active:
		return

	if event.is_action_pressed("next_spectator_camera"):
		_cycle_spectator_target(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("previous_spectator_camera"):
		_cycle_spectator_target(-1)
		get_viewport().set_input_as_handled()


# ============================================================
# MULTIPLAYER TRANSITION
# ============================================================

func _on_all_peers_loaded(level_path: String) -> void:
	if level_path != TransitionManager.CONVEYOR_SHOWDOWN_SCENE:
		return

	if not multiplayer.is_server():
		return

	_start_intro_sequence()
