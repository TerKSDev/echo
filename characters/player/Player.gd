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
const STEP_INTERVAL_WALK := 0.5
const STEP_INTERVAL_SNEAK := 0.8

# Voice Sound
const CHARGE_TIME := 0.8
const MIN_LOUDNESS := 0.3
const MAX_LOUDNESS := 0.6
const CLICK_MIC_IGNORE_TIME := 0.3 # Ignore mic right after a click (the click noise itself)

const TRAIL_LENGTH := 12

# Nodes
@onready var mic: MicInput = $MicInput
@onready var trail: Line2D = $TrailLine
@onready var camera: Camera2D = $PlayerCamera

# Player States
var alive := true
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

func _ready() -> void:
	add_to_group("player")
	trail.top_level = true
	trail.global_position = Vector2.ZERO
	mic.voice_detected.connect(make_voice_sound)
	mic.start()

# Handle Player Input
func _unhandled_input(event: InputEvent) -> void:
	# Ignore input if the player is dead
	if not alive:
		return
	
	# Handle touch input (on mobile)
	var pressed_pos = null
	if event is InputEventScreenTouch and event.pressed:
		pressed_pos = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed_pos = get_global_mouse_position()
	
	# Move the player to the pressed position
	if pressed_pos != null:
		print("move to: ", pressed_pos)
		target = pressed_pos
		moving = true
		click_cooldown = CLICK_MIC_IGNORE_TIME
	
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

	# Stop moving after hitting the wall
	if moving and get_slide_collision_count() > 0 and velocity.length() < 5.0:
		moving = false
		desired = Vector2.ZERO
		velocity = Vector2.ZERO
	
	# Step sound
	if velocity.length() > 1.0:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = STEP_INTERVAL_SNEAK if sneaking else STEP_INTERVAL_WALK
			make_sound(STEP_LOUDNESS_SNEAK if sneaking else STEP_LOUDNESS_WALK)
	else:
		step_timer = 0.0
	
	# Voice charging
	if charging:
		charge = min(charge + delta / CHARGE_TIME, 1.0)
		if charge >= 1.0 and not was_full:
			was_full = true
			full_charge = 1.0
			Input.vibrate_handheld(40)
	full_charge = move_toward(full_charge, 0.0, delta * 4.0)

	# Ignore mic right after a click for a short time
	click_cooldown = maxf(click_cooldown - delta, 0.0)

	_update_trail()
	queue_redraw()

func make_voice_sound(k: float):
	# The click itself can be picked up by the mic, so ignore it
	if click_cooldown > 0.0:
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

	if loudness > STEP_LOUDNESS_WALK:
		var tween := create_tween()
		pulse_scale = 1.0 + loudness * 0.8
		tween.tween_property(self, "pulse_scale", 1.0, 0.25).set_ease(Tween.EASE_OUT)

# Handle Sneak Toggle
func toggle_sneak():
	sneaking = not sneaking
	sneak_toggled.emit(sneaking)

# Handle Voice Charging
func start_charge():
	if not alive:
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
func die() -> void:
	# Ignore death if the player is already dead
	if not alive:
		return
	
	# Stop all movement and actions
	alive = false
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
	if camera != null:
		camera.offset = Vector2.ZERO
	trail.clear_points()
	queue_redraw()
	modulate = Color.WHITE

# Handle Player Drawing
func _draw() -> void:
	# Ignore drawing if the player is dead, show death collapse effect
	if not alive:
		if _death_alpha > 0.01:
			var spread: float = (1.0 - _death_alpha) * 45.0
			draw_circle(Vector2.ZERO, spread + 15.0, Color(1.0, 0.2, 0.2, 0.35 * _death_alpha))
			draw_circle(Vector2.ZERO, spread + 6.0, Color(1.0, 0.7, 0.7, 0.7 * _death_alpha))
		return

	var t := Time.get_ticks_msec() / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * 2.8)

	if sneaking:
		# --- Sneak Mode: Condensed acoustic dampener core ---
		# Subtle focused dampener ring
		draw_arc(Vector2.ZERO, 10.0 + 1.2 * breathe, 0.0, TAU, 24, Color(0.2, 0.65, 0.85, 0.35), 1.5)
		# Concentrated silent core
		draw_circle(Vector2.ZERO, 5.0 * pulse_scale, Color(0.3, 0.8, 1.0, 0.55))
		draw_circle(Vector2.ZERO, 2.5 * pulse_scale, Color(0.8, 0.95, 1.0, 0.8))
	else:
		# --- Normal Mode: Radiant bioluminescent acoustic core ---
		# Outer ambient breathing glow
		draw_circle(Vector2.ZERO, 20.0 + 3.0 * breathe, Color(0.15, 0.6, 0.9, 0.08))
		# Inner soft aura
		draw_circle(Vector2.ZERO, 13.0 + 1.5 * breathe, Color(0.25, 0.8, 1.0, 0.18))
		# Main body core
		draw_circle(Vector2.ZERO, 7.5 * pulse_scale, Color(0.3, 0.92, 1.0, 0.95))
		# Hot white center
		draw_circle(Vector2.ZERO, 3.5 * pulse_scale, Color(0.9, 0.98, 1.0, 1.0))

		# Directional sonar heading cue when moving
		if velocity.length() > 10.0:
			var heading := velocity.normalized()
			var tip := heading * (13.0 + 2.0 * breathe)
			var left_wing := heading.rotated(2.4) * 8.0
			var right_wing := heading.rotated(-2.4) * 8.0
			draw_line(tip, tip + left_wing, Color(0.4, 0.9, 1.0, 0.45), 1.5)
			draw_line(tip, tip + right_wing, Color(0.4, 0.9, 1.0, 0.45), 1.5)

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

	# Target marker (when tap to move)
	if marker > 0.01:
		var p := to_local(target)
		var p_pulse := 1.0 + 0.15 * sin(t * 8.0)
		draw_arc(p, 10.0 * p_pulse, 0.0, TAU, 24, Color(0.3, 1.0, 1.0, 0.5 * marker), 2.0)
		draw_circle(p, 2.0, Color(0.8, 1.0, 1.0, 0.7 * marker))
