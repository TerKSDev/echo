extends CharacterBody2D
class_name Player

# Signals
signal sound_emitted(pos: Vector2, loudness: float, is_voice: bool, is_sneak: bool)
signal died
signal sneak_toggled(sneaking: bool)
signal pebble_thrown(pos: Vector2)
signal pebble_count_changed(count: int)

# Decoy Pebble System
const MAX_PEBBLE_DIST := 340.0
const MAX_PEBBLES := 3

var pebbles: int = 3
var is_aiming_pebble := false
var pebble_aim_raw_pos := Vector2.ZERO
var pebble_aim_target := Vector2.ZERO

# Movement
const WALK_SPEED := 185.0
const SNEAK_SPEED := 100.0
const ARRIVE_DIST := 8.0
const ACCEL := 900.0
const FRICTION := 1200.0

# Step Sound
const STEP_LOUDNESS_WALK := 0.20
const STEP_LOUDNESS_SNEAK := 0.015
const STRIDE_DIST_WALK := 115.0
const STRIDE_DIST_SNEAK := 96.0

# Voice Sound (tuned to 8~10 tiles: 32px * 8.5~10 = ~270~320px)
const CHARGE_TIME := 0.8
const MIN_LOUDNESS := 0.22
const MAX_LOUDNESS := 0.42
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
var can_move := true
var can_sound := true
var can_sneak := true
var can_pebble := true
var killed_by_type := -1
var target := Vector2.ZERO
var desired := Vector2.ZERO
var marker := 0.0
var moving := false
var sneaking := false
var _step_dist_accum := 0.0
var charging := false
var charge := 0.0
var pulse_scale := 1.0
var was_full := false
var full_charge := 0.0
var click_cooldown := 0.0
var water_count := 0 # > 0 when standing in water tiles (slows player & amplifies footsteps)

# Visual Enhancements
var _burst_radius := 0.0
var _burst_alpha := 0.0
var _death_alpha := 0.0
var _shake_timer := 0.0
var _shake_intensity := 0.0
var _stun_timer := 0.0
var _slow_timer := 0.0
var _slow_mult := 1.0
var _idle_timer := 0.0
var _entry_timer := 1.2 # Prevents idle zoom during the initial level entry pull-back
var _sneak_blend := 0.0 # Smooth 0..1 transition between normal and sneak visual state
var wake_up_anim := false # Cinematic waking-up camera/scale sequence
var _step_ripples: Array[Dictionary] = [] # World-space micro-ripples under footsteps
var _tap_flash := 0.0 # Crisp ripple animation at destination marker when tapped
var _wall_bump_pos := Vector2.ZERO
var _wall_bump_normal := Vector2.UP
var _wall_bump_alpha := 0.0
var _second_wind_used := false
var _second_wind_burst_timer := 0.0
var _terror_shiver_timer := 0.0
var _sonic_surge_timer := 0.0
var _resonance_backlash_timer := 0.0


func has_resonance_backlash() -> bool:
	return _resonance_backlash_timer > 0.0


func has_sonic_surge() -> bool:
	return _sonic_surge_timer > 0.0


func is_holding_breath() -> bool:
	return _idle_timer >= 1.0


func get_max_pebbles() -> int:
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		if ChallengeModifiers.has_curse("curse_single_stone"):
			return 1
		if ChallengeModifiers.has_boon("boon_deep_pockets"):
			return 4
	return MAX_PEBBLES


func trigger_terror_shiver(duration: float = 3.0) -> void:
	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_terror_shiver"):
		_terror_shiver_timer = maxf(_terror_shiver_timer, duration)
var _stuck_timer := 0.0
var _last_progress_pos := Vector2.ZERO
var _water_splash_timer := 0.0
var _facing_dir := Vector2.DOWN
var joystick_direction := Vector2.ZERO


func set_joystick_direction(dir: Vector2) -> void:
	joystick_direction = dir
	if joystick_direction != Vector2.ZERO:
		moving = false
		marker = 0.0
var _cane_timer := 0.0
var _wall_bump_sound_cooldown := 0.0
var _last_touch_time := 0
var _cached_pebble_trajectory: Array[Vector2] = []
var _sfx_cached: SfxManager = null
var _self_exclude: Array[RID] = []


func _get_sfx() -> SfxManager:
	if _sfx_cached == null or not is_instance_valid(_sfx_cached):
		_sfx_cached = get_node_or_null("../SfxManager") as SfxManager
	return _sfx_cached


func _get_self_exclude() -> Array[RID]:
	if _self_exclude.is_empty():
		_self_exclude.append(get_rid())
	return _self_exclude

# Shake Camera
func camera_shake(duration: float = 0.4, intensity: float = 8.0) -> void:
	var mult: float = GameState.screen_shake_intensity
	if mult <= 0.001:
		return
	_shake_timer = maxf(_shake_timer, duration)
	_shake_intensity = maxf(_shake_intensity, intensity * mult)

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


# Slow down player (e.g. hit or acoustic resonance from Listener)
func apply_slow(duration: float = 3.0, multiplier: float = 0.5) -> void:
	if not alive:
		return
	_slow_timer = maxf(_slow_timer, duration)
	_slow_mult = multiplier
	queue_redraw()

func _ready() -> void:
	add_to_group("player")
	trail.top_level = true
	trail.global_position = Vector2.ZERO
	trail.clear_points()
	if camera != null:
		camera.zoom = Vector2(ENTRY_ZOOM_LEVEL, ENTRY_ZOOM_LEVEL)

	# 2D spatial audio listener: centers binaural headphone panning and distance falloff on the player
	var listener := AudioListener2D.new()
	listener.name = "PlayerAudioListener"
	add_child(listener)
	listener.make_current()

	mic.voice_detected.connect(make_voice_sound)
	if GameState.mic_enabled and GameState.is_mic_permission_granted():
		mic.start()
	reset_for_level()


func reset_for_level() -> void:
	if trail != null:
		trail.default_color = GameState.get_sonar_color()
	pebbles = get_max_pebbles()
	pebble_count_changed.emit(pebbles)
	_second_wind_used = false
	_second_wind_burst_timer = 0.0
	_terror_shiver_timer = 0.0
	_sonic_surge_timer = 0.0
	_resonance_backlash_timer = 0.0
	is_aiming_pebble = false
	moving = false
	charging = false
	charge = 0.0
	was_full = false
	_stun_timer = 0.0
	_slow_timer = 0.0
	_slow_mult = 1.0
	water_count = 0
	alive = true
	can_move = true
	can_sound = true
	can_sneak = true
	can_pebble = true
	queue_redraw()

