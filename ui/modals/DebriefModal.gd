extends Control
## Post-mission evaluation & debrief screen for ECHO.
## Displays level completion time, sonar pulses emitted, and monster detection count.
## Evaluates and animates the 3-star "Ghost Rating" with procedural sound chimes.

signal next_pressed
signal retry_pressed
signal select_pressed

var _dimmer: ColorRect
var _center: CenterContainer
var _card: PanelContainer
var _title_lbl: Label
var _subtitle_lbl: Label
var _rank_badge: Label

var _star_cards: Array[PanelContainer] = []
var _star_icons: Array[Label] = []
var _star_subs: Array[Label] = []

var _stat_time_val: Label
var _stat_pings_val: Label
var _stat_alerts_val: Label

var _btn_retry: Button
var _btn_select: Button
var _btn_next: Button
var _hms_sync_btn: Button

var _is_open := false
var _data: Dictionary = {}
var _sfx_mgr: SfxManager
var _cur_lvl_num: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_sync_viewport_size()
	_build_ui()
	HMSService.auth_status_changed.connect(func(_logged): _update_hms_button_state())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 50.0 and vp.y > 50.0:
		size = vp
		if _dimmer != null:
			_dimmer.size = vp
		if _center != null:
			_center.size = vp


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			get_viewport().set_input_as_handled()
			_on_next()
		elif event.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			_on_retry()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_select()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 1. Fullscreen Dimmer
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0.015, 0.03, 0.055, 0.92)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dimmer)

	# 2. Center Alignment Container
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.anchor_right = 1.0
	_center.anchor_bottom = 1.0
	add_child(_center)

	# 3. Main Glassmorphic Card
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(580, 555)
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.024, 0.055, 0.09, 0.98)
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color(0.25, 0.82, 0.95, 0.9)
	card_style.corner_radius_top_left = 18
	card_style.corner_radius_top_right = 18
	card_style.corner_radius_bottom_right = 18
	card_style.corner_radius_bottom_left = 18
	card_style.shadow_color = Color(0.08, 0.55, 0.95, 0.35)
	card_style.shadow_size = 24
	card_style.content_margin_left = 32
	card_style.content_margin_right = 32
	card_style.content_margin_top = 28
	card_style.content_margin_bottom = 28
	_card.add_theme_stylebox_override("panel", card_style)
	_center.add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(vbox)

	# --- Header: Kicker + Title ---
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 4)
	header_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_vbox)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = "ACOUSTIC EXTRACTION SUCCESSFUL"
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.add_theme_font_size_override("font_size", 12)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75, 0.95))
	header_vbox.add_child(_subtitle_lbl)

	_title_lbl = Label.new()
	_title_lbl.text = "SECTOR CLEARED"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 24)
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.55, 0.95, 0.8))
	_title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	header_vbox.add_child(_title_lbl)

	# --- Rank Pill ---
	var rank_container := HBoxContainer.new()
	rank_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(rank_container)

	_rank_badge = Label.new()
	_rank_badge.text = "RANK S  •  ABYSSAL PHANTOM"
	_rank_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_badge.add_theme_font_size_override("font_size", 13)
	_rank_badge.add_theme_color_override("font_color", Color(0.35, 0.92, 1.0))
	rank_container.add_child(_rank_badge)

	# --- Three Star / Badge Cards ---
	var stars_hbox := HBoxContainer.new()
	stars_hbox.add_theme_constant_override("separation", 14)
	stars_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stars_hbox)

	var star_specs: Array[Dictionary] = [
		{"name": "SURVIVOR", "cond": "SURVIVE & ESCAPE"},
		{"name": "GHOST", "cond": "ZERO ALERTS"},
		{"name": "SWIFT ECHO", "cond": "BEAT PAR TIME"}
	]

	_star_cards.clear()
	_star_icons.clear()
	_star_subs.clear()

	for i in 3:
		var spec: Dictionary = star_specs[i]
		var sc := PanelContainer.new()
		sc.custom_minimum_size = Vector2(160, 110)
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sc_style := StyleBoxFlat.new()
		sc_style.bg_color = Color(0.018, 0.04, 0.07, 0.85)
		sc_style.border_width_left = 1
		sc_style.border_width_top = 1
		sc_style.border_width_right = 1
		sc_style.border_width_bottom = 1
		sc_style.border_color = Color(0.18, 0.32, 0.45, 0.75)
		sc_style.corner_radius_top_left = 12
		sc_style.corner_radius_top_right = 12
		sc_style.corner_radius_bottom_right = 12
		sc_style.corner_radius_bottom_left = 12
		sc_style.content_margin_left = 8
		sc_style.content_margin_right = 8
		sc_style.content_margin_top = 10
		sc_style.content_margin_bottom = 10
		sc.add_theme_stylebox_override("panel", sc_style)

		var svbox := VBoxContainer.new()
		svbox.alignment = BoxContainer.ALIGNMENT_CENTER
		svbox.add_theme_constant_override("separation", 4)
		sc.add_child(svbox)

		var icon := Label.new()
		icon.text = "☆"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 28)
		icon.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.6))
		icon.pivot_offset = Vector2(14, 18)
		svbox.add_child(icon)

		var sname := Label.new()
		sname.text = spec["name"]
		sname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sname.add_theme_font_size_override("font_size", 12)
		sname.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		svbox.add_child(sname)

		var ssub := Label.new()
		ssub.text = spec["cond"]
		ssub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ssub.add_theme_font_size_override("font_size", 10)
		ssub.add_theme_color_override("font_color", Color(0.45, 0.62, 0.75, 0.8))
		svbox.add_child(ssub)

		stars_hbox.add_child(sc)
		_star_cards.append(sc)
		_star_icons.append(icon)
		_star_subs.append(ssub)

	# --- Telemetry Statistics Box ---
	var stat_panel := PanelContainer.new()
	var stat_style := StyleBoxFlat.new()
	stat_style.bg_color = Color(0.015, 0.035, 0.065, 0.9)
	stat_style.border_width_left = 1
	stat_style.border_width_top = 1
	stat_style.border_width_right = 1
	stat_style.border_width_bottom = 1
	stat_style.border_color = Color(0.12, 0.28, 0.42, 0.6)
	stat_style.corner_radius_top_left = 10
	stat_style.corner_radius_top_right = 10
	stat_style.corner_radius_bottom_right = 10
	stat_style.corner_radius_bottom_left = 10
	stat_style.content_margin_left = 20
	stat_style.content_margin_right = 20
	stat_style.content_margin_top = 12
	stat_style.content_margin_bottom = 12
	stat_panel.add_theme_stylebox_override("panel", stat_style)
	vbox.add_child(stat_panel)

	var stat_grid := GridContainer.new()
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 24)
	stat_grid.add_theme_constant_override("v_separation", 6)
	stat_panel.add_child(stat_grid)

	# Column 1: Time
	var t_box := _build_stat_cell("ESCAPE TIME", "--:--")
	_stat_time_val = t_box.get_node("Val")
	stat_grid.add_child(t_box)

	# Column 2: Pings
	var p_box := _build_stat_cell("SONAR PINGS", "0")
	_stat_pings_val = p_box.get_node("Val")
	stat_grid.add_child(p_box)

	# Column 3: Alerts
	var a_box := _build_stat_cell("MONSTER ALERTS", "0")
	_stat_alerts_val = a_box.get_node("Val")
	stat_grid.add_child(a_box)

	# --- Huawei Leaderboard / HMS Sync Bar ---
	var hms_row := HBoxContainer.new()
	hms_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hms_row)

	_hms_sync_btn = Button.new()
	_hms_sync_btn.focus_mode = Control.FOCUS_NONE
	_hms_sync_btn.custom_minimum_size = Vector2(420, 34)
	_hms_sync_btn.pressed.connect(_on_hms_button_pressed)
	_style_hms_button(_hms_sync_btn)
	_update_hms_button_state()
	hms_row.add_child(_hms_sync_btn)

	# --- Action Buttons ---
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	_btn_retry = _build_action_button("RETRY", false)
	_btn_retry.pressed.connect(_on_retry)
	btn_hbox.add_child(_btn_retry)

	_btn_select = _build_action_button("LEVEL SELECT", false)
	_btn_select.pressed.connect(_on_select)
	btn_hbox.add_child(_btn_select)

	_btn_next = _build_action_button("NEXT SECTOR >", true)
	_btn_next.pressed.connect(_on_next)
	btn_hbox.add_child(_btn_next)


