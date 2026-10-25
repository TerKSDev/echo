extends Control

# Background FX
var _time := 0.0
var _ambient_wave_timer := 2.0
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

# Audio Streams
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV

# Node References
@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var back_button: Button = $TopBar/BackButton
@onready var reset_defaults_btn: Button = get_node_or_null("TopBar/ResetDefaultsBtn")
@onready var tab_general_btn: Button = $TabBar/TabGeneral
@onready var tab_controls_btn: Button = $TabBar/TabControls
@onready var tab_display_btn: Button = $TabBar/TabDisplay
@onready var tab_advanced_btn: Button = $TabBar/TabAdvanced
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

# Tab Panels
var _panels: Array[VBoxContainer] = []
var _tab_buttons: Array[Button] = []
var _current_tab := 0

# Live Mic Input for Settings Sampling
var _menu_mic: MicInput
var _meter_canvas: Control
var _calib_btn: Button
var _mic_slider: HSlider
var _mic_val_lbl: Label
var _calibrated_flash_timer := 0.0

# Confirmation Modal for Progress Reset
var _confirm_modal: Control
var _danger_modal_visible := false


func _ready() -> void:
	_build_ui_audio()
	_init_spores()

	# Ambient backdrop and contrast tint
	var bg := get_node_or_null("Background") as CanvasItem
	if bg != null:
		bg.modulate = Color(0.68, 0.74, 0.80, 0.95)

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	# Clean scroll container
	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var vbar := scroll_container.get_v_scroll_bar()
		if vbar != null:
			vbar.modulate.a = 0.0 # Hide ugly scrollbar while allowing scrolling

	_setup_top_bar()
	_setup_tab_bar()
	_build_all_panels()
	_switch_tab(0)

	# Start mic if enabled
	_init_menu_mic()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _danger_modal_visible:
			_close_confirm_modal()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _setup_top_bar() -> void:
	if back_button != null:
		back_button.text = ""
		back_button.custom_minimum_size = Vector2(40, 40)
		back_button.focus_mode = Control.FOCUS_NONE
		var empty_style := StyleBoxEmpty.new()
		back_button.add_theme_stylebox_override("normal", empty_style)
		back_button.add_theme_stylebox_override("hover", empty_style)
		back_button.add_theme_stylebox_override("pressed", empty_style)
		back_button.add_theme_stylebox_override("focus", empty_style)
		back_button.add_theme_stylebox_override("disabled", empty_style)
		back_button.draw.connect(_draw_back_arrow.bind(back_button))
		back_button.mouse_entered.connect(func(): back_button.queue_redraw())
		back_button.mouse_exited.connect(func(): back_button.queue_redraw())
		back_button.button_down.connect(func(): back_button.queue_redraw())
		back_button.button_up.connect(func(): back_button.queue_redraw())
		back_button.pressed.connect(_on_back_pressed)
		_wire_juice(back_button)

	if reset_defaults_btn != null:
		_style_action_button(reset_defaults_btn, Color(0.35, 0.65, 0.90, 0.65), Color(0.03, 0.08, 0.15, 0.8))
		reset_defaults_btn.pressed.connect(_on_reset_defaults_pressed)
		_wire_juice(reset_defaults_btn)


func _setup_tab_bar() -> void:
	_tab_buttons = [tab_general_btn, tab_controls_btn, tab_display_btn, tab_advanced_btn]
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if btn != null:
			btn.pressed.connect(_switch_tab.bind(i))
			_wire_juice(btn)


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

	var p_general := _build_general_panel()
	var p_controls := _build_controls_panel()
	var p_display := _build_display_panel()
	var p_advanced := _build_advanced_panel()

	content_box.add_child(p_general)
	content_box.add_child(p_controls)
	content_box.add_child(p_display)
	content_box.add_child(p_advanced)

	_panels = [p_general, p_controls, p_display, p_advanced]


