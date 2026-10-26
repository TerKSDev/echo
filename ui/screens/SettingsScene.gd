extends Control

const Icons = preload("res://ui/icons/Icons.gd")
const SettingsUIFactory = preload("res://ui/settings/SettingsUIFactory.gd")
const SettingsPanels = preload("res://ui/settings/SettingsPanels.gd")
const ResetConfirmModal = preload("res://ui/settings/ResetConfirmModal.gd")

@onready var back_button: Button = $TopBar/BackButton
@onready var reset_defaults_btn: Button = get_node_or_null("TopBar/ResetDefaultsButton")
@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

@onready var tab_general_btn: Button = $TabBar/TabGeneral
@onready var tab_controls_btn: Button = $TabBar/TabControls
@onready var tab_display_btn: Button = $TabBar/TabDisplay
@onready var tab_advanced_btn: Button = $TabBar/TabAdvanced

var _tab_buttons: Array[Button] = []
var _panels: Array[VBoxContainer] = []
var _current_tab: int = 0

var _menu_mic: MicInput = null
var _meter_canvas: Control = null
var _calib_btn: Button = null

var _confirm_modal: Control = null
var _danger_modal_visible: bool = false

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

# Procedural UI & BGM Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_back: AudioStreamWAV


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()
	_init_menu_mic()

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	_setup_top_bar()
	_setup_tab_bar()
	_build_all_panels()
	_switch_tab(0)
	_apply_safe_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_safe_area()


func _apply_safe_area() -> void:
	if not OS.has_feature("mobile") and OS.get_name() != "Android":
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen_sz := DisplayServer.screen_get_size()
	var vp_sz := get_viewport_rect().size
	if screen_sz.y > 0 and safe.position.y > 0:
		var top_pad := (float(safe.position.y) / float(screen_sz.y)) * vp_sz.y
		var target_top := maxf(top_pad + 6.0, 34.0)
		if has_node("TopBar"):
			$TopBar.position.y = target_top
		if has_node("TabBar"):
			$TabBar.position.y = target_top + 64.0
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 120.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		if _danger_modal_visible:
			_close_confirm_modal()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _setup_top_bar() -> void:
	if back_button != null:
		back_button.text = ""
		back_button.custom_minimum_size = Vector2(44, 44)
		back_button.focus_mode = Control.FOCUS_NONE
		var empty_sb := StyleBoxEmpty.new()
		back_button.add_theme_stylebox_override("normal", empty_sb)
		back_button.add_theme_stylebox_override("hover", empty_sb)
		back_button.add_theme_stylebox_override("pressed", empty_sb)
		back_button.add_theme_stylebox_override("focus", empty_sb)
		back_button.add_theme_stylebox_override("disabled", empty_sb)
		back_button.draw.connect(func(): Icons.draw_back_arrow(back_button))
		back_button.mouse_entered.connect(func(): back_button.queue_redraw())
		back_button.mouse_exited.connect(func(): back_button.queue_redraw())
		back_button.button_down.connect(func(): back_button.queue_redraw())
		back_button.button_up.connect(func(): back_button.queue_redraw())
		back_button.pressed.connect(_on_back_pressed)
		wire_juice(back_button)

	if reset_defaults_btn != null:
		SettingsUIFactory.style_action_button(reset_defaults_btn, Color(0.35, 0.65, 0.90, 0.65), Color(0.03, 0.09, 0.16, 0.85))
		reset_defaults_btn.pressed.connect(_on_reset_defaults_pressed)
		wire_juice(reset_defaults_btn)


func _setup_tab_bar() -> void:
	_tab_buttons = [tab_general_btn, tab_controls_btn, tab_display_btn, tab_advanced_btn]
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if btn != null:
			btn.pressed.connect(_switch_tab.bind(i))
			wire_juice(btn)


