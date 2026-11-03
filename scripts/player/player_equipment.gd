
class_name PlayerEquipment
extends Node

enum Hand {
	NONE,
	LEFT,
	RIGHT,
	BOTH
}

signal equipment_changed

var left_equipment: Node = null
var right_equipment: Node = null


# === Hand Targets ===

@export_group("Hand Target Settings")
@export var crouch_hand_offset: float = -0.35
@export var crouch_hand_lerp_speed: float = 10.0

@onready var held_item_target: Node3D = $"../Armature/HeldItemTarget"
@onready var held_item_hand_target: Node3D = $"../Armature/HeldItemHandTarget"
@onready var held_box_hand_target_left: Node3D = $"../Armature/HeldBoxHandTargetLeft"
@onready var held_box_hand_target_right: Node3D = $"../Armature/HeldBoxHandTargetRight"

var standing_item_target_position: Vector3
var standing_hand_target_position: Vector3
var standing_box_hand_target_left_position: Vector3
var standing_box_hand_target_right_position: Vector3

# === Hand IK Management ===

@onready var left_hand_ik: TwoBoneIK3D = $"../Armature/Skeleton3D/LeftTwoBoneIK3D"
@onready var right_hand_ik: TwoBoneIK3D = $"../Armature/Skeleton3D/RightTwoBoneIK3D"


func _ready() -> void:
	standing_item_target_position = held_item_target.position
	standing_hand_target_position = held_item_hand_target.position
	standing_box_hand_target_left_position = held_box_hand_target_left.position
	standing_box_hand_target_right_position = held_box_hand_target_right.position


# Hand Target Functions

func update_hand_targets(delta: float, is_crouching: bool) -> void:
	var offset: Vector3 = Vector3.ZERO

	if is_crouching:
		offset.y = crouch_hand_offset

	var weight: float = 1.0 - exp(
		-crouch_hand_lerp_speed * delta
	)

	held_item_target.position = held_item_target.position.lerp(
		standing_item_target_position + offset,
		weight
	)

	held_item_hand_target.position = held_item_hand_target.position.lerp(
		standing_hand_target_position + offset,
		weight
	)

	held_box_hand_target_left.position = held_box_hand_target_left.position.lerp(
		standing_box_hand_target_left_position + offset,
		weight
	)

	held_box_hand_target_right.position = held_box_hand_target_right.position.lerp(
		standing_box_hand_target_right_position + offset,
		weight
	)

func set_hand_ik(hand: Hand, target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	match hand:
		Hand.LEFT:
			_assign_ik_target(left_hand_ik, target)

		Hand.RIGHT:
			_assign_ik_target(right_hand_ik, target)


func set_both_hand_ik(
	left_target: Node3D,
	right_target: Node3D
) -> void:
	if not is_instance_valid(left_target):
		return

	if not is_instance_valid(right_target):
		return

	_assign_ik_target(left_hand_ik, left_target)
	_assign_ik_target(right_hand_ik, right_target)


func clear_hand_ik(hand: Hand) -> void:
	match hand:
		Hand.LEFT:
			_clear_ik_target(left_hand_ik)

		Hand.RIGHT:
			_clear_ik_target(right_hand_ik)

		Hand.BOTH:
			_clear_ik_target(left_hand_ik)
			_clear_ik_target(right_hand_ik)


# IK Functions

func _assign_ik_target(
	ik: TwoBoneIK3D,
	target: Node3D
) -> void:
	if not is_instance_valid(ik):
		return

	ik.set_target_node(0, target.get_path())
	ik.influence = 1.0


func _clear_ik_target(ik: TwoBoneIK3D) -> void:
	if not is_instance_valid(ik):
		return

	ik.influence = 0.0
	ik.set_target_node(0, NodePath(""))


# General Equip Functions.

func can_equip(hand: Hand) -> bool:
	match hand:
		Hand.LEFT:
			return left_equipment == null

		Hand.RIGHT:
			return right_equipment == null

		Hand.BOTH:
			return left_equipment == null and right_equipment == null

	return false


func equip(equipment: Node, hand: Hand) -> bool:
	if not is_instance_valid(equipment):
		return false

	if not can_equip(hand):
		return false

	match hand:
		Hand.LEFT:
			left_equipment = equipment

		Hand.RIGHT:
			right_equipment = equipment

		Hand.BOTH:
			left_equipment = equipment
			right_equipment = equipment

	equipment_changed.emit()
	return true


func unequip(equipment: Node) -> void:
	var changed: bool = false

	if left_equipment == equipment:
		left_equipment = null
		changed = true

	if right_equipment == equipment:
		right_equipment = null
		changed = true

	if changed:
		equipment_changed.emit()


func is_holding_anything() -> bool:
	return left_equipment != null or right_equipment != null


func is_holding(equipment: Node) -> bool:
	return left_equipment == equipment or right_equipment == equipment


func get_equipment_hand(equipment: Node) -> Hand:
	var in_left: bool = left_equipment == equipment
	var in_right: bool = right_equipment == equipment

	if in_left and in_right:
		return Hand.BOTH

	if in_left:
		return Hand.LEFT

	if in_right:
		return Hand.RIGHT

	return Hand.NONE
