extends CharacterBody2D
class_name Enemy

# Signals
signal woke_up(pos: Vector2)
signal screamed(pos: Vector2, radius: float)
signal alarmed(pos: Vector2, target_pos: Vector2)

enum EnemyType {
	SLEEPER,
	PATROLLER,
	CHASER,
	SCREAMER,
	LISTENER
}

enum State {
	SLEEP,
	PATROL,
	ALERT,
	INVESTIGATE,
	SEARCH,
	RETURN,
	SCREAM,
	ALARM
}

# --- Enemy Archetype Configuration ---
@export var enemy_type: EnemyType = EnemyType.PATROLLER:
	set(val):
		enemy_type = val
		_apply_type_preset()

@export_group("Hearing & Perception")
@export var hearing_range := 400.0
@export var hearing_threshold := 0.02
@export var can_hear_sneak := true
@export var can_hear_walk := true
@export var can_hear_voice := true

@export_group("Movement Speeds")
@export var patrol_speed := 75.0
@export var chase_speed := 150.0

@export_group("Sensory & Proximity")
@export var sense_radius := 90.0
@export var sneak_sense_radius := 60.0
@export var sleep_wake_radius := 75.0

@export_group("States & Patrol")
@export var init_state: State = State.PATROL
@export var patrol_points: Array[Vector2] = []

# Constants
const ALERT_TIME := 0.4
const SEARCH_TIME := 2.5
const SEARCH_RADIUS := 80.0
const INVESTIGATE_TIMEOUT := 3.5 # Maximum chase duration before enemy loses target and begins searching
const ARRIVE_DIST := 10.0
const WARN_RADIUS := 160.0

const STATE_FLASH := {
	State.SLEEP: 0.3,
	State.PATROL: 0.3,
	State.ALERT: 1.0,
	State.INVESTIGATE: 0.7,
	State.SEARCH: 0.6,
	State.RETURN: 0.5,
	State.SCREAM: 1.0,
	State.ALARM: 1.0,
}

# Runtime States
var state: State = State.SLEEP
var home: Vector2
var target: Vector2
var search_point: Vector2
var timer := 0.0
var patrol_idx := 0
var visible_alpha := 0.0
var proximity := 0.0
var _trail_points: Array[Vector2] = []

# --- Archetype-Specific Mechanics ---
# Screamer (needs 2 voice triggers within time window to scream)
var screamer_count := 0
var screamer_decay_timer := 0.0
var screamer_cooldown := 0.0
var _scream_wave_radius := 0.0

# Listener (counts sounds detected up to 5 after hearing a shout)
var listener_count := 0
var listener_decay_timer := 0.0
var listener_cooldown := 0.0
var _alarm_wave_radius := 0.0

# Speed Boost Buff (e.g. triggered by Listener map pulse)
var speed_boost_timer := 0.0
var speed_boost_mult := 1.0

func apply_speed_boost(multiplier: float = 1.35, duration: float = 7.5) -> void:
	speed_boost_mult = multiplier
	speed_boost_timer = duration
	reveal(1.0)

# Force alert to a specific location (used by map-wide alarms like Listener, ignores hearing range limits)
func force_alert_to(pos: Vector2) -> void:
	if enemy_type == EnemyType.SCREAMER or enemy_type == EnemyType.LISTENER:
		return
	target = pos
	_enter(State.INVESTIGATE)
	reveal(1.0)

# Footstep echo timer for mobile enemies
var _step_echo_timer := 0.0
var _step_ripples: Array[Dictionary] = []

func _init() -> void:
	_apply_type_preset()

func _ready() -> void:
	add_to_group("enemy")
	home = global_position
	_collect_patrol_points()
	state = init_state

	if state == State.PATROL and patrol_points.size() < 2:
		# If immobile or has no patrol markers, keep in SLEEP
		if enemy_type == EnemyType.SCREAMER or enemy_type == EnemyType.LISTENER:
			state = State.SLEEP
		elif patrol_points.is_empty():
			state = State.SLEEP

	$CatchArea.body_entered.connect(_on_catch)

