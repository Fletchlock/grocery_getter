extends Node3D


@onready var order_label: Label3D = $Label3D
@onready var scanner_beep_player: AudioStreamPlayer3D = $AcceptOrderArea/ScannerBeepPlayer




var showing_new_order: bool = false

func _ready() -> void:
	OrderManager.order_generated.connect(_on_order_generated)
	OrderManager.order_updated.connect(_on_order_updated)

	showing_new_order = true
	order_label.text = "NEW ORDER AVAILABLE"
		
		

func _process(delta: float) -> void:
	if showing_new_order:
		return
	
	if OrderManager.current_order == null:
		return
		
	if OrderManager.current_order.state == OrderData.OrderState.ACTIVE:
		_update_order_display(OrderManager.current_order)


func _on_order_generated(order: OrderData) -> void:
	showing_new_order = true
	order_label.text = "NEW ORDER AVAILABLE"


func _on_order_updated(order: OrderData) -> void:
	_update_order_display(order)


func _update_order_display(order: OrderData) -> void:
	var text: String = "ORDER #%d\n\n" % order.order_id

	for item: OrderItem in order.items:
		var item_text: String = "%s    %d/%d" % [
			item.product.display_name,
			item.quantity_fulfilled,
			item.quantity
		]

		if item.is_complete():
			text += "%s\n" % item_text
		else:
			text += "%s\n" % item_text
	
	text += "\nORDER TOTAL: $%.2f" % order.current_profit
	
	var start_minutes: int = int(order.time_limit) / 60
	var start_seconds: int = int(order.time_limit) % 60
	
	text += "\nTIME LIMIT: %02d:%02d" % [start_minutes, start_seconds]

	var remaining_time: float = maxf(
		order.time_limit - order.elapsed_time,
		0.0
	)
	
	var minutes: int = int(remaining_time) / 60
	var seconds: int = int(remaining_time) % 60
	
	text += "\nTIME REMAINING: %02d:%02d" % [minutes, seconds]
	
	if order.state == OrderData.OrderState.COMPLETED:
		text += "\n*** ORDER COMPLETE ***"
		if order.elapsed_time > order.time_limit:
			text += "\nTHE ORDER WAS LATE!"
		else:
			text += "\nGOOD JOB!"
	
	order_label.text = text
	
	
func get_interaction_prompt(player: CharacterBody3D) -> String:
	if player.network_holding_item:
		if player.held_item == null:
			return ""
		
		return "[E] Checkout " + player.held_item.display_name
		
	if OrderManager.current_order == null:
		return ""
		
	if OrderManager.current_order.state != OrderData.OrderState.WAITING:
		return ""
		
	return "[E] Accept Order"
	
	
func interact(player: CharacterBody3D) -> void:
	if player.network_holding_item:
		if multiplayer.is_server():
			var submitted: bool = OrderManager.submit_product(player.held_item)
		
			if submitted:
				var player_peer_id: int = player.get_multiplayer_authority()

				if player_peer_id == multiplayer.get_unique_id():
					player._clear_held_item()
				else:
					player.clear_held_item.rpc_id(player_peer_id)
			
		else:
			request_submit_product.rpc_id(
				1,
				player.get_path(),
				player.held_item.resource_path
			)
		scanner_beep_player.pitch_scale = randf_range(1.0, 1.05)
		scanner_beep_player.play()
		return

	if OrderManager.current_order == null:
		return

	if OrderManager.current_order.state != OrderData.OrderState.WAITING:
		return

	OrderManager.accept_order(player)
	showing_new_order = false
	_update_order_display(OrderManager.current_order)

@rpc("any_peer", "call_remote", "reliable")
func request_submit_product(
	player_path: NodePath,
	product_path: String
	) -> void:

	if not multiplayer.is_server():
		return

	var requesting_peer_id: int = multiplayer.get_remote_sender_id()

	var player: CharacterBody3D = get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return

	if player.get_multiplayer_authority() != requesting_peer_id:
		return

	var product: ProductData = load(product_path) as ProductData
	if product == null:
		return

	var submitted: bool = OrderManager.submit_product(product)
	if not submitted:
		return

	var player_peer_id: int = player.get_multiplayer_authority()
	if player_peer_id == multiplayer.get_unique_id():
		player._clear_held_item()
	else:
		player.clear_held_item.rpc_id(player_peer_id)
