extends Control
## Full-Screen Huawei Game Service Leaderboard Screen for ECHO.
## Unified Challenge Mode All-Sectors Speedrun Leaderboard (Levels 1 to 21 / SP).
## Features an Olympic-style Top 3 Podium (1st Center, 2nd Left, 3rd Right),
## Date-of-run tracking, sticky table header, floating raised player bar,
## and clean top-bar authentication controls.

@onready var back_button: Button = $TopBar/BackButton
@onready var title_lbl: Label = $TopBar/TitleBox/Title
@onready var subtitle_lbl: Label = $TopBar/TitleBox/Subtitle
@onready var account_action_btn: Button = $TopBar/AccountBox/AccountActionBtn

@onready var campaign_card: PanelContainer = $CampaignCard
@onready var campaign_icon_canvas: Control = $CampaignCard/Margin/CampaignBox/CampaignIconCanvas
@onready var campaign_tag_pill: PanelContainer = $CampaignCard/Margin/CampaignBox/CampaignTagPill

@onready var table_header: PanelContainer = $TableHeader
@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

@onready var bottom_bar: PanelContainer = $BottomBar
@onready var rank_pill: PanelContainer = $BottomBar/Margin/BottomHBox/RankPill
@onready var rank_label: Label = $BottomBar/Margin/BottomHBox/RankPill/RankPillMargin/RankLabel
@onready var player_name_label: Label = $BottomBar/Margin/BottomHBox/PlayerInfoBox/PlayerNameLabel
@onready var player_status_label: Label = $BottomBar/Margin/BottomHBox/PlayerInfoBox/PlayerStatusLabel
@onready var player_time_label: Label = $BottomBar/Margin/BottomHBox/TimeBox/PlayerTimeLabel
@onready var time_caption_label: Label = $BottomBar/Margin/BottomHBox/TimeBox/TimeCaptionLabel
@onready var locate_btn: Button = $BottomBar/Margin/BottomHBox/LocateBtn

var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_back: AudioStreamWAV
var _wav_error: AudioStreamWAV
var _wav_locate: AudioStreamWAV

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _row_nodes: Dictionary = {} # rank: int -> Control
var _nearby_bracket_box: VBoxContainer = null


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var vbar := scroll_container.get_v_scroll_bar()
		if vbar != null:
			vbar.modulate.a = 0.0
			vbar.custom_minimum_size = Vector2.ZERO
			vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hbar := scroll_container.get_h_scroll_bar()
		if hbar != null:
			hbar.modulate.a = 0.0
			hbar.custom_minimum_size = Vector2.ZERO
			hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if content_box != null:
		content_box.mouse_filter = Control.MOUSE_FILTER_PASS

	_setup_top_bar()
	_setup_campaign_card()
	_setup_table_header()
	_setup_bottom_bar()

	HMSService.auth_status_changed.connect(func(_logged): _refresh_view())

	if HMSService.is_logged_in and GameState.is_challenge_completed():
		var tot_t := GameState.get_total_challenge_time()
		if tot_t > 0.0:
			HMSService.submit_challenge_run(tot_t)

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
		if has_node("CampaignCard"):
			$CampaignCard.position.y = target_top + 58.0
		if has_node("TableHeader"):
			$TableHeader.position.y = target_top + 116.0
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 152.0

	if screen_sz.y > 0:
		var bottom_inset := float(screen_sz.y - (safe.position.y + safe.size.y))
		if bottom_inset > 0:
			var bot_pad := (bottom_inset / float(screen_sz.y)) * vp_sz.y
			if has_node("BottomBar"):
				var bbar := $BottomBar as Control
				bbar.offset_bottom = -48.0 - bot_pad
				bbar.offset_top = -116.0 - bot_pad
			if has_node("MainArea"):
				var main := $MainArea as Control
				main.offset_bottom = -130.0 - bot_pad


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

	if account_action_btn != null:
		account_action_btn.pressed.connect(_on_account_action_pressed)
		wire_juice(account_action_btn)


