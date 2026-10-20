extends CharacterBody2D

# Signals
signal sound_emitted(pos: Vector2, loudness: float, is_voice: bool)
signal died
signal sneak_toggled(sneaking: bool)

# Movement
const WALK_SPEED := 190.0
const SNEAK_SPEED := 100.0
const ARRIVE_DIST := 8.0
const ACCEL := 900.0
const FRICTION := 1200.0

# Step Sound
const STEP_LOUDNESS_WALK := 0.22
const STEP_LOUDNESS_SNEAK := 0.03
const STEP_INTERVAL_WALK := 0.62
const STEP_INTERVAL_SNEAK := 0.98

# Voice Sound
const CHARGE_TIME := 0.8
const MIN_LOUDNESS := 0.3
const MAX_LOUDNESS := 0.6
const CLICK_MIC_IGNORE_TIME := 0.3 # Ignore mic right after a click (the click noise itself)

const TRAIL_LENGTH := 12
const IDLE_ZOOM_DELAY := 1.8   # Seconds of standing still before camera drifts in
const IDLE_ZOOM_LEVEL := 1.42  # Gentle focus zoom when idle (1.0 = normal view)
const ENTRY_ZOOM_LEVEL := 2.35 # Initial close-up zoom on level entry

# Nodes
@onready var mic: MicInput = $MicInput
@onready var trail: Line2D = $TrailLine
@onready var camera: Camera2D = $PlayerCamera

# Player States
var alive := true
var killed_by_type := -1
var target := Vector2.ZERO
var desired := Vector2.ZERO
var marker := 0.0
var moving := false
var sneaking := false
var step_timer := 0.0
var charging := false
var charge := 0.0
var pulse_scale := 1.0
var was_full := false
var full_charge := 0.0
var click_cooldown := 0.0

# Visual Enhancements
var _burst_radius := 0.0
var _burst_alpha := 0.0
var _death_alpha := 0.0
var _shake_timer := 0.0
var _shake_intensity := 0.0
var _stun_timer := 0.0
var _idle_timer := 0.0
var _entry_timer := 1.2 # Prevents idle zoom during the initial level entry pull-back
var _sneak_blend := 0.0 # Smooth 0..1 transition between normal and sneak visual state
var _step_ripples: Array[Dictionary] = [] # World-space micro-ripples under footsteps
var _tap_flash := 0.0 # Crisp ripple animation at destination marker when tapped
var _wall_bump_pos := Vector2.ZERO
var _wall_bump_normal := Vector2.UP
var _wall_bump_alpha := 0.0

# Shake Camera
func camera_shake(duration: float = 0.4, intensity: float = 8.0) -> void:
	_shake_timer = maxf(_shake_timer, duration)
	_shake_intensity = maxf(_shake_intensity, intensity)

# Immobilize / Stun player (e.g. hit by Screamer sonic shriek)
func immobilize(duration: float = 1.6) -> void:
	if not alive:
		return
	_stun_timer = maxf(_stun_timer, duration)
	moving = false
	charging = false
	charge = 0.0
	was_full = false
	marker = 0.0
	desired = Vector2.ZERO
	velocity = Vector2.ZERO
	camera_shake(0.35, 8.0)
	Input.vibrate_handheld(80)
	queue_redraw()

func _ready() -> void:
	add_to_group("player")
	trail.top_level = true
	trail.global_position = Vector2.ZERO
	if camera != null:
		camera.zoom = Vector2(ENTRY_ZOOM_LEVEL, ENTRY_ZOOM_LEVEL)
	mic.voice_detected.connect(make_voice_sound)
	mic.start()

# Handle Player Input
func _unhandled_input(event: InputEvent) -> void:
	# Ignore input if the player is dead or immobilized
	if not alive or _stun_timer > 0.0:
		return
	
	# Handle touch / mouse tap & drag steering
	var pressed_pos = null
	var is_new_tap := false
	if event is InputEventScreenTouch and event.pressed:
		pressed_pos = get_canvas_transform().affine_inverse() * event.position
		is_new_tap = true
	elif event is InputEventScreenDrag:
		pressed_pos = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed_pos = get_global_mouse_position()
		is_new_tap = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pressed_pos = get_global_mouse_position()
	
	# Move the player to the pressed/dragged position
	if pressed_pos != null:
		target = pressed_pos
		moving = true
		if is_new_tap:
			_tap_flash = 1.0
		if event is InputEventScreenTouch and OS.get_name() == "Android" and mic != null:
			mic.suppress_timer = 0.08
	
	# Handle keyboard input (on desktop)
	if event.is_action_pressed("ui_accept"):
		start_charge()
	elif event.is_action_released("ui_accept"):
		release_charge()
	
	# Handle sneaking toggle with Shift key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		toggle_sneak()

