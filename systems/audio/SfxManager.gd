extends Node
class_name SfxManager
## Unified procedural audio & heartbeat manager for ECHO.
## Generates all sound effects and the dynamic "lub-dub" threat heartbeat in memory
## as 16-bit PCM WAV streams on startup (zero external audio files needed).

signal beat(threat: float)

const MIX_RATE := 44100

# Heartbeat parameters
@export var interval_calm := 1.30   # Seconds between beats when safe (~46 BPM)
@export var interval_panic := 0.35  # Seconds between beats when hunted (~170 BPM)
@export var vol_calm := -11.0       # Quiet subtle pulse when safe
@export var vol_panic := 3.2        # Pounding chest thump when hunted
@export var pitch_calm := 0.88
@export var pitch_panic := 1.22

var _hb_players: Array[AudioStreamPlayer] = []
var _hb_idx := 0
var _hb_timer := 0.0
var _threat := 0.0

var _wav_steps_walk: Array[AudioStreamWAV] = []
var _wav_steps_sneak: Array[AudioStreamWAV] = []
var _wav_steps_water: Array[AudioStreamWAV] = []
var _last_walk_idx := -1
var _last_sneak_idx := -1
var _last_water_idx := -1

var _ambient_drone_player: AudioStreamPlayer
var _wav_abyssal_drone: AudioStreamWAV
var _wav_cave_droplet: AudioStreamWAV
var _droplet_timer := 5.0

var _wav_enemy_step: AudioStreamWAV
var _wav_echo_ping: AudioStreamWAV
var _wav_charge_full: AudioStreamWAV
var _wav_roar_sleeper: AudioStreamWAV
var _wav_roar_patroller: AudioStreamWAV
var _wav_roar_chaser: AudioStreamWAV
var _wav_sleeper_snore: AudioStreamWAV
var _wav_screamer_crack: AudioStreamWAV
var _wav_screamer_shriek: AudioStreamWAV
var _wav_listener_pip: AudioStreamWAV
var _wav_listener_alarm: AudioStreamWAV
var _wav_player_stun: AudioStreamWAV
var _wav_player_death: AudioStreamWAV
var _wav_level_intro: AudioStreamWAV
var _wav_level_exit: AudioStreamWAV
var _wav_victory_fanfare: AudioStreamWAV
var _wav_sneak_toggle: AudioStreamWAV
var _wav_charge_loop: AudioStreamWAV
var _wav_star_chimes: Array[AudioStreamWAV] = []
var _wav_pebble_clatter: AudioStreamWAV
var _wav_pebble_clink: AudioStreamWAV
var _wav_deny_tick: AudioStreamWAV
var _wav_exit_beacon: AudioStreamWAV
var _wav_wall_echo: AudioStreamWAV
var _wav_cane_tap: AudioStreamWAV
var _wav_wall_bump: AudioStreamWAV
var _wav_assist_on: AudioStreamWAV
var _wav_assist_off: AudioStreamWAV
var _wav_door_open: AudioStreamWAV
var _wav_inv_pip: AudioStreamWAV

var _charge_player: AudioStreamPlayer
var _player_ref: Node2D
static var _cache: Dictionary = {}

const NON_SPATIAL_POOL_SIZE := 6
const SPATIAL_POOL_SIZE := 8

var _non_spatial_pool: Array[AudioStreamPlayer] = []
var _non_spatial_idx := 0

var _spatial_pool: Array[AudioStreamPlayer2D] = []
var _spatial_idx := 0


func _ready() -> void:
	add_to_group("sfx_manager")
	_build_all_streams()
	_setup_charge_player()
	_setup_heartbeat_players()
	_setup_audio_pools()
	_setup_ambient_drone()


func _process(delta: float) -> void:
	_process_heartbeat(delta)
	_process_ambient_subterranean(delta)


func set_player(player: Node2D) -> void:
	_player_ref = player


# Optional brief mic suppression only on extreme speaker bursts if needed
func _suppress_mic(_duration: float) -> void:
	pass


# --- Public Playback API -----------------------------------------------------

func play_step_walk() -> void:
	_suppress_mic(0.18)
	if _wav_steps_walk.is_empty():
		return
	var idx := randi() % _wav_steps_walk.size()
	if idx == _last_walk_idx and _wav_steps_walk.size() > 1:
		idx = (idx + 1) % _wav_steps_walk.size()
	_last_walk_idx = idx
	_play_non_spatial(_wav_steps_walk[idx], -5.5, randf_range(0.96, 1.04))


func play_step_sneak() -> void:
	if _wav_steps_sneak.is_empty():
		return
	var idx := randi() % _wav_steps_sneak.size()
	if idx == _last_sneak_idx and _wav_steps_sneak.size() > 1:
		idx = (idx + 1) % _wav_steps_sneak.size()
	_last_sneak_idx = idx
	_play_non_spatial(_wav_steps_sneak[idx], -13.5, randf_range(0.97, 1.03))


func play_step_water(is_sneak: bool) -> void:
	if _wav_steps_water.is_empty():
		return
	var idx := randi() % _wav_steps_water.size()
	if idx == _last_water_idx and _wav_steps_water.size() > 1:
		idx = (idx + 1) % _wav_steps_water.size()
	_last_water_idx = idx
	var vol_db: float = -12.0 if is_sneak else -5.0
	var pitch: float = randf_range(0.96, 1.06) if is_sneak else randf_range(0.92, 1.04)
	_play_non_spatial(_wav_steps_water[idx], vol_db, pitch)


func play_sleeper_snore(pos: Vector2, occluded: bool = false) -> void:
	var vol_db: float = -18.0 if occluded else -12.5
	_play_spatial(_wav_sleeper_snore, pos, vol_db, randf_range(0.94, 1.04), 320.0)


func play_echo_ping(loudness: float) -> void:
	_suppress_mic(0.45)
	var vol_db: float = lerpf(-10.0, 2.0, clampf(loudness, 0.0, 1.0))
	var pitch: float = lerpf(1.12, 0.88, clampf(loudness, 0.0, 1.0))
	_play_non_spatial(_wav_echo_ping, vol_db, pitch)


func play_charge_full() -> void:
	_suppress_mic(0.2)
	_play_non_spatial(_wav_charge_full, -4.0, 1.0)


func update_charge_hum(charging: bool, charge_amount: float) -> void:
	if _charge_player == null:
		return
	if charging:
		if not _charge_player.playing:
			_charge_player.play()
		_charge_player.volume_db = lerpf(-22.0, -6.0, charge_amount)
		_charge_player.pitch_scale = lerpf(0.75, 1.65, charge_amount)
	else:
		if _charge_player.playing:
			_charge_player.stop()