# Apply defaults based on enemy type (scaled relative to Player: Walk 190, Sneak 100)
func _apply_type_preset() -> void:
	match enemy_type:
		EnemyType.SLEEPER:
			hearing_range = 350.0
			hearing_threshold = 0.14 # High threshold: hard to wake up, close walk or voice needed
			can_hear_sneak = false  # Immune to sneak steps
			can_hear_walk = true
			can_hear_voice = true
			patrol_speed = 60.0
			chase_speed = 135.0     # Moderate chase speed (player can outrun easily)
			init_state = State.SLEEP
			sleep_wake_radius = 70.0

		EnemyType.PATROLLER:
			hearing_range = 400.0
			hearing_threshold = 0.02 # Moderate-high sensitivity, hears all sounds
			can_hear_sneak = true   # Can hear sneak if close enough
			can_hear_walk = true
			can_hear_voice = true
			patrol_speed = 75.0
			chase_speed = 150.0     # Fast chase speed
			init_state = State.PATROL
			sleep_wake_radius = 80.0

		EnemyType.CHASER:
			hearing_range = 300.0   # Shorter hearing range
			hearing_threshold = 0.06 # Very sensitive to normal walk and shouts
			can_hear_sneak = false  # Immune to sneak footsteps (Sneak is the key to bypass!)
			can_hear_walk = true
			can_hear_voice = true
			patrol_speed = 90.0
			chase_speed = 175.0     # Extremely fast! (Close to player's 190.0 speed)
			init_state = State.PATROL
			sleep_wake_radius = 90.0

		EnemyType.SCREAMER:
			hearing_range = 450.0   # Wide hearing range
			hearing_threshold = 0.08
			can_hear_sneak = false  # Ignores all footsteps
			can_hear_walk = false   # Ignores all footsteps
			can_hear_voice = true   # Only reacts to voice / vocal sound
			patrol_speed = 0.0      # Stationary
			chase_speed = 0.0       # Stationary
			init_state = State.SLEEP
			sleep_wake_radius = 50.0

		EnemyType.LISTENER:
			hearing_range = 500.0   # Generous acoustic hearing range
			hearing_threshold = 0.02 # High acoustic sensitivity
			can_hear_sneak = false  # Ignores stealth movements
			can_hear_walk = true    # Tracked during listening state
			can_hear_voice = true   # Wakes on shout
			patrol_speed = 0.0      # Stationary
			chase_speed = 0.0       # Stationary
			init_state = State.SLEEP
			sleep_wake_radius = 60.0

# Patrol Points Discovery
func _collect_patrol_points() -> void:
	var path = get_node_or_null("Path")
	if path != null:
		var markers: Array[Vector2] = []
		for child in path.get_children():
			if child is Marker2D:
				markers.append(child.global_position)
		if not markers.is_empty():
			patrol_points = markers
		path.queue_free()
	elif patrol_points.is_empty():
		for child in get_children():
			if child is Marker2D:
				patrol_points.append(child.global_position)

# Sound Detection Handler
func on_sound(pos: Vector2, loudness: float, radius: float, is_voice: bool = false) -> void:
	var is_sneak_step := (!is_voice and loudness <= 0.05)
	var is_walk_step := (!is_voice and loudness > 0.05)

	# Special Listener perception rule:
	# "Cannot hear stealthy movements or footsteps, but upon hearing a shout, it enters a listening state.
	# During this state, it tracks the number of sounds detected..."
	if enemy_type == EnemyType.LISTENER:
		if is_sneak_step:
			return # Never hears stealthy movements
		if listener_count == 0 and not is_voice:
			return # Only a shout can wake it into the listening state

	# General sound immunity filter for all other enemies
	if enemy_type != EnemyType.LISTENER:
		if is_sneak_step and not can_hear_sneak:
			return
		if is_walk_step and not can_hear_walk:
			return
		if is_voice and not can_hear_voice:
			return

	# 2. Check effective distance against sound radius and enemy's hearing range
	var dist: float = global_position.distance_to(pos)
	var effective_max := minf(radius, hearing_range)
	if dist > effective_max:
		return

	# 3. Calculate sound attenuation
	var attenuation := 1.0 - (dist / effective_max)
	var heard := loudness * attenuation
	if heard < hearing_threshold:
		return

	# 4. Route to archetype behavior
	match enemy_type:
		EnemyType.SCREAMER:
			_handle_screamer_sound(pos, heard)
		EnemyType.LISTENER:
			_handle_listener_sound(pos, heard, is_voice)
		_:
			_notice(pos)

