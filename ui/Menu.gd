extends Control

const MIX_RATE := 22050
const TOTAL_LEVEL_COUNT := 20
const LEVEL_ZERO_PATH := "res://levels/level_0.tscn"
const LEVEL_SP_PATH := "res://levels/level_SP.tscn"

@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var title_label: Label = $Content/VBoxContainer/Title
@onready var start_button: Button = $Content/VBoxContainer/StartButton
@onready var settings_button: Button = $Content/VBoxContainer/SettingsButton
@onready var how_to_play_button: Button = $Content/VBoxContainer/HowToPlayButton
@onready var credits_button: Button = $Content/VBoxContainer/CreditsButton

var _time := 0.0
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
var _menu_mic: MicInput
var _menu_meter_canvas: Control
var _menu_calib_btn: Button

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

	var buttons: Array[Button] = [
		start_button,
		settings_button,
		how_to_play_button,
		credits_button,
	]
	for btn in buttons:
		_wire_button_Juice(btn)

	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	credits_button.pressed.connect(_on_credits_pressed)

	_build_modal_shell()


func _process(delta: float) -> void:
	_time += delta
	_process_menu_bgm(delta)

	# Gentle breathing glow on the main title
	if title_label != null:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
		title_label.modulate = Color(1.0, 1.0, 1.0, 0.88 + 0.12 * pulse)

	# Periodic ambient sonar wave behind the title
	if fmod(_time, 2.6) < delta:
		var center: Vector2 = size * Vector2(0.5, 0.34)
		_ripples.append({"pos": center, "age": 0.0, "max_r": 290.0, "alpha": 0.28})

	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples = _ripples.filter(func(r): return float(r["age"]) < 2.8)

	for s in _spores:
		var pos: Vector2 = s["pos"]
		pos.y -= float(s["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(s["phase"])) * 12.0 * delta
		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))
		s["pos"] = pos

	sonar_backdrop.queue_redraw()
	if _is_modal_open and _menu_meter_canvas != null and is_instance_valid(_menu_meter_canvas):
		_menu_meter_canvas.queue_redraw()
		if _menu_calib_btn != null and is_instance_valid(_menu_calib_btn) and _menu_mic != null:
			if _menu_mic.is_calibrating():
				_menu_calib_btn.text = "SAMPLING..."
				_menu_calib_btn.disabled = true
			else:
				_menu_calib_btn.text = "CALIBRATE ROOM"
				_menu_calib_btn.disabled = not GameState.mic_enabled


func _gui_input(event: InputEvent) -> void:
	if _is_modal_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_ripples.append({"pos": event.position, "age": 0.0, "max_r": 180.0, "alpha": 0.45})
	elif event is InputEventScreenTouch and event.pressed:
		_ripples.append({"pos": event.position, "age": 0.0, "max_r": 180.0, "alpha": 0.45})


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
		sonar_backdrop.draw_circle(pos, r * 2.4, Color(0.2, 0.75, 1.0, twinkle * 0.18))
		sonar_backdrop.draw_circle(pos, r, Color(0.55, 0.92, 1.0, twinkle))

	for r in _ripples:
		var prog: float = clampf(float(r["age"]) / 2.8, 0.0, 1.0)
		var rad: float = prog * float(r["max_r"])
		var a: float = (1.0 - prog) * float(r["alpha"])
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

func _on_start_pressed() -> void:
	if _is_modal_open:
		return
	_play_ui_sound(_wav_start, -4.0, 1.0)
	Input.vibrate_handheld(35)

	if start_button != null:
		var spawn_pos: Vector2 = start_button.global_position + start_button.size * 0.5
		_ripples.append({"pos": spawn_pos, "age": 0.0, "max_r": 520.0, "alpha": 0.85})

	_open_modal("SELECT DEPTH", "CHOOSE CAVERN SECTOR")

	# Test arena button at top
	var test_btn := Button.new()
	test_btn.custom_minimum_size = Vector2(0, 42)
	test_btn.focus_mode = Control.FOCUS_NONE
	test_btn.text = "TEST ARENA (ALL MONSTERS SANDBOX)"
	test_btn.add_theme_font_size_override("font_size", 13)
	test_btn.pressed.connect(func():
		GameState.start_game(0)
	)
	_wire_button_Juice(test_btn)
	_modal_body.add_child(test_btn)

	# Scrollable level list: DEPTH 00, 20-level grid, then the SP level
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	list.add_child(_make_level_button("DEPTH 00", LEVEL_ZERO_PATH))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)

	for i in range(1, TOTAL_LEVEL_COUNT + 1):
		var lvl_path: String = "res://levels/level_%02d.tscn" % i
		var exists: bool = ResourceLoader.exists(lvl_path)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(195, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.text = "DEPTH %02d" % i
		if not exists:
			btn.modulate = Color(0.65, 0.75, 0.88, 0.7)
		btn.pressed.connect(func():
			_launch_level_by_number(i, lvl_path)
		)
		_wire_button_Juice(btn)
		grid.add_child(btn)

	list.add_child(_make_level_button("SPECIAL DEPTH (SP)", LEVEL_SP_PATH))


func _make_level_button(label: String, lvl_path: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 42)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)
	btn.text = label
	if not ResourceLoader.exists(lvl_path):
		btn.modulate = Color(0.65, 0.75, 0.88, 0.7)
	btn.pressed.connect(func():
		var idx: int = GameState.LEVELS.find(lvl_path)
		GameState.start_game(maxi(idx, 0))
	)
	_wire_button_Juice(btn)
	return btn