func play_player_stun() -> void:
	_suppress_mic(0.5)
	_play_non_spatial(_wav_player_stun, 0.0, 1.0)


func play_player_death() -> void:
	_suppress_mic(0.8)
	update_charge_hum(false, 0.0)
	_play_non_spatial(_wav_player_death, 2.0, 1.0)


func play_level_intro() -> void:
	_suppress_mic(0.55)
	_play_non_spatial(_wav_level_intro, -3.0, 1.0)


func play_level_exit() -> void:
	_suppress_mic(0.4)
	_play_non_spatial(_wav_level_exit, -2.0, 1.0)


func play_victory_fanfare() -> void:
	_suppress_mic(1.8)
	_play_non_spatial(_wav_victory_fanfare, 1.0, 1.0)


func play_star_chime(index: int) -> void:
	if _wav_star_chimes.is_empty():
		return
	var idx := clampi(index, 0, _wav_star_chimes.size() - 1)
	_play_non_spatial(_wav_star_chimes[idx], -2.5, 1.0)


func play_pebble_clatter(pos: Vector2) -> void:
	_suppress_mic(0.3)
	_play_spatial(_wav_pebble_clatter, pos, 2.0, randf_range(0.95, 1.08), 650.0)


func play_pebble_clink(pos: Vector2) -> void:
	_suppress_mic(0.2)
	_play_spatial(_wav_pebble_clink, pos, 2.2, randf_range(0.96, 1.08), 580.0)


func play_deny_tick() -> void:
	_play_non_spatial(_wav_deny_tick, -6.0, 1.0)


# Visually Impaired (Blind) Echolocation & Navigation Audio API:
func play_exit_beacon(pos: Vector2, is_near: bool = false, dist: float = 200.0, max_dist: float = 380.0) -> void:
	var ratio: float = clampf(dist / maxf(max_dist, 1.0), 0.0, 1.0)
	var vol_db: float = lerpf(0.5, -11.0, ratio)
	var pitch: float = 1.06 if is_near else 1.0
	_play_spatial(_wav_exit_beacon, pos, vol_db, pitch, max_dist * 1.15)


func play_wall_echo(pos: Vector2, dist: float, max_range: float) -> void:
	var ratio: float = clampf(dist / maxf(max_range, 1.0), 0.0, 1.0)
	var vol_db: float = lerpf(-4.0, -18.0, ratio)
	var pitch: float = lerpf(1.35, 0.85, ratio)
	_play_spatial(_wav_wall_echo, pos, vol_db, pitch, 650.0)


func play_cane_tap(dist: float) -> void:
	var pitch: float = lerpf(1.35, 0.92, clampf(dist / 50.0, 0.0, 1.0))
	_play_non_spatial(_wav_cane_tap, -6.5, pitch)


func play_wall_bump() -> void:
	_play_non_spatial(_wav_wall_bump, -3.5, randf_range(0.95, 1.05))


func play_assist_toggle(enabled: bool) -> void:
	_play_non_spatial(_wav_assist_on if enabled else _wav_assist_off, 0.0, 1.0)


func play_door_open(pos: Vector2) -> void:
	_suppress_mic(0.4)
	_play_spatial(_wav_door_open, pos, 1.5, 1.0, 1400.0)


func play_inventory_pips(count: int) -> void:
	if count <= 0:
		play_deny_tick()
		return
	for i in count:
		get_tree().create_timer(float(i) * 0.11).timeout.connect(func():
			_play_non_spatial(_wav_inv_pip, -3.0, 1.0 + float(i) * 0.16)
		)


func play_sneak_toggle(entering_sneak: bool) -> void:
	var pitch: float = 0.82 if entering_sneak else 1.18
	_play_non_spatial(_wav_sneak_toggle, -10.0, pitch)


func play_monster_roar(pos: Vector2, enemy_type: int, occluded: bool = false) -> void:
	_suppress_mic(0.65)
	var stream: AudioStreamWAV = _wav_roar_patroller
	var pitch: float = randf_range(0.94, 1.06)
	match enemy_type:
		0: # SLEEPER - deep guttural roar
			stream = _wav_roar_sleeper
			pitch = randf_range(0.88, 0.98)
		1: # PATROLLER - mid metallic rasp roar
			stream = _wav_roar_patroller
			pitch = randf_range(0.95, 1.05)
		2: # CHASER - feral high-aggression shriek-roar
			stream = _wav_roar_chaser
			pitch = randf_range(1.02, 1.12)
	var vol_db: float = -7.0 if occluded else 1.5
	_play_spatial(stream, pos, vol_db, pitch, 650.0)


func play_screamer_crack(pos: Vector2, occluded: bool = false) -> void:
	_suppress_mic(0.35)
	var vol_db: float = -8.0 if occluded else -1.0
	_play_spatial(_wav_screamer_crack, pos, vol_db, randf_range(0.96, 1.04), 600.0)


func play_screamer_shriek(pos: Vector2) -> void:
	_suppress_mic(0.9)
	_play_spatial(_wav_screamer_shriek, pos, 3.0, 1.0, 800.0)


func play_listener_pip(pos: Vector2, count: int, occluded: bool = false) -> void:
	_suppress_mic(0.3)
	# Pitch rises with each recorded shout (1..4) to build tension
	var pitch: float = 0.85 + float(clampi(count, 1, 5)) * 0.14
	var vol_db: float = -7.0 if occluded else 0.0
	_play_spatial(_wav_listener_pip, pos, vol_db, pitch, 700.0)


func play_listener_alarm(pos: Vector2) -> void:
	_suppress_mic(1.1)
	_play_spatial(_wav_listener_alarm, pos, 3.5, 1.0, 1400.0)


func play_enemy_step(pos: Vector2, is_chasing: bool, occluded: bool) -> void:
	var vol_db: float = -6.0 if is_chasing else -13.0
	if occluded:
		vol_db -= 9.0
	var pitch: float = randf_range(1.05, 1.18) if is_chasing else randf_range(0.85, 0.98)
	_play_spatial(_wav_enemy_step, pos, vol_db, pitch, 420.0)


# --- Internal Player Spawners ------------------------------------------------

func _setup_charge_player() -> void:
	_charge_player = AudioStreamPlayer.new()
	_charge_player.stream = _wav_charge_loop
	_charge_player.bus = &"SFX"
	add_child(_charge_player)


func _setup_heartbeat_players() -> void:
	if not _cache.has("heartbeat"):
		_cache["heartbeat"] = _synth_heartbeat()
	var hb_stream: AudioStreamWAV = _cache["heartbeat"]
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.stream = hb_stream
		p.bus = &"SFX"
		add_child(p)
		_hb_players.append(p)


