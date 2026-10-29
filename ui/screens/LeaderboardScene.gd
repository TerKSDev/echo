extends Control
## Full-Screen Huawei Game Service Leaderboard Screen for ECHO.
## Displays global speedrun rankings, sector par times, player telemetry,
## and on-demand HUAWEI ID authentication.

@onready var back_button: Button = $TopBar/BackButton
@onready var title_lbl: Label = $TopBar/TitleBox/Title
@onready var subtitle_lbl: Label = $TopBar/TitleBox/Subtitle

@onready var account_status_pill: PanelContainer = $TopBar/AccountBox/AccountStatusPill
@onready var account_status_lbl: Label = $TopBar/AccountBox/AccountStatusPill/Margin/AccountStatusLabel
@onready var account_action_btn: Button = $TopBar/AccountBox/AccountActionBtn

@onready var prev_sector_btn: Button = $SectorBar/PrevSectorBtn
@onready var next_sector_btn: Button = $SectorBar/NextSectorBtn
@onready var sector_info_card: PanelContainer = $SectorBar/SectorInfoCard
@onready var sector_name_lbl: Label = $SectorBar/SectorInfoCard/Margin/SectorBox/SectorNameLabel
@onready var sector_depth_lbl: Label = $SectorBar/SectorInfoCard/Margin/SectorBox/SectorDepthLabel

@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

var _current_sector: int = 1
var _max_sector: int = 21

var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_back: AudioStreamWAV

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()

	_max_sector = GameState.LEVELS.size()
	_current_sector = clampi(GameState.leaderboard_default_sector, 1, _max_sector)

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	_setup_top_bar()
	_setup_sector_bar()
	HMSService.auth_status_changed.connect(func(_logged): _refresh_view())

	_refresh_view()
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
		var target_top := maxf(top_pad + 6.0, 29.0)
		if has_node("TopBar"):
			$TopBar.position.y = target_top
		if has_node("SectorBar"):
			$SectorBar.position.y = target_top + 70.0
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 126.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta

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


func _setup_top_bar() -> void:
	if back_button != null:
		back_button.text = ""
		back_button.custom_minimum_size = Vector2(32, 44)
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

	if account_status_pill != null:
		var pill_style := StyleBoxFlat.new()
		pill_style.bg_color = Color(0.03, 0.08, 0.14, 0.88)
		pill_style.border_color = Color(0.2, 0.45, 0.70, 0.55)
		pill_style.set_border_width_all(1)
		pill_style.set_corner_radius_all(10)
		account_status_pill.add_theme_stylebox_override("panel", pill_style)

	if account_action_btn != null:
		account_action_btn.pressed.connect(_on_account_action_pressed)
		wire_juice(account_action_btn)


func _setup_sector_bar() -> void:
	if sector_info_card != null:
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.04, 0.12, 0.20, 0.88)
		card_style.border_color = Color(0.35, 0.80, 1.0, 0.6)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(10)
		sector_info_card.add_theme_stylebox_override("panel", card_style)

	if prev_sector_btn != null:
		_style_nav_btn(prev_sector_btn)
		prev_sector_btn.pressed.connect(_on_prev_sector_pressed)
		wire_juice(prev_sector_btn)

	if next_sector_btn != null:
		_style_nav_btn(next_sector_btn)
		next_sector_btn.pressed.connect(_on_next_sector_pressed)
		wire_juice(next_sector_btn)


func _style_nav_btn(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.14, 0.24, 0.90)
	sb.border_color = Color(0.35, 0.82, 1.0, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))


func _on_prev_sector_pressed() -> void:
	_play_ui_sound(_wav_click, -6.0, 1.1)
	_current_sector = _max_sector if _current_sector <= 1 else _current_sector - 1
	_refresh_view()


func _on_next_sector_pressed() -> void:
	_play_ui_sound(_wav_click, -6.0, 1.1)
	_current_sector = 1 if _current_sector >= _max_sector else _current_sector + 1
	_refresh_view()


func _on_account_action_pressed() -> void:
	_play_ui_sound(_wav_click, -4.0, 1.0)
	if HMSService.is_logged_in:
		HMSService.logout_huawei()
		_refresh_view()
	else:
		HMSService.login_huawei(func(_name): _refresh_view())


