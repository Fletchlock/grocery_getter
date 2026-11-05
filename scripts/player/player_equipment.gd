
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
@onready var mop_cleaning_target: Node3D = $"../Armature/MopCleaningTarget"

var standing_item_target_position: Vector3
var standing_hand_target_position: Vector3
var standing_box_hand_target_left_position: Vector3
var standing_box_hand_target_right_position: Vector3

# === Hand IK Management ===
@onready var left_hand_ik: TwoBoneIK3D = $"../Armature/Skeleton3D/LeftTwoBoneIK3D"
@onready var right_hand_ik: TwoBoneIK3D = $"../Armature/Skeleton3D/RightTwoBoneIK3D"
@onready var left_hand_rotation: CopyTransformModifier3D = (
	$"../Armature/Skeleton3D/LeftHandRotationModifier"
)
@onready var right_hand_rotation: CopyTransformModifier3D = (
	$"../Armature/Skeleton3D/RightHandRotatioinModifier"
)
var left_ik_owner: StringName = &""
var right_ik_owner: StringName = &""

# === Product Visuals ===
@onready var product_network_visual: MeshInstance3D = (
	$"../Armature/HeldItemTarget/HeldItemNetworkVisual"
)

# === Restock Scanner Visuals ===
const RESTOCK_SCANNER_DEFINITION: EquipmentDefinition = preload(
	"res://resources/equipment/restock_scanner.tres"
)

var scanner_network_visual: Node3D = null

# === Restock Box Visuals ===
const RESTOCK_BOX_DEFINITION: EquipmentDefinition = preload(
	"res://resources/equipment/restock_box.tres"
)

@onready var restock_box_network_visual: Node3D = (
	$"../Armature/HeldItemTarget/HeldRestockBoxNetworkVisual"
)

# === Mop Visuals ===
const MOP_SCENE: PackedScene = preload(
	"res://scenes/objects/tools/mop.tscn"
)

const MOP_DEFINITION: EquipmentDefinition = preload(
	"res://resources/equipment/mop.tres"
)

@export_group("Mop Cleaning Pose")
@export var mop_cleaning_position: Vector3 = Vector3(0.0, 0.90, -0.5)
@export var mop_cleaning_rotation: Vector3 = Vector3(-20.0, 150.0, -10.0)

var mop_network_visual: Node3D = null
var mop_is_cleaning: bool = false

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


func set_hand_rotation_targets(
	left_target: Node3D,
	right_target: Node3D
) -> void:
	if not is_instance_valid(left_target):
		return

	if not is_instance_valid(right_target):
		return

	left_hand_rotation.target_node = left_target.get_path()
	right_hand_rotation.target_node = right_target.get_path()

	left_hand_rotation.influence = 1.0
	right_hand_rotation.influence = 1.0


func clear_hand_rotation_targets() -> void:
	left_hand_rotation.influence = 0.0
	right_hand_rotation.influence = 0.0

	left_hand_rotation.target_node = NodePath("")
	right_hand_rotation.target_node = NodePath("")
	

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
	visual_transform: Transform3D = Transform3D.IDENTITY,
	initial_properties: Dictionary = {}
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

	# Configure the scene before _ready() runs.
	for property_name: Variant in initial_properties:
		equipment_visual.set(
			property_name,
			initial_properties[property_name]
		)

	attachment_target.add_child(equipment_visual)
	equipment_visual.transform = visual_transform

	return equipment_visual


func attach_defined_equipment_visual(
	equipment_definition: EquipmentDefinition,
	attachment_target: Node3D,
	initial_properties: Dictionary = {}
) -> Node3D:
	if equipment_definition == null:
		return null

	if equipment_definition.visual_scene == null:
		return null

	return attach_equipment_visual(
		equipment_definition.visual_scene,
		attachment_target,
		equipment_definition.get_attachment_transform(),
		initial_properties
	)


func remove_equipment_visual(
	equipment_visual: Node3D
) -> void:
	if not is_instance_valid(equipment_visual):
		return

	equipment_visual.queue_free()


# === Product Visuals ===
func create_local_product_visual(
	product: ProductData,
	attachment_target: Node3D
) -> MeshInstance3D:
	if product == null or product.product_mesh == null:
		return null

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = product.product_mesh
	visual.position = product.hand_position
	visual.rotation = product.hand_rotation
	visual.scale = product.hand_scale

	attachment_target.add_child(visual)

	return visual


func remove_local_product_visual(
	visual: MeshInstance3D
) -> void:
	remove_equipment_visual(visual)


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
func create_local_scanner_visual(
	attachment_target: Node3D
) -> Node3D:
	return attach_defined_equipment_visual(
		RESTOCK_SCANNER_DEFINITION,
		attachment_target
	)


func update_scanner_visual(holding: bool) -> void:
	remove_equipment_visual(scanner_network_visual)
	scanner_network_visual = null

	var equipment_id: StringName = (
		RESTOCK_SCANNER_DEFINITION.equipment_id
	)

	if not holding:
		release_hand_ik(equipment_id, Hand.RIGHT)
		return

	var scanner_visual: Node3D = attach_defined_equipment_visual(
		RESTOCK_SCANNER_DEFINITION,
		held_item_target
	)

	if scanner_visual == null:
		return

	# Disable interaction and collision on the remote visual.
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
		equipment_id,
		Hand.RIGHT,
		held_item_hand_target
	)


