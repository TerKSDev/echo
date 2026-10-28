class_name SettingsPanels
extends RefCounted
## Tab Panel Construction for ECHO Settings System.
## Modularly builds General, Controls, Display, and Advanced options.


static func update_fps_btn_text(btn: Button) -> void:
	match GameState.max_fps:
		30:
			btn.text = "TARGET: 30 FPS"
		60:
			btn.text = "TARGET: 60 FPS"
		120:
			btn.text = "TARGET: 120 FPS"
		0:
			btn.text = "TARGET: UNCAPPED"
		_:
			btn.text = "TARGET: %d FPS" % GameState.max_fps
	SettingsUIFactory.style_action_button(btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)


static func update_palette_btn(btn: Button, chip: ColorRect) -> void:
	chip.color = GameState.get_sonar_color()
	match GameState.sonar_palette:
		"cyan":
			btn.text = "CYAN"
		"emerald":
			btn.text = "EMERALD"
		"amber":
			btn.text = "AMBER"
		"white":
			btn.text = "WHITE"
		_:
			btn.text = GameState.sonar_palette.to_upper()
	SettingsUIFactory.style_action_button(btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)


static func build_general_panel(scene: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	# --- Section 1: Master Audio ---
	root.add_child(SettingsUIFactory.create_section_header("AUDIO OUTPUT & VOLUMES"))

	# Master Audio Mute Switch
	var mute_btn := Button.new()
	mute_btn.custom_minimum_size = Vector2(136, 32)
	mute_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(mute_btn, not GameState.master_muted, "ENABLED", "MUTED")

	# Master Volume Slider
	var master_vol_row := SettingsUIFactory.create_slider_row("MASTER VOLUME", "Global gain for all acoustic output.", GameState.master_volume, true, func(v: float):
		GameState.set_master_volume(v)
	)

	# Ambience & Music (BGM) Slider
	var bgm_vol_row := SettingsUIFactory.create_slider_row("AMBIENCE & MUSIC", "Subterranean cavern drones, resonant bass hums, and title themes.", GameState.bgm_volume, true, func(v: float):
		GameState.set_bgm_volume(v)
	)

	# Sound Effects (SFX) Slider
	var sfx_vol_row := SettingsUIFactory.create_slider_row("SOUND EFFECTS (SFX)", "Acoustic ping sonar waves, monster roars, footsteps, and cave water droplets.", GameState.sfx_volume, true, func(v: float):
		GameState.set_sfx_volume(v)
	)

	var update_audio_deps := func() -> void:
		var audio_active: bool = not GameState.master_muted
		SettingsUIFactory.set_slider_row_enabled(master_vol_row, audio_active)
		SettingsUIFactory.set_slider_row_enabled(bgm_vol_row, audio_active)
		SettingsUIFactory.set_slider_row_enabled(sfx_vol_row, audio_active)

	mute_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.set_master_muted(not GameState.master_muted)
		SettingsUIFactory.refresh_toggle_btn(mute_btn, not GameState.master_muted, "ENABLED", "MUTED")
		update_audio_deps.call()
	)
	scene.call("wire_juice", mute_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"MASTER AUDIO OUTPUT",
		"Enable or silence all master game audio while preserving your volume slider levels.",
		mute_btn
	))
	root.add_child(master_vol_row)
	root.add_child(bgm_vol_row)
	root.add_child(sfx_vol_row)

	root.add_child(SettingsUIFactory.create_category_divider())

	# --- Section 2: Microphone Input ---
	root.add_child(SettingsUIFactory.create_section_header("MICROPHONE SENSOR & CALIBRATION"))

	# Mic Sensor Enabled Toggle
	var mic_btn := Button.new()
	mic_btn.custom_minimum_size = Vector2(136, 32)
	mic_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(mic_btn, GameState.mic_enabled, "ENABLED", "MUTED")

	# Mic Sensitivity Slider
	var mic_sens_row := SettingsUIFactory.create_slider_row("MICROPHONE SENSITIVITY", "Threshold margin above ambient room noise required to trigger sonar pulses.", GameState.mic_sensitivity, true, func(v: float):
		GameState.mic_sensitivity = v
		GameState.save_settings()
	)

	# Live Mic Meter & Calibration Button
	var calib_row := HBoxContainer.new()
	calib_row.add_theme_constant_override("separation", 10)

	var meter_canvas := Control.new()
	meter_canvas.custom_minimum_size = Vector2(0, 32)
	meter_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_canvas.draw.connect(func(): scene.call("_draw_menu_mic_meter", meter_canvas))
	calib_row.add_child(meter_canvas)
	scene.set("_meter_canvas", meter_canvas)

	var calib_btn := Button.new()
	calib_btn.custom_minimum_size = Vector2(136, 32)
	calib_btn.focus_mode = Control.FOCUS_NONE
	calib_btn.add_theme_font_size_override("font_size", 12)
	calib_btn.text = "CALIBRATE ROOM"
	SettingsUIFactory.style_action_button(calib_btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)
	calib_btn.pressed.connect(func():
		scene.call("play_click")
		var mic: Node = scene.get("_menu_mic")
		if mic != null:
			mic.call("recalibrate")
	)
	scene.call("wire_juice", calib_btn)
	calib_row.add_child(calib_btn)
	scene.set("_calib_btn", calib_btn)

	var calib_container := VBoxContainer.new()
	calib_container.add_theme_constant_override("separation", 6)
	calib_container.add_child(calib_row)

	var hint_lbl := Label.new()
	hint_lbl.text = "SPEAK TO TEST  •  YELLOW LINE = TRIGGER THRESHOLD  •  KEY [M] = QUICK MUTE"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color(0.42, 0.65, 0.85, 0.65))
	calib_container.add_child(hint_lbl)

	var update_mic_deps := func() -> void:
		var mic_active: bool = GameState.mic_enabled
		SettingsUIFactory.set_slider_row_enabled(mic_sens_row, mic_active)
		if calib_btn != null and is_instance_valid(calib_btn):
			calib_btn.disabled = not mic_active
			if mic_active:
				SettingsUIFactory.style_action_button(calib_btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)
			else:
				SettingsUIFactory.style_disabled_button(calib_btn, true)
		if calib_container != null and is_instance_valid(calib_container):
			calib_container.modulate.a = 1.0 if mic_active else 0.38
			calib_container.mouse_filter = Control.MOUSE_FILTER_PASS if mic_active else Control.MOUSE_FILTER_IGNORE

	mic_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.mic_enabled = not GameState.mic_enabled
		GameState.save_settings()
		var mic: Node = scene.get("_menu_mic")
		if mic != null:
			mic.set("enabled", GameState.mic_enabled)
		SettingsUIFactory.refresh_toggle_btn(mic_btn, GameState.mic_enabled, "ENABLED", "MUTED")
		var hud = scene.get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_node("MicIndicator"):
			hud.get_node("MicIndicator").visible = GameState.mic_enabled
		update_mic_deps.call()
	)
	scene.call("wire_juice", mic_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"MICROPHONE SENSOR",
		"Detects real-world vocalization to generate acoustic echo waves in the abyss.",
		mic_btn
	))
	root.add_child(mic_sens_row)
	root.add_child(calib_container)

	update_audio_deps.call()
	update_mic_deps.call()

	return root


