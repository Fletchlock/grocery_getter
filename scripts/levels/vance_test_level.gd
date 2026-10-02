extends Node3D


const TABLET_MENU := "res://scenes/menus/tablet_menu.tscn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_order_hud"):
		_toggle_tablet_menu()

func _toggle_tablet_menu() -> void:
	var tablet_menu = get_node_or_null("UI/TabletMenu")

	if tablet_menu == null:
		var tablet_menu_scene := load(TABLET_MENU) as PackedScene

		if tablet_menu_scene == null:
			push_error("Could not load tablet menu")
			return

		tablet_menu = tablet_menu_scene.instantiate()
		$UI.add_child(tablet_menu)

	tablet_menu.get_node("CanvasLayer/OrderHUD")._toggle_hud()
