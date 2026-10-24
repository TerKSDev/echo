extends Control

const MIX_RATE := 22050
const LEVEL_BUTTON_HEIGHT := 56.0
const BOTTOM_BUTTON_HEIGHT := 56.0
const TEST_LEVEL_PATH := "res://levels/level_test.tscn"

@onready var level_grid: GridContainer = $CenterContainer/Content/ScrollContainer/LevelGrid
@onready var test_arena_button: Button = $TopBar/TestArenaButton
@onready var back_button: Button = $TopBar/BackButton
@onready var intel_button: Button = $TopBar/IntelButton
@onready var settings_button: Button = $TopBar/SettingsButton
@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $CenterContainer/Content/ScrollContainer

var _time := 0.0
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _suppress_level_click := false

# Procedural UI Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV

# Modal overlay nodes
var _modal_root: Control
var _modal_dimmer: ColorRect
var _modal_panel: PanelContainer
var _modal_title: Label
var _modal_subtitle: Label
var _modal_scroll: ScrollContainer
var _modal_body: VBoxContainer
var _is_modal_open := false
var _menu_mic: MicInput
var _menu_meter_canvas: Control
var _menu_calib_btn: Button


func _ready() -> void:
	_build_ui_audio()
	_init_spores()

	# Background effects should not block button input.
	sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	# Two columns create the left-right staggered vertical map.
	level_grid.columns = 2

	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	level_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Hide the scrollbar visually while retaining scrolling.
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.modulate.a = 0.0

	level_grid.add_theme_constant_override("h_separation", 12)
	level_grid.add_theme_constant_override("v_separation", 20)

	_style_bottom_button(test_arena_button)
	_style_bottom_button(intel_button)
	_style_bottom_button(settings_button)
	_style_bottom_button(back_button)

	_create_level_buttons()

	test_arena_button.pressed.connect(_on_test_arena_pressed)
	intel_button.pressed.connect(_on_intel_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_wire_button_Juice(test_arena_button)
	_wire_button_Juice(intel_button)
	_wire_button_Juice(settings_button)
	_wire_button_Juice(back_button)

	_build_modal_shell()


# --------------------------------------------------
# GET PLAYABLE LEVELS
# --------------------------------------------------

func _get_playable_levels() -> Array[String]:
	var playable_levels: Array[String] = []

	for level_path in GameState.LEVELS:
		var path := str(level_path)

		# Exclude the test arena from the level selection map.
		if path == TEST_LEVEL_PATH:
			continue

		playable_levels.append(path)

	return playable_levels


# --------------------------------------------------
# BUTTON STYLES
# --------------------------------------------------

func _make_button_style(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _style_level_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override(
		"font_color",
		Color(0.76, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.45, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.9, 0.97, 1.0)
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.94),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(
			Color(0.06, 0.18, 0.29, 0.98),
			Color(0.25, 0.78, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(
			Color(0.08, 0.24, 0.36, 1.0),
			Color(0.4, 0.86, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"focus",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.94),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)


func _style_bottom_button(button: Button) -> void:
	button.custom_minimum_size.y = BOTTOM_BUTTON_HEIGHT

	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override(
		"font_color",
		Color(0.76, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.45, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.9, 0.97, 1.0)
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.96),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(
			Color(0.06, 0.18, 0.29, 1.0),
			Color(0.25, 0.78, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(
			Color(0.08, 0.24, 0.36, 1.0),
			Color(0.4, 0.86, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"focus",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.96),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)


# --------------------------------------------------
# LEVEL BUTTONS
# --------------------------------------------------

func _create_level_buttons() -> void:
	# Only create buttons for playable levels.
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()

	for i in range(1, total_levels + 1):
		var button := Button.new()
		var unlocked: bool = i <= GameState.highest_unlocked_level

		if unlocked:
			button.text = "◉\nDEPTH %02d" % i
			button.disabled = false
		else:
			button.text = "🔒\nDEPTH %02d" % i
			button.disabled = true

		button.custom_minimum_size = Vector2(
			110,
			LEVEL_BUTTON_HEIGHT
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.focus_mode = Control.FOCUS_NONE

		_style_level_button(button)

		if unlocked:
			button.pressed.connect(_on_level_pressed.bind(i))
			_wire_button_Juice(button)
		else:
			button.modulate = Color(0.45, 0.50, 0.58, 0.8)

		# Spacer creates the staggered left-right map.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(
			0,
			LEVEL_BUTTON_HEIGHT + 100.0
		)
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if i % 2 == 1:
			level_grid.add_child(button)
			level_grid.add_child(spacer)
		else:
			level_grid.add_child(spacer)
			level_grid.add_child(button)


func _on_level_pressed(level_number: int) -> void:
	if _is_modal_open:
		return

	# Ignore clicks if the player dragged the map.
	if _suppress_level_click:
		_suppress_level_click = false
		return

	var playable_levels := _get_playable_levels()
	var playable_index: int = level_number - 1

	if playable_index < 0 or playable_index >= playable_levels.size():
		push_error("Invalid level number: %d" % level_number)
		return

	# Find the actual index in GameState.LEVELS.
	var actual_level_index: int = GameState.LEVELS.find(
		playable_levels[playable_index]
	)

	if actual_level_index == -1:
		push_error(
			"Level not found in GameState.LEVELS: "
			+ playable_levels[playable_index]
		)
		return

	GameState.start_game(actual_level_index)


func _on_test_arena_pressed() -> void:
	if _is_modal_open:
		return
	GameState.start_game(0)


func _on_back_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 0.9)
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color.BLACK
	curtain.modulate.a = 0.0
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain.top_level = true
	curtain.z_index = 4096
	get_tree().root.add_child(curtain)

	var c_tw := curtain.create_tween()
	c_tw.tween_property(curtain, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_callback(func():
		GameState.go_to_menu()
		var fade_in := curtain.create_tween()
		fade_in.tween_interval(0.06)
		fade_in.tween_property(curtain, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(curtain.queue_free)
	)


# --------------------------------------------------
# SETTINGS & INTEL / BESTIARY MODALS
# --------------------------------------------------

func _on_settings_pressed() -> void:
	_open_modal("SETTINGS", "AUDIO & MICROPHONE SENSOR", 320.0)

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

	# Live MicInput for testing & calibration in Settings
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


func _on_intel_pressed() -> void:
	_open_modal("SURVIVAL INTEL", "MONSTER BESTIARY & ACOUSTIC SURVIVAL GUIDE", 520.0)

	_add_section_header("THREAT ARCHIVE / BESTIARY")
	_add_bestiary_card(
		Color(0.72, 0.45, 1.0),
		"SLEEPER",
		"DORMANT LURKER",
		"Remains in deep torpor within the shadows. Awakens only if you sprint or step directly into its immediate proximity halo.",
		"TIP: Hold SNEAK to quietly slip past its sleep radius."
	)
	_add_bestiary_card(
		Color(1.0, 0.82, 0.25),
		"PATROLLER",
		"ACOUSTIC SENTRY",
		"Relentlessly paces fixed cavern paths. Acute stereoscopic hearing allows it to detect even sneaking footsteps when within close range.",
		"TIP: Observe its patrol route; wait behind solid stone corners."
	)
	_add_bestiary_card(
		Color(1.0, 0.28, 0.28),
		"CHASER",
		"APEX PREDATOR",
		"Deaf to subtle sneaking footfalls, but possesses lethal charge velocity. The moment an acoustic wave touches it, it charges straight toward the sound origin.",
		"TIP: Never shout or emit sonar when a Chaser lurks near."
	)
	_add_bestiary_card(
		Color(0.95, 0.32, 0.72),
		"SCREAMER",
		"SONIC COCOON",
		"Stationary vocal entity. When disturbed by consecutive sound waves, it unleashes a deafening screech that reverberates across the entire cavern.",
		"TIP: Hide behind solid obstacles to block its concussive screech."
	)
	_add_bestiary_card(
		Color(0.22, 0.95, 0.68),
		"LISTENER",
		"THE HIVE EAR",
		"Completely deaf to normal footsteps. Accumulates sound waves; on reaching its 5th acoustic trigger, it transmits a global alarm to all beasts in the sector.",
		"TIP: Minimize voice and sonar usage; extract swiftly."
	)

	_add_divider()
	_add_section_header("ACOUSTIC MECHANICS & TACTICS")
	_add_guide_row(Color(0.35, 0.92, 1.0), "SNEAK / MUTE", "Hold [SHIFT / SNEAK] to silence footsteps and shrink your sound footprint.")
	_add_guide_row(Color(0.55, 0.96, 1.0), "SONAR ECHO", "Hold [SPACE / ECHO] or speak into your mic to reveal wall boundaries.")
	_add_guide_row(Color(0.3, 0.72, 0.95), "ACOUSTIC SHADOWS", "Solid stone walls absorb acoustic waves and block monster line of sight.")
	_add_guide_row(Color(0.45, 0.88, 0.62), "EXTRACTION", "Locate the escape ladder to clear the sector and unlock deeper cavern depths.")


func _add_bestiary_card(badge_color: Color, monster_name: String, role_text: String, description: String, tip: String) -> void:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 14.0
	card_style.content_margin_top = 10.0
	card_style.content_margin_right = 14.0
	card_style.content_margin_bottom = 10.0
	card_style.bg_color = Color(0.02, 0.07, 0.14, 0.75)
	card_style.border_color = badge_color.lerp(Color.WHITE, 0.2)
	card_style.border_color.a = 0.5
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", card_style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# Title line: colored dot + Name + Subtitle
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = badge_color
	hb.add_child(dot)

	var name_lbl := Label.new()
	name_lbl.text = monster_name
	name_lbl.add_theme_color_override("font_color", badge_color.lerp(Color.WHITE, 0.45))
	name_lbl.add_theme_font_size_override("font_size", 14)
	hb.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = "⟨ %s ⟩" % role_text
	role_lbl.add_theme_color_override("font_color", Color(badge_color.r, badge_color.g, badge_color.b, 0.75))
	role_lbl.add_theme_font_size_override("font_size", 11)
	hb.add_child(role_lbl)
	vb.add_child(hb)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 0.98, 0.92))
	desc_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(desc_lbl)

	# Tactical Tip
	var tip_lbl := Label.new()
	tip_lbl.text = tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_color_override("font_color", Color(0.42, 0.78, 1.0, 0.85))
	tip_lbl.add_theme_font_size_override("font_size", 11)
	vb.add_child(tip_lbl)

	_modal_body.add_child(card)


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


func _build_modal_shell() -> void:
	_modal_root = Control.new()
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.visible = false
	_modal_root.modulate.a = 0.0
	_modal_root.z_index = 100
	add_child(_modal_root)

	_modal_dimmer = ColorRect.new()
	_modal_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_dimmer.color = Color(0.0, 0.02, 0.05, 0.78)
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
	_modal_panel.custom_minimum_size = Vector2(580, 0)
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 24.0
	card_style.content_margin_top = 20.0
	card_style.content_margin_right = 24.0
	card_style.content_margin_bottom = 22.0
	card_style.bg_color = Color(0.04, 0.11, 0.2, 0.96)
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
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "✕"
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.05, 0.14, 0.24, 0.8)
	close_normal.set_border_width_all(1)
	close_normal.border_color = Color(0.28, 0.56, 0.82, 0.75)
	close_normal.set_corner_radius_all(20)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.12, 0.28, 0.44, 0.95)
	close_hover.set_border_width_all(1)
	close_hover.border_color = Color(0.48, 0.82, 1.0, 1.0)
	close_hover.set_corner_radius_all(20)
	close_btn.add_theme_stylebox_override("normal", close_normal)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.pressed.connect(_close_modal)
	header.add_child(close_btn)

	var top_div := ColorRect.new()
	top_div.custom_minimum_size = Vector2(0, 1)
	top_div.color = Color(0.2, 0.48, 0.74, 0.45)
	outer_vbox.add_child(top_div)

	_modal_scroll = ScrollContainer.new()
	_modal_scroll.custom_minimum_size = Vector2(530, 480)
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_vbox.add_child(_modal_scroll)

	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 12)
	_modal_scroll.add_child(_modal_body)


func _open_modal(title_text: String, subtitle_text: String, scroll_height: float = 460.0) -> void:
	for child in _modal_body.get_children():
		child.queue_free()

	_modal_scroll.custom_minimum_size.y = scroll_height
	_modal_title.text = title_text
	_modal_subtitle.text = subtitle_text
	_is_modal_open = true
	_modal_root.visible = true
	_modal_scroll.scroll_vertical = 0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_modal_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_modal_panel.scale = Vector2(0.93, 0.93)
	_modal_panel.pivot_offset = Vector2(290.0, 240.0)
	tw.tween_property(_modal_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_modal() -> void:
	if not _is_modal_open:
		return
	_play_ui_sound(_wav_click, -8.0, 0.9)
	_is_modal_open = false
	if _menu_mic != null and is_instance_valid(_menu_mic):
		_menu_mic.queue_free()
		_menu_mic = null
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
	key_lbl.custom_minimum_size = Vector2(110, 0)
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


# --------------------------------------------------
# AMBIENT SONAR AND FLOATING PARTICLES
# --------------------------------------------------

func _process(delta: float) -> void:
	_time += delta

	# Process modal live mic meter if open
	if _is_modal_open and _menu_meter_canvas != null and is_instance_valid(_menu_meter_canvas):
		_menu_meter_canvas.queue_redraw()
		if _menu_calib_btn != null and is_instance_valid(_menu_calib_btn) and _menu_mic != null:
			if _menu_mic.is_calibrating():
				_menu_calib_btn.text = "SAMPLING..."
				_menu_calib_btn.disabled = true
			else:
				_menu_calib_btn.text = "CALIBRATE ROOM"
				_menu_calib_btn.disabled = not GameState.mic_enabled

	# Create an ambient sonar wave every 2.6 seconds.
	if fmod(_time, 2.6) < delta:
		var title_center := Vector2(
			size.x * 0.5,
			size.y * 0.245
		)

		_ripples.append({
			"pos": title_center,
			"age": 0.0,
			"max_r": 320.0,
			"alpha": 0.35
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(
		func(ripple: Dictionary) -> bool:
			return float(ripple["age"]) < 2.8
	)

	for spore in _spores:
		var pos: Vector2 = spore["pos"]

		pos.y -= float(spore["speed"]) * delta
		pos.x += (
			sin(_time * 1.4 + float(spore["phase"]))
			* 12.0
			* delta
		)

		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(
				0.0,
				maxf(size.x, 600.0)
			)

		spore["pos"] = pos

	sonar_backdrop.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _is_modal_open:
		return

	# Clicking/touching empty space creates an ECHO wave.
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_ripples.append({
			"pos": event.position,
			"age": 0.0,
			"max_r": 180.0,
			"alpha": 0.45
		})


func _init_spores() -> void:
	for i in range(26):
		_spores.append({
			"pos": Vector2(
				randf_range(40.0, 760.0),
				randf_range(40.0, 960.0)
			),
			"r": randf_range(1.2, 2.8),
			"speed": randf_range(12.0, 28.0),
			"phase": randf() * TAU
		})


func _draw_sonar_backdrop() -> void:
	# Draw floating glowing particles.
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		var radius: float = float(spore["r"])

		var twinkle := 0.35 + 0.35 * sin(
			_time * 2.5 + float(spore["phase"])
		)

		sonar_backdrop.draw_circle(
			pos,
			radius * 2.4,
			Color(0.2, 0.75, 1.0, twinkle * 0.18)
		)

		sonar_backdrop.draw_circle(
			pos,
			radius,
			Color(0.55, 0.92, 1.0, twinkle)
		)

	# Draw expanding sonar rings.
	for ripple in _ripples:
		var progress := clampf(
			float(ripple["age"]) / 2.8,
			0.0,
			1.0
		)

		var radius := progress * float(ripple["max_r"])
		var alpha := (
			(1.0 - progress)
			* float(ripple["alpha"])
		)

		sonar_backdrop.draw_arc(
			ripple["pos"],
			radius,
			0.0,
			TAU,
			64,
			Color(0.35, 0.88, 1.0, alpha),
			1.8
		)


# --------------------------------------------------
# BUTTON HOVER AND CLICK EFFECTS
# --------------------------------------------------

func _wire_button_Juice(btn: Button) -> void:
	btn.mouse_entered.connect(func() -> void:
		_play_ui_sound(
			_wav_hover,
			-14.0,
			randf_range(0.98, 1.04)
		)

		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(1.03, 1.03),
			0.1
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	btn.mouse_exited.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2.ONE,
			0.12
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	btn.button_down.connect(func() -> void:
		_play_ui_sound(_wav_click, -5.0, 1.0)

		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(0.96, 0.96),
			0.06
		)
	)

	btn.button_up.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(1.02, 1.02),
			0.12
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


# --------------------------------------------------
# PROCEDURAL UI AUDIO
# --------------------------------------------------

func _build_ui_audio() -> void:
	_wav_click = _synth_tone(620.0, 920.0, 0.14)
	_wav_hover = _synth_tone(480.0, 540.0, 0.06)


func _synth_tone(
	f_start: float,
	f_end: float,
	dur: float
) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)

	var phase := 0.0

	for i in range(count):
		var t: float = float(i) / MIX_RATE
		var envelope := minf(t / 0.004, 1.0) * exp(-t * 24.0)
		var frequency := lerpf(f_start, f_end, t / dur)

		phase += TAU * frequency / MIX_RATE

		var sample := clampf(
			sin(phase) * envelope * 0.7,
			-1.0,
			1.0
		)

		bytes.encode_s16(
			i * 2,
			int(sample * 32767.0)
		)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes

	return wav


func _play_ui_sound(
	stream: AudioStreamWAV,
	vol_db: float,
	pitch: float
) -> void:
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"Master"

	add_child(player)

	player.finished.connect(player.queue_free)
	player.play()
