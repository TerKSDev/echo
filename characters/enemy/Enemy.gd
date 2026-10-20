extends CharacterBody2D
class_name Enemy

# Signals
signal woke_up(pos: Vector2)

enum State {
	SLEEP,
	PATROL,
	ALERT,
	INVESTIGATE,
	SEARCH,
	RETURN
}

# Enemy Properties
@export var init_state: State = State.SLEEP
@export var patrol_points: Array[Vector2] = []
@export var hearing_threshold := 0.07 
@export var patrol_speed := 70.0
@export var chase_speed := 180.0
@export var sense_radius := 90.0
@export var sneak_sense_radius := 60.0
@export var sleep_wake_radius := 75.0 

# Enemy Timers
const ALERT_TIME := 0.4
const SEARCH_TIME := 3.0
const SEARCH_RADIUS := 80.0
const INVESTIGATE_TIMEOUT := 6.0
const ARRIVE_DIST := 10.0

# Visual Feedback
const WARN_RADIUS := 150.0 
const STATE_FLASH := {
	State.SLEEP: 0.3,
	State.PATROL: 0.3,
	State.ALERT: 1.0,
	State.INVESTIGATE: 0.6,
	State.SEARCH: 0.6,
	State.RETURN: 0.5,
}

# Enemy States
var state: State = State.SLEEP
var home: Vector2
var target: Vector2
var search_point: Vector2
var timer := 0.0
var patrol_idx := 0
var visible_alpha := 0.0
var proximity := 0.0
var _trail_points: Array[Vector2] = []

func _ready() -> void:
	add_to_group("enemy")
	home = global_position
	_collect_patrol_points()
	state = init_state

	if state == State.PATROL and patrol_points.size() < 2:
		push_warning("%s Enemy is set to patrol but has fewer than 2 patrol points. Switching to SLEEP state." % name)
		state = State.SLEEP

	$CatchArea.body_entered.connect(_on_catch)

# Patrol Points
func _collect_patrol_points() -> void:
	var path := get_node_or_null("Path")
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

# Sound Detection
func on_sound(pos: Vector2, loudness: float, radius: float) -> void:
	var dist := global_position.distance_to(pos)
	if dist > radius:
		return

	var attenuation := 1.0 - (dist / radius)
	var heard := loudness * attenuation
	if heard < hearing_threshold:
		return

	_notice(pos)

# Player Detection
func _notice(pos: Vector2) -> void:
	target = pos
	match state:
		State.SLEEP, State.PATROL, State.RETURN:
			_enter(State.ALERT) # Flashes visible so the player knows they were noticed
			woke_up.emit(global_position)
		State.INVESTIGATE, State.SEARCH:
			_enter(State.INVESTIGATE)
		State.ALERT:
			pass

# State Manager
func _enter(s: State) -> void:
	var changed := s != state
	state = s
	timer = 0.0
	if s == State.SEARCH:
		search_point = _random_search_point()
	if changed:
		reveal(float(STATE_FLASH.get(s, 0.0)))

# Movement and AI
func _random_search_point() -> Vector2:
	return target + Vector2.from_angle(randf() * TAU) * randf_range(30.0, SEARCH_RADIUS)

# Return Player Node
func _get_player() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.alive:
		return null
	return player

# Player Detection
func _sense_player() -> void:
	if state == State.ALERT:
		return
	var player := _get_player()
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if state == State.SLEEP:
		if dist <= sleep_wake_radius:
			_notice(player.global_position)
		return
	
	var radius: float = sneak_sense_radius if player.sneaking else sense_radius
	if dist <= radius:
		_notice(player.global_position)

# Proximity and Threat Level
func _update_proximity() -> void:
	proximity = 0.0
	var player := _get_player()
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	proximity = clampf(1.0 - dist / WARN_RADIUS, 0.0, 1.0)

# Treat Level
func get_threat_level(player_pos: Vector2) -> float:
	match state:
		State.ALERT, State.INVESTIGATE:
			return 1.0
		State.SEARCH:
			var dist := global_position.distance_to(player_pos)
			return clampf(maxf(0.5, 1.0 - dist / 250.0), 0.0, 1.0)
		State.PATROL, State.RETURN:
			var dist := global_position.distance_to(player_pos)
			return clampf(1.0 - dist / 220.0, 0.0, 1.0)
		State.SLEEP:
			var dist := global_position.distance_to(player_pos)
			return clampf(inverse_lerp(180.0, sleep_wake_radius, dist), 0.0, 0.95)
	return 0.0

# Physics and Movement
func _physics_process(delta: float) -> void:
	timer += delta
	visible_alpha = move_toward(visible_alpha, 0.0, delta * 0.8)
	_sense_player()

	match state:
		State.SLEEP:
			velocity = Vector2.ZERO
		State.PATROL:
			_do_patrol()
		State.ALERT:
			velocity = Vector2.ZERO
			if timer >= ALERT_TIME:
				_enter(State.INVESTIGATE)
		State.INVESTIGATE:
			if _move_toward(target, chase_speed) or timer >= INVESTIGATE_TIMEOUT:
				velocity = Vector2.ZERO
				_enter(State.SEARCH)
		State.SEARCH:
			# Wander around the sound source instead of standing still
			if _move_toward(search_point, patrol_speed):
				search_point = _random_search_point()
			if timer >= SEARCH_TIME:
				_enter(State.RETURN)
		State.RETURN:
			var dest := _home_target()
			if _move_toward(dest, patrol_speed):
				_enter(State.PATROL if patrol_points.size() > 1 else State.SLEEP)
	
	move_and_slide()

	# Record phantom trail during chase
	if state == State.INVESTIGATE and velocity.length() > 20.0:
		_trail_points.push_front(global_position)
		if _trail_points.size() > 8:
			_trail_points.pop_back()
	elif _trail_points.size() > 0:
		_trail_points.pop_back()

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
	if _move_toward(patrol_points[patrol_idx], patrol_speed):
		patrol_idx = (patrol_idx + 1) % patrol_points.size()

