extends CharacterBody2D
class_name Enemy
## One script for all 5 enemy types. Pick the type in the inspector (or use the
## enemy_*.tscn presets). Stats live in EnemyPresets.gd, drawing in EnemyVisual.gd.

signal woke_up(pos: Vector2)
signal screamed(pos: Vector2, radius: float)   # Screamer shriek
signal alarmed(pos: Vector2, target_pos: Vector2)   # Listener map-wide pulse

enum EnemyType { SLEEPER, PATROLLER, CHASER, SCREAMER, LISTENER }

enum State { SLEEP, PATROL, ALERT, INVESTIGATE, SEARCH, RETURN, SCREAM, ALARM }

@export var enemy_type: EnemyType = EnemyType.PATROLLER:
	set(val):
		enemy_type = val
		EnemyPresets.apply(self, enemy_type)

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
@export var sneak_wake_radius := 40.0 # Wake distance while the player sneaks

@export_group("Reaction Times")
@export var alert_time := 0.4          # Frozen "!" time before chasing (player's head start)
@export var investigate_timeout := 3.5 # Max chase time before losing the target

@export_group("States & Patrol")
@export var init_state: State = State.PATROL
## Global positions. Leave empty to use the Marker2D children of "EnemyPath".
@export var patrol_points: Array[Vector2] = []

const SEARCH_TIME := 2.5
const SEARCH_RADIUS := 80.0
const ARRIVE_DIST := 10.0
const WARN_RADIUS := 160.0
const SOUND_WAVE_SPEED := 400.0   # Shriek / alarm wave expansion (same as EchoLayer)
const SCREAMER_MIN_GAP := 1.0     # Seconds between two counted voices
const LISTENER_MIN_GAP := 0.8

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

# Runtime state
var state: State = State.SLEEP
var home: Vector2
var target: Vector2
var search_point: Vector2
var timer := 0.0
var patrol_idx := 0
var visible_alpha := 0.0
var proximity := 0.0

# Screamer: needs 2 sounds within 6s to shriek
var screamer_count := 0
var screamer_decay_timer := 0.0
var screamer_cooldown := 0.0
var screamer_gap_timer := 0.0
var scream_wave_radius := 0.0

# Listener: a shout starts "listening"; counts sounds up to 5, then pulses the map
var listener_count := 0
var listener_decay_timer := 0.0
var listener_cooldown := 0.0
var listener_gap_timer := 0.0
var alarm_wave_radius := 0.0

# Speed boost buff (from the Listener pulse)
var speed_boost_timer := 0.0
var speed_boost_mult := 1.0

# Data for EnemyVisual
var trail_points: Array[Vector2] = []
var step_ripples: Array[Dictionary] = []
var _step_echo_timer := 0.0
var _visual: EnemyVisual


func _init() -> void:
	EnemyPresets.apply(self, enemy_type)


func _ready() -> void:
	add_to_group("enemy")
	home = global_position
	_collect_patrol_points()
	state = init_state

	# Without a route a patroller just stands guard
	if state == State.PATROL and patrol_points.size() < 2:
		state = State.SLEEP

	_visual = EnemyVisual.new()
	_visual.enemy = self
	add_child(_visual)

	$CatchArea.body_entered.connect(_on_catch)


func _is_stationary() -> bool:
	return enemy_type == EnemyType.SCREAMER or enemy_type == EnemyType.LISTENER


# Patrol route: patrol_points, else Marker2D children of "EnemyPath" (if moved away from the enemy)
func _collect_patrol_points() -> void:
	var path := get_node_or_null("EnemyPath")
	if path == null:
		return
	if patrol_points.is_empty():
		var markers: Array[Vector2] = []
		var spread := false
		for child in path.get_children():
			if child is Marker2D:
				markers.append(child.global_position)
				if child.global_position.distance_to(global_position) > 1.0:
					spread = true
		if spread:
			patrol_points = markers
	path.queue_free()


# --- Sound detection ---------------------------------------------------------

