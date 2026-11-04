#!/usr/bin/env python3
"""Generate full corrected Grocery Getter scripts from the current GitHub checkout.
Run from the repository root: python3 apply_rewrite.py
"""
from pathlib import Path
import re, shutil, sys

root = Path.cwd()
player_path = root/'scripts/player/low_poly_character_FP.gd'
equip_path = root/'scripts/player/player_equipment.gd'
display_path = root/'scripts/items/product_display.gd'
def_path = root/'resources/equipment/restock_box.tres'
for p in (player_path,equip_path,display_path,def_path):
    if not p.is_file():
        sys.exit(f'Missing {p}. Run from the Grocery Getter repository root.')

player=player_path.read_text()
equip=equip_path.read_text()
display=display_path.read_text()
definition=def_path.read_text()

def replace_exact(s,old,new,desc):
    n=s.count(old)
    if n!=1: raise ValueError(f'{desc}: expected exactly one match, found {n}; no files changed')
    return s.replace(old,new,1)

def replace_func(s,name,body):
    pat=rf'(?m)^func {re.escape(name)}\('
    match=re.search(pat,s)
    if not match: raise ValueError(f'Missing function: {name}')
    nxt=re.search(r'(?m)^(?:func |@rpc\(|# Mop pick up|# === )',s[match.end():])
    end=match.end()+nxt.start() if nxt else len(s)
    # Decorator for the next function remains intact
    return s[:match.start()]+body.rstrip()+'\n\n\n'+s[end:]

player=replace_exact(player,'var held_restock_box: RestockBox = null','var held_restock_box: RestockBoxVisual = null','held box type')
player=replace_exact(player,'var held_restock_box_visual: Node3D = null','''var held_restock_box_visual: Node3D = null

# Server-authoritative restock box contents. Never trust client quantities.
var server_restock_box_product_path: String = ""
var server_restock_box_quantity: int = 0''','server state')

player=replace_func(player,'try_pickup_restock_box','''func try_pickup_restock_box(box: RestockBox) -> void:
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(box):
		return
	if held_restock_box != null or held_item != null:
		return
	if held_restock_scanner != null or attached_cart != null:
		return
	if box.product_data == null:
		return

	# The player receives a visual only AFTER server approval.
	var box_path: NodePath = box.get_path()
	if multiplayer.is_server():
		_server_pickup_restock_box(box_path, get_multiplayer_authority())
	else:
		request_pickup_restock_box.rpc_id(1, box_path)''')

player=replace_func(player,'_server_pickup_restock_box','''func _server_pickup_restock_box(
	box_path: NodePath,
	requesting_peer_id: int
) -> void:
	if not multiplayer.is_server():
		return
	if get_multiplayer_authority() != requesting_peer_id:
		return
	if not server_restock_box_product_path.is_empty():
		return

	var box: RestockBox = get_node_or_null(box_path) as RestockBox
	if not is_instance_valid(box):
		return
	if not box.is_in_group("restock_boxes"):
		return
	if box.is_queued_for_deletion() or box.get_meta("picked_up", false):
		return
	if box.product_data == null or box.quantity <= 0:
		return

	# Claim atomically on the server. The MultiplayerSpawner handles despawning.
	box.set_meta("picked_up", true)
	var product_path: String = box.product_data.resource_path
	var box_quantity: int = box.quantity
	server_restock_box_product_path = product_path
	server_restock_box_quantity = box_quantity

	# The client must be granted before the spawned world box disappears.
	_grant_restock_box.rpc_id(requesting_peer_id, product_path, box_quantity)
	if requesting_peer_id == multiplayer.get_unique_id():
		_grant_restock_box(product_path, box_quantity)

	box.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func _grant_restock_box(product_path: String, box_quantity: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:
		return
	if not is_multiplayer_authority():
		return
	if held_restock_box != null:
		return
	if held_item != null or held_restock_scanner != null:
		return

	var product: ProductData = load(product_path) as ProductData
	if product == null:
		return

	var visual: RestockBoxVisual = player_equipment.create_local_restock_box_visual(
		held_box_holder, product, box_quantity
	)
	if visual == null:
		return

	held_restock_box = visual
	held_restock_box_visual = visual
	network_holding_restock_box = true
	network_restock_box_product_path = product_path
	network_restock_box_quantity = box_quantity''')

