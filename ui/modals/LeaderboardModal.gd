extends Control
## Huawei Game Service Leaderboard & Challenge Mode Modal for ECHO.
## Displays global speedrun rankings, sector par times, and on-demand HUAWEI ID login.

signal closed

var _card: PanelContainer
var _dimmer: ColorRect
var _center: CenterContainer
var _account_banner: PanelContainer
var _account_lbl: Label
var _login_btn: Button
var _logout_btn: Button
var _sector_lbl: Label
var _prev_sector_btn: Button
var _next_sector_btn: Button
var _list_container: VBoxContainer

var _current_sector: int = 1
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 105
	visible = false
	modulate.a = 0.0
	_build_ui()
	_sync_viewport_size()
	HMSService.auth_status_changed.connect(func(_logged): _refresh_view())


static func open_modal(parent: Node, default_sector: int = 1) -> Control:
	var existing = parent.get_node_or_null("LeaderboardModal")
	if existing != null:
		existing.open(default_sector)
		return existing
	var script: GDScript = load("res://ui/modals/LeaderboardModal.gd") as GDScript
	var modal := script.new() as Control
	modal.name = "LeaderboardModal"
	parent.add_child(modal)
	modal.open(default_sector)
	return modal


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	ModalTemplate.apply_full_rect(self)
	if _dimmer != null:
		ModalTemplate.apply_full_rect(_dimmer)
	if _center != null:
		ModalTemplate.apply_full_rect(_center)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		close()
		get_viewport().set_input_as_handled()