# Handle Player Input
func _unhandled_input(event: InputEvent) -> void:
	# Ignore input if the player is dead or immobilized
	if not alive or _stun_timer > 0.0:
		return

	if not can_move:
		# Allow keyboard Space / Enter to charge sound only if sound is unlocked
		if can_sound:
			if event.is_action_pressed("ui_accept"):
				start_charge()
			elif event.is_action_released("ui_accept"):
				release_charge()
		return

	# Handle Pebble Aiming inputs (Key E, Right Mouse)
	if can_pebble and event is InputEventKey and event.keycode == KEY_E:
		if event.pressed and not event.echo:
			if not is_aiming_pebble:
				if pebbles <= 0 or _stun_timer > 0.0:
					_trigger_pebble_deny()
				else:
					start_aim_pebble()
					update_aim_pebble(get_global_mouse_position())
			else:
				finish_aim_pebble()
		return

	if can_pebble and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if is_aiming_pebble:
				cancel_aim_pebble()
				return
			else:
				if pebbles <= 0 or _stun_timer > 0.0:
					_trigger_pebble_deny()
					return
				start_aim_pebble()
				update_aim_pebble(get_global_mouse_position())
		else:
			if is_aiming_pebble:
				finish_aim_pebble()
		return

	if is_aiming_pebble:
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
			cancel_aim_pebble()
			return
		if event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_SPACE or event.is_action("ui_accept")):
			finish_aim_pebble()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			var aim_dir := Vector2.ZERO
			if event.keycode == KEY_W or event.keycode == KEY_UP:
				aim_dir.y -= 1.0
			elif event.keycode == KEY_S or event.keycode == KEY_DOWN:
				aim_dir.y += 1.0
			elif event.keycode == KEY_A or event.keycode == KEY_LEFT:
				aim_dir.x -= 1.0
			elif event.keycode == KEY_D or event.keycode == KEY_RIGHT:
				aim_dir.x += 1.0
			if aim_dir != Vector2.ZERO:
				_facing_dir = aim_dir.normalized()
				update_aim_pebble(global_position + _facing_dir * 200.0)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion:
			update_aim_pebble(get_global_mouse_position())
			return
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			finish_aim_pebble()
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventScreenDrag:
			var hud := get_parent().get_node_or_null("Hud")
			if hud != null and hud.get("_joystick_active") == true and event.index == hud.get("_joystick_touch_id"):
				return
			var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
			update_aim_pebble(world_pos)
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventScreenTouch and event.pressed:
			var hud := get_parent().get_node_or_null("Hud")
			if hud != null and hud.get("_joystick_active") == true and event.index == hud.get("_joystick_touch_id"):
				return
			var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
			update_aim_pebble(world_pos)
			finish_aim_pebble()
			get_viewport().set_input_as_handled()
			return

	# Mobile Multi-touch Accessibility: 3-finger tap on mobile toggles Blind Assist Mode
	if event is InputEventScreenTouch and event.pressed and event.index == 2:
		GameState.blind_assist_mode = not GameState.blind_assist_mode
		GameState.save_settings()
		var sfx_b := get_node_or_null("../SfxManager") as SfxManager
		if sfx_b != null:
			sfx_b.play_assist_toggle(GameState.blind_assist_mode)
		Input.vibrate_handheld(80)
		get_viewport().set_input_as_handled()
		return

	# Handle touch / mouse tap & drag steering
	var pressed_pos = null
	var is_new_tap := false
	var is_joy_zone: bool = GameState.virtual_joystick_enabled and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion)

	if not is_joy_zone:
		if event is InputEventScreenTouch and event.pressed:
			pressed_pos = get_canvas_transform().affine_inverse() * event.position
			is_new_tap = true
			# Mobile double-tap detection for Fast Pulse Mode
			if GameState.fast_pulse_mode and event.index == 0:
				var now_ms: int = Time.get_ticks_msec()
				if now_ms - _last_touch_time < 320:
					make_sound(MIN_LOUDNESS, true)
					_last_touch_time = 0
				else:
					_last_touch_time = now_ms
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
			if mic != null:
				mic.suppress_timer = 0.08
	
	# Handle keyboard input (on desktop)
	if can_sound:
		if event.is_action_pressed("ui_accept"):
			start_charge()
		elif event.is_action_released("ui_accept"):
			release_charge()
	
		# Fast Pulse: double tap / double click triggers an instant burst of sonar sound
		if GameState.fast_pulse_mode and is_new_tap and event is InputEventMouseButton and event.double_click:
			make_sound(MIN_LOUDNESS, true)

	# Handle sneaking with Shift key (supports Toggle or Hold mode)
	if can_sneak and event is InputEventKey and event.keycode == KEY_SHIFT:
		if GameState.sneak_hold_mode:
			if event.pressed and not event.echo:
				sneaking = true
				queue_redraw()
			elif not event.pressed:
				sneaking = false
				queue_redraw()
		else:
			if event.pressed and not event.echo:
				toggle_sneak()

	# Quick Mic Mute hotkey [M]
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if not GameState.mic_enabled:
			if GameState.is_mic_permission_granted():
				GameState.mic_enabled = true
				GameState.save_settings()
				if mic != null:
					mic.start()
		else:
			GameState.mic_enabled = false
			GameState.save_settings()
			if mic != null:
				mic.enabled = false

	# Hotkey [B]: Toggle Blind Assist Mode on the fly with audio chime confirmation
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		GameState.blind_assist_mode = not GameState.blind_assist_mode
		GameState.save_settings()
		var sfx_b := get_node_or_null("../SfxManager") as SfxManager
		if sfx_b != null:
			sfx_b.play_assist_toggle(GameState.blind_assist_mode)
		Input.vibrate_handheld(60)

	# Hotkey [C]: Check Pebble Inventory via audio pips
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		var sfx_c := get_node_or_null("../SfxManager") as SfxManager
		if sfx_c != null:
			sfx_c.play_inventory_pips(pebbles)

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

	# Handle movement lock during story sequences
	if not can_move:
		moving = false
		desired = Vector2.ZERO
		velocity = Vector2.ZERO
		move_and_slide()
		_update_charging_and_visuals(delta)
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

	# Handle movement with fluid drag in water
	var base_sneak := SNEAK_SPEED * (1.25 if (GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_phantom_tread")) else 1.0)
	var speed: float = base_sneak if sneaking else WALK_SPEED
	if _second_wind_burst_timer > 0.0:
		speed *= 1.40
	if _sonic_surge_timer > 0.0 and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_echo_surge"):
		speed *= 1.25
	if water_count > 0:
		if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_water_strider"):
			speed *= 1.20
		else:
			speed *= 0.55

	if _slow_timer > 0.0:
		_slow_timer -= delta
		speed *= _slow_mult

	# Direct directional input (WASD / Arrow Keys or Virtual Joystick)
	var input_vec := joystick_direction
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1.0

	if input_vec != Vector2.ZERO:
		moving = false
		marker = move_toward(marker, 0.0, delta * 4.0)
		_facing_dir = input_vec.normalized()
		desired = _facing_dir * speed
	elif moving:
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
			var move_dir: Vector2 = to_target.normalized()
			_facing_dir = move_dir

			# Corner-rounding / vertex slip assist in tight corridors (1-tile width):
			# If the player is slightly clipped on a tile corner, cast orthogonal feelers
			# to nudge them around the vertex smoothly
			if dist > 12.0:
				var perp := move_dir.orthogonal()
				var space := get_world_2d().direct_space_state
				var excl := _get_self_exclude()

				var f_left := PhysicsRayQueryParameters2D.create(global_position + perp * 8.0, global_position + perp * 8.0 + move_dir * 16.0)
				f_left.collision_mask = 1
				f_left.exclude = excl
				var hit_l := space.intersect_ray(f_left)

				f_left.from = global_position - perp * 8.0
				f_left.to = global_position - perp * 8.0 + move_dir * 16.0
				var hit_r := space.intersect_ray(f_left)

				if not hit_l.is_empty() and hit_r.is_empty():
					move_dir = (move_dir - perp * 0.65).normalized()
				elif hit_l.is_empty() and not hit_r.is_empty():
					move_dir = (move_dir + perp * 0.65).normalized()

			desired = move_dir * target_speed
	else:
		marker = move_toward(marker, 0.0, delta * 2.0)
		desired = Vector2.ZERO
	
	# Fluid resistance in water: cushioned acceleration and heavier viscous drag
	var base_rate: float = ACCEL if desired != Vector2.ZERO else FRICTION
	var is_water_strider: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_water_strider"))
	var rate: float
	if is_water_strider:
		rate = base_rate
	else:
		rate = (base_rate * 0.72) if (water_count > 0 and desired != Vector2.ZERO) else (base_rate * (1.3 if water_count > 0 else 1.0))
	velocity = velocity.move_toward(desired, rate * delta)
	move_and_slide()

	# Virtual Cane Proximity Radar for Blind / Visually Impaired navigation
	_cane_timer -= delta
	_wall_bump_sound_cooldown -= delta
	if GameState.blind_assist_mode and _cane_timer <= 0.0 and (velocity.length() > 5.0 or desired != Vector2.ZERO):
		var feel_dir: Vector2 = desired.normalized() if desired != Vector2.ZERO else _facing_dir
		var space_state := get_world_2d().direct_space_state
		var cane_query := PhysicsRayQueryParameters2D.create(global_position, global_position + feel_dir * 46.0)
		cane_query.collision_mask = 1
		cane_query.exclude = _get_self_exclude()
		var cane_hit := space_state.intersect_ray(cane_query)
		if not cane_hit.is_empty():
			var hit_dist: float = global_position.distance_to(cane_hit.position)
			_cane_timer = lerpf(0.18, 0.44, hit_dist / 46.0)
			Input.vibrate_handheld(25)
			var sfx_node := _get_sfx()
			if sfx_node != null:
				sfx_node.play_cane_tap(hit_dist)

	# Handle wall collision: allow sliding along walls, stop only on head-on obstacle or zero progress
	if get_slide_collision_count() > 0:
		var col := get_slide_collision(0)
		if col != null:
			var normal: Vector2 = col.get_normal()
			if _wall_bump_alpha < 0.25 and velocity.length() < 45.0:
				_wall_bump_pos = col.get_position()
				_wall_bump_normal = normal
				_wall_bump_alpha = 0.85

			var heading_into_wall: float = desired.normalized().dot(normal)
			if (moving or input_vec != Vector2.ZERO) and heading_into_wall < -0.4:
				# Play impact bump sound only on distinct collision, not repeatedly when resting against wall
				if _wall_bump_sound_cooldown <= 0.0 and velocity.length() > 20.0:
					_wall_bump_sound_cooldown = 0.38
					var sfx_bump := get_node_or_null("../SfxManager") as SfxManager
					if sfx_bump != null:
						sfx_bump.play_wall_bump()
					Input.vibrate_handheld(40)

			# Stuck detection while moving: if tap target is unreachable or blocked by walls/corners
			if moving:
				var d_moved: float = global_position.distance_to(_last_progress_pos)
				if d_moved < 2.0:
					_stuck_timer += delta
					if _stuck_timer > 0.16:
						moving = false
						marker = 0.0
						desired = Vector2.ZERO
						velocity = Vector2.ZERO
						_stuck_timer = 0.0
						camera_shake(0.06, 1.0)
				else:
					_stuck_timer = 0.0
					_last_progress_pos = global_position
			else:
				_stuck_timer = 0.0
				_last_progress_pos = global_position
	else:
		_stuck_timer = 0.0
		_last_progress_pos = global_position

	# Continuous hydrodynamic fluid ripples while wading through water
	if water_count > 0 and velocity.length() > 14.0:
		_water_splash_timer -= delta
		if _water_splash_timer <= 0.0:
			_water_splash_timer = 0.16
			_step_ripples.append({
				"pos": global_position + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)),
				"age": 0.0,
				"max_r": 20.0,
				"alpha": 0.52,
				"is_water": true
			})
	
	# Step sound: Kinematically tied to ground displacement distance (stride physics)
	var speed_now: float = velocity.length()
	if speed_now > 5.0:
		_step_dist_accum += speed_now * delta
		var stride: float = STRIDE_DIST_SNEAK if sneaking else STRIDE_DIST_WALK
		if _step_dist_accum >= stride:
			_step_dist_accum = 0.0
			var is_sneak := sneaking
			var step_loud: float = STEP_LOUDNESS_SNEAK if is_sneak else STEP_LOUDNESS_WALK
			if is_sneak and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_phantom_tread"):
				step_loud *= 0.50
			elif not is_sneak and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_silent_stride"):
				step_loud *= 0.65

			if water_count > 0:
				var water_mult := 1.6 if is_sneak else 2.5
				if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_treacherous_waters"):
					water_mult *= 2.0
				step_loud *= water_mult

			if _terror_shiver_timer > 0.0 and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_terror_shiver"):
				step_loud *= 1.50
			if _resonance_backlash_timer > 0.0 and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_resonance_backlash"):
				step_loud *= 1.50

			make_sound(step_loud, false, is_sneak)
	else:
		# Gradually relax residual stride accumulation when standing still (prevents premature step on next micro-tap)
		_step_dist_accum = move_toward(_step_dist_accum, 0.0, delta * 35.0)
	
	_update_charging_and_visuals(delta)


