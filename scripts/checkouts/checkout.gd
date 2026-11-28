
extends Node3D
class_name Checkout

const CHECKOUT_OUTLINE_MATERIAL: Material = preload(
	"res://assets/materials/outline_standard_material_3d.tres"
)

@onready var checkout_point: Marker3D = $CheckoutPoint
@onready var waiting_points: Array[Marker3D] = [
	$WaitingPoints/WaitingPoint1,
	$WaitingPoints/WaitingPoint2,
	$WaitingPoints/WaitingPoint3
]

@onready var checkout_grid: CheckoutGrid = $CheckoutGrid
@onready var bag_grid: CartGrid = $BagGrid
@onready var checkout_camera: Camera3D = $CheckoutCamera
@onready var bag_point: Marker3D = $BagPoint
@onready var bag_mesh: MeshInstance3D = $BagGrid/BagMesh
@onready var checkout_instructions: CanvasLayer = $CheckoutInstructions

# AI Checkout Scanner
@onready var scan_area: Area3D = $ScanArea
@onready var scanner_beep_player: AudioStreamPlayer3D = $ScannerBeepPlayer
@onready var checkout_finished_player: AudioStreamPlayer3D = $CheckoutFinishedPlayer
@onready var scanner_flash: ScannerFlash = $ScannerFlash

@export_group("Barcode Scanning")
@export_range(0.0, 90.0, 1.0) var barcode_angle_tolerance: float = 25.0
@export_range(0.01, 1.0, 0.01) var barcode_scan_distance: float = 0.10

# Checkout Display
@onready var checkout_display: CheckoutDisplay = $CheckoutViewport/CheckoutUI
@onready var checkout_screen: MeshInstance3D = $CheckoutScreen
@onready var checkout_viewport: SubViewport = $CheckoutViewport

# Customers
var checkout_customer: ShopperAI = null
var waiting_customers: Array[ShopperAI] = []
var unscanned_items: Array[ProductData] = []

# Checkout hover outlines
var bag_outline: MeshInstance3D = null

# Desk Bell
@onready var desk_bell: AudioStreamPlayer3D = $DeskBellPlayer
const BELL_WAIT_MINUTES: int = 10
var last_scan_game_minute: int = 0
var checkout_active: bool = false

var scanner_user_peer_id: int = 0

# Snake Mini-Game
const SNAKE_COLUMNS: int = 28
const SNAKE_ROWS: int = 18

const SNAKE_START_INTERVAL: float = 0.336
const SNAKE_NORMAL_INTERVAL: float = 0.112
const SNAKE_ACCELERATION_DURATION: float = 1.0

@onready var checkout_display_panel: Control = (
	$CheckoutViewport/CheckoutUI/PanelContainer
)

var snake_game: SnakeGame = null

var snake_customer_present: bool = false
var snake_game_open: bool = false

var snake_body: Array[Vector2i] = []
var snake_direction: Vector2i = Vector2i.RIGHT
var snake_queued_direction: Vector2i = Vector2i.RIGHT
var snake_food: Vector2i = Vector2i.ZERO
var snake_score: int = 0

var snake_move_accumulator: float = 0.0
var snake_ramp_elapsed: float = 0.0

func _ready() -> void:
	add_to_group("checkout")
	bag_mesh.hide()

	checkout_grid.outline_material = CHECKOUT_OUTLINE_MATERIAL
	bag_grid.outline_material = CHECKOUT_OUTLINE_MATERIAL

	_create_bag_outline()

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = checkout_viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	checkout_screen.material_override = material

	# Create the shared Snake display.
	snake_game = SnakeGame.new()
	snake_game.name = "SnakeGame"
	snake_game.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	checkout_display.add_child(snake_game)
	snake_game.hide()

	checkout_display_panel.show()

	if multiplayer.is_server():
		_reset_snake_state()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_check_checkout_bell()
		_process_snake_game(delta)


func get_interaction_prompt(player: CharacterBody3D) -> String:

	if player == null:
		return ""

	if player.held_item == null:

		if player.is_holding_equipment():
			return ""

		return "[E] Use Checkout"

	if not player.network_holding_item:
		return ""

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return ""

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return ""

	return ""


