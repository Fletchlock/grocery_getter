extends Control


@onready var clock_label: Label = $TopCenterContainer/VBoxContainer/PanelContainer/ClockLabel
@onready var panel_container_2: PanelContainer = $TopCenterContainer/VBoxContainer/PanelContainer2




func _ready() -> void:
	DayManager.clock_updated.connect(_on_clock_updated)

	# Display the current clock immediately, in case the clock
	# was synchronized before this HUD finished loading.
	_on_clock_updated(
		DayManager.current_day,
		DayManager.current_hour,
		DayManager.current_minute
	)


func _exit_tree() -> void:
	if DayManager.clock_updated.is_connected(_on_clock_updated):
		DayManager.clock_updated.disconnect(_on_clock_updated)


func _on_clock_updated(
	day: int,
	hour: int,
	minute: int
) -> void:
	var period: String = "AM"
	var display_hour: int = hour

	if display_hour >= 12:
		period = "PM"

	if display_hour == 0:
		display_hour = 12
	elif display_hour > 12:
		display_hour -= 12

	clock_label.text = "DAY: %02d    TIME: %02d:%02d %s" % [
		day,
		display_hour,
		minute,
		period
	]

	# Turn the clock out panel to visible when the day is done.
	panel_container_2.modulate.a = 1.0 if not DayManager.clock_running else 0.0
	