func _launch_level_by_number(level_num: int, lvl_path: String) -> void:
	var idx: int = GameState.LEVELS.find(lvl_path)
	if idx != -1:
		GameState.start_game(idx)
	elif level_num < GameState.LEVELS.size():
		GameState.start_game(level_num)
	else:
		GameState.start_game(0)


func _on_settings_pressed() -> void:
	_open_modal("SETTINGS", "AUDIO & MICROPHONE SENSOR")

	var bus_idx: int = AudioServer.get_bus_index("Master")
	var cur_vol: float = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))

	var vol_header := HBoxContainer.new()
	var vol_lbl := Label.new()
	vol_lbl.text = "MASTER VOLUME"
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	vol_lbl.add_theme_font_size_override("font_size", 13)

	var vol_val := Label.new()
	vol_val.text = "%d%%" % int(round(cur_vol * 100.0))
	vol_val.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	vol_val.add_theme_font_size_override("font_size", 13)

	vol_header.add_child(vol_lbl)
	vol_header.add_child(vol_val)
	_modal_body.add_child(vol_header)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 26)
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = cur_vol
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		GameState.set_master_volume(v)
		vol_val.text = "%d%%" % int(round(v * 100.0))
	)
	_modal_body.add_child(slider)

	var mic_row := HBoxContainer.new()
	var mic_lbl := Label.new()
	mic_lbl.text = "MICROPHONE SENSOR"
	mic_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	mic_lbl.add_theme_font_size_override("font_size", 13)

	var mic_btn := Button.new()
	mic_btn.custom_minimum_size = Vector2(110, 36)
	mic_btn.focus_mode = Control.FOCUS_NONE
	mic_btn.add_theme_font_size_override("font_size", 13)
	_refresh_mic_btn(mic_btn)
	mic_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.mic_enabled = not GameState.mic_enabled
		GameState.save_settings()
		if _menu_mic != null:
			_menu_mic.enabled = GameState.mic_enabled
		_refresh_mic_btn(mic_btn)
	)

	mic_row.add_child(mic_lbl)
	mic_row.add_child(mic_btn)
	_modal_body.add_child(mic_row)

	# Ensure live MicInput exists for testing & calibration in Main Menu
	if _menu_mic == null:
		_menu_mic = MicInput.new()
		add_child(_menu_mic)
		_menu_mic.start()
	_menu_mic.enabled = GameState.mic_enabled

	# Mic Sensitivity Header + Slider
	var sens_header := HBoxContainer.new()
	var sens_lbl := Label.new()
	sens_lbl.text = "MIC SENSITIVITY"
	sens_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	sens_lbl.add_theme_font_size_override("font_size", 13)

	var sens_val := Label.new()
	sens_val.text = "%d%%" % int(round(GameState.mic_sensitivity * 100.0))
	sens_val.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	sens_val.add_theme_font_size_override("font_size", 13)

	sens_header.add_child(sens_lbl)
	sens_header.add_child(sens_val)
	_modal_body.add_child(sens_header)

	var sens_slider := HSlider.new()
	sens_slider.custom_minimum_size = Vector2(0, 26)
	sens_slider.max_value = 1.0
	sens_slider.step = 0.01
	sens_slider.value = GameState.mic_sensitivity
	sens_slider.focus_mode = Control.FOCUS_NONE
	sens_slider.value_changed.connect(func(v: float):
		GameState.mic_sensitivity = v
		sens_val.text = "%d%%" % int(round(v * 100.0))
		GameState.save_settings()
	)
	_modal_body.add_child(sens_slider)

	# Live Mic Meter + Calibrate Room Button
	var calib_row := HBoxContainer.new()
	calib_row.add_theme_constant_override("separation", 12)

	_menu_meter_canvas = Control.new()
	_menu_meter_canvas.custom_minimum_size = Vector2(0, 32)
	_menu_meter_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_meter_canvas.draw.connect(_draw_menu_mic_meter)
	calib_row.add_child(_menu_meter_canvas)

	_menu_calib_btn = Button.new()
	_menu_calib_btn.custom_minimum_size = Vector2(142, 34)
	_menu_calib_btn.focus_mode = Control.FOCUS_NONE
	_menu_calib_btn.add_theme_font_size_override("font_size", 12)
	_menu_calib_btn.text = "CALIBRATE ROOM"
	_menu_calib_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		if _menu_mic != null:
			_menu_mic.recalibrate()
	)
	calib_row.add_child(_menu_calib_btn)
	_modal_body.add_child(calib_row)