# Remove obsolete manual world despawn RPC, since MultiplayerSpawner owns it.
player=replace_func(player,'remove_world_restock_box','''func remove_world_restock_box(_box_path: NodePath) -> void:
	# Legacy compatibility only. World boxes are despawned by the server
	# through their MultiplayerSpawner.
	pass''')

player=replace_func(player,'_clear_held_restock_box','''func _clear_held_restock_box() -> void:
	if is_instance_valid(held_restock_box):
		held_restock_box.queue_free()
	held_restock_box = null
	held_restock_box_visual = null
	network_holding_restock_box = false
	network_restock_box_product_path = ""
	network_restock_box_quantity = 0


func _server_clear_restock_box_contents() -> void:
	if not multiplayer.is_server():
		return
	server_restock_box_product_path = ""
	server_restock_box_quantity = 0''')

# Equipment: a single visual-only scene, no collision disabling required.
equip=replace_func(equip,'update_restock_box_visual','''func create_local_restock_box_visual(
	attachment_target: Node3D,
	product: ProductData,
	box_quantity: int
) -> RestockBoxVisual:
	var visual: Node3D = attach_defined_equipment_visual(
		RESTOCK_BOX_DEFINITION,
		attachment_target,
		{&"product_data": product, &"quantity": box_quantity}
	)
	if not visual is RestockBoxVisual:
		remove_equipment_visual(visual)
		return null
	return visual as RestockBoxVisual


func update_restock_box_visual(
	holding: bool,
	product_path: String,
	quantity: int
) -> void:
	var equipment_id: StringName = RESTOCK_BOX_DEFINITION.equipment_id
	for box_child: Node in restock_box_network_visual.get_children():
		if box_child is Node3D:
			remove_equipment_visual(box_child as Node3D)

	if not holding or product_path.is_empty():
		restock_box_network_visual.visible = false
		release_hand_ik(equipment_id, Hand.BOTH)
		return

	var product: ProductData = load(product_path) as ProductData
	if product == null:
		restock_box_network_visual.visible = false
		release_hand_ik(equipment_id, Hand.BOTH)
		return

	var visual: RestockBoxVisual = create_local_restock_box_visual(
		restock_box_network_visual, product, quantity
	)
	if visual == null:
		restock_box_network_visual.visible = false
		release_hand_ik(equipment_id, Hand.BOTH)
		return

	restock_box_network_visual.visible = true
	claim_both_hand_ik(
		equipment_id,
		held_box_hand_target_left,
		held_box_hand_target_right
	)''')

# ProductDisplay now handles visual-only held box and verifies server-side contents.
display=display.replace('var box: RestockBox = player.held_restock_box','var box: RestockBoxVisual = player.held_restock_box')
display=replace_func(display,'request_restock_from_box','''func request_restock_from_box(
	player_path: NodePath,
	box_product_path: String,
	box_quantity: int
) -> void:
	if not is_unlocked or not multiplayer.is_server():
		return
	var requesting_peer_id: int = multiplayer.get_remote_sender_id()
	var player: CharacterBody3D = get_node_or_null(player_path) as CharacterBody3D
	if player == null or player.get_multiplayer_authority() != requesting_peer_id:
		return
	if product_data == null:
		return
	if player.server_restock_box_product_path != product_data.resource_path:
		return
	if box_product_path != player.server_restock_box_product_path:
		return
	if box_quantity != player.server_restock_box_quantity:
		return
	_restock_from_box(player, player.server_restock_box_quantity)''')
display=replace_func(display,'_restock_from_box','''func _restock_from_box(
	player: CharacterBody3D,
	box_quantity: int
) -> void:
	if not is_unlocked or not multiplayer.is_server():
		return
	if player == null or product_data == null:
		return
	if player.server_restock_box_product_path != product_data.resource_path:
		return
	if box_quantity <= 0 or box_quantity != player.server_restock_box_quantity:
		return
	if quantity + box_quantity > max_quantity:
		return

	quantity += box_quantity
	player._server_clear_restock_box_contents()
	var player_peer_id: int = player.get_multiplayer_authority()
	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_restock_box()
	else:
		player.clear_held_restock_box.rpc_id(player_peer_id)''')