func _setup_campaign_card() -> void:
	if campaign_card != null:
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.025, 0.07, 0.13, 0.92)
		card_style.border_color = Color(0.35, 0.82, 1.0, 0.55)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(10)
		card_style.shadow_color = Color(0.08, 0.35, 0.65, 0.22)
		card_style.shadow_size = 6
		campaign_card.add_theme_stylebox_override("panel", card_style)

	if campaign_icon_canvas != null:
		campaign_icon_canvas.draw.connect(_draw_trophy_crest)

	if campaign_tag_pill != null:
		var tag_sb := StyleBoxFlat.new()
		tag_sb.bg_color = Color(0.04, 0.14, 0.22, 0.90)
		tag_sb.border_color = Color(0.35, 0.90, 0.75, 0.45)
		tag_sb.set_border_width_all(1)
		tag_sb.set_corner_radius_all(6)
		campaign_tag_pill.add_theme_stylebox_override("panel", tag_sb)


func _draw_trophy_crest() -> void:
	if campaign_icon_canvas == null:
		return
	var sz: Vector2 = campaign_icon_canvas.size
	var center := sz * 0.5
	var gold := Color(1.0, 0.82, 0.32, 0.95)
	var gold_dim := Color(1.0, 0.82, 0.32, 0.35)
	var cyan := Color(0.35, 0.92, 1.0, 0.85)

	# Outer subtle radar arc
	var r := minf(sz.x, sz.y) * 0.44
	campaign_icon_canvas.draw_arc(center, r, 0.0, TAU, 32, gold_dim, 1.0)

	# Vector acoustic trophy cup
	var top_w := 13.0
	var bot_w := 6.5
	var cup_h := 10.0
	var cup_top_y := center.y - 6.5
	var cup_bot_y := cup_top_y + cup_h

	# Rim
	campaign_icon_canvas.draw_line(Vector2(center.x - top_w * 0.5, cup_top_y), Vector2(center.x + top_w * 0.5, cup_top_y), gold, 1.6)
	# Sides
	campaign_icon_canvas.draw_line(Vector2(center.x - top_w * 0.5, cup_top_y), Vector2(center.x - bot_w * 0.5, cup_bot_y), gold, 1.6)
	campaign_icon_canvas.draw_line(Vector2(center.x + top_w * 0.5, cup_top_y), Vector2(center.x + bot_w * 0.5, cup_bot_y), gold, 1.6)
	# Bottom of cup
	campaign_icon_canvas.draw_line(Vector2(center.x - bot_w * 0.5, cup_bot_y), Vector2(center.x + bot_w * 0.5, cup_bot_y), gold, 1.6)

	# Stem
	var stem_bot_y := cup_bot_y + 4.0
	campaign_icon_canvas.draw_line(Vector2(center.x, cup_bot_y), Vector2(center.x, stem_bot_y), gold, 1.8)
	# Base
	var base_w := 11.0
	campaign_icon_canvas.draw_line(Vector2(center.x - base_w * 0.5, stem_bot_y), Vector2(center.x + base_w * 0.5, stem_bot_y), gold, 1.8)

	# Handles
	campaign_icon_canvas.draw_arc(Vector2(center.x - top_w * 0.5 - 1.2, cup_top_y + 3.8), 3.2, -PI * 0.6, PI * 0.6, 12, gold, 1.3)
	campaign_icon_canvas.draw_arc(Vector2(center.x + top_w * 0.5 + 1.2, cup_top_y + 3.8), 3.2, PI * 0.4, PI * 1.6, 12, gold, 1.3)

	# Center acoustic core dot
	campaign_icon_canvas.draw_circle(Vector2(center.x, cup_top_y + 4.5), 1.5, cyan)


func _setup_table_header() -> void:
	if table_header != null:
		var hdr_style := StyleBoxFlat.new()
		hdr_style.bg_color = Color(0.015, 0.045, 0.08, 0.90)
		hdr_style.border_color = Color(0.20, 0.45, 0.70, 0.40)
		hdr_style.set_border_width_all(0)
		hdr_style.border_width_bottom = 1
		table_header.add_theme_stylebox_override("panel", hdr_style)


