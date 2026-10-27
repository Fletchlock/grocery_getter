extends Node



enum GameState {
	MAIN_MENU,
	LOBBY,
	PLAYING,
	PAUSED,
	GAME_OVER,
	LATE_JOIN_WAITING
}

enum GameStartMode {
	NEW_GAME,
	CONTINUE_GAME
}

const STORE_LEVEL_PATH: String = "res://scenes/levels/third_person_level.tscn"

var game_start_mode: GameStartMode = GameStartMode.NEW_GAME


signal game_state_changed(new_state: GameState)

# CURRENT GAME STATE
# This keeps track of the current state of the game.
# We start in MAIN_MENU because that's where the game begins.
var current_state: GameState = GameState.MAIN_MENU
var is_late_joining: bool = false

# Our GameManager now listens for an important event from NetworkManager:
#
#     "The host has successfully been created."
#
# NetworkManager doesn't need to know what GameManager will do with that
# information. It simply emits the signal.
func _ready() -> void:
	
	# Connect NetworkManager's host_created signal to our local function.
	# The syntax:
	#     NetworkManager.host_created.connect(_on_host_created)
	# means:
	#     "When NetworkManager says host_created, call _on_host_created."
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.host_created.connect(_on_host_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)


# HOST CREATED
# This function is called when NetworkManager successfully creates the
# multiplayer host.
# At this point:
#     Steam lobby       -> created
#     Steam peer        -> created
#     Godot multiplayer -> configured
# We are NOT spawning players here yet.
# We're simply changing the overall game state.
func _on_host_created() -> void:
	print("GameManager: Host created.")
	
	
func _on_host_disconnected() -> void:
	print("GameManager: Host disconnected. Returning to main menu.")

	LevelManager.unload_level()
	LobbyManager.clear_players()
	NetworkManager.disconnect_from_lobby()

	set_game_state(GameState.MAIN_MENU)


func _on_lobby_joined(_lobby_id: int) -> void:
	if is_late_joining:
		print("GameManager: Waiting for late-join character selection.")
		return

	print("GameManager: Client joined lobby.")
	set_game_state(GameState.LOBBY)


func start_multiplayer_game() -> void:
	if not multiplayer.is_server():
		return
	
	print("GameManager: Initializing orders in Order Manager.")
	
	# Tell order manager to initialize orders.
	# Now handled in on_day_started in the order manager OrderManager.initialize_orders()
	
	print("GameManager: Starting multiplayer game.")

	# Prepare the selected game before loading the store scene.
	match game_start_mode:
		GameStartMode.NEW_GAME:
			print("GameManager: Starting NEW GAME.")
			
			SaveManager.reset_creation_date_on_save = true
			StoreManager.reset_store()
			StockOrderManager.reset_stock_orders()
			ReputationManager.reset_reputation()
			DayManager.load_save_data({
				"current_day": 1
			})
			StoreManager.sync_finances()
			if not SaveManager.save_game():
				push_error("GameManager: Failed to create initial game save.")
				return

			print("GameManager: Initial Day 1 save created.")
			
		GameStartMode.CONTINUE_GAME:
			print("GameManager: Continuing saved game.")
			
			SaveManager.reset_creation_date_on_save = false
			if not SaveManager.load_game():
				push_error("GameManager: Failed to load saved game.")
				return

	# Tell all clients to start the game.
	start_multiplayer_game_rpc.rpc()

	# Start the game locally for the host.
	set_game_state(GameState.PLAYING)

	LevelManager.load_level(
		"res://scenes/levels/third_person_level.tscn"
	)

	await get_tree().process_frame

	# Only restore saved boxes when continuing.
	if game_start_mode == GameStartMode.CONTINUE_GAME:
		StockOrderManager.restore_saved_boxes()

	DayManager.start_day()


@rpc("authority", "reliable")
func start_multiplayer_game_rpc() -> void:
	# The host already started the game locally.
	if multiplayer.is_server():
		return

	print("GameManager: Host started the game.")

	set_game_state(GameState.PLAYING)
	LevelManager.load_level("res://scenes/levels/third_person_level.tscn")

func set_game_state(new_state: GameState) -> void:
	current_state = new_state

	if multiplayer.is_server() and NetworkManager.current_lobby_id != 0:
		var session_state: String = "lobby"

		if new_state == GameState.PLAYING:
			session_state = "playing"

		Steam.setLobbyData(
			NetworkManager.current_lobby_id,
			"session_state",
			session_state
		)

	game_state_changed.emit(new_state)


func return_to_main_menu() -> void:
	print("GameManager: Returning to main menu.")

	# Stop the current game
	get_tree().paused = false

	# Unload the current level
	LevelManager.unload_level()

	# Clear multiplayer player data
	LobbyManager.clear_players()

	# Disconnect from Steam lobby and multiplayer peer
	await NetworkManager.disconnect_from_lobby()

	# Return to main menu state
	set_game_state(GameState.MAIN_MENU)


func leave_lobby() -> void:
	print("GameManager: Leaving lobby.")

	get_tree().paused = false

	LobbyManager.clear_players()

	await NetworkManager.disconnect_from_lobby()

	set_game_state(GameState.MAIN_MENU)

func _on_connected_to_server() -> void:
	if multiplayer.is_server():
		return

	print("GameManager: Requesting host game state.")
	request_host_game_state.rpc_id(1)


@rpc("any_peer", "reliable")
func request_host_game_state() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	if peer_id <= 0:
		return

	print("GameManager: Sending game state to peer ", peer_id)

	receive_host_game_state.rpc_id(
		peer_id,
		current_state
	)


@rpc("authority", "reliable")
func receive_host_game_state(host_state: int) -> void:
	if multiplayer.is_server():
		return

	print("GameManager: Received host state: ", host_state)

	if host_state == GameState.PLAYING:
		print("GameManager: Host is already playing.")

		if is_late_joining:
			print("GameManager: Remaining in late-join waiting state.")
		else:
			set_game_state(GameState.PLAYING)

			if LevelManager.current_level == null:
				LevelManager.load_level(STORE_LEVEL_PATH)

		DayManager.request_clock_state()
		StoreManager.request_finances()

func begin_late_join() -> void:
	if multiplayer.is_server() and NetworkManager.peer != null:
		return

	is_late_joining = true

	print("GameManager: Preparing late join.")

	set_game_state(GameState.LATE_JOIN_WAITING)


func complete_late_join() -> void:
	if not is_late_joining:
		return

	is_late_joining = false

	print("GameManager: Late join complete.")

	set_game_state(GameState.PLAYING)
