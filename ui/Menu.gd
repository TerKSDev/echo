extends Control

const MIX_RATE := 22050
const TOTAL_LEVEL_COUNT := 20

@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var title_label: Label = $Content/HeaderBox/Title
@onready var touch_cue: Label = $Content/StartCue/TouchToStart
@onready var credits_button: Button = $Content/CreditsButton
@onready var touch_area: Button = $TouchArea

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

# Modal overlay nodes
var _modal_root: Control
var _modal_dimmer: ColorRect
var _modal_panel: PanelContainer
var _modal_title: Label
var _modal_subtitle: Label
var _modal_body: VBoxContainer
var _is_modal_open := false

# Procedural UI & BGM audio
const BGM_SCALE: Array[float] = [0.75, 1.0, 1.125, 1.2, 1.333, 1.5, 1.6, 1.8, 2.0]
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_start: AudioStreamWAV
var _wav_bgm_note: AudioStreamWAV
var _wav_bgm_droplet: AudioStreamWAV
var _bgm_pad_player: AudioStreamPlayer
var _bgm_note_timer := 1.2
var _bgm_drop_timer := 2.8
var _bgm_note_step := 0


func _ready() -> void:
	_build_ui_audio()
	_setup_menu_bgm()
	_init_spores()
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	_wire_button_Juice(credits_button)
	credits_button.pressed.connect(_on_credits_pressed)

	if touch_area != null:
		touch_area.pressed.connect(_on_touch_area_pressed)

	_build_modal_shell()


func _process(delta: float) -> void:
	_time += delta
	_process_menu_bgm(delta)

	# Gentle breathing glow on the main title
	if title_label != null:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
		title_label.modulate = Color(1.0, 1.0, 1.0, 0.88 + 0.12 * pulse)

	# Gentle breathing glow on the "TOUCH TO START" prompt (TOS style)
	if touch_cue != null and not _descending:
		var cue_pulse: float = 0.5 + 0.5 * sin(_time * 3.2)
		touch_cue.modulate = Color(1.0, 1.0, 1.0, 0.4 + 0.6 * cue_pulse)

	# Periodic ambient sonar wave - low frequency, random position, faint color
	_ambient_wave_timer -= delta
	if _ambient_wave_timer <= 0.0:
		_ambient_wave_timer = randf_range(5.2, 8.8)
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		var rand_pos := Vector2(
			randf_range(w_w * 0.18, w_w * 0.82),
			randf_range(w_h * 0.22, w_h * 0.76)
		)
		var rand_r: float = randf_range(160.0, 220.0)
		_ripples.append({"pos": rand_pos, "age": 0.0, "max_r": rand_r, "alpha": 0.20})

	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples = _ripples.filter(func(r): return float(r["age"]) < 2.0)

	for s in _spores:
		var pos: Vector2 = s["pos"]
		pos.y -= float(s["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(s["phase"])) * 12.0 * delta
		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))
		s["pos"] = pos

	sonar_backdrop.queue_redraw()


func _on_touch_area_pressed() -> void:
	var click_pos := get_viewport().get_mouse_position()
	_on_screen_tapped(click_pos)


