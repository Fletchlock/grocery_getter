extends Node

@export var fade_duration: float = 5.0
@export var fade_exponent: float = 5.0

var fade_tween: Tween


func _ready() -> void:
	await get_tree().process_frame

	var ship_root: Node = get_parent()
	var ship_lights: Array[Light3D] = []

	_collect_lights(ship_root, ship_lights)

	print("Ship lights found: ", ship_lights.size())

	fade_tween = create_tween()
	fade_tween.set_parallel(true)

	for light in ship_lights:
		var target_energy: float = light.light_energy

		light.light_energy = 0.0

		fade_tween.tween_method(
			func(progress: float):
				light.light_energy = target_energy * pow(
					progress,
					fade_exponent
				),
			0.0,
			1.0,
			fade_duration
		)


func stop_fade() -> void:
	if fade_tween != null and fade_tween.is_running():
		fade_tween.kill()


func _collect_lights(node: Node, lights: Array[Light3D]) -> void:
	if node is Light3D:
		lights.append(node)

	for child in node.get_children():
		_collect_lights(child, lights)