func _draw_menu_mic_meter() -> void:
	if _menu_meter_canvas == null or not is_instance_valid(_menu_meter_canvas):
		return
	var w: float = _menu_meter_canvas.size.x
	var bar_y := 6.0
	var bar_h := 12.0

	_menu_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.03, 0.08, 0.15, 0.9))

	var cur_db: float = _menu_mic.level_db if (_menu_mic != null and GameState.mic_enabled) else -80.0
	var trig_db: float = GameState.get_mic_trigger_db()

	var fill_frac: float = clampf(inverse_lerp(-70.0, -5.0, cur_db), 0.0, 1.0)
	var trig_frac: float = clampf(inverse_lerp(-70.0, -5.0, trig_db), 0.0, 1.0)

	var active: bool = cur_db >= trig_db
	var fill_col: Color = Color(0.35, 0.95, 1.0, 0.95) if active else Color(0.22, 0.58, 0.85, 0.75)
	if fill_frac > 0.01:
		_menu_meter_canvas.draw_rect(Rect2(0.0, bar_y, w * fill_frac, bar_h), fill_col)

	_menu_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.24, 0.52, 0.78, 0.6), false, 1.0)

	var tx: float = w * trig_frac
	_menu_meter_canvas.draw_line(Vector2(tx, bar_y - 3.0), Vector2(tx, bar_y + bar_h + 3.0), Color(1.0, 0.82, 0.28, 0.95), 2.0)

	var hint_text := "SPEAK TO TEST  (YELLOW LINE = TRIGGER)"
	_menu_meter_canvas.draw_string(ThemeDB.fallback_font, Vector2(0.0, bar_y + bar_h + 12.0), hint_text, HORIZONTAL_ALIGNMENT_LEFT, int(w), 9, Color(0.55, 0.78, 0.95, 0.65))


func _refresh_mic_btn(btn: Button) -> void:
	if GameState.mic_enabled:
		btn.text = "ENABLED"
		btn.self_modulate = Color(0.35, 1.2, 1.8, 1.0)
	else:
		btn.text = "MUTED"
		btn.self_modulate = Color(0.7, 0.7, 0.7, 0.7)


func _on_how_to_play_pressed() -> void:
	_open_modal("HOW TO PLAY", "SURVIVAL GUIDE & MONSTER BESTIARY")

	_add_section_header("CORE CONTROLS")
	_add_guide_row(Color(0.35, 0.92, 1.0), "MOVE", "Tap / Left-Click anywhere to walk toward that spot.")
	_add_guide_row(Color(0.55, 0.96, 1.0), "SONAR ECHO", "Hold [SPACE / ECHO] or speak into your Mic to reveal walls.")
	_add_guide_row(Color(0.3, 0.72, 0.95), "SNEAK", "Press [SHIFT / SNEAK] to silence footsteps and move quietly.")
	_add_guide_row(Color(0.5, 0.68, 0.88), "WALL COVER", "Solid walls block your footsteps and shield you from Screamers.")

	_add_divider()
	_add_section_header("MONSTER BESTIARY")
	_add_guide_row(Color(0.68, 0.42, 0.98), "SLEEPER", "Dormant in the dark. Wakes up if you walk loud or step too close.")
	_add_guide_row(Color(1.0, 0.82, 0.25), "PATROLLER", "Roams fixed paths. Acute hearing—can even hear sneaking nearby.")
	_add_guide_row(Color(1.0, 0.22, 0.22), "CHASER", "Deaf to sneaking, but charges at lethal speed when alerted.")
	_add_guide_row(Color(0.95, 0.28, 0.72), "SCREAMER", "Stationary cocoon. Shrieks on the 2nd shout to stun you.")
	_add_guide_row(Color(0.2, 0.94, 0.68), "LISTENER", "Ignores footsteps. Counts 5 shouts, then alerts the whole map.")


func _on_credits_pressed() -> void:
	_open_modal("CREDITS", "ECHO: SOUND IN THE DARKNESS")

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


func _unhandled_input(event: InputEvent) -> void:
	if _is_modal_open and event.is_action_pressed("ui_cancel"):
		_close_modal()
		get_viewport().set_input_as_handled()


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
	var calibrating_mic: bool = _is_modal_open and _menu_meter_canvas != null and is_instance_valid(_menu_meter_canvas)
	if _bgm_pad_player != null:
		var target_db: float = -22.0 if calibrating_mic else -7.5
		_bgm_pad_player.volume_db = lerpf(_bgm_pad_player.volume_db, target_db, clampf(delta * 4.0, 0.0, 1.0))

	if calibrating_mic:
		return

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
				if is_inside_tree() and not (_is_modal_open and _menu_meter_canvas != null and is_instance_valid(_menu_meter_canvas)):
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
	var dur := 0.42
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.008, 1.0) * exp(-t * 6.5)
		p1 += TAU * 330.0 / MIX_RATE
		p2 += TAU * 495.0 / MIX_RATE
		p3 += TAU * 660.0 / MIX_RATE
		var s: float = (sin(p1) * 0.45 + sin(p2) * 0.35 + sin(p3) * 0.25) * env
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