# --------------------------------------------------
# PANEL 1: GENERAL & AUDIO
# --------------------------------------------------
func _build_general_panel() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	# --- Section 1: Master Audio ---
	root.add_child(_create_section_header("AUDIO OUTPUT & VOLUMES"))

	# Master Audio Mute Switch
	var mute_btn := Button.new()
	mute_btn.custom_minimum_size = Vector2(136, 32)
	mute_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(mute_btn, not GameState.master_muted, "ENABLED", "MUTED")
	mute_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.set_master_muted(not GameState.master_muted)
		_refresh_toggle_btn(mute_btn, not GameState.master_muted, "ENABLED", "MUTED")
	)
	_wire_juice(mute_btn)
	root.add_child(_create_setting_row(
		"MASTER AUDIO OUTPUT",
		"Enable or silence all master game audio while preserving your volume slider levels.",
		mute_btn
	))

	# Master Volume Slider
	root.add_child(_create_slider_row("MASTER VOLUME", "Global gain for all acoustic output.", GameState.master_volume, 0.01, 0.0, 1.0, "%d%%", func(v: float):
		GameState.set_master_volume(v)
	))

	# Ambience & Music (BGM) Slider
	root.add_child(_create_slider_row("AMBIENCE & MUSIC", "Subterranean cavern drones, resonant echo notes and water droplets.", GameState.bgm_volume, 0.01, 0.0, 1.0, "%d%%", func(v: float):
		GameState.set_bgm_volume(v)
	))

	# Sound Effects (SFX) Slider
	root.add_child(_create_slider_row("SOUND EFFECTS (SFX)", "Acoustic ping sonar waves, player footsteps, heartbeats, and entity cries.", GameState.sfx_volume, 0.01, 0.0, 1.0, "%d%%", func(v: float):
		GameState.set_sfx_volume(v)
	))

	root.add_child(_create_category_divider())

	# --- Section 2: Microphone Input ---
	root.add_child(_create_section_header("MICROPHONE SENSOR & CALIBRATION"))

	# Mic Sensor Enabled Toggle
	var mic_btn := Button.new()
	mic_btn.custom_minimum_size = Vector2(136, 32)
	mic_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(mic_btn, GameState.mic_enabled, "ENABLED", "MUTED")
	mic_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.mic_enabled = not GameState.mic_enabled
		GameState.save_settings()
		if _menu_mic != null:
			_menu_mic.enabled = GameState.mic_enabled
		_refresh_toggle_btn(mic_btn, GameState.mic_enabled, "ENABLED", "MUTED")
	)
	_wire_juice(mic_btn)
	root.add_child(_create_setting_row(
		"MICROPHONE SENSOR",
		"Detects real-world vocalization to generate acoustic echo waves in the abyss.",
		mic_btn
	))

	# Mic Sensitivity Slider
	root.add_child(_create_slider_row("MICROPHONE SENSITIVITY", "Threshold margin above room noise required to trigger a sound ping.", GameState.mic_sensitivity, 0.01, 0.0, 1.0, "%d%%", func(v: float):
		GameState.mic_sensitivity = v
		GameState.save_settings()
	))

	# Live Mic Meter & Calibration Button
	var calib_row := HBoxContainer.new()
	calib_row.add_theme_constant_override("separation", 10)

	_meter_canvas = Control.new()
	_meter_canvas.custom_minimum_size = Vector2(0, 32)
	_meter_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter_canvas.draw.connect(_draw_menu_mic_meter.bind(_meter_canvas))
	calib_row.add_child(_meter_canvas)

	_calib_btn = Button.new()
	_calib_btn.custom_minimum_size = Vector2(136, 32)
	_calib_btn.focus_mode = Control.FOCUS_NONE
	_calib_btn.add_theme_font_size_override("font_size", 12)
	_calib_btn.text = "CALIBRATE ROOM"
	_style_action_button(_calib_btn, Color(0.28, 0.65, 0.95, 0.8), Color(0.04, 0.12, 0.22, 0.9))
	_calib_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		if _menu_mic != null:
			_menu_mic.recalibrate()
	)
	_wire_juice(_calib_btn)
	calib_row.add_child(_calib_btn)

	var calib_container := VBoxContainer.new()
	calib_container.add_theme_constant_override("separation", 6)
	calib_container.add_child(calib_row)

	var hint_lbl := Label.new()
	hint_lbl.text = "SPEAK TO TEST  •  YELLOW LINE = TRIGGER THRESHOLD  •  KEY [M] = QUICK MUTE"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.42, 0.65, 0.85, 0.65))
	calib_container.add_child(hint_lbl)

	root.add_child(calib_container)

	return root


