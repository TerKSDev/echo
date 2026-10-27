extends CanvasLayer

const DebriefModal = preload("res://ui/modals/DebriefModal.gd")

@onready var player: Node2D = get_node_or_null("../Player")
@onready var story_overlay: Control = get_node_or_null("StoryOverlay")

var _base_inner_radius := 0.42
var _sector_badge: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sector_badge()
	if has_node("Vignette"):
		$Vignette.visible = GameState.vignette_enabled
	var mat := _vignette_material()
	if mat != null:
		mat.set_shader_parameter("vignette_color", Color(0.01, 0.035, 0.07, 0.7))
		mat.set_shader_parameter("inner_radius", _base_inner_radius)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player != null:
		$SoundBtn.button_down.connect(player.start_charge)
		$SoundBtn.button_up.connect(player.release_charge)
		$SneakBtn.button_down.connect(func():
			if not player.can_sneak:
				return
			if GameState.sneak_hold_mode:
				player.sneaking = true
				player.queue_redraw()
			else:
				player.toggle_sneak()
		)
		$SneakBtn.button_up.connect(func():
			if GameState.sneak_hold_mode:
				player.sneaking = false
				player.queue_redraw()
		)
		if player.has_node("MicInput"):
			var mic = player.get_node("MicInput")
			if mic != null and mic.has_signal("voice_detected"):
				mic.voice_detected.connect(_on_voice_detected)

	if has_node("PauseBtn") and has_node("SettingsModal"):
		$PauseBtn.pressed.connect($SettingsModal.open)

	_setup_sound_indicator_canvas()

func _on_voice_detected(_loudness: float) -> void:
	if has_node("MicIndicator"):
		$MicIndicator.pulse_flash()

# Vignette tightens on every heartbeat; stronger when more threatened
func pulse_vignette(threat: float) -> void:
	if threat < 0.2:
		return
	var mat := _vignette_material()
	if mat == null:
		return
	var pulse_r := clampf(_base_inner_radius - 0.12 * threat, 0.18, _base_inner_radius)
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/inner_radius", pulse_r, 0.08)
	tw.tween_property(mat, "shader_parameter/inner_radius", _base_inner_radius, 0.28)

# Crimson flash when the player dies
func flash_death() -> void:
	var mat := _vignette_material()
	if mat == null:
		return
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.65, 0.05, 0.08, 0.95), 0.08)
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.28, 0.02, 0.04, 0.85), 0.6)

# Momentary crimson alert flash during surprise danger / chase triggers
func flash_threat(hold_dur: float = 0.4) -> void:
	var mat := _vignette_material()
	if mat == null:
		return
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.55, 0.05, 0.08, 0.90), 0.1)
	tw.tween_interval(hold_dur)
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.01, 0.035, 0.07, 0.7), 0.6)

# Reset vignette color back to calm abyssal blue-black
func reset_vignette(fade_duration: float = 0.5) -> void:
	var mat := _vignette_material()
	if mat == null:
		return
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.01, 0.035, 0.07, 0.7), fade_duration)

func set_gameplay_buttons_visible(buttons_visible: bool) -> void:
	if has_node("PauseBtn"):
		$PauseBtn.visible = buttons_visible
	if has_node("SneakBtn"):
		$SneakBtn.visible = buttons_visible
	if has_node("SoundBtn"):
		$SoundBtn.visible = buttons_visible
	if has_node("PebbleBtn"):
		$PebbleBtn.visible = buttons_visible
	if has_node("MicIndicator"):
		$MicIndicator.visible = buttons_visible
	if _sector_badge != null:
		_sector_badge.visible = buttons_visible
	if not buttons_visible:
		hide_tutorial_callout()


var _tutorial_callout: PanelContainer = null
var _tutorial_pointer: Control = null