func _gui_input(event: InputEvent) -> void:
	if _is_modal_open or _descending:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_on_screen_tapped(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if _is_modal_open:
		if event.is_action_pressed("ui_cancel"):
			_close_modal()
			get_viewport().set_input_as_handled()
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_on_screen_tapped(event.position)
		get_viewport().set_input_as_handled()


func _on_screen_tapped(tap_pos: Vector2) -> void:
	if _is_modal_open or _descending:
		return
	# Standard clean sound wave ripple expanding across the screen
	_ripples.append({
		"pos": tap_pos,
		"age": 0.0,
		"dur": 1.4,
		"max_r": 220.0,
		"alpha": 0.65,
	})
	_start_game_sequence()


# --- Ambient Sonar & Bioluminescent Backdrop ---------------------------------

func _init_spores() -> void:
	for i in 26:
		_spores.append({
			"pos": Vector2(randf_range(40.0, 680.0), randf_range(40.0, 1200.0)),
			"r": randf_range(1.2, 2.8),
			"speed": randf_range(12.0, 28.0),
			"phase": randf() * TAU,
		})


func _draw_sonar_backdrop() -> void:
	for s in _spores:
		var pos: Vector2 = s["pos"]
		var r: float = float(s["r"])
		var twinkle: float = 0.35 + 0.35 * sin(_time * 2.5 + float(s["phase"]))
		sonar_backdrop.draw_circle(pos, r * 2.4, Color(0.2, 0.75, 1.0, twinkle * 0.14))
		sonar_backdrop.draw_circle(pos, r, Color(0.55, 0.92, 1.0, twinkle * 0.75))

	for r in _ripples:
		var dur: float = float(r.get("dur", 2.0))
		var prog: float = clampf(float(r["age"]) / dur, 0.0, 1.0)
		var rad: float = prog * float(r["max_r"])
		var a: float = (1.0 - prog) * float(r.get("alpha", 0.45))
		sonar_backdrop.draw_arc(r["pos"], rad, 0.0, TAU, 64, Color(0.35, 0.88, 1.0, a), 1.8)


func _wire_button_Juice(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		_play_ui_sound(_wav_hover, -14.0, randf_range(0.98, 1.04))
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	btn.button_down.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.06)
	)
	btn.button_up.connect(func():
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.02, 1.02), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


# --- Button Actions ----------------------------------------------------------

var _descending := false