static func build_controls_panel(scene: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(SettingsUIFactory.create_section_header("MOVEMENT & STEALTH"))

	# Movement Scheme: Joystick vs Drag & Tap
	var scheme_btn := Button.new()
	scheme_btn.custom_minimum_size = Vector2(160, 32)
	scheme_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(scheme_btn, GameState.virtual_joystick_enabled, "JOYSTICK", "DRAG & TAP")
	scheme_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.virtual_joystick_enabled = not GameState.virtual_joystick_enabled
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(scheme_btn, GameState.virtual_joystick_enabled, "JOYSTICK", "DRAG & TAP")
		var hud = scene.get_tree().get_first_node_in_group("hud")
		if hud == null:
			hud = scene.get_node_or_null("../../Hud")
		if hud != null and hud.has_method("update_controls_layout"):
			hud.update_controls_layout()
	)
	scene.call("wire_juice", scheme_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"MOVEMENT SCHEME",
		"Choose between dual-thumb Virtual Joystick or direct Drag & Tap touch steering.",
		scheme_btn
	))

	# Action Buttons Side / Handedness
	var layout_btn := Button.new()
	layout_btn.custom_minimum_size = Vector2(160, 32)
	layout_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(layout_btn, GameState.controls_layout == "right", "ACTIONS RIGHT", "ACTIONS LEFT")
	layout_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.controls_layout = "left" if GameState.controls_layout == "right" else "right"
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(layout_btn, GameState.controls_layout == "right", "ACTIONS RIGHT", "ACTIONS LEFT")
		var hud = scene.get_tree().get_first_node_in_group("hud")
		if hud == null:
			hud = scene.get_node_or_null("../../Hud")
		if hud != null and hud.has_method("update_controls_layout"):
			hud.update_controls_layout()
	)
	scene.call("wire_juice", layout_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"ACTION BUTTONS SIDE",
		"Position action buttons on the Right (left-thumb move) or Left (right-thumb move).",
		layout_btn
	))

	# Sneak Mode: Hold vs Toggle
	var sneak_btn := Button.new()
	sneak_btn.custom_minimum_size = Vector2(148, 32)
	sneak_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(sneak_btn, GameState.sneak_hold_mode, "HOLD TO SNEAK", "TOGGLE SNEAK")
	sneak_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.sneak_hold_mode = not GameState.sneak_hold_mode
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(sneak_btn, GameState.sneak_hold_mode, "HOLD TO SNEAK", "TOGGLE SNEAK")
	)
	scene.call("wire_juice", sneak_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"SNEAK INPUT MODE",
		"Choose whether holding Shift / Sneak button maintains stealth or a single tap toggles.",
		sneak_btn
	))

	root.add_child(SettingsUIFactory.create_category_divider())

	# --- Section 2: Aiming & Sensitivity ---
	root.add_child(SettingsUIFactory.create_section_header("AIMING & THROW SENSITIVITY"))

	# Pebble Throw Aiming Sensitivity (50% ~ 200%)
	root.add_child(SettingsUIFactory.create_slider_row(
		"PEBBLE THROW SENSITIVITY",
		"Adjust touch drag sensitivity for pebble aiming reach and distance.",
		GameState.pebble_sensitivity,
		true,
		func(v: float):
			GameState.pebble_sensitivity = clampf(v, 0.5, 2.0)
			GameState.save_settings()
	, 0.5, 2.0, 0.05))

	root.add_child(SettingsUIFactory.create_category_divider())

	# --- Section 3: Sonar & Acoustic Assistance ---
	root.add_child(SettingsUIFactory.create_section_header("SONAR & ACOUSTIC ASSISTANCE"))

	# Fast Pulse Mode
	var pulse_btn := Button.new()
	pulse_btn.custom_minimum_size = Vector2(136, 32)
	pulse_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(pulse_btn, GameState.fast_pulse_mode, "ENABLED", "DISABLED")
	pulse_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.fast_pulse_mode = not GameState.fast_pulse_mode
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(pulse_btn, GameState.fast_pulse_mode, "ENABLED", "DISABLED")
	)
	scene.call("wire_juice", pulse_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"FAST PULSE DOUBLE CLICK",
		"Double-click or double-tap to instantly emit a quick sonar pulse without holding Space.",
		pulse_btn
	))

	# Directional Sound Visual Indicator
	var ind_btn := Button.new()
	ind_btn.custom_minimum_size = Vector2(136, 32)
	ind_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(ind_btn, GameState.sound_indicator_enabled, "ENABLED", "DISABLED")
	ind_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.sound_indicator_enabled = not GameState.sound_indicator_enabled
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(ind_btn, GameState.sound_indicator_enabled, "ENABLED", "DISABLED")
	)
	scene.call("wire_juice", ind_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"OFF-SCREEN SOUND COMPASS",
		"Displays subtle directional arcs at the screen edge when entities screech or roar out of view.",
		ind_btn
	))

	# Visually Impaired (Blind) Echolocation & Navigation Mode
	var blind_btn := Button.new()
	blind_btn.custom_minimum_size = Vector2(136, 32)
	blind_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(blind_btn, GameState.blind_assist_mode, "ENABLED", "DISABLED")
	blind_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.blind_assist_mode = not GameState.blind_assist_mode
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(blind_btn, GameState.blind_assist_mode, "ENABLED", "DISABLED")
	)
	scene.call("wire_juice", blind_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"UNIVERSAL ACCESSIBILITY MODE",
		"Enhanced binaural cane echoes, wall proximity warnings, and tactile navigation support.",
		blind_btn
	))

	root.add_child(SettingsUIFactory.create_category_divider())

	# --- Section 4: HUD & On-Screen Layout ---
	root.add_child(SettingsUIFactory.create_section_header("HUD & ON-SCREEN CONTROLS"))

	# Custom HUD Layout Editor
	var custom_btn := Button.new()
	custom_btn.custom_minimum_size = Vector2(160, 32)
	custom_btn.focus_mode = Control.FOCUS_NONE
	custom_btn.text = "CUSTOMIZE HUD"
	custom_btn.add_theme_font_size_override("font_size", 12)
	SettingsUIFactory.style_action_button(custom_btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)
	custom_btn.pressed.connect(func():
		scene.call("play_click")
		HudLayoutCustomizer.open(scene.get_tree().root)
	)
	scene.call("wire_juice", custom_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"CUSTOMIZE HUD LAYOUT",
		"Freely reposition and resize buttons, sector info, voice sensor, and pause button.",
		custom_btn
	))

	return root