func _process_heartbeat(delta: float) -> void:
	if _hb_players.is_empty():
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
	if _player_ref == null or not is_instance_valid(_player_ref) or not _player_ref.get("alive"):
		for p in _hb_players:
			if p.playing:
				p.stop()
		return

	var max_threat := 0.0
	var player_pos: Vector2 = _player_ref.global_position
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy):
			max_threat = maxf(max_threat, enemy.get_threat_level(player_pos))

	var rate := 4.2 if max_threat > _threat else 1.2
	_threat = move_toward(_threat, max_threat, delta * rate)

	_hb_timer += delta
	if _hb_timer >= lerpf(interval_calm, interval_panic, _threat):
		_hb_timer = 0.0
		var p := _hb_players[_hb_idx]
		_hb_idx = (_hb_idx + 1) % _hb_players.size()
		p.volume_db = lerpf(vol_calm, vol_panic, _threat)
		p.pitch_scale = lerpf(pitch_calm, pitch_panic, _threat)
		p.play()
		beat.emit(_threat)


func _setup_ambient_drone() -> void:
	if _ambient_drone_player != null:
		return
	if not _cache.has("abyssal_drone"):
		_cache["abyssal_drone"] = _synth_abyssal_drone()
	_ambient_drone_player = AudioStreamPlayer.new()
	_ambient_drone_player.stream = _cache["abyssal_drone"]
	_ambient_drone_player.bus = &"BGM"
	_ambient_drone_player.volume_db = -17.0
	add_child(_ambient_drone_player)
	_ambient_drone_player.play()


func _process_ambient_subterranean(delta: float) -> void:
	# Dynamic subterranean drone volume ducking during intense threats
	if _ambient_drone_player != null and _ambient_drone_player.playing:
		var target_vol: float = lerpf(-17.0, -29.0, _threat)
		_ambient_drone_player.volume_db = move_toward(_ambient_drone_player.volume_db, target_vol, delta * 6.0)

	# Organic distant spatial stalactite water droplets echoing in the darkness
	if _player_ref != null and is_instance_valid(_player_ref) and bool(_player_ref.get("alive")):
		_droplet_timer -= delta
		if _droplet_timer <= 0.0:
			_droplet_timer = randf_range(5.0, 9.5)
			var ang := randf() * TAU
			var dist := randf_range(220.0, 480.0)
			var drop_pos: Vector2 = _player_ref.global_position + Vector2.from_angle(ang) * dist
			_play_spatial(_wav_cave_droplet, drop_pos, -13.5, randf_range(0.92, 1.08), 850.0)


func _synth_heartbeat() -> AudioStreamWAV:
	var dur := 0.42
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase1 := 0.0
	var phase2 := 0.0
	var dub_start := 0.17
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env1: float = minf(t / 0.008, 1.0) * exp(-t * 22.0)
		var f1: float = lerpf(98.0, 42.0, clampf(t / 0.11, 0.0, 1.0))
		phase1 += TAU * f1 / MIX_RATE
		# Lub: AV valves snap shut - deep resonant body + palpable 90-180Hz chest thump
		var lub: float = (sin(phase1) * 0.65 + sin(phase1 * 1.8) * 0.32 + sin(phase1 * 2.6) * 0.14) * env1 * 0.95

		var dub := 0.0
		if t >= dub_start:
			var td: float = t - dub_start
			var env2: float = minf(td / 0.006, 1.0) * exp(-td * 24.0)
			var f2: float = lerpf(118.0, 48.0, clampf(td / 0.09, 0.0, 1.0))
			phase2 += TAU * f2 / MIX_RATE
			# Dub: semilunar valves snap shut - punchy secondary impact
			dub = (sin(phase2) * 0.65 + sin(phase2 * 1.7) * 0.30 + sin(phase2 * 2.5) * 0.12) * env2 * 0.82

		out[i] = tanh((lub + dub) * 1.45) * 0.92
	return _make_wav(out)


func _setup_audio_pools() -> void:
	for i in NON_SPATIAL_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_non_spatial_pool.append(p)

	for i in SPATIAL_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.attenuation = 1.5
		p.panning_strength = 1.4
		add_child(p)
		_spatial_pool.append(p)


func _play_non_spatial(stream: AudioStreamWAV, volume_db: float, pitch: float) -> void:
	if stream == null or _non_spatial_pool.is_empty():
		return
	var p: AudioStreamPlayer = _non_spatial_pool[_non_spatial_idx]
	_non_spatial_idx = (_non_spatial_idx + 1) % NON_SPATIAL_POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _play_spatial(stream: AudioStreamWAV, pos: Vector2, volume_db: float, pitch: float, max_dist: float) -> void:
	if stream == null or _spatial_pool.is_empty():
		return
	var p: AudioStreamPlayer2D = _spatial_pool[_spatial_idx]
	_spatial_idx = (_spatial_idx + 1) % SPATIAL_POOL_SIZE
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.play()


# --- Procedural Waveform Synthesis -------------------------------------------