func _update_charging_and_visuals(delta: float) -> void:
	if _second_wind_burst_timer > 0.0:
		_second_wind_burst_timer = maxf(0.0, _second_wind_burst_timer - delta)
	if _terror_shiver_timer > 0.0:
		_terror_shiver_timer = maxf(0.0, _terror_shiver_timer - delta)
	if _sonic_surge_timer > 0.0:
		_sonic_surge_timer = maxf(0.0, _sonic_surge_timer - delta)
		queue_redraw()
	if _resonance_backlash_timer > 0.0:
		_resonance_backlash_timer = maxf(0.0, _resonance_backlash_timer - delta)
		queue_redraw()

	# Voice charging
	var sfx_mgr := _get_sfx()
	if charging:
		var charge_dur := CHARGE_TIME * (1.40 if (GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_fragile_breath")) else 1.0)
		charge = min(charge + delta / charge_dur, 1.0)
		if charge >= 1.0 and not was_full:
			was_full = true
			full_charge = 1.0
			Input.vibrate_handheld(40)
			if sfx_mgr != null:
				sfx_mgr.play_charge_full()
	if sfx_mgr != null:
		sfx_mgr.update_charge_hum(charging, charge)
	full_charge = move_toward(full_charge, 0.0, delta * 4.0)

	# Ignore mic right after a click for a short time
	click_cooldown = maxf(click_cooldown - delta, 0.0)

	# Smooth sneak transition, tap flash, wall contact spark, and world-space footstep ripples
	_sneak_blend = move_toward(_sneak_blend, 1.0 if sneaking else 0.0, delta * 8.0)
	_tap_flash = move_toward(_tap_flash, 0.0, delta * 3.2)
	_wall_bump_alpha = move_toward(_wall_bump_alpha, 0.0, delta * 2.8)
	if not _step_ripples.is_empty():
		var wr := 0
		for i in _step_ripples.size():
			var r: Dictionary = _step_ripples[i]
			var next_age: float = float(r["age"]) + delta
			if next_age < 0.65:
				r["age"] = next_age
				_step_ripples[wr] = r
				wr += 1
		if wr < _step_ripples.size():
			_step_ripples.resize(wr)

	if is_aiming_pebble:
		_cached_pebble_trajectory = get_pebble_trajectory(pebble_aim_raw_pos)

	# Dynamic camera zoom: initial pull-back on entry, gentle zoom-in when idle, wide view when active
	if _entry_timer > 0.0:
		_entry_timer = maxf(0.0, _entry_timer - delta)
	var is_active: bool = moving or velocity.length() > 5.0 or charging or _burst_alpha > 0.15
	if is_active or _entry_timer > 0.0:
		_idle_timer = 0.0
	else:
		_idle_timer += delta

	if camera != null and not wake_up_anim:
		var target_z: float = IDLE_ZOOM_LEVEL if (_idle_timer >= IDLE_ZOOM_DELAY) else 1.0
		if charging:
			target_z -= 0.06 * charge # Subtle camera pull-back tension while charging
		var zoom_speed: float = 0.75 if (_idle_timer >= IDLE_ZOOM_DELAY) else 2.6
		var cur_z: float = lerpf(camera.zoom.x, target_z, clampf(delta * zoom_speed, 0.0, 1.0))
		camera.zoom = Vector2(cur_z, cur_z)

	_update_trail()
	queue_redraw()


func make_voice_sound(k: float):
	# Ignore mic while dead, stunned, sound input locked, paused, or during story/level transitions
	if not alive or _stun_timer > 0.0 or not can_sound or get_tree().paused:
		return
	var main := get_parent()
	if main != null:
		if "_changing" in main and main._changing:
			return
		if main.has_node("Hud"):
			var hud = main.get_node("Hud")
			if hud != null:
				if hud.has_node("StoryOverlay"):
					var so = hud.get_node("StoryOverlay")
					if so != null and (so.visible or (so.has_method("is_active") and so.is_active()) or so.get("_is_active") == true):
						return
				if hud.has_node("DebriefModal") and hud.get_node("DebriefModal").visible:
					return
				if hud.get("_debrief_modal") != null and is_instance_valid(hud.get("_debrief_modal")) and hud.get("_debrief_modal").visible:
					return
				if hud.has_node("DeathScreen") and hud.get_node("DeathScreen").visible:
					return
				if hud.has_node("VictoryScreen") and hud.get_node("VictoryScreen").visible:
					return
				if hud.has_node("NoteReadModal") and hud.get_node("NoteReadModal").visible:
					return
	make_sound(lerpf(MIN_LOUDNESS, MAX_LOUDNESS, k), true)

# Handle Vocalize
func make_sound(loudness: float, is_voice := false, force_sneak := false) -> void:
	# Ignore sound if the player is dead
	if not alive:
		return

	# Emit the sound signal with explicit sneaking state
	var is_sneak: bool = force_sneak or (sneaking and not is_voice)
	var final_loudness := loudness
	if is_voice and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_curse("curse_acoustic_decay"):
		final_loudness *= 0.75
	sound_emitted.emit(global_position, final_loudness, is_voice, is_sneak)

	# Trigger acoustic burst ring on the player core
	_burst_radius = 8.0
	_burst_alpha = clampf(final_loudness * 2.0, 0.4, 1.0)

	if is_voice:
		if GameState.current_mode == GameState.GameMode.CHALLENGE:
			if ChallengeModifiers.has_boon("boon_echo_surge"):
				_sonic_surge_timer = 2.0
				queue_redraw()
			if ChallengeModifiers.has_curse("curse_resonance_backlash"):
				_resonance_backlash_timer = 2.5
				queue_redraw()

		if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_sonic_stagger") and final_loudness >= 0.50:
			for node in get_tree().get_nodes_in_group("enemy"):
				var enemy_node := node as Enemy
				if enemy_node != null and is_instance_valid(enemy_node):
					if global_position.distance_to(enemy_node.global_position) <= 135.0:
						enemy_node.stun(1.5)
						var push: Vector2 = (enemy_node.global_position - global_position).normalized()
						if push.is_zero_approx():
							push = Vector2.UP
						enemy_node.velocity = push * 200.0

		camera_shake(0.16, lerpf(1.4, 4.2, clampf(final_loudness, 0.0, 1.0)))
		var tween := create_tween()
		pulse_scale = 1.0 + final_loudness * 0.8
		tween.tween_property(self, "pulse_scale", 1.0, 0.25).set_ease(Tween.EASE_OUT)
		_emit_wall_echos(final_loudness)
	else:
		var ripple_r: float = (16.0 if sneaking else 30.0) * (1.45 if water_count > 0 else 1.0)
		var ripple_a: float = (0.24 if sneaking else 0.46) * (1.35 if water_count > 0 else 1.0)
		_step_ripples.append({
			"pos": global_position,
			"age": 0.0,
			"max_r": ripple_r,
			"alpha": clampf(ripple_a, 0.0, 0.85)
		})
		var step_tw := create_tween()
		pulse_scale = 1.05 if sneaking else 1.13
		step_tw.tween_property(self, "pulse_scale", 1.0, 0.18).set_ease(Tween.EASE_OUT)


# Acoustic Echolocation Reflection: emits 8 directional sensory rays that reflect off nearby cave walls
# with travel-time delays and 3D spatial panning (left ear / right ear) for blind navigation
func _emit_wall_echos(loudness: float) -> void:
	if not GameState.blind_assist_mode:
		return
	var space := get_world_2d().direct_space_state
	var max_range: float = 120.0 + loudness * 550.0
	var p_rid := get_rid()
	var ray_dirs: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2(0.7071, 0.7071),
		Vector2.DOWN,
		Vector2(-0.7071, 0.7071),
		Vector2.LEFT,
		Vector2(-0.7071, -0.7071),
		Vector2.UP,
		Vector2(0.7071, -0.7071),
	]
	for dir in ray_dirs:
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * max_range)
		q.collision_mask = 1
		q.exclude = [p_rid]
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var hit_pos: Vector2 = hit.position
			var dist: float = global_position.distance_to(hit_pos)
			var delay: float = dist / 1150.0 # Acoustic travel delay
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(self) and alive:
					var sfx_node := get_node_or_null("../SfxManager") as SfxManager
					if sfx_node != null:
						sfx_node.play_wall_echo(hit_pos, dist, max_range)
			)

