extends Button

var _player: Node = null
var _press_scale := 1.0
var _ripple_time := 0.0
var tutorial_pulse := false
var tutorial_hold_mode := false

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pivot_offset = Vector2(size.x * 0.5, 48.0)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	_player = get_tree().get_first_node_in_group("player")

func _on_down() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 0.92, 0.08).set_trans(Tween.TRANS_SINE)

func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_ripple_time += delta
	scale = Vector2(_press_scale, _press_scale)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 48.0)
	var radius := 44.0

	# 1. Subtle Outer Glow halo / Tutorial beacon
	if tutorial_pulse:
		var t_wave := fposmod(_ripple_time * 1.6, 1.0)
		var t_r := radius + 4.0 + t_wave * 26.0
		var t_a := (1.0 - t_wave) * 0.85
		draw_arc(center, t_r, 0.0, TAU, 36, Color(0.45, 0.92, 1.0, t_a), 2.2)
		draw_circle(center, radius + 4.0, Color(0.20, 0.70, 1.0, 0.16 + 0.10 * sin(_ripple_time * 6.0)))
	else:
		draw_circle(center, radius + 5.0, Color(0.12, 0.45, 0.8, 0.15))

	# 2. Main Cavern Glass Disc
	draw_circle(center, radius, Color(0.04, 0.12, 0.22, 0.78))
	draw_circle(center, radius * 0.78, Color(0.08, 0.22, 0.36, 0.35))

	# 3. Base Border Ring
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.26, 0.54, 0.82, 0.65), 1.8)

	# 4. Dynamic Charge Ring & Stun State (tracked from player)
	var charging := false
	var charge_val := 0.0
	var is_stunned := false
	if _player != null and is_instance_valid(_player):
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			is_stunned = true
		if "charging" in _player and _player.charging:
			charging = true
			charge_val = float(_player.charge)

	if is_stunned:
		draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 0.28, 0.5, 0.75), 2.0)

	if charging and charge_val > 0.01:
		var start_angle := -PI * 0.5
		var sweep := TAU * clampf(charge_val, 0.0, 1.0)
		var charge_color := Color(0.35, 0.85, 1.0).lerp(Color(1.0, 1.0, 1.0), charge_val)
		draw_arc(center, radius, start_angle, start_angle + sweep, 48, charge_color, 3.5)

		# Spark glow at leading edge of charging circle
		var tip_angle := start_angle + sweep
		var tip_pos := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
		draw_circle(tip_pos, 4.0, Color.WHITE)

		# When full charge, pulse full inner ring
		if charge_val >= 1.0:
			var pulse := 0.5 + 0.5 * sin(_ripple_time * 16.0)
			draw_arc(center, radius * 0.82, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.4 * pulse), 2.0)

	# 5. Concentric Echo Icons (( · ))
	var icon_col := Color(0.85, 0.94, 1.0, 0.92) if not charging else Color.WHITE
	if is_stunned:
		icon_col = Color(1.0, 0.45, 0.6, 0.45)
	# Center dot
	draw_circle(center, 4.5, icon_col)
	# Inner echo waves (left and right)
	draw_arc(center, 13.0, -PI * 0.32, PI * 0.32, 16, icon_col, 2.0)
	draw_arc(center, 13.0, PI * 0.68, PI * 1.32, 16, icon_col, 2.0)
	# Outer echo waves (left and right)
	var outer_wave_col := Color(icon_col, 0.6)
	draw_arc(center, 22.0, -PI * 0.28, PI * 0.28, 16, outer_wave_col, 1.8)
	draw_arc(center, 22.0, PI * 0.72, PI * 1.28, 16, outer_wave_col, 1.8)

	# 6. Micro Label Below
	var label_text := "STUNNED" if is_stunned else ("CALLING..." if charging else ("HOLD TO CHARGE" if tutorial_hold_mode else ("TAP TO CALL" if tutorial_pulse else "ECHO")))
	var label_col := Color(0.55, 0.8, 1.0, 0.7 if not charging else 0.95)
	if tutorial_pulse:
		label_col = Color(0.75, 0.96, 1.0, 0.95)
	elif is_stunned:
		label_col = Color(1.0, 0.38, 0.55, 0.85)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, 114.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 11, label_col)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, 127.0), "[SPACE / HOLD]", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 9, Color(label_col, 0.45))