# Handle Logic for Each Physics Frame
func _physics_process(delta: float) -> void:
	# Camera shake decay
	if _shake_timer > 0.0:
		_shake_timer -= delta
		if camera != null:
			camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_intensity
			_shake_intensity = move_toward(_shake_intensity, 0.0, delta * 35.0)
			if _shake_timer <= 0.0:
				camera.offset = Vector2.ZERO

	# Sound burst shockwave expansion
	if _burst_alpha > 0.0:
		_burst_radius += delta * 180.0
		_burst_alpha = move_toward(_burst_alpha, 0.0, delta * 2.8)

	# Handle death decay animation
	if not alive:
		if _death_alpha > 0.0:
			_death_alpha = move_toward(_death_alpha, 0.0, delta * 1.5)
			queue_redraw()
		return

	# Handle immobilization / stun
	if _stun_timer > 0.0:
		_stun_timer -= delta
		moving = false
		desired = Vector2.ZERO
		var sfx_stun := get_node_or_null("../SfxManager") as SfxManager
		if sfx_stun != null:
			sfx_stun.update_charge_hum(false, 0.0)
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		move_and_slide()
		_update_trail()
		queue_redraw()
		return

	# Handle movement
	var speed: float = SNEAK_SPEED if sneaking else WALK_SPEED
	if moving:
		marker = move_toward(marker, 1.0, delta * 8.0)
		var to_target: Vector2 = target - global_position
		var dist: float = to_target.length()
		
		if dist <= 2.0 or (velocity.length() * delta >= dist and velocity.dot(to_target) > 0):
			global_position = target
			velocity = Vector2.ZERO
			desired = Vector2.ZERO
			moving = false
		else:
			var slow_dist: float = (speed * speed) / (2.0 * FRICTION)
			var target_speed: float = speed * clampf(dist / slow_dist, 0.15, 1.0)
			desired = to_target.normalized() * target_speed
	else:
		marker = move_toward(marker, 0.0, delta * 2.0)
		desired = Vector2.ZERO
	
	# Update velocity
	var rate = ACCEL if desired != Vector2.ZERO else FRICTION
	velocity = velocity.move_toward(desired, rate * delta)
	move_and_slide()

	# Stop moving after hitting the wall, and give a tactile wall-contact spark in the dark
	if get_slide_collision_count() > 0:
		var col := get_slide_collision(0)
		if col != null and _wall_bump_alpha < 0.25 and velocity.length() < 45.0:
			_wall_bump_pos = col.get_position()
			_wall_bump_normal = col.get_normal()
			_wall_bump_alpha = 0.85
		if moving and velocity.length() < 5.0:
			moving = false
			desired = Vector2.ZERO
			velocity = Vector2.ZERO
			camera_shake(0.08, 1.2)
	
	# Step sound (decay smoothly when idle instead of hard-resetting to 0 so micro-taps don't machine-gun steps)
	if velocity.length() > 1.0:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = STEP_INTERVAL_SNEAK if sneaking else STEP_INTERVAL_WALK
			make_sound(STEP_LOUDNESS_SNEAK if sneaking else STEP_LOUDNESS_WALK)
	else:
		step_timer = maxf(step_timer - delta * 0.5, 0.16)
	
	# Voice charging
	if charging:
		charge = min(charge + delta / CHARGE_TIME, 1.0)
		if charge >= 1.0 and not was_full:
			was_full = true
			full_charge = 1.0
			Input.vibrate_handheld(40)
			var sfx_node := get_node_or_null("../SfxManager") as SfxManager
			if sfx_node != null:
				sfx_node.play_charge_full()
	var sfx_mgr := get_node_or_null("../SfxManager") as SfxManager
	if sfx_mgr != null:
		sfx_mgr.update_charge_hum(charging, charge)
	full_charge = move_toward(full_charge, 0.0, delta * 4.0)

	# Ignore mic right after a click for a short time
	click_cooldown = maxf(click_cooldown - delta, 0.0)

	# Smooth sneak transition, tap flash, wall contact spark, and world-space footstep ripples
	_sneak_blend = move_toward(_sneak_blend, 1.0 if sneaking else 0.0, delta * 8.0)
	_tap_flash = move_toward(_tap_flash, 0.0, delta * 3.2)
	_wall_bump_alpha = move_toward(_wall_bump_alpha, 0.0, delta * 2.8)
	var alive_ripples: Array[Dictionary] = []
	for r: Dictionary in _step_ripples:
		var next_age: float = float(r["age"]) + delta
		if next_age < 0.65:
			r["age"] = next_age
			alive_ripples.append(r)
	_step_ripples = alive_ripples

	# Dynamic camera zoom: initial pull-back on entry, gentle zoom-in when idle, wide view when active
	if _entry_timer > 0.0:
		_entry_timer = maxf(0.0, _entry_timer - delta)
	var is_active: bool = moving or velocity.length() > 5.0 or charging or _burst_alpha > 0.15
	if is_active or _entry_timer > 0.0:
		_idle_timer = 0.0
	else:
		_idle_timer += delta

	if camera != null:
		var target_z: float = IDLE_ZOOM_LEVEL if (_idle_timer >= IDLE_ZOOM_DELAY) else 1.0
		if charging:
			target_z -= 0.06 * charge # Subtle camera pull-back tension while charging
		var zoom_speed: float = 0.75 if (_idle_timer >= IDLE_ZOOM_DELAY) else 2.6
		var cur_z: float = lerpf(camera.zoom.x, target_z, clampf(delta * zoom_speed, 0.0, 1.0))
		camera.zoom = Vector2(cur_z, cur_z)

	_update_trail()
	queue_redraw()