# Player Detection (Mobile Enemies)
func _notice(pos: Vector2) -> void:
	target = pos
	match state:
		State.SLEEP, State.PATROL, State.RETURN:
			_enter(State.ALERT)
			woke_up.emit(global_position)
		State.SEARCH:
			if timer >= 0.5:
				_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			# While already chasing, update destination toward latest sound,
			# but do not reset chase timer so chase timeout (3.5s) allows escape.
			pass
		State.ALERT:
			pass

# --- Screamer Mechanics ---
func _handle_screamer_sound(pos: Vector2, heard: float) -> void:
	if state == State.SCREAM or screamer_cooldown > 0.0:
		return

	screamer_count += 1
	screamer_decay_timer = 6.0
	reveal(1.0)

	if screamer_count == 1:
		# First trigger: Agitated warning state
		_enter(State.ALERT)
	elif screamer_count >= 2:
		# Second trigger: Trigger the shriek!
		_trigger_scream()

func _trigger_scream() -> void:
	_enter(State.SCREAM)
	screamer_count = 0
	_scream_wave_radius = 0.0
	# Massive scream sound wave covering 550px
	screamed.emit(global_position, 550.0)

# --- Listener Mechanics ---
# It cannot hear stealthy movements or footsteps, but upon hearing a shout, it enters a "listening" state.
# During this state, it tracks the number of sounds detected; once more than 5 sounds have been registered,
# it emits a map-wide sonic pulse that draws all monsters on the map toward it and increases their movement speed.
func _handle_listener_sound(pos: Vector2, heard: float, is_voice: bool) -> void:
	if state == State.ALARM or listener_cooldown > 0.0:
		return

	# If not yet in listening state, only hearing a shout / voice triggers the listening state
	if listener_count == 0:
		if not is_voice:
			return
		listener_count = 1
		listener_decay_timer = 8.0
		reveal(1.0)
		_enter(State.ALERT)
		return

	# During listening state, track each detected sound
	listener_count += 1
	listener_decay_timer = 8.0
	reveal(1.0)

	if listener_count >= 5:
		_trigger_listener_alarm()
	else:
		_enter(State.ALERT)

func _trigger_listener_alarm() -> void:
	_enter(State.ALARM)
	listener_count = 0
	_alarm_wave_radius = 0.0
	# Draws all monsters toward IT (Listener's position)
	alarmed.emit(global_position, global_position)

# State Manager
func _enter(s: State) -> void:
	var changed := s != state
	state = s
	timer = 0.0
	if s == State.SEARCH:
		search_point = _random_search_point()
	if changed:
		reveal(float(STATE_FLASH.get(s, 0.5)))

func _random_search_point() -> Vector2:
	return target + Vector2.from_angle(randf() * TAU) * randf_range(30.0, SEARCH_RADIUS)

func _get_player() -> Node2D:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.alive:
		return null
	return player as Node2D

# Physical Proximity Sensing
func _sense_player() -> void:
	if state == State.ALERT or state == State.SCREAM or state == State.ALARM:
		return
	var player := _get_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)

	if state == State.SLEEP:
		if dist <= sleep_wake_radius:
			if enemy_type == EnemyType.SCREAMER:
				_handle_screamer_sound(player.global_position, 0.5)
			elif enemy_type == EnemyType.LISTENER:
				pass # Listener only triggers on voice
			else:
				_notice(player.global_position)
		return

	var radius: float = sneak_sense_radius if player.sneaking else sense_radius
	if dist <= radius:
		_notice(player.global_position)

func _update_proximity() -> void:
	proximity = 0.0
	var player := _get_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	proximity = clampf(1.0 - dist / WARN_RADIUS, 0.0, 1.0)

