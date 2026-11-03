
extends PanelContainer
class_name ProductUnlockNotification

signal removal_finished

@export_group("Animation")
@export var slide_duration: float = 0.35
@export var collapse_duration: float = 0.25
@export var slide_distance: float = 400.0

const BG_GREEN: Texture2D = preload(
	"res://assets/images/order_notify_bg_green.png"
)

const TEXTURE_MARGIN: float = 13.0

@onready var notification_label: Label = $Label

var animation_tween: Tween = null
var is_removing: bool = false


func _ready() -> void:
	offset_transform_enabled = true
	offset_transform_position.x = slide_distance

	_set_background(BG_GREEN)


func setup(product_name: String) -> void:
	notification_label.text = "NEW PRODUCT UNLOCKED!\n%s" % product_name


func _set_background(texture: Texture2D) -> void:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture

	style.texture_margin_left = TEXTURE_MARGIN
	style.texture_margin_top = TEXTURE_MARGIN
	style.texture_margin_right = TEXTURE_MARGIN
	style.texture_margin_bottom = TEXTURE_MARGIN

	style.axis_stretch_horizontal = (
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)
	style.axis_stretch_vertical = (
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)

	add_theme_stylebox_override("panel", style)


func slide_in() -> void:
	if is_removing:
		return

	if animation_tween != null:
		animation_tween.kill()

	animation_tween = create_tween()
	animation_tween.set_trans(Tween.TRANS_CUBIC)
	animation_tween.set_ease(Tween.EASE_OUT)

	animation_tween.tween_property(
		self,
		"offset_transform_position:x",
		0.0,
		slide_duration
	)


func slide_out() -> void:
	if is_removing:
		return

	is_removing = true

	if animation_tween != null:
		animation_tween.kill()

	animation_tween = create_tween()
	animation_tween.set_trans(Tween.TRANS_CUBIC)
	animation_tween.set_ease(Tween.EASE_IN)

	animation_tween.tween_property(
		self,
		"offset_transform_position:x",
		slide_distance,
		slide_duration
	)

	await animation_tween.finished

	removal_finished.emit()
