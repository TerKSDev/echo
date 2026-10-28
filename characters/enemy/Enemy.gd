extends CharacterBody2D
class_name Enemy
## One script for all 5 enemy types. Pick the type in the inspector (or use the
## enemy_*.tscn presets). Stats live in EnemyPresets.gd, drawing in EnemyVisual.gd.

signal woke_up(pos: Vector2)
signal alert_triggered(enemy: Enemy)
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
@export var sneak_sense_radius := 26.0
@export var sleep_wake_radius := 75.0
@export var sneak_wake_radius := 28.0 # Wake distance while the player sneaks

@export_group("Reaction Times")
@export var alert_time := 0.4          # Frozen "!" time before chasing (player's head start)
@export var investigate_timeout := 3.5 # Max chase time before losing the target

@export_group("States & Patrol")
@export var init_state: State = State.PATROL
## Global positions. Leave empty to use the Marker2D children of "EnemyPath".
@export var patrol_points: Array[Vector2] = []

const SEARCH_TIME := 2.5
const RETURN_TIMEOUT := 9.0
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
var is_in_water := false
var is_investigating_decoy := false
var _snore_timer := 2.5
var eye_linger_timer := 0.0
var spasm_timer := 0.0
var spasm_offset := Vector2.ZERO

# Data for EnemyVisual & AI steering
var trail_points: Array[Vector2] = []
var step_ripples: Array[Dictionary] = []
var facing_dir := Vector2.DOWN
var _step_echo_timer := 0.0
var _patrol_wait_timer := 0.0
var _search_wait_timer := 0.0
var _stuck_timer := 0.0
var _last_progress_pos := Vector2.ZERO
var _visual: EnemyVisual
var _player_cached: Node2D = null
var _cached_exclude: Array[RID] = []
var _ray_query: PhysicsRayQueryParameters2D = null
var _last_occ_self_pos := Vector2(-99999.0, -99999.0)
var _last_occ_player_pos := Vector2(-99999.0, -99999.0)
var _was_visually_active := true
var _stun_timer := 0.0


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

	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		_apply_challenge_modifiers()


func _apply_challenge_modifiers() -> void:
	if ChallengeModifiers.has_curse("curse_swift_predators"):
		patrol_speed *= 1.15
		chase_speed *= 1.15
	if ChallengeModifiers.has_curse("curse_extended_hunt"):
		investigate_timeout *= 1.75
	if ChallengeModifiers.has_curse("curse_acute_hearing"):
		hearing_range *= 1.30
	if ChallengeModifiers.has_curse("curse_predator_instinct"):
		sneak_wake_radius *= 1.80
		sleep_wake_radius *= 1.35


func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)
	velocity = Vector2.ZERO


func _is_stationary() -> bool:
	return enemy_type == EnemyType.SCREAMER or enemy_type == EnemyType.LISTENER


# Patrol route: PatrolPath node, patrol_points array, or Marker2D children of "EnemyPath"
func _collect_patrol_points() -> void:
	var patrol_path := get_node_or_null("PatrolPath") as PatrolPath
	if patrol_path != null:
		var pts: Array[Vector2] = patrol_path.get_global_waypoints()
		if not pts.is_empty():
			patrol_points = pts
			return

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

func on_sound(pos: Vector2, loudness: float, radius: float, is_voice: bool = false, is_sneak: bool = false) -> void:
	var is_sneak_step := (not is_voice and (is_sneak or loudness <= 0.05))
	var is_walk_step := (not is_voice and not is_sneak and loudness > 0.05)

	var p_node := _get_player()
	var player_in_water := p_node != null and is_instance_valid(p_node) and p_node.get("water_count") != null and int(p_node.water_count) > 0
	var is_water_move := not is_voice and player_in_water and not is_sneak

	if enemy_type == EnemyType.LISTENER:
		# Listener ignores normal footsteps, but is alerted by shouts
		if not is_voice:
			return
	elif enemy_type == EnemyType.SCREAMER:
		# Screamer ignores dry footsteps and sneaking, but detects voice AND unsneaked water movement splashing
		if not is_voice and not is_water_move:
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

	# Wall occlusion: footsteps cannot pass through walls; shouts muffled by dense rock only travel <= 140px (~4 tiles)
	var wall_blocked := _is_blocked_by_wall(pos, global_position)
	if wall_blocked:
		if not is_voice:
			return
		if dist > 140.0:
			return
		loudness *= 0.20

	var thresh := 0.07 if (enemy_type == EnemyType.SLEEPER and state != State.SLEEP) else hearing_threshold
	var heard := loudness * (1.0 - dist / effective_max)
	if heard < thresh:
		return

	match enemy_type:
		EnemyType.SCREAMER:
			_handle_screamer_sound()
		EnemyType.LISTENER:
			_handle_listener_sound(is_voice)
		_:
			_notice(pos, wall_blocked)