func _build_all_streams() -> void:
	# 1. Footstep variations (prevents machine-gun repetition)
	for i in 4:
		var key := "step_walk_%d" % i
		if not _cache.has(key):
			_cache[key] = _synth_step_walk(i)
	for i in 3:
		var key := "step_sneak_%d" % i
		if not _cache.has(key):
			_cache[key] = _synth_step_sneak(i)
	for i in 3:
		var key := "step_water_%d" % i
		if not _cache.has(key):
			_cache[key] = _synth_step_water(i)

	if not _cache.has("abyssal_drone"):
		_cache["abyssal_drone"] = _synth_abyssal_drone()
	if not _cache.has("cave_droplet"):
		_cache["cave_droplet"] = _synth_cave_droplet()
	if not _cache.has("sleeper_snore"):
		_cache["sleeper_snore"] = _synth_sleeper_snore()

	if not _cache.has("enemy_step"):
		_cache["enemy_step"] = _synth_enemy_step()
		_cache["echo_ping"] = _synth_echo_ping()
		_cache["charge_full"] = _synth_charge_full()
		_cache["charge_loop"] = _synth_charge_loop()
		_cache["roar_sleeper"] = _synth_monster_roar(95.0, 0.78, 0.35)
		_cache["roar_patroller"] = _synth_monster_roar(135.0, 0.68, 0.55)
		_cache["roar_chaser"] = _synth_monster_roar(185.0, 0.62, 0.85)
		_cache["screamer_crack"] = _synth_screamer_crack()
		_cache["screamer_shriek"] = _synth_screamer_shriek()
		_cache["listener_pip"] = _synth_listener_pip()
		_cache["listener_alarm"] = _synth_listener_alarm()
		_cache["player_stun"] = _synth_player_stun()
		_cache["player_death"] = _synth_player_death()
		_cache["level_intro"] = _synth_level_intro()
		_cache["level_exit"] = _synth_level_exit()
		_cache["victory_fanfare"] = _synth_victory_fanfare()
		_cache["sneak_toggle"] = _synth_sneak_toggle()

	if not _cache.has("star_chime_0"):
		_cache["star_chime_0"] = _synth_star_chime(523.25)
		_cache["star_chime_1"] = _synth_star_chime(659.25)
		_cache["star_chime_2"] = _synth_star_chime(783.99)

	if not _cache.has("pebble_clatter"):
		_cache["pebble_clatter"] = _synth_pebble_clatter()
	if not _cache.has("pebble_clink"):
		_cache["pebble_clink"] = _synth_pebble_clink()
	if not _cache.has("deny_tick"):
		_cache["deny_tick"] = _synth_deny_tick()

	# Visually Impaired (Blind) Echolocation & Navigation Streams
	if not _cache.has("exit_beacon"):
		_cache["exit_beacon"] = _synth_exit_beacon()
	if not _cache.has("wall_echo"):
		_cache["wall_echo"] = _synth_wall_echo()
	if not _cache.has("cane_tap"):
		_cache["cane_tap"] = _synth_cane_tap()
	if not _cache.has("wall_bump"):
		_cache["wall_bump"] = _synth_wall_bump()
	if not _cache.has("assist_on"):
		_cache["assist_on"] = _synth_assist_toggle(true)
	if not _cache.has("assist_off"):
		_cache["assist_off"] = _synth_assist_toggle(false)
	if not _cache.has("door_open"):
		_cache["door_open"] = _synth_door_open()
	if not _cache.has("inv_pip"):
		_cache["inv_pip"] = _synth_inv_pip()

	_wav_steps_walk.clear()
	for i in 4:
		_wav_steps_walk.append(_cache.get("step_walk_%d" % i, null))

	_wav_steps_sneak.clear()
	for i in 3:
		_wav_steps_sneak.append(_cache.get("step_sneak_%d" % i, null))

	_wav_steps_water.clear()
	for i in 3:
		_wav_steps_water.append(_cache.get("step_water_%d" % i, null))

	_wav_abyssal_drone = _cache.get("abyssal_drone", null)
	_wav_cave_droplet = _cache.get("cave_droplet", null)
	_wav_sleeper_snore = _cache.get("sleeper_snore", null)

	_wav_enemy_step = _cache.get("enemy_step", null)
	_wav_echo_ping = _cache.get("echo_ping", null)
	_wav_charge_full = _cache.get("charge_full", null)
	_wav_charge_loop = _cache.get("charge_loop", null)
	_wav_roar_sleeper = _cache.get("roar_sleeper", null)
	_wav_roar_patroller = _cache.get("roar_patroller", null)
	_wav_roar_chaser = _cache.get("roar_chaser", null)
	_wav_screamer_crack = _cache.get("screamer_crack", null)
	_wav_screamer_shriek = _cache.get("screamer_shriek", null)
	_wav_listener_pip = _cache.get("listener_pip", null)
	_wav_listener_alarm = _cache.get("listener_alarm", null)
	_wav_player_stun = _cache.get("player_stun", null)
	_wav_player_death = _cache.get("player_death", null)
	_wav_level_intro = _cache.get("level_intro", null)
	_wav_level_exit = _cache.get("level_exit", null)
	_wav_victory_fanfare = _cache.get("victory_fanfare", null)
	_wav_sneak_toggle = _cache.get("sneak_toggle", null)
	_wav_pebble_clatter = _cache.get("pebble_clatter", null)
	_wav_pebble_clink = _cache.get("pebble_clink", null)
	_wav_deny_tick = _cache.get("deny_tick", null)
	_wav_exit_beacon = _cache.get("exit_beacon", null)
	_wav_wall_echo = _cache.get("wall_echo", null)
	_wav_cane_tap = _cache.get("cane_tap", null)
	_wav_wall_bump = _cache.get("wall_bump", null)
	_wav_assist_on = _cache.get("assist_on", null)
	_wav_assist_off = _cache.get("assist_off", null)
	_wav_door_open = _cache.get("door_open", null)
	_wav_inv_pip = _cache.get("inv_pip", null)
	_wav_star_chimes = [
		_cache.get("star_chime_0", null),
		_cache.get("star_chime_1", null),
		_cache.get("star_chime_2", null)
	]


static func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var byte_data := PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in samples.size():
		var s: float = clampf(samples[i], -1.0, 1.0)
		var pcm: int = int(s * 32767.0)
		byte_data.encode_s16(i * 2, pcm)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = byte_data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


# Stone cavern footstep: 4 distinct natural variations (heel strike, sole impact, toe scuff, hollow rock)
func _synth_step_walk(variant: int = 0) -> AudioStreamWAV:
	var dur := 0.16
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	var f_start: float = [148.0, 162.0, 136.0, 175.0][clampi(variant, 0, 3)]
	var f_end: float = [44.0, 52.0, 40.0, 56.0][clampi(variant, 0, 3)]
	var decay: float = [26.0, 31.0, 24.0, 33.0][clampi(variant, 0, 3)]
	var grit_freq: float = [880.0, 1150.0, 720.0, 1340.0][clampi(variant, 0, 3)]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var freq: float = lerpf(f_start, f_end, clampf(t / 0.08, 0.0, 1.0))
		phase += TAU * freq / MIX_RATE
		var thump: float = sin(phase) * exp(-t * decay)
		var grit: float = randf_range(-1.0, 1.0) * exp(-t * 48.0) * sin(t * grit_freq)
		out[i] = (thump * 0.74 + grit * 0.36) * 0.85
	return _make_wav(out)


# Soft muffled sneak steps (3 subtle toe/sole variations)
func _synth_step_sneak(variant: int = 0) -> AudioStreamWAV:
	var dur := 0.11
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	var f_start: float = [94.0, 102.0, 86.0][clampi(variant, 0, 2)]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var freq: float = lerpf(f_start, 38.0, clampf(t / 0.065, 0.0, 1.0))
		phase += TAU * freq / MIX_RATE
		var soft: float = sin(phase) * exp(-t * 38.0)
		var brush: float = randf_range(-1.0, 1.0) * exp(-t * 65.0) * 0.14
		out[i] = (soft * 0.62 + brush) * 0.65
	return _make_wav(out)