# Handle Sneak Toggle
func toggle_sneak():
	if not alive or _stun_timer > 0.0 or not can_sneak:
		return
	sneaking = not sneaking
	var sfx_node := get_node_or_null("../SfxManager") as SfxManager
	if sfx_node != null:
		sfx_node.play_sneak_toggle(sneaking)
	sneak_toggled.emit(sneaking)

# Handle Voice Charging
func start_charge():
	if not alive or _stun_timer > 0.0 or not can_sound:
		return
	if is_aiming_pebble:
		cancel_aim_pebble()
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
	var main := get_tree().current_scene
	if main != null and is_instance_valid(main) and main.get("_changing") == true:
		return
	if has_meta("tutorial_invulnerable") and get_meta("tutorial_invulnerable") == true:
		# Cinematic protection during tutorial chase: knock player backward without killing
		moving = false
		target = global_position + Vector2(-120.0, 0.0)
		velocity = Vector2(-320.0, 0.0)
		camera_shake(0.3, 5.0)
		Input.vibrate_handheld(60)
		return

	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_second_wind") and not _second_wind_used:
		_second_wind_used = true
		_second_wind_burst_timer = 3.0
		# Stun all nearby enemies within 220px and knock them away
		for node in get_tree().get_nodes_in_group("enemy"):
			var e := node as Enemy
			if e != null and is_instance_valid(e):
				if global_position.distance_to(e.global_position) <= 220.0:
					e.stun(2.5)
					var p_dir := (e.global_position - global_position).normalized()
					if p_dir.is_zero_approx():
						p_dir = Vector2.UP
					e.velocity = p_dir * 260.0
		camera_shake(0.4, 8.0)
		Input.vibrate_handheld(120)
		var sfx_m := _get_sfx()
		if sfx_m != null:
			sfx_m.play_charge_full()
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
	_second_wind_burst_timer = 0.0
	_terror_shiver_timer = 0.0
	_sonic_surge_timer = 0.0
	_resonance_backlash_timer = 0.0
	_idle_timer = 0.0
	_entry_timer = 1.2
	_sneak_blend = 0.0
	_tap_flash = 0.0
	_wall_bump_alpha = 0.0
	_stuck_timer = 0.0
	_water_splash_timer = 0.0
	_step_dist_accum = 0.0
	water_count = 0
	_step_ripples.clear()
	if camera != null:
		camera.offset = Vector2.ZERO
		camera.zoom = Vector2(ENTRY_ZOOM_LEVEL, ENTRY_ZOOM_LEVEL)
	trail.clear_points()
	queue_redraw()
	modulate = Color.WHITE