static func build_display_panel(scene: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(SettingsUIFactory.create_section_header("VISUAL FEEDBACK & MOTION"))

	# Screen Shake Intensity Slider
	root.add_child(SettingsUIFactory.create_slider_row("SCREEN SHAKE INTENSITY", "Camera vibration strength upon monster roars and cavern shocks.", GameState.screen_shake_intensity, true, func(v: float):
		GameState.screen_shake_intensity = v
		GameState.save_settings()
	))

	# Sonar Glow Boost Slider
	root.add_child(SettingsUIFactory.create_slider_row("SONAR PHOSPHOR BRIGHTNESS", "Multiplies visibility and lingering decay glow of wall echo marks.", GameState.sonar_glow_boost, false, func(v: float):
		GameState.sonar_glow_boost = v
		GameState.save_settings()
	))

	# Vignette & Distortion Toggle
	var vig_btn := Button.new()
	vig_btn.custom_minimum_size = Vector2(136, 32)
	vig_btn.focus_mode = Control.FOCUS_NONE
	SettingsUIFactory.refresh_toggle_btn(vig_btn, GameState.vignette_enabled, "ENABLED", "DISABLED")
	vig_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.vignette_enabled = not GameState.vignette_enabled
		GameState.save_settings()
		SettingsUIFactory.refresh_toggle_btn(vig_btn, GameState.vignette_enabled, "ENABLED", "DISABLED")
	)
	scene.call("wire_juice", vig_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"HEARTBEAT THREAT VIGNETTE",
		"Pulsing edge shadow and claustrophobic chromatic distortion when monsters approach.",
		vig_btn
	))

	root.add_child(SettingsUIFactory.create_category_divider())

	root.add_child(SettingsUIFactory.create_section_header("MOBILE PERFORMANCE & POWER"))

	# Target Frame Rate (30 / 60 / 120 FPS)
	var fps_btn := Button.new()
	fps_btn.custom_minimum_size = Vector2(170, 34)
	fps_btn.focus_mode = Control.FOCUS_NONE
	update_fps_btn_text(fps_btn)
	fps_btn.pressed.connect(func():
		scene.call("play_click")
		match GameState.max_fps:
			30:
				GameState.max_fps = 60
			60:
				GameState.max_fps = 120
			120:
				GameState.max_fps = 0
			_:
				GameState.max_fps = 30
		GameState.apply_display_settings()
		GameState.save_settings()
		update_fps_btn_text(fps_btn)
	)
	scene.call("wire_juice", fps_btn)
	root.add_child(SettingsUIFactory.create_setting_row(
		"TARGET FRAME RATE",
		"Cycle between 30 FPS (Battery Saver), 60 FPS (Balanced), 120 FPS (Smooth), and Uncapped (Max).",
		fps_btn
	))

	return root


