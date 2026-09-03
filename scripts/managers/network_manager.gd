extends Node


# ============================================================================
# SIGNALS
# ============================================================================
# Signals allow NetworkManager to tell other parts of the game that something
# important has happened.
#
# We don't want NetworkManager to directly control the GameManager,
# LevelManager, UI, etc.
#
# Instead, it announces:
#   "The host has been created!"
#   "A lobby has been joined!"
#
# Other systems can listen for these signals.
# ============================================================================

signal host_created
signal lobby_joined(lobby_id: int)


# ============================================================================
# LOBBY CONFIGURATION
# ============================================================================
# These are constants because we don't expect them to change while the game
# is running.
#
# LOBBY_TYPE:
#   Determines what kind of Steam lobby we create.
#
# FRIENDS_ONLY means that the lobby is restricted to Steam friends.
#
# MAX_MEMBERS:
#   Our game supports 1-4 players, so we set the maximum to 4.
# ============================================================================

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4


# ============================================================================
# MULTIPLAYER PEER
# ============================================================================
# A MultiplayerPeer is the object Godot uses to communicate with the other
# players.
#
# SteamMultiplayerPeer is provided by GodotSteam.
#
# We don't create it immediately because we don't have a connection yet.
# It will be created when we actually host or join a lobby.
# ============================================================================

var peer: SteamMultiplayerPeer


# ============================================================================
# _ready()
# ============================================================================
# _ready() is called once when NetworkManager enters the scene tree.
#
# Because NetworkManager will be an Autoload, this effectively happens when
# the game starts.
# ============================================================================

func _ready() -> void:

	# ------------------------------------------------------------------------
	# Initialize Steam Relay Networking
	# ------------------------------------------------------------------------
	# Steam's relay system allows players to communicate through Steam's
	# networking infrastructure without us having to manually deal with
	# IP addresses and port forwarding.
	#
	# This is particularly useful for a Steam game where one player acts
	# as the host.
	# ------------------------------------------------------------------------

	Steam.initRelayNetworkAccess()


	# ------------------------------------------------------------------------
	# Connect Steam signals
	# ------------------------------------------------------------------------
	# Steam is going to notify us when certain things happen.
	#
	# For example:
	#
	# Steam.createLobby()
	#       ↓
	# Steam creates the lobby
	#       ↓
	# Steam emits "lobby_created"
	#       ↓
	# _on_lobby_created() is called
	#
	# We connect those Steam signals to our functions here.
	# ------------------------------------------------------------------------

	Steam.lobby_created.connect(_on_lobby_created)

	Steam.lobby_joined.connect(_on_lobby_joined)

	Steam.join_requested.connect(_on_join_requested)



# ============================================================================
# _process()
# ============================================================================
# _process() runs once every frame.
#
# Steam requires us to process its callbacks regularly so that Steam can
# notify our game about things that have happened.
#
# IMPORTANT:
# We only want ONE place in our project calling Steam.run_callbacks().
#
# That's why NetworkManager is a good place for it.
# ============================================================================

func _process(_delta: float) -> void:

	# Tell Steam to process any waiting Steam events/callbacks.
	Steam.run_callbacks()



# ============================================================================
# HOST LOBBY
# ============================================================================
# This function is what we'll eventually call when the player clicks:
#
#              [ HOST GAME ]
#
# Notice that this function doesn't actually create the multiplayer peer.
#
# It first asks Steam to create the lobby.
#
# Steam will then call _on_lobby_created() when that operation finishes.
# ============================================================================

func host_lobby() -> void:

	# Ask Steam to create a friends-only lobby with a maximum of 4 players.
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)



# ============================================================================
# STEAM: LOBBY CREATED
# ============================================================================
# This function is called by Steam after we request a lobby.
#
# Steam gives us two important pieces of information:
#
#   connect
#       Whether the operation succeeded or failed.
#
#   lobby_id
#       The unique Steam ID for the lobby.
# ============================================================================