# Handle Player Drawing
func _draw() -> void:
	var is_chal := GameState.current_mode == GameState.GameMode.CHALLENGE
	var is_pink := is_chal or GameState.sonar_palette in ["magenta", "violet", "purple"]
	# Draw world-space footstep water ripples first (underneath player core)
	for r: Dictionary in _step_ripples:
		var age: float = float(r["age"])
		var p_ratio: float = clampf(age / 0.65, 0.0, 1.0)
		var ease_p: float = 1.0 - pow(1.0 - p_ratio, 2.2)
		var rad: float = lerpf(3.0, float(r["max_r"]), ease_p)
		var a: float = float(r["alpha"]) * (1.0 - p_ratio)
		var local_pos: Vector2 = to_local(Vector2(r["pos"]))
		var is_water_ripple: bool = (r.get("is_water", false) == true)
		var ripple_col: Color
		if is_pink:
			ripple_col = Color(0.95, 0.45, 0.85, a) if is_water_ripple else Color(1.0, 0.55, 0.90, a)
		else:
			ripple_col = Color(0.24, 0.76, 1.0, a) if is_water_ripple else Color(0.32, 0.86, 1.0, a)
		draw_arc(local_pos, rad, 0.0, TAU, 24, ripple_col, 1.6 if is_water_ripple else 1.4)
		if p_ratio < 0.45 or is_water_ripple:
			var inner_r: float = rad * (0.58 if is_water_ripple else 0.55)
			var inner_col: Color = Color(1.0, 0.70, 0.95, a * 0.55) if is_pink else Color(0.5, 0.92, 1.0, a * 0.55)
			draw_arc(local_pos, inner_r, 0.0, TAU, 18, inner_col, 1.0)

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
		var glow_col := Color(0.85, 0.20, 0.70, 0.10 * norm_a) if is_pink else Color(0.15, 0.6, 0.9, 0.08 * norm_a)
		draw_circle(core_ofs, (20.0 + 3.0 * breathe) * lerpf(1.0, 0.65, sb), glow_col)
		# Inner soft aura
		var aura_col := Color(0.95, 0.35, 0.80, 0.22 * norm_a) if is_pink else Color(0.25, 0.8, 1.0, 0.18 * norm_a)
		draw_circle(core_ofs, (13.0 + 1.5 * breathe) * lerpf(1.0, 0.75, sb), aura_col)

	if sb > 0.01:
		# Subtle focused dampener ring in Sneak mode
		var ring_r: float = lerpf(14.0, 10.0 + 1.2 * breathe, sb)
		var ring_col := Color(0.90, 0.30, 0.75, 0.42 * sb) if is_pink else Color(0.2, 0.65, 0.85, 0.38 * sb)
		draw_arc(core_ofs, ring_r, 0.0, TAU, 24, ring_col, 1.5)

	# Main body core & hot center (smoothly interpolated size and opacity)
	var body_r: float = lerpf(7.5, 5.0, sb) * pulse_scale
	var body_a: float = lerpf(0.95, 0.58, sb)
	var body_col := Color(1.0, lerpf(0.40, 0.25, sb), 0.85, body_a) if is_pink else Color(0.3, lerpf(0.92, 0.8, sb), 1.0, body_a)
	draw_circle(core_ofs, body_r, body_col)

	var center_r: float = lerpf(3.5, 2.5, sb) * pulse_scale
	var center_a: float = lerpf(1.0, 0.82, sb)
	var center_col := Color(1.0, 0.92, 0.98, center_a) if is_pink else Color(0.88, 0.97, 1.0, center_a)
	draw_circle(core_ofs, center_r, center_col)

	# Directional sonar heading cue when moving
	if velocity.length() > 10.0:
		var heading := velocity.normalized()
		var cue_scale: float = lerpf(1.0, 0.75, sb)
		var cue_alpha: float = lerpf(0.45, 0.24, sb)
		var tip := core_ofs + heading * (13.0 + 2.0 * breathe) * cue_scale
		var left_wing := heading.rotated(2.4) * (8.0 * cue_scale)
		var right_wing := heading.rotated(-2.4) * (8.0 * cue_scale)
		var cue_col := Color(1.0, 0.55, 0.90, cue_alpha) if is_pink else Color(0.4, 0.9, 1.0, cue_alpha)
		draw_line(tip, tip + left_wing, cue_col, 1.5)
		draw_line(tip, tip + right_wing, cue_col, 1.5)

	# Sound emission burst shockwave
	if _burst_alpha > 0.01:
		var burst_col := Color(1.0, 0.60, 0.92, _burst_alpha) if is_pink else Color(0.6, 0.95, 1.0, _burst_alpha)
		draw_arc(Vector2.ZERO, _burst_radius, 0.0, TAU, 32, burst_col, 2.0)

	# Charging ring
	if charging:
		var ring_radius := 16.0 + charge * 14.0
		var base_charge_col := Color(1.0, 0.45, 0.85) if is_pink else Color(0.35, 0.85, 1.0)
		var ring_color := base_charge_col.lerp(Color.WHITE, charge)
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
		var m_outer := Color(1.0, 0.45, 0.90, 0.55 * marker) if is_pink else Color(0.3, 1.0, 1.0, 0.48 * marker)
		var m_inner := Color(1.0, 0.88, 0.96, 0.82 * marker) if is_pink else Color(0.85, 1.0, 1.0, 0.78 * marker)
		draw_arc(p, 9.0 * p_pulse, 0.0, TAU, 24, m_outer, 1.8)
		draw_circle(p, 2.2, m_inner)
		if _tap_flash > 0.01:
			var tap_r: float = lerpf(22.0, 9.0, 1.0 - _tap_flash)
			var tap_col := Color(1.0, 0.65, 0.92, 0.65 * _tap_flash) if is_pink else Color(0.65, 0.98, 1.0, 0.65 * _tap_flash)
			draw_arc(p, tap_r, 0.0, TAU, 24, tap_col, 1.4)

	# Tactile wall contact shimmer when brushing/stopping against a wall in darkness
	if _wall_bump_alpha > 0.01:
		var bp := to_local(_wall_bump_pos)
		var tangent := Vector2(-_wall_bump_normal.y, _wall_bump_normal.x)
		var span: float = lerpf(6.0, 15.0, 1.0 - _wall_bump_alpha)
		var bump_line := Color(1.0, 0.50, 0.88, 0.75 * _wall_bump_alpha) if is_pink else Color(0.45, 0.92, 1.0, 0.75 * _wall_bump_alpha)
		var bump_dot := Color(1.0, 0.90, 0.97, 0.85 * _wall_bump_alpha) if is_pink else Color(0.85, 0.98, 1.0, 0.85 * _wall_bump_alpha)
		draw_line(bp - tangent * span, bp + tangent * span, bump_line, 2.2)
		draw_circle(bp, 2.5, bump_dot)

	# Acoustic paralysis / Stun visual feedback
	if _stun_timer > 0.0:
		var stun_pulse := 16.0 + 2.5 * sin(t * 26.0)
		draw_arc(Vector2.ZERO, stun_pulse, 0.0, TAU, 28, Color(1.0, 0.3, 0.5, 0.85), 2.0)
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.15, 0.3, 0.35))
		for i in 4:
			var ang := i * PI * 0.5 + t * 6.0
			var spark := Vector2.from_angle(ang) * (stun_pulse + 4.0)
			draw_circle(spark, 2.0, Color(1.0, 0.85, 0.9, 0.9))
	elif _slow_timer > 0.0:
		var slow_pulse := 15.0 + 1.8 * sin(t * 10.0)
		draw_arc(Vector2.ZERO, slow_pulse, 0.0, TAU, 24, Color(0.2, 0.94, 0.68, 0.70), 1.6)
		draw_circle(Vector2.ZERO, 5.0, Color(0.1, 0.65, 0.45, 0.25))

	# Sonic surge boon feedback (cyan sprint stream)
	if _sonic_surge_timer > 0.0:
		var surge_ratio: float = clampf(_sonic_surge_timer / 2.0, 0.0, 1.0)
		var surge_r: float = 17.0 + 2.5 * sin(t * 16.0)
		draw_arc(core_ofs, surge_r, 0.0, TAU, 28, Color(0.25, 0.95, 0.85, 0.52 * surge_ratio), 1.8)
		if velocity.length() > 10.0:
			var trail_back := -velocity.normalized() * (12.0 * surge_ratio)
			draw_line(core_ofs, core_ofs + trail_back, Color(0.35, 1.0, 0.90, 0.70 * surge_ratio), 2.2)

	# Resonance backlash curse feedback (unstable magenta acoustic vibration ring)
	if _resonance_backlash_timer > 0.0:
		var res_ratio: float = clampf(_resonance_backlash_timer / 2.5, 0.0, 1.0)
		var res_r: float = 21.0 + 3.5 * sin(t * 20.0)
		draw_arc(core_ofs, res_r, 0.0, TAU, 28, Color(0.85, 0.25, 0.95, 0.55 * res_ratio), 1.8)
		for i in 3:
			var ang := i * (TAU / 3.0) + t * 4.0
			var orb := core_ofs + Vector2.from_angle(ang) * res_r
			draw_circle(orb, 2.0, Color(1.0, 0.45, 0.95, 0.75 * res_ratio))

	# Calm breath boon feedback (serene mint breathing aura when idle for >= 1.0s)
	if _idle_timer >= 1.0 and GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_calm_breath"):
		var calm_breathe := 0.5 + 0.5 * sin(t * 2.0)
		var calm_r: float = 16.0 + 2.0 * calm_breathe
		draw_arc(core_ofs, calm_r, 0.0, TAU, 24, Color(0.35, 0.95, 0.75, 0.40 + 0.20 * calm_breathe), 1.5)
		draw_circle(core_ofs, 4.0, Color(0.4, 1.0, 0.8, 0.18 * calm_breathe))

	# Pebble Aiming trajectory arc & noise landing reticle
	if is_aiming_pebble:
		_draw_pebble_aim_trajectory(t)