# Hydrodynamic water wading footsteps (viscous water displacement surge + surface fluid slosh)
func _synth_step_water(variant: int = 0) -> AudioStreamWAV:
	var dur := 0.22
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var p_low := 0.0
	var f_base: float = [115.0, 100.0, 128.0][clampi(variant, 0, 2)]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var f_low: float = f_base - 58.0 * clampf(t / 0.12, 0.0, 1.0)
		p_low += TAU * f_low / MIX_RATE
		var sub: float = sin(p_low) * exp(-t * 19.0) * 0.75
		var splash: float = randf_range(-1.0, 1.0) * exp(-t * 42.0) * sin(t * 1950.0) * 0.45
		var pop := 0.0
		if t >= 0.045:
			var tp: float = t - 0.045
			pop = sin(TAU * (560.0 + 780.0 * (tp / 0.04)) * tp) * exp(-tp * 54.0) * 0.35
		out[i] = tanh((sub + splash + pop) * 1.3) * 0.82
	return _make_wav(out)


# Seamless 8-second subterranean atmospheric air & tectonic pressure drone
func _synth_abyssal_drone() -> AudioStreamWAV:
	var dur := 8.0
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var lfo1: float = 0.55 + 0.45 * sin(TAU * 0.125 * t)
		var lfo2: float = 0.50 + 0.50 * cos(TAU * 0.125 * t)
		var lfo3: float = 0.50 + 0.50 * sin(TAU * 0.25 * t)

		var sub1: float = sin(TAU * 48.0 * t) * 0.36 * lfo1
		var sub2: float = sin(TAU * 72.0 * t) * 0.24 * lfo2
		var air1: float = (sin(TAU * 120.0 * t) + sin(TAU * 120.125 * t)) * 0.08 * lfo3
		var air2: float = sin(TAU * 144.0 * t) * 0.06 * lfo1

		out[i] = tanh((sub1 + sub2 + air1 + air2) * 1.2) * 0.65
	return _make_wav(out, true)


# Subterranean stalactite water droplet plop
func _synth_cave_droplet() -> AudioStreamWAV:
	var dur := 0.24
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.002, 1.0) * exp(-t * 32.0)
		var f: float = lerpf(680.0, 1420.0, clampf(t / 0.05, 0.0, 1.0))
		var body: float = sin(TAU * f * t) * att * 0.72
		var echo_drop := 0.0
		if t >= 0.07:
			var te: float = t - 0.07
			var att_e: float = minf(te / 0.002, 1.0) * exp(-te * 42.0)
			echo_drop = sin(TAU * 960.0 * te) * att_e * 0.26
		out[i] = clampf(body + echo_drop, -1.0, 1.0)
	return _make_wav(out)


# Low slumbering guttural breathing for dormant Sleeper monsters
func _synth_sleeper_snore() -> AudioStreamWAV:
	var dur := 0.85
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var norm_t: float = t / dur
		var env: float = sin(norm_t * PI) * (1.0 - 0.22 * norm_t)
		var f: float = 52.0 + 8.0 * sin(TAU * 1.2 * t)
		p1 += TAU * f / MIX_RATE
		var cords: float = sin(p1) + 0.42 * sin(p1 * 2.0) + 0.22 * sin(p1 * 3.0)
		var breath: float = randf_range(-1.0, 1.0) * exp(-absf(norm_t - 0.5) * 4.0) * 0.16
		out[i] = (cords * 0.72 + breath) * env * 0.75
	return _make_wav(out)


# Heavy monster footstep thud
func _synth_enemy_step() -> AudioStreamWAV:
	var dur := 0.18
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var freq: float = lerpf(110.0, 34.0, clampf(t / 0.12, 0.0, 1.0))
		phase += TAU * freq / MIX_RATE
		var sub: float = sin(phase) * exp(-t * 22.0)
		var claw: float = randf_range(-1.0, 1.0) * exp(-t * 50.0) * 0.25
		out[i] = tanh((sub + claw) * 1.4) * 0.8
	return _make_wav(out)


# Bioluminescent sonar ping + 44.1kHz Solfeggio shimmer and sub bloom
func _synth_echo_ping() -> AudioStreamWAV:
	var dur := 0.68
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 5.4)
		var f1 := 528.0
		var f2 := 792.0
		var f3 := 1056.0
		var f4 := 1584.0
		var sig: float = sin(TAU * f1 * t) * 0.55 + sin(TAU * f2 * t) * 0.24 * exp(-t * 7.5) + sin(TAU * f3 * t) * 0.16 * exp(-t * 11.0) + sin(TAU * f4 * t) * 0.09 * exp(-t * 15.0)
		var sub: float = sin(TAU * 132.0 * t) * exp(-t * 12.0) * 0.38
		out[i] = clampf((sig * env + sub) * 0.85, -1.0, 1.0)
	return _make_wav(out)


# Charge full harmonic chime
func _synth_charge_full() -> AudioStreamWAV:
	var dur := 0.28
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 11.0)
		out[i] = (sin(TAU * 880.0 * t) * 0.55 + sin(TAU * 1320.0 * t) * 0.35) * env * 0.7
	return _make_wav(out)


# Seamless loop for voice charging hum
func _synth_charge_loop() -> AudioStreamWAV:
	var freq := 220.0
	var cycles := 44
	var count := int(round(float(cycles) * MIX_RATE / freq))
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var phase: float = TAU * float(cycles) * float(i) / float(count)
		out[i] = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.1) * 0.5
	return _make_wav(out, true)


