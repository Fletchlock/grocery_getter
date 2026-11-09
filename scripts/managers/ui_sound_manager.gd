extends Node

var hover_sound: AudioStream = preload("res://assets/sounds/button_hover_click.wav")
var click_sound: AudioStream = preload("res://assets/sounds/button_select_click.wav")
var slider_sound: AudioStream = preload("res://assets/sounds/slider_tick.wav")

var hover_player: AudioStreamPlayer
var click_player: AudioStreamPlayer
var slider_player: AudioStreamPlayer
var slider_sound_cooldown: float = 0.05
var slider_sound_timer: float = 0.0

func _ready() -> void:
	hover_player = AudioStreamPlayer.new()
	hover_player.bus = "UI"
	add_child(hover_player)

	click_player = AudioStreamPlayer.new()
	click_player.bus = "UI"
	add_child(click_player)
	
	slider_player = AudioStreamPlayer.new()
	slider_player.bus = "UI"
	add_child(slider_player)


func _process(delta: float) -> void:
	if slider_sound_timer > 0.0:
		slider_sound_timer -= delta



func play_hover() -> void:
	if hover_sound == null:
		return

	hover_player.stream = hover_sound
	hover_player.play()


func play_click() -> void:
	if click_sound == null:
		return

	click_player.stream = click_sound
	click_player.play()
	

func play_slider() -> void:
	if slider_sound == null or slider_sound_timer > 0.0:
		return

	slider_sound_timer = slider_sound_cooldown
	slider_player.stream = slider_sound
	slider_player.play()