# --------------------------------------------------
# PANEL 2: GAMEPLAY & CONTROLS
# --------------------------------------------------
func _build_controls_panel() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(_create_section_header("MOVEMENT & STEALTH"))

	# Sneak Mode: Hold vs Toggle
	var sneak_btn := Button.new()
	sneak_btn.custom_minimum_size = Vector2(148, 32)
	sneak_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(sneak_btn, GameState.sneak_hold_mode, "HOLD TO SNEAK", "TOGGLE SNEAK")
	sneak_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.sneak_hold_mode = not GameState.sneak_hold_mode
		GameState.save_settings()
		_refresh_toggle_btn(sneak_btn, GameState.sneak_hold_mode, "HOLD TO SNEAK", "TOGGLE SNEAK")
	)
	_wire_juice(sneak_btn)
	root.add_child(_create_setting_row(
		"SNEAK INPUT MODE",
		"Choose whether holding Shift / Sneak button maintains stealth or a single tap toggles stance.",
		sneak_btn
	))

	root.add_child(_create_category_divider())

	root.add_child(_create_section_header("SONAR & ACOUSTIC ASSISTANCE"))

	# Fast Pulse Mode
	var pulse_btn := Button.new()
	pulse_btn.custom_minimum_size = Vector2(136, 32)
	pulse_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(pulse_btn, GameState.fast_pulse_mode, "ENABLED", "DISABLED")
	pulse_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.fast_pulse_mode = not GameState.fast_pulse_mode
		GameState.save_settings()
		_refresh_toggle_btn(pulse_btn, GameState.fast_pulse_mode, "ENABLED", "DISABLED")
	)
	_wire_juice(pulse_btn)
	root.add_child(_create_setting_row(
		"FAST PULSE DOUBLE CLICK",
		"Double click or double tap mouse to instantly trigger a maximum radius acoustic wave.",
		pulse_btn
	))

	# Directional Sound Visual Indicator
	var ind_btn := Button.new()
	ind_btn.custom_minimum_size = Vector2(136, 32)
	ind_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(ind_btn, GameState.sound_indicator_enabled, "ENABLED", "DISABLED")
	ind_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.sound_indicator_enabled = not GameState.sound_indicator_enabled
		GameState.save_settings()
		_refresh_toggle_btn(ind_btn, GameState.sound_indicator_enabled, "ENABLED", "DISABLED")
	)
	_wire_juice(ind_btn)
	root.add_child(_create_setting_row(
		"OFF-SCREEN SOUND COMPASS",
		"Displays subtle directional arcs at the screen edge when entities screech or roar off-screen.",
		ind_btn
	))

	# Visually Impaired (Blind) Echolocation & Navigation Mode
	var blind_btn := Button.new()
	blind_btn.custom_minimum_size = Vector2(136, 32)
	blind_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(blind_btn, GameState.blind_assist_mode, "ENABLED", "DISABLED")
	blind_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.blind_assist_mode = not GameState.blind_assist_mode
		GameState.save_settings()
		_refresh_toggle_btn(blind_btn, GameState.blind_assist_mode, "ENABLED", "DISABLED")
	)
	_wire_juice(blind_btn)
	root.add_child(_create_setting_row(
		"BLIND NAVIGATION ASSIST (视障辅助)",
		"Emits periodic 3D spatial exit beacons, acoustic wall reflection echoes, obstacle cane radar, and inventory pips [C]. (Hotkey [B] in-game)",
		blind_btn
	))

	return root


# --------------------------------------------------
# PANEL 3: DISPLAY & GRAPHICS
# --------------------------------------------------
func _build_display_panel() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(_create_section_header("VISUAL FEEDBACK & MOTION"))

	# Screen Shake Intensity Slider
	root.add_child(_create_slider_row("SCREEN SHAKE INTENSITY", "Camera vibration strength when startled, stunned, or hit by Screamer shrieks.", GameState.screen_shake_intensity, 0.05, 0.0, 1.0, "%d%%", func(v: float):
		GameState.screen_shake_intensity = v
		GameState.save_settings()
	))

	# Sonar Glow Boost Slider
	root.add_child(_create_slider_row("SONAR PHOSPHOR BRIGHTNESS", "Multiplies visibility and luminance of reverberating sound waves in deep dark trenches.", GameState.sonar_glow_boost, 0.05, 0.6, 1.4, "%d%%", func(v: float):
		GameState.sonar_glow_boost = v
		GameState.save_settings()
	))

	# Vignette & Distortion Toggle
	var vig_btn := Button.new()
	vig_btn.custom_minimum_size = Vector2(136, 32)
	vig_btn.focus_mode = Control.FOCUS_NONE
	_refresh_toggle_btn(vig_btn, GameState.vignette_enabled, "ENABLED", "DISABLED")
	vig_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		GameState.vignette_enabled = not GameState.vignette_enabled
		GameState.save_settings()
		_refresh_toggle_btn(vig_btn, GameState.vignette_enabled, "ENABLED", "DISABLED")
	)
	_wire_juice(vig_btn)
	root.add_child(_create_setting_row(
		"HEARTBEAT THREAT VIGNETTE",
		"Pulsing edge shadow and claustrophobic chromatic distortion when monsters approach.",
		vig_btn
	))

	root.add_child(_create_category_divider())

	root.add_child(_create_section_header("MOBILE PERFORMANCE & POWER"))

	# Target Frame Rate (30 / 60 / 120 FPS)
	var fps_btn := Button.new()
	fps_btn.custom_minimum_size = Vector2(170, 34)
	fps_btn.focus_mode = Control.FOCUS_NONE
	_update_fps_btn_text(fps_btn)
	fps_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		match GameState.max_fps:
			30:
				GameState.max_fps = 60
			60:
				GameState.max_fps = 120
			_:
				GameState.max_fps = 30
		GameState.apply_display_settings()
		GameState.save_settings()
		_update_fps_btn_text(fps_btn)
	)
	_wire_juice(fps_btn)
	root.add_child(_create_setting_row(
		"TARGET FRAME RATE",
		"Cycle between 30 FPS (Battery Saver), 60 FPS (Balanced), and 120 FPS (High Refresh Rate).",
		fps_btn
	))

	return root


