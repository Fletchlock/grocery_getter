
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
var left_ik_owner: StringName = &""
var right_ik_owner: StringName = &""

# === Product Visuals ===
@onready var product_network_visual: MeshInstance3D = (
	$"../Armature/HeldItemTarget/HeldItemNetworkVisual"
)

# === Restock Scanner Visuals ===
const RESTOCK_SCANNER_SCENE: PackedScene = preload(
	"res://scenes/objects/terminals/restock_scanner.tscn"
)

var scanner_network_visual: Node3D = null

# === Restock Box Visuals ===
const RESTOCK_BOX_SCENE: PackedScene = preload(
	"res://scenes/items/restock_box.tscn"
)

@onready var restock_box_network_visual: Node3D = (
	$"../Armature/HeldItemTarget/HeldRestockBoxNetworkVisual"
)


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



# === IK Ownership ===
func can_claim_ik(
	equipment_owner: StringName,
	hand: Hand
) -> bool:
	if equipment_owner == &"":
		return false

	match hand:
		Hand.LEFT:
			return (
				left_ik_owner == &""
				or left_ik_owner == equipment_owner
			)

		Hand.RIGHT:
			return (
				right_ik_owner == &""
				or right_ik_owner == equipment_owner
			)

		Hand.BOTH:
			return (
				(left_ik_owner == &"" or left_ik_owner == equipment_owner)
				and
				(right_ik_owner == &"" or right_ik_owner == equipment_owner)
			)

	return false


func claim_hand_ik(
	equipment_owner: StringName,
	hand: Hand,
	target: Node3D
) -> bool:
	if hand != Hand.LEFT and hand != Hand.RIGHT:
		return false

	if not is_instance_valid(target):
		return false

	if not can_claim_ik(equipment_owner, hand):
		return false

	match hand:
		Hand.LEFT:
			_assign_ik_target(left_hand_ik, target)
			left_ik_owner = equipment_owner

		Hand.RIGHT:
			_assign_ik_target(right_hand_ik, target)
			right_ik_owner = equipment_owner

	return true


func claim_both_hand_ik(
	equipment_owner: StringName,
	left_target: Node3D,
	right_target: Node3D
) -> bool:
	if not is_instance_valid(left_target):
		return false

	if not is_instance_valid(right_target):
		return false

	if not can_claim_ik(equipment_owner, Hand.BOTH):
		return false

	_assign_ik_target(left_hand_ik, left_target)
	_assign_ik_target(right_hand_ik, right_target)

	left_ik_owner = equipment_owner
	right_ik_owner = equipment_owner

	return true


func release_hand_ik(
	equipment_owner: StringName,
	hand: Hand
) -> void:
	if equipment_owner == &"":
		return

	if hand == Hand.LEFT or hand == Hand.BOTH:
		if left_ik_owner == equipment_owner:
			_clear_ik_target(left_hand_ik)
			left_ik_owner = &""

	if hand == Hand.RIGHT or hand == Hand.BOTH:
		if right_ik_owner == equipment_owner:
			_clear_ik_target(right_hand_ik)
			right_ik_owner = &""



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


# === Generic Equipment Visual Helpers ===
func attach_equipment_visual(
	equipment_scene: PackedScene,
	attachment_target: Node3D,
	visual_transform: Transform3D = Transform3D.IDENTITY
) -> Node3D:
	if equipment_scene == null:
		return null

	if not is_instance_valid(attachment_target):
		return null

	var equipment_visual: Node3D = (
		equipment_scene.instantiate() as Node3D
	)

	if equipment_visual == null:
		return null

	attachment_target.add_child(equipment_visual)
	equipment_visual.transform = visual_transform

	return equipment_visual


func remove_equipment_visual(
	equipment_visual: Node3D
) -> void:
	if not is_instance_valid(equipment_visual):
		return

	equipment_visual.queue_free()