func open(default_sector: int = 1) -> void:
	if _is_open:
		return
	_is_open = true
	var max_sec := GameState.LEVELS.size()
	_current_sector = clampi(default_sector, 1, max_sec)
	visible = true
	_sync_viewport_size()
	_refresh_view()

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card.scale = Vector2(0.94, 0.94)
	_card.pivot_offset = _card.size * 0.5 if _card.size.x > 50.0 else Vector2(ModalTemplate.CARD_WIDTH * 0.5, 310.0)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	closed.emit()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 1. Fullscreen Dimmer
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = ModalTemplate.DIMMER_COLOR
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dimmer)

	# 2. Center Alignment Container
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	# 3. Glassmorphic Card
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 620)
	_card.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(ModalTemplate.ThemeKind.CRIMSON))
	_center.add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_card.add_child(vbox)

	# --- Header Bar ---
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(32, 32)
	var red_bg := ColorRect.new()
	red_bg.custom_minimum_size = Vector2(30, 30)
	red_bg.color = Color(0.85, 0.14, 0.18, 1.0)
	icon_box.add_child(red_bg)
	var icon_lbl := Label.new()
	icon_lbl.text = "HW"
	icon_lbl.add_theme_font_size_override("font_size", 11)
	icon_lbl.add_theme_color_override("font_color", Color.WHITE)
	icon_box.add_child(icon_lbl)
	header.add_child(icon_box)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)

	var title_lbl := Label.new()
	title_lbl.text = "HUAWEI GAME SERVICE  •  GLOBAL LEADERBOARD"
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.48, 1.0))
	titles.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "Abyssal Speedrun & Stealth Par Challenge (Global Ranking)"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.82, 0.95, 0.8))
	titles.add_child(sub_lbl)

	var close_btn := ModalTemplate.make_close_button(close, ModalTemplate.ThemeKind.CRIMSON)
	header.add_child(close_btn)

	# --- Progressive Login Banner ---
	_account_banner = PanelContainer.new()
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.04, 0.08, 0.14, 0.9)
	banner_style.set_border_width_all(1)
	banner_style.border_color = Color(0.2, 0.45, 0.7, 0.45)
	banner_style.set_corner_radius_all(10)
	banner_style.content_margin_left = 14
	banner_style.content_margin_right = 14
	banner_style.content_margin_top = 8
	banner_style.content_margin_bottom = 8
	_account_banner.add_theme_stylebox_override("panel", banner_style)
	vbox.add_child(_account_banner)

	var banner_hbox := HBoxContainer.new()
	banner_hbox.add_theme_constant_override("separation", 10)
	_account_banner.add_child(banner_hbox)

	_account_lbl = Label.new()
	_account_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_lbl.add_theme_font_size_override("font_size", 12)
	banner_hbox.add_child(_account_lbl)

	_login_btn = Button.new()
	_login_btn.text = "SIGN IN WITH HUAWEI ID"
	_login_btn.custom_minimum_size = Vector2(170, 30)
	_login_btn.focus_mode = Control.FOCUS_NONE
	_login_btn.add_theme_font_size_override("font_size", 11)
	ModalTemplate.style_danger_button(_login_btn, true, true)
	_login_btn.pressed.connect(func():
		HMSService.login_huawei(func(_name): _refresh_view())
	)
	banner_hbox.add_child(_login_btn)

	_logout_btn = Button.new()
	_logout_btn.text = "SIGN OUT"
	_logout_btn.custom_minimum_size = Vector2(75, 30)
	_logout_btn.focus_mode = Control.FOCUS_NONE
	_logout_btn.flat = true
	_logout_btn.add_theme_font_size_override("font_size", 11)
	_logout_btn.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.7))
	_logout_btn.pressed.connect(func():
		HMSService.logout_huawei()
		_refresh_view()
	)
	banner_hbox.add_child(_logout_btn)

	# --- Sector Navigation Toolbar ---
	var sec_toolbar := HBoxContainer.new()
	sec_toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	sec_toolbar.add_theme_constant_override("separation", 14)
	vbox.add_child(sec_toolbar)

	_prev_sector_btn = Button.new()
	_prev_sector_btn.text = "◀"
	_prev_sector_btn.custom_minimum_size = Vector2(36, 30)
	_prev_sector_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(_prev_sector_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	_prev_sector_btn.pressed.connect(func():
		var max_sec := GameState.LEVELS.size()
		_current_sector = max_sec if _current_sector <= 1 else _current_sector - 1
		_refresh_view()
	)
	sec_toolbar.add_child(_prev_sector_btn)

	_sector_lbl = Label.new()
	_sector_lbl.text = "SECTOR 01: ABYSS ORIGIN"
	_sector_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sector_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sector_lbl.add_theme_font_size_override("font_size", 14)
	_sector_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	sec_toolbar.add_child(_sector_lbl)

	_next_sector_btn = Button.new()
	_next_sector_btn.text = "▶"
	_next_sector_btn.custom_minimum_size = Vector2(36, 30)
	_next_sector_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(_next_sector_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	_next_sector_btn.pressed.connect(func():
		var max_sec := GameState.LEVELS.size()
		_current_sector = 1 if _current_sector >= max_sec else _current_sector + 1
		_refresh_view()
	)
	sec_toolbar.add_child(_next_sector_btn)

	# --- Table Column Header ---
	var col_header := HBoxContainer.new()
	col_header.add_theme_constant_override("separation", 8)
	vbox.add_child(col_header)

	var h_rank := Label.new()
	h_rank.text = "RANK"
	h_rank.custom_minimum_size = Vector2(50, 0)
	h_rank.add_theme_font_size_override("font_size", 11)
	h_rank.add_theme_color_override("font_color", Color(0.45, 0.68, 0.88, 0.8))
	col_header.add_child(h_rank)

	var h_name := Label.new()
	h_name.text = "EXPLORER (DEVICE)"
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_name.add_theme_font_size_override("font_size", 11)
	h_name.add_theme_color_override("font_color", Color(0.45, 0.68, 0.88, 0.8))
	col_header.add_child(h_name)

	var h_stars := Label.new()
	h_stars.text = "RATING"
	h_stars.custom_minimum_size = Vector2(60, 0)
	h_stars.add_theme_font_size_override("font_size", 11)
	h_stars.add_theme_color_override("font_color", Color(0.45, 0.68, 0.88, 0.8))
	col_header.add_child(h_stars)

	var h_time := Label.new()
	h_time.text = "TIME"
	h_time.custom_minimum_size = Vector2(70, 0)
	h_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h_time.add_theme_font_size_override("font_size", 11)
	h_time.add_theme_color_override("font_color", Color(0.45, 0.68, 0.88, 0.8))
	col_header.add_child(h_time)

	# --- Scrollable Leaderboard List ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_container)


func _refresh_view() -> void:
	if not _is_open:
		return

	# Update Account status row
	if HMSService.is_logged_in:
		_account_lbl.text = "◈ HUAWEI ID: %s   (Rankings Synced)" % HMSService.display_name
		_account_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75, 1.0))
		_login_btn.visible = false
		_logout_btn.visible = true
	else:
		_account_lbl.text = "Casual Play Mode. Sign in with HUAWEI ID to rank your escape speed."
		_account_lbl.add_theme_color_override("font_color", Color(0.72, 0.82, 0.95, 0.85))
		_login_btn.visible = true
		_logout_btn.visible = false

	# Update Sector Title
	var sec_name: String = GameState.get_level_name(_current_sector)
	_sector_lbl.text = "SECTOR %02d: %s" % [_current_sector, sec_name]

	# Rebuild table rows
	for child in _list_container.get_children():
		child.queue_free()

	var entries: Array = HMSService.get_sector_leaderboard(_current_sector)
	for i in entries.size():
		var row := _build_leaderboard_row(i + 1, entries[i])
		_list_container.add_child(row)