func _notice(pos: Vector2, wall_blocked: bool = false) -> void:
	is_investigating_decoy = false
	var to_sound := (pos - global_position).normalized()
	if not to_sound.is_zero_approx():
		facing_dir = to_sound
	_stuck_timer = 0.0

	# If the sound is occluded behind a solid wall (muffled shout):
	# The predator is awakened / alerted facing the wall, but does NOT blindly charge into solid rock.
	if wall_blocked:
		reveal(0.7)
		match state:
			State.SLEEP, State.RETURN:
				_enter(State.ALERT)
				woke_up.emit(global_position)
			State.PATROL:
				_enter(State.ALERT)
		return

	target = pos
	match state:
		State.SLEEP, State.PATROL, State.RETURN:
			_enter(State.ALERT)
			woke_up.emit(global_position)
		State.SEARCH:
			# Already actively hunting after a chase: snap back to chasing without re-roaring every step
			if timer >= 0.15:
				_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			# While already chasing, update destination toward latest sound,
			# and give a small chase timer refresh so continuous loud running keeps the pursuit alive.
			timer = maxf(0.0, timer - 0.5)


# Decoy stone sound reaction: luring/distraction behavior
func on_decoy_sound(pos: Vector2, loudness: float, radius: float, is_wall_clink: bool = false) -> void:
	var dist: float = global_position.distance_to(pos)
	var effective_max := minf(radius, hearing_range * 1.1)
	if dist > effective_max:
		return

	var wall_blocked := _is_blocked_by_wall(pos, global_position)
	if wall_blocked:
		# Floor impact in adjacent room: solid basalt wall 100% blocks airborne sound
		if not is_wall_clink:
			return
		# Physical wall clink: structure-borne vibration, only audible within 110px (~3.5 tiles) across the wall
		if dist > 110.0:
			return
		loudness *= 0.28

	var heard := loudness * (1.0 - dist / effective_max)
	if heard < hearing_threshold * 0.8:
		return

	var to_sound := (pos - global_position).normalized()
	if not to_sound.is_zero_approx():
		facing_dir = to_sound

	if enemy_type == EnemyType.SCREAMER:
		_handle_screamer_sound()
		return

	if enemy_type == EnemyType.LISTENER:
		_handle_listener_sound(true)
		return

	# If blocked by wall: the monster perceives the knock/vibration through the rock,
	# but does NOT mindlessly sprint into the dead wall. It wakes up, turns to face the wall, and stays on high alert.
	if wall_blocked:
		reveal(0.75)
		if state == State.SLEEP or state == State.RETURN:
			_enter(State.ALERT)
			woke_up.emit(global_position)
		return

	# Clear path / open space: full decoy investigation (runs to the pebble)
	target = pos
	is_investigating_decoy = true
	_stuck_timer = 0.0

	match state:
		State.SLEEP, State.PATROL, State.RETURN, State.SEARCH:
			_enter_decoy_investigate()
		State.ALERT, State.INVESTIGATE:
			timer = 0.0
			reveal(0.85)


func _enter_decoy_investigate() -> void:
	state = State.INVESTIGATE
	timer = 0.0
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	reveal(float(STATE_FLASH.get(State.INVESTIGATE, 0.7)))


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

