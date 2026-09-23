extends RayCast3D

@export var prompt_label: Label

var current_interactable: Node3D = null
var current_outline_mesh: MeshInstance3D = null

func _process(_delta: float) -> void:
	if is_colliding():
		var collider = get_collider()
		
		if collider and collider.is_in_group("interactable_items"):
			if current_interactable != collider:
				_clear_highlight()
				
				current_interactable = collider
				
				# Find the outline mesh we created inside the box
				# (Change "MeshInstance3D_Outline" to match your node's exact name)
				current_outline_mesh = collider.get_node_or_null("MeshOutline")
				
				# Turn on the outline and the UI text
				if current_outline_mesh:
					current_outline_mesh.visible = true
				if prompt_label:
					prompt_label.visible = true
			return

	_clear_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and current_interactable:
		var item = current_interactable
		_clear_highlight()
		item.queue_free()

func _clear_highlight() -> void:
	if current_outline_mesh:
		current_outline_mesh.visible = false
		current_outline_mesh = null
		
	current_interactable = null
	if prompt_label:
		prompt_label.visible = false
