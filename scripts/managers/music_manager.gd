# MusicManager.gd
extends Node

@onready var player: AudioStreamPlayer = $AudioStreamPlayer

var intro: AudioStream = preload("res://assets/music/DjangoIntro.wav")
var loop: AudioStream = preload("res://assets/music/DjangoLoop.wav")

func _ready() -> void:
	player.finished.connect(_on_music_finished)
	player.stream = intro


func play_music(track: AudioStream) -> void:
	if player.stream == track and player.playing:
		return
	player.stream = track
	player.play()


func stop_music() -> void:
	player.stop()


func _on_music_finished() -> void:
	if player.stream == intro:
		player.stream = loop
		player.play()