# Threat Level for Dynamic Heartbeat
func get_threat_level(player_pos: Vector2) -> float:
	var dist: float = global_position.distance_to(player_pos)

	if state == State.SCREAM or state == State.ALARM:
		return 1.0

	match state:
		State.ALERT, State.INVESTIGATE:
			return 1.0
		State.SEARCH:
			return clampf(maxf(0.5, 1.0 - dist / 250.0), 0.0, 1.0)
		State.PATROL, State.RETURN:
			return clampf(1.0 - dist / 220.0, 0.0, 1.0)
		State.SLEEP:
			if enemy_type == EnemyType.SCREAMER and screamer_count > 0:
				return clampf(1.0 - dist / 280.0, 0.4, 0.95)
			if enemy_type == EnemyType.LISTENER and listener_count > 0:
				return clampf(0.3 * listener_count + (1.0 - dist / 260.0) * 0.4, 0.0, 0.9)
			return clampf(inverse_lerp(180.0, sleep_wake_radius, dist), 0.0, 0.9)
	return 0.0

# Physics and Movement Processing
func _physics_process(delta: float) -> void:
	timer += delta
	visible_alpha = move_toward(visible_alpha, 0.0, delta * 0.7)
	_sense_player()

	# Cooldowns and count decays
	if screamer_decay_timer > 0.0:
		screamer_decay_timer -= delta
		if screamer_decay_timer <= 0.0 and screamer_count > 0:
			screamer_count = 0
			if state == State.ALERT:
				_enter(State.SLEEP)

	if screamer_cooldown > 0.0:
		screamer_cooldown -= delta

	if listener_decay_timer > 0.0:
		listener_decay_timer -= delta
		if listener_decay_timer <= 0.0 and listener_count > 0:
			listener_count = maxi(0, listener_count - 1)
			listener_decay_timer = 5.0 if listener_count > 0 else 0.0
			if listener_count == 0 and state == State.ALERT:
				_enter(State.SLEEP)

	if listener_cooldown > 0.0:
		listener_cooldown -= delta

	# Speed boost buff decay
	if speed_boost_timer > 0.0:
		speed_boost_timer -= delta
		if speed_boost_timer <= 0.0:
			speed_boost_mult = 1.0

	var cur_chase := chase_speed * (speed_boost_mult if speed_boost_timer > 0.0 else 1.0)
	var cur_patrol := patrol_speed * (speed_boost_mult if speed_boost_timer > 0.0 else 1.0)

	# State Machine Logic
	match state:
		State.SLEEP:
			velocity = Vector2.ZERO
		State.PATROL:
			_do_patrol()
		State.ALERT:
			velocity = Vector2.ZERO
			if timer >= ALERT_TIME:
				if enemy_type == EnemyType.SCREAMER or enemy_type == EnemyType.LISTENER:
					# Immobile alert stays in sleep/alert until triggered or decay
					pass
				else:
					_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			if _move_toward(target, cur_chase) or timer >= INVESTIGATE_TIMEOUT:
				velocity = Vector2.ZERO
				_enter(State.SEARCH)
		State.SEARCH:
			if _move_toward(search_point, cur_patrol):
				search_point = _random_search_point()
			if timer >= SEARCH_TIME:
				_enter(State.RETURN)
		State.RETURN:
			var dest := _home_target()
			if _move_toward(dest, cur_patrol):
				_enter(State.PATROL if patrol_points.size() > 1 else State.SLEEP)
		State.SCREAM:
			velocity = Vector2.ZERO
			_scream_wave_radius += delta * 320.0
			reveal(1.0)
			if timer >= 2.2:
				screamer_cooldown = 5.0
				_enter(State.SLEEP)
		State.ALARM:
			velocity = Vector2.ZERO
			_alarm_wave_radius += delta * 400.0
			reveal(1.0)
			if timer >= 2.5:
				listener_cooldown = 6.0
				_enter(State.SLEEP)

	# Apply motion for mobile enemies
	if enemy_type != EnemyType.SCREAMER and enemy_type != EnemyType.LISTENER:
		move_and_slide()

		# Chaser phantom trail during chase
		if enemy_type == EnemyType.CHASER and state == State.INVESTIGATE and velocity.length() > 20.0:
			_trail_points.push_front(global_position)
			if _trail_points.size() > 10:
				_trail_points.pop_back()
		elif _trail_points.size() > 0:
			_trail_points.pop_back()

		# Footstep acoustic ripples when moving
		if velocity.length() > 15.0:
			_step_echo_timer += delta
			var interval := 0.4 if state == State.INVESTIGATE else 0.75
			if _step_echo_timer >= interval:
				_step_echo_timer = 0.0
				_step_ripples.append({
					"pos": global_position,
					"age": 0.0,
					"max_r": 35.0 if state == State.INVESTIGATE else 22.0
				})

	# Update step ripples
	for r in _step_ripples:
		r["age"] += delta
	_step_ripples = _step_ripples.filter(func(r): return r["age"] < 1.0)

	_update_proximity()
	queue_redraw()