func _switch_tab(tab_idx: int) -> void:
	_play_ui_sound(_wav_click, -7.0, 1.05)
	_current_tab = tab_idx

	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if btn == null:
			continue
		var is_active := (i == tab_idx)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.set_border_width_all(1)
		if is_active:
			style.bg_color = Color(0.08, 0.24, 0.42, 0.95)
			style.border_color = Color(0.35, 0.88, 1.0, 1.0)
			btn.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0, 1.0))
		else:
			style.bg_color = Color(0.03, 0.08, 0.15, 0.80)
			style.border_color = Color(0.18, 0.38, 0.60, 0.45)
			btn.add_theme_color_override("font_color", Color(0.55, 0.75, 0.92, 0.70))
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("focus", style)
		btn.add_theme_font_size_override("font_size", 13)

	for i in _panels.size():
		var p := _panels[i]
		if p != null:
			p.visible = (i == tab_idx)

	if scroll_container != null:
		scroll_container.scroll_vertical = 0


func _build_all_panels() -> void:
	for child in content_box.get_children():
		child.queue_free()
	_panels.clear()

	_panels.append(SettingsPanels.build_general_panel(self))
	_panels.append(SettingsPanels.build_controls_panel(self))
	_panels.append(SettingsPanels.build_display_panel(self))
	_panels.append(SettingsPanels.build_advanced_panel(self))

	for p in _panels:
		content_box.add_child(p)
		p.visible = false

	if _current_tab >= 0 and _current_tab < _panels.size():
		_panels[_current_tab].visible = true


func play_click() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)


func wire_juice(btn: Button) -> void:
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.02, 1.02), 0.1)
		_play_ui_sound(_wav_hover, -10.0, 1.05)
	)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12)
	)
	btn.button_down.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.05)
	)
	btn.button_up.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
	)


func _on_back_pressed() -> void:
	_play_ui_sound(_wav_back, -4.0, 0.95)
	GameState.return_from_settings()


func _on_reset_defaults_pressed() -> void:
	_play_ui_sound(_wav_back, -3.0, 1.1)
	GameState.reset_to_defaults()
	_build_all_panels()
	_switch_tab(_current_tab)


func open_confirm_modal() -> void:
	if GameState.highest_unlocked_level <= 1:
		return
	if _confirm_modal != null and is_instance_valid(_confirm_modal):
		_confirm_modal.queue_free()

	_danger_modal_visible = true
	_confirm_modal = ResetConfirmModal.show_modal(
		self,
		func():
			_danger_modal_visible = false
			_confirm_modal = null
			_build_all_panels()
			_switch_tab(_current_tab),
		func():
			_danger_modal_visible = false
			_confirm_modal = null,
		func():
			_play_ui_sound(_wav_click, -3.0, 0.75),
		wire_juice
	)


func _close_confirm_modal() -> void:
	_danger_modal_visible = false
	if _confirm_modal != null and is_instance_valid(_confirm_modal):
		_confirm_modal.queue_free()
		_confirm_modal = null


func _init_menu_mic() -> void:
	if _menu_mic == null:
		_menu_mic = MicInput.new()
		add_child(_menu_mic)
		_menu_mic.calibration_finished.connect(_on_mic_calibration_finished)
		_menu_mic.start()


func _on_mic_calibration_finished(floor_db: float) -> void:
	_play_ui_sound(_wav_back, -2.0, 1.25)
	GameState.mic_noise_floor_db = floor_db
	GameState.mic_calibrated = true
	GameState.save_settings()
	if _calib_btn != null and is_instance_valid(_calib_btn):
		_calib_btn.text = "CALIBRATE ROOM"
		_calib_btn.disabled = false
	if _current_tab == 3:
		_build_all_panels()
		_switch_tab(3)