func _setup_bottom_bar() -> void:
	if bottom_bar != null:
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = Color(0.02, 0.05, 0.09, 0.96)
		bar_style.border_color = Color(0.30, 0.75, 1.0, 0.70)
		bar_style.set_border_width_all(1)
		bar_style.border_width_top = 2
		bar_style.set_corner_radius_all(12)
		bar_style.shadow_color = Color(0.10, 0.45, 0.85, 0.25)
		bar_style.shadow_size = 12
		bottom_bar.add_theme_stylebox_override("panel", bar_style)

		# Allow clicking anywhere on bottom bar to trigger navigation
		bottom_bar.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_locate_pressed()
			elif event is InputEventScreenTouch and event.pressed:
				_on_locate_pressed()
		)

	if rank_pill != null:
		var pill_sb := StyleBoxFlat.new()
		pill_sb.bg_color = Color(0.04, 0.12, 0.22, 0.92)
		pill_sb.border_color = Color(0.30, 0.75, 1.0, 0.45)
		pill_sb.set_border_width_all(1)
		pill_sb.set_corner_radius_all(6)
		rank_pill.add_theme_stylebox_override("panel", pill_sb)

	if locate_btn != null:
		_style_locate_btn(locate_btn)
		locate_btn.pressed.connect(_on_locate_pressed)
		wire_juice(locate_btn)


func _style_locate_btn(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.24, 0.38, 0.90)
	sb.border_color = Color(0.35, 0.90, 1.0, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))


func _on_account_action_pressed() -> void:
	_play_ui_sound(_wav_click, -4.0, 1.0)
	if HMSService.is_logged_in:
		HMSService.logout_huawei()
		_refresh_view()
	else:
		# Enforce Rule 1: Must pass Story Mode to sign in with HUAWEI ID and compete
		if not GameState.is_story_completed():
			_play_ui_sound(_wav_error, -4.0, 0.85)
			HMSService.show_hms_toast("ACCESS RESTRICTED", "Complete Story Mode first to sign in with HUAWEI ID and enter Abyss Rankings.")
			return
		HMSService.login_huawei(func(_name): _refresh_view())


func _refresh_view() -> void:
	# 1. Update Top Bar Account Button:
	# If logged in, hide SIGN IN button completely to keep top right pristine clean!
	if HMSService.is_logged_in:
		account_action_btn.visible = false
	else:
		account_action_btn.visible = true
		account_action_btn.text = "SIGN IN"
		_style_action_btn(account_action_btn, true)

	# 2. Populate Main Area Content (Olympic Top 3 Podium + Rows 4..100)
	_row_nodes.clear()
	_nearby_bracket_box = null
	for child in content_box.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = HMSService.get_challenge_leaderboard(100)

	# Build Olympic-style Top 3 Podium (2nd on left, 1st center, 3rd on right)
	if entries.size() >= 3:
		var podium := _build_podium_stand(entries.slice(0, 3))
		content_box.add_child(podium)

		# Subheader divider for #04 ~ #100
		var div_card := PanelContainer.new()
		div_card.mouse_filter = Control.MOUSE_FILTER_PASS
		var div_style := StyleBoxFlat.new()
		div_style.bg_color = Color(0.015, 0.045, 0.08, 0.70)
		div_style.border_color = Color(0.20, 0.45, 0.70, 0.35)
		div_style.set_border_width_all(0)
		div_style.border_width_top = 1
		div_style.border_width_bottom = 1
		div_style.content_margin_top = 6
		div_style.content_margin_bottom = 6
		div_card.add_theme_stylebox_override("panel", div_style)

		var div_lbl := Label.new()
		div_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		div_lbl.text = "◈  GLOBAL EXPEDITION BOARD  //  RANKS #04 TO #100  ◈"
		div_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		div_lbl.add_theme_font_size_override("font_size", 10)
		div_lbl.add_theme_color_override("font_color", Color(0.40, 0.70, 0.95, 0.80))
		div_card.add_child(div_lbl)
		content_box.add_child(div_card)

	# Populate rows #04 to #100
	var start_idx := 3 if entries.size() >= 3 else 0
	for i in range(start_idx, entries.size()):
		var rank: int = i + 1
		var row := _build_leaderboard_row(rank, entries[i])
		_row_nodes[rank] = row
		content_box.add_child(row)

	# 3. Update Pinned Floating Bottom Bar
	_update_bottom_bar()

	if scroll_container != null:
		scroll_container.scroll_vertical = 0


