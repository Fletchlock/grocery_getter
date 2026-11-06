extends Control

@onready var master_slider: Slider = $MarginContainer/VBoxContainer/MasterContainer/MasterSlider
@onready var music_slider: Slider = $MarginContainer/VBoxContainer/MusicContainer/MusicSlider
@onready var sfx_slider: Slider = $MarginContainer/VBoxContainer/SFXContainer/SFXSlider


func _ready() -> void:
	master_slider.set_value_no_signal(SettingsManager.master_volume)
	music_slider.set_value_no_signal(SettingsManager.music_volume)
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume)

	master_slider.value_changed.connect(SettingsManager.set_master_volume)
	music_slider.value_changed.connect(SettingsManager.set_music_volume)
	sfx_slider.value_changed.connect(SettingsManager.set_sfx_volume)


func _on_master_slider_value_changed(value: float) -> void:
	SettingsManager.set_master_volume(value)
	SettingsManager.save_settings()


func _on_music_slider_value_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)
	SettingsManager.save_settings()


func _on_sfx_slider_value_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value)
	SettingsManager.save_settings()