# --- Decoy Pebble System -----------------------------------------------------

func get_pebble_trajectory(target_world_pos: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = [global_position]
	var offset := target_world_pos - global_position
	var total_len := clampf(offset.length(), 24.0, MAX_PEBBLE_DIST)
	var dir := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT

	var space := get_world_2d().direct_space_state
	var excl := _get_self_exclude()

	# First segment: from player toward target or wall
	var q1 := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * total_len)
	q1.collision_mask = 1
	q1.hit_from_inside = true
	q1.exclude = excl
	var hit1 := space.intersect_ray(q1)

	if hit1.is_empty():
		result.append(global_position + dir * total_len)
		return result

	# Hit Wall 1: Ricochet bounce calculation
	var hit1_pos: Vector2 = hit1.position
	var n1: Vector2 = hit1.get("normal", -dir)
	if n1.is_zero_approx() or dir.dot(n1) > 0.0:
		n1 = -dir
	else:
		n1 = n1.normalized()

	var d1: float = global_position.distance_to(hit1_pos)
	var remaining := (total_len - d1) * 0.72 # Friction/energy loss on impact
	if remaining < 18.0:
		result.append(hit1_pos + n1 * 6.0)
		return result

	result.append(hit1_pos)

	# Specular reflection: d_bounce = d - 2(d . n)n
	var bounce_dir: Vector2 = dir.bounce(n1).normalized()
	if bounce_dir.dot(n1) < 0.0:
		bounce_dir = (bounce_dir - 2.0 * bounce_dir.dot(n1) * n1).normalized()
	if bounce_dir.is_zero_approx():
		bounce_dir = n1

	var bounce_start: Vector2 = hit1_pos + n1 * 4.0

	var q2 := PhysicsRayQueryParameters2D.create(bounce_start, bounce_start + bounce_dir * remaining)
	q2.collision_mask = 1
	q2.hit_from_inside = true
	q2.exclude = excl
	var hit2 := space.intersect_ray(q2)

	if hit2.is_empty():
		result.append(bounce_start + bounce_dir * remaining)
	else:
		var hit2_pos: Vector2 = hit2.position
		var n2: Vector2 = hit2.get("normal", -bounce_dir)
		if n2.is_zero_approx() or bounce_dir.dot(n2) > 0.0:
			n2 = -bounce_dir
		else:
			n2 = n2.normalized()
		result.append(hit2_pos + n2 * 6.0)

	return result