func _move_toward(dest: Vector2, speed: float) -> bool:
	var to_dest := dest - global_position
	if to_dest.length() < ARRIVE_DIST:
		velocity = Vector2.ZERO
		return true

	velocity = to_dest.normalized() * speed
	return false

func _home_target() -> Vector2:
	if patrol_points.size() > 0:
		return patrol_points[patrol_idx]
	else:
		return home

func _do_patrol() -> void:
	if patrol_points.size() < 2:
		velocity = Vector2.ZERO
		return
	var cur_patrol := patrol_speed * (speed_boost_mult if speed_boost_timer > 0.0 else 1.0)
	if _move_toward(patrol_points[patrol_idx], cur_patrol):
		patrol_idx = (patrol_idx + 1) % patrol_points.size()

# Player Catch Callback
func _on_catch(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()

func reveal(amount: float = 1.0) -> void:
	visible_alpha = clampf(visible_alpha + amount, 0.0, 1.0)

# Unique Base Theme Color for Each Enemy Archetype
func _get_type_color() -> Color:
	match enemy_type:
		EnemyType.SLEEPER:
			return Color(0.68, 0.42, 0.98) # Eerie Amethyst Purple
		EnemyType.PATROLLER:
			return Color(1.0, 0.82, 0.25)  # Sentinel Amber Gold
		EnemyType.CHASER:
			return Color(1.0, 0.18, 0.18)  # Predatory Blood Crimson
		EnemyType.SCREAMER:
			return Color(0.95, 0.28, 0.72) # Banshee Fuchsia / Orchid
		EnemyType.LISTENER:
			return Color(0.2, 0.94, 0.68)  # Acoustic Sonar Emerald
	return Color.WHITE

func _draw() -> void:
	var base := _get_type_color()
	var t := Time.get_ticks_msec() / 1000.0

	# 1. Footstep acoustic ripple rings for mobile enemies
	for r in _step_ripples:
		var prog: float = r["age"] / 1.0
		var rad: float = prog * float(r["max_r"])
		var alpha: float = (1.0 - prog) * 0.4
		var local_p := to_local(r["pos"])
		draw_arc(local_p, rad, 0.0, TAU, 20, Color(base, alpha), 1.2)

	# 2. Biological Proximity Aura & Pulse
	if proximity > 0.0:
		var beat := 0.5 + 0.5 * sin(t * (4.0 + 10.0 * proximity))
		draw_arc(Vector2.ZERO, 20.0 + 8.0 * beat * proximity, 0.0, TAU, 32, Color(base, 0.15 + 0.45 * proximity), 2.0)

		if state == State.SLEEP:
			var breathe := 0.5 + 0.5 * sin(t * 1.8)
			draw_circle(Vector2.ZERO, 14.0 + 3.0 * breathe, Color(base, 0.12 * proximity))

	# 3. Phantom shadow trail for Chaser
	if enemy_type == EnemyType.CHASER and _trail_points.size() > 0:
		for i in range(_trail_points.size()):
			var p := to_local(_trail_points[i])
			var frac := 1.0 - float(i) / _trail_points.size()
			draw_circle(p, (11.0 - i * 0.8), Color(1.0, 0.15, 0.15, 0.25 * frac * maxf(visible_alpha, 0.5)))

	# 4. Screamer & Listener Special Active Wave Visuals
	if state == State.SCREAM and _scream_wave_radius > 0.0:
		var scream_fade := clampf(1.0 - _scream_wave_radius / 550.0, 0.0, 1.0)
		for ring in 3:
			var r_offset := _scream_wave_radius - ring * 35.0
			if r_offset > 0.0:
				draw_arc(Vector2.ZERO, r_offset, 0.0, TAU, 48, Color(0.98, 0.2, 0.4, scream_fade * 0.8), 2.5)

	if state == State.ALARM and _alarm_wave_radius > 0.0:
		var alarm_fade := clampf(1.0 - _alarm_wave_radius / 500.0, 0.0, 1.0)
		for ring in 3:
			var r_offset := _alarm_wave_radius - ring * 40.0
			if r_offset > 0.0:
				draw_arc(Vector2.ZERO, r_offset, 0.0, TAU, 48, Color(0.2, 0.95, 0.7, alarm_fade * 0.75), 2.0)

	# Frenzied Speed Boost Aura
	if speed_boost_timer > 0.0:
		var boost_pulse := 16.0 + 3.0 * sin(t * 18.0)
		draw_arc(Vector2.ZERO, boost_pulse, 0.0, TAU, 24, Color(1.0, 0.45, 0.1, 0.65 * maxf(visible_alpha, 0.5)), 1.8)

	# Early return if not visible enough and not alert/screaming/alarming
	if visible_alpha < 0.02 and state != State.ALERT and state != State.SCREAM and state != State.ALARM:
		return

	var draw_alpha := maxf(visible_alpha, 0.35 if (state == State.ALERT or state == State.SCREAM or state == State.ALARM) else 0.0)
	var type_color := Color(base, draw_alpha)

	# 5. Archetype-Specific Body Manifestation
	match enemy_type:
		EnemyType.SLEEPER:
			_draw_sleeper(t, type_color, draw_alpha)
		EnemyType.PATROLLER:
			_draw_patroller(t, type_color, draw_alpha)
		EnemyType.CHASER:
			_draw_chaser(t, type_color, draw_alpha)
		EnemyType.SCREAMER:
			_draw_screamer(t, type_color, draw_alpha)
		EnemyType.LISTENER:
			_draw_listener(t, type_color, draw_alpha)

# --- Drawing Archetypes ---

# 1. Sleeper: Violet orb, dormant closed eye slit in sleep, heavy glowing eye when awake
func _draw_sleeper(t: float, col: Color, alpha: float) -> void:
	if state == State.SLEEP:
		draw_circle(Vector2.ZERO, 13.0, Color(col, 0.5 * alpha))
		draw_line(Vector2(-9, 0), Vector2(9, 0), Color(0.18, 0.05, 0.3, alpha), 2.5)
	elif state == State.ALERT:
		_draw_alert_eye(t, col, alpha)
	elif state == State.INVESTIGATE:
		draw_circle(Vector2.ZERO, 13.0, col)
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.9, 1.0, alpha))
		draw_arc(Vector2.ZERO, 18.0 + 2.0 * sin(t * 8.0), 0.0, TAU, 24, Color(col, 0.6 * alpha), 2.0)
	else:
		draw_circle(Vector2.ZERO, 12.0, col)
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 1.0, alpha))