func _process(delta: float) -> void:
	_time += delta

	# Process active mic visualizer meter in General Tab
	if _current_tab == 0 and _meter_canvas != null and is_instance_valid(_meter_canvas):
		_meter_canvas.queue_redraw()
		if _calib_btn != null and is_instance_valid(_calib_btn) and _menu_mic != null and is_instance_valid(_menu_mic):
			if _menu_mic.is_calibrating():
				_calib_btn.text = "SAMPLING..."
				_calib_btn.disabled = true
			else:
				_calib_btn.text = "CALIBRATE ROOM"
				_calib_btn.disabled = not GameState.mic_enabled

	# Ambient sonar ripples
	_ambient_wave_timer -= delta
	if _ambient_wave_timer <= 0.0:
		_ambient_wave_timer = randf_range(5.0, 8.5)
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		var rand_pos := Vector2(
			randf_range(w_w * 0.16, w_w * 0.84),
			randf_range(w_h * 0.18, w_h * 0.82)
		)
		var rand_r: float = randf_range(160.0, 240.0)
		_ripples.append({
			"pos": rand_pos,
			"age": 0.0,
			"max_r": rand_r,
			"alpha": 0.20,
			"dur": 2.2
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(
		func(ripple: Dictionary) -> bool:
			return float(ripple["age"]) < float(ripple.get("dur", 2.2))
	)

	# Ambient spore particles
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		pos.y -= float(spore["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(spore["phase"])) * 12.0 * delta
		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))
		spore["pos"] = pos

	if sonar_backdrop != null and is_instance_valid(sonar_backdrop):
		sonar_backdrop.queue_redraw()


func _draw_sonar_backdrop() -> void:
	var w := size.x
	var h := size.y
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		if pos.x < -10.0 or pos.x > w + 10.0 or pos.y < -10.0 or pos.y > h + 10.0:
			continue
		var col := Color(0.4, 0.85, 1.0, float(spore["alpha"]))
		sonar_backdrop.draw_circle(pos, float(spore["r"]), col)

	for ripple in _ripples:
		var age: float = float(ripple["age"])
		var dur: float = float(ripple.get("dur", 2.2))
		var max_r: float = float(ripple.get("max_r", 200.0))
		var peak_a: float = float(ripple.get("alpha", 0.25))
		var progress: float = clampf(age / dur, 0.0, 1.0)
		var radius: float = progress * max_r
		var fade := 1.0 - progress
		fade = fade * fade
		var alpha := peak_a * fade
		sonar_backdrop.draw_arc(ripple["pos"], radius, 0.0, TAU, 48, Color(0.35, 0.85, 1.0, alpha), 1.4)


func _draw_menu_mic_meter(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas):
		return
	var w := canvas.size.x
	var h := canvas.size.y
	canvas.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.06, 0.12, 0.85), true)
	canvas.draw_rect(Rect2(0, 0, w, h), Color(0.18, 0.38, 0.58, 0.65), false, 1.0)

	var cur_db := -60.0
	if _menu_mic != null and GameState.mic_enabled:
		if _menu_mic.has_method("get_current_db"):
			cur_db = _menu_mic.get_current_db()
		elif "level_db" in _menu_mic:
			cur_db = _menu_mic.level_db

	var norm_val := clampf((cur_db + 60.0) / 60.0, 0.0, 1.0)
	var bar_w := w * norm_val
	var bar_col := Color(0.25, 0.75, 1.0, 0.85)
	if cur_db >= GameState.get_mic_trigger_db():
		bar_col = Color(0.35, 1.0, 0.65, 0.95)

	if bar_w > 1.0:
		canvas.draw_rect(Rect2(2, 2, bar_w - 4, h - 4), bar_col, true)

	var trig_norm := clampf((GameState.get_mic_trigger_db() + 60.0) / 60.0, 0.0, 1.0)
	var trig_x := w * trig_norm
	canvas.draw_line(Vector2(trig_x, 0), Vector2(trig_x, h), Color(1.0, 0.85, 0.25, 0.95), 1.5)


func _init_spores() -> void:
	_spores.clear()
	for i in range(24):
		_spores.append({
			"pos": Vector2(
				randf_range(0.0, maxf(size.x, 720.0)),
				randf_range(0.0, maxf(size.y, 1280.0))
			),
			"speed": randf_range(12.0, 32.0),
			"phase": randf_range(0.0, TAU),
			"r": randf_range(1.2, 2.8),
			"alpha": randf_range(0.12, 0.40)
		})


func _build_ui_audio() -> void:
	_wav_click = _synth_tone(720.0, 1080.0, 0.045)
	_wav_hover = _synth_tone(1100.0, 1320.0, 0.030)
	_wav_back = _synth_tone(540.0, 360.0, 0.065)


func _synth_tone(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var n_samples := int(sample_rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(n_samples * 2)

	var phase := 0.0
	for i in range(n_samples):
		var t := float(i) / float(n_samples)
		var freq := lerpf(f_start, f_end, t)
		var env := sin(t * PI)
		var sample := sin(phase) * env * 0.35
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s16)
		phase += TAU * freq / float(sample_rate)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _play_ui_sound(stream: AudioStreamWAV, vol_db: float, pitch: float, bus_name: StringName = &"SFX") -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = bus_name
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