func get_clamped_pebble_target(target_world_pos: Vector2) -> Vector2:
	var traj := get_pebble_trajectory(target_world_pos)
	return traj.back()


func _trigger_pebble_deny() -> void:
	var hud_node := get_parent().get_node_or_null("Hud")
	if hud_node != null and hud_node.has_node("PebbleBtn"):
		var p_btn = hud_node.get_node("PebbleBtn")
		if p_btn.has_method("play_empty_feedback"):
			p_btn.play_empty_feedback()


func start_aim_pebble() -> void:
	if pebbles <= 0 or not alive or _stun_timer > 0.0 or not can_pebble:
		return
	if charging:
		charging = false
	is_aiming_pebble = true
	var dir: Vector2 = velocity.normalized() if velocity.length() > 10.0 else _facing_dir
	pebble_aim_raw_pos = global_position + dir * 180.0
	_cached_pebble_trajectory = get_pebble_trajectory(pebble_aim_raw_pos)
	pebble_aim_target = _cached_pebble_trajectory.back()
	queue_redraw()


func update_aim_pebble(target_world_pos: Vector2) -> void:
	if not is_aiming_pebble:
		return
	pebble_aim_raw_pos = target_world_pos
	_cached_pebble_trajectory = get_pebble_trajectory(pebble_aim_raw_pos)
	pebble_aim_target = _cached_pebble_trajectory.back()
	queue_redraw()