func _refresh_view() -> void:
	# 1. Update Account Bar
	if HMSService.is_logged_in:
		account_status_lbl.text = "◈ HUAWEI ID: %s" % HMSService.display_name
		account_status_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75, 1.0))
		account_action_btn.text = "SIGN OUT"
		_style_action_btn(account_action_btn, false)
	else:
		account_status_lbl.text = "◈ CASUAL EXPLORER (OFFLINE)"
		account_status_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 0.95, 0.85))
		account_action_btn.text = "SIGN IN"
		_style_action_btn(account_action_btn, true)

	# 2. Update Sector Card
	var sec_name: String = GameState.get_level_name(_current_sector)
	var sec_depth: String = GameState.get_level_depth_str(_current_sector)
	sector_name_lbl.text = "SECTOR %02d: %s" % [_current_sector, sec_name]
	sector_depth_lbl.text = "•  DEPTH: %s" % sec_depth

	# 3. Populate Main Area Content
	for child in content_box.get_children():
		child.queue_free()

	_build_personal_best_card()
	_build_table_header()
	_build_leaderboard_rows()

	if scroll_container != null:
		scroll_container.scroll_vertical = 0


func _style_action_btn(btn: Button, is_sign_in: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4

	if is_sign_in:
		sb.bg_color = Color(0.55, 0.12, 0.16, 0.92)
		sb.border_color = Color(1.0, 0.35, 0.4, 0.95)
		sb.set_border_width_all(1)
		btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	else:
		sb.bg_color = Color(0.04, 0.12, 0.2, 0.85)
		sb.border_color = Color(0.28, 0.50, 0.75, 0.6)
		sb.set_border_width_all(1)
		btn.add_theme_color_override("font_color", Color(0.7, 0.82, 0.95, 0.8))

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _build_personal_best_card() -> void:
	var best_t: float = GameState.get_level_best_time(_current_sector)
	var stars: int = GameState.get_level_stars(_current_sector)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 18.0
	style.content_margin_top = 10.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 10.0
	style.bg_color = Color(0.03, 0.09, 0.16, 0.88)
	style.border_color = Color(0.35, 0.85, 1.0, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	card.add_child(hbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "⚡"
	icon_lbl.add_theme_font_size_override("font_size", 16)
	icon_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	hbox.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "YOUR SECTOR RECORD:"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.85))
	hbox.add_child(title_lbl)

	var record_lbl := Label.new()
	record_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_lbl.add_theme_font_size_override("font_size", 13)

	if stars > 0 and best_t > 0.0 and best_t < 900.0:
		var mins := floori(best_t / 60.0)
		var secs := int(best_t) % 60
		var frac := int((best_t - floorf(best_t)) * 100.0)
		var time_str := "%02d:%02d.%02d" % [mins, secs, frac]
		var star_str := "★".repeat(stars) + "☆".repeat(maxi(0, 3 - stars))
		record_lbl.text = "%s  •  %s  •  %s" % [time_str, star_str, "HMS SYNCED" if HMSService.is_logged_in else "LOCAL"]
		record_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75, 1.0))
	else:
		record_lbl.text = "UNEXPLORED / NOT CLEARED YET"
		record_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.65))
	hbox.add_child(record_lbl)

	content_box.add_child(card)


func _build_table_header() -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 18.0
	style.content_margin_top = 8.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 8.0
	style.bg_color = Color(0.015, 0.045, 0.08, 0.75)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var h_rank := Label.new()
	h_rank.text = "RANK"
	h_rank.custom_minimum_size = Vector2(60, 0)
	h_rank.add_theme_font_size_override("font_size", 11)
	h_rank.add_theme_color_override("font_color", Color(0.45, 0.72, 0.95, 0.85))
	hbox.add_child(h_rank)

	var h_name := Label.new()
	h_name.text = "EXPLORER (DEVICE)"
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_name.add_theme_font_size_override("font_size", 11)
	h_name.add_theme_color_override("font_color", Color(0.45, 0.72, 0.95, 0.85))
	hbox.add_child(h_name)

	var h_stars := Label.new()
	h_stars.text = "RATING"
	h_stars.custom_minimum_size = Vector2(80, 0)
	h_stars.add_theme_font_size_override("font_size", 11)
	h_stars.add_theme_color_override("font_color", Color(0.45, 0.72, 0.95, 0.85))
	hbox.add_child(h_stars)

	var h_time := Label.new()
	h_time.text = "ESCAPE TIME"
	h_time.custom_minimum_size = Vector2(90, 0)
	h_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h_time.add_theme_font_size_override("font_size", 11)
	h_time.add_theme_color_override("font_color", Color(0.45, 0.72, 0.95, 0.85))
	hbox.add_child(h_time)

	content_box.add_child(card)