# --------------------------------------------------
# PANEL 4: ADVANCED & DATA
# --------------------------------------------------
func _build_advanced_panel() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(_create_section_header("ACOUSTIC HUD PALETTE"))

	# Sonar Color Theme Cycle
	var palette_box := HBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 10)

	var preview_chip := ColorRect.new()
	preview_chip.custom_minimum_size = Vector2(24, 24)
	preview_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_chip.color = GameState.get_sonar_color()
	palette_box.add_child(preview_chip)

	var palette_btn := Button.new()
	palette_btn.custom_minimum_size = Vector2(170, 32)
	palette_btn.focus_mode = Control.FOCUS_NONE
	_update_palette_btn(palette_btn, preview_chip)
	palette_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -5.0, 1.0)
		match GameState.sonar_palette:
			"cyan":
				GameState.sonar_palette = "emerald"
			"emerald":
				GameState.sonar_palette = "amber"
			"amber":
				GameState.sonar_palette = "white"
			_:
				GameState.sonar_palette = "cyan"
		GameState.save_settings()
		_update_palette_btn(palette_btn, preview_chip)
		sonar_backdrop.queue_redraw()
	)
	_wire_juice(palette_btn)
	palette_box.add_child(palette_btn)

	root.add_child(_create_setting_row(
		"SONAR PHOSPHOR COLOR",
		"Choose the bioluminescent acoustic frequency theme for echo ripples and scan markers.",
		palette_box
	))

	root.add_child(_create_category_divider())

	root.add_child(_create_section_header("EXPEDITION ARCHIVE & DATA"))

	# Progress diagnostic status
	var diag_card := PanelContainer.new()
	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.03, 0.07, 0.13, 0.85)
	d_style.set_border_width_all(1)
	d_style.border_color = Color(0.18, 0.38, 0.60, 0.4)
	d_style.set_corner_radius_all(8)
	d_style.content_margin_left = 16.0
	d_style.content_margin_right = 16.0
	d_style.content_margin_top = 12.0
	d_style.content_margin_bottom = 12.0
	diag_card.add_theme_stylebox_override("panel", d_style)

	var diag_box := VBoxContainer.new()
	diag_box.add_theme_constant_override("separation", 6)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "FURTHEST SECTOR UNLOCKED:  %s" % GameState.get_level_name(GameState.highest_unlocked_level)
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 0.95))
	diag_box.add_child(lvl_lbl)

	var floor_lbl := Label.new()
	floor_lbl.text = "CALIBRATED AMBIENT NOISE FLOOR:  %.1f dB" % GameState.mic_noise_floor_db
	floor_lbl.add_theme_font_size_override("font_size", 11)
	floor_lbl.add_theme_color_override("font_color", Color(0.4, 0.65, 0.85, 0.75))
	diag_box.add_child(floor_lbl)

	diag_card.add_child(diag_box)
	root.add_child(diag_card)

	root.add_child(_create_category_divider())

	# Danger Zone: Reset Progress / Return to Abyss
	root.add_child(_create_section_header("DANGER ZONE • RETURN TO ABYSS"))

	var has_cleared_adv := GameState.highest_unlocked_level > 1
	var reset_btn := Button.new()
	reset_btn.custom_minimum_size = Vector2(170, 36)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_font_size_override("font_size", 12)
	if has_cleared_adv:
		reset_btn.text = "RETURN TO ABYSS"
		_style_action_button(reset_btn, Color(0.92, 0.28, 0.35, 0.95), Color(0.20, 0.04, 0.06, 0.92))
		reset_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.78, 1.0))
		reset_btn.pressed.connect(_open_confirm_modal)
		_wire_juice(reset_btn)
	else:
		reset_btn.text = "LOCKED (%s)" % GameState.get_level_name(1)
		reset_btn.disabled = true
		_style_disabled_button(reset_btn)

	var adv_desc := "Reset all unlocked sectors back to %s. Irreversible. (Requires at least 1 completed sector)." % [GameState.get_level_name(1)] if has_cleared_adv else "Locked. Complete at least one expedition sector before you can trigger a return to the abyss."

	root.add_child(_create_setting_row(
		"RETURN TO ABYSS",
		adv_desc,
		reset_btn
	))

	return root