# === Restock Box Visuals ===
func create_restock_box_visual(
	product: ProductData,
	quantity: int,
	attachment_target: Node3D
) -> RestockBox:
	var box: RestockBox = (
		RESTOCK_BOX_DEFINITION.visual_scene.instantiate()
		as RestockBox
	)

	if box == null:
		return null

	box.product_data = product
	box.quantity = quantity

	# Keep Area3D/MeshOutline for RestockBox._ready().
	# Disable interaction without removing required nodes.
	var interaction_area: Area3D = box.get_node("Area3D") as Area3D
	interaction_area.monitoring = false
	interaction_area.monitorable = false
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 0

	var collision_shape: CollisionShape3D = (
		interaction_area.get_node("CollisionShape3D")
		as CollisionShape3D
	)
	collision_shape.disabled = true

	attachment_target.add_child(box)
	box.transform = Transform3D.IDENTITY

	return box


func update_restock_box_visual(
		holding: bool,
		product_path: String,
		quantity: int
	) -> void:
	var equipment_id: StringName = RESTOCK_BOX_DEFINITION.equipment_id

	for child: Node in restock_box_network_visual.get_children():
		child.queue_free()

	if not holding or product_path.is_empty():
		restock_box_network_visual.visible = false
		release_hand_ik(equipment_id, Hand.BOTH)
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	var box: RestockBox = create_restock_box_visual(
		product,
		quantity,
		restock_box_network_visual
	)

	if box == null:
		return

	restock_box_network_visual.visible = true

	claim_both_hand_ik(
		equipment_id,
		held_box_hand_target_left,
		held_box_hand_target_right
	)


# === Mop Visuals ===
func create_local_mop_visual(
		attachment_target: Node3D,
		hold_position: Vector3,
		hold_rotation: Vector3
	) -> Node3D:
	var mop_visual: Node3D = attach_equipment_visual(
		MOP_SCENE,
		attachment_target
	)

	if mop_visual == null:
		return null

	_prepare_mop_visual(mop_visual)

	mop_visual.position = hold_position
	mop_visual.rotation_degrees = hold_rotation

	return mop_visual


func update_mop_visual(holding: bool) -> void:
	remove_equipment_visual(mop_network_visual)
	mop_network_visual = null

	var equipment_id: StringName = MOP_DEFINITION.equipment_id

	if not holding:
		release_hand_ik(equipment_id, Hand.RIGHT)
		return

	var mop_visual: Node3D = attach_defined_equipment_visual(
		MOP_DEFINITION,
		held_item_target
	)

	if mop_visual == null:
		return

	_prepare_mop_visual(mop_visual)
	mop_network_visual = mop_visual

	claim_hand_ik(
		equipment_id,
		Hand.RIGHT,
		held_item_hand_target
	)
	
	#temp testing
	set_mop_cleaning(true)


func _prepare_mop_visual(mop_visual: Node3D) -> void:
	# The bucket stays in the world.
	var bucket_mesh: MeshInstance3D = (
		mop_visual.get_node_or_null("BucketMesh") as MeshInstance3D
	)

	if bucket_mesh != null:
		bucket_mesh.hide()

	_disable_mop_area(mop_visual, "Area3D")
	_disable_mop_area(mop_visual, "ReturnArea")

	var outline: Node3D = (
		mop_visual.get_node_or_null("Area3D/MeshOutline") as Node3D
	)

	if outline != null:
		outline.visible = false


func _disable_mop_area(
		mop_visual: Node3D,
		area_path: String
	) -> void:
	var area: Area3D = (
		mop_visual.get_node_or_null(area_path) as Area3D
	)

	if area == null:
		return

	area.monitoring = false
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 0

	var collision_shape: CollisionShape3D = (
		area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)

	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)


# === Mop Cleaning Pose ===
func set_mop_cleaning(cleaning: bool) -> void:
	if mop_is_cleaning == cleaning:
		return

	mop_is_cleaning = cleaning

	if not is_instance_valid(mop_network_visual):
		return

	var equipment_id: StringName = MOP_DEFINITION.equipment_id

	if cleaning:
		if not can_claim_ik(equipment_id, Hand.BOTH):
			mop_is_cleaning = false
			return

		mop_network_visual.reparent(mop_cleaning_target, false)
		mop_network_visual.position = mop_cleaning_position
		mop_network_visual.rotation_degrees = mop_cleaning_rotation

		var left_grip: Node3D = (
			mop_network_visual.get_node_or_null("LeftHandGrip") as Node3D
		)
		var right_grip: Node3D = (
			mop_network_visual.get_node_or_null("RightHandGrip") as Node3D
		)

		if left_grip != null and right_grip != null:
			if claim_both_hand_ik(
				equipment_id,
				left_grip,
				right_grip
			):
				set_hand_rotation_targets(
					left_grip,
					right_grip
				)
	else:
		mop_network_visual.reparent(held_item_target, false)
		mop_network_visual.transform = MOP_DEFINITION.get_attachment_transform()
		
		release_hand_ik(equipment_id, Hand.LEFT)
		clear_hand_rotation_targets()
		claim_hand_ik(
			equipment_id,
			Hand.RIGHT,
			held_item_hand_target
		)