## Builds the 3-column Olympic style podium stand (2nd Left, 1st Center, 3rd Right)
func _build_podium_stand(top3: Array[Dictionary]) -> Control:
	var podium_container := MarginContainer.new()
	podium_container.mouse_filter = Control.MOUSE_FILTER_PASS
	podium_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	podium_container.add_theme_constant_override("margin_top", 4)
	podium_container.add_theme_constant_override("margin_bottom", 8)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	podium_container.add_child(hbox)

	# 2nd Place on Left (Silver)
	if top3.size() >= 2:
		var p2 := _build_podium_pillar(2, top3[1], 134.0)
		_row_nodes[2] = p2
		hbox.add_child(p2)

	# 1st Place in Center (Gold Champion - Tallest & Most Prominent)
	if top3.size() >= 1:
		var p1 := _build_podium_pillar(1, top3[0], 156.0)
		_row_nodes[1] = p1
		hbox.add_child(p1)

	# 3rd Place on Right (Bronze)
	if top3.size() >= 3:
		var p3 := _build_podium_pillar(3, top3[2], 122.0)
		_row_nodes[3] = p3
		hbox.add_child(p3)

	return podium_container


func _build_podium_pillar(rank: int, data: Dictionary, height_px: float) -> PanelContainer:
	var pillar := PanelContainer.new()
	pillar.mouse_filter = Control.MOUSE_FILTER_PASS
	pillar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pillar.custom_minimum_size = Vector2(0, height_px)
	pillar.size_flags_vertical = Control.SIZE_SHRINK_END

	var is_me: bool = (data.get("name") == HMSService.display_name and HMSService.is_logged_in) or (data.get("is_me", false) == true)

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 8

	var rank_title: String
	var rank_col: Color
	var time_col: Color
	var num_watermark: String

	match rank:
		1:
			rank_title = "CHAMPION // 01"
			rank_col = Color(1.0, 0.86, 0.35)
			time_col = Color(1.0, 0.88, 0.40)
			num_watermark = "I"
			style.bg_color = Color(0.12, 0.08, 0.02, 0.95)
			style.border_color = Color(1.0, 0.82, 0.30, 0.95)
			style.set_border_width_all(1)
			style.border_width_top = 3
			style.shadow_color = Color(1.0, 0.75, 0.20, 0.32)
			style.shadow_size = 14
		2:
			rank_title = "2ND // 02"
			rank_col = Color(0.85, 0.92, 1.0)
			time_col = Color(0.85, 0.95, 1.0)
			num_watermark = "II"
			style.bg_color = Color(0.04, 0.08, 0.14, 0.92)
			style.border_color = Color(0.75, 0.88, 1.0, 0.85)
			style.set_border_width_all(1)
			style.border_width_top = 2
			style.shadow_color = Color(0.35, 0.65, 1.0, 0.20)
			style.shadow_size = 8
		3:
			rank_title = "3RD // 03"
			rank_col = Color(0.95, 0.68, 0.45)
			time_col = Color(0.95, 0.68, 0.45)
			num_watermark = "III"
			style.bg_color = Color(0.08, 0.05, 0.03, 0.92)
			style.border_color = Color(0.90, 0.60, 0.38, 0.85)
			style.set_border_width_all(1)
			style.border_width_top = 2
			style.shadow_color = Color(0.80, 0.45, 0.20, 0.18)
			style.shadow_size = 8

	if is_me:
		style.border_color = Color(0.35, 1.0, 1.0, 0.95)
		style.shadow_color = Color(0.2, 0.7, 1.0, 0.40)
		style.shadow_size = 12

	pillar.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	pillar.add_child(vbox)

	# Rank badge
	var badge_lbl := Label.new()
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_lbl.text = rank_title
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", 11 if rank == 1 else 10)
	badge_lbl.add_theme_color_override("font_color", rank_col)
	vbox.add_child(badge_lbl)

	# Explorer Name
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var raw_name: String = str(data.get("name", "Unknown Explorer"))
	name_lbl.text = raw_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 13 if rank == 1 else 12)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0) if is_me else Color.WHITE)
	vbox.add_child(name_lbl)

	# Device & Date
	var dev_lbl := Label.new()
	dev_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_lbl.text = str(data.get("device", "HUAWEI Device"))
	dev_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dev_lbl.add_theme_font_size_override("font_size", 9)
	dev_lbl.add_theme_color_override("font_color", Color(0.55, 0.70, 0.85, 0.65))
	vbox.add_child(dev_lbl)

	var date_lbl := Label.new()
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_lbl.text = str(data.get("date", "2026-10-28"))
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_lbl.add_theme_font_size_override("font_size", 9)
	date_lbl.add_theme_color_override("font_color", Color(0.50, 0.65, 0.80, 0.60))
	vbox.add_child(date_lbl)

	# Clear Time
	var time_lbl := Label.new()
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t_val: float = float(data.get("time", 0.0))
	time_lbl.text = _format_time(t_val)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_lbl.add_theme_font_size_override("font_size", 14 if rank == 1 else 13)
	time_lbl.add_theme_color_override("font_color", time_col)
	vbox.add_child(time_lbl)

	# Roman numeral pedestal base
	var base_num := Label.new()
	base_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_num.text = num_watermark
	base_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base_num.add_theme_font_size_override("font_size", 14 if rank == 1 else 12)
	base_num.add_theme_color_override("font_color", Color(rank_col.r, rank_col.g, rank_col.b, 0.35))
	vbox.add_child(base_num)

	return pillar