func _build_stat_cell(title: String, default_val: String) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.alignment = BoxContainer.ALIGNMENT_CENTER

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.48, 0.65, 0.8, 0.85))
	c.add_child(lbl)

	var val := Label.new()
	val.name = "Val"
	val.text = default_val
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	c.add_child(val)
	return c


func _build_action_button(text: String, is_primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 44)
	b.focus_mode = Control.FOCUS_NONE

	var norm := StyleBoxFlat.new()
	var hov := StyleBoxFlat.new()
	var prs := StyleBoxFlat.new()

	for sb: StyleBoxFlat in [norm, hov, prs]:
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.corner_radius_bottom_left = 10

	if is_primary:
		norm.bg_color = Color(0.06, 0.32, 0.52, 0.95)
		norm.border_width_left = 2
		norm.border_width_top = 2
		norm.border_width_right = 2
		norm.border_width_bottom = 2
		norm.border_color = Color(0.35, 0.88, 1.0, 0.95)

		hov.bg_color = Color(0.09, 0.42, 0.68, 0.98)
		hov.border_width_left = 2
		hov.border_width_top = 2
		hov.border_width_right = 2
		hov.border_width_bottom = 2
		hov.border_color = Color(0.65, 0.96, 1.0, 1.0)

		prs.bg_color = Color(0.12, 0.50, 0.80, 1.0)
		prs.border_width_left = 2
		prs.border_width_top = 2
		prs.border_width_right = 2
		prs.border_width_bottom = 2
		prs.border_color = Color(0.85, 1.0, 1.0, 1.0)
	else:
		norm.bg_color = Color(0.03, 0.08, 0.14, 0.88)
		norm.border_width_left = 1
		norm.border_width_top = 1
		norm.border_width_right = 1
		norm.border_width_bottom = 1
		norm.border_color = Color(0.20, 0.40, 0.58, 0.75)

		hov.bg_color = Color(0.05, 0.13, 0.22, 0.95)
		hov.border_width_left = 1
		hov.border_width_top = 1
		hov.border_width_right = 1
		hov.border_width_bottom = 1
		hov.border_color = Color(0.35, 0.65, 0.88, 0.95)

		prs.bg_color = Color(0.07, 0.18, 0.30, 1.0)
		prs.border_width_left = 1
		prs.border_width_top = 1
		prs.border_width_right = 1
		prs.border_width_bottom = 1
		prs.border_color = Color(0.50, 0.80, 0.98, 1.0)

	b.add_theme_stylebox_override("normal", norm)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", prs)
	b.add_theme_stylebox_override("focus", norm)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))

	b.mouse_entered.connect(func():
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2(1.03, 1.03), 0.08)
	)
	b.mouse_exited.connect(func():
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.1)
	)
	return b


