extends Button

const Icons = preload("res://ui/icons/Icons.gd")

var _player: Node = null
var _press_scale := 1.0
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
		is_sneaking = bool(_player.get("sneaking"))
	_active_blend = move_toward(_active_blend, 1.0 if is_sneaking else 0.0, delta * 9.0)
	scale = Vector2(_press_scale, _press_scale)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 48.0)
	var radius := 44.0
	var is_sneaking := false
	var is_stunned := false
	if _player != null and is_instance_valid(_player):
		is_sneaking = bool(_player.get("sneaking"))
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			is_stunned = true

	var b: float = _active_blend
	var pulse := 0.5 + 0.5 * sin(_timer * 3.5)

	# Outer aura (blended smoothly)
	if tutorial_pulse:
		var t_wave := fposmod(_timer * 1.6, 1.0)
		var t_r := radius + 4.0 + t_wave * 26.0
		var t_a := (1.0 - t_wave) * 0.85
		draw_arc(center, t_r, 0.0, TAU, 36, Color(0.45, 0.92, 1.0, t_a), 2.2)
		draw_circle(center, radius + 4.0, Color(0.20, 0.70, 1.0, 0.16 + 0.10 * sin(_timer * 6.0)))
	else:
		var halo_r: float = radius + lerpf(3.0, 4.0 + 3.0 * pulse, b)
		var halo_col: Color = Color(0.1, 0.35, 0.6, 0.1).lerp(Color(0.18, 0.65, 1.0, 0.15 + 0.12 * pulse), b)
		draw_circle(center, halo_r, halo_col)

	# Glass disc
	var disc_col: Color = Color(0.04, 0.11, 0.2, 0.72).lerp(Color(0.06, 0.22, 0.36, 0.9), b)
	draw_circle(center, radius, disc_col)

	# Border rim
	var rim_col: Color = Color(0.24, 0.48, 0.72, 0.55).lerp(Color(0.38, 0.88, 1.0, 0.95), b)
	if is_stunned:
		rim_col = Color(1.0, 0.28, 0.5, 0.75)
	draw_arc(center, radius, 0.0, TAU, 40, rim_col, lerpf(1.6, 2.2, b))

	# Center Icons
	var icon_col: Color = Color(0.7, 0.85, 0.98, 0.6).lerp(Color(0.5, 0.95, 1.0, 1.0), b)
	if is_stunned:
		icon_col = Color(1.0, 0.45, 0.6, 0.45)
	_draw_stealth_icon(center, icon_col)

	# Label below
	var tut_lbl := "HOLD TO SNEAK" if GameState.sneak_hold_mode else "TAP TO SNEAK"
	var lbl_text := "STUNNED" if is_stunned else ("SNEAKING" if is_sneaking else (tut_lbl if tutorial_pulse else "SNEAK"))
	var lbl_col: Color = Color(0.48, 0.72, 0.92, 0.7).lerp(Color(0.5, 0.95, 1.0, 0.95), b)
	if is_stunned:
		lbl_col = Color(1.0, 0.38, 0.55, 0.85)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, 114.0), lbl_text, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 11, lbl_col)
	if not GameState.is_touch_or_mobile():
		var key_hint := "[HOLD SHIFT]" if GameState.sneak_hold_mode else "[SHIFT]"
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 127.0), key_hint, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 9, Color(lbl_col, 0.45))

func _draw_stealth_icon(center: Vector2, col: Color) -> void:
	Icons.draw_stealth(self, center, col)
