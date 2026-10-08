extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Player.sound_emitted.connect(_on_sound_emitted)

func _on_sound_emitted(pos: Vector2, loudness: float, is_voice: bool) -> void:
	var exclude: Array[RID] = [$Player.get_rid()]
	$EchoLayer.emit_echo(pos, 150.0 + loudness * 500.0, exclude, is_voice)