func _handle_listener_sound(_is_voice: bool) -> void:
	if state == State.ALARM or listener_cooldown > 0.0:
		return

	# Voices and decoy pebbles count, but ignore triggers faster than one per LISTENER_MIN_GAP
	if listener_count > 0 and listener_gap_timer > 0.0:
		return

	listener_count += 1
	listener_gap_timer = LISTENER_MIN_GAP
	reveal(1.2)

	var max_count := 2 if (GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_listener_feedback")) else 3
	if listener_count >= max_count:
		_trigger_listener_alarm()
	else:
		_enter(State.ALERT)
		woke_up.emit(global_position)


func _trigger_listener_alarm() -> void:
	_enter(State.ALARM)
	alarm_wave_radius = 0.0
	alarmed.emit(global_position, global_position)
	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_listener_feedback"):
		var p := _get_player() as Player
		if p != null and is_instance_valid(p) and p.alive:
			p.immobilize(1.2)


# --- State machine -----------------------------------------------------------

func _enter(s: State) -> void:
	var changed := s != state
	if s != State.INVESTIGATE and s != State.SEARCH:
		is_investigating_decoy = false
	state = s
	timer = 0.0
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	if s == State.SEARCH:
		_search_wait_timer = 0.18
		search_point = _random_search_point()
	elif s == State.ALERT:
		var to_t: Vector2 = target - global_position
		if not to_t.is_zero_approx():
			facing_dir = to_t.normalized()
	if changed:
		reveal(float(STATE_FLASH.get(s, 0.5)))
		if s == State.ALERT:
			alert_triggered.emit(self)
		# Survival-horror discovery shudder / camera jolt when a monster spots the player
		if s == State.ALERT and not _is_stationary():
			var player := _get_player()
			if player != null and is_instance_valid(player):
				var dist: float = global_position.distance_to(player.global_position)
				if dist < 450.0:
					player.camera_shake(0.28, 5.0 * (1.0 - dist / 450.0))


func _random_search_point() -> Vector2:
	var origin: Vector2 = global_position
	var space := get_world_2d().direct_space_state
	var best_pt: Vector2 = origin
	var best_dist := 0.0
	var q := _get_ray_query()
	# Try up to 4 angles and pick the most open reachable direction so the monster doesn't search into a corner
	for attempt in 4:
		var candidate: Vector2 = origin + Vector2.from_angle(randf() * TAU) * randf_range(40.0, SEARCH_RADIUS)
		q.from = origin
		q.to = candidate
		var hit: Dictionary = space.intersect_ray(q)
		var reach_pt: Vector2 = candidate
		if not hit.is_empty():
			var hit_pos: Vector2 = hit.position
			var dir: Vector2 = (hit_pos - origin).normalized()
			reach_pt = hit_pos - dir * 18.0
		var d: float = origin.distance_to(reach_pt)
		if d > best_dist:
			best_dist = d
			best_pt = reach_pt
	return best_pt


func _get_player() -> Node2D:
	if _player_cached == null or not is_instance_valid(_player_cached):
		_player_cached = get_tree().get_first_node_in_group("player") as Node2D
		_cached_exclude.clear()
	if _player_cached == null or not _player_cached.get("alive"):
		return null
	return _player_cached


# Excludes this enemy and the player so wall raycasts only detect physical walls/obstacles
func _wall_query_exclude() -> Array[RID]:
	if _cached_exclude.is_empty():
		_cached_exclude.append(get_rid())
		var p := _get_player()
		if p is CollisionObject2D and is_instance_valid(p):
			_cached_exclude.append(p.get_rid())
	return _cached_exclude


func _get_ray_query() -> PhysicsRayQueryParameters2D:
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters2D.new()
		_ray_query.collision_mask = 1
	_ray_query.exclude = _wall_query_exclude()
	return _ray_query


# Checks if a solid wall (collision layer 1) blocks line of sight between two points
func _is_blocked_by_wall(from_pos: Vector2, to_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var q := _get_ray_query()
	q.from = from_pos
	q.to = to_pos
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty()

# Notices a player who walks right next to it
func _sense_player() -> void:
	if state == State.ALERT or state == State.SCREAM or state == State.ALARM:
		return
	if is_investigating_decoy:
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
				# Only trigger 2nd shriek from proximity if the player keeps moving after the 1st warning
				if screamer_count == 0 or player.velocity.length() > 8.0:
					_handle_screamer_sound()
			elif enemy_type != EnemyType.LISTENER: # Listener only reacts to shouts
				_notice(player.global_position)
		return

	# While awake (PATROL, INVESTIGATE, SEARCH, RETURN):
	# If player is walking openly with no walls during a chase, maintain visual awareness (140px);
	# Sneaking collapses detection radius down to sneak_sense_radius (24~32px).
	var active_sense: float = 140.0 if state == State.INVESTIGATE else sense_radius
	var radius: float = sneak_sense_radius if player.sneaking else active_sense
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


# How scary this enemy is right now (drives the player's dynamic heartbeat)
func get_threat_level(player_pos: Vector2) -> float:
	var dist: float = global_position.distance_to(player_pos)

	# Baseline proximity fear: scales smoothly as the player draws closer within 340px (~10 tiles)
	var prox: float = clampf(1.0 - dist / 340.0, 0.0, 1.0)
	var raw_threat := 0.0

	match state:
		State.ALERT, State.INVESTIGATE, State.SCREAM, State.ALARM:
			# Active hunting or shrieking: high alert panic surge
			var active_urgency := clampf(1.0 - maxf(dist - 240.0, 0.0) / 480.0, 0.65, 1.0)
			raw_threat = maxf(prox, active_urgency)
		State.SEARCH:
			raw_threat = clampf(maxf(prox * 1.1, 0.4), 0.0, 1.0)
		State.PATROL, State.RETURN:
			# Patroller / wandering monster proximity
			raw_threat = prox * 0.9
		State.SLEEP:
			if enemy_type == EnemyType.SCREAMER and screamer_count > 0:
				raw_threat = clampf(1.0 - dist / 320.0, 0.45, 0.98)
			elif enemy_type == EnemyType.LISTENER and listener_count > 0:
				raw_threat = clampf(0.35 * listener_count + (1.0 - dist / 300.0) * 0.45, 0.0, 0.95)
			else:
				# Sleeper proximity: heart quickens steadily as you approach its slumber radius
				raw_threat = prox * 0.85

	# Wall occlusion muffles threat, but does not completely extinguish intuition of nearby predators behind thin walls
	if is_wall_occluded:
		if state == State.ALERT or state == State.INVESTIGATE or state == State.SCREAM or state == State.ALARM:
			return raw_threat * 0.45
		# Faint muffled intuition for sleeping/patrolling monsters right behind a wall (dist < 200px)
		return clampf(raw_threat * 0.38, 0.0, 0.35) if dist < 200.0 else 0.0

	return raw_threat


func _physics_process(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer = maxf(0.0, _stun_timer - delta)
		velocity = Vector2.ZERO
		return

	timer += delta
	visible_alpha = move_toward(visible_alpha, 0.0, delta * 0.7)
	if visible_alpha > 0.05:
		eye_linger_timer = 0.45
	elif eye_linger_timer > 0.0:
		eye_linger_timer = maxf(0.0, eye_linger_timer - delta)

	if spasm_timer > 0.0:
		spasm_timer = maxf(0.0, spasm_timer - delta)
		if spasm_timer > 0.0:
			var spasm_prog := spasm_timer / 0.16
			spasm_offset = Vector2(randf_range(-2.8, 2.8), randf_range(-2.8, 2.8)) * spasm_prog
		else:
			spasm_offset = Vector2.ZERO

	var player := _get_player()
	if player != null and is_instance_valid(player):
		var p_pos: Vector2 = player.global_position
		var d_to_player: float = global_position.distance_to(p_pos)
		if d_to_player <= 650.0:
			if d_to_player <= 165.0 or global_position.distance_squared_to(_last_occ_self_pos) > 36.0 or p_pos.distance_squared_to(_last_occ_player_pos) > 36.0:
				_last_occ_self_pos = global_position
				_last_occ_player_pos = p_pos
				is_wall_occluded = _is_blocked_by_wall(global_position, p_pos)
		else:
			is_wall_occluded = true
	else:
		is_wall_occluded = false

	_sense_player()
	_tick_timers(delta)

	var boost := speed_boost_mult if speed_boost_timer > 0.0 else 1.0
	var water_drag: float
	if is_in_water:
		water_drag = 1.25 if (GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_treacherous_waters")) else 0.72
	else:
		water_drag = 1.0
	_run_state(delta, patrol_speed * boost * water_drag, chase_speed * boost * water_drag)

	if not _is_stationary():
		move_and_slide()
		_update_trail_and_steps(delta)

	if not step_ripples.is_empty():
		var w_idx := 0
		for i in step_ripples.size():
			var r: Dictionary = step_ripples[i]
			var speed_factor: float = 1.35 if (r.get("is_breath", false) == true) else 1.0
			var next_age: float = float(r["age"]) + delta * speed_factor
			if next_age < 1.0:
				r["age"] = next_age
				step_ripples[w_idx] = r
				w_idx += 1
		if w_idx < step_ripples.size():
			step_ripples.resize(w_idx)

	_update_proximity()

	var is_visually_active: bool = (
		visible_alpha > 0.01
		or eye_linger_timer > 0.0
		or spasm_timer > 0.0
		or not step_ripples.is_empty()
		or not trail_points.is_empty()
		or speed_boost_timer > 0.0
		or state == State.ALERT
		or state == State.SCREAM
		or state == State.ALARM
	)
	if is_visually_active or _was_visually_active:
		_visual.queue_redraw()
		_was_visually_active = is_visually_active


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
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			if enemy_type == EnemyType.SLEEPER:
				_snore_timer -= delta
				if _snore_timer <= 0.0:
					_snore_timer = randf_range(3.6, 5.4)
					step_ripples.append({
						"pos": global_position,
						"age": 0.0,
						"max_r": 28.0,
						"is_breath": true,
						"is_water": false
					})
					var p_node := get_tree().get_first_node_in_group("player")
					if p_node != null and is_instance_valid(p_node):
						if global_position.distance_to(p_node.global_position) <= 240.0:
							var sfx_mgr := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
							if sfx_mgr == null:
								sfx_mgr = get_node_or_null("../../SfxManager") as SfxManager
							if sfx_mgr != null and sfx_mgr.has_method("play_sleeper_snore"):
								sfx_mgr.play_sleeper_snore(global_position, is_wall_occluded)
		State.PATROL:
			if patrol_points.size() < 2:
				velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			elif _patrol_wait_timer > 0.0:
				_patrol_wait_timer -= delta
				velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
			elif _move_toward(patrol_points[patrol_idx], cur_patrol, delta):
				patrol_idx = (patrol_idx + 1) % patrol_points.size()
				_patrol_wait_timer = 0.42
		State.ALERT:
			velocity = velocity.move_toward(Vector2.ZERO, 950.0 * delta)
			# Stationary enemies (Screamer/Listener) return to sleep so they fade back into darkness;
			# mobile enemies finish their discovery roar and begin chasing.
			if _is_stationary():
				if timer >= alert_time:
					_enter(State.SLEEP)
			else:
				if timer >= alert_time:
					_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			if _move_toward(target, cur_chase, delta) or timer >= investigate_timeout or _is_stuck(delta):
				velocity = Vector2.ZERO
				_enter(State.SEARCH)
		State.SEARCH:
			if _search_wait_timer > 0.0:
				_search_wait_timer -= delta
				velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
			elif _move_toward(search_point, cur_patrol, delta) or _is_stuck(delta):
				_search_wait_timer = 0.35
				search_point = _random_search_point()
			if timer >= SEARCH_TIME:
				is_investigating_decoy = false
				_enter(State.RETURN)
		State.RETURN:
			var dest := patrol_points[patrol_idx] if patrol_points.size() > 0 else home
			if _move_toward(dest, cur_patrol, delta) or timer >= RETURN_TIMEOUT or _is_stuck(delta):
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


func _is_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_progress_pos) > 10.0:
		_last_progress_pos = global_position
		_stuck_timer = 0.0
		return false
	_stuck_timer += delta
	var limit := 1.35 if state == State.RETURN else 0.65
	if _stuck_timer >= limit:
		_stuck_timer = 0.0
		_last_progress_pos = global_position
		return true
	return false


# Chaser afterimage + footstep ripples (visual only)
func _update_trail_and_steps(delta: float) -> void:
	if velocity.length() > 8.0:
		var target_face := velocity.normalized()
		facing_dir = facing_dir.slerp(target_face, clampf(delta * 12.0, 0.0, 1.0)).normalized()

	if enemy_type == EnemyType.CHASER and state == State.INVESTIGATE and velocity.length() > 20.0:
		trail_points.push_front(global_position)
		if trail_points.size() > 10:
			trail_points.pop_back()
	elif trail_points.size() > 0:
		trail_points.pop_back()

	if velocity.length() > 15.0:
		_step_echo_timer += delta
		var chasing := state == State.INVESTIGATE
		var interval := (0.55 if chasing else 0.95) if is_in_water else (0.42 if chasing else 0.78)
		if _step_echo_timer >= interval:
			_step_echo_timer = 0.0
			step_ripples.append({
				"pos": global_position,
				"age": 0.0,
				"max_r": (48.0 if chasing else 28.0) if is_in_water else (35.0 if chasing else 22.0),
				"is_water": is_in_water
			})
			step_taken.emit(global_position, chasing, is_wall_occluded)


func _move_toward(dest: Vector2, speed: float, delta: float) -> bool:
	var to_dest := dest - global_position
	var dist := to_dest.length()
	if dist < ARRIVE_DIST:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		return true
	var dir := to_dest.normalized()

	# Whisker obstacle avoidance so monsters steer around corners instead of grinding head-first into walls
	var space := get_world_2d().direct_space_state
	var feel_dist := 26.0
	var q := _get_ray_query()
	q.from = global_position
	q.to = global_position + dir * feel_dist
	var hit_fwd: Dictionary = space.intersect_ray(q)
	if not hit_fwd.is_empty():
		var left_dir := dir.rotated(-0.65)
		var right_dir := dir.rotated(0.65)
		q.to = global_position + left_dir * feel_dist
		var hit_l: Dictionary = space.intersect_ray(q)
		q.to = global_position + right_dir * feel_dist
		var hit_r: Dictionary = space.intersect_ray(q)
		if hit_l.is_empty() and not hit_r.is_empty():
			dir = left_dir
		elif hit_r.is_empty() and not hit_l.is_empty():
			dir = right_dir
		else:
			var wide_l := dir.rotated(-1.20)
			var wide_r := dir.rotated(1.20)
			q.to = global_position + wide_l * feel_dist
			var hw_l: Dictionary = space.intersect_ray(q)
			q.to = global_position + wide_r * feel_dist
			var hw_r: Dictionary = space.intersect_ray(q)
			if hw_l.is_empty() and not hw_r.is_empty():
				dir = wide_l
			elif hw_r.is_empty() and not hw_l.is_empty():
				dir = wide_r
			else:
				var n: Vector2 = hit_fwd.normal
				var slide := dir.slide(n)
				if slide.length() > 0.2:
					dir = slide.normalized()
				else:
					dir = n.orthogonal()

	# Slide smoothly along walls on physical contact
	if get_slide_collision_count() > 0:
		var col := get_slide_collision(0)
		if col != null:
			var normal := col.get_normal()
			if dir.dot(normal) < -0.05:
				var slide_dir := dir.slide(normal)
				if slide_dir.length() > 0.2:
					dir = slide_dir.normalized()
				else:
					dir = normal.orthogonal()

	# Smooth acceleration & deceleration near destination
	var slow_factor := clampf(dist / 24.0, 0.35, 1.0)
	var desired_vel := dir * (speed * slow_factor)
	var accel := 950.0 if state == State.INVESTIGATE else 620.0
	velocity = velocity.move_toward(desired_vel, accel * delta)
	return false


func _on_catch(body: Node) -> void:
	var main := get_tree().current_scene
	if main != null and is_instance_valid(main) and main.get("_changing") == true:
		return
	if is_wall_occluded:
		return
	if body.is_in_group("player") and body.has_method("die"):
		if enemy_type == EnemyType.LISTENER and state != State.ALARM:
			_handle_listener_sound(true)
			if body.has_method("apply_slow"):
				body.apply_slow(3.0, 0.45)
			if state != State.ALARM:
				var push_dir: Vector2 = (body.global_position - global_position).normalized()
				if push_dir.is_zero_approx():
					push_dir = Vector2.DOWN
				body.set("moving", false)
				body.set("velocity", push_dir * 220.0)
				if body.has_method("camera_shake"):
					body.camera_shake(0.22, 4.5)
				return
		body.die(int(enemy_type))


func reveal(amount: float = 1.0) -> void:
	if visible_alpha < 0.12 and amount > 0.15:
		spasm_timer = 0.16
		spasm_offset = Vector2(randf_range(-3.2, 3.2), randf_range(-3.2, 3.2))
	visible_alpha = clampf(visible_alpha + amount, 0.0, 1.0)
	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_acoustic_amplifier"):
		eye_linger_timer = 4.0
		visible_alpha = 1.0
	else:
		eye_linger_timer = 0.45