func on_sound(pos: Vector2, loudness: float, radius: float, is_voice: bool = false) -> void:
	var is_sneak_step := (not is_voice and loudness <= 0.05)
	var is_walk_step := (not is_voice and loudness > 0.05)

	if enemy_type == EnemyType.LISTENER:
		# Deaf to all footsteps (walking and sneaking): only shouts count
		if not is_voice:
			return
	else:
		if is_sneak_step and not can_hear_sneak:
			return
		if is_walk_step and not can_hear_walk:
			return
		if is_voice and not can_hear_voice:
			return

	var dist: float = global_position.distance_to(pos)
	var effective_max := minf(radius, hearing_range)
	if dist > effective_max:
		return

	var heard := loudness * (1.0 - dist / effective_max)
	if heard < hearing_threshold:
		return

	match enemy_type:
		EnemyType.SCREAMER:
			_handle_screamer_sound()
		EnemyType.LISTENER:
			_handle_listener_sound(is_voice)
		_:
			_notice(pos)


func _notice(pos: Vector2) -> void:
	target = pos
	match state:
		State.SLEEP, State.PATROL, State.RETURN:
			_enter(State.ALERT)
			woke_up.emit(global_position)
		State.SEARCH:
			if timer >= 0.5:
				_enter(State.INVESTIGATE)
		# While chasing the target keeps updating, but the timer is not reset,
		# so the chase timeout lets the player escape.


# Used by map-wide alarms: ignores hearing range
func force_alert_to(pos: Vector2) -> void:
	if _is_stationary():
		return
	target = pos
	_enter(State.INVESTIGATE)
	reveal(1.0)


func apply_speed_boost(multiplier: float = 1.35, duration: float = 7.5) -> void:
	speed_boost_mult = multiplier
	speed_boost_timer = duration
	reveal(1.0)


# --- Screamer ----------------------------------------------------------------
# 1st sound: alert only. 2nd sound: shriek (attracts monsters, immobilizes player).
# Afterwards it falls asleep again.

func _handle_screamer_sound() -> void:
	if state == State.SCREAM or screamer_cooldown > 0.0:
		return
	# One word can trigger the mic twice; ignore sounds too close together
	if screamer_count > 0 and screamer_gap_timer > 0.0:
		return

	screamer_count += 1
	screamer_decay_timer = 6.0
	screamer_gap_timer = SCREAMER_MIN_GAP
	reveal(1.0)

	if screamer_count == 1:
		_enter(State.ALERT)
	else:
		_trigger_scream()


func _trigger_scream() -> void:
	_enter(State.SCREAM)
	screamer_count = 0
	scream_wave_radius = 0.0
	screamed.emit(global_position, 550.0)


# --- Listener ----------------------------------------------------------------
# A shout starts listening. It then counts sounds (not sneaking); at 5 it sends a
# map-wide pulse that pulls every monster to it and speeds them up.

func _handle_listener_sound(is_voice: bool) -> void:
	if state == State.ALARM or listener_cooldown > 0.0:
		return

	if listener_count == 0 and not is_voice:
		return
	# Only voices count, and not faster than one per LISTENER_MIN_GAP
	if not is_voice or (listener_count > 0 and listener_gap_timer > 0.0):
		return

	listener_count += 1
	listener_decay_timer = 8.0
	listener_gap_timer = LISTENER_MIN_GAP
	reveal(1.0)

	if listener_count >= 5:
		_trigger_listener_alarm()
	else:
		_enter(State.ALERT)


func _trigger_listener_alarm() -> void:
	_enter(State.ALARM)
	listener_count = 0
	alarm_wave_radius = 0.0
	alarmed.emit(global_position, global_position)


# --- State machine -----------------------------------------------------------

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


# Notices a player who walks right next to it
func _sense_player() -> void:
	if state == State.ALERT or state == State.SCREAM or state == State.ALARM:
		return
	var player := _get_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)

	if state == State.SLEEP:
		var wake_radius := sneak_wake_radius if player.sneaking else sleep_wake_radius
		if dist <= wake_radius:
			if enemy_type == EnemyType.SCREAMER:
				_handle_screamer_sound()
			elif enemy_type != EnemyType.LISTENER: # Listener only reacts to shouts
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


# How scary this enemy is right now (drives the heartbeat)
func get_threat_level(player_pos: Vector2) -> float:
	var dist: float = global_position.distance_to(player_pos)
	# Active enemies far away are less scary: full threat within 300px, half beyond 600px
	var active_threat := clampf(1.0 - maxf(dist - 300.0, 0.0) / 600.0, 0.5, 1.0)

	match state:
		State.ALERT, State.INVESTIGATE, State.SCREAM, State.ALARM:
			return active_threat
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