func show_tutorial_callout(pos_type: int, title: String, subtitle: String = "") -> void:
	hide_tutorial_callout()

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_callout = panel

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.07, 0.14, 0.94)
	style.border_color = Color(0.38, 0.88, 1.0, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0.08, 0.45, 0.8, 0.35)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title_lbl)

	if subtitle != "":
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_lbl.custom_minimum_size = Vector2(212.0, 0.0)
		sub_lbl.add_theme_color_override("font_color", Color(0.48, 0.82, 0.98, 0.85))
		sub_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(sub_lbl)

	add_child(panel)

	# Dedicated pointer arrow dynamically locked to target button's physical center
	if pos_type == 0 or pos_type == 1:
		panel.custom_minimum_size = Vector2(240.0, 0.0)
		var pointer := Control.new()
		pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tutorial_pointer = pointer
		panel.add_child(pointer)

		pointer.draw.connect(func():
			var target_center_x: float = 0.0
			if pos_type == 0:
				var btn := get_node_or_null("SoundBtn") as Control
				if btn != null:
					target_center_x = btn.global_position.x + btn.size.x * 0.5
				else:
					target_center_x = get_viewport().get_visible_rect().size.x - 95.0
			elif pos_type == 1:
				var btn := get_node_or_null("SneakBtn") as Control
				if btn != null:
					target_center_x = btn.global_position.x + btn.size.x * 0.5
				else:
					target_center_x = 95.0

			# Dynamically compute arrow X so it is always 100% dead center on the button
			var arrow_x: float = target_center_x - pointer.global_position.x
			arrow_x = clampf(arrow_x, 20.0, panel.size.x - 20.0)

			var py: float = panel.size.y
			# Subtle living bob animation (floats up and down by 2px in the gap)
			var bob: float = sin(Time.get_ticks_msec() * 0.005) * 2.0
			var tip_y: float = py + 16.0 + bob
			var top_y: float = py + 7.0 + bob
			var stem_top: float = py + 2.0

			# 1. Soft glowing bloom pass
			var glow_col := Color(0.12, 0.55, 0.9, 0.38)
			pointer.draw_line(Vector2(arrow_x, stem_top), Vector2(arrow_x, tip_y), glow_col, 4.0)
			pointer.draw_line(Vector2(arrow_x - 7.0, top_y), Vector2(arrow_x, tip_y), glow_col, 3.5)
			pointer.draw_line(Vector2(arrow_x, tip_y), Vector2(arrow_x + 7.0, top_y), glow_col, 3.5)

			# 2. Crisp neon cyan directional HUD arrow (stem + downward chevron)
			var core_col := Color(0.40, 0.92, 1.0, 0.95)
			pointer.draw_line(Vector2(arrow_x, stem_top), Vector2(arrow_x, tip_y), core_col, 1.8)
			pointer.draw_line(Vector2(arrow_x - 7.0, top_y), Vector2(arrow_x, tip_y), core_col, 2.0)
			pointer.draw_line(Vector2(arrow_x, tip_y), Vector2(arrow_x + 7.0, top_y), core_col, 2.0)

			# 3. Bright white luminous tip beacon
			pointer.draw_circle(Vector2(arrow_x, tip_y), 1.8, Color(0.95, 0.98, 1.0, 1.0))
		)
		panel.resized.connect(pointer.queue_redraw)

	match pos_type:
		0: # BOTTOM_RIGHT (above SoundBtn, elevated with ~50px clearance)
			panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			panel.offset_left = -260.0
			panel.offset_right = -20.0
			panel.offset_top = -300.0
			panel.offset_bottom = -236.0
		1: # BOTTOM_LEFT (above SneakBtn, elevated with ~50px clearance)
			panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			panel.offset_left = 20.0
			panel.offset_right = 260.0
			panel.offset_top = -300.0
			panel.offset_bottom = -236.0
		_: # BOTTOM_CENTER (Movement)
			panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			panel.offset_left = -140.0
			panel.offset_right = 140.0
			panel.offset_top = -135.0
			panel.offset_bottom = -75.0

	panel.modulate.a = 0.0
	var orig_top: float = panel.offset_top
	var orig_bottom: float = panel.offset_bottom
	panel.offset_top -= 8.0
	panel.offset_bottom -= 8.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "offset_top", orig_top, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "offset_bottom", orig_bottom, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_tutorial_callout() -> void:
	_tutorial_pointer = null
	if _tutorial_callout != null and is_instance_valid(_tutorial_callout):
		var target := _tutorial_callout
		_tutorial_callout = null
		var tw := create_tween()
		tw.tween_property(target, "modulate:a", 0.0, 0.18)
		tw.tween_callback(target.queue_free)


