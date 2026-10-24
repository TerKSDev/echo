extends CanvasLayer

@onready var player: Node2D = get_node_or_null("../Player")

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
		if GameState.sneak_hold_mode:
			$SneakBtn.button_down.connect(func():
				player.sneaking = true
				player.queue_redraw()
			)
			$SneakBtn.button_up.connect(func():
				player.sneaking = false
				player.queue_redraw()
			)
		else:
			$SneakBtn.pressed.connect(player.toggle_sneak)
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

func set_gameplay_buttons_visible(show: bool) -> void:
	if has_node("PauseBtn"):
		$PauseBtn.visible = show
	if has_node("SneakBtn"):
		$SneakBtn.visible = show
	if has_node("SoundBtn"):
		$SoundBtn.visible = show
	if has_node("PebbleBtn"):
		$PebbleBtn.visible = show
	if has_node("MicIndicator"):
		$MicIndicator.visible = show
	if _sector_badge != null:
		_sector_badge.visible = show


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


var _debrief_modal: DebriefModal = null

func _get_or_create_debrief() -> DebriefModal:
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


# Grand campaign victory celebration when conquering Depth 13
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

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.05, 0.09, 0.94)
	victory_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460.0, 360.0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var tag := Label.new()
	tag.text = "◈   T H E   L I G H T   R E T U R N S   ◈"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35, 0.9))
	tag.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tag)

	var title := Label.new()
	title.text = "SURFACE REACHED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.9, 0.55, 0.15, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(260.0, 2.0)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sep.color = Color(1.0, 0.78, 0.3, 0.75)
	vbox.add_child(sep)

	var desc := Label.new()
	desc.text = "You kept your calm and stayed silent in the pitch-black abyss.\nGuided only by acoustic echoes across 13 subterranean sectors,\nyou silenced every terror and emerged back into the sun."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 0.88))
	desc.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	var replay_btn := Button.new()
	replay_btn.custom_minimum_size = Vector2(160.0, 44.0)
	replay_btn.text = "REPLAY %s" % GameState.get_level_name(13)
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
	_sector_badge.text = "◈  SECTOR"
	add_child(_sector_badge)


# Atmospheric fade-from-black + sonar title banner on level entry
func play_level_intro(title_text: String, subtitle_text: String = "Listen closely. Stay unseen.") -> void:
	set_gameplay_buttons_visible(true)
	if _sector_badge != null:
		_sector_badge.text = "◈  " + title_text
	# 1. Fullscreen abyss curtain fading out smoothly
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.color = Color(0.0, 0.015, 0.035, 1.0)
	add_child(curtain)

	var c_tw := create_tween()
	c_tw.tween_property(curtain, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_callback(curtain.queue_free)

	# 2. Floating sonar sector banner (non-blocking)
	var banner := VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 155.0
	banner.offset_left = -220.0
	banner.offset_right = 220.0
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", 6)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	add_child(banner)

	var tag := Label.new()
	tag.text = "((   A C O U S T I C   D E S C E N T   ))"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_color_override("font_color", Color(0.38, 0.85, 1.0, 0.82))
	tag.add_theme_font_size_override("font_size", 11)
	banner.add_child(tag)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.45, 0.82, 0.65))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_font_size_override("font_size", 32)
	banner.add_child(title_lbl)

	var line_holder := CenterContainer.new()
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
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.84, 0.96, 0.8))
	sub_lbl.add_theme_font_size_override("font_size", 13)
	banner.add_child(sub_lbl)

	var b_tw := create_tween()
	b_tw.set_parallel(true)
	b_tw.tween_property(banner, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(banner, "offset_top", 138.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(scan_line, "custom_minimum_size:x", 240.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var out_tw := create_tween()
	out_tw.tween_interval(1.65)
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