func _physics_process(delta: float) -> void:
	timer += delta
	visible_alpha = move_toward(visible_alpha, 0.0, delta * 0.7)
	_sense_player()
	_tick_timers(delta)

	var boost := speed_boost_mult if speed_boost_timer > 0.0 else 1.0
	_run_state(delta, patrol_speed * boost, chase_speed * boost)

	if not _is_stationary():
		move_and_slide()
		_update_trail_and_steps(delta)

	for r in step_ripples:
		r["age"] += delta
	step_ripples = step_ripples.filter(func(r): return r["age"] < 1.0)

	_update_proximity()
	_visual.queue_redraw()


# Cooldowns, counter decay and buff expiry
func _tick_timers(delta: float) -> void:
	if screamer_decay_timer > 0.0:
		screamer_decay_timer -= delta
		if screamer_decay_timer <= 0.0 and screamer_count > 0:
			screamer_count = 0
			if state == State.ALERT:
				_enter(State.SLEEP)
	screamer_cooldown = maxf(0.0, screamer_cooldown - delta)
	screamer_gap_timer = maxf(0.0, screamer_gap_timer - delta)

	if listener_decay_timer > 0.0:
		listener_decay_timer -= delta
		if listener_decay_timer <= 0.0 and listener_count > 0:
			listener_count -= 1
			listener_decay_timer = 5.0 if listener_count > 0 else 0.0
			if listener_count == 0 and state == State.ALERT:
				_enter(State.SLEEP)
	listener_cooldown = maxf(0.0, listener_cooldown - delta)
	listener_gap_timer = maxf(0.0, listener_gap_timer - delta)

	if speed_boost_timer > 0.0:
		speed_boost_timer -= delta
		if speed_boost_timer <= 0.0:
			speed_boost_mult = 1.0


func _run_state(delta: float, cur_patrol: float, cur_chase: float) -> void:
	match state:
		State.SLEEP:
			velocity = Vector2.ZERO
		State.PATROL:
			if patrol_points.size() < 2:
				velocity = Vector2.ZERO
			elif _move_toward(patrol_points[patrol_idx], cur_patrol):
				patrol_idx = (patrol_idx + 1) % patrol_points.size()
		State.ALERT:
			velocity = Vector2.ZERO
			# Stationary enemies stay alert until triggered again or the count decays
			if timer >= alert_time and not _is_stationary():
				_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			if _move_toward(target, cur_chase) or timer >= investigate_timeout:
				velocity = Vector2.ZERO
				_enter(State.SEARCH)
		State.SEARCH:
			if _move_toward(search_point, cur_patrol):
				search_point = _random_search_point()
			if timer >= SEARCH_TIME:
				_enter(State.RETURN)
		State.RETURN:
			var dest := patrol_points[patrol_idx] if patrol_points.size() > 0 else home
			if _move_toward(dest, cur_patrol):
				_enter(State.PATROL if patrol_points.size() > 1 else State.SLEEP)
		State.SCREAM:
			velocity = Vector2.ZERO
			scream_wave_radius += delta * SOUND_WAVE_SPEED
			reveal(1.0)
			if timer >= 2.2:
				screamer_cooldown = 5.0
				_enter(State.SLEEP)
		State.ALARM:
			velocity = Vector2.ZERO
			alarm_wave_radius += delta * SOUND_WAVE_SPEED
			reveal(1.0)
			if timer >= 2.5:
				listener_cooldown = 6.0
				_enter(State.SLEEP)


# Chaser afterimage + footstep ripples (visual only)
func _update_trail_and_steps(delta: float) -> void:
	if enemy_type == EnemyType.CHASER and state == State.INVESTIGATE and velocity.length() > 20.0:
		trail_points.push_front(global_position)
		if trail_points.size() > 10:
			trail_points.pop_back()
	elif trail_points.size() > 0:
		trail_points.pop_back()

	if velocity.length() > 15.0:
		_step_echo_timer += delta
		var chasing := state == State.INVESTIGATE
		if _step_echo_timer >= (0.4 if chasing else 0.75):
			_step_echo_timer = 0.0
			step_ripples.append({
				"pos": global_position,
				"age": 0.0,
				"max_r": 35.0 if chasing else 22.0,
			})


func _move_toward(dest: Vector2, speed: float) -> bool:
	var to_dest := dest - global_position
	if to_dest.length() < ARRIVE_DIST:
		velocity = Vector2.ZERO
		return true
	velocity = to_dest.normalized() * speed
	return false


func _on_catch(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()


func reveal(amount: float = 1.0) -> void:
	visible_alpha = clampf(visible_alpha + amount, 0.0, 1.0)