func make_voice_sound(k: float):
	# Ignore mic while dead or stunned
	if not alive or _stun_timer > 0.0:
		return
	make_sound(lerpf(MIN_LOUDNESS, MAX_LOUDNESS, k), true)

# Handle Vocalize
func make_sound(loudness: float, is_voice := false) -> void:
	# Ignore sound if the player is dead
	if not alive:
		return

	# Emit the sound signal
	sound_emitted.emit(global_position, loudness, is_voice)

	# Trigger acoustic burst ring on the player core
	_burst_radius = 8.0
	_burst_alpha = clampf(loudness * 2.0, 0.4, 1.0)

	if is_voice:
		camera_shake(0.16, lerpf(1.4, 4.2, clampf(loudness, 0.0, 1.0)))
		var tween := create_tween()
		pulse_scale = 1.0 + loudness * 0.8
		tween.tween_property(self, "pulse_scale", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	else:
		_step_ripples.append({
			"pos": global_position,
			"age": 0.0,
			"max_r": 16.0 if sneaking else 30.0,
			"alpha": 0.24 if sneaking else 0.46
		})
		var step_tw := create_tween()
		pulse_scale = 1.05 if sneaking else 1.13
		step_tw.tween_property(self, "pulse_scale", 1.0, 0.18).set_ease(Tween.EASE_OUT)

# Handle Sneak Toggle
func toggle_sneak():
	if not alive or _stun_timer > 0.0:
		return
	sneaking = not sneaking
	var sfx_node := get_node_or_null("../SfxManager") as SfxManager
	if sfx_node != null:
		sfx_node.play_sneak_toggle(sneaking)
	sneak_toggled.emit(sneaking)

# Handle Voice Charging
func start_charge():
	if not alive or _stun_timer > 0.0:
		return
	charging = true
	charge = 0.0
	was_full = false

# Handle Voice Release
func release_charge():
	if not charging:
		return
	charging = false
	var loudness := lerpf(MIN_LOUDNESS, MAX_LOUDNESS, charge)
	make_sound(loudness, true)

	if loudness > 0.5:
		Input.vibrate_handheld(int(30 + loudness * 50))
	charge = 0.0

# Handle Trail Effect
func _update_trail() -> void:
	if velocity.length() > 5.0:
		trail.add_point(global_position)
	elif trail.get_point_count() > 0:
		trail.remove_point(0)

	while trail.get_point_count() > TRAIL_LENGTH:
		trail.remove_point(0)
	trail.modulate.a = 0.15 if sneaking else 0.5

# Handle Player Death
func die(killer_type: int = -1) -> void:
	# Ignore death if the player is already dead
	if not alive:
		return
	
	# Stop all movement and actions
	alive = false
	killed_by_type = killer_type
	moving = false
	charging = false
	velocity = Vector2.ZERO
	_shake_timer = 0.45
	_shake_intensity = 16.0
	_death_alpha = 1.0
	Input.vibrate_handheld(150)
	died.emit()
	queue_redraw()

# Handle Player State Reset
func reset(pos: Vector2) -> void:
	alive = true
	killed_by_type = -1
	global_position = pos
	velocity = Vector2.ZERO
	moving = false
	charging = false
	charge = 0.0
	full_charge = 0.0
	sneaking = false
	sneak_toggled.emit(false)
	pulse_scale = 1.0
	was_full = false
	_burst_alpha = 0.0
	_death_alpha = 0.0
	_shake_timer = 0.0
	_shake_intensity = 0.0
	_stun_timer = 0.0
	_idle_timer = 0.0
	_entry_timer = 1.2
	_sneak_blend = 0.0
	_tap_flash = 0.0
	_wall_bump_alpha = 0.0
	_step_ripples.clear()
	if camera != null:
		camera.offset = Vector2.ZERO
		camera.zoom = Vector2(ENTRY_ZOOM_LEVEL, ENTRY_ZOOM_LEVEL)
	trail.clear_points()
	queue_redraw()
	modulate = Color.WHITE

# Handle Player Drawing
func _draw() -> void:
	# Draw world-space footstep water ripples first (underneath player core)
	for r: Dictionary in _step_ripples:
		var age: float = float(r["age"])
		var p_ratio: float = clampf(age / 0.65, 0.0, 1.0)
		var ease_p: float = 1.0 - pow(1.0 - p_ratio, 2.2)
		var rad: float = lerpf(3.0, float(r["max_r"]), ease_p)
		var a: float = float(r["alpha"]) * (1.0 - p_ratio)
		var local_pos: Vector2 = to_local(Vector2(r["pos"]))
		draw_arc(local_pos, rad, 0.0, TAU, 24, Color(0.32, 0.86, 1.0, a), 1.4)
		if p_ratio < 0.45:
			draw_arc(local_pos, rad * 0.55, 0.0, TAU, 18, Color(0.55, 0.95, 1.0, a * 0.55), 1.0)

	# Ignore drawing if the player is dead, show death collapse effect
	if not alive:
		if _death_alpha > 0.01:
			var spread: float = (1.0 - _death_alpha) * 45.0
			draw_circle(Vector2.ZERO, spread + 15.0, Color(1.0, 0.2, 0.2, 0.35 * _death_alpha))
			draw_circle(Vector2.ZERO, spread + 6.0, Color(1.0, 0.7, 0.7, 0.7 * _death_alpha))
		return

	var t := Time.get_ticks_msec() / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * 2.8)
	var sb: float = _sneak_blend

	# Subtle high-frequency core vibration when holding a high voice charge
	var core_ofs := Vector2.ZERO
	if charging and charge > 0.25:
		var jitter: float = (charge - 0.25) * 1.8
		core_ofs = Vector2(sin(t * 55.0), cos(t * 49.0)) * jitter

	# Smoothly blended Normal <-> Sneak bioluminescent core
	if sb < 0.99:
		var norm_a: float = 1.0 - sb
		# Outer ambient breathing glow
		draw_circle(core_ofs, (20.0 + 3.0 * breathe) * lerpf(1.0, 0.65, sb), Color(0.15, 0.6, 0.9, 0.08 * norm_a))
		# Inner soft aura
		draw_circle(core_ofs, (13.0 + 1.5 * breathe) * lerpf(1.0, 0.75, sb), Color(0.25, 0.8, 1.0, 0.18 * norm_a))

	if sb > 0.01:
		# Subtle focused dampener ring in Sneak mode
		var ring_r: float = lerpf(14.0, 10.0 + 1.2 * breathe, sb)
		draw_arc(core_ofs, ring_r, 0.0, TAU, 24, Color(0.2, 0.65, 0.85, 0.38 * sb), 1.5)

	# Main body core & hot center (smoothly interpolated size and opacity)
	var body_r: float = lerpf(7.5, 5.0, sb) * pulse_scale
	var body_a: float = lerpf(0.95, 0.58, sb)
	draw_circle(core_ofs, body_r, Color(0.3, lerpf(0.92, 0.8, sb), 1.0, body_a))

	var center_r: float = lerpf(3.5, 2.5, sb) * pulse_scale
	var center_a: float = lerpf(1.0, 0.82, sb)
	draw_circle(core_ofs, center_r, Color(0.88, 0.97, 1.0, center_a))

	# Directional sonar heading cue when moving
	if velocity.length() > 10.0:
		var heading := velocity.normalized()
		var cue_scale: float = lerpf(1.0, 0.75, sb)
		var cue_alpha: float = lerpf(0.45, 0.24, sb)
		var tip := core_ofs + heading * (13.0 + 2.0 * breathe) * cue_scale
		var left_wing := heading.rotated(2.4) * (8.0 * cue_scale)
		var right_wing := heading.rotated(-2.4) * (8.0 * cue_scale)
		draw_line(tip, tip + left_wing, Color(0.4, 0.9, 1.0, cue_alpha), 1.5)
		draw_line(tip, tip + right_wing, Color(0.4, 0.9, 1.0, cue_alpha), 1.5)

	# Sound emission burst shockwave
	if _burst_alpha > 0.01:
		draw_arc(Vector2.ZERO, _burst_radius, 0.0, TAU, 32, Color(0.6, 0.95, 1.0, _burst_alpha), 2.0)

	# Charging ring
	if charging:
		var ring_radius := 16.0 + charge * 14.0
		var ring_color := Color(0.35, 0.85, 1.0).lerp(Color.WHITE, charge)
		draw_arc(Vector2.ZERO, ring_radius, -PI / 2, -PI / 2 + TAU * charge, 32, ring_color, 2.0 + charge * 2.0)
		# Spark tip
		var tip_angle := -PI / 2 + TAU * charge
		draw_circle(Vector2(cos(tip_angle), sin(tip_angle)) * ring_radius, 3.0, Color.WHITE)

	if full_charge > 0.01:
		draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 32, Color(1, 1, 1, full_charge), 3.0)

	# Target marker (when tap/drag to move)
	if marker > 0.01:
		var p := to_local(target)
		var p_pulse := 1.0 + 0.15 * sin(t * 8.0)
		draw_arc(p, 9.0 * p_pulse, 0.0, TAU, 24, Color(0.3, 1.0, 1.0, 0.48 * marker), 1.8)
		draw_circle(p, 2.2, Color(0.85, 1.0, 1.0, 0.78 * marker))
		if _tap_flash > 0.01:
			var tap_r: float = lerpf(22.0, 9.0, 1.0 - _tap_flash)
			draw_arc(p, tap_r, 0.0, TAU, 24, Color(0.65, 0.98, 1.0, 0.65 * _tap_flash), 1.4)

	# Tactile wall contact shimmer when brushing/stopping against a wall in darkness
	if _wall_bump_alpha > 0.01:
		var bp := to_local(_wall_bump_pos)
		var tangent := Vector2(-_wall_bump_normal.y, _wall_bump_normal.x)
		var span: float = lerpf(6.0, 15.0, 1.0 - _wall_bump_alpha)
		draw_line(bp - tangent * span, bp + tangent * span, Color(0.45, 0.92, 1.0, 0.75 * _wall_bump_alpha), 2.2)
		draw_circle(bp, 2.5, Color(0.85, 0.98, 1.0, 0.85 * _wall_bump_alpha))

	# Acoustic paralysis / Stun visual feedback
	if _stun_timer > 0.0:
		var stun_pulse := 16.0 + 2.5 * sin(t * 26.0)
		draw_arc(Vector2.ZERO, stun_pulse, 0.0, TAU, 28, Color(1.0, 0.3, 0.5, 0.85), 2.0)
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.15, 0.3, 0.35))
		for i in 4:
			var ang := i * PI * 0.5 + t * 6.0
			var spark := Vector2.from_angle(ang) * (stun_pulse + 4.0)
			draw_circle(spark, 2.0, Color(1.0, 0.85, 0.9, 0.9))
