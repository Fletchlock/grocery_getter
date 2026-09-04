extends Node


# GAME STATES
# These represent the major states our game can be in.
# MAIN_MENU
#     The player is at the main menu.
# PLAYING
#     The actual game is running.
# PAUSED
#     The game is currently paused.
# GAME_OVER
#     The game has ended.
enum GameState {
	MAIN_MENU,
	PLAYING,
	PAUSED,
	GAME_OVER
}

signal game_state_changed(new_state: GameState)

# CURRENT GAME STATE
# This keeps track of the current state of the game.
# We start in MAIN_MENU because that's where the game begins.
var current_state: GameState = GameState.MAIN_MENU


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
	NetworkManager.host_created.connect(_on_host_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)


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

	# Change the game state to PLAYING.
	# We'll eventually change this flow so that the game enters a lobby
	# state first. For now, we're keeping things simple while we build
	# the networking foundation.

	set_game_state(GameState.PLAYING)
	LevelManager.load_level("res://scenes/levels/third_person_level.tscn")


func _on_lobby_joined(_lobby_id: int) -> void:
	print("GameManager: Client joined lobby.")
	set_game_state(GameState.PLAYING)
	LevelManager.load_level("res://scenes/levels/third_person_level.tscn")


# SET GAME STATE
# This is our central function for changing the game's state.
# Other systems can eventually call:
#     GameManager.set_game_state(GameState.PAUSED)
# or:
#     GameManager.set_game_state(GameState.GAME_OVER)
# Keeping the change in one function gives us a good place to add additional
# behavior later.
func set_game_state(new_state: GameState) -> void:
	current_state = new_state
	game_state_changed.emit(new_state)
