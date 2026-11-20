
extends Node
class_name ScannerFlash

@export var scanner_mesh: MeshInstance3D
@export_range(0, 20) var surface_index: int = 4

@export_group("Flash Settings")
@export var flash_color: Color = Color(0.1, 1.0, 0.2, 1.0)
@export_range(0.0, 16.0, 0.1) var flash_energy: float = 5.0
@export_range(0.05, 2.0, 0.05) var flash_duration: float = 0.25

var scanner_material: StandardMaterial3D
var flash_tween: Tween


func _ready() -> void:
	if scanner_mesh == null or scanner_mesh.mesh == null:
		push_warning("ScannerFlash: Scanner mesh not assigned.")
		return

	if surface_index >= scanner_mesh.mesh.get_surface_count():
		push_warning("ScannerFlash: Invalid surface index.")
		return

	var original_material: Material = scanner_mesh.get_active_material(
		surface_index
	)

	if not original_material is StandardMaterial3D:
		push_warning("ScannerFlash: Surface material must be StandardMaterial3D.")
		return

	# Give this checkout its own material instance.
	scanner_material = original_material.duplicate() as StandardMaterial3D

	scanner_mesh.set_surface_override_material(
		surface_index,
		scanner_material
	)

	# Preserve the original dull green appearance.
	scanner_material.emission_enabled = true
	scanner_material.emission = flash_color
	scanner_material.emission_energy_multiplier = 0.0


func flash() -> void:
	if scanner_material == null:
		return

	if flash_tween != null and flash_tween.is_running():
		flash_tween.kill()

	scanner_material.emission = flash_color
	scanner_material.emission_energy_multiplier = flash_energy

	flash_tween = create_tween()
	flash_tween.tween_property(
		scanner_material,
		"emission_energy_multiplier",
		0.0,
		flash_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
