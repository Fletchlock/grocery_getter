extends GPUParticles3D


func _ready() -> void:
	emitting = false

	finished.connect(_on_finished)

	restart()
	emitting = true


func _on_finished() -> void:
	queue_free()
