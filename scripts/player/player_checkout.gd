
extends Node
class_name PlayerCheckout


# ============================================================
# CONSTANTS
# ============================================================

const CHECKOUT_POINTER_TEXTURE: Texture2D = preload(
	"res://assets/images/hand_pointer_32px.png"
)


# ============================================================
# CHECKOUT POINTER STATE
# ============================================================

var checkout_pointer_layer: CanvasLayer = null
var checkout_pointer: Sprite2D = null


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


func update_checkout_pointer(
	checkout_mode_active: bool,
	holding_checkout_product: bool,
	rotating_held_product: bool,
	checkout_virtual_mouse_position: Vector2
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
