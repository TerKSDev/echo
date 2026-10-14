extends CharacterBody2D

signal sound_emitted(pos: Vector2, loudness: float, is_voice: bool)

const WALK_SPEED := 220.0
const SNEAK_SPEED := 90.0
const ARRIVE_DIST := 8.0
const ACCEL := 900.0
const FRICTION := 1200.0
const TRAIL_LENGTH := 12

# Step sound parameters
const STEP_LOUDNESS_WALK := 0.22
const STEP_LOUDNESS_SNEAK := 0.06
const STEP_INTERVAL_WALK := 0.5
const STEP_INTERVAL_SNEAK := 0.8

# Voice sound parameters
const CHARGE_TIME := 0.8
const MIN_LOUDNESS := 0.3
const MAX_LOUDNESS := 1.0

# Movement variables
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

@onready var mic: MicInput = $MicInput
@onready var trail: Line2D = $TrailLine

func _ready():
	trail.top_level = true
	trail.global_position = Vector2.ZERO
	mic.voice_detected.connect(make_voice_sound)
	mic.start()

func make_voice_sound(k: float):
	make_sound(lerpf(MIN_LOUDNESS, MAX_LOUDNESS, k), true)

func _unhandled_input(event):
	# Handle touch input for movement (on mobile)
	var pressed_pos = null
	
	if event is InputEventScreenTouch and event.pressed:
		pressed_pos = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed_pos = get_global_mouse_position()

	if pressed_pos != null:
		print("move to: ", pressed_pos)
		target = pressed_pos
		moving = true

	# Handle keyboard input for movement and actions (on desktop)
	if event.is_action_pressed("ui_accept"):
		start_charge()
	elif event.is_action_released("ui_accept"):
		release_charge()
	
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		toggle_sneak()

func _physics_process(delta):
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
	
	var rate = ACCEL if desired != Vector2.ZERO else FRICTION
	velocity = velocity.move_toward(desired, rate * delta)
	move_and_slide()

	# Handle collision detection
	if moving and get_slide_collision_count() > 0 and velocity.length() < 5.0:
		moving = false
		desired = Vector2.ZERO
		velocity = Vector2.ZERO
	
	# Handle step sound emission
	if velocity.length() > 1.0:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = STEP_INTERVAL_SNEAK if sneaking else STEP_INTERVAL_WALK
			make_sound(STEP_LOUDNESS_SNEAK if sneaking else STEP_LOUDNESS_WALK)
	else:
		step_timer = 0.0
	
	# Handle voice charging and emission
	if charging:
		charge = min(charge + delta / CHARGE_TIME, 1.0)
		if charge >= 1.0 and not was_full:
			was_full = true
			full_charge = 1.0
			Input.vibrate_handheld(40)

	full_charge = move_toward(full_charge, 0.0, delta * 4.0)

	_update_trail()
	queue_redraw()

# Handle voice emission
func make_sound(loudness: float, is_voice := false):
	sound_emitted.emit(global_position, loudness, is_voice)
	if loudness > STEP_LOUDNESS_WALK:
		var tween := create_tween()
		pulse_scale = 1.0 + loudness * 0.8
		tween.tween_property(self, "pulse_scale", 1.0, 0.25).set_ease(Tween.EASE_OUT)

# Toggle sneaking state
func toggle_sneak():
	sneaking = not sneaking

# Start charging the voice sound
func start_charge():
	charging = true
	charge = 0.0
	was_full = false

func release_charge():
	if not charging:
		return
	charging = false
	var loudness := lerpf(MIN_LOUDNESS, MAX_LOUDNESS, charge)
	make_sound(loudness, true)

	if loudness > 0.5:
		Input.vibrate_handheld(int(30 + loudness * 50))
	charge = 0.0

func _update_trail():
	trail.add_point(global_position)
	while trail.get_point_count() > TRAIL_LENGTH:
		trail.remove_point(0)
	trail.modulate.a = 0.15 if sneaking else 0.35

# Simple debug drawing for the player
func _draw():
	var glow := 0.35 if sneaking else 1.0
	draw_circle(Vector2.ZERO, 24.0, Color(0.3, 1.0, 1.0, 0.06 * glow))
	draw_circle(Vector2.ZERO, 16.0, Color(0.3, 1.0, 1.0, 0.12 * glow))

	var color = Color(0.3, 1.0, 1.0, 0.35 if sneaking else 1.0)
	draw_circle(Vector2.ZERO, 8.0 * pulse_scale, color)
	
	if charging:
		var ring_radius := 16.0 + charge * 14.0
		var ring_color := color.lerp(Color.WHITE, charge)
		draw_arc(Vector2.ZERO, ring_radius, -PI / 2, -PI / 2 + TAU * charge, 32, ring_color, 2.0 + charge * 2.0)
	if full_charge > 0.01:
		draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(1, 1, 1, full_charge), 3.0)
	
	var p := to_local(target)
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
	draw_arc(p, 8.0 * pulse, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.5 * marker), 2.0)