func _on_lobby_created(connected: int, lobby_id: int) -> void:

	# ------------------------------------------------------------------------
	# Check whether Steam successfully created the lobby.
	# ------------------------------------------------------------------------
	# Steam.RESULT_OK means everything worked.
	#
	# If it didn't work, we don't want to continue creating our multiplayer
	# connection.
	# ------------------------------------------------------------------------

	if connected != Steam.RESULT_OK:

		print("Failed to create Steam lobby. Result: ", connect)

		return


	# If we reach this point, the lobby was successfully created.

	print("Steam lobby created: ", lobby_id)



	# =========================================================================
	# CREATE THE HOST'S MULTIPLAYER PEER
	# =========================================================================
	# Now that Steam has created our lobby, we need to tell Godot:
	#
	# "This computer is going to be the multiplayer host."
	#
	# SteamMultiplayerPeer handles the actual networking connection.
	# =========================================================================

	peer = SteamMultiplayerPeer.new()


	# ------------------------------------------------------------------------
	# server_relay
	# ------------------------------------------------------------------------
	# Tell SteamMultiplayerPeer to use Steam's relay networking.
	#
	# This allows Steam to handle the networking connection between players.
	# ------------------------------------------------------------------------

	peer.server_relay = true


	# ------------------------------------------------------------------------
	# create_host()
	# ------------------------------------------------------------------------
	# This computer becomes the multiplayer server/host.
	#
	# Remember:
	#
	# HOST
	#   └── also plays the game
	#
	# CLIENT
	#   └── connects to the host
	#
	# For our 1-4 player game, one of the players will always be the host.
	# ------------------------------------------------------------------------

	peer.create_host()


	# ------------------------------------------------------------------------
	# Give Godot the multiplayer peer
	# ------------------------------------------------------------------------
	# Until this line, Godot doesn't actually have a multiplayer connection.
	#
	# This line effectively says:
	#
	# "Godot, use this Steam connection for multiplayer."
	# ------------------------------------------------------------------------

	multiplayer.multiplayer_peer = peer


	# ------------------------------------------------------------------------
	# Tell the rest of our game that hosting is ready.
	# ------------------------------------------------------------------------
	# NetworkManager doesn't need to know what happens next.
	#
	# The GameManager or LevelManager can listen for this signal and decide
	# what to do next.
	#
	# For example:
	#
	#   Host created
	#       ↓
	#   GameManager receives signal
	#       ↓
	#   LevelManager loads the game level
	#       ↓
	#   LevelManager spawns the host player
	# ------------------------------------------------------------------------

	host_created.emit()



# ============================================================================
# STEAM: LOBBY JOINED
# ============================================================================
# Steam calls this function when somebody successfully joins a lobby.
#
# This can happen because:
#
#   1. We joined somebody else's lobby.
#
#   2. Steam launched our game because somebody invited us.
#
# Steam provides several pieces of information.
#
# We only need the lobby_id and response for now.
# ============================================================================

func _on_lobby_joined(
	lobby_id: int,
	_permission: int,
	_locked: bool,
	response: int
) -> void:


	# ------------------------------------------------------------------------
	# Make sure joining the lobby succeeded.
	# ------------------------------------------------------------------------

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:

		print("Failed to join Steam lobby. Response: ", response)

		return


	print("Joined Steam lobby: ", lobby_id)



	# =========================================================================
	# ARE WE THE HOST?
	# =========================================================================
	# There is an important special case.
	#
	# When the host creates a Steam lobby, Steam also considers the host to
	# have "joined" that lobby.
	#
	# Therefore, the host can potentially receive lobby_joined as well.
	#
	# We don't want the host to create a client connection to itself!
	#
	# So we compare:
	#
	#   Steam.getLobbyOwner(lobby_id)
	#
	# against:
	#
	#   Steam.getSteamID()
	#
	# If they are the same person, we're the lobby owner.
	# ==========================================================================

	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():

		# We're already hosting this lobby.
		return



	# =========================================================================
	# CREATE THE CLIENT'S MULTIPLAYER PEER
	# =========================================================================
	# We aren't the lobby owner, so we're joining somebody else's game.
	#
	# Therefore this computer needs to become a multiplayer CLIENT.
	# =========================================================================

	peer = SteamMultiplayerPeer.new()


	# Use Steam relay networking.

	peer.server_relay = true


	# ------------------------------------------------------------------------
	# Connect to the Steam ID of the lobby owner.
	# ------------------------------------------------------------------------
	# The lobby owner is our multiplayer host.
	# ------------------------------------------------------------------------

	peer.create_client(Steam.getLobbyOwner(lobby_id))


	# Give Godot the new client connection.

	multiplayer.multiplayer_peer = peer


	# Tell the rest of the game that we've successfully joined the lobby.

	lobby_joined.emit(lobby_id)



# ============================================================================
# STEAM: JOIN REQUESTED
# ============================================================================
# Steam can ask our game to join a lobby.
#
# For example:
#
# Player A is playing our game.
#
# Player B opens their Steam friends list and joins Player A's game.
#
# Steam can launch Player B's game and provide the lobby ID.
#
# Steam then calls this function.
# ============================================================================

func _on_join_requested(lobby_id: int, _steam_id: int) -> void:

	# Tell Steam to join the requested lobby.
	#
	# Once Steam finishes joining it, our _on_lobby_joined() function
	# will be called automatically.

	Steam.joinLobby(lobby_id)