func interact(player: CharacterBody3D) -> void:
	if player == null:
		return

	if player.held_item == null:
		if not player.is_holding_equipment():
			player.enter_checkout_mode(self)
		return

	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return

	var product: ProductData = player.held_item as ProductData

	if product == null:
		return

	# Don't allow an already-scanned or pending-barcode
	# product to trigger the scanner again.
	if (
		player.checkout_scanned_product_path == product.resource_path
		or player.checkout_barcode_product_path == product.resource_path
	):
		return

	if product.product_category == "produce":
		_open_produce_code_hud(player, product)
		return

	if not is_barcode_aligned(
		product,
		player.checkout_cursor_visual
	):
		return

	_request_ai_scan(player, product)


func get_checkout_camera() -> Camera3D:
	return checkout_camera


func show_checkout_instructions() -> void:
	checkout_instructions.show()


func hide_checkout_instructions() -> void:
	checkout_instructions.hide()


func is_mouse_over_scanner(mouse_position: Vector2) -> bool:

	var camera: Camera3D = checkout_camera

	if camera == null:
		return false

	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * 100.0
	)

	# ScanArea uses collision layer 256.
	query.collision_mask = scan_area.collision_layer
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = (
		get_world_3d().direct_space_state.intersect_ray(query)
	)

	if result.is_empty():
		return false

	return result.get("collider") == scan_area


#region Snake Functions
func is_mouse_over_checkout_screen(
	mouse_position: Vector2
) -> bool:
	if checkout_screen == null or checkout_screen.mesh == null:
		return false

	var camera: Camera3D = checkout_camera

	if camera == null:
		return false

	var origin: Vector3 = camera.project_ray_origin(
		mouse_position
	)

	var direction: Vector3 = camera.project_ray_normal(
		mouse_position
	)

	var normal: Vector3 = (
		checkout_screen.global_basis.z.normalized()
	)

	var denominator: float = direction.dot(normal)

	if absf(denominator) < 0.0001:
		return false

	var distance: float = (
		checkout_screen.global_position - origin
	).dot(normal) / denominator

	if distance < 0.0:
		return false

	var hit_position: Vector3 = (
		origin + direction * distance
	)

	var local_position: Vector3 = (
		checkout_screen.to_local(hit_position)
	)

	var screen_bounds: AABB = (
		checkout_screen.mesh.get_aabb().grow(0.02)
	)

	return screen_bounds.has_point(local_position)


func request_snake_game_open(
	player: CharacterBody3D
) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_open_snake_game(
			player,
			player.get_multiplayer_authority()
		)
	else:
		request_snake_game_open_rpc.rpc_id(
			1,
			player.get_path()
		)


@rpc("any_peer", "call_remote", "reliable")
func request_snake_game_open_rpc(
	player_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = (
		get_node_or_null(player_path) as CharacterBody3D
	)

	_server_open_snake_game(player, peer_id)


func _server_open_snake_game(
	player: CharacterBody3D,
	peer_id: int
) -> void:
	if not multiplayer.is_server():
		return

	if player == null:
		return

	if player.get_multiplayer_authority() != peer_id:
		return

	if scanner_user_peer_id != peer_id:
		return

	if snake_customer_present or snake_game_open:
		return

	if snake_body.is_empty():
		_reset_snake_state()

	snake_game_open = true
	snake_move_accumulator = 0.0
	snake_ramp_elapsed = 0.0
	snake_queued_direction = snake_direction

	sync_snake_game_state.rpc(
		true,
		snake_body,
		snake_food,
		snake_score
	)


func request_snake_game_close(
	player: CharacterBody3D
) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_close_snake_game()
	else:
		request_snake_game_close_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_snake_game_close_rpc() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	if peer_id != scanner_user_peer_id:
		return

	_server_close_snake_game()


func _server_close_snake_game() -> void:
	if not multiplayer.is_server():
		return

	if not snake_game_open:
		return

	snake_game_open = false
	snake_move_accumulator = 0.0

	sync_snake_game_state.rpc(
		false,
		snake_body,
		snake_food,
		snake_score
	)


@rpc("authority", "call_local", "reliable")
func sync_snake_game_state(
	is_open: bool,
	new_body: Array[Vector2i],
	new_food: Vector2i,
	new_score: int
) -> void:
	snake_game_open = is_open
	snake_body = new_body.duplicate()
	snake_food = new_food
	snake_score = new_score

	checkout_display_panel.visible = not is_open
	snake_game.visible = is_open

	snake_game.set_game_state(
		snake_body,
		snake_food,
		snake_score
	)


func request_snake_direction(
	player: CharacterBody3D,
	direction: Vector2i
) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_set_snake_direction(
			player.get_multiplayer_authority(),
			direction
		)
	else:
		request_snake_direction_rpc.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "reliable")