# Resident Evil style monster discovery roar (growl + formant rasp + guttural distortion)
func _synth_monster_roar(base_freq: float, dur: float, aggression: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var noise_lp := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var norm_t: float = t / dur
		# Envelope: sharp intake, intense sustained roar, ragged decay
		var attack: float = clampf(t / 0.04, 0.0, 1.0)
		var decay: float = clampf((1.0 - norm_t) / 0.28, 0.0, 1.0)
		var env: float = attack * decay

		# Pitch rises in fury then drops gutturally
		var pitch_curve: float = 1.0 + 0.28 * sin(norm_t * PI) - 0.22 * norm_t
		var vibrato: float = 1.0 + 0.06 * sin(TAU * 26.0 * t)
		var f: float = base_freq * pitch_curve * vibrato

		p1 += TAU * f / MIX_RATE
		p2 += TAU * (f * 1.48) / MIX_RATE
		p3 += TAU * (f * 0.5) / MIX_RATE

		# Saw-like vocal cords + sub-growl + filtered breath rasp
		var cords: float = sin(p1) + 0.55 * sin(p1 * 2.0) + 0.35 * sin(p2) + 0.6 * sin(p3)
		var raw_noise: float = randf_range(-1.0, 1.0)
		noise_lp = lerpf(noise_lp, raw_noise, 0.18 + 0.22 * aggression)
		var rasp: float = noise_lp * (0.65 + 0.5 * sin(p1))

		var mixed: float = tanh((cords * 0.7 + rasp * (0.6 + 0.4 * aggression)) * (1.8 + aggression))
		out[i] = mixed * env * 0.85
	return _make_wav(out)


# Screamer 1st sound warning: crystalline fracture / crack
func _synth_screamer_crack() -> AudioStreamWAV:
	var dur := 0.38
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		# Two sharp fracture snaps + tense high metallic resonance
		var snap1: float = randf_range(-1.0, 1.0) * exp(-t * 55.0)
		var snap2: float = randf_range(-1.0, 1.0) * exp(-maxf(t - 0.07, 0.0) * 65.0) if t >= 0.07 else 0.0
		var ring: float = (sin(TAU * 1480.0 * t) + 0.6 * sin(TAU * 2120.0 * t)) * exp(-t * 9.5)
		out[i] = clampf((snap1 * 0.8 + snap2 * 0.7 + ring * 0.45) * 0.85, -1.0, 1.0)
	return _make_wav(out)


# Screamer 2nd sound: piercing banshee sonic shriek
func _synth_screamer_shriek() -> AudioStreamWAV:
	var dur := 1.15
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := 0.0
	var p2 := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var norm_t: float = t / dur
		var env: float = clampf(t / 0.03, 0.0, 1.0) * exp(-norm_t * 2.2)
		var fm: float = sin(TAU * 38.0 * t) * 65.0
		var f1: float = lerpf(1180.0, 760.0, norm_t) + fm
		var f2: float = lerpf(1790.0, 1120.0, norm_t) - fm * 0.7
		p1 += TAU * f1 / MIX_RATE
		p2 += TAU * f2 / MIX_RATE
		var shriek: float = sin(p1) * 0.55 + sin(p2) * 0.4 + randf_range(-0.35, 0.35) * exp(-t * 2.5)
		var boom: float = sin(TAU * lerpf(160.0, 45.0, clampf(t / 0.25, 0.0, 1.0)) * t) * exp(-t * 8.0) * 0.5
		out[i] = tanh((shriek + boom) * 1.6) * env * 0.82
	return _make_wav(out)


# Listener pip: tense sonar lock-on beep
func _synth_listener_pip() -> AudioStreamWAV:
	var dur := 0.24
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.005, 1.0) * exp(-t * 14.0)
		var sig: float = sin(TAU * 740.0 * t) * 0.7 + sin(TAU * 1480.0 * t) * 0.3
		out[i] = sig * env * 0.75
	return _make_wav(out)


# Listener 5-stack map-wide alarm: deep dread horn + sweeping radar pulse
func _synth_listener_alarm() -> AudioStreamWAV:
	var dur := 1.6
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var p_horn := 0.0
	var p_sweep := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var norm_t: float = t / dur
		var env: float = clampf(t / 0.05, 0.0, 1.0) * clampf((1.0 - norm_t) / 0.2, 0.0, 1.0)
		var horn_f: float = 110.0 * (1.0 - 0.12 * norm_t)
		var sweep_f: float = 440.0 + 320.0 * sin(TAU * 3.0 * t)
		p_horn += TAU * horn_f / MIX_RATE
		p_sweep += TAU * sweep_f / MIX_RATE
		var horn: float = sin(p_horn) + 0.5 * sin(p_horn * 2.0) + 0.3 * sin(p_horn * 3.0)
		var radar: float = sin(p_sweep) * 0.35 * (0.5 + 0.5 * sin(TAU * 6.0 * t))
		out[i] = tanh((horn * 0.65 + radar) * 1.5) * env * 0.85
	return _make_wav(out)


# Player stunned: shock impact + high tinnitus ring
func _synth_player_stun() -> AudioStreamWAV:
	var dur := 0.85
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var impact: float = randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.7
		var ring: float = sin(TAU * 2450.0 * t) * exp(-t * 2.6) * 0.35
		var buzz: float = sin(TAU * 95.0 * t) * exp(-t * 6.0) * 0.45
		out[i] = clampf(impact + ring + buzz, -1.0, 1.0) * 0.8
	return _make_wav(out)


# Player death: dark bass collapse + dissolving static
func _synth_player_death() -> AudioStreamWAV:
	var dur := 0.95
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var freq: float = lerpf(190.0, 28.0, clampf(t / 0.7, 0.0, 1.0))
		phase += TAU * freq / MIX_RATE
		var drop: float = sin(phase) * exp(-t * 3.2)
		var crunch: float = randf_range(-1.0, 1.0) * exp(-t * 9.0) * 0.5
		out[i] = tanh((drop * 0.85 + crunch) * 1.7) * 0.9
	return _make_wav(out)


# Level entry: deep cavern sub-swell + crystalline awakening sonar ping
func _synth_level_intro() -> AudioStreamWAV:
	var dur := 1.1
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var sub_phase := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var swell_env: float = clampf(t / 0.18, 0.0, 1.0) * exp(-t * 2.8)
		var sub_f: float = lerpf(68.0, 110.0, clampf(t / 0.45, 0.0, 1.0))
		sub_phase += TAU * sub_f / MIX_RATE
		var sub: float = sin(sub_phase) * swell_env * 0.55

		var ping := 0.0
		if t >= 0.16:
			var tp: float = t - 0.16
			var p_env: float = minf(tp / 0.01, 1.0) * exp(-tp * 4.2)
			ping = (sin(TAU * 528.0 * tp) * 0.5 + sin(TAU * 792.0 * tp) * 0.3 + sin(TAU * 1056.0 * tp) * 0.2) * p_env * 0.65

		out[i] = clampf(sub + ping, -1.0, 1.0)
	return _make_wav(out)


# Subtle acoustic dampener whoosh when toggling sneak mode
func _synth_sneak_toggle() -> AudioStreamWAV:
	var dur := 0.14
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = sin((t / dur) * PI) * exp(-t * 14.0)
		var f: float = lerpf(320.0, 190.0, t / dur)
		phase += TAU * f / MIX_RATE
		var breath: float = randf_range(-1.0, 1.0) * 0.25
		out[i] = (sin(phase) * 0.65 + breath) * env * 0.7
	return _make_wav(out)