func _update_bottom_bar() -> void:
	var rank_info: Dictionary = HMSService.get_challenge_player_rank()
	var is_logged: bool = rank_info.get("is_logged_in", false)
	var sp_cleared: bool = rank_info.get("sp_cleared", false)
	var cleared_cnt: int = int(rank_info.get("cleared_count", 0))
	var tot_time: float = float(rank_info.get("total_time", 0.0))
	var disp_rank: String = str(rank_info.get("display_rank", "OFFLINE"))
	var can_locate: bool = rank_info.get("can_locate", false)

	if not is_logged:
		rank_label.text = "OFFLINE"
		rank_label.add_theme_color_override("font_color", Color(0.60, 0.72, 0.85, 0.85))
		player_name_label.text = "Guest Explorer"
		player_name_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95, 0.9))
		player_status_label.text = "HUAWEI Game Service • Sign in to record run"
		player_time_label.text = "--:--.--"
		time_caption_label.text = "TOTAL TIME"
		locate_btn.text = "SIGN IN"
		locate_btn.tooltip_text = "Sign in with HUAWEI ID to enter rankings"
	elif not sp_cleared:
		rank_label.text = "UNRANKED"
		rank_label.add_theme_color_override("font_color", Color(0.95, 0.68, 0.35, 0.95))
		player_name_label.text = "%s (YOU)" % HMSService.display_name
		player_name_label.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0, 1.0))
		player_status_label.text = "%d/21 Sectors Cleared • Complete King Sector SP to qualify" % cleared_cnt
		player_time_label.text = _format_time(tot_time) if tot_time > 0.0 else "--:--.--"
		time_caption_label.text = "CURRENT RUN"
		locate_btn.text = "INCOMPLETE"
		locate_btn.tooltip_text = "Clear all 21 sectors to enter rankings"
	else:
		rank_label.text = disp_rank
		match disp_rank:
			"#1":
				rank_label.text = "TOP 01"
				rank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
			"#2":
				rank_label.text = "TOP 02"
				rank_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
			"#3":
				rank_label.text = "TOP 03"
				rank_label.add_theme_color_override("font_color", Color(0.95, 0.68, 0.45, 1.0))
			_:
				if disp_rank.begins_with("TOP"):
					rank_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75, 1.0))
				else:
					rank_label.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0, 1.0))

		player_name_label.text = "%s (YOU)" % HMSService.display_name
		player_name_label.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0, 1.0))
		player_status_label.text = "21/21 Sectors Cleared • Active Global Pool"
		player_time_label.text = _format_time(tot_time)
		time_caption_label.text = "TOTAL TIME"

		if can_locate:
			locate_btn.text = "LOCATE"
			locate_btn.tooltip_text = "Jump to your rank in the leaderboard"
		else:
			locate_btn.text = "TOP 500"
			locate_btn.tooltip_text = "Rank within Top 500 required for locator"