func request_snake_direction_rpc(
	direction: Vector2i
) -> void:
	if not multiplayer.is_server():
		return

	_server_set_snake_direction(
		multiplayer.get_remote_sender_id(),
		direction
	)


func _server_set_snake_direction(
	peer_id: int,
	direction: Vector2i
) -> void:
	if not multiplayer.is_server():
		return

	if peer_id != scanner_user_peer_id or not snake_game_open:
		return

	if absi(direction.x) + absi(direction.y) != 1:
		return

	if direction == -snake_direction:
		return

	if direction == -snake_queued_direction:
		return

	snake_queued_direction = direction


func _process_snake_game(delta: float) -> void:
	if not snake_game_open:
		return

	if snake_customer_present:
		_server_close_snake_game()
		return

	snake_ramp_elapsed = minf(
		snake_ramp_elapsed + delta,
		SNAKE_ACCELERATION_DURATION
	)

	var progress: float = clampf(
		snake_ramp_elapsed / SNAKE_ACCELERATION_DURATION,
		0.0,
		1.0
	)

	# Smoothstep acceleration.
	progress = progress * progress * (3.0 - 2.0 * progress)

	var movement_interval: float = lerpf(
		SNAKE_START_INTERVAL,
		SNAKE_NORMAL_INTERVAL,
		progress
	)

	snake_move_accumulator += delta

	while snake_move_accumulator >= movement_interval:
		snake_move_accumulator -= movement_interval

		if _advance_snake():
			break


func _advance_snake() -> bool:
	snake_direction = snake_queued_direction

	var next_head: Vector2i = (
		snake_body[0] + snake_direction
	)

	var eating_food: bool = next_head == snake_food

	var hit_wall: bool = (
		next_head.x < 0
		or next_head.x >= SNAKE_COLUMNS
		or next_head.y < 0
		or next_head.y >= SNAKE_ROWS
	)

	var hit_body: bool = (
		snake_body.has(next_head)
		and (
			eating_food
			or next_head != snake_body.back()
		)
	)

	# Losing immediately restarts the game.
	if hit_wall or hit_body:
		_reset_snake_state()

		snake_move_accumulator = 0.0

		sync_snake_game_state.rpc(
			true,
			snake_body,
			snake_food,
			snake_score
		)

		return true

	snake_body.insert(0, next_head)

	if eating_food:
		snake_score += 1
		_spawn_snake_food()
	else:
		snake_body.pop_back()

	sync_snake_game_state.rpc(
		true,
		snake_body,
		snake_food,
		snake_score
	)

	return false


func _reset_snake_state() -> void:
	snake_body = [
		Vector2i(8, 9),
		Vector2i(7, 9),
		Vector2i(6, 9)
	]

	snake_direction = Vector2i.RIGHT
	snake_queued_direction = Vector2i.RIGHT
	snake_score = 0

	_spawn_snake_food()


func _spawn_snake_food() -> void:
	while true:
		var candidate := Vector2i(
			randi_range(0, SNAKE_COLUMNS - 1),
			randi_range(0, SNAKE_ROWS - 1)
		)

		if not snake_body.has(candidate):
			snake_food = candidate
			return
#endregion


