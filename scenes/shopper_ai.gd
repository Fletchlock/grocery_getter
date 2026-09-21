extends CharacterBody3D

# Character refs
@onready var body_mesh: MeshInstance3D = $Armature/Skeleton3D/npc_shopper_01


# AI Movement and rotation
@export var rotation_speed: float = 10.0
@export var speed: float = 2.25
var target_rotation: float = 0.0

# Animations
var current_animation: StringName = &""

# Blink
@export_group("Blink")
@export var blink_min_time: float = 2.5 ## Minimum time to wait before a blink.
@export var blink_max_time: float = 6.5 ## Maximum time to wait before a blink.
@export var blink_duration: float = 0.14 ## How long it takes for the eyes to close and reopen.
@export var blink_min_value: float = 0.32 ## Shape key value when the eyes are normally open.
@export var blink_max_value: float = 1.65 ## Shape key value when the eyes are fully closed.
@export_range(0.0, 1.0) var double_blink_chance: float = 0.08 ## Chance of a second blink after a normal blink.
@export var double_blink_delay: float = 0.10 ## Delay between the first and second blink.
var blink_timer := 0.0
var blink_progress := -1.0
var double_blink_pending := false

# Look at others when in proximity
@export_group("Idle Look")
@export var look_distance: float = 5.0 ## Maximum distance to look at another player.
@export var look_speed: float = 5.0 ## Speed at which the head turns toward another player.
@export var look_back_speed: float = 1.0 ## Speed at which the head turns away from another player.
@export_range(0.0, 180.0) var look_angle: float = 70.0 ## Maximum angle from forward that the character will look.

@onready var look_at_modifier: LookAtModifier3D = $Armature/Skeleton3D/LookAtModifier3D
var look_target: Node3D = null

# Network replication
@export var network_is_grounded : bool = true

# States
enum State { IDLE, WAITING_TO_MOVE, MOVING}
var state : State = State.IDLE

# Timers
@export var idle_wait_time_min: float = 3.0
@export var idle_wait_time_max: float = 6.0
var idle_timer_count: float = 0 # internal countdown timer
var stuck_timer: float = 1.5 # If AI gets stuck in avoidance hell
var last_position: Vector3 = Vector3.ZERO


# Node Refs
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	blink_timer = randf_range(blink_min_time, blink_max_time)


func _process(delta: float) -> void:
	blink(delta)
	update_idle_look(delta)

func _physics_process(delta: float) -> void:

	velocity += get_gravity() * delta

	match state:
		State.IDLE:
			_on_idle()
		State.WAITING_TO_MOVE:
			_on_waiting_to_move(delta)
		State.MOVING:
			_on_moving(delta)
	
	update_animation()
	
	move_and_slide()
	
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

func _on_idle():
	velocity = Vector3.ZERO
	navigation_agent_3d.velocity = Vector3.ZERO
	idle_timer_count = randf_range(idle_wait_time_min, idle_wait_time_max)
	state = State.WAITING_TO_MOVE
	

func _on_waiting_to_move(delta):
	idle_timer_count -= delta
	
	if idle_timer_count <= 0.0:
		var target = get_new_target_location()
		var nav_map = navigation_agent_3d.get_navigation_map()
		var safe_target = NavigationServer3D.map_get_closest_point(nav_map, target)
		
		navigation_agent_3d.target_position = safe_target
		last_position = global_transform.origin
		stuck_timer = 0.0
		state = State.MOVING


func _on_moving(delta: float) -> void:
	var current_position = global_transform.origin
	var next_position = navigation_agent_3d.get_next_path_position()
	var direction = (next_position - current_position).normalized()
	var new_velocity = direction * speed
	
	navigation_agent_3d.velocity = new_velocity
	
	if new_velocity.length_squared() > 0.01:
		target_rotation = atan2(direction.x, direction.z)

	if current_position.distance_to(last_position) < 0.05:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
		last_position = current_position

	if stuck_timer >= 1.5:
		stuck_timer = 0.0
		state = State.IDLE

func get_new_target_location() -> Vector3:
	# 1. Get a random direction vector on a flat 2D plane (X and Z)
	var random_direction = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	# 2. Multiply by a random distance between 5.0 and 10.0
	var random_distance = randf_range(10.0, 20.0)
	# 3. Add to your current position
	return global_transform.origin + (random_direction * random_distance)


func _on_navigation_agent_3d_target_reached() -> void:
	velocity = Vector3.ZERO
	navigation_agent_3d.velocity = Vector3.ZERO
	state = State.IDLE


func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3) -> void:
	if state == State.MOVING and is_on_floor():
		velocity = velocity.move_toward(safe_velocity, 0.55)
		#velocity = safe_velocity
		
		
func update_animation() -> void:
	var new_animation: StringName = &"low_poly_character_anims/idle"
	
	match state:
		State.IDLE:
			new_animation = &"low_poly_character_anims/idle"
		State.WAITING_TO_MOVE:
			new_animation = &"low_poly_character_anims/idle"
		State.MOVING:
			new_animation = &"low_poly_character_anims/Walk"

	if new_animation != current_animation:
		$AnimationPlayer.play(new_animation)
		current_animation = new_animation


func blink(delta: float) -> void:
	if blink_progress < 0.0:
		blink_timer -= delta

		if blink_timer <= 0.0:
			blink_progress = 0.0
	else:
		blink_progress += delta / blink_duration

		var blink_amount: float = lerp(
			blink_min_value,
			blink_max_value,
			1.0 - abs(blink_progress * 2.0 - 1.0)
		)

		body_mesh.set_blend_shape_value(0, blink_amount)

		if blink_progress >= 1.0:
			blink_progress = -1.0

			if double_blink_pending:
				double_blink_pending = false
				blink_timer = randf_range(blink_min_time, blink_max_time)
			elif randf() < double_blink_chance:
				double_blink_pending = true
				blink_timer = double_blink_delay
			else:
				blink_timer = randf_range(blink_min_time, blink_max_time)


func update_idle_look(delta: float) -> void:
	var grounded: bool = network_is_grounded

	if is_multiplayer_authority():
		grounded = is_on_floor()

	if not grounded:
		look_target = null
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			0.0,
			look_speed * delta
		)
		return

	look_target = find_nearest_player()
	

	if look_target != null:
		look_at_modifier.target_node = look_target.get_node("LookTarget").get_path()
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			1.0,
			look_speed * delta
		)
	else:
		look_at_modifier.influence = move_toward(
			look_at_modifier.influence,
			0.0,
			look_back_speed * delta
		)
		
		
func find_nearest_player() -> Node3D:
	var nearest_player: Node3D = null
	var nearest_distance: float = look_distance
	var max_angle: float = deg_to_rad(look_angle)
	var min_dot: float = cos(max_angle)

	for player in get_parent().get_children():
		if player == self or not player is CharacterBody3D:
			continue

		var to_player: Vector3 = player.global_position - global_position
		var distance: float = to_player.length()

		if distance >= nearest_distance:
			continue

		var direction: Vector3 = to_player.normalized()
		var forward: Vector3 = -$Armature.global_transform.basis.z

		if forward.dot(direction) < min_dot:
			continue

		nearest_distance = distance
		nearest_player = player

	return nearest_player