func _on_locate_pressed() -> void:
	if not HMSService.is_logged_in:
		_on_account_action_pressed()
		return

	var rank_info: Dictionary = HMSService.get_challenge_player_rank()
	if not rank_info.get("sp_cleared", false):
		_play_ui_sound(_wav_error, -4.0, 0.85)
		HMSService.show_hms_toast("INCOMPLETE RUN", "Clear all 21 Challenge sectors (including SP level) to qualify for rank navigation.")
		return

	if not rank_info.get("can_locate", false):
		# Rank > 500
		_play_ui_sound(_wav_error, -4.0, 0.85)
		var disp: String = str(rank_info.get("display_rank", "TOP %"))
		HMSService.show_hms_toast("TOP 500 ONLY", "Currently ranked %s. Shave seconds to enter the Top 500 bracket to locate adjacent competitors!" % disp)
		return

	var rank: int = int(rank_info.get("rank", 1))
	_jump_to_rank(rank)


func _jump_to_rank(rank: int) -> void:
	if rank <= 3 and _row_nodes.has(rank):
		var target_pillar: Control = _row_nodes[rank]
		_scroll_to_node_and_pulse(target_pillar)
	elif rank > 3 and rank <= 100 and _row_nodes.has(rank):
		var target_row: Control = _row_nodes[rank]
		_scroll_to_node_and_pulse(target_row)
	elif rank > 100 and rank <= 500:
		_show_nearby_bracket_and_scroll(rank)


func _show_nearby_bracket_and_scroll(rank: int) -> void:
	if _nearby_bracket_box != null and is_instance_valid(_nearby_bracket_box):
		_nearby_bracket_box.queue_free()

	_nearby_bracket_box = VBoxContainer.new()
	_nearby_bracket_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_nearby_bracket_box.add_theme_constant_override("separation", 6)

	# Separator Banner
	var sep_card := PanelContainer.new()
	sep_card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.04, 0.16, 0.28, 0.90)
	sep_style.border_color = Color(0.35, 0.85, 1.0, 0.70)
	sep_style.set_border_width_all(1)
	sep_style.set_corner_radius_all(6)
	sep_style.content_margin_left = 16
	sep_style.content_margin_right = 16
	sep_style.content_margin_top = 8
	sep_style.content_margin_bottom = 8
	sep_card.add_theme_stylebox_override("panel", sep_style)

	var sep_lbl := Label.new()
	sep_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var min_r := maxi(101, rank - 2)
	var max_r := mini(500, rank + 2)
	sep_lbl.text = "◈  NEARBY COMPETITORS  //  RANKS #%d TO #%d  ◈" % [min_r, max_r]
	sep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep_lbl.add_theme_font_size_override("font_size", 11)
	sep_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 0.95))
	sep_card.add_child(sep_lbl)
	_nearby_bracket_box.add_child(sep_card)

	# Populate nearby rows
	var nearby_entries := HMSService.get_challenge_nearby_entries(rank, 2)
	var my_row_node: PanelContainer = null
	for item in nearby_entries:
		var item_rank: int = int(item.get("rank", rank))
		var row := _build_leaderboard_row(item_rank, item)
		_nearby_bracket_box.add_child(row)
		if item.get("is_me", false):
			my_row_node = row

	content_box.add_child(_nearby_bracket_box)

	# Smoothly scroll down to bracket
	call_deferred("_scroll_to_node_and_pulse", my_row_node if my_row_node != null else sep_card)