# --------------------------------------------------
# UI BUILDER HELPERS
# --------------------------------------------------
func _create_section_header(title: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = Color(0.35, 0.85, 1.0, 0.95)
	hbox.add_child(bar)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.48, 0.84, 1.0, 0.95))
	lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(lbl)
	return hbox


func _create_category_divider() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 1)
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.color = Color(0.18, 0.38, 0.60, 0.35)
	c.add_child(line)
	return c


func _create_setting_row(title_text: String, desc_text: String, action_control: Control) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0, 0.98))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.add_theme_font_size_override("font_size", 15)
	text_box.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.74, 0.92, 0.85))
	desc_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.75))
	desc_lbl.add_theme_constant_override("shadow_offset_y", 1)
	desc_lbl.add_theme_font_size_override("font_size", 13)
	text_box.add_child(desc_lbl)

	hbox.add_child(text_box)

	action_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(action_control)

	return hbox


func _create_slider_row(
	title: String,
	desc: String,
	current_val: float,
	step: float,
	min_v: float,
	max_v: float,
	format_str: String,
	on_changed: Callable
) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0, 0.98))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.add_theme_font_size_override("font_size", 15)
	text_box.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.74, 0.92, 0.85))
	desc_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.75))
	desc_lbl.add_theme_constant_override("shadow_offset_y", 1)
	desc_lbl.add_theme_font_size_override("font_size", 13)
	text_box.add_child(desc_lbl)
	header.add_child(text_box)

	var val_lbl := Label.new()
	val_lbl.text = format_str % int(round(current_val * 100.0))
	val_lbl.custom_minimum_size = Vector2(56, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 1.0))
	val_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.85))
	val_lbl.add_theme_constant_override("shadow_offset_y", 1)
	val_lbl.add_theme_font_size_override("font_size", 15)
	header.add_child(val_lbl)

	vbox.add_child(header)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 24)
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = current_val
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		val_lbl.text = format_str % int(round(v * 100.0))
		on_changed.call(v)
	)
	vbox.add_child(slider)

	if title == "MICROPHONE SENSITIVITY":
		_mic_slider = slider
		_mic_val_lbl = val_lbl

	return vbox


func _refresh_toggle_btn(btn: Button, active: bool, on_text: String, off_text: String) -> void:
	btn.text = on_text if active else off_text
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	if active:
		btn.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 1.0))
		style.bg_color = Color(0.04, 0.14, 0.24, 0.90)
		style.border_color = Color(0.28, 0.75, 1.0, 0.85)
	else:
		btn.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80, 0.75))
		style.bg_color = Color(0.06, 0.08, 0.12, 0.80)
		style.border_color = Color(0.24, 0.35, 0.46, 0.65)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)


func _update_fps_btn_text(btn: Button) -> void:
	match GameState.max_fps:
		30:
			btn.text = "30 FPS (SAVER)"
		120:
			btn.text = "120 FPS (ULTRA)"
		_:
			btn.text = "60 FPS (BALANCED)"
	_style_action_button(btn, Color(0.3, 0.65, 0.9, 0.75), Color(0.04, 0.12, 0.22, 0.85))


func _update_palette_btn(btn: Button, chip: ColorRect) -> void:
	chip.color = GameState.get_sonar_color()
	match GameState.sonar_palette:
		"emerald":
			btn.text = "EMERALD REEF"
		"amber":
			btn.text = "AMBER GOLD"
		"white":
			btn.text = "PURE WHITE"
		_:
			btn.text = "ABYSS CYAN"
	_style_action_button(btn, chip.color.lerp(Color.WHITE, 0.2), Color(0.04, 0.12, 0.22, 0.85))


