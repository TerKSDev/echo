extends Button

var _player: Node = null
var _press_scale := 1.0
var base_scale := 1.0
var _anim_time := 0.0
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _empty_flash := 0.0


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pivot_offset = Vector2(size.x * 0.5, 36.0)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	_player = get_tree().get_first_node_in_group("player")


func play_empty_feedback() -> void:
	_empty_flash = 1.0
	Input.vibrate_handheld(45)
	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_deny_tick()
	var orig_x := position.x
	var tw := create_tween()
	tw.tween_property(self, "position:x", orig_x - 4.0, 0.04)
	tw.tween_property(self, "position:x", orig_x + 4.0, 0.04)
	tw.tween_property(self, "position:x", orig_x - 2.5, 0.04)
	tw.tween_property(self, "position:x", orig_x + 2.5, 0.04)
	tw.tween_property(self, "position:x", orig_x, 0.04)


func _on_down() -> void:
	if _player != null and is_instance_valid(_player):
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			play_empty_feedback()
			return
		if "pebbles" in _player and int(_player.pebbles) <= 0:
			play_empty_feedback()
			return
		if _player.is_aiming_pebble:
			_player.cancel_aim_pebble()
			_is_dragging = false
			return
		_is_dragging = true
		_drag_start = get_viewport().get_mouse_position()
		_player.start_aim_pebble()
		if GameState.blind_assist_mode:
			var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
			if sfx != null and is_instance_valid(sfx):
				sfx.play_inventory_pips(_player.pebbles)
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 0.92, 0.08).set_trans(Tween.TRANS_SINE)


