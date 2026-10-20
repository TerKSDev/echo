extends CharacterBody2D
class_name Enemy
## One script for all 5 enemy types. Pick the type in the inspector (or use the
## enemy_*.tscn presets). Stats live in EnemyPresets.gd, drawing in EnemyVisual.gd.

signal woke_up(pos: Vector2)
signal step_taken(pos: Vector2, is_chasing: bool, occluded: bool)
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
const RETURN_TIMEOUT := 6.0
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
var is_wall_occluded: bool = false

# Screamer: needs 2 sounds within 6s to shriek
var screamer_count := 0
var screamer_decay_timer := 0.0
var screamer_cooldown := 0.0
var screamer_gap_timer := 0.0
var scream_wave_radius := 0.0

# Listener: a shout starts "listening"; counts sounds up to 5, then pulses the map
var listener_count := 0
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

	# Wall occlusion: footsteps cannot pass through walls; shouts lose 75% volume
	if _is_blocked_by_wall(pos, global_position):
		if not is_voice:
			return
		loudness *= 0.25

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
			# Already actively hunting after a chase: snap back to chasing without re-roaring every step
			if timer >= 0.4:
				_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			# While already chasing, update destination toward latest sound,
			# but do not reset chase timer so chase timeout lets the player escape.
			pass


# Used by map-wide alarms: ignores hearing range
func force_alert_to(pos: Vector2) -> void:
	if _is_stationary():
		return
	target = pos
	_enter(State.ALERT)
	woke_up.emit(global_position)
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
		woke_up.emit(global_position)
	else:
		_trigger_scream()


func _trigger_scream() -> void:
	_enter(State.SCREAM)
	screamer_count = 0
	scream_wave_radius = 0.0
	screamed.emit(global_position, 550.0)


# --- Listener ----------------------------------------------------------------
# A shout starts listening. It then counts sounds; at 5 it sends a
# map-wide pulse that pulls every monster to it and speeds them up.
# Count never decays automatically until triggered.

func _handle_listener_sound(is_voice: bool) -> void:
	if state == State.ALARM or listener_cooldown > 0.0:
		return

	# Only voices count, and not faster than one per LISTENER_MIN_GAP
	if not is_voice or (listener_count > 0 and listener_gap_timer > 0.0):
		return

	listener_count += 1
	listener_gap_timer = LISTENER_MIN_GAP
	reveal(1.2)

	if listener_count >= 5:
		_trigger_listener_alarm()
	else:
		_enter(State.ALERT)
		woke_up.emit(global_position)


func _trigger_listener_alarm() -> void:
	_enter(State.ALARM)
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
		# Survival-horror discovery shudder / camera jolt when a monster spots the player
		if s == State.ALERT and not _is_stationary():
			var player := _get_player()
			if player != null and is_instance_valid(player):
				var dist: float = global_position.distance_to(player.global_position)
				if dist < 450.0:
					player.camera_shake(0.28, 5.0 * (1.0 - dist / 450.0))


func _random_search_point() -> Vector2:
	var candidate: Vector2 = target + Vector2.from_angle(randf() * TAU) * randf_range(30.0, SEARCH_RADIUS)
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, candidate)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Vector2 = hit.position
		var dir: Vector2 = (hit_pos - global_position).normalized()
		return hit_pos - dir * 18.0
	return candidate


func _get_player() -> Node2D:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.alive:
		return null
	return player as Node2D


# Checks if a solid wall (collision layer 1) blocks line of sight between two points
func _is_blocked_by_wall(from_pos: Vector2, to_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collision_mask = 1
	var exclude: Array[RID] = [get_rid()]
	var player = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		exclude.append(player.get_rid())
	query.exclude = exclude

	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty()

# Notices a player who walks right next to it
func _sense_player() -> void:
	if state == State.ALERT or state == State.SCREAM or state == State.ALARM:
		return
	var player := _get_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)

	# Cannot sense player through solid walls
	if is_wall_occluded:
		return

	if state == State.SLEEP:
		var wake_radius: float = sneak_wake_radius if player.sneaking else sleep_wake_radius
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
	if is_wall_occluded:
		return
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
	var raw_threat := 0.0

	match state:
		State.ALERT, State.INVESTIGATE, State.SCREAM, State.ALARM:
			raw_threat = active_threat
		State.SEARCH:
			raw_threat = clampf(maxf(0.5, 1.0 - dist / 250.0), 0.0, 1.0)
		State.PATROL, State.RETURN:
			raw_threat = clampf(1.0 - dist / 220.0, 0.0, 1.0)
		State.SLEEP:
			if enemy_type == EnemyType.SCREAMER and screamer_count > 0:
				raw_threat = clampf(1.0 - dist / 280.0, 0.4, 0.95)
			elif enemy_type == EnemyType.LISTENER and listener_count > 0:
				raw_threat = clampf(0.2 * listener_count + (1.0 - dist / 260.0) * 0.4, 0.0, 0.9)
			else:
				raw_threat = clampf(inverse_lerp(180.0, sleep_wake_radius, dist), 0.0, 0.9)

	# Walls muffle threat: idle monsters behind a wall don't cause false heartbeat panic
	if is_wall_occluded:
		if state == State.SLEEP or state == State.PATROL or state == State.RETURN:
			return 0.0
		return raw_threat * 0.35
	return raw_threat


func _physics_process(delta: float) -> void:
	timer += delta
	visible_alpha = move_toward(visible_alpha, 0.0, delta * 0.7)

	var player := _get_player()
	if player != null and is_instance_valid(player):
		is_wall_occluded = _is_blocked_by_wall(global_position, player.global_position)
	else:
		is_wall_occluded = false

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

	# Listener counts do NOT decay over time (persists until 5 triggers alarm)
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
			# Stationary enemies (Screamer/Listener) return to sleep so they fade back into darkness;
			# mobile enemies finish their discovery roar and begin chasing.
			if _is_stationary():
				if timer >= alert_time:
					_enter(State.SLEEP)
			else:
				if timer >= alert_time:
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
			if _move_toward(dest, cur_patrol) or timer >= RETURN_TIMEOUT:
				if patrol_points.size() < 2:
					home = global_position
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
				listener_cooldown = 8.0
				listener_count = 0
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
			step_taken.emit(global_position, chasing, is_wall_occluded)


func _move_toward(dest: Vector2, speed: float) -> bool:
	var to_dest := dest - global_position
	if to_dest.length() < ARRIVE_DIST:
		velocity = Vector2.ZERO
		return true
	var dir := to_dest.normalized()
	# Slide smoothly along walls instead of headbutting into them
	if get_slide_collision_count() > 0:
		var col := get_slide_collision(0)
		if col != null:
			var normal := col.get_normal()
			if dir.dot(normal) < -0.1:
				var slide_dir := dir.slide(normal).normalized()
				if not slide_dir.is_zero_approx():
					dir = slide_dir
	velocity = dir * speed
	return false


func _on_catch(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die(int(enemy_type))


func reveal(amount: float = 1.0) -> void:
	visible_alpha = clampf(visible_alpha + amount, 0.0, 1.0)