func _scroll_to_node_and_pulse(target_node: Control) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	_play_ui_sound(_wav_locate, -4.0, 1.15)

	var target_y: float = target_node.position.y
	var view_h: float = scroll_container.size.y
	var vbar := scroll_container.get_v_scroll_bar()
	var max_scroll := int(vbar.max_value - vbar.page) if vbar != null else 1000
	var scroll_target: int = clampi(int(target_y - view_h * 0.35), 0, max_scroll)

	var tw := create_tween()
	tw.tween_property(scroll_container, "scroll_vertical", scroll_target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Flash pulse
	var pulse_tw := target_node.create_tween()
	pulse_tw.tween_property(target_node, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.15)
	pulse_tw.tween_property(target_node, "modulate", Color.WHITE, 0.35)


func _style_action_btn(btn: Button, is_sign_in: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
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


func _build_leaderboard_row(rank: int, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	var is_me: bool = (data.get("name") == HMSService.display_name and HMSService.is_logged_in) or (data.get("is_me", false) == true)

	if is_me:
		style.bg_color = Color(0.05, 0.18, 0.30, 0.95)
		style.set_border_width_all(1)
		style.border_color = Color(0.35, 1.0, 1.0, 0.95)
		style.shadow_color = Color(0.2, 0.7, 1.0, 0.35)
		style.shadow_size = 8
	else:
		style.bg_color = Color(0.022, 0.052, 0.090, 0.85) if rank % 2 == 1 else Color(0.015, 0.035, 0.065, 0.85)
		style.set_border_width_all(1)
		style.border_color = Color(0.18, 0.35, 0.55, 0.22)

	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Rank badge
	var rank_box := CenterContainer.new()
	rank_box.mouse_filter = Control.MOUSE_FILTER_PASS
	rank_box.custom_minimum_size = Vector2(68, 0)
	hbox.add_child(rank_box)

	var rank_lbl := Label.new()
	rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_lbl.text = "#%02d" % rank if rank < 100 else "#%d" % rank
	rank_lbl.add_theme_font_size_override("font_size", 13)
	rank_lbl.add_theme_color_override("font_color", Color(0.48, 0.68, 0.85, 0.85))
	rank_box.add_child(rank_lbl)

	# Name + Device
	var name_box := VBoxContainer.new()
	name_box.mouse_filter = Control.MOUSE_FILTER_PASS
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 1)
	hbox.add_child(name_box)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_PASS
	name_row.add_theme_constant_override("separation", 6)
	name_box.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var raw_name: String = str(data.get("name", "Unknown Explorer"))
	name_lbl.text = raw_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0, 1.0) if is_me else Color(0.88, 0.94, 1.0, 0.95))
	name_row.add_child(name_lbl)

	if is_me:
		var you_tag := PanelContainer.new()
		you_tag.mouse_filter = Control.MOUSE_FILTER_PASS
		var tag_sb := StyleBoxFlat.new()
		tag_sb.bg_color = Color(0.08, 0.28, 0.42, 0.95)
		tag_sb.border_color = Color(0.35, 1.0, 1.0, 0.70)
		tag_sb.set_border_width_all(1)
		tag_sb.set_corner_radius_all(4)
		tag_sb.content_margin_left = 6
		tag_sb.content_margin_right = 6
		tag_sb.content_margin_top = 1
		tag_sb.content_margin_bottom = 1
		you_tag.add_theme_stylebox_override("panel", tag_sb)
		var you_lbl := Label.new()
		you_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		you_lbl.text = "YOU"
		you_lbl.add_theme_font_size_override("font_size", 9)
		you_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 1.0))
		you_tag.add_child(you_lbl)
		name_row.add_child(you_tag)

	var dev_lbl := Label.new()
	dev_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_lbl.text = str(data.get("device", "HUAWEI Device"))
	dev_lbl.add_theme_font_size_override("font_size", 10)
	dev_lbl.add_theme_color_override("font_color", Color(0.42, 0.60, 0.75, 0.65))
	name_box.add_child(dev_lbl)

	# Date Badge (replaces old sectors column)
	var date_lbl := Label.new()
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_lbl.custom_minimum_size = Vector2(88, 0)
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_lbl.text = str(data.get("date", "2026-10-28"))
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.add_theme_color_override("font_color", Color(0.45, 0.68, 0.88, 0.70))
	hbox.add_child(date_lbl)

	# Total Clear Time
	var time_lbl := Label.new()
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_lbl.custom_minimum_size = Vector2(100, 0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var t_val: float = float(data.get("time", 0.0))
	time_lbl.text = _format_time(t_val)
	time_lbl.add_theme_font_size_override("font_size", 13)
	time_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.80, 1.0) if is_me else Color(0.38, 0.96, 0.80, 0.95))
	hbox.add_child(time_lbl)

	return panel


func _format_time(t_val: float) -> String:
	if t_val <= 0.0:
		return "--:--.--"
	var mins := floori(t_val / 60.0)
	var secs := int(t_val) % 60
	var frac := int((t_val - floorf(t_val)) * 100.0)
	return "%02d:%02d.%02d" % [mins, secs, frac]


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
	_wav_error = _synth_tone(320.0, 210.0, 0.080)
	_wav_locate = _synth_tone(840.0, 1480.0, 0.075)


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
