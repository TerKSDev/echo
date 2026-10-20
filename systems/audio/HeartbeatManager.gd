extends Node
class_name HeartbeatManager
## Plays a heartbeat whose speed/volume/pitch follows the highest enemy threat.
## Emits `beat` on every heartbeat so the HUD can pulse the vignette in sync.

signal beat(threat: float)

const HEARTBEAT_AUDIO_PATH := "res://audio/heartbeat.mp3"

@export var interval_calm := 1.25   # Seconds between beats when safe
@export var interval_panic := 0.42  # Seconds between beats when hunted
@export var vol_calm := 6.0
@export var vol_panic := 8.0
@export var pitch_calm := 0.95
@export var pitch_panic := 1.15

var _players: Array[AudioStreamPlayer] = []
var _player_idx := 0
var _timer := 0.0
var _threat := 0.0


func _ready() -> void:
	if not ResourceLoader.exists(HEARTBEAT_AUDIO_PATH):
		return
	var stream: AudioStream = load(HEARTBEAT_AUDIO_PATH)
	# Two alternating players so a fast beat does not cut off the previous tail
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = &"Master"
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	if _players.is_empty():
		return

	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.alive:
		for p in _players:
			if p.playing:
				p.stop()
		return

	# Highest threat among all enemies (0.0 ~ 1.0)
	var max_threat := 0.0
	var player_pos: Vector2 = player.global_position
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy):
			max_threat = maxf(max_threat, enemy.get_threat_level(player_pos))

	# Rises fast, falls slowly
	var rate := 3.5 if max_threat > _threat else 1.0
	_threat = move_toward(_threat, max_threat, delta * rate)

	_timer += delta
	if _timer >= lerpf(interval_calm, interval_panic, _threat):
		_timer = 0.0
		var p := _players[_player_idx]
		_player_idx = (_player_idx + 1) % _players.size()
		p.volume_db = lerpf(vol_calm, vol_panic, _threat)
		p.pitch_scale = lerpf(pitch_calm, pitch_panic, _threat)
		p.play()
		beat.emit(_threat)