# Keep the existing world box scene unchanged; the visual is a separate scene.
visual_script='''extends Node3D
class_name RestockBoxVisual

@export var product_data: ProductData
@export_range(1, 400, 1) var quantity: int = 10

@onready var box_label_viewport: SubViewport = $BoxLabelViewport
@onready var front_label_mesh: MeshInstance3D = $FrontLabelMesh
@onready var back_label_mesh: MeshInstance3D = $BackLabelMesh
@onready var product_name_label: Label = $BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer/ProductNameLabel
@onready var quantity_label: Label = $BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer/QuantityLabel

func _ready() -> void:
	var label_material: StandardMaterial3D = StandardMaterial3D.new()
	label_material.albedo_texture = box_label_viewport.get_texture()
	label_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	label_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	front_label_mesh.material_override = label_material
	back_label_mesh.material_override = label_material
	product_name_label.text = product_data.display_name if product_data != null else "Unassigned Product"
	quantity_label.text = "QTY: %d" % quantity
'''
visual_scene='''[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/items/restock_box_visual.gd" id="1"]
[ext_resource type="ArrayMesh" path="res://assets/models/checkouts/restock_box_Cube_021.res" id="2"]

[sub_resource type="QuadMesh" id="QuadMesh_1"]
size = Vector2(0.33, 0.11)

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_1"]
bg_color = Color(0.94149923, 0.9214006, 0.9176794, 1)

[node name="RestockBoxVisual" type="Node3D"]
script = ExtResource("1")

[node name="BoxMesh" type="MeshInstance3D" parent="."]
mesh = ExtResource("2")

[node name="FrontLabelMesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.1, 0.42, 0.251)
mesh = SubResource("QuadMesh_1")

[node name="BackLabelMesh" type="MeshInstance3D" parent="."]
transform = Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, 0.1, 0.42, -0.251)
mesh = SubResource("QuadMesh_1")

[node name="BoxLabelViewport" type="SubViewport" parent="."]
size = Vector2i(600, 200)
render_target_update_mode = 1

[node name="Control" type="Control" parent="BoxLabelViewport"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

grow_horizontal = 2
grow_vertical = 2

[node name="PanelContainer" type="PanelContainer" parent="BoxLabelViewport/Control"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

grow_horizontal = 2
grow_vertical = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_1")

[node name="MarginContainer" type="MarginContainer" parent="BoxLabelViewport/Control/PanelContainer"]
layout_mode = 2
size_flags_vertical = 3
theme_override_constants/margin_left = 8
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 8
theme_override_constants/margin_bottom = 8

[node name="VBoxContainer" type="VBoxContainer" parent="BoxLabelViewport/Control/PanelContainer/MarginContainer"]
layout_mode = 2
alignment = 2

[node name="ProductNameLabel" type="Label" parent="BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 3
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_font_sizes/font_size = 56
text = "Unassigned Product"

[node name="QuantityLabel" type="Label" parent="BoxLabelViewport/Control/PanelContainer/MarginContainer/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 1
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_font_sizes/font_size = 50
text = "QTY: 10"
horizontal_alignment = 2
vertical_alignment = 2
'''

definition=replace_exact(definition,'path="res://scenes/items/restock_box.tscn"','path="res://scenes/items/restock_box_visual.tscn"','equipment scene path')
# UID of original world scene must not be reused for new visual scene.
definition=re.sub(r'(\[ext_resource type="PackedScene") uid="[^"]+"',r'\1',definition,count=1)

files={
 player_path:player,
 equip_path:equip,
 display_path:display,
 def_path:definition,
 root/'scripts/items/restock_box_visual.gd':visual_script,
 root/'scenes/items/restock_box_visual.tscn':visual_scene,
}
# Refuse to clobber uncommitted output on repeat runs.
for path in files:
    if path.exists() and path.name in ('restock_box_visual.gd','restock_box_visual.tscn'):
        sys.exit(f'Visual scene already exists: {path}; refusing to overwrite')
for path in files:
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists(): shutil.copy2(path,path.with_suffix(path.suffix+'.before_rewrite'))
for path,contents in files.items():
    path.write_text(contents)
    print('Wrote:',path.relative_to(root))
print('Done. Original files saved as *.before_rewrite. Review with git diff before testing.')
