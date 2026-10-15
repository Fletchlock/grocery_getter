extends Control


@onready var clock_label: Label = $TopCenterContainer/VBoxContainer/PanelContainer/ClockLabel
@onready var panel_container_2: PanelContainer = $TopCenterContainer/VBoxContainer/PanelContainer2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var online_order_panel: PanelContainer = $OnlineOrderPanel
@onready var online_order_label: Label = $OnlineOrderPanel/OnlineOrderLabel

@export var online_order_slide_duration: float = 0.35
@export var online_order_right_margin: float = 20.0

var shopper_stats: Node3D = null
var online_order_tween: Tween
var online_order_visible: bool = false
var waiting_order_count: int = -1



func _ready() -> void:
	DayManager.clock_updated.connect(_on_clock_updated)

	# Display the current clock immediately, in case the clock
	# was synchronized before this HUD finished loading.
	_on_clock_updated(
		DayManager.current_day,
		DayManager.current_hour,
		DayManager.current_minute
	)
	
	OrderManager.orders_synced.connect(_update_online_order_panel)

	# Start offscreen without an animation.
	online_order_panel.position.x = size.x + online_order_panel.size.x
	_update_online_order_panel()
	

func _process(_delta: float) -> void:
	if shopper_stats == null or not is_instance_valid(shopper_stats):
		shopper_stats = get_tree().get_first_node_in_group("shopper_stats")
		if shopper_stats == null:
			return

	_update_clock_label()


func _exit_tree() -> void:
	if DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.disconnect(_on_clock_updated)


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	_update_clock_label()

	# Turn the clock out panel visible when the day is done.
	panel_container_2.modulate.a = 1.0 if not DayManager.clock_running else 0.0

	# Show the restock banner when the ordering window opens.
	if hour == 18 and minute == 0:
		animation_player.play("restock banner in")

	# Hide the restock banner when the ordering window closes.
	elif hour == 20 and minute == 0:
		animation_player.play("restock banner out")


func _update_clock_label() -> void:
	var hour: int = DayManager.current_hour
	var period: String = "AM"
	var display_hour: int = hour

	if display_hour >= 12:
		period = "PM"

	if display_hour == 0:
		display_hour = 12
	elif display_hour > 12:
		display_hour -= 12

	var store_cash: float = 0.0

	if shopper_stats != null and is_instance_valid(shopper_stats):
		store_cash = shopper_stats.total_sales

	clock_label.text = "DAY: %02d    TIME: %02d:%02d %s    $%.2f" % [
		DayManager.current_day,
		display_hour,
		DayManager.current_minute,
		period,
		store_cash
	]


func _on_order_changed(_order: OrderData) -> void:
	_update_online_order_panel()


func _update_online_order_panel() -> void:
	var count: int = 0

	for order: OrderData in OrderManager.get_orders():
		if order.state == OrderData.OrderState.WAITING:
			count += 1

	# No change means no new animation is needed.
	if count == waiting_order_count:
		return

	waiting_order_count = count

	online_order_label.text = "Online Order Available (%d)" % count

	if count > 0:
		_slide_online_order_panel(true)
	else:
		_slide_online_order_panel(false)


func _slide_online_order_panel(show_panel: bool) -> void:
	if online_order_visible == show_panel:
		return

	online_order_visible = show_panel

	if online_order_tween != null and online_order_tween.is_running():
		online_order_tween.kill()

	var target_x: float = size.x + online_order_panel.size.x

	if show_panel:
		target_x = (
			size.x
			- online_order_panel.size.x
			- online_order_right_margin
		)

	online_order_tween = create_tween()
	online_order_tween.set_trans(Tween.TRANS_CUBIC)
	online_order_tween.set_ease(Tween.EASE_OUT)

	online_order_tween.tween_property(
		online_order_panel,
		"position:x",
		target_x,
		online_order_slide_duration
	)
