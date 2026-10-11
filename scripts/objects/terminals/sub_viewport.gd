extends SubViewport


func _ready() -> void:
	self.transparent_bg = false
	self.gui_disable_input = true
	
	var panel = get_node_or_null("PanelContainer")
	if not panel:
		return
		
	# 1. Ensure the panel matches the exact pixel resolution of the viewport
	panel.custom_minimum_size = self.size
	panel.size = self.size
	
	# 2. Add an internal margin so text never hugs the physical screen edge
	# This adds a 20-pixel safe buffer all around the screen
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 20)
	margin_container.add_theme_constant_override("margin_bottom", 20)
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_right", 20)
	
	# 3. Restructure the nodes safely via code to enforce the padding
	var vbox = panel.get_node_or_null("VBoxContainer")
	if vbox:
		# Reparent the VBox container inside our new safe margin layout
		panel.remove_child(vbox)
		panel.add_child(margin_container)
		margin_container.add_child(vbox)
		
		# Set the VBox to fill the vertical space cleanly
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# 4. Apply our dark monitor styling
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color.hex(0x111116) 
	panel.add_theme_stylebox_override("panel", style_box)
	
	_load_debug_ui()


func _load_debug_ui() -> void:
	var time_label = get_node_or_null("PanelContainer/VBoxContainer/TimeLabel")
	if time_label:
		time_label.text = "Day 1 — 12:00 PM"
		time_label.add_theme_color_override("font_color", Color.WHITE)
		time_label.add_theme_font_size_override("font_size", 36) # Ensure it's large enough to see