func cancel_aim_pebble() -> void:
	if not is_aiming_pebble:
		return
	is_aiming_pebble = false
	queue_redraw()


func finish_aim_pebble() -> bool:
	if not is_aiming_pebble:
		return false
	var target_to_throw := pebble_aim_raw_pos
	is_aiming_pebble = false
	queue_redraw()
	return throw_pebble(target_to_throw)


func throw_pebble(target_world_pos: Vector2) -> bool:
	if pebbles <= 0 or not alive or _stun_timer > 0.0:
		return false
	pebbles -= 1
	pebble_count_changed.emit(pebbles)

	var trajectory: Array[Vector2] = _cached_pebble_trajectory.duplicate() if _cached_pebble_trajectory.size() >= 2 else get_pebble_trajectory(target_world_pos)
	var final_target: Vector2 = trajectory.back()

	var proj := PebbleProjectile.new()
	proj.setup(trajectory)
	get_parent().add_child(proj)
	pebble_thrown.emit(final_target)

	Input.vibrate_handheld(40)
	return true


func _draw_pebble_aim_trajectory(t: float) -> void:
	var trajectory: Array[Vector2] = _cached_pebble_trajectory if _cached_pebble_trajectory.size() >= 2 else get_pebble_trajectory(pebble_aim_raw_pos)
	if trajectory.size() < 2:
		return

	var final_world: Vector2 = trajectory.back()
	var final_local := to_local(final_world)
	var amber := Color(1.0, 0.78, 0.28)

	# 1. Acoustic distraction estimation ring at final target landing spot (280px dry / 360px in water)
	var is_water_target := false
	var main_node := get_parent()
	if main_node != null and "water_cells" in main_node and "_level_root" in main_node and main_node._level_root != null and main_node._level_root.walls != null:
		var wc: Vector2i = main_node._level_root.walls.local_to_map(main_node._level_root.walls.to_local(final_world))
		is_water_target = main_node.water_cells.has(wc)
	var noise_rad := 360.0 if is_water_target else 280.0
	var ring_col := Color(0.35, 0.88, 1.0) if is_water_target else amber
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	draw_arc(final_local, noise_rad, 0.0, TAU, 48, Color(ring_col, 0.14 + 0.06 * pulse), 1.2)
	for k in 12:
		var ang := k * TAU / 12.0 + t * 0.5
		var tick_p := final_local + Vector2.from_angle(ang) * noise_rad
		draw_circle(tick_p, 1.8, Color(ring_col, 0.38))

	# 2. Draw each flight segment (parabolic arc)
	for s_idx in range(trajectory.size() - 1):
		var p0_local := to_local(trajectory[s_idx])
		var p1_local := to_local(trajectory[s_idx + 1])
		var seg_len := p0_local.distance_to(p1_local)
		var seg_segs := clampi(int(seg_len / 16.0), 6, 16)
		var h_max := clampf(seg_len * 0.16, 12.0, 44.0) * (0.65 if s_idx > 0 else 1.0)

		for i in range(1, seg_segs):
			var frac := float(i) / float(seg_segs)
			var h := sin(frac * PI) * h_max
			var ground_pt := p0_local.lerp(p1_local, frac)
			var arc_pt := ground_pt - Vector2(0.0, h)

			draw_circle(ground_pt, 1.4, Color(0.0, 0.0, 0.0, 0.25))

			var is_pulse := absf(fposmod(frac * 3.0 - t * 3.5, 1.0)) < 0.22
			var dot_col := Color.WHITE if is_pulse else Color(amber, 0.75 + 0.25 * sin(frac * PI))
			draw_circle(arc_pt, lerpf(1.8, 3.0, sin(frac * PI)), dot_col)

		# If this segment hits a wall (i.e. ricochet bounce node), draw a gleaming wall impact diamond!
		if s_idx < trajectory.size() - 2:
			var d_pulse := 1.0 + 0.2 * sin(t * 10.0)
			draw_arc(p1_local, 7.0 * d_pulse, 0.0, TAU, 16, Color(1.0, 0.9, 0.5, 0.9), 1.8)
			draw_circle(p1_local, 3.0, Color.WHITE)

	# 3. Final Landing Target Reticle
	draw_circle(final_local, 7.0, Color(amber, 0.25))
	var reticle_r := 12.0 + 2.0 * sin(t * 8.0)
	draw_arc(final_local, reticle_r, 0.0, TAU, 24, Color(amber, 0.85), 1.8)
	draw_circle(final_local, 2.5, Color.WHITE)
	var ch_len := 5.0
	draw_line(final_local + Vector2(-reticle_r - ch_len, 0), final_local + Vector2(-reticle_r + 2, 0), amber, 1.5)
	draw_line(final_local + Vector2(reticle_r - 2, 0), final_local + Vector2(reticle_r + ch_len, 0), amber, 1.5)
	draw_line(final_local + Vector2(0, -reticle_r - ch_len), final_local + Vector2(0, -reticle_r + 2), amber, 1.5)
	draw_line(final_local + Vector2(0, reticle_r - 2), final_local + Vector2(0, reticle_r + ch_len), amber, 1.5)