func _build_leaderboard_row(rank: int, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var is_me: bool = (data.get("name") == HMSService.display_name and HMSService.is_logged_in)

	if is_me:
		style.bg_color = Color(0.08, 0.22, 0.35, 0.95)
		style.set_border_width_all(1)
		style.border_color = Color(0.35, 0.92, 1.0, 0.95)
	else:
		style.bg_color = Color(0.03, 0.07, 0.12, 0.75) if rank % 2 == 1 else Color(0.02, 0.05, 0.09, 0.75)
		style.set_border_width_all(0)

	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Rank badge (Top 3 have medals)
	var rank_lbl := Label.new()
	rank_lbl.custom_minimum_size = Vector2(50, 0)
	rank_lbl.add_theme_font_size_override("font_size", 12)
	match rank:
		1:
			rank_lbl.text = "#1"
			rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
		2:
			rank_lbl.text = "#2"
			rank_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
		3:
			rank_lbl.text = "#3"
			rank_lbl.add_theme_color_override("font_color", Color(0.9, 0.65, 0.45, 1.0))
		_:
			rank_lbl.text = "#%d" % rank
			rank_lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 0.8))
	hbox.add_child(rank_lbl)

	# Name + Device
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 1)
	hbox.add_child(name_box)

	var name_lbl := Label.new()
	var raw_name: String = str(data.get("name", "Unknown Explorer"))
	name_lbl.text = raw_name + (" (YOU)" if is_me else "")
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 1.0) if is_me else Color(0.88, 0.94, 1.0, 0.95))
	name_box.add_child(name_lbl)

	var dev_lbl := Label.new()
	dev_lbl.text = str(data.get("device", "HUAWEI Device"))
	dev_lbl.add_theme_font_size_override("font_size", 10)
	dev_lbl.add_theme_color_override("font_color", Color(0.42, 0.6, 0.75, 0.65))
	name_box.add_child(dev_lbl)

	# Stars
	var stars_lbl := Label.new()
	stars_lbl.custom_minimum_size = Vector2(60, 0)
	var s_count: int = int(data.get("stars", 3))
	stars_lbl.text = "★".repeat(s_count) + "☆".repeat(maxi(0, 3 - s_count))
	stars_lbl.add_theme_font_size_override("font_size", 12)
	stars_lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 0.95))
	hbox.add_child(stars_lbl)

	# Time
	var time_lbl := Label.new()
	time_lbl.custom_minimum_size = Vector2(70, 0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var t_val: float = float(data.get("time", 0.0))
	var mins := floori(t_val / 60.0)
	var secs := int(t_val) % 60
	var frac := int((t_val - floorf(t_val)) * 100.0)
	time_lbl.text = "%02d:%02d.%02d" % [mins, secs, frac]
	time_lbl.add_theme_font_size_override("font_size", 12)
	time_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75, 1.0) if is_me else Color(0.85, 0.95, 1.0, 0.9))
	hbox.add_child(time_lbl)

	return panel
