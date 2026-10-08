extends CharacterBody2D

signal sound_emitted(pos: Vector2, loudness: float, is_voice: bool)

const WALK_SPEED := 200.0
const SNEAK_SPEED := 80.0
const ARRIVE_DIST := 8.0

# Step sound parameters
const STEP_LOUDNESS_WALK := 0.05
const STEP_LOUDNESS_SNEAK := 0.01
const STEP_INTERVAL_WALK := 0.5
const STEP_INTERVAL_SNEAK := 0.8

# Voice sound parameters
const CHARGE_TIME := 0.3
const MIN_LOUDNESS := 0.01
const MAX_LOUDNESS := 0.25

# Movement variables
var target := Vector2.ZERO
var moving := false
var sneaking := false
var step_timer := 0.0
var charging := false
var charge := 0.0

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
	var speed = SNEAK_SPEED if sneaking else WALK_SPEED
	if moving:
		var dir = target - global_position
		if dir.length() < ARRIVE_DIST:
			moving = false
			velocity = Vector2.ZERO
		else:
			velocity = dir.normalized() * speed
	
	move_and_slide()

	# Handle collision detection
	if moving and get_slide_collision_count() > 0 and velocity.length() < 5.0:
		moving = false
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

	queue_redraw()

# Handle voice emission
func make_sound(loudness: float, is_voice := false):
	sound_emitted.emit(global_position, loudness, is_voice)

# Toggle sneaking state
func toggle_sneak():
	sneaking = not sneaking

# Start charging the voice sound
func start_charge():
	charging = true
	charge = 0.0

func release_charge():
	if not charging:
		return
	charging = false
	make_sound(lerp(MIN_LOUDNESS, MAX_LOUDNESS, charge), true)
	charge = 0.0

# Simple debug drawing for the player
func _draw():
	var color = Color(0.3, 1.0, 1.0, 0.35 if sneaking else 1.0)
	draw_circle(Vector2.ZERO, 8.0, color)
	if charging:
		draw_arc(Vector2.ZERO, 16.0, -PI / 2, -PI / 2 + TAU * charge, 32, color, 2.0)