# Level exit portal: ascending crystalline resonance
func _synth_level_exit() -> AudioStreamWAV:
	var dur := 0.42
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.02, 1.0) * exp(-t * 5.2)
		var f1: float = lerpf(392.0, 784.0, t / dur)
		var f2: float = lerpf(587.3, 1174.6, t / dur)
		var tone: float = (sin(TAU * f1 * t) * 0.55 + sin(TAU * f2 * t) * 0.35) * env * 0.72
		out[i] = clampf(tone, -1.0, 1.0)
	return _make_wav(out)


# Campaign victory fanfare: triumphant multi-harmonic crystalline ascent
func _synth_victory_fanfare() -> AudioStreamWAV:
	var dur := 2.6
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	# Harmonic frequencies: E4, G#4, B4, E5, B5, E6
	var freqs: Array[float] = [329.63, 415.30, 493.88, 659.25, 987.77, 1318.5]
	var delays: Array[float] = [0.0, 0.14, 0.28, 0.42, 0.56, 0.70]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var total_sample := 0.0
		for k in freqs.size():
			var note_t: float = t - delays[k]
			if note_t >= 0.0:
				var note_env: float = minf(note_t / 0.015, 1.0) * exp(-note_t * 1.85)
				var s: float = sin(TAU * freqs[k] * note_t) + 0.25 * sin(TAU * freqs[k] * 2.0 * note_t)
				total_sample += s * note_env * 0.2
		out[i] = clampf(tanh(total_sample * 1.5) * 0.88, -1.0, 1.0)
	return _make_wav(out)


# Procedural crystalline bell chime for debrief star reveals
func _synth_star_chime(freq: float) -> AudioStreamWAV:
	var dur := 0.72
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 5.4)
		var body: float = sin(TAU * freq * t) + 0.38 * sin(TAU * freq * 2.0 * t) + 0.15 * sin(TAU * freq * 3.0 * t)
		out[i] = clampf(body * env * 0.82, -1.0, 1.0)
	return _make_wav(out)


# Organic stone skipping/clattering on cavern rock: sharp primary impact, high clack, secondary bounces and small roll
func _synth_pebble_clatter() -> AudioStreamWAV:
	var dur := 0.42
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var hits: Array[float] = [0.0, 0.11, 0.20, 0.27, 0.33]
	var amps: Array[float] = [1.0, 0.52, 0.26, 0.14, 0.08]
	var freqs: Array[float] = [620.0, 780.0, 890.0, 1020.0, 1150.0]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var sample := 0.0
		for k in hits.size():
			var dt: float = t - hits[k]
			if dt >= 0.0 and dt < 0.12:
				var att: float = minf(dt / 0.0018, 1.0)
				var env: float = att * exp(-dt * 48.0)
				var ping: float = sin(TAU * freqs[k] * dt) * exp(-dt * 32.0)
				var clack: float = randf_range(-1.0, 1.0) * exp(-dt * 85.0)
				sample += (ping * 0.72 + clack * 0.48) * env * amps[k]
		out[i] = clampf(tanh(sample * 1.35) * 0.88, -1.0, 1.0)
	return _make_wav(out)


# Sharp high-frequency pebble impact against hard wall rock
func _synth_pebble_clink() -> AudioStreamWAV:
	var dur := 0.09
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.0012, 1.0)
		var env: float = att * exp(-t * 68.0)
		var ping: float = sin(TAU * 1420.0 * t) * exp(-t * 42.0)
		var ping2: float = sin(TAU * 2360.0 * t) * exp(-t * 85.0) * 0.45
		var crack: float = randf_range(-1.0, 1.0) * exp(-t * 115.0)
		var sample: float = (ping * 0.85 + ping2 + crack * 0.55) * env
		out[i] = clampf(tanh(sample * 1.45) * 0.88, -1.0, 1.0)
	return _make_wav(out)


# Tactile hollow dry click for unavailable / empty action denial
func _synth_deny_tick() -> AudioStreamWAV:
	var dur := 0.06
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.0015, 1.0)
		var env: float = att * exp(-t * 90.0)
		var thud: float = sin(TAU * 160.0 * t) * exp(-t * 60.0)
		var tick: float = sin(TAU * 950.0 * t) * exp(-t * 120.0) * 0.6
		var sample: float = (thud * 0.7 + tick * 0.5) * env
		out[i] = clampf(tanh(sample * 1.3) * 0.85, -1.0, 1.0)
	return _make_wav(out)


# Serene Tibetan singing bowl / crystal harmonic exit beacon pulse (528 Hz Solfeggio fundamental)
func _synth_exit_beacon() -> AudioStreamWAV:
	var dur := 1.25
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.018, 1.0) * exp(-t * 2.8)
		# 528Hz fundamental + 1056Hz octave + 1584Hz 3rd harmonic + 132Hz warm deep undertone
		var s1: float = sin(TAU * 528.0 * t) * 0.52
		var s2: float = sin(TAU * 1056.0 * t) * 0.28
		var s3: float = sin(TAU * 1584.0 * t) * 0.14
		var sub: float = sin(TAU * 132.0 * t) * 0.18
		out[i] = clampf((s1 + s2 + s3 + sub) * env * 0.92, -1.0, 1.0)
	return _make_wav(out)


# Crisp high-frequency acoustic reflection tap (reproducing human echolocation tongue-click reflection)
func _synth_wall_echo() -> AudioStreamWAV:
	var dur := 0.045
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.0012, 1.0)
		var env: float = att * exp(-t * 95.0)
		var body: float = sin(TAU * 1180.0 * t) * 0.75
		var air: float = randf_range(-1.0, 1.0) * exp(-t * 130.0) * 0.35
		out[i] = clampf((body + air) * env * 0.88, -1.0, 1.0)
	return _make_wav(out)


# Tactile acoustic cane feeler / proximity radar tick
func _synth_cane_tap() -> AudioStreamWAV:
	var dur := 0.048
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.0015, 1.0)
		var env: float = att * exp(-t * 88.0)
		var thud: float = sin(TAU * 240.0 * t) * exp(-t * 60.0) * 0.75
		var click: float = sin(TAU * 880.0 * t) * exp(-t * 140.0) * 0.45
		out[i] = clampf((thud + click) * env * 0.85, -1.0, 1.0)
	return _make_wav(out)


# Muffled physical impact thud when the player bumps against a solid cave wall
func _synth_wall_bump() -> AudioStreamWAV:
	var dur := 0.09
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var att: float = minf(t / 0.002, 1.0)
		var env: float = att * exp(-t * 46.0)
		var sub: float = sin(TAU * 110.0 * t) * exp(-t * 35.0) * 0.72
		var snap: float = sin(TAU * 360.0 * t) * exp(-t * 75.0) * 0.42
		out[i] = clampf((sub + snap) * env * 0.9, -1.0, 1.0)
	return _make_wav(out)