# Open debrief modal with animated star reveals
func show_debrief(data: Dictionary, sfx: SfxManager = null) -> void:
	_data = data
	_sfx_mgr = sfx
	_is_open = true
	visible = true
	get_tree().paused = true
	_sync_viewport_size()

	var lvl_num: int = int(data.get("level_number", 1))
	var clear_time: float = float(data.get("clear_time", 0.0))
	var pings: int = int(data.get("pings", 0))
	var alerts: int = int(data.get("alerts", 0))
	var par_time: float = float(data.get("par_time", 45.0))
	var par_pings: int = int(data.get("par_pings", 12))

	var is_surv: bool = bool(data.get("is_survivor", true))
	var is_ghost: bool = bool(data.get("is_ghost", false))
	var is_swift: bool = bool(data.get("is_swift", false))
	var run_stars: int = int(data.get("run_stars", 1))

	_cur_lvl_num = lvl_num
	HMSService.submit_sector_score(lvl_num, clear_time, pings, run_stars)
	HMSService.check_sector_clear_achievement(lvl_num, pings, alerts, is_swift)
	_update_hms_button_state()

	# Format level title with sector name
	if GameState.current_mode == GameState.GameMode.STORY and GameState.current_level == 0:
		_title_lbl.text = "PROLOGUE CLEARED"
	else:
		_title_lbl.text = "%s CLEARED" % GameState.get_level_name(GameState.current_level)

	# Update telemetry stats
	var mins := floori(clear_time / 60.0)
	var secs := int(clear_time) % 60
	var ms := int((clear_time - int(clear_time)) * 10.0)
	var time_str := "%02d:%02d.%d" % [mins, secs, ms]
	_stat_time_val.text = "%s (PAR ≤ %0.0fs)" % [time_str, par_time]
	if is_swift:
		_stat_time_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.7))
	else:
		_stat_time_val.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))

	_stat_pings_val.text = "%d (PAR ≤ %d)" % [pings, par_pings]
	if pings <= par_pings:
		_stat_pings_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.7))
	else:
		_stat_pings_val.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))

	if alerts == 0:
		_stat_alerts_val.text = "0 (PERFECT GHOST)"
		_stat_alerts_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.65))
	else:
		_stat_alerts_val.text = "%d ALERTS" % alerts
		_stat_alerts_val.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))

	# Update condition subtitles
	_star_subs[0].text = "SURVIVED [DONE]"
	_star_subs[1].text = "0 ALERTS (ACTUAL: %d)" % alerts
	_star_subs[2].text = "≤ %0.1fs (ACTUAL: %s)" % [par_time, time_str]

	# Overall Rank Banner
	match run_stars:
		3:
			_rank_badge.text = "★ ★ ★  RANK: S  •  ABYSSAL PHANTOM"
			_rank_badge.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		2:
			_rank_badge.text = "★ ★ ☆  RANK: A  •  SILENT SHADOW"
			_rank_badge.add_theme_color_override("font_color", Color(0.35, 0.92, 0.70))
		_:
			_rank_badge.text = "★ ☆ ☆  RANK: B  •  CAVERN SURVIVOR"
			_rank_badge.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))

	# Next button label for final depth
	if not GameState.has_next_level():
		_btn_next.text = "FINALE VICTORY >"
	else:
		_btn_next.text = "NEXT SECTOR >"

	# Reset star visuals before animation
	for i in 3:
		_star_icons[i].text = "☆"
		_star_icons[i].scale = Vector2.ONE
		_star_icons[i].add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.5))
		var sc_style := _star_cards[i].get_theme_stylebox("panel") as StyleBoxFlat
		if sc_style != null:
			sc_style.border_color = Color(0.18, 0.32, 0.45, 0.6)

	# Smooth entrance animation
	_card.scale = Vector2(0.94, 0.94)
	_card.pivot_offset = Vector2(290.0, 260.0) if _card.size.x < 100.0 else _card.size * 0.5
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Sequenced star illumination with audio chimes
	var star_unlocked: Array[bool] = [is_surv, is_ghost, is_swift]
	var star_colors: Array[Color] = [
		Color(0.35, 0.92, 1.0),   # Cyan for Survivor
		Color(0.28, 0.95, 0.68),  # Emerald for Ghost
		Color(1.0, 0.85, 0.30)    # Gold for Swift
	]

	for i in 3:
		var delay := 0.38 + i * 0.28
		tw.tween_callback(func():
			if star_unlocked[i]:
				_animate_star_earn(i, star_colors[i])
			else:
				_star_icons[i].text = "☆"
				_star_icons[i].add_theme_color_override("font_color", Color(0.3, 0.38, 0.46, 0.45))
		).set_delay(delay if i == 0 else 0.28)


