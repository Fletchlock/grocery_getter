extends Control


@onready var lobby_list: VBoxContainer = $VBoxContainer/ScrollContainer/LobbyList
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var refresh_button: Button = $VBoxContainer/ButtonRow/RefreshButton
@onready var back_button: Button = $VBoxContainer/ButtonRow/BackButton


func _ready() -> void:
	NetworkManager.lobby_search_finished.connect(_on_lobby_search_finished)

	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_refresh_lobbies()


func _exit_tree() -> void:
	if NetworkManager.lobby_search_finished.is_connected(_on_lobby_search_finished):
		NetworkManager.lobby_search_finished.disconnect(_on_lobby_search_finished)


func _refresh_lobbies() -> void:
	for child: Node in lobby_list.get_children():
		child.queue_free()

	status_label.text = "Searching for games..."
	refresh_button.disabled = true

	NetworkManager.search_lobbies()


func _on_lobby_search_finished(lobbies: Array[Dictionary]) -> void:
	refresh_button.disabled = false

	if lobbies.is_empty():
		status_label.text = "No available games found."
		return

	status_label.text = "%d game(s) found" % lobbies.size()

	for session: Dictionary in lobbies:
		_add_lobby_row(session)


func _add_lobby_row(session: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	lobby_list.add_child(row)

	var host_label: Label = Label.new()
	host_label.custom_minimum_size.x = 260.0
	host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_label.text = str(session["host_name"])
	row.add_child(host_label)

	var players_label: Label = Label.new()
	players_label.custom_minimum_size.x = 90.0
	players_label.text = "%d/%d" % [
		int(session["players"]),
		int(session["max_players"])
	]
	row.add_child(players_label)

	var status: String = str(session["status"])
	var status_label_row: Label = Label.new()
	status_label_row.custom_minimum_size.x = 130.0
	status_label_row.text = "Playing" if status == "playing" else "In Lobby"
	row.add_child(status_label_row)

	var join_button: Button = Button.new()
	join_button.custom_minimum_size.x = 110.0

	var lobby_id: int = int(session["lobby_id"])
	var is_full: bool = int(session["players"]) >= int(session["max_players"])

	join_button.text = "Full" if is_full else "Join"
	join_button.disabled = is_full
	join_button.pressed.connect(_on_join_pressed.bind(lobby_id))

	row.add_child(join_button)


func _on_join_pressed(lobby_id: int) -> void:
	print("LobbyBrowser: Joining lobby ", lobby_id)

	NetworkManager.join_lobby(lobby_id)


func _on_refresh_pressed() -> void:
	_refresh_lobbies()


func _on_back_pressed() -> void:
	var main: Node = get_parent().get_parent()

	main.close_lobby_browser()
