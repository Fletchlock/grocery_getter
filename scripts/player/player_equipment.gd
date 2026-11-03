
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