func _animate_star_earn(idx: int, star_color: Color) -> void:
	if not _is_open:
		return
	if _sfx_mgr != null:
		_sfx_mgr.play_star_chime(idx)

	var icon := _star_icons[idx]
	icon.text = "★"
	icon.add_theme_color_override("font_color", star_color)

	var sc_style := _star_cards[idx].get_theme_stylebox("panel") as StyleBoxFlat
	if sc_style != null:
		sc_style.border_color = star_color
		sc_style.bg_color = Color(star_color.r * 0.12, star_color.g * 0.12, star_color.b * 0.12, 0.92)

	# Pop punch tween
	icon.pivot_offset = Vector2(14, 18)
	icon.scale = Vector2(1.7, 1.7)
	var pop_tw := create_tween()
	pop_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pop_tw.tween_property(icon, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_next() -> void:
	_is_open = false
	get_tree().paused = false
	next_pressed.emit()


func _on_retry() -> void:
	_is_open = false
	get_tree().paused = false
	retry_pressed.emit()


func _on_select() -> void:
	_is_open = false
	get_tree().paused = false
	select_pressed.emit()


func _style_hms_button(btn: Button) -> void:
	var norm := StyleBoxFlat.new()
	var hov := StyleBoxFlat.new()
	var prs := StyleBoxFlat.new()
	for sb in [norm, hov, prs]:
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0

	norm.bg_color = Color(0.12, 0.02, 0.04, 0.85)
	norm.border_color = Color(0.85, 0.2, 0.25, 0.7)
	norm.set_border_width_all(1)

	hov.bg_color = Color(0.22, 0.04, 0.06, 0.95)
	hov.border_color = Color(1.0, 0.35, 0.4, 0.95)
	hov.set_border_width_all(1)

	prs.bg_color = Color(0.32, 0.06, 0.08, 1.0)
	prs.border_color = Color(1.0, 0.55, 0.6, 1.0)
	prs.set_border_width_all(1)

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", prs)
	btn.add_theme_stylebox_override("focus", norm)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.9))


func _update_hms_button_state() -> void:
	if _hms_sync_btn == null:
		return
	if HMSService.is_logged_in:
		var p_name: String = HMSService.get_player_name()
		_hms_sync_btn.text = "🔴 HUAWEI ID: %s • SYNCED (VIEW LEADERBOARD)" % p_name
		_hms_sync_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
	else:
		_hms_sync_btn.text = "🏆 JOIN GLOBAL SPEEDRUN RANKING (HUAWEI ID)"
		_hms_sync_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))


func _on_hms_button_pressed() -> void:
	var modal_script: GDScript = load("res://ui/modals/LeaderboardModal.gd") as GDScript
	if modal_script != null:
		modal_script.open_modal(self, _cur_lvl_num)