func _style_action_button(btn: Button, border_col: Color, bg_col: Color) -> void:
	var norm := StyleBoxFlat.new()
	norm.set_corner_radius_all(6)
	norm.set_border_width_all(1)
	norm.bg_color = bg_col
	norm.border_color = border_col

	var hov := StyleBoxFlat.new()
	hov.set_corner_radius_all(6)
	hov.set_border_width_all(1)
	hov.bg_color = bg_col.lerp(Color(0.2, 0.5, 0.8, 1.0), 0.25)
	hov.border_color = border_col.lerp(Color.WHITE, 0.4)

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", norm)


func _style_disabled_button(btn: Button) -> void:
	var dis := StyleBoxFlat.new()
	dis.set_corner_radius_all(6)
	dis.set_border_width_all(1)
	dis.bg_color = Color(0.04, 0.07, 0.11, 0.65)
	dis.border_color = Color(0.18, 0.28, 0.38, 0.45)
	btn.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 0.55))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.55, 0.65, 0.55))
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_stylebox_override("normal", dis)
	btn.add_theme_stylebox_override("hover", dis)
	btn.add_theme_stylebox_override("pressed", dis)
	btn.add_theme_stylebox_override("focus", dis)


func _wire_juice(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		_play_ui_sound(_wav_hover, -14.0, randf_range(0.98, 1.04))
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(1.02, 1.02), 0.08)
	)
	btn.mouse_exited.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2.ONE, 0.1)
	)
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(0.97, 0.97), 0.05)
	)
	btn.button_up.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(1.02, 1.02), 0.1)
	)


# --------------------------------------------------
# BACK & RESTORE ACTIONS
# --------------------------------------------------
func _on_back_pressed() -> void:
	_play_ui_sound(_wav_click, -6.0, 0.95)
	GameState.save_settings()
	if _menu_mic != null and is_instance_valid(_menu_mic):
		_menu_mic.queue_free()
		_menu_mic = null
	GameState.return_from_settings()


func _on_reset_defaults_pressed() -> void:
	_play_ui_sound(_wav_click, -4.0, 1.1)
	GameState.master_volume = 1.0
	GameState.master_muted = false
	GameState.bgm_volume = 0.8
	GameState.sfx_volume = 1.0
	GameState.mic_enabled = true
	GameState.mic_sensitivity = 0.5
	GameState.sneak_hold_mode = false
	GameState.fast_pulse_mode = false
	GameState.sound_indicator_enabled = true
	GameState.fullscreen_enabled = false
	GameState.screen_shake_intensity = 1.0
	GameState.sonar_glow_boost = 1.0
	GameState.vignette_enabled = true
	GameState.vsync_enabled = true
	GameState.max_fps = 60
	GameState.sonar_palette = "cyan"
	GameState.apply_audio_settings()
	GameState.apply_display_settings()
	GameState.save_settings()

	_build_all_panels()
	_switch_tab(_current_tab)


# --------------------------------------------------
# CONFIRMATION MODAL FOR PROGRESS RESET
# --------------------------------------------------
func _open_confirm_modal() -> void:
	if GameState.highest_unlocked_level <= 1:
		return
	if _confirm_modal != null and is_instance_valid(_confirm_modal):
		_confirm_modal.queue_free()

	_danger_modal_visible = true

	_confirm_modal = Control.new()
	_confirm_modal.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.02, 0.05, 0.85)
	_confirm_modal.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 26.0
	card_style.content_margin_top = 24.0
	card_style.content_margin_right = 26.0
	card_style.content_margin_bottom = 26.0
	card_style.bg_color = Color(0.09, 0.02, 0.04, 0.98)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.95, 0.28, 0.35, 0.95)
	card_style.set_corner_radius_all(14)
	card_style.shadow_color = Color(0.8, 0.1, 0.2, 0.25)
	card_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "RETURN TO ABYSS?"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.40, 1.0))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "WARNING: This action is completely IRREVERSIBLE.\n\nAll unlocked sectors and expedition progress will be erased, returning you to %s.\n\nAre you sure you want to return to the abyss?" % GameState.get_level_name(1)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.95, 0.82, 0.85, 0.95))
	vbox.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.custom_minimum_size = Vector2(0, 42)
	_style_action_button(cancel_btn, Color(0.3, 0.5, 0.7, 0.7), Color(0.05, 0.12, 0.2, 0.9))
	cancel_btn.pressed.connect(_close_confirm_modal)
	_wire_juice(cancel_btn)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "CONFIRM: RETURN TO ABYSS"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.custom_minimum_size = Vector2(0, 42)
	_style_action_button(confirm_btn, Color(0.95, 0.3, 0.35, 1.0), Color(0.28, 0.05, 0.08, 0.98))
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.8, 1.0))
	confirm_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -3.0, 0.75)
		GameState.reset_progress()
		_close_confirm_modal()
		_build_all_panels()
		_switch_tab(_current_tab)
	)
	_wire_juice(confirm_btn)
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)
	add_child(_confirm_modal)


