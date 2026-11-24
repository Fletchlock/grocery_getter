
extends Node
class_name AlienAppearance


@export var appearance_data: AlienAppearanceData

enum ClothingColor {
	BLACK,
	RED,
	GREEN,
	BLUE,
	YELLOW,
	BROWN,
	ORANGE,
	WHITE,
	GREY
}

const CLOTHING_COLORS: Array[Color] = [
	Color("#202020"), # Black 0
	Color("#c83a3a"), # Red 1
	Color("#459b55"), # Green 2
	Color("#377ac4"), # Blue 3
	Color("#e8c63b"), # Yellow 4
	Color("#795438"), # Brown 5
	Color("#e78b35"), # Orange 6
	Color("#f1f1ed"), # White 7
	Color("#888888")  # Grey 8
]

var top_color: int = ClothingColor.WHITE
var bottom_color: int = ClothingColor.BLUE
var feet_color: int = ClothingColor.BLACK
var sole_color: int = ClothingColor.WHITE

@export var default_skin_color: Color = Color("#40bf59")
@export var default_pattern_color: Color = Color("#0d401a")

var skin_color: Color
var pattern_color: Color

var skin_material: ShaderMaterial

@export_group("Eye Customization")
@export var default_pupil_color: Color = Color("#240c38")

@export_group("Lip Customization")
@export var lips_use_skin_color: bool = true
@export var default_lip_color: Color = Color("#c95b86")

var pupil_color: Color
var lip_color: Color

var pupil_material: StandardMaterial3D
var lip_material: StandardMaterial3D

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
	set_top_color(top_color)
	set_bottom_color(bottom_color)
	set_feet_color(feet_color)
	set_sole_color(sole_color)
	_setup_skin_material()
	_setup_face_materials()
	
	set_top_color(ClothingColor.ORANGE)
	set_bottom_color(ClothingColor.BLUE)
	set_feet_color(ClothingColor.BROWN)
	set_sole_color(ClothingColor.BLACK)
	
	if appearance_data != null:
		apply_appearance(appearance_data)
	


func _process(_delta: float) -> void:
	_sync_blink()


func set_head_style(index: int) -> void:
	if head == null:
		return

	if index == -1:
		head.visible = false
		return

	head.visible = true
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
	
	if slot == head:
		_update_head_material()
	
	if slot == top:
		set_top_color(top_color)
	elif slot == bottom:
		set_bottom_color(bottom_color)
	elif slot == feet:
		set_feet_color(feet_color)
		set_sole_color(sole_color)

	if slot == top or slot == bottom:
		_apply_weight_to_mesh(slot)

func set_body_weight(value: float) -> void:
	body_weight = clampf(value, 0.0, 1.0)

	print("BODY: ", body)
	print("TOP: ", top)
	print("BOTTOM: ", bottom)

	if body != null and body.mesh != null:
		print("Body blend shapes: ", body.mesh.get_blend_shape_count())

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


func _set_surface_color(
	target: MeshInstance3D,
	surface_index: int,
	color_index: int
) -> void:
	if target == null or target.mesh == null:
		return

	if color_index < 0 or color_index >= CLOTHING_COLORS.size():
		push_warning("Invalid clothing color index: %d" % color_index)
		return

	if surface_index < 0 or surface_index >= target.mesh.get_surface_count():
		return

	var source_material: Material = target.mesh.surface_get_material(surface_index)

	if not source_material is StandardMaterial3D:
		return

	var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
	material.albedo_color = CLOTHING_COLORS[color_index]

	target.set_surface_override_material(surface_index, material)
	
	
func set_top_color(color_index: int) -> void:
	top_color = color_index
	_set_surface_color(top, 0, top_color)


func set_bottom_color(color_index: int) -> void:
	bottom_color = color_index
	_set_surface_color(bottom, 0, bottom_color)


func set_feet_color(color_index: int) -> void:
	feet_color = color_index
	_set_surface_color(feet, 0, feet_color)


func set_sole_color(color_index: int) -> void:
	sole_color = color_index
	_set_surface_color(feet, 1, sole_color)


func _setup_skin_material() -> void:
	if body == null:
		return

	var source_material: Material = body.get_active_material(0)

	if not source_material is ShaderMaterial:
		push_warning("AlienBody Surface 0 requires a ShaderMaterial.")
		return

	skin_material = source_material.duplicate() as ShaderMaterial
	body.set_surface_override_material(0, skin_material)

	skin_color = default_skin_color
	pattern_color = default_pattern_color

	set_skin_color(skin_color)
	set_pattern_color(pattern_color)
	_update_head_material()


func set_skin_color(color: Color) -> void:
	skin_color = color

	if skin_material != null:
		skin_material.set_shader_parameter("skin_color", skin_color)

	if lips_use_skin_color:
		_update_lip_color()


func set_pattern_color(color: Color) -> void:
	pattern_color = color

	if skin_material != null:
		skin_material.set_shader_parameter("pattern_color", pattern_color)


func _update_head_material() -> void:
	if head == null or head.mesh == null:
		return

	if skin_material == null:
		return

	head.set_surface_override_material(0, skin_material)


func _setup_face_materials() -> void:
	if body == null:
		return

	var pupil_source: Material = body.get_active_material(2)
	var lip_source: Material = body.get_active_material(3)

	if pupil_source is StandardMaterial3D:
		pupil_material = pupil_source.duplicate() as StandardMaterial3D
		body.set_surface_override_material(2, pupil_material)

	if lip_source is StandardMaterial3D:
		lip_material = lip_source.duplicate() as StandardMaterial3D
		body.set_surface_override_material(3, lip_material)

	pupil_color = default_pupil_color
	lip_color = default_lip_color

	set_pupil_color(pupil_color)
	_update_lip_color()
	

func set_pupil_color(color: Color) -> void:
	pupil_color = color

	if pupil_material != null:
		pupil_material.albedo_color = pupil_color


func set_lip_color(color: Color) -> void:
	lip_color = color
	_update_lip_color()


func set_lips_use_skin_color(enabled: bool) -> void:
	lips_use_skin_color = enabled
	_update_lip_color()


func _update_lip_color() -> void:
	if lip_material == null:
		return

	if lips_use_skin_color:
		lip_material.albedo_color = skin_color
	else:
		lip_material.albedo_color = lip_color


func apply_appearance(data: AlienAppearanceData) -> void:
	if data == null:
		return

	set_body_weight(data.body_weight)

	set_skin_color(data.skin_color)
	set_pattern_color(data.pattern_color)

	set_pupil_color(data.pupil_color)
	set_lip_color(data.lip_color)
	set_lips_use_skin_color(data.lips_use_skin_color)
	set_eyelashes_enabled(data.eyelashes_enabled)

	set_head_style(data.head_style)
	set_top_style(data.top_style)
	set_bottom_style(data.bottom_style)
	set_feet_style(data.feet_style)

	set_top_color(data.top_color)
	set_bottom_color(data.bottom_color)
	set_feet_color(data.feet_color)
	set_sole_color(data.sole_color)