# 2. Patroller: Amber orb with orbiting sentinel scanner satellites
func _draw_patroller(t: float, col: Color, alpha: float) -> void:
	if state == State.ALERT:
		_draw_alert_eye(t, col, alpha)
		return

	draw_circle(Vector2.ZERO, 12.0, col)
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.95, 0.85, alpha))

	# Orbiting scanner satellite dots
	var orbit_r := 18.0
	draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 24, Color(col, 0.35 * alpha), 1.2)
	for i in 3:
		var ang := t * 3.5 + i * TAU / 3.0
		var sat_pos := Vector2.from_angle(ang) * orbit_r
		draw_circle(sat_pos, 2.5, Color(1.0, 0.95, 0.5, alpha))

# 3. Chaser: Aggressive crimson core with 6 sharp spiky barbs & demonic slit
func _draw_chaser(t: float, col: Color, alpha: float) -> void:
	var spike_count := 6
	var vib := sin(t * 24.0) * 2.0
	var core_r := 12.0

	# Sharp radiating demonic barbs
	for i in spike_count:
		var ang := i * TAU / float(spike_count) + t * (4.0 if state == State.INVESTIGATE else 1.5)
		var p_base := Vector2.from_angle(ang) * core_r
		var p_tip := Vector2.from_angle(ang) * (core_r + 8.0 + vib)
		draw_line(p_base, p_tip, Color(1.0, 0.2, 0.2, alpha), 2.4)

	draw_circle(Vector2.ZERO, core_r, col)
	# Aggressive vertical slit pupil
	draw_line(Vector2(0, -7), Vector2(0, 7), Color(0.1, 0.0, 0.0, alpha), 2.8)
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.8, 0.8, alpha))

