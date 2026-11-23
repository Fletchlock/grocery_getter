
extends Node
class_name AlienAppearance


@export_group("Character Meshes")
@export var body: MeshInstance3D
@export var eyelashes: MeshInstance3D
@export var head: MeshInstance3D
@export var top: MeshInstance3D
@export var bottom: MeshInstance3D
@export var feet: MeshInstance3D


@export_group("Head Options")
@export var head_meshes: Array[Mesh] = []

@export_group("Top Options")
@export var top_meshes: Array[Mesh] = []

@export_group("Bottom Options")
@export var bottom_meshes: Array[Mesh] = []

@export_group("Feet Options")
@export var feet_meshes: Array[Mesh] = []


@export_group("Default Appearance")
@export_range(0.0, 1.0, 0.01) var default_weight: float = 0.5
@export var default_eyelashes: bool = false


var body_weight: float = 0.5
var eyelashes_enabled: bool = false

func _test_shirt_switching() -> void:
	for i: int in top_meshes.size():
		set_top_style(i)
		print("Switched to shirt: ", i)
		await get_tree().create_timer(3.0).timeout

func _ready() -> void:
	body_weight = default_weight
	set_eyelashes_enabled(default_eyelashes)
	set_body_weight(body_weight)
	
	_test_shirt_switching()


func _process(_delta: float) -> void:
	_sync_blink()


func set_head_style(index: int) -> void:
	_set_equipment(head, head_meshes, index)


func set_top_style(index: int) -> void:
	_set_equipment(top, top_meshes, index)


func set_bottom_style(index: int) -> void:
	_set_equipment(bottom, bottom_meshes, index)


func set_feet_style(index: int) -> void:
	_set_equipment(feet, feet_meshes, index)


func _set_equipment(
	slot: MeshInstance3D,
	meshes: Array[Mesh],
	index: int
) -> void:
	if slot == null:
		return

	if index < 0 or index >= meshes.size():
		push_warning("Invalid equipment index: %d" % index)
		return

	if meshes[index] == null:
		push_warning("Equipment mesh is missing.")
		return

	slot.mesh = meshes[index]

	if slot == top or slot == bottom:
		_apply_weight_to_mesh(slot)


func set_body_weight(value: float) -> void:
	body_weight = clampf(value, 0.0, 1.0)

	_apply_weight_to_mesh(body)
	_apply_weight_to_mesh(top)
	_apply_weight_to_mesh(bottom)


func _apply_weight_to_mesh(target: MeshInstance3D) -> void:
	if target == null or target.mesh == null:
		return

	var slim: float = maxf(0.0, (0.5 - body_weight) * 2.0)
	var heavy: float = maxf(0.0, (body_weight - 0.5) * 2.0)

	_set_blend_shape(target, &"Slim", slim)
	_set_blend_shape(target, &"Heavy", heavy)


func _set_blend_shape(
	target: MeshInstance3D,
	shape_name: StringName,
	value: float
) -> void:
	if target == null or target.mesh == null:
		return

	var shape_count: int = target.mesh.get_blend_shape_count()

	for i: int in range(shape_count):
		if target.mesh.get_blend_shape_name(i) == shape_name:
			target.set_blend_shape_value(i, value)
			return


func set_eyelashes_enabled(enabled: bool) -> void:
	eyelashes_enabled = enabled

	if eyelashes != null:
		eyelashes.visible = enabled


func _sync_blink() -> void:
	if body == null or eyelashes == null:
		return

	if body.mesh == null or eyelashes.mesh == null:
		return

	var body_index: int = _get_blend_shape_index(body, &"Blink")
	var eyelash_index: int = _get_blend_shape_index(eyelashes, &"Blink")

	if body_index == -1 or eyelash_index == -1:
		return

	var blink_value: float = body.get_blend_shape_value(body_index)
	eyelashes.set_blend_shape_value(eyelash_index, blink_value)


func _get_blend_shape_index(
	target: MeshInstance3D,
	shape_name: StringName
) -> int:
	if target == null or target.mesh == null:
		return -1

	for i: int in range(target.mesh.get_blend_shape_count()):
		if target.mesh.get_blend_shape_name(i) == shape_name:
			return i

	return -1