func is_barcode_aligned(
	product: ProductData,
	product_visual: MeshInstance3D
) -> bool:
	if product == null:
		return false

	if not is_instance_valid(product_visual):
		return false

	if not is_instance_valid(scan_area):
		return false

	var barcode_world: Transform3D = (
		product_visual.global_transform
		* product.barcode_transform
	)

	# The barcode marker's +Z points outward from the product.
	var barcode_direction: Vector3 = (
		barcode_world.basis.z.normalized()
	)

	# The scanner's +Y points upward from its reading surface.
	var scanner_direction: Vector3 = (
		scan_area.global_basis.y.normalized()
	)

	var alignment: float = barcode_direction.dot(
		-scanner_direction
	)

	var minimum_alignment: float = cos(
		deg_to_rad(barcode_angle_tolerance)
	)

	if alignment < minimum_alignment:
		return false

	var distance: float = (
		barcode_world.origin.distance_to(
			scan_area.global_position
		)
	)

	return distance <= barcode_scan_distance


func request_checkout(customer: ShopperAI) -> Marker3D:
	if customer == checkout_customer:
		return checkout_point

	if waiting_customers.has(customer):
		var index: int = waiting_customers.find(customer)
		return waiting_points[index]

	if checkout_customer == null:
		checkout_customer = customer
		return checkout_point

	if waiting_customers.size() >= waiting_points.size():
		return null

	waiting_customers.append(customer)

	return waiting_points[waiting_customers.size() - 1]


func _request_ai_scan(
	player: CharacterBody3D,
	product: ProductData,
	entered_code: String = ""
) -> void:
	if multiplayer.is_server():
		_server_scan_ai_product(player, product, entered_code)
	else:
		request_scan_ai_product.rpc_id(
			1,
			player.get_path(),
			product.resource_path,
			entered_code
		)


@rpc("any_peer", "call_remote", "reliable")
func request_scan_ai_product(
	player_path: NodePath,
	product_path: String,
	entered_code: String = ""
) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if player.get_multiplayer_authority() != peer_id:
		return

	if not player.network_holding_item:
		return

	if player.network_held_item_path != product_path:
		return

	var product: ProductData = load(product_path) as ProductData

	if product == null:
		return

	_server_scan_ai_product(player, product, entered_code)


func _server_scan_ai_product(
	player: CharacterBody3D,
	product: ProductData,
	entered_code: String = ""
	) -> void:
	if not multiplayer.is_server():
		return

	if player == null or product == null:
		return

	if not player.network_holding_item:
		return

	if player.network_held_item_path != product.resource_path:
		return

	# Validate the origin recorded by the server.
	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return

	# Produce must have the correct code before scanning.
	if product.product_category == "produce":
		if entered_code.is_empty():
			return

		if entered_code != product.product_code:
			return

	if not scan_ai_product(product):
		return

	# Record that this held product has been successfully scanned.
	player.checkout_scanned_product_path = product.resource_path

	var peer_id: int = player.get_multiplayer_authority()

	# Synchronize the scanned-product state with the owning client.
	if peer_id != multiplayer.get_unique_id():
		_sync_scanned_product_to_player.rpc_id(
			peer_id,
			player.get_path(),
			product.resource_path
		)

	# Close and reset the barcode HUD after a successful produce scan.
	if product.product_category == "produce":
		if peer_id == multiplayer.get_unique_id():
			_apply_barcode_hud_state(false)
			_reset_completed_barcode_code()
		else:
			_apply_barcode_hud_state.rpc_id(peer_id, false)
			_reset_completed_barcode_code.rpc_id(peer_id)


func request_scanner_access(player: CharacterBody3D) -> void:
	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_request_scanner_access(
			player,
			player.get_multiplayer_authority()
		)
	else:
		request_scanner_access_rpc.rpc_id(
			1,
			player.get_path()
		)