func _build_leaderboard_rows() -> void:
	var entries: Array = HMSService.get_sector_leaderboard(_current_sector)
	for i in entries.size():
		var row := _build_leaderboard_row(i + 1, entries[i])
		content_box.add_child(row)


func _build_leaderboard_row(rank: int, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var is_me: bool = (data.get("name") == HMSService.display_name and HMSService.is_logged_in)

	if is_me:
		style.bg_color = Color(0.08, 0.24, 0.38, 0.95)
		style.set_border_width_all(1)
		style.border_color = Color(0.35, 0.95, 1.0, 0.95)
		style.shadow_color = Color(0.2, 0.6, 1.0, 0.3)
		style.shadow_size = 4
	else:
		style.bg_color = Color(0.025, 0.065, 0.11, 0.85) if rank % 2 == 1 else Color(0.018, 0.048, 0.085, 0.85)
		style.set_border_width_all(0)

	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Rank badge
	var rank_lbl := Label.new()
	rank_lbl.custom_minimum_size = Vector2(60, 0)
	rank_lbl.add_theme_font_size_override("font_size", 14)
	match rank:
		1:
			rank_lbl.text = "🥇 #1"
			rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
		2:
			rank_lbl.text = "🥈 #2"
			rank_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		3:
			rank_lbl.text = "🥉 #3"
			rank_lbl.add_theme_color_override("font_color", Color(0.95, 0.68, 0.45, 1.0))
		_:
			rank_lbl.text = "   #%d" % rank
			rank_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88, 0.8))
	hbox.add_child(rank_lbl)

	# Name + Device
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 2)
	hbox.add_child(name_box)

	var name_lbl := Label.new()
	var raw_name: String = str(data.get("name", "Unknown Explorer"))
	name_lbl.text = raw_name + (" (YOU)" if is_me else "")
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0, 1.0) if is_me else Color(0.90, 0.96, 1.0, 0.95))
	name_box.add_child(name_lbl)

	var dev_lbl := Label.new()
	dev_lbl.text = str(data.get("device", "HUAWEI Device"))
	dev_lbl.add_theme_font_size_override("font_size", 10)
	dev_lbl.add_theme_color_override("font_color", Color(0.42, 0.62, 0.78, 0.65))
	name_box.add_child(dev_lbl)

	# Stars
	var stars_lbl := Label.new()
	stars_lbl.custom_minimum_size = Vector2(80, 0)
	var s_count: int = int(data.get("stars", 3))
	stars_lbl.text = "★".repeat(s_count) + "☆".repeat(maxi(0, 3 - s_count))
	stars_lbl.add_theme_font_size_override("font_size", 13)
	stars_lbl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.30, 0.95))
	hbox.add_child(stars_lbl)

	# Time
	var time_lbl := Label.new()
	time_lbl.custom_minimum_size = Vector2(90, 0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var t_val: float = float(data.get("time", 0.0))
	var mins := floori(t_val / 60.0)
	var secs := int(t_val) % 60
	var frac := int((t_val - floorf(t_val)) * 100.0)
	time_lbl.text = "%02d:%02d.%02d" % [mins, secs, frac]
	time_lbl.add_theme_font_size_override("font_size", 13)
	time_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.80, 1.0) if is_me else Color(0.88, 0.96, 1.0, 0.95))
	hbox.add_child(time_lbl)

	return panel


func _init_spores() -> void:
	_spores.clear()
	var w := maxf(size.x, 720.0)
	var h := maxf(size.y, 1280.0)
	for i in range(36):
		_spores.append({
			"pos": Vector2(randf_range(0.0, w), randf_range(0.0, h)),
			"speed": randf_range(12.0, 32.0),
			"phase": randf_range(0.0, TAU),
			"r": randf_range(1.2, 2.8),
			"alpha": randf_range(0.12, 0.40)
		})


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


func _on_back_pressed() -> void:
	_play_ui_sound(_wav_back, -4.0, 0.95)
	GameState.go_to_previous_scene()


func wire_juice(btn: Button) -> void:
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.02, 1.02), 0.1)
		_play_ui_sound(_wav_hover, -10.0, 1.05)
	)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12)
	)
	btn.button_down.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.05)
	)
	btn.button_up.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
	)


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