class WakeUpOverlay extends Control:
	var eyelid_open: float = 0.0 # 0.0 = fully closed, 1.0 = fully open

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 1.0 or h <= 1.0:
			return

		if eyelid_open <= 0.0001:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.012, 0.022, 1.0))
			return

		if eyelid_open >= 1.0 and modulate.a <= 0.001:
			return

		var mid_x: float = w * 0.5
		var mid_y: float = h * 0.5

		var p: float = clampf(eyelid_open, 0.0, 1.0)
		var base_reach: float = (h * 0.55) * p
		var corner_clear: float = (h * 0.70) * pow(p, 2.5)

		var segs := 36
		var top_pts := PackedVector2Array()
		var btm_pts := PackedVector2Array()

		top_pts.append(Vector2(0.0, -10.0))
		top_pts.append(Vector2(w, -10.0))
		btm_pts.append(Vector2(0.0, h + 10.0))
		btm_pts.append(Vector2(w, h + 10.0))

		var top_curve := PackedVector2Array()
		var btm_curve := PackedVector2Array()

		for i in range(segs + 1):
			var frac := float(i) / float(segs)
			var x := frac * w
			var nx := (x - mid_x) / mid_x
			var arch := 1.0 - pow(absf(nx), 1.8) * 0.65
			var half_open: float = maxf(0.0, base_reach * arch + corner_clear)

			var ty: float = mid_y - half_open
			var by: float = mid_y + half_open
			top_curve.append(Vector2(x, ty))
			btm_curve.append(Vector2(x, by))

		for i in range(segs, -1, -1):
			top_pts.append(top_curve[i])
			btm_pts.append(btm_curve[i])

		var eyelid_col := Color(0.005, 0.012, 0.022, 1.0)
		draw_colored_polygon(top_pts, eyelid_col)
		draw_colored_polygon(btm_pts, eyelid_col)

		# Soft organic eyelid shadow along eyelash fringe
		if p > 0.02 and p < 0.98:
			var fringe_a: float = clampf(1.0 - p * 0.6, 0.0, 1.0)
			draw_polyline(top_curve, Color(0.005, 0.012, 0.022, 0.60 * fringe_a), 8.0)
			draw_polyline(btm_curve, Color(0.005, 0.012, 0.022, 0.60 * fringe_a), 8.0)
			draw_polyline(top_curve, Color(0.005, 0.012, 0.022, 0.28 * fringe_a), 20.0)
			draw_polyline(btm_curve, Color(0.005, 0.012, 0.022, 0.28 * fringe_a), 20.0)