@rpc("any_peer", "call_remote", "reliable")
func request_scanner_access_rpc(player_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if player.get_multiplayer_authority() != peer_id:
		return

	_server_request_scanner_access(player, peer_id)


func _server_request_scanner_access(
	player: CharacterBody3D,
	peer_id: int
) -> void:
	if not multiplayer.is_server():
		return

	if player == null or peer_id <= 0:
		# Players must have empty hands to enter checkout mode.
		if (
			player.network_holding_item
			or player.held_item != null
			or player.is_holding_equipment()
		):
			return

	# The scanner is already occupied by another player.
	if (
		scanner_user_peer_id != 0
		and scanner_user_peer_id != peer_id
	):
		return

	scanner_user_peer_id = peer_id
	sync_scanner_user.rpc(peer_id)

	if peer_id == multiplayer.get_unique_id():
		player._activate_checkout_mode(self)
	else:
		grant_scanner_access.rpc_id(
			peer_id,
			player.get_path()
		)


@rpc("authority", "call_local", "reliable")
func sync_scanner_user(peer_id: int) -> void:
	scanner_user_peer_id = peer_id


@rpc("authority", "call_remote", "reliable")
func grant_scanner_access(player_path: NodePath) -> void:
	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	player._activate_checkout_mode(self)


func release_scanner_access(player: CharacterBody3D) -> void:
	if player == null:
		return

	var peer_id: int = player.get_multiplayer_authority()

	if multiplayer.is_server():
		_server_release_scanner_access(peer_id)
	else:
		release_scanner_access_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func release_scanner_access_rpc() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	_server_release_scanner_access(peer_id)


func _server_release_scanner_access(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Only the current scanner user can release access.
	if scanner_user_peer_id != peer_id:
		return

	# Hide Snake and preserve its current state.
	_server_close_snake_game()

	scanner_user_peer_id = 0
	sync_scanner_user.rpc(0)


func _open_produce_code_hud(
	player: CharacterBody3D,
	product: ProductData
) -> void:
	if player == null or product == null:
		return

	# Don't reopen an existing barcode prompt.
	if (
		player.checkout_scanned_product_path == product.resource_path
		or player.checkout_barcode_product_path == product.resource_path
	):
		return

	# Mark this product as having an active barcode prompt.
	player.checkout_barcode_product_path = product.resource_path

	var player_peer_id: int = player.get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		_apply_barcode_hud_state(true, product.product_code)
	else:
		_apply_barcode_hud_state.rpc_id(
			player_peer_id,
			true,
			product.product_code
		)


@rpc("authority", "call_remote", "reliable")
func _apply_barcode_hud_state(
	should_show: bool,
	product_code: String = ""
) -> void:
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud == null:
		return

	if should_show:
		hud.set_barcode_checkout(self)
		hud.show_barcode_hud(product_code)
	else:
		hud.close_barcode_hud()


func complete_produce_code(product_code: String) -> void:
	var player: CharacterBody3D = (
		get_tree().get_first_node_in_group("local_player")
		as CharacterBody3D
	)

	if player == null or player.held_item == null:
		return
	
	if player.held_item_origin != player.ItemOrigin.CHECKOUT_GRID:
		return
	
	var product: ProductData = player.held_item as ProductData

	if product == null:
		return

	if product.product_category != "produce":
		return

	if product.product_code != product_code:
		return

	_request_ai_scan(player, product, product_code)


@rpc("authority", "call_remote", "reliable")
func _reset_completed_barcode_code() -> void:
	var hud: Node = get_tree().get_first_node_in_group(
		"day_time_hud"
	)

	if hud != null:
		hud.completed_barcode_code = ""


# Called when the active shopper reaches CheckoutPoint.
func customer_arrived_at_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return
	
	if customer != checkout_customer:
		return
	
	snake_customer_present = true
	_server_close_snake_game()
	
	unscanned_items = customer.purchased_items.duplicate()
	_reset_checkout_display.rpc()
	_clear_grid(checkout_grid)

	for product: ProductData in customer.purchased_items:
		if product == null:
			continue

		if not checkout_grid.add_item(product):
			push_warning(
				"CheckoutGrid could not fit product: "
				+ product.display_name
			)

	_sync_grid_to_clients(checkout_grid)
	# Show the checkout bag when the shopper places their items.
	set_bag_visible.rpc(not checkout_grid.cart_items.is_empty())
	
	if not unscanned_items.is_empty():
		_start_checkout_wait()
	else:
		_stop_checkout_wait()


func customer_arrived_at_bag_point(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return

	if customer != checkout_customer:
		return
	
	_stop_checkout_wait()
	
	# Shopper collects their bag.
	_play_checkout_finished.rpc()
	_clear_grid(bag_grid)
	_sync_grid_to_clients(bag_grid)
	
	# Release checkout for the next shopper.
	checkout_customer = null
	snake_customer_present = false

	if waiting_customers.is_empty():
		return

	# Promote the first waiting shopper.
	checkout_customer = waiting_customers.pop_front()

	_move_customer(
		checkout_customer,
		checkout_point
	)

	# Move remaining shoppers forward in the queue.
	for i: int in range(waiting_customers.size()):
		_move_customer(
			waiting_customers[i],
			waiting_points[i]
		)



func can_scan_ai_product(product: ProductData) -> bool:
	if not multiplayer.is_server():
		return false

	if checkout_customer == null or product == null:
		return false

	for unscanned_product: ProductData in unscanned_items:
		if unscanned_product.resource_path == product.resource_path:
			return true

	return false


func scan_ai_product(product: ProductData) -> bool:
	if not can_scan_ai_product(product):
		return false

	for i: int in range(unscanned_items.size()):
		if unscanned_items[i].resource_path == product.resource_path:
			unscanned_items.remove_at(i)
			break

	_play_scanner_beep.rpc()
	_reset_checkout_wait()

	# Update the display without completing the sale yet.
	_update_checkout_display.rpc(
		product.display_name,
		product.product_price,
		false
	)

	if unscanned_items.is_empty():
		_stop_checkout_wait()

	return true


func notify_product_bagged(player: CharacterBody3D) -> void:
	if not multiplayer.is_server():
		return

	if player == null:
		return

	# Clear the scanned and pending barcode states.
	player.checkout_scanned_product_path = ""
	player.checkout_barcode_product_path = ""

	var peer_id: int = player.get_multiplayer_authority()

	# Also clear it on the player's client.
	if peer_id != multiplayer.get_unique_id():
		_sync_scanned_product_to_player.rpc_id(
			peer_id,
			player.get_path(),
			""
		)

	if checkout_customer == null:
		return

	# All products must have been scanned.
	if not unscanned_items.is_empty():
		return

	# All products must also have been placed in the bag.
	if bag_grid.cart_items.size() < checkout_customer.purchased_items.size():
		return

	# Start the sale-complete display timer only after
	# the final product has been placed in the bag.
	checkout_display.complete_sale.rpc()

	checkout_customer.checkout_scanning_completed()


func _clear_grid(grid: CartGrid) -> void:
	while grid.has_items():
		grid.take_item_at_index(0)

	if grid == bag_grid and multiplayer.is_server():
		set_bag_visible.rpc(false)


func _sync_grid_to_clients(grid: CartGrid) -> void:
	if not multiplayer.is_server():
		return

	var product_paths: Array[String] = grid._get_product_paths()
	var positions: Array[Vector3] = grid.item_positions.duplicate()
	var scales: Array[float] = grid.item_scales.duplicate()
	var rotations: Array[float] = grid._get_item_rotations()

	grid.sync_cart_state.rpc(product_paths, positions, scales, rotations)


func customer_finished_checkout(customer: ShopperAI) -> void:
	if not multiplayer.is_server():
		return

	if customer != checkout_customer:
		return
	
	_stop_checkout_wait()
	
	# Shopper walks to BagPoint to collect their products.
	customer.set_navigation_target(bag_point.global_position)
	customer.state = customer.State.BAGGING

	# Clear the checkout grid, but leave BagGrid untouched.
	_clear_grid(checkout_grid)
	_sync_grid_to_clients(checkout_grid)

	unscanned_items.clear()

	# Do not advance the queue yet.
	# The shopper must collect their bag first.


func _create_bag_outline() -> void:
	if bag_mesh == null or bag_mesh.mesh == null:
		return

	bag_outline = MeshInstance3D.new()
	bag_outline.name = "BagHoverOutline"

	# Copy the original bag mesh.
	bag_outline.mesh = bag_mesh.mesh

	# Match the bag's position, rotation, and scale.
	bag_outline.transform = bag_mesh.transform

	# Make the outline slightly larger than the original.
	bag_outline.scale *= Vector3(1.01, 1.01, 1.01)
	#bag_outline.position.y -= 0.025

	# Apply the existing outline material.
	bag_outline.material_override = CHECKOUT_OUTLINE_MATERIAL

	# Don't let the outline cast shadows.
	bag_outline.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	# Add it beside the original bag mesh.
	bag_mesh.get_parent().add_child(bag_outline)

	# Only show it when the mouse hovers over the bag.
	bag_outline.hide()


func is_mouse_over_bag(mouse_position: Vector2) -> bool:

	if not bag_mesh.visible or bag_mesh.mesh == null:
		return false

	var camera: Camera3D = checkout_camera

	if camera == null:
		return false

	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)

	# Reuse CartGrid's existing ray-to-mesh intersection function.
	var distance: float = bag_grid._get_ray_mesh_distance(
		origin,
		direction,
		bag_mesh
	)

	return distance >= 0.0


func update_checkout_hover_outline(
	mouse_position: Vector2,
	can_hover_products: bool
) -> void:

	# First, check whether the mouse is over a product.
	var product_index: int = -1

	if can_hover_products:
		product_index = checkout_grid.update_mouse_item_outline(
			mouse_position
		)
	else:
		checkout_grid.clear_mouse_item_outline()

	# If a product is highlighted, hide the bag outline.
	if product_index >= 0:
		if is_instance_valid(bag_outline):
			bag_outline.hide()

		return

	# Otherwise, check whether the mouse is over the bag.
	var over_bag: bool = is_mouse_over_bag(mouse_position)

	if is_instance_valid(bag_outline):
		bag_outline.visible = over_bag


func clear_checkout_hover_outlines() -> void:
	checkout_grid.clear_mouse_item_outline()

	if is_instance_valid(bag_outline):
		bag_outline.hide()


func _move_customer(
		customer: ShopperAI,
		target_point: Marker3D
	) -> void:
	if not is_instance_valid(customer):
		return

	customer.set_navigation_target(target_point.global_position)

	if target_point == checkout_point:
		customer.state = customer.State.CHECKOUT
	else:
		customer.state = customer.State.CHECKOUT_LINEUP



@rpc("authority", "call_local", "reliable")
func set_bag_visible(should_show: bool) -> void:
	bag_mesh.visible = should_show


# Bell functions
func _get_game_minutes() -> int:
	return (
		DayManager.current_day * 1440
		+ DayManager.current_hour * 60
		+ DayManager.current_minute
	)


func _start_checkout_wait() -> void:
	if not multiplayer.is_server():
		return

	checkout_active = true
	last_scan_game_minute = _get_game_minutes()


func _reset_checkout_wait() -> void:
	if not multiplayer.is_server():
		return

	last_scan_game_minute = _get_game_minutes()


func _stop_checkout_wait() -> void:
	checkout_active = false


func _check_checkout_bell() -> void:
	if not multiplayer.is_server():
		return

	if not checkout_active:
		return

	if checkout_customer == null:
		return

	if _get_game_minutes() - last_scan_game_minute < BELL_WAIT_MINUTES:
		return

	_reset_checkout_wait()

	if is_instance_valid(checkout_customer):
		if checkout_customer.experience != null:
			checkout_customer.experience.decrease(
				ShopperExperience.CHECKOUT_BELL_PENALTY,
				"Waited too long at checkout"
			)

	_play_desk_bell.rpc()


@rpc("authority", "call_local", "reliable")
func _play_desk_bell() -> void:
	desk_bell.play()


@rpc("authority", "call_local", "reliable")
func _play_scanner_beep() -> void:
	if is_instance_valid(scanner_beep_player):
		scanner_beep_player.pitch_scale = randf_range(1.0, 1.05)
		scanner_beep_player.play()

	scanner_flash.flash()


@rpc("authority", "call_local", "reliable")
func _play_checkout_finished() -> void:
	checkout_finished_player.play()

# Checkout Display RPC's

@rpc("authority", "call_local", "reliable")
func _reset_checkout_display() -> void:
	checkout_display.start_checkout()


@rpc("authority", "call_local", "reliable")
func _update_checkout_display(
	product_name: String,
	price: float,
	sale_complete: bool
) -> void:
	checkout_display.add_scanned_item(product_name, price)

	if sale_complete:
		checkout_display.complete_sale()


@rpc("authority", "call_remote", "reliable")
func _sync_scanned_product_to_player(
	player_path: NodePath,
	product_path: String
) -> void:
	var player: CharacterBody3D = get_node_or_null(
		player_path
	) as CharacterBody3D

	if player == null:
		return

	player.checkout_scanned_product_path = product_path

	if product_path.is_empty():
		player.checkout_barcode_product_path = ""
