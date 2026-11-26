
extends Node
class_name PlayerCheckout


# ============================================================
# CONSTANTS
# ============================================================

const CHECKOUT_POINTER_TEXTURE: Texture2D = preload(
	"res://assets/images/hand_pointer_32px.png"
)


# ============================================================
# VIRTUAL CURSOR STATE
# ============================================================

var checkout_virtual_mouse_position: Vector2 = Vector2.ZERO
var checkout_virtual_mouse_initialized: bool = false
var checkout_last_mouse_position: Vector2 = Vector2.ZERO
var checkout_using_controller_cursor: bool = false


# ============================================================
# CHECKOUT POINTER STATE
# ============================================================

var checkout_pointer_layer: CanvasLayer = null
var checkout_pointer: Sprite2D = null


# ============================================================
# CURSOR INITIALIZATION
# ============================================================

func initialize_cursor() -> void:
	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	checkout_virtual_mouse_position = viewport_size * 0.5
	checkout_last_mouse_position = checkout_virtual_mouse_position
	checkout_virtual_mouse_initialized = true
	checkout_using_controller_cursor = false


func ensure_cursor_initialized() -> void:
	if checkout_virtual_mouse_initialized:
		return

	checkout_virtual_mouse_position = (
		get_viewport().get_mouse_position()
	)

	checkout_virtual_mouse_initialized = true


# ============================================================
# SHARED CURSOR MOVEMENT
# ============================================================

func _move_cursor(cursor_delta: Vector2) -> void:
	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	checkout_virtual_mouse_position += cursor_delta

	checkout_virtual_mouse_position = (
		checkout_virtual_mouse_position.clamp(
			Vector2.ZERO,
			viewport_size
		)
	)

	checkout_last_mouse_position = checkout_virtual_mouse_position


# ============================================================
# MOUSE CURSOR INPUT
# ============================================================

func handle_mouse_motion(
	event: InputEventMouseMotion,
	rotating_held_product: bool,
	mouse_sensitivity: float
) -> void:
	if rotating_held_product:
		return

	var mouse_delta: Vector2 = (
		event.screen_relative * mouse_sensitivity
	)

	if mouse_delta.length_squared() <= 0.0:
		return

	checkout_using_controller_cursor = false

	_move_cursor(mouse_delta)


func update_checkout_mouse_cursor(
	checkout_mode_active: bool
) -> void:
	if not checkout_mode_active:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	checkout_virtual_mouse_initialized = true


# ============================================================
# CONTROLLER CURSOR INPUT
# ============================================================

func update_checkout_controller_cursor(
	delta: float,
	is_local_player: bool,
	checkout_mode_active: bool,
	cursor_speed: float,
	controller_sensitivity: float
) -> void:
	if not is_local_player:
		return

	if not checkout_mode_active:
		return

	var stick_input: Vector2 = Input.get_vector(
		"checkout_cursor_left",
		"checkout_cursor_right",
		"checkout_cursor_up",
		"checkout_cursor_down"
	)

	if stick_input.length() < 0.15:
		return

	checkout_using_controller_cursor = true

	var cursor_delta: Vector2 = (
		stick_input
		* cursor_speed
		* controller_sensitivity
		* delta
	)

	_move_cursor(cursor_delta)

	checkout_virtual_mouse_initialized = true


# ============================================================
# CHECKOUT POINTER
# ============================================================

func create_checkout_pointer() -> void:
	if is_instance_valid(checkout_pointer_layer):
		return

	checkout_pointer_layer = CanvasLayer.new()
	checkout_pointer_layer.layer = 100
	add_child(checkout_pointer_layer)

	checkout_pointer = Sprite2D.new()
	checkout_pointer.texture = CHECKOUT_POINTER_TEXTURE
	checkout_pointer.centered = false
	checkout_pointer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	checkout_pointer_layer.add_child(checkout_pointer)


func remove_checkout_pointer() -> void:
	if is_instance_valid(checkout_pointer_layer):
		checkout_pointer_layer.queue_free()

	checkout_pointer_layer = null
	checkout_pointer = null

	checkout_using_controller_cursor = false


func update_checkout_pointer(
	checkout_mode_active: bool,
	holding_checkout_product: bool,
	rotating_held_product: bool
) -> void:
	if not checkout_mode_active:
		return

	if not is_instance_valid(checkout_pointer):
		return

	checkout_pointer.visible = (
		not holding_checkout_product
		and not rotating_held_product
	)

	checkout_pointer.position = checkout_virtual_mouse_position