func play_wake_up_sequence(player_node: Node2D, sfx_mgr: SfxManager, on_complete: Callable) -> void:
	var overlay := WakeUpOverlay.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 85
	add_child(overlay)

	var cam: Camera2D = null
	if player_node != null and is_instance_valid(player_node):
		player_node.set("wake_up_anim", true)
		if "_entry_timer" in player_node:
			player_node._entry_timer = 20.0 # Keep steady camera for the sequence and subsequent pause
		cam = player_node.get_node_or_null("PlayerCamera") as Camera2D
		player_node.modulate.a = 0.18 # Faint dormant spark in the dark
		player_node.scale = Vector2(0.65, 0.65) # Compact uniform ember, circular
		if cam != null:
			cam.zoom = Vector2(1.75, 1.75) # Close-up view
			cam.rotation = 0.0

	overlay.eyelid_open = 0.0
	overlay.modulate.a = 1.0

	var tw := create_tween()

	# 1. Total silence in the pitch-black void, first muffled heartbeat
	tw.tween_interval(0.6)
	if sfx_mgr != null:
		tw.tween_callback(func(): sfx_mgr.play_single_heartbeat(-8.0, 0.85))

	# The dormant spark stirs faintly in response
	if player_node != null:
		tw.tween_property(player_node, "modulate:a", 0.38, 0.28).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(player_node, "scale", Vector2(0.72, 0.72), 0.28).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_property(player_node, "modulate:a", 0.22, 0.35).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(player_node, "scale", Vector2(0.65, 0.65), 0.35).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_interval(0.4)

	# 2. First struggling blink: eyelids crack open slowly (~0.35)
	tw.tween_interval(0.35)
	tw.tween_property(overlay, "eyelid_open", 0.35, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if player_node != null:
		tw.parallel().tween_property(player_node, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(player_node, "scale", Vector2(0.75, 0.75), 1.1).set_trans(Tween.TRANS_SINE)
	if cam != null:
		tw.parallel().tween_property(cam, "zoom", Vector2(1.65, 1.65), 1.1).set_trans(Tween.TRANS_SINE)

	# Heavy fatigue drags eyelids back shut into darkness
	tw.tween_interval(0.2)
	tw.tween_property(overlay, "eyelid_open", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if player_node != null:
		tw.parallel().tween_property(player_node, "modulate:a", 0.25, 0.85).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(player_node, "scale", Vector2(0.68, 0.68), 0.85).set_trans(Tween.TRANS_SINE)

	# 3. Second heartbeat: clearer, stronger thump-thump
	tw.tween_interval(0.45)
	if sfx_mgr != null:
		tw.tween_callback(func(): sfx_mgr.play_single_heartbeat(-3.5, 0.98))

	# 4. Second awakening: eyelids force open wider (~0.75), light floods in
	tw.tween_interval(0.25)
	tw.tween_property(overlay, "eyelid_open", 0.75, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if player_node != null:
		tw.parallel().tween_property(player_node, "scale", Vector2(0.88, 0.88), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(player_node, "modulate:a", 0.78, 1.1).set_trans(Tween.TRANS_SINE)
	if cam != null:
		tw.parallel().tween_property(cam, "zoom", Vector2(1.35, 1.35), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Drowsy flutter fighting off the void
	tw.tween_interval(0.12)
	tw.tween_property(overlay, "eyelid_open", 0.58, 0.22).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(overlay, "eyelid_open", 0.85, 0.32).set_trans(Tween.TRANS_QUAD)

	# 5. Full awakening: eyelids glide completely open and off-screen, vitality restored
	tw.tween_property(overlay, "eyelid_open", 1.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(overlay, "modulate:a", 0.0, 0.75)
	if player_node != null:
		tw.parallel().tween_property(player_node, "scale", Vector2.ONE, 0.75).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(player_node, "modulate:a", 1.0, 0.75)
		tw.parallel().tween_callback(func():
			if sfx_mgr != null:
				sfx_mgr.play_level_intro()
			if "pulse_scale" in player_node:
				player_node.pulse_scale = 1.30
				var pt := create_tween()
				pt.tween_property(player_node, "pulse_scale", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
		)
	if cam != null:
		tw.parallel().tween_property(cam, "zoom", Vector2.ONE, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 6. Complete animation phase: clean up overlay & restore player animation state
	tw.tween_callback(func():
		overlay.queue_free()
		if player_node != null and is_instance_valid(player_node):
			player_node.set("wake_up_anim", false)
			if "_entry_timer" in player_node:
				player_node._entry_timer = 5.0 # Prevent idle zoom during the quiet pause
	)

	# 7. Cinematic breathing pause when fully awake: pause for 2.6s before entering story narration
	tw.tween_interval(2.6)

	tw.tween_callback(func():
		if on_complete.is_valid():
			on_complete.call()
	)


func show_death_screen(killer_type: int = -1) -> void:
	if has_node("SettingsModal") and $SettingsModal.visible:
		$SettingsModal.visible = false
	set_gameplay_buttons_visible(false)
	if has_node("DeathScreen"):
		$DeathScreen.open(killer_type)


# Smooth level exit dissolve transition before loading next depth
func play_level_exit_transition(on_complete: Callable) -> void:
	var sfx_mgr := get_node_or_null("../SfxManager") as SfxManager
	if sfx_mgr != null:
		sfx_mgr.play_level_exit()
	on_complete.call()


var _debrief_modal: Control = null

func _get_or_create_debrief() -> Control:
	if _debrief_modal == null or not is_instance_valid(_debrief_modal):
		_debrief_modal = DebriefModal.new()
		add_child(_debrief_modal)
	return _debrief_modal


func show_debrief(data: Dictionary, on_next: Callable, on_retry: Callable, on_select: Callable) -> void:
	if has_node("SettingsModal") and $SettingsModal.visible:
		$SettingsModal.visible = false
	set_gameplay_buttons_visible(false)
	var dm := _get_or_create_debrief()
	# Disconnect any prior connections to avoid stacking callbacks
	for c: Dictionary in dm.next_pressed.get_connections():
		dm.next_pressed.disconnect(c.callable)
	for c: Dictionary in dm.retry_pressed.get_connections():
		dm.retry_pressed.disconnect(c.callable)
	for c: Dictionary in dm.select_pressed.get_connections():
		dm.select_pressed.disconnect(c.callable)

	dm.next_pressed.connect(on_next)
	dm.retry_pressed.connect(on_retry)
	dm.select_pressed.connect(on_select)

	var sfx_mgr := get_node_or_null("../SfxManager") as SfxManager
	dm.show_debrief(data, sfx_mgr)


# Grand campaign victory celebration when conquering the finale
func show_victory_screen() -> void:
	if has_node("SettingsModal") and $SettingsModal.visible:
		$SettingsModal.visible = false
	set_gameplay_buttons_visible(false)

	var sfx_mgr := get_node_or_null("../SfxManager") as SfxManager
	if sfx_mgr != null:
		sfx_mgr.play_victory_fanfare()

	get_tree().paused = true

	var victory_root := Control.new()
	victory_root.process_mode = Node.PROCESS_MODE_ALWAYS
	victory_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_root.modulate.a = 0.0
	add_child(victory_root)

	var is_challenge: bool = GameState.current_mode == GameState.GameMode.CHALLENGE

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.02, 0.07, 0.96) if is_challenge else Color(0.02, 0.05, 0.09, 0.95)
	victory_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480.0, 380.0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var tag := Label.new()
	tag.text = "◈   T H E   F I N A L   E C H O   ◈" if is_challenge else "◈   T H E   L I G H T   R E T U R N S   ◈"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.75, 0.95) if is_challenge else Color(1.0, 0.82, 0.35, 0.95))
	tag.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tag)

	var title := Label.new()
	title.text = "ABYSS CONQUERED" if is_challenge else "SURFACE REACHED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.95, 1.0) if is_challenge else Color(1.0, 0.94, 0.8, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.65, 0.12, 0.45, 0.85) if is_challenge else Color(0.9, 0.55, 0.15, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(280.0, 2.0)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sep.color = Color(0.9, 0.35, 0.65, 0.85) if is_challenge else Color(1.0, 0.78, 0.3, 0.8)
	vbox.add_child(sep)

	var desc := Label.new()
	if is_challenge:
		desc.text = "You plunged into the absolute singularity of the dark: -9,999 Meters.\nThrough supreme mastery over sound and silence, you conquered the King Sector\nand revealed the timeless truth of the primordial echo."
	else:
		desc.text = "You kept your calm and stayed silent across 4,200 meters of the pitch-black abyss.\nGuided only by acoustic echoes across 20 perilous subterranean sectors,\nyou overcame every fear and emerged back into the warmth of the sun."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98, 0.92))
	desc.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	var replay_btn := Button.new()
	replay_btn.custom_minimum_size = Vector2(160.0, 44.0)
	replay_btn.text = "REPLAY FINALE"
	replay_btn.focus_mode = Control.FOCUS_NONE
	replay_btn.pressed.connect(func():
		GameState.restart_level()
	)
	actions.add_child(replay_btn)

	var menu_btn := Button.new()
	menu_btn.custom_minimum_size = Vector2(160.0, 44.0)
	menu_btn.text = "LEVEL SELECT"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func():
		GameState.go_to_level_select()
	)
	actions.add_child(menu_btn)

	var tw := create_tween()
	tw.tween_property(victory_root, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_sector_badge() -> void:
	_sector_badge = Label.new()
	_sector_badge.position = Vector2(38.0, 52.0)
	_sector_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sector_badge.add_theme_color_override("font_color", Color(0.45, 0.78, 0.98, 0.55))
	_sector_badge.add_theme_font_size_override("font_size", 12)
	_sector_badge.text = "◈  PROLOGUE • FIRST STEPS  (-4,200 M)"
	add_child(_sector_badge)


# Atmospheric fade-from-black + sonar title banner on level entry
func play_level_intro(title_text: String, subtitle_text: String = "Listen closely. Stay unseen.") -> void:
	set_gameplay_buttons_visible(true)

	var cur_lvl: int = GameState.current_level
	var is_challenge: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	var kicker_str: String = "((   A C O U S T I C   A S C E N T   ))"
	var badge_str: String = "◈  " + title_text

	if is_challenge:
		var c_idx := clampi(cur_lvl, 0, GameState.CHALLENGE_SECTORS.size() - 1)
		var raw_depth: String = str(GameState.CHALLENGE_SECTORS[c_idx]["depth"])
		if cur_lvl >= 20:
			kicker_str = "((   K I N G   S E C T O R   •   D E P T H   %s   •   S I N G U L A R I T Y   ))" % raw_depth
			badge_str = "👑  KING SECTOR • %s  (%s)" % [title_text, raw_depth]
		else:
			kicker_str = "((   A B Y S S   R I F T   %02d   •   D E P T H   %s   •   D E S C E N T   ))" % [cur_lvl + 1, raw_depth]
			badge_str = "◈  ABYSS %02d • %s  (%s)" % [cur_lvl + 1, title_text, raw_depth]
	else:
		if cur_lvl == 0:
			kicker_str = "((   P R O L O G U E   •   D E P T H   - 4 , 2 0 0   M   •   A W A K E N I N G   ))"
			badge_str = "◈  PROLOGUE • %s  (-4,200 M)" % title_text
		else:
			var s_idx := clampi(cur_lvl - 1, 0, GameState.STORY_SECTORS.size() - 1)
			var raw_depth: String = str(GameState.STORY_SECTORS[s_idx]["depth"])
			kicker_str = "((   S E C T O R   %02d   •   D E P T H   %s   •   A S C E N T   ))" % [cur_lvl, raw_depth]
			badge_str = "◈  SECTOR %02d • %s  (%s)" % [cur_lvl, title_text, raw_depth]

	if _sector_badge != null:
		_sector_badge.text = badge_str

	# 1. Fullscreen abyss curtain fading out smoothly
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.color = Color(0.0, 0.015, 0.035, 1.0)
	add_child(curtain)

	var c_tw := create_tween()
	c_tw.tween_property(curtain, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_callback(curtain.queue_free)

	# 2. Floating sonar sector banner (non-blocking, centered across the viewport)
	var banner := VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 36.0
	banner.offset_right = -36.0
	banner.offset_top = 160.0
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	add_child(banner)

	var tag := Label.new()
	tag.text = kicker_str
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35, 0.90) if (is_challenge and cur_lvl >= 20) else Color(0.38, 0.85, 1.0, 0.85))
	tag.add_theme_font_size_override("font_size", 11)
	banner.add_child(tag)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.45, 0.82, 0.65))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_font_size_override("font_size", 30)
	banner.add_child(title_lbl)

	var line_holder := CenterContainer.new()
	line_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(line_holder)

	var scan_line := ColorRect.new()
	scan_line.custom_minimum_size = Vector2(16.0, 2.0)
	scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan_line.color = Color(0.38, 0.9, 1.0, 0.85)
	line_holder.add_child(scan_line)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle_text
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 0.98, 0.85))
	sub_lbl.add_theme_font_size_override("font_size", 13)
	banner.add_child(sub_lbl)

	var b_tw := create_tween()
	b_tw.set_parallel(true)
	b_tw.tween_property(banner, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(banner, "offset_top", 140.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(scan_line, "custom_minimum_size:x", 280.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var out_tw := create_tween()
	out_tw.tween_interval(2.2)
	out_tw.tween_property(banner, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tw.tween_callback(banner.queue_free)

func _vignette_material() -> ShaderMaterial:
	var vig := get_node_or_null("Vignette") as ColorRect
	if vig == null:
		return null
	return vig.material as ShaderMaterial


# --- Off-screen Sound Direction Compass ---
var _indicator_canvas: Control
var _sound_indicators: Array[Dictionary] = []


func _setup_sound_indicator_canvas() -> void:
	_indicator_canvas = Control.new()
	_indicator_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_indicator_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_canvas.draw.connect(_draw_sound_indicators)
	add_child(_indicator_canvas)

	var sound_bus = get_node_or_null("../SoundBus")
	if sound_bus != null and sound_bus.has_signal("offscreen_sound_emitted"):
		sound_bus.offscreen_sound_emitted.connect(_on_offscreen_sound_emitted)


func _on_offscreen_sound_emitted(origin_pos: Vector2, color: Color) -> void:
	if not GameState.sound_indicator_enabled or player == null or not is_instance_valid(player) or not player.alive:
		return
	var diff: Vector2 = origin_pos - player.global_position
	if diff.length() < 160.0:
		return # Already on-screen / close
	var dir: Vector2 = diff.normalized()
	_sound_indicators.append({
		"dir": dir,
		"alpha": 1.0,
		"color": color
	})


func _process(delta: float) -> void:
	if _tutorial_pointer != null and is_instance_valid(_tutorial_pointer):
		_tutorial_pointer.queue_redraw()
	if not _sound_indicators.is_empty():
		for ind in _sound_indicators:
			ind["alpha"] = float(ind["alpha"]) - delta * 1.6
		_sound_indicators = _sound_indicators.filter(func(ind: Dictionary) -> bool:
			return float(ind["alpha"]) > 0.0
		)
		if _indicator_canvas != null and is_instance_valid(_indicator_canvas):
			_indicator_canvas.queue_redraw()


func _draw_sound_indicators() -> void:
	if _indicator_canvas == null or _sound_indicators.is_empty():
		return
	var vp_size := _indicator_canvas.size
	if vp_size.x <= 10.0 or vp_size.y <= 10.0:
		return
	var center := vp_size * 0.5
	var edge_r := minf(center.x, center.y) - 34.0

	for ind in _sound_indicators:
		var dir: Vector2 = ind["dir"]
		var alpha: float = float(ind["alpha"])
		var col: Color = ind["color"]
		var marker_pos := center + dir * edge_r
		var ang := dir.angle()

		# Outer glowing arc on edge
		var arc_col := Color(col.r, col.g, col.b, alpha * 0.85)
		_indicator_canvas.draw_arc(marker_pos, 18.0, ang - 0.75, ang + 0.75, 14, arc_col, 2.5)

		# Tip chevron triangle pointing outward
		var tip := marker_pos + dir * 6.0
		var p1 := marker_pos + dir.rotated(2.2) * 8.0
		var p2 := marker_pos + dir.rotated(-2.2) * 8.0
		_indicator_canvas.draw_colored_polygon(PackedVector2Array([tip, p1, p2]), Color(col.r, col.g, col.b, alpha * 0.95))
