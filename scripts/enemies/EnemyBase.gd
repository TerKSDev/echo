extends CharacterBody2D
class_name EnemyBase
## 敌人基类占位：你朋友可在此扩展 AI。
## 约定：
## 1) 加入 group "enemies"（EnemySpawn 会自动加）
## 2) 可选 meta "echo_color" 让回声照亮
## 3) 监听玩家 sound_emitted（在 setup 里连接）做听觉追踪

@export var move_speed := 60.0
@export var hear_range := 280.0

var _hear_mult := 1.0
var _player: Node2D


func _ready() -> void:
	if not is_in_group("enemies"):
		add_to_group("enemies")
	set_meta("echo_color", Color(1.0, 0.35, 0.35))
	if has_meta("hear_multiplier"):
		_hear_mult = float(get_meta("hear_multiplier"))
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		_player = get_node_or_null("/root/Node2D/Player")
	if _player and _player.has_signal("sound_emitted"):
		if not _player.sound_emitted.is_connected(_on_sound_emitted):
			_player.sound_emitted.connect(_on_sound_emitted)


func setup_from_spawn(spawn: Node) -> void:
	if spawn and "hear_multiplier" in spawn:
		_hear_mult = spawn.hear_multiplier


func _on_sound_emitted(pos: Vector2, loudness: float, _is_voice: bool) -> void:
	var range := hear_range * _hear_mult * (0.6 + loudness)
	if global_position.distance_to(pos) <= range:
		# 占位：听到声音时面向声源。朋友可改成寻路追击。
		look_at(pos)
