extends Node


# ============================================================================
# CURRENT LEVEL
# ============================================================================
# Keeps a reference to the level currently loaded into the game.
#
# If we load another level later, we can remove the old one first.
# ============================================================================

var current_level: Node = null


# ============================================================================
# PLAYER SCENE
# ============================================================================
# This is the scene that will be instantiated when we need to create a player.
#
# We're using the same player scene you already have:
#
#     res://scenes/low_poly_character.tscn
#
# preload() loads the PackedScene ahead of time so we can instantiate it
# whenever we need it.
# ============================================================================

const PLAYER_SCENE := preload("res://scenes/low_poly_character.tscn")


# ============================================================================
# LOAD LEVEL
# ============================================================================
# Loads a level into the Game node.
# ============================================================================

func load_level(level_path: String) -> void:

	# ------------------------------------------------------------------------
	# Remove the currently loaded level, if there is one.
	# ------------------------------------------------------------------------

	if current_level:
		current_level.queue_free()
		current_level = null


	# ------------------------------------------------------------------------
	# Load the requested level scene.
	# ------------------------------------------------------------------------

	var level_scene := load(level_path) as PackedScene


	# Make sure the level actually loaded.

	if level_scene == null:
		push_error("Could not load level: " + level_path)
		return


	# ------------------------------------------------------------------------
	# Create an instance of the level.
	# ------------------------------------------------------------------------
	# At this point the level exists in memory, but isn't yet part of the
	# running scene tree.
	# ------------------------------------------------------------------------

	current_level = level_scene.instantiate()


	# ------------------------------------------------------------------------
	# Find our Game node.
	# ------------------------------------------------------------------------
	# Your current project structure has the loaded level placed underneath
	# the Game node.
	# ------------------------------------------------------------------------

	var main := get_tree().current_scene
	var game := main.get_node("Game")


	# ------------------------------------------------------------------------
	# Add the level to the Game node.
	# ------------------------------------------------------------------------

	game.add_child(current_level)


	# ------------------------------------------------------------------------
	# Spawn the local player.
	# ------------------------------------------------------------------------
	# We wait until the level has been added to the scene tree before trying
	# to find PlayerSpawnPoint.
	# ------------------------------------------------------------------------

	spawn_player()



# ============================================================================
# SPAWN PLAYER
# ============================================================================
# Creates a Player scene and places it at the level's spawn point.
#
# For now we're only spawning the host's player.
#
# Networking this player will come in the next step.
# ============================================================================

func spawn_player() -> void:

	print("PLAYER SPAWN: Starting")

	# Create the Player scene.
	var player := PLAYER_SCENE.instantiate()

	# The multiplayer peer ID identifies the computer that owns
	# this Player.
	var peer_id := multiplayer.get_unique_id()

	# Give the Player a name corresponding to its peer ID.
	player.name = str(peer_id)

	# Add the Player to the level.
	current_level.add_child(player)

	print("PLAYER SPAWN: Player added to level")

	# Explicitly assign multiplayer authority.
	#
	# This tells Godot:
	#
	#     "Peer X is responsible for controlling this Player."
	#
	player.set_multiplayer_authority(peer_id)
	player.setup_local_player()

	print(
		"PLAYER SPAWN: Authority assigned to peer ",
		peer_id
	)

	# Find the spawn point.
	var spawn_point := current_level.get_node("PlayerSpawnPoint") as Marker3D

	# Place the Player at the spawn point.
	player.global_transform = spawn_point.global_transform

	print("PLAYER SPAWN: Player positioned")
