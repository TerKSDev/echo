extends Node2D

const BASE_RADIUS := 40.0 # Range of a near-silent sound
const RADIUS_PER_LOUDNESS := 660.0 # Extra range per 1.0 of loudness

# Heartbeat parameters
const HEARTBEAT_AUDIO_PATH := "res://audio/heartbeat.mp3"
@export var heartbeat_interval_calm := 1.25   # 平常心跳间隔（秒）
@export var heartbeat_interval_panic := 0.42  # 极度靠近 / 被追击时心跳间隔（秒，极度急促）
@export var heartbeat_vol_calm := 6.0         # 平常音量（大幅提高增益，正常耳机音量下清晰可辨）
@export var heartbeat_vol_panic := 8.0       # 极度靠近 / 被追击时音量（响亮震撼）
@export var heartbeat_pitch_calm := 0.95      # 平常音调
@export var heartbeat_pitch_panic := 1.15     # 危险音调（稍高发紧）

var _heartbeat_stream: AudioStream
var _heartbeat_players: Array[AudioStreamPlayer] = []
var _player_idx := 0
var _heartbeat_timer := 0.0
var _current_threat := 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Player.sound_emitted.connect(_on_sound_emitted)
	$Player.died.connect(_on_player_died)
	_setup_heartbeat()

func _setup_heartbeat() -> void:
	if ResourceLoader.exists(HEARTBEAT_AUDIO_PATH):
		_heartbeat_stream = load(HEARTBEAT_AUDIO_PATH)
		# 创建两个播放器交替播放，急促时上一声的余韵不会被直接截断
		for i in 2:
			var p := AudioStreamPlayer.new()
			p.stream = _heartbeat_stream
			p.bus = &"Master"
			add_child(p)
			_heartbeat_players.append(p)

func _process(delta: float) -> void:
	_update_heartbeat(delta)

func _update_heartbeat(delta: float) -> void:
	if _heartbeat_players.is_empty():
		return
	
	if not is_instance_valid($Player) or not $Player.alive:
		for p in _heartbeat_players:
			if p.playing:
				p.stop()
		return

	# 计算当前场景中所有敌人对玩家的最大威胁度 (0.0 ~ 1.0)
	var max_threat := 0.0
	var player_pos: Vector2 = $Player.global_position
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy):
			max_threat = maxf(max_threat, enemy.get_threat_level(player_pos))
	
	# 快速上升、平缓下降，营造紧张刺激感
	var rate := 3.5 if max_threat > _current_threat else 1.0
	_current_threat = move_toward(_current_threat, max_threat, delta * rate)

	var interval := lerpf(heartbeat_interval_calm, heartbeat_interval_panic, _current_threat)
	var vol := lerpf(heartbeat_vol_calm, heartbeat_vol_panic, _current_threat)
	var pitch := lerpf(heartbeat_pitch_calm, heartbeat_pitch_panic, _current_threat)

	_heartbeat_timer += delta
	if _heartbeat_timer >= interval:
		_heartbeat_timer = 0.0
		var p := _heartbeat_players[_player_idx]
		_player_idx = (_player_idx + 1) % _heartbeat_players.size()
		p.volume_db = vol
		p.pitch_scale = pitch
		p.play()

func _on_sound_emitted(pos: Vector2, loudness: float, is_voice: bool) -> void:
	var radius := BASE_RADIUS + loudness * RADIUS_PER_LOUDNESS
	var exclude: Array[RID] = [$Player.get_rid()]
	$EchoLayer.emit_echo(pos, radius, exclude, is_voice)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.on_sound(pos, loudness, radius)

func _on_player_died() -> void:
	# Flash intense crimson death vignette and shake screen
	if has_node("Hud/Vignette"):
		var vig: ColorRect = $Hud/Vignette
		var mat: ShaderMaterial = vig.material as ShaderMaterial
		if mat != null:
			var tw := create_tween()
			tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.65, 0.05, 0.08, 0.95), 0.08)
			tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.01, 0.035, 0.07, 0.7), 0.9)

	await get_tree().create_timer(1.1).timeout
	get_tree().reload_current_scene()