func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if not _is_dragging or _player == null or not is_instance_valid(_player):
		return

	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		var center_screen := global_position + Vector2(size.x * 0.5, 36.0)
		var touch_pos: Vector2 = event.position if (event is InputEventScreenDrag) else get_viewport().get_mouse_position()
		var offset := touch_pos - center_screen
		if offset.length() > 14.0:
			var sens: float = GameState.pebble_sensitivity
			var aim_dist: float = clampf(offset.length() * 2.5 * sens, 50.0, 340.0)
			var aim_dir: Vector2 = offset.normalized()
			_player.update_aim_pebble(_player.global_position + aim_dir * aim_dist)
			get_viewport().set_input_as_handled()

	elif (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and not event.pressed):
		_is_dragging = false
		var tw := create_tween()
		tw.tween_property(self, "_press_scale", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _player != null and is_instance_valid(_player) and _player.is_aiming_pebble:
			var touch_pos: Vector2 = event.position if event is InputEventScreenTouch else get_viewport().get_mouse_position()
			if touch_pos.distance_to(_drag_start) > 22.0:
				_player.finish_aim_pebble()
				get_viewport().set_input_as_handled()
			else:
				# Quick tap: keep aim mode active so player can tap target on map!
				pass


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_anim_time += delta
	if _empty_flash > 0.0:
		_empty_flash = maxf(0.0, _empty_flash - delta * 4.0)
	scale = Vector2(_press_scale * base_scale, _press_scale * base_scale)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, 36.0)
	var radius := 32.0

	var pebbles_left := 3
	var is_aiming := false
	var is_stunned := false
	if _player != null and is_instance_valid(_player):
		pebbles_left = int(_player.get("pebbles"))
		is_aiming = (_player.get("is_aiming_pebble") == true)
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			is_stunned = true

	var is_empty := pebbles_left <= 0 and not is_aiming

	# Color palette: Warm Amber / Golden Topaz (tactical decoy sub-button)
	# When empty, gently fades down so it doesn't clutter darkness
	var empty_alpha_mult := 0.35 if is_empty else 1.0

	var col_glow := Color(1.0, 0.72, 0.22, (0.14 if not is_aiming else 0.35) * empty_alpha_mult)
	var col_disc := Color(0.12, 0.09, 0.04, 0.82 * empty_alpha_mult) if not is_empty else Color(0.05, 0.06, 0.09, 0.45)
	var col_rim := Color(1.0, 0.78, 0.28, (0.75 if not is_empty else 0.28) * empty_alpha_mult)
	if is_aiming:
		col_rim = Color(1.0, 0.92, 0.5, 0.98)
	if is_stunned:
		col_rim = Color(1.0, 0.28, 0.5, 0.75)

	# 1. Outer Glow
	if not is_empty or is_aiming:
		var pulse := 0.5 + 0.5 * sin(_anim_time * (8.0 if is_aiming else 2.8))
		draw_circle(center, radius + (5.0 if is_aiming else 3.5 * pulse), col_glow)

	# 2. Main Cavern Disc
	draw_circle(center, radius, col_disc)
	draw_circle(center, radius * 0.78, Color(col_rim, 0.10 * empty_alpha_mult))

	# 3. Border Rim
	draw_arc(center, radius, 0.0, TAU, 36, col_rim, 2.0 if is_aiming else 1.6)

	# If active aiming, draw rotating amber tick ring
	if is_aiming:
		var spin := _anim_time * 3.5
		for k in 6:
			var ang := spin + k * TAU / 6.0
			var p_tick := center + Vector2.from_angle(ang) * (radius - 2.5)
			draw_circle(p_tick, 1.8, Color(1.0, 0.95, 0.6))

	# 4. Stylized Pebble Icons (Smooth stone with skip arc & motion spark)
	var icon_col := Color(1.0, 0.88, 0.6, 0.9 * empty_alpha_mult) if not is_empty else Color(0.6, 0.65, 0.75, 0.25)
	if is_aiming:
		icon_col = Color.WHITE
	if is_stunned:
		icon_col = Color(1.0, 0.45, 0.6, 0.45)

	_draw_pebble_icon(center, icon_col, is_empty)

	# 5. Pebble Count Badge (prominent top-right notch badge breaking the circle silhouette)
	var badge_pos := center + Vector2(25.0, -23.0)
	var badge_bg := Color(0.12, 0.09, 0.03, 0.98 * empty_alpha_mult) if not is_empty else Color(0.06, 0.08, 0.11, 0.85)
	var badge_border := col_rim
	if _empty_flash > 0.01:
		badge_bg = badge_bg.lerp(Color(0.48, 0.05, 0.08, 0.98), _empty_flash)
		badge_border = badge_border.lerp(Color(1.0, 0.35, 0.45, 1.0), _empty_flash)

	# Dark backing disc to punch out the main button rim underneath
	draw_circle(badge_pos, 11.5, Color(0.015, 0.025, 0.04, 0.98))
	draw_circle(badge_pos, 10.0, badge_bg)
	draw_arc(badge_pos, 10.0, 0.0, TAU, 24, badge_border, 1.6)

	var count_str := str(pebbles_left)
	var num_col := Color(1.0, 0.96, 0.82) if not is_empty else Color(0.65, 0.72, 0.82, 0.45)
	draw_string(ThemeDB.fallback_font, badge_pos + Vector2(-9.0, 4.0), count_str, HORIZONTAL_ALIGNMENT_CENTER, 18, 11, num_col)

	# 6. Micro Label Below
	var label_text := "STUNNED" if is_stunned else ("AIMING..." if is_aiming else ("EMPTY" if is_empty else "PEBBLE"))
	var label_col := col_rim
	if is_stunned:
		label_col = Color(1.0, 0.38, 0.55, 0.85)
	elif is_empty:
		label_col = Color(0.55, 0.62, 0.7, 0.35)

	draw_string(ThemeDB.fallback_font, Vector2(0.0, 84.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 10, label_col)
	if not GameState.is_touch_or_mobile():
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 96.0), "[E / AIM]", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 8, Color(label_col, 0.45 * empty_alpha_mult))


func _draw_pebble_icon(center: Vector2, col: Color, is_empty: bool) -> void:
	Icons.draw_pebble(self, center, col, is_empty)
