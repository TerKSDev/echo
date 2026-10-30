extends Button

var _player: Node = null
var _press_scale := 1.0
var base_scale := 1.0
var _timer := 0.0
var _active_blend := 0.0
var tutorial_pulse := false

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
	_timer += delta
	var is_sneaking := false
	if _player != null and is_instance_valid(_player):
		is_sneaking = (_player.get("sneaking") == true)
	_active_blend = move_toward(_active_blend, 1.0 if is_sneaking else 0.0, delta * 9.0)
	scale = Vector2(_press_scale * base_scale, _press_scale * base_scale)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 48.0)
	var radius := 44.0
	var is_chal: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	var is_sneaking := false
	var is_stunned := false
	if _player != null and is_instance_valid(_player):
		is_sneaking = (_player.get("sneaking") == true)
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			is_stunned = true

	var b: float = _active_blend
	var pulse := 0.5 + 0.5 * sin(_timer * 3.5)

	# Outer aura (blended smoothly)
	if tutorial_pulse:
		var t_wave := fposmod(_timer * 1.6, 1.0)
		var t_r := radius + 4.0 + t_wave * 26.0
		var t_a := (1.0 - t_wave) * 0.85
		var t_col := Color(1.0, 0.50, 0.90, t_a) if is_chal else Color(0.45, 0.92, 1.0, t_a)
		var t_glow := Color(0.85, 0.25, 0.75, 0.16 + 0.10 * sin(_timer * 6.0)) if is_chal else Color(0.20, 0.70, 1.0, 0.16 + 0.10 * sin(_timer * 6.0))
		draw_arc(center, t_r, 0.0, TAU, 36, t_col, 2.2)
		draw_circle(center, radius + 4.0, t_glow)
	else:
		var halo_r: float = radius + lerpf(5.0, 6.0 + 3.0 * pulse, b)
		var base_halo := Color(0.85, 0.20, 0.65, 0.16).lerp(Color(1.0, 0.45, 0.88, 0.25 + 0.12 * pulse), b) if is_chal else Color(0.12, 0.45, 0.8, 0.15).lerp(Color(0.20, 0.72, 1.0, 0.22 + 0.12 * pulse), b)
		draw_circle(center, halo_r, base_halo)

	# Dual-layer abyssal glass disc (matching SoundButton)
	var disc_col: Color
	var inner_col: Color
	if is_chal:
		disc_col = Color(0.16, 0.03, 0.13, 0.88).lerp(Color(0.28, 0.06, 0.22, 0.94), b)
		inner_col = Color(0.25, 0.05, 0.20, 0.45).lerp(Color(0.40, 0.10, 0.34, 0.55), b)
	else:
		disc_col = Color(0.04, 0.12, 0.22, 0.78).lerp(Color(0.06, 0.24, 0.38, 0.92), b)
		inner_col = Color(0.08, 0.22, 0.36, 0.35).lerp(Color(0.12, 0.34, 0.52, 0.50), b)
	draw_circle(center, radius, disc_col)
	draw_circle(center, radius * 0.78, inner_col)

	# Border rim & cardinal sonar bezel ticks
	var rim_col: Color
	if is_chal:
		rim_col = Color(0.85, 0.25, 0.75, 0.78).lerp(Color(1.0, 0.55, 0.92, 0.98), b)
	else:
		rim_col = Color(0.26, 0.54, 0.82, 0.65).lerp(Color(0.42, 0.92, 1.0, 0.98), b)
	if is_stunned:
		rim_col = Color(1.0, 0.28, 0.5, 0.75)
	draw_arc(center, radius, 0.0, TAU, 48, rim_col, lerpf(1.8, 2.4, b))

	var tick_col := Color(rim_col, lerpf(0.35, 0.75, b))
	for i in range(4):
		var ang := i * PI * 0.5
		var dir := Vector2.from_angle(ang)
		draw_line(center + dir * (radius - 5.5), center + dir * (radius - 1.5), tick_col, 1.4)

	# Center Icons
	var icon_base := Color(1.0, 0.90, 0.96, 0.92).lerp(Color(1.0, 0.65, 0.95, 1.0), b) if is_chal else Color(0.85, 0.94, 1.0, 0.88).lerp(Color(0.55, 0.98, 1.0, 1.0), b)
	var icon_col: Color = icon_base
	if is_stunned:
		icon_col = Color(1.0, 0.45, 0.6, 0.45)
	_draw_stealth_icon(center, icon_col)

	# Label below
	var tut_lbl := "HOLD TO SNEAK" if GameState.sneak_hold_mode else "TAP TO SNEAK"
	var lbl_text := "STUNNED" if is_stunned else ("SNEAKING" if is_sneaking else (tut_lbl if tutorial_pulse else "SNEAK"))
	var normal_lbl_col: Color = (Color(0.95, 0.65, 0.88, 0.75).lerp(Color(1.0, 0.75, 0.95, 0.98), b)) if is_chal else (Color(0.55, 0.80, 1.0, 0.72).lerp(Color(0.5, 0.95, 1.0, 0.95), b))
	var lbl_col: Color = Color(1.0, 0.38, 0.55, 0.85) if is_stunned else normal_lbl_col
	draw_string(ThemeDB.fallback_font, Vector2(0.0, 114.0), lbl_text, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 11, lbl_col)
	if not GameState.is_touch_or_mobile():
		var key_hint := "[HOLD SHIFT]" if GameState.sneak_hold_mode else "[SHIFT]"
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 127.0), key_hint, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 9, Color(lbl_col, 0.45))

func _draw_stealth_icon(center: Vector2, col: Color) -> void:
	Icons.draw_stealth(self, center, col)
