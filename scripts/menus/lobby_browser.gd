extends Control

@onready var lobby_list: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/LobbyList
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var refresh_button: Button = $PanelContainer/VBoxContainer/ButtonRow/RefreshButton
@onready var back_button: Button = $PanelContainer/VBoxContainer/ButtonRow/BackButton
@onready var join_button_template: Button = $PanelContainer/JoinButtonTemplate

@export_group("Lobby List Styling")
@export var lobby_font_size: int = 26
@export var join_font_size: int = 26
@export var row_separation: int = 20
@export var join_button_width: float = 140.0
@export var join_button_height: float = 50.0


func _ready() -> void:
	NetworkManager.lobby_search_finished.connect(_on_lobby_search_finished)
	
	join_button_template.hide()
	join_button_template.focus_mode = Control.FOCUS_NONE
	
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)

	refresh_button.focus_mode = Control.FOCUS_ALL
	back_button.focus_mode = Control.FOCUS_ALL

	_refresh_lobbies()


func _exit_tree() -> void:
	if NetworkManager.lobby_search_finished.is_connected(_on_lobby_search_finished):
		NetworkManager.lobby_search_finished.disconnect(_on_lobby_search_finished)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if event.is_echo():
		return

	get_viewport().set_input_as_handled()
	_on_back_pressed()


func _refresh_lobbies() -> void:
	for child: Node in lobby_list.get_children():
		child.queue_free()

	status_label.text = "Searching for games..."
	refresh_button.disabled = true

	back_button.grab_focus.call_deferred()

	NetworkManager.search_lobbies()


func _on_lobby_search_finished(lobbies: Array[Dictionary]) -> void:
	refresh_button.disabled = false

	if lobbies.is_empty():
		status_label.text = "No available games found."
	else:
		status_label.text = "%d game(s) found" % lobbies.size()

		for session: Dictionary in lobbies:
			_add_lobby_row(session)

	_setup_lobby_navigation()
	refresh_button.grab_focus.call_deferred()


func _add_lobby_row(session: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", row_separation)
	lobby_list.add_child(row)

	var host_label: Label = Label.new()
	host_label.custom_minimum_size.x = 260.0
	host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_label.text = str(session["host_name"])
	host_label.add_theme_font_size_override("font_size", lobby_font_size)
	row.add_child(host_label)

	var players_label: Label = Label.new()
	players_label.custom_minimum_size.x = 90.0
	players_label.text = "%d/%d" % [
		int(session["players"]),
		int(session["max_players"])
	]
	players_label.add_theme_font_size_override("font_size", lobby_font_size)
	row.add_child(players_label)

	var status: String = str(session["status"])
	var status_label_row: Label = Label.new()
	status_label_row.custom_minimum_size.x = 130.0
	status_label_row.text = "Playing" if status == "playing" else "In Lobby"
	status_label_row.add_theme_font_size_override("font_size", lobby_font_size)
	row.add_child(status_label_row)

	var join_button: Button = join_button_template.duplicate() as Button
	join_button.show()
	join_button.focus_mode = Control.FOCUS_ALL

	var lobby_id: int = int(session["lobby_id"])
	var is_full: bool = int(session["players"]) >= int(session["max_players"])

	join_button.text = "Full" if is_full else "Join"
	join_button.disabled = is_full
	if is_full:
		join_button.focus_mode = Control.FOCUS_NONE
	join_button.pressed.connect(_on_join_pressed.bind(lobby_id))

	row.add_child(join_button)
	join_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)


func _setup_lobby_navigation() -> void:
	var join_buttons: Array[Button] = []

	for row: Node in lobby_list.get_children():
		for child: Node in row.get_children():
			if child is Button:
				var button: Button = child as Button

				if not button.disabled:
					join_buttons.append(button)

	# Reset navigation.
	refresh_button.focus_neighbor_top = NodePath("")
	refresh_button.focus_neighbor_bottom = NodePath("")
	back_button.focus_neighbor_top = NodePath("")
	back_button.focus_neighbor_bottom = NodePath("")

	# Refresh and Back are next to each other.
	refresh_button.focus_neighbor_right = refresh_button.get_path_to(back_button)
	back_button.focus_neighbor_left = back_button.get_path_to(refresh_button)

	if join_buttons.is_empty():
		return

	# Refresh -> last available Join button.
	var last_button: Button = join_buttons.back()

	refresh_button.focus_neighbor_top = refresh_button.get_path_to(last_button)

	# Connect the Join buttons vertically.
	for i: int in range(join_buttons.size()):
		var button: Button = join_buttons[i]

		if i > 0:
			button.focus_neighbor_top = button.get_path_to(join_buttons[i - 1])

		if i < join_buttons.size() - 1:
			button.focus_neighbor_bottom = button.get_path_to(join_buttons[i + 1])
		else:
			button.focus_neighbor_bottom = button.get_path_to(refresh_button)

	# Back can also navigate upward to the list.
	back_button.focus_neighbor_top = back_button.get_path_to(last_button)


func _on_join_pressed(lobby_id: int) -> void:
	print("LobbyBrowser: Joining lobby ", lobby_id)

	NetworkManager.join_lobby(lobby_id)


func _on_refresh_pressed() -> void:
	_refresh_lobbies()


func _on_back_pressed() -> void:
	var main: Node = get_parent().get_parent()

	main.close_lobby_browser()