# === Product Visuals ===
func update_product_visual(
	holding: bool,
	product_path: String
) -> void:
	if not holding or product_path.is_empty():
		product_network_visual.visible = false
		release_hand_ik(&"product", Hand.RIGHT)
		return

	var resource: Resource = load(product_path)

	if not resource is ProductData:
		return

	var product: ProductData = resource as ProductData

	if product.product_mesh == null:
		return

	product_network_visual.mesh = product.product_mesh
	product_network_visual.position = product.hand_position
	product_network_visual.rotation = product.hand_rotation
	product_network_visual.scale = product.hand_scale
	product_network_visual.visible = true

	claim_hand_ik(
		&"product",
		Hand.RIGHT,
		held_item_hand_target
	)


# === Restock Scanner Visuals ===
func update_scanner_visual(holding: bool) -> void:
	# Remove the previous scanner visual.
	remove_equipment_visual(scanner_network_visual)
	scanner_network_visual = null

	if not holding:
		release_hand_ik(&"scanner", Hand.RIGHT)
		return

	# Scanner-specific attachment transform.
	var scanner_transform: Transform3D = Transform3D(
		Basis.from_euler(
			Vector3(
				deg_to_rad(-12.0),
				0.0,
				deg_to_rad(15.0)
			)
		),
		Vector3(0.0, -0.12, -0.02)
	)

	var scanner_visual: Node3D = attach_equipment_visual(
		RESTOCK_SCANNER_SCENE,
		held_item_target,
		scanner_transform
	)

	if scanner_visual == null:
		return

	# Disable interaction and collision on the visual copy.
	var interaction_area: Area3D = (
		scanner_visual.get_node_or_null("Area3D")
		as Area3D
	)

	if interaction_area != null:
		interaction_area.monitoring = false
		interaction_area.monitorable = false

		var collision_shape: CollisionShape3D = (
			interaction_area.get_node_or_null("CollisionShape3D")
			as CollisionShape3D
		)

		if collision_shape != null:
			collision_shape.disabled = true

	scanner_network_visual = scanner_visual

	claim_hand_ik(
		&"scanner",
		Hand.RIGHT,
		held_item_hand_target
	)



# === Restock Box Visuals ===
func update_restock_box_visual(
	holding: bool,
	product_path: String,
	quantity: int
) -> void:
	# Remove any existing box visuals.
	for box_child: Node in restock_box_network_visual.get_children():
		if box_child is Node3D:
			remove_equipment_visual(box_child as Node3D)

	if not holding or product_path.is_empty():
		restock_box_network_visual.visible = false
		release_hand_ik(&"restock_box", Hand.BOTH)
		return

	# Load the product associated with the box.
	var loaded_resource: Resource = load(product_path)

	if not loaded_resource is ProductData:
		restock_box_network_visual.visible = false
		release_hand_ik(&"restock_box", Hand.BOTH)
		return

	# Create the box using our generic attachment helper.
	var box_visual: Node3D = attach_equipment_visual(
		RESTOCK_BOX_SCENE,
		restock_box_network_visual
	)

	if box_visual == null:
		restock_box_network_visual.visible = false
		release_hand_ik(&"restock_box", Hand.BOTH)
		return

	var restock_box: RestockBox = box_visual as RestockBox

	if restock_box == null:
		remove_equipment_visual(box_visual)
		restock_box_network_visual.visible = false
		release_hand_ik(&"restock_box", Hand.BOTH)
		return

	# Initialize the product and quantity.
	restock_box.product_data = loaded_resource as ProductData
	restock_box.quantity = quantity
	restock_box.scale = Vector3.ONE

	# Prevent the visual copy from affecting physics.
	var box_body: StaticBody3D = (
		restock_box.get_node_or_null("StaticBody3D")
		as StaticBody3D
	)

	if box_body != null:
		box_body.collision_layer = 0
		box_body.collision_mask = 0

	restock_box_network_visual.visible = true

	# The restock box requires both hands.
	claim_both_hand_ik(
		&"restock_box",
		held_box_hand_target_left,
		held_box_hand_target_right
	)
