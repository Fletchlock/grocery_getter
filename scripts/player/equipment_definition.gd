
extends Resource
class_name EquipmentDefinition

enum HandRequirement {
	LEFT,
	RIGHT,
	BOTH
}

@export_group("Identity")
@export var equipment_id: StringName = &""
@export var display_name: String = ""

@export_group("Visual")
@export var visual_scene: PackedScene
@export var attachment_position: Vector3 = Vector3.ZERO
@export var attachment_rotation: Vector3 = Vector3.ZERO
@export var attachment_scale: Vector3 = Vector3.ONE

@export_group("Hands")
@export var required_hands: HandRequirement = HandRequirement.RIGHT


func get_attachment_transform() -> Transform3D:
	var attachment_basis: Basis = Basis.from_euler(
		Vector3(
			deg_to_rad(attachment_rotation.x),
			deg_to_rad(attachment_rotation.y),
			deg_to_rad(attachment_rotation.z)
		)
	)

	attachment_basis = attachment_basis.scaled(attachment_scale)

	return Transform3D(
		attachment_basis,
		attachment_position
	)