# Player Capture
func _on_catch(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()

func reveal(amount: float = 1.0) -> void:
	visible_alpha = clampf(visible_alpha + amount, 0.0, 1.0)

# One color per state so the player can read what the enemy is doing
func _state_color() -> Color:
	match state:
		State.SLEEP:
			return Color(0.6, 0.4, 1.0) # purple
		State.PATROL:
			return Color(1.0, 0.85, 0.3) # yellow
		State.ALERT:
			return Color(1.0, 1.0, 1.0) # white
		State.INVESTIGATE:
			return Color(1.0, 0.3, 0.3) # red
		State.SEARCH:
			return Color(1.0, 0.6, 0.2) # orange
		State.RETURN:
			return Color(0.4, 0.6, 1.0) # blue
	return Color.WHITE

func _draw() -> void:
	var base := _state_color()
	var t := Time.get_ticks_msec() / 1000.0

	# 1. Proximity biological breathing aura & warning ring
	if proximity > 0.0:
		var beat := 0.5 + 0.5 * sin(t * (4.0 + 10.0 * proximity))
		# Pulsing bio-sonar warning ring
		draw_arc(Vector2.ZERO, 20.0 + 8.0 * beat * proximity, 0.0, TAU, 32, Color(base, 0.15 + 0.5 * proximity), 2.0)
		
		# Eerie slumbering core aura when in sleep
		if state == State.SLEEP:
			var breathe := 0.5 + 0.5 * sin(t * 1.8)
			draw_circle(Vector2.ZERO, 15.0 + 3.0 * breathe, Color(0.45, 0.2, 0.8, 0.15 * proximity))
			draw_circle(Vector2.ZERO, 6.0, Color(0.6, 0.3, 0.95, 0.35 * proximity))

	# 2. Phantom shadow trail during INVESTIGATE / chase
	if state == State.INVESTIGATE and _trail_points.size() > 0:
		for i in range(_trail_points.size()):
			var p := to_local(_trail_points[i])
			var frac := 1.0 - float(i) / _trail_points.size()
			draw_circle(p, (10.0 - i * 0.9), Color(1.0, 0.15, 0.15, 0.28 * frac * maxf(visible_alpha, 0.5)))

	if visible_alpha < 0.02 and state != State.ALERT:
		return

	var color := Color(base, visible_alpha)

	# 3. State-specific visual manifestation
	match state:
		State.SLEEP:
			draw_circle(Vector2.ZERO, 12.0, Color(base, 0.6 * visible_alpha))
			draw_line(Vector2(-9, 0), Vector2(9, 0), Color(0.2, 0.05, 0.35, visible_alpha), 2.5)

		State.ALERT:
			# --- Awakened Demonic Eye & Shock Spikes (Replaces generic "!") ---
			var eye_alpha := maxf(visible_alpha, 0.8)
			# Upper & Lower Eye Eyelids
			draw_arc(Vector2(0, 11), 15.0, -PI * 0.72, -PI * 0.28, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
			draw_arc(Vector2(0, -11), 15.0, PI * 0.28, PI * 0.72, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
			# Demonic Crimson Slit Pupil
			draw_line(Vector2(0, -8), Vector2(0, 8), Color(1.0, 0.1, 0.1, eye_alpha), 3.0)
			draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.9, 0.9, eye_alpha))
			# Radial alarm acoustic spikes
			for i in range(6):
				var ang := i * TAU / 6.0 + t * 5.0
				var p1 := Vector2.from_angle(ang) * 16.0
				var p2 := Vector2.from_angle(ang) * (25.0 + 4.0 * sin(t * 22.0))
				draw_line(p1, p2, Color(1.0, 0.2, 0.2, 0.9 * eye_alpha), 2.0)

		State.INVESTIGATE:
			# --- Crimson Hunting Core with Jagged Corona ---
			var hunt_pulse := 14.0 + 3.0 * sin(t * 16.0)
			draw_arc(Vector2.ZERO, hunt_pulse, 0.0, TAU, 24, Color(1.0, 0.2, 0.2, 0.75 * visible_alpha), 2.0)
			draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.15, 0.15, visible_alpha))
			draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.9, 0.9, visible_alpha))

		State.SEARCH:
			# --- Sonar Sweep Waves searching for player ---
			var sweep_r := fmod(timer * 50.0, SEARCH_RADIUS)
			var sweep_a := 1.0 - (sweep_r / SEARCH_RADIUS)
			draw_arc(Vector2.ZERO, sweep_r, 0.0, TAU, 32, Color(1.0, 0.6, 0.2, 0.65 * sweep_a * visible_alpha), 1.6)
			draw_circle(Vector2.ZERO, 11.0, Color(1.0, 0.55, 0.15, visible_alpha))
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.95, 0.8, visible_alpha))

		State.PATROL, State.RETURN:
			# --- Bio-sentinel glowing orb ---
			draw_circle(Vector2.ZERO, 11.0, color)
			draw_circle(Vector2.ZERO, 4.5, Color(Color.WHITE, visible_alpha))
			draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 24, Color(base, 0.45 * visible_alpha), 1.5)
