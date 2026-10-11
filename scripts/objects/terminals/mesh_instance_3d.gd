extends MeshInstance3D

@export var target_viewport: SubViewport 

func _ready() -> void:
	if not target_viewport:
		push_error("Screen Error: Please assign the SubViewport node to target_viewport!")
		return

	# 1. Force the SubViewport to instantly process its internal 2D drawing loops
	target_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# 2. Wait for the engine's 2D canvas layer to finish drafting its layouts
	await get_tree().process_frame
	
	# 3. Wait an extra frame for the 3D rendering pipeline to register the graphics memory buffer
	await get_tree().process_frame
	
	# 4. Generate the material completely clear of editor settings
	var runtime_material = StandardMaterial3D.new()
	
	# 5. Grab the live texture 
	var live_texture = target_viewport.get_texture()
	
	# 6. Apply settings that bypass uninitialized frame caching
	runtime_material.albedo_texture = live_texture
	runtime_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Fixes lighting washouts
	
	# 7. Bind to your second surface slot (Surface 1)
	set_surface_override_material(1, runtime_material)
	
	# 8. Force Godot to redraw the SubViewport one final time to flush out the white frame
	target_viewport.notify_property_list_changed()
