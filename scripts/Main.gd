extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Player.sound_emitted.connect(_on_sound_emitted)

const BASE_RADIUS := 40.0 # Range of a near-silent sound
const RADIUS_PER_LOUDNESS := 660.0 # Extra range per 1.0 of loudness

func _on_sound_emitted(pos: Vector2, loudness: float, is_voice: bool) -> void:
	var exclude: Array[RID] = [$Player.get_rid()]
	$EchoLayer.emit_echo(pos, BASE_RADIUS + loudness * RADIUS_PER_LOUDNESS, exclude, is_voice)