static func build_advanced_panel(scene: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)

	root.add_child(SettingsUIFactory.create_section_header("ACOUSTIC HUD PALETTE"))

	# Sonar Color Theme Cycle
	var palette_box := HBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 10)

	var preview_chip := ColorRect.new()
	preview_chip.custom_minimum_size = Vector2(24, 24)
	preview_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_chip.color = GameState.get_sonar_color()
	palette_box.add_child(preview_chip)

	var palette_btn := Button.new()
	palette_btn.custom_minimum_size = Vector2(136, 32)
	palette_btn.focus_mode = Control.FOCUS_NONE
	palette_btn.add_theme_font_size_override("font_size", 13)
	update_palette_btn(palette_btn, preview_chip)
	palette_btn.pressed.connect(func():
		scene.call("play_click")
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
		update_palette_btn(palette_btn, preview_chip)
		var bd: Control = scene.get("sonar_backdrop")
		if bd != null:
			bd.queue_redraw()
	)
	scene.call("wire_juice", palette_btn)
	palette_box.add_child(palette_btn)

	root.add_child(SettingsUIFactory.create_setting_row(
		"SONAR PHOSPHOR COLOR",
		"Choose the bioluminescent acoustic frequency theme for echo ripples and scan markers.",
		palette_box
	))

	root.add_child(SettingsUIFactory.create_category_divider())

	root.add_child(SettingsUIFactory.create_section_header("EXPEDITION ARCHIVE & DATA"))

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
	lvl_lbl.add_theme_font_size_override("font_size", 13)
	lvl_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 0.95))
	diag_box.add_child(lvl_lbl)

	var floor_lbl := Label.new()
	floor_lbl.text = "CALIBRATED AMBIENT NOISE FLOOR:  %.1f dB" % GameState.mic_noise_floor_db
	floor_lbl.add_theme_font_size_override("font_size", 12)
	floor_lbl.add_theme_color_override("font_color", Color(0.4, 0.65, 0.85, 0.75))
	diag_box.add_child(floor_lbl)

	diag_card.add_child(diag_box)
	root.add_child(diag_card)

	# Replay Prologue / Opening Story
	var prologue_btn := Button.new()
	prologue_btn.custom_minimum_size = Vector2(160, 32)
	prologue_btn.focus_mode = Control.FOCUS_NONE
	prologue_btn.text = "REPLAY PROLOGUE"
	SettingsUIFactory.style_action_button(prologue_btn, Color(0.35, 0.85, 1.0, 0.85), Color(0.04, 0.14, 0.25, 0.85), true)
	prologue_btn.pressed.connect(func():
		scene.call("play_click")
		GameState.transition_to_scene("res://ui/screens/intro_cutscene.tscn")
	)
	scene.call("wire_juice", prologue_btn)

	root.add_child(SettingsUIFactory.create_setting_row(
		"OPENING PROLOGUE",
		"Re-experience the initial awakening at the bottom of the abyss and the tutorial sequence.",
		prologue_btn
	))

	root.add_child(SettingsUIFactory.create_category_divider())

	# Danger Zone: Reset Progress / Return to Abyss
	root.add_child(SettingsUIFactory.create_section_header("DANGER ZONE • RETURN TO ABYSS"))

	var has_cleared_adv := GameState.highest_unlocked_level > 1
	var reset_btn := Button.new()
	reset_btn.custom_minimum_size = Vector2(160, 32)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_font_size_override("font_size", 12)
	if has_cleared_adv:
		reset_btn.text = "RETURN TO ABYSS"
		SettingsUIFactory.style_danger_button(reset_btn, false, true)
		reset_btn.pressed.connect(func(): scene.call("open_confirm_modal"))
		scene.call("wire_juice", reset_btn)
	else:
		reset_btn.text = "LOCKED (%s)" % GameState.get_level_name(1)
		reset_btn.disabled = true
		SettingsUIFactory.style_disabled_button(reset_btn, true)

	var adv_desc := "Reset Story Mode's 20 sectors back to Sector 01. Challenge Mode and Tutorial progress are preserved." if GameState.is_challenge_unlocked() else "Reset Story Mode's 20 sectors back to Sector 01. Tutorial progress is preserved."

	root.add_child(SettingsUIFactory.create_setting_row(
		"RETURN TO ABYSS",
		adv_desc,
		reset_btn
	))

	return root