# 4. Screamer: Mimic crystal cocoon, fracture lines on count 1, bursting petals on scream
func _draw_screamer(t: float, col: Color, alpha: float) -> void:
	var pulse := 1.0 + 0.15 * sin(t * (18.0 if screamer_count > 0 else 2.5))

	if state == State.SCREAM:
		# Bursting jaws / sonic petals
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			var tip := Vector2.from_angle(ang) * (24.0 * pulse)
			draw_line(Vector2.ZERO, tip, Color(1.0, 0.3, 0.6, alpha), 3.0)
		draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.1, 0.3, alpha))
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, alpha))
	else:
		# Crystal / Cocoon shape
		var r := 13.0 * pulse
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, col, 2.0)
		draw_circle(Vector2.ZERO, r * 0.7, Color(col, 0.4 * alpha))

		# First trigger warning fracture lines (1/2 alert)
		if screamer_count >= 1:
			var flash_col := Color(1.0, 0.2, 0.4, alpha)
			draw_line(Vector2(-8, -8), Vector2(8, 8), flash_col, 2.0)
			draw_line(Vector2(8, -8), Vector2(-8, 8), flash_col, 2.0)
			draw_circle(Vector2.ZERO, 4.0, flash_col)
		else:
			draw_circle(Vector2.ZERO, 3.5, Color(0.2, 0.05, 0.15, alpha))

# 5. Listener: Acoustic satellite crescent dish with 5 segmented charge pips
func _draw_listener(t: float, col: Color, alpha: float) -> void:
	# Acoustic curved dish
	draw_arc(Vector2.ZERO, 15.0, -PI * 0.8, PI * 0.8, 24, col, 2.5)
	draw_circle(Vector2.ZERO, 8.0, Color(col, 0.4 * alpha))

	# 5 Segmented Sound Tracking Nodes (0/5 ... 5/5)
	for i in 5:
		var ang := -PI * 0.72 + i * (PI * 1.44 / 4.0)
		var pip_pos := Vector2.from_angle(ang) * 22.0
		var active := (listener_count > i)
		if active:
			draw_circle(pip_pos, 4.0, Color(0.2, 1.0, 0.7, alpha))
			draw_circle(pip_pos, 1.8, Color(1.0, 1.0, 1.0, alpha))
		else:
			draw_circle(pip_pos, 3.0, Color(col, 0.3 * alpha))

# Generic Alert Eye with Spikes
func _draw_alert_eye(t: float, col: Color, alpha: float) -> void:
	var eye_alpha := maxf(alpha, 0.8)
	draw_arc(Vector2(0, 11), 15.0, -PI * 0.72, -PI * 0.28, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
	draw_arc(Vector2(0, -11), 15.0, PI * 0.28, PI * 0.72, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color(col, eye_alpha), 3.0)
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.9, 0.9, eye_alpha))

	# Radial alarm spikes
	for i in 6:
		var ang := i * TAU / 6.0 + t * 5.0
		var p1 := Vector2.from_angle(ang) * 16.0
		var p2 := Vector2.from_angle(ang) * (25.0 + 4.0 * sin(t * 22.0))
		draw_line(p1, p2, Color(col, 0.9 * eye_alpha), 2.0)
