extends Node


@export_group("Spill Events")
@export_range(0.0, 100.0, 1.0) var spill_chance: float = 100.0
@export var spill_cooldown: float = 0.0
@export var max_active_spills: int = 2

var active_spills: int = 0
var spill_cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if spill_cooldown_remaining > 0.0:
		spill_cooldown_remaining = maxf(
			spill_cooldown_remaining - delta,
			0.0
		)


func on_shopper_at_point(
	shopper: ShopperAI,
	shopping_point: Node3D
) -> void:
	if not multiplayer.is_server():
		return

	if not DayManager.store_open:
		return

	if not is_instance_valid(shopper):
		return

	if not is_instance_valid(shopping_point):
		return

	if spill_cooldown_remaining > 0.0:
		return

	if active_spills >= max_active_spills:
		return

	if randf() * 100.0 >= spill_chance:
		return

	spill_cooldown_remaining = spill_cooldown

	print(
		"EVENT MANAGER: Spill triggered by ",
		shopper.name,
		" at ",
		shopping_point.name
	)