func _start_game_sequence() -> void:
	if _descending or _is_modal_open:
		return
	_descending = true
	_play_ui_sound(_wav_start, -2.5, 1.0)
	Input.vibrate_handheld(45)

	# Responsive feedback on Touch Cue:
	# Flash bright cyan upon click, then pulse and gently fade out over ~0.8s
	if touch_cue != null:
		var cue_tw := create_tween()
		cue_tw.tween_property(touch_cue, "modulate", Color(1.8, 2.3, 2.8, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		cue_tw.tween_property(touch_cue, "modulate", Color(0.4, 0.85, 1.0, 0.85), 0.25).set_trans(Tween.TRANS_SINE)
		cue_tw.tween_property(touch_cue, "modulate", Color(1.4, 2.0, 2.6, 1.0), 0.16).set_trans(Tween.TRANS_SINE)
		cue_tw.tween_property(touch_cue, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Smooth black curtain transition into Level Select with ~1.0s delay
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color.BLACK
	curtain.modulate.a = 0.0
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain.top_level = true
	curtain.z_index = 4096
	get_tree().root.add_child(curtain)

	var c_tw := curtain.create_tween()
	# Wait ~0.75s so the sound wave ripples out, chime resonates, and feedback is fully seen
	c_tw.tween_interval(0.75)
	# Smoothly fade to black over 0.35s (total elapsed time ≈ 1.1s)
	c_tw.tween_property(curtain, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_callback(func():
		get_tree().change_scene_to_file("res://ui/level_select.tscn")
		var fade_in := curtain.create_tween()
		fade_in.tween_interval(0.08)
		fade_in.tween_property(curtain, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(curtain.queue_free)
	)


func _on_start_pressed() -> void:
	_start_game_sequence()


func _on_credits_pressed() -> void:
	_open_modal("CREDITS", "ECHO: STAY SILENT")

	var desc := Label.new()
	desc.text = "An atmospheric acoustic stealth survival experience.\nNavigate the abyss using only sound waves—where every echo illuminates the path, yet beckons what lurks in the dark."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.72, 0.86, 0.98, 0.9))
	desc.add_theme_font_size_override("font_size", 13)
	_modal_body.add_child(desc)

	_add_divider()
	_add_guide_row(Color(0.38, 0.88, 1.0), "GAME DESIGN", "Team ECHO")
	_add_guide_row(Color(0.38, 0.88, 1.0), "SYSTEMS & AI", "Team ECHO")
	_add_guide_row(Color(0.38, 0.88, 1.0), "LEVEL DESIGN", "20 Cavern Sectors + SP by Team")
	_add_guide_row(Color(0.38, 0.88, 1.0), "AUDIO ENGINE", "Procedural Acoustic Synthesizer")


# --- Reusable Frosted-Glass Modal System -------------------------------------

func _build_modal_shell() -> void:
	_modal_root = Control.new()
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.visible = false
	_modal_root.modulate.a = 0.0
	add_child(_modal_root)

	_modal_dimmer = ColorRect.new()
	_modal_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_dimmer.color = Color(0.0, 0.02, 0.05, 0.74)
	_modal_dimmer.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			_close_modal()
	)
	_modal_root.add_child(_modal_dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(440, 0)
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 26.0
	card_style.content_margin_top = 22.0
	card_style.content_margin_right = 26.0
	card_style.content_margin_bottom = 24.0
	card_style.bg_color = Color(0.04, 0.11, 0.2, 0.95)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.28, 0.6, 0.88, 0.85)
	card_style.set_corner_radius_all(18)
	card_style.shadow_color = Color(0.08, 0.38, 0.72, 0.35)
	card_style.shadow_size = 14
	_modal_panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(_modal_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	_modal_panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	_modal_title = Label.new()
	_modal_title.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	_modal_title.add_theme_font_size_override("font_size", 24)
	title_box.add_child(_modal_title)

	_modal_subtitle = Label.new()
	_modal_subtitle.add_theme_color_override("font_color", Color(0.45, 0.76, 1.0, 0.78))
	_modal_subtitle.add_theme_font_size_override("font_size", 11)
	title_box.add_child(_modal_subtitle)

	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(38, 38)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "✕"
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.05, 0.14, 0.24, 0.8)
	close_normal.set_border_width_all(1)
	close_normal.border_color = Color(0.28, 0.56, 0.82, 0.75)
	close_normal.set_corner_radius_all(19)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.12, 0.28, 0.44, 0.95)
	close_hover.set_border_width_all(1)
	close_hover.border_color = Color(0.48, 0.82, 1.0, 1.0)
	close_hover.set_corner_radius_all(19)
	close_btn.add_theme_stylebox_override("normal", close_normal)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.pressed.connect(_close_modal)
	header.add_child(close_btn)

	var top_div := ColorRect.new()
	top_div.custom_minimum_size = Vector2(0, 1)
	top_div.color = Color(0.2, 0.48, 0.74, 0.45)
	outer_vbox.add_child(top_div)

	_modal_body = VBoxContainer.new()
	_modal_body.add_theme_constant_override("separation", 11)
	outer_vbox.add_child(_modal_body)


func _open_modal(title_text: String, subtitle_text: String) -> void:
	for child in _modal_body.get_children():
		child.queue_free()

	_modal_title.text = title_text
	_modal_subtitle.text = subtitle_text
	_is_modal_open = true
	_modal_root.visible = true

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_modal_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_modal_panel.scale = Vector2(0.93, 0.93)
	_modal_panel.pivot_offset = Vector2(220.0, 200.0)
	tw.tween_property(_modal_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_modal() -> void:
	if not _is_modal_open:
		return
	_play_ui_sound(_wav_click, -8.0, 0.9)
	_is_modal_open = false
	var tw := create_tween()
	tw.tween_property(_modal_root, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_modal_root.visible = false


func _add_section_header(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.45, 0.82, 1.0, 0.92))
	lbl.add_theme_font_size_override("font_size", 12)
	_modal_body.add_child(lbl)


func _add_divider() -> void:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color = Color(0.2, 0.45, 0.7, 0.35)
	_modal_body.add_child(d)


func _add_guide_row(dot_color: Color, label_text: String, desc_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = dot_color
	row.add_child(dot)

	var key_lbl := Label.new()
	key_lbl.custom_minimum_size = Vector2(102, 0)
	key_lbl.text = label_text
	key_lbl.add_theme_color_override("font_color", dot_color.lerp(Color.WHITE, 0.35))
	key_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_lbl.text = desc_text
	val_lbl.add_theme_color_override("font_color", Color(0.78, 0.88, 0.96, 0.9))
	val_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(val_lbl)

	_modal_body.add_child(row)


# --- Procedural UI & BGM Audio -----------------------------------------------

func _setup_menu_bgm() -> void:
	_wav_bgm_note = SfxManager.get_menu_bgm_note()
	_wav_bgm_droplet = SfxManager.get_menu_bgm_droplet()

	_bgm_pad_player = AudioStreamPlayer.new()
	_bgm_pad_player.stream = SfxManager.get_menu_bgm_pad()
	_bgm_pad_player.bus = &"Master"
	_bgm_pad_player.volume_db = -28.0
	add_child(_bgm_pad_player)
	_bgm_pad_player.play()

	var tw := create_tween()
	tw.tween_property(_bgm_pad_player, "volume_db", -7.5, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process_menu_bgm(delta: float) -> void:
	if _bgm_pad_player != null:
		_bgm_pad_player.volume_db = lerpf(_bgm_pad_player.volume_db, -7.5, clampf(delta * 4.0, 0.0, 1.0))

	# Generative crystalline echo notes (A minor / Dorian motif)
	_bgm_note_timer -= delta
	if _bgm_note_timer <= 0.0:
		_bgm_note_timer = randf_range(2.8, 4.8)
		var motif_indices: Array[int] = [1, 4, 3, 1, 5, 3, 2, 0, 1, 6, 4, 3]
		var idx: int = motif_indices[_bgm_note_step % motif_indices.size()]
		_bgm_note_step += 1
		var pitch: float = BGM_SCALE[idx]
		_play_ui_sound(_wav_bgm_note, randf_range(-11.5, -8.5), pitch)

		# Occasional soft harmonic answer note
		if randf() < 0.45:
			var ans_pitch: float = BGM_SCALE[(idx + 2) % BGM_SCALE.size()]
			get_tree().create_timer(0.44).timeout.connect(func():
				if is_inside_tree():
					_play_ui_sound(_wav_bgm_note, -13.5, ans_pitch)
			)

	# Subterranean cavern water droplets
	_bgm_drop_timer -= delta
	if _bgm_drop_timer <= 0.0:
		_bgm_drop_timer = randf_range(4.2, 7.8)
		_play_ui_sound(_wav_bgm_droplet, randf_range(-13.0, -9.5), randf_range(0.84, 1.26))
		if size.x > 0.0 and size.y > 0.0:
			var drop_pos := Vector2(randf_range(size.x * 0.15, size.x * 0.85), randf_range(size.y * 0.2, size.y * 0.85))
			_ripples.append({"pos": drop_pos, "age": 0.0, "max_r": 120.0, "alpha": 0.26})


func _build_ui_audio() -> void:
	_wav_click = _synth_tone(620.0, 920.0, 0.14)
	_wav_hover = _synth_tone(480.0, 540.0, 0.06)
	_wav_start = _synth_start_chime()


func _synth_start_chime() -> AudioStreamWAV:
	var dur := 0.85
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.008, 1.0) * exp(-t * 3.8)
		p1 += TAU * 330.0 / MIX_RATE
		p2 += TAU * 495.0 / MIX_RATE
		p3 += TAU * 660.0 / MIX_RATE
		var s: float = (sin(p1) * 0.42 + sin(p2) * 0.35 + sin(p3) * 0.23) * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _synth_tone(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.004, 1.0) * exp(-t * 24.0)
		var freq: float = lerpf(f_start, f_end, t / dur)
		phase += TAU * freq / MIX_RATE
		var s: float = clampf(sin(phase) * env * 0.7, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _play_ui_sound(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = &"Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