func _close_confirm_modal() -> void:
	_danger_modal_visible = false
	if _confirm_modal != null and is_instance_valid(_confirm_modal):
		_confirm_modal.queue_free()
		_confirm_modal = null


# --------------------------------------------------
# LIVE MIC & CALIBRATION DRAWING
# --------------------------------------------------
func _init_menu_mic() -> void:
	if _menu_mic == null:
		_menu_mic = MicInput.new()
		add_child(_menu_mic)
		_menu_mic.start()
		_menu_mic.calibration_finished.connect(_on_mic_calibration_finished)
	_menu_mic.enabled = GameState.mic_enabled


func _on_mic_calibration_finished(floor_db: float) -> void:
	# Automatically adapt optimal room sensitivity based on measured ambient noise:
	# Quiet environment (-54 dB) -> ~65% sensitivity (whispers easily detected)
	# Noisy environment (-34 dB) -> ~35% sensitivity (higher threshold to avoid false alarms)
	var auto_sens := clampf(inverse_lerp(-34.0, -54.0, floor_db) * 0.35 + 0.35, 0.25, 0.75)
	GameState.mic_sensitivity = auto_sens
	GameState.save_settings()

	# Visually update the sensitivity slider and percentage in real time
	if _mic_slider != null and is_instance_valid(_mic_slider):
		_mic_slider.value = auto_sens
	if _mic_val_lbl != null and is_instance_valid(_mic_val_lbl):
		_mic_val_lbl.text = "%d%%" % int(round(auto_sens * 100.0))

	_calibrated_flash_timer = 2.4


func _process(delta: float) -> void:
	_time += delta

	# Process live mic meter
	if _meter_canvas != null and is_instance_valid(_meter_canvas):
		_meter_canvas.queue_redraw()
		if _calib_btn != null and is_instance_valid(_calib_btn) and _menu_mic != null and is_instance_valid(_menu_mic):
			if _menu_mic.is_calibrating():
				_calib_btn.text = "SAMPLING..."
				_calib_btn.disabled = true
			elif _calibrated_flash_timer > 0.0:
				_calibrated_flash_timer -= delta
				_calib_btn.text = "CALIBRATED (%.0fdB)" % GameState.mic_noise_floor_db
				_calib_btn.disabled = false
			else:
				_calib_btn.text = "CALIBRATE ROOM"
				_calib_btn.disabled = not GameState.mic_enabled

	# Ambient sonar ripples
	_ambient_wave_timer -= delta
	if _ambient_wave_timer <= 0.0:
		_ambient_wave_timer = randf_range(5.0, 8.5)
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		_ripples.append({
			"pos": Vector2(randf_range(w_w * 0.16, w_w * 0.84), randf_range(w_h * 0.18, w_h * 0.82)),
			"age": 0.0,
			"max_r": randf_range(160.0, 240.0),
			"alpha": 0.20,
			"dur": 2.2
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(func(r: Dictionary) -> bool:
		return float(r["age"]) < float(r.get("dur", 2.2))
	)

	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		var vel: Vector2 = spore["vel"]
		pos += vel * delta
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		if pos.x < 0.0: pos.x = w_w
		elif pos.x > w_w: pos.x = 0.0
		if pos.y < 0.0: pos.y = w_h
		elif pos.y > w_h: pos.y = 0.0
		spore["pos"] = pos

	if sonar_backdrop != null:
		sonar_backdrop.queue_redraw()


func _draw_sonar_backdrop() -> void:
	if sonar_backdrop == null:
		return
	var theme_col: Color = GameState.get_sonar_color()
	var glow_boost: float = GameState.sonar_glow_boost

	for ripple in _ripples:
		var dur: float = float(ripple.get("dur", 2.2))
		var progress: float = clampf(float(ripple["age"]) / dur, 0.0, 1.0)
		var radius: float = progress * float(ripple["max_r"])
		var alpha: float = (1.0 - progress) * float(ripple.get("alpha", 0.45)) * glow_boost
		var r_col := Color(theme_col.r, theme_col.g, theme_col.b, alpha)
		sonar_backdrop.draw_arc(ripple["pos"], radius, 0.0, TAU, 36, r_col, 1.4)

	for spore in _spores:
		var pulse: float = 0.5 + 0.5 * sin(_time * float(spore["pulse_speed"]) + float(spore["phase"]))
		var alpha: float = lerpf(0.12, float(spore["base_alpha"]), pulse) * glow_boost
		var col := Color(theme_col.r, theme_col.g, theme_col.b, alpha)
		sonar_backdrop.draw_circle(spore["pos"], float(spore["radius"]), col)


func _draw_menu_mic_meter(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas):
		return
	var w: float = canvas.size.x
	var h: float = canvas.size.y
	if w <= 1.0 or h <= 1.0:
		return

	var bar_h: float = 16.0
	var bar_y: float = (h - bar_h) * 0.5

	canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.02, 0.06, 0.12, 0.95), true)

	var cur_db: float = _menu_mic.level_db if (_menu_mic != null and is_instance_valid(_menu_mic) and GameState.mic_enabled) else -80.0
	var trig_db: float = GameState.get_mic_trigger_db()

	var fill_frac: float = clampf(inverse_lerp(-70.0, -5.0, cur_db), 0.0, 1.0)
	var trig_frac: float = clampf(inverse_lerp(-70.0, -5.0, trig_db), 0.0, 1.0)

	var active: bool = cur_db >= trig_db
	var fill_col: Color = Color(0.35, 0.95, 1.0, 0.95) if active else Color(0.20, 0.55, 0.80, 0.80)
	if fill_frac > 0.01:
		canvas.draw_rect(Rect2(0.0, bar_y, w * fill_frac, bar_h), fill_col, true)

	canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.24, 0.52, 0.78, 0.65), false, 1.0)

	var tx: float = clampf(w * trig_frac, 2.0, w - 2.0)
	canvas.draw_line(Vector2(tx, bar_y - 2.5), Vector2(tx, bar_y + bar_h + 2.5), Color(1.0, 0.85, 0.30, 1.0), 2.0)


