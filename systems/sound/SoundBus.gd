extends Node
class_name SoundBus
## Routes every sound in the game: player sounds, Screamer shrieks and Listener alarms.
## It draws the echo wave and tells the right enemies / player what happened.

const BASE_RADIUS := 40.0           # Range of a near-silent sound
const RADIUS_PER_LOUDNESS := 660.0  # Extra range per 1.0 of loudness
const WAVE_SPEED := 400.0           # Matches EchoLayer.WAVE_SPEED

signal offscreen_sound_emitted(pos: Vector2, color: Color)

var _player: Node2D
var _echo: Node2D
var _sfx: SfxManager


func _ready() -> void:
	add_to_group("sound_bus")


func setup(player: Node2D, echo_layer: Node2D, sfx: SfxManager = null) -> void:
	_player = player
	_echo = echo_layer
	_sfx = sfx
	_player.sound_emitted.connect(_on_player_sound)


# Call after a level is loaded so every enemy in it is wired up
func connect_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		if not enemy.woke_up.is_connected(_on_enemy_woke_up):
			enemy.woke_up.connect(_on_enemy_woke_up.bind(enemy))
		if not enemy.step_taken.is_connected(_on_enemy_step):
			enemy.step_taken.connect(_on_enemy_step)
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


func _on_player_sound(pos: Vector2, loudness: float, is_voice: bool, is_sneak: bool = false) -> void:
	if _sfx != null:
		if is_voice:
			_sfx.play_echo_ping(loudness)
		elif is_sneak or loudness <= 0.05:
			_sfx.play_step_sneak()
		else:
			_sfx.play_step_walk()

	var radius := BASE_RADIUS + loudness * RADIUS_PER_LOUDNESS
	var exclude: Array[RID] = [_player.get_rid()]
	var w_col: Color = GameState.get_sonar_color()
	if is_instance_valid(_player) and _player.get("water_count") != null and _player.water_count > 0 and not is_voice:
		w_col = w_col.lerp(Color(0.28, 0.75, 1.0), 0.45)
	_echo.emit_echo(pos, radius, exclude, is_voice, w_col)
	for enemy in _enemies():
		enemy.on_sound(pos, loudness, radius, is_voice, is_sneak)


# Decoy Pebble clatter: emits an amber acoustic ripple that bounces off walls,
# reveals the area, and distracts nearby enemies toward the impact point without ruining ghost rating.
func emit_decoy_sound(pos: Vector2, loudness: float = 0.38, radius: float = 260.0) -> void:
	if _sfx != null:
		_sfx.play_pebble_clatter(pos)
	var exclude: Array[RID] = []
	if is_instance_valid(_player):
		exclude.append(_player.get_rid())
	var pebble_color := Color(1.0, 0.78, 0.28) # Warm golden amber ripple
	_echo.emit_echo(pos, radius, exclude, true, pebble_color)
	offscreen_sound_emitted.emit(pos, pebble_color)
	for enemy in _enemies():
		enemy.on_decoy_sound(pos, loudness, radius)


func _on_enemy_woke_up(pos: Vector2, enemy: Enemy) -> void:
	if _sfx == null or not is_instance_valid(enemy):
		return
	offscreen_sound_emitted.emit(pos, Color(1.0, 0.55, 0.25))
	match enemy.enemy_type:
		Enemy.EnemyType.SCREAMER:
			_sfx.play_screamer_crack(pos, enemy.is_wall_occluded)
		Enemy.EnemyType.LISTENER:
			_sfx.play_listener_pip(pos, enemy.listener_count, enemy.is_wall_occluded)
		_:
			_sfx.play_monster_roar(pos, int(enemy.enemy_type), enemy.is_wall_occluded)


func _on_enemy_step(pos: Vector2, is_chasing: bool, occluded: bool) -> void:
	if _sfx != null:
		_sfx.play_enemy_step(pos, is_chasing, occluded)


# Screamer: big wave, attracts nearby monsters, immobilizes the player if hit
func _on_enemy_screamed(pos: Vector2, radius: float) -> void:
	offscreen_sound_emitted.emit(pos, Color(1.0, 0.25, 0.52))
	if _sfx != null:
		_sfx.play_screamer_shriek(pos)
	var no_exclude: Array[RID] = []
	_echo.emit_echo(pos, radius, no_exclude, true, Color(1.0, 0.28, 0.52))

	if is_instance_valid(_player) and _player.alive:
		var dist: float = _player.global_position.distance_to(pos)
		if dist <= radius:
			var arrival_time: float = maxf(0.01, dist / WAVE_SPEED)
			get_tree().create_timer(arrival_time).timeout.connect(func():
				if is_instance_valid(_player) and _player.alive:
					var cur_dist: float = _player.global_position.distance_to(pos)
					if cur_dist <= radius:
						# Walls block the scream's physical shockwave: taking cover shields the player
						var space := _player.get_world_2d().direct_space_state
						var query := PhysicsRayQueryParameters2D.create(pos, _player.global_position)
						query.collision_mask = 1
						query.exclude = [_player.get_rid()]
						var hit: Dictionary = space.intersect_ray(query)
						var in_cover: bool = not hit.is_empty()

						if not in_cover:
							if _sfx != null:
								_sfx.play_player_stun()
							_player.immobilize(1.6)
			)

	for enemy in _enemies():
		enemy.on_sound(pos, 0.95, radius, true)


# Listener: map-wide pulse, every monster rushes to the Listener and gets faster
func _on_enemy_alarmed(pos: Vector2, _target_pos: Vector2) -> void:
	offscreen_sound_emitted.emit(pos, Color(1.0, 0.75, 0.2))
	if _sfx != null:
		_sfx.play_listener_alarm(pos)
	var no_exclude: Array[RID] = []
	_echo.emit_echo(pos, 1100.0, no_exclude, true, Color(1.0, 0.38, 0.16))

	if is_instance_valid(_player) and _player.alive:
		_player.camera_shake(0.65, 8.0)

	for enemy in _enemies():
		enemy.force_alert_to(pos)
		enemy.apply_speed_boost(1.25, 6.0)
