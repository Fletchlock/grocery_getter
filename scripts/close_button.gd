extends Button

# Close the game when the X is clicked
func _on_pressed() -> void:
	self.visible = true
	get_tree().quit()
