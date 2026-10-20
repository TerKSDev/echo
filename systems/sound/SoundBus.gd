extends Node
class_name SoundBus
## Routes every sound in the game: player sounds, Screamer shrieks and Listener alarms.
## It draws the echo wave and tells the right enemies / player what happened.

const BASE_RADIUS := 40.0           # Range of a near-silent sound
const RADIUS_PER_LOUDNESS := 660.0  # Extra range per 1.0 of loudness
const WAVE_SPEED := 400.0           # Matches EchoLayer.WAVE_SPEED

var _player: Node2D
var _echo: Node2D


func setup(player: Node2D, echo_layer: Node2D) -> void:
	_player = player
	_echo = echo_layer
	_player.sound_emitted.connect(_on_player_sound)


# Call after a level is loaded so every enemy in it is wired up
func connect_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		if not enemy.screamed.is_connected(_on_enemy_screamed):
			enemy.screamed.connect(_on_enemy_screamed)
		if not enemy.alarmed.is_connected(_on_enemy_alarmed):
			enemy.alarmed.connect(_on_enemy_alarmed)


func _enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy):
			result.append(enemy)
	return result


func _on_player_sound(pos: Vector2, loudness: float, is_voice: bool) -> void:
	var radius := BASE_RADIUS + loudness * RADIUS_PER_LOUDNESS
	var exclude: Array[RID] = [_player.get_rid()]
	_echo.emit_echo(pos, radius, exclude, is_voice)
	for enemy in _enemies():
		enemy.on_sound(pos, loudness, radius, is_voice)


# Screamer: big wave, attracts nearby monsters, immobilizes the player if hit
func _on_enemy_screamed(pos: Vector2, radius: float) -> void:
	var no_exclude: Array[RID] = []
	_echo.emit_echo(pos, radius, no_exclude, true)

	if is_instance_valid(_player) and _player.alive:
		var dist: float = _player.global_position.distance_to(pos)
		if dist <= radius:
			# The wave takes time to reach the player
			get_tree().create_timer(dist / WAVE_SPEED).timeout.connect(func():
				if is_instance_valid(_player) and _player.alive:
					_player.immobilize(1.6)
			)

	for enemy in _enemies():
		enemy.on_sound(pos, 0.95, radius, true)


# Listener: map-wide pulse, every monster rushes to the Listener and gets faster
func _on_enemy_alarmed(pos: Vector2, _target_pos: Vector2) -> void:
	var no_exclude: Array[RID] = []
	_echo.emit_echo(pos, 1100.0, no_exclude, true)

	if is_instance_valid(_player) and _player.alive:
		_player.camera_shake(0.65, 8.0)

	for enemy in _enemies():
		enemy.force_alert_to(pos)
		enemy.apply_speed_boost(1.25, 6.0)