# Ascending (ON) or descending (OFF) two-tone chime for Blind Assist mode confirmation
func _synth_assist_toggle(enabled: bool) -> AudioStreamWAV:
	var dur := 0.28
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var f1: float = 523.25 if enabled else 783.99
	var f2: float = 783.99 if enabled else 523.25
	for i in count:
		var t: float = float(i) / MIX_RATE
		var s := 0.0
		if t < 0.14:
			var env1: float = minf(t / 0.008, 1.0) * exp(-t * 18.0)
			s += (sin(TAU * f1 * t) + 0.3 * sin(TAU * f1 * 2.0 * t)) * env1
		if t >= 0.11:
			var t2: float = t - 0.11
			var env2: float = minf(t2 / 0.008, 1.0) * exp(-t2 * 16.0)
			s += (sin(TAU * f2 * t2) + 0.3 * sin(TAU * f2 * 2.0 * t2)) * env2
		out[i] = clampf(s * 0.75, -1.0, 1.0)
	return _make_wav(out)


# Subterranean stone door sliding open: low cavern grinding rumble followed by latch release
func _synth_door_open() -> AudioStreamWAV:
	var dur := 0.65
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.03, 1.0) * exp(-t * 3.8)
		var rumble: float = sin(TAU * 75.0 * t) * exp(-t * 2.5) * 0.55
		var grind: float = randf_range(-1.0, 1.0) * exp(-t * 4.5) * 0.35
		var latch: float = 0.0
		if t >= 0.25:
			var tl: float = t - 0.25
			var latch_env: float = minf(tl / 0.005, 1.0) * exp(-tl * 25.0)
			latch = sin(TAU * 880.0 * tl) * latch_env * 0.4
		out[i] = clampf((rumble + grind + latch) * env * 0.85, -1.0, 1.0)
	return _make_wav(out)


# Bright crystalline inventory pip for stone count check
func _synth_inv_pip() -> AudioStreamWAV:
	var dur := 0.075
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.004, 1.0) * exp(-t * 45.0)
		var tone: float = sin(TAU * 880.0 * t) + 0.32 * sin(TAU * 1760.0 * t)
		out[i] = clampf(tone * env * 0.78, -1.0, 1.0)
	return _make_wav(out)


# --- Main Menu Procedural BGM Synthesis --------------------------------------

# Seamless 8-second subterranean ambient pad loop (A minor 9th / Dorian cavern drone).
# All carrier and LFO frequencies are exact multiples of 0.125 Hz (1 / 8.0s) for zero-click looping.
static func get_menu_bgm_pad() -> AudioStreamWAV:
	if _cache.has("menu_bgm_pad"):
		return _cache["menu_bgm_pad"]
	var dur := 8.0
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var lfo1: float = 0.55 + 0.45 * sin(TAU * 0.125 * t)
		var lfo2: float = 0.55 + 0.45 * cos(TAU * 0.125 * t)
		var lfo3: float = 0.50 + 0.50 * sin(TAU * 0.25 * t - 1.1)
		var lfo4: float = pow(0.5 + 0.5 * sin(TAU * 0.125 * t + 2.6), 2.0)

		# Deep abyssal sub-bass (A1 = 55 Hz, E2 = 82.5 Hz)
		var sub: float = sin(TAU * 55.0 * t) * 0.34 * lfo1 + sin(TAU * 82.5 * t) * 0.22 * lfo2
		# Warm binaural chorus pad (A2 = 110 Hz, C3 = 132 Hz, E3 = 165 Hz)
		var pad_a: float = (sin(TAU * 110.0 * t) + sin(TAU * 110.125 * t)) * 0.14
		var pad_c: float = (sin(TAU * 132.0 * t) + sin(TAU * 131.875 * t)) * 0.11 * lfo3
		var pad_e: float = (sin(TAU * 165.0 * t) + sin(TAU * 165.125 * t)) * 0.10 * lfo2
		# Ethereal upper harmonic shimmer (G3 = 198 Hz, B3 = 247.5 Hz)
		var shimmer: float = (sin(TAU * 198.0 * t) * 0.06 + sin(TAU * 247.5 * t) * 0.05) * lfo4

		out[i] = tanh((sub + pad_a + pad_c + pad_e + shimmer) * 1.15) * 0.68
	var wav: AudioStreamWAV = _make_wav(out, true)
	_cache["menu_bgm_pad"] = wav
	return wav


# Crystalline acoustic echo note (A3 = 220 Hz base) with built-in 2-tap cavern delay.
static func get_menu_bgm_note() -> AudioStreamWAV:
	if _cache.has("menu_bgm_note"):
		return _cache["menu_bgm_note"]
	var dur := 2.2
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var taps: Array[float] = [0.0, 0.38, 0.78]
	var gains: Array[float] = [1.0, 0.36, 0.15]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var sample := 0.0
		for k in taps.size():
			var dt: float = t - taps[k]
			if dt >= 0.0:
				var att: float = minf(dt / 0.018, 1.0)
				var body: float = sin(TAU * 220.0 * dt) * exp(-dt * 2.3)
				var oct: float = sin(TAU * 440.0 * dt) * exp(-dt * 4.0) * 0.32
				var bell: float = sin(TAU * 660.0 * dt) * exp(-dt * 7.2) * 0.11
				sample += (body + oct + bell) * att * gains[k]
		out[i] = clampf(sample * 0.58, -1.0, 1.0)
	var wav: AudioStreamWAV = _make_wav(out)
	_cache["menu_bgm_note"] = wav
	return wav


# Subterranean water droplet with stalactite cave reflection.
static func get_menu_bgm_droplet() -> AudioStreamWAV:
	if _cache.has("menu_bgm_droplet"):
		return _cache["menu_bgm_droplet"]
	var dur := 0.65
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var taps: Array[float] = [0.0, 0.24, 0.46]
	var gains: Array[float] = [0.75, 0.28, 0.11]
	for i in count:
		var t: float = float(i) / MIX_RATE
		var sample := 0.0
		for k in taps.size():
			var dt: float = t - taps[k]
			if dt >= 0.0 and dt < 0.18:
				var env: float = minf(dt / 0.003, 1.0) * exp(-dt * 30.0)
				var f: float = lerpf(540.0, 1220.0, clampf(dt / 0.045, 0.0, 1.0))
				sample += sin(TAU * f * dt) * env * gains[k]
		out[i] = clampf(sample, -1.0, 1.0)
	var wav: AudioStreamWAV = _make_wav(out)
	_cache["menu_bgm_droplet"] = wav
	return wav
