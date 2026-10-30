
extends PanelContainer
class_name OrderNotification

signal removal_finished

@export_group("Animation")
@export var slide_duration: float = 0.35
@export var collapse_duration: float = 0.25
@export var slide_distance: float = 400.0
@export var result_display_duration: float = 4.0

const BG_GREEN: Texture2D = preload("res://assets/images/order_notify_bg_green.png")
const BG_BLUE: Texture2D = preload("res://assets/images/order_notify_bg_blue.png")
const BG_GREY: Texture2D = preload("res://assets/images/order_notify_bg_grey.png")
const BG_RED: Texture2D = preload("res://assets/images/order_notify_bg_red.png")

const TEXTURE_MARGIN: float = 13.0

@onready var notification_label: Label = $Label

var order_id: int = -1
var is_removing: bool = false
var animation_tween: Tween = null
var acceptance_deadline: int = -1
var result_displayed: bool = false
var current_background: Texture2D = null


func _ready() -> void:
	# Containers control layout, so animate the visual offset.
	offset_transform_enabled = true
	offset_transform_position.x = slide_distance

	# New available orders start green.
	_set_background(BG_GREEN)


func _set_background(texture: Texture2D) -> void:
	if current_background == texture:
		return

	current_background = texture

	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture

	style.texture_margin_left = TEXTURE_MARGIN
	style.texture_margin_top = TEXTURE_MARGIN
	style.texture_margin_right = TEXTURE_MARGIN
	style.texture_margin_bottom = TEXTURE_MARGIN

	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

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


func update_acceptance_countdown() -> void:
	if acceptance_deadline < 0:
		return

	var current_minute: int = (
		DayManager.current_hour * 60
		+ DayManager.current_minute
	)

	var remaining: int = maxi(
		acceptance_deadline - current_minute,
		0
	)

	var total_minutes: int = int(remaining)
	var hours: int = floori(remaining / 60.0)
	var minutes: int = total_minutes % 60

	notification_label.text = (
		"New Order - %dh%02dm"
		% [hours, minutes]
	)


func update_active_order(order: OrderData) -> void:
	if result_displayed:
		return

	# Accepted orders use the blue background.
	_set_background(BG_BLUE)

	var player_name: String = LobbyManager.get_player_name(
		order.accepted_by_peer_id
	)

	if player_name.is_empty():
		player_name = "Player %d" % order.accepted_by_peer_id

	var remaining: int = maxi(
		ceili(order.time_limit - order.elapsed_time),
		0
	)

	var total_seconds: int = int(remaining)
	var minutes: int = floori(remaining / 60.0)
	var seconds: int = total_seconds % 60

	notification_label.text = "Order %02d - %s - %dm%02ds" % [
		order.order_id,
		player_name,
		minutes,
		seconds
	]


func show_order_result(order: OrderData) -> void:
	if result_displayed:
		return

	result_displayed = true

	var player_name: String = LobbyManager.get_player_name(
		order.accepted_by_peer_id
	)

	if player_name.is_empty():
		player_name = "Player %d" % order.accepted_by_peer_id

	var result_text: String = ""
	var result_texture: Texture2D = BG_GREEN

	if order.state == OrderData.OrderState.COMPLETED:
		if order.elapsed_time <= order.time_limit:
			# Completed on time.
			var remaining: int = maxi(
				ceili(order.time_limit - order.elapsed_time),
				0
			)

			var total_seconds: int = int(remaining)
			var minutes: int = floori(remaining / 60.0)
			var seconds: int = total_seconds % 60

			result_text = "%dm%02ds" % [minutes, seconds]
			result_texture = BG_GREEN
		else:
			# Completed late, with reduced profit.
			var loss: float = maxf(
				order.base_profit - order.current_profit,
				0.0
			)

			result_text = "$%.2f Loss" % loss
			result_texture = BG_GREY

	elif order.state == OrderData.OrderState.CANCELLED:
		# Failed order loses its full original profit.
		result_text = "$%.2f Loss" % order.base_profit
		result_texture = BG_RED

	else:
		result_displayed = false
		return

	notification_label.text = "Order %02d - %s - %s" % [
		order.order_id,
		player_name,
		result_text
	]

	_set_background(result_texture)