# Custom drawn minimalist back arrow icon (no rectangular button borders)
func _draw_back_arrow(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas):
		return
	var c: Vector2 = canvas.size * 0.5
	var btn := canvas as Button
	var is_hov: bool = btn != null and btn.is_hovered()
	var is_prs: bool = btn != null and btn.is_pressed()

	var col: Color = Color(0.40, 0.85, 1.0, 1.0) if is_prs else (Color(1.0, 1.0, 1.0, 1.0) if is_hov else Color(0.65, 0.84, 1.0, 0.88))

	# Subtle ambient glow aura on mouse hover
	if is_hov:
		canvas.draw_circle(c, 16.0, Color(0.20, 0.65, 1.0, 0.16))

	# Minimalist stem line
	canvas.draw_line(Vector2(c.x - 9.0, c.y), Vector2(c.x + 9.0, c.y), col, 2.2, true)

	# Minimalist chevron arrowhead
	var wing_top := Vector2(c.x - 2.0, c.y - 7.0)
	var tip := Vector2(c.x - 9.0, c.y)
	var wing_bot := Vector2(c.x - 2.0, c.y + 7.0)
	canvas.draw_polyline(PackedVector2Array([wing_top, tip, wing_bot]), col, 2.2, true)


# --------------------------------------------------
# PROCEDURAL AUDIO & PARTICLES
# --------------------------------------------------
func _init_spores() -> void:
	_spores.clear()
	var w_w: float = maxf(size.x, 720.0)
	var w_h: float = maxf(size.y, 1280.0)
	for i in 24:
		_spores.append({
			"pos": Vector2(randf_range(0.0, w_w), randf_range(0.0, w_h)),
			"vel": Vector2(randf_range(-8.0, 8.0), randf_range(-14.0, -4.0)),
			"radius": randf_range(1.4, 2.8),
			"base_alpha": randf_range(0.22, 0.55),
			"pulse_speed": randf_range(1.5, 3.5),
			"phase": randf_range(0.0, TAU)
		})


func _build_ui_audio() -> void:
	_wav_click = _synth_tone(620.0, 920.0, 0.14)
	_wav_hover = _synth_tone(480.0, 540.0, 0.06)


func _synth_tone(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var mix_rate := 44100
	var count := int(dur * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / mix_rate
		var env: float = minf(t / 0.004, 1.0) * exp(-t * 24.0)
		var freq: float = lerpf(f_start, f_end, t / dur)
		phase += TAU * freq / mix_rate
		var s: float = clampf(sin(phase) * env * 0.7, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.data = bytes
	return wav


func _play_ui_sound(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
