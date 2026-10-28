extends Control
## Post-mission evaluation & debrief screen for ECHO.
## Displays level completion time, sonar pulses emitted, and monster detection count.
## Evaluates and animates the 3-star "Ghost Rating" with procedural sound chimes,
## vector gem stars, radar shockwaves, atmospheric sonar waves, and celebration sparks.

signal next_pressed
signal retry_pressed
signal select_pressed

# --- Procedural Vector Star Badge Control ------------------------------------
class StarBadgeCanvas extends Control:
	var unlocked := false
	var star_color: Color = Color(0.35, 0.45, 0.55, 0.5)
	var glow_alpha: float = 0.0
	var shockwave_r: float = 0.0
	var shockwave_alpha: float = 0.0
	var pulse_scale: float = 1.0

	func _ready() -> void:
		custom_minimum_size = Vector2(70, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5

		# 1. Shockwave ring expanding on unlock
		if shockwave_alpha > 0.01 and shockwave_r > 0.0:
			draw_arc(c, shockwave_r, 0.0, TAU, 36, Color(star_color.r, star_color.g, star_color.b, shockwave_alpha), 2.0, true)

		# 2. Glowing orbital radar halo
		var ring_alpha := (0.22 + 0.45 * glow_alpha) if unlocked else 0.28
		var ring_col := Color(star_color.r, star_color.g, star_color.b, ring_alpha) if unlocked else Color(0.20, 0.32, 0.45, 0.40)
		draw_arc(c, 24.0, 0.0, TAU, 36, ring_col, 1.5, true)
		if unlocked:
			# Soft radiant back-glow
			draw_circle(c, 22.0, Color(star_color.r, star_color.g, star_color.b, 0.16 * glow_alpha))
			# Subtle 4-axis optic cross ticks on the orbit ring
			var tick_len := 4.5
			var tick_col := Color(star_color.r, star_color.g, star_color.b, 0.75 * glow_alpha)
			draw_line(Vector2(c.x, c.y - 28.0), Vector2(c.x, c.y - 28.0 + tick_len), tick_col, 1.5, true)
			draw_line(Vector2(c.x, c.y + 28.0), Vector2(c.x, c.y + 28.0 - tick_len), tick_col, 1.5, true)
			draw_line(Vector2(c.x - 28.0, c.y), Vector2(c.x - 28.0 + tick_len, c.y), tick_col, 1.5, true)
			draw_line(Vector2(c.x + 28.0, c.y), Vector2(c.x + 28.0 - tick_len, c.y), tick_col, 1.5, true)

		# 3. Faceted 5-point Star Geometry
		var r_out := 16.5 * pulse_scale
		var r_in := 7.5 * pulse_scale
		var star_pts := PackedVector2Array()
		for i in range(10):
			var r := r_out if i % 2 == 0 else r_in
			var ang := -PI * 0.5 + float(i) * TAU / 10.0
			star_pts.append(Vector2(c.x + cos(ang) * r, c.y + sin(ang) * r))

		if unlocked:
			# Faceted 3D shading: Alternating light/dark triangles from center creates gorgeous cut-gem look
			var light_col := star_color.lightened(0.28)
			var dark_col := star_color.darkened(0.25)
			for i in range(10):
				var p1 := star_pts[i]
				var p2 := star_pts[(i + 1) % 10]
				var tri := PackedVector2Array([c, p1, p2])
				var f_col := light_col if (i % 2 == 0) else dark_col
				draw_colored_polygon(tri, f_col)

			# Crisp bright outline
			var closed := star_pts.duplicate()
			closed.append(star_pts[0])
			draw_polyline(closed, Color(1.0, 1.0, 1.0, 0.90), 1.6, true)
			# Brilliant center core
			draw_circle(c, 2.6, Color.WHITE)
		else:
			# Locked blueprint state: muted dark silhouette with subtle outline
			draw_colored_polygon(star_pts, Color(0.04, 0.08, 0.12, 0.75))
			var closed := star_pts.duplicate()
			closed.append(star_pts[0])
			draw_polyline(closed, Color(0.22, 0.35, 0.48, 0.60), 1.4, true)


# --- Ambient Sonar Wave & Celebration Ember Particles Behind Modal -----------
class VictoryBackdropFx extends Control:
	var pulse_timer := 0.0
	var rings: Array[Dictionary] = []
	var particles: Array[Dictionary] = []
	var is_rank_s := false

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		pulse_timer += delta
		if pulse_timer > 1.30:
			pulse_timer = 0.0
			rings.append({
				"r": 50.0,
				"max_r": 480.0,
				"dur": 3.4,
				"age": 0.0
			})

		for r in rings:
			r["age"] = float(r["age"]) + delta
		rings = rings.filter(func(r): return float(r["age"]) < float(r["dur"]))

		# Golden/cyan celebration embers when Rank S (3 Stars) is achieved
		if is_rank_s and particles.size() < 26 and randf() < 0.38:
			particles.append({
				"pos": Vector2(randf_range(size.x * 0.15, size.x * 0.85), size.y * 0.76 + randf_range(0, 30)),
				"vel": Vector2(randf_range(-14, 14), randf_range(-45, -85)),
				"age": 0.0,
				"dur": randf_range(2.0, 3.8),
				"col": Color(1.0, 0.84, 0.35) if randf() < 0.65 else Color(0.40, 0.92, 1.0)
			})

		for p in particles:
			p["age"] = float(p["age"]) + delta
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		particles = particles.filter(func(p): return float(p["age"]) < float(p["dur"]))

		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		# Sonar radial waves
		for r in rings:
			var prog: float = clampf(float(r["age"]) / float(r["dur"]), 0.0, 1.0)
			var rad: float = lerpf(float(r["r"]), float(r["max_r"]), prog)
			var a: float = (1.0 - prog) * 0.18
			var ring_col := Color(0.28, 0.78, 1.0, a) if not is_rank_s else Color(1.0, 0.84, 0.35, a)
			draw_arc(c, rad, 0.0, TAU, 48, ring_col, 1.6, true)

		# Sparkle embers
		for p in particles:
			var prog: float = clampf(float(p["age"]) / float(p["dur"]), 0.0, 1.0)
			var a: float = sin(prog * PI) * 0.85
			var col: Color = p["col"]
			draw_circle(p["pos"], 2.2, Color(col.r, col.g, col.b, a))


# --- Holographic Glass Specular & Corner Cyber-Reticles ----------------------
class CardDecoOverlay extends Control:
	var corner_col := Color(0.35, 0.88, 1.0, 0.85)

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 10.0 or h <= 10.0:
			return

		# 1. Top Specular curved highlight line (gives realistic curved glass refraction)
		draw_line(Vector2(24.0, 1.5), Vector2(w - 24.0, 1.5), Color(1.0, 1.0, 1.0, 0.22), 1.5, true)

		# 2. Four Corner Cyber Reticles (L-brackets)
		var clen := 14.0
		var ccol := corner_col
		var inset := 4.0
		# Top-Left
		draw_line(Vector2(inset, inset), Vector2(inset + clen, inset), ccol, 2.0, true)
		draw_line(Vector2(inset, inset), Vector2(inset, inset + clen), ccol, 2.0, true)
		# Top-Right
		draw_line(Vector2(w - inset, inset), Vector2(w - inset - clen, inset), ccol, 2.0, true)
		draw_line(Vector2(w - inset, inset), Vector2(w - inset, inset + clen), ccol, 2.0, true)
		# Bottom-Left
		draw_line(Vector2(inset, h - inset), Vector2(inset + clen, h - inset), ccol, 2.0, true)
		draw_line(Vector2(inset, h - inset), Vector2(inset, h - inset - clen), ccol, 2.0, true)
		# Bottom-Right
		draw_line(Vector2(w - inset, h - inset), Vector2(w - inset - clen, h - inset), ccol, 2.0, true)
		draw_line(Vector2(w - inset, h - inset), Vector2(w - inset, h - inset - clen), ccol, 2.0, true)


# --- Node References & State -------------------------------------------------
var _dimmer: ColorRect
var _backdrop_fx: VictoryBackdropFx
var _center: CenterContainer
var _card: PanelContainer
var _card_deco: CardDecoOverlay
var _title_lbl: Label
var _subtitle_lbl: Label
var _rank_panel: PanelContainer
var _rank_badge: Label

var _star_cards: Array[PanelContainer] = []
var _star_icons: Array[StarBadgeCanvas] = []
var _star_titles: Array[Label] = []
var _star_subs: Array[Label] = []
var _stars_row: HBoxContainer

var _stat_time_val: Label
var _stat_time_sub: Label
var _stat_pings_val: Label
var _stat_pings_sub: Label
var _stat_alerts_val: Label
var _stat_alerts_sub: Label

var _btn_retry: Button
var _btn_select: Button
var _btn_next: Button
var _hms_row: HBoxContainer
var _hms_sync_btn: Button

var _is_open := false
var _data: Dictionary = {}
var _sfx_mgr: SfxManager
var _cur_lvl_num: int = 1
var _hero_pulse_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	visible = false
	modulate.a = 0.0
	_build_ui()
	_sync_viewport_size()
	HMSService.auth_status_changed.connect(func(_logged): _update_hms_button_state())


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

	# 1. Fullscreen Dimmer with deep atmospheric tint
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0.008, 0.018, 0.035, 0.84)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dimmer)

	# 1b. Ambient procedural sonar rings & celebration ember canvas
	_backdrop_fx = VictoryBackdropFx.new()
	_dimmer.add_child(_backdrop_fx)

	# 2. Center Alignment Container
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.anchor_right = 1.0
	_center.anchor_bottom = 1.0
	add_child(_center)

	# 3. Main Glassmorphic Holographic Card
	_card = PanelContainer.new()
	var init_challenge: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	_card.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 545.0 if init_challenge else 495.0)
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Advanced glass style with dual-layer border and deep shadow
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.012, 0.032, 0.062, 0.94)
	card_style.border_color = Color(0.20, 0.52, 0.82, 0.75)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(ModalTemplate.CORNER_RADIUS)
	card_style.shadow_color = Color(0.0, 0.16, 0.36, 0.55)
	card_style.shadow_size = 28
	card_style.content_margin_left = 22.0
	card_style.content_margin_right = 22.0
	card_style.content_margin_top = 20.0
	card_style.content_margin_bottom = 20.0
	_card.add_theme_stylebox_override("panel", card_style)
	_center.add_child(_card)

	# Cyber reticle & specular overlay on card
	_card_deco = CardDecoOverlay.new()
	_card.add_child(_card_deco)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(vbox)

	# --- Header: Kicker + Title + Philosophical Subtitle ---
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 3)
	header_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_vbox)

	var kicker := Label.new()
	kicker.text = "◈   S E C T O R   C L E A R E D   ◈"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", Color(0.35, 0.95, 0.78, 0.95))
	header_vbox.add_child(kicker)

	_title_lbl = Label.new()
	_title_lbl.text = "SHALLOW RING"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 25)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.55, 0.95, 0.85))
	_title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	header_vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = "“In the deepest dark, silence is not emptiness—it is your canvas.”"
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_lbl.add_theme_font_size_override("font_size", 12)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.68, 0.85, 0.98, 0.88))
	header_vbox.add_child(_subtitle_lbl)

	# --- Rank Pill Capsule Container ---
	var rank_container := HBoxContainer.new()
	rank_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(rank_container)

	_rank_panel = PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.set_corner_radius_all(14)
	r_style.content_margin_left = 22.0
	r_style.content_margin_right = 22.0
	r_style.content_margin_top = 5.0
	r_style.content_margin_bottom = 5.0
	r_style.bg_color = Color(0.04, 0.14, 0.24, 0.88)
	r_style.border_color = Color(0.35, 0.85, 1.0, 0.80)
	r_style.set_border_width_all(1)
	_rank_panel.add_theme_stylebox_override("panel", r_style)
	rank_container.add_child(_rank_panel)

	_rank_badge = Label.new()
	_rank_badge.text = "★ ★ ★   RANK: S   •   ABYSSAL PHANTOM"
	_rank_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_badge.add_theme_font_size_override("font_size", 12)
	_rank_badge.add_theme_color_override("font_color", Color(0.40, 0.92, 1.0))
	_rank_panel.add_child(_rank_badge)

	# --- Three Star / Badge Cards with Vector Stars ---
	var stars_hbox := HBoxContainer.new()
	stars_hbox.add_theme_constant_override("separation", 12)
	stars_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stars_hbox)
	_stars_row = stars_hbox

	var star_specs: Array[Dictionary] = [
		{"name": "SURVIVOR", "cond": "SURVIVE & ESCAPE", "type": 0},
		{"name": "GHOST", "cond": "ZERO ALERTS", "type": 1},
		{"name": "SWIFT ECHO", "cond": "BEAT PAR TIME", "type": 2}
	]

	_star_cards.clear()
	_star_icons.clear()
	_star_titles.clear()
	_star_subs.clear()

	for i in 3:
		var spec: Dictionary = star_specs[i]
		var sc := PanelContainer.new()
		sc.custom_minimum_size = Vector2(164, 122)
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sc_style := StyleBoxFlat.new()
		sc_style.bg_color = Color(0.016, 0.038, 0.068, 0.88)
		sc_style.set_border_width_all(1)
		sc_style.border_color = Color(0.18, 0.32, 0.45, 0.70)
		sc_style.set_corner_radius_all(12)
		sc_style.content_margin_left = 6
		sc_style.content_margin_right = 6
		sc_style.content_margin_top = 8
		sc_style.content_margin_bottom = 8
		sc.add_theme_stylebox_override("panel", sc_style)

		var svbox := VBoxContainer.new()
		svbox.alignment = BoxContainer.ALIGNMENT_CENTER
		svbox.add_theme_constant_override("separation", 3)
		sc.add_child(svbox)

		# Vector Star Badge Canvas
		var star_canvas := StarBadgeCanvas.new()
		star_canvas.custom_minimum_size = Vector2(64, 52)
		star_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		star_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		svbox.add_child(star_canvas)

		var sname := Label.new()
		sname.text = spec["name"]
		sname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sname.add_theme_font_size_override("font_size", 12)
		sname.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		svbox.add_child(sname)

		var ssub := Label.new()
		ssub.text = spec["cond"]
		ssub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ssub.add_theme_font_size_override("font_size", 10)
		ssub.add_theme_color_override("font_color", Color(0.50, 0.68, 0.82, 0.85))
		svbox.add_child(ssub)

		stars_hbox.add_child(sc)
		_star_cards.append(sc)
		_star_icons.append(star_canvas)
		_star_titles.append(sname)
		_star_subs.append(ssub)

	# --- Telemetry Statistics Pods ---
	var stat_pods_hbox := HBoxContainer.new()
	stat_pods_hbox.add_theme_constant_override("separation", 10)
	stat_pods_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stat_pods_hbox)

	# Column 1: Time
	var t_pod := _build_stat_pod("⏱  ESCAPE TIME", "--:--")
	_stat_time_val = t_pod.find_child("Val") as Label
	_stat_time_sub = t_pod.find_child("Sub") as Label
	stat_pods_hbox.add_child(t_pod)

	# Column 2: Pings
	var p_pod := _build_stat_pod("◎  SONAR PINGS", "0")
	_stat_pings_val = p_pod.find_child("Val") as Label
	_stat_pings_sub = p_pod.find_child("Sub") as Label
	stat_pods_hbox.add_child(p_pod)

	# Column 3: Alerts
	var a_pod := _build_stat_pod("⚠  MONSTER ALERTS", "0")
	_stat_alerts_val = a_pod.find_child("Val") as Label
	_stat_alerts_sub = a_pod.find_child("Sub") as Label
	stat_pods_hbox.add_child(a_pod)

	# --- Huawei Leaderboard / HMS Sync Bar (Challenge Mode exclusive) ---
	_hms_row = HBoxContainer.new()
	_hms_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hms_row.visible = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	vbox.add_child(_hms_row)

	_hms_sync_btn = Button.new()
	_hms_sync_btn.focus_mode = Control.FOCUS_NONE
	_hms_sync_btn.custom_minimum_size = Vector2(420, 34)
	_hms_sync_btn.pressed.connect(_on_hms_button_pressed)
	_style_hms_button(_hms_sync_btn)
	_update_hms_button_state()
	_hms_row.add_child(_hms_sync_btn)

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


func _build_stat_pod(header_title: String, default_val: String) -> PanelContainer:
	var pod := PanelContainer.new()
	pod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pod.custom_minimum_size = Vector2(160, 64)

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.014, 0.034, 0.058, 0.90)
	p_style.border_color = Color(0.16, 0.32, 0.48, 0.70)
	p_style.set_border_width_all(1)
	p_style.set_corner_radius_all(10)
	p_style.content_margin_left = 10.0
	p_style.content_margin_right = 10.0
	p_style.content_margin_top = 7.0
	p_style.content_margin_bottom = 7.0
	pod.add_theme_stylebox_override("panel", p_style)

	var c := VBoxContainer.new()
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 2)
	pod.add_child(c)

	var lbl := Label.new()
	lbl.text = header_title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.52, 0.72, 0.90, 0.90))
	c.add_child(lbl)

	var val := Label.new()
	val.name = "Val"
	val.text = default_val
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 17)
	val.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	c.add_child(val)

	var sub := Label.new()
	sub.name = "Sub"
	sub.text = ""
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70, 0.90))
	c.add_child(sub)

	return pod


func _build_action_button(text: String, is_primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(164, 46)
	b.focus_mode = Control.FOCUS_NONE

	var norm := StyleBoxFlat.new()
	var hov := StyleBoxFlat.new()
	var prs := StyleBoxFlat.new()

	for sb: StyleBoxFlat in [norm, hov, prs]:
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0

	if is_primary:
		norm.bg_color = Color(0.06, 0.35, 0.58, 0.95)
		norm.set_border_width_all(2)
		norm.border_color = Color(0.40, 0.92, 1.0, 0.95)
		norm.shadow_color = Color(0.0, 0.35, 0.65, 0.40)
		norm.shadow_size = 8

		hov.bg_color = Color(0.09, 0.45, 0.72, 0.98)
		hov.set_border_width_all(2)
		hov.border_color = Color(0.70, 0.98, 1.0, 1.0)
		hov.shadow_color = Color(0.0, 0.45, 0.85, 0.60)
		hov.shadow_size = 12

		prs.bg_color = Color(0.12, 0.55, 0.85, 1.0)
		prs.set_border_width_all(2)
		prs.border_color = Color(0.90, 1.0, 1.0, 1.0)
	else:
		norm.bg_color = Color(0.024, 0.065, 0.12, 0.90)
		norm.set_border_width_all(1)
		norm.border_color = Color(0.20, 0.42, 0.62, 0.75)

		hov.bg_color = Color(0.04, 0.12, 0.22, 0.95)
		hov.set_border_width_all(1)
		hov.border_color = Color(0.38, 0.70, 0.95, 0.95)

		prs.bg_color = Color(0.06, 0.16, 0.30, 1.0)
		prs.set_border_width_all(1)
		prs.border_color = Color(0.55, 0.85, 1.0, 1.0)

	b.add_theme_stylebox_override("normal", norm)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", prs)
	b.add_theme_stylebox_override("focus", norm)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))

	b.mouse_entered.connect(func():
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2(1.035, 1.035), 0.08)
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

	var is_surv: bool = (data.get("is_survivor", true) == true)
	var is_ghost: bool = (data.get("is_ghost", false) == true)
	var is_swift: bool = (data.get("is_swift", false) == true)
	var run_stars: int = int(data.get("run_stars", 1))

	_cur_lvl_num = lvl_num
	var is_challenge: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	if _hms_row != null:
		_hms_row.visible = is_challenge

	if is_challenge:
		HMSService.submit_sector_score(lvl_num, clear_time, pings, run_stars)
		_update_hms_button_state()

	if _card != null:
		_card.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 545.0 if is_challenge else 495.0)

	HMSService.check_sector_clear_achievement(lvl_num, pings, alerts, is_swift)

	# Format level title with sector name and subtitle narrative
	if GameState.current_mode == GameState.GameMode.STORY and GameState.current_level == 0:
		_title_lbl.text = "PROLOGUE CLEARED"
		_subtitle_lbl.text = "“Step by step, you begin the ascent.”"
	else:
		_title_lbl.text = "%s CLEARED" % GameState.get_level_name(GameState.current_level)
		if GameState.current_mode == GameState.GameMode.STORY:
			var quote: String = GameState.get_sector_log(GameState.current_level)
			_subtitle_lbl.text = "“%s”" % quote
		else:
			_subtitle_lbl.text = "ABYSS EXPEDITION EXTRACTION SUCCESSFUL"

	# Update telemetry stats
	var mins := floori(clear_time / 60.0)
	var secs := int(clear_time) % 60
	var ms := int((clear_time - int(clear_time)) * 10.0)
	var time_str := "%02d:%02d.%d" % [mins, secs, ms]

	_stat_time_val.text = time_str
	if is_swift:
		_stat_time_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70))
		_stat_time_sub.text = "✓ BEAT PAR (≤ %0.0fs)" % par_time
		_stat_time_sub.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70))
	else:
		_stat_time_val.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
		_stat_time_sub.text = "PAR ≤ %0.0fs" % par_time
		_stat_time_sub.add_theme_color_override("font_color", Color(0.55, 0.70, 0.85))

	_stat_pings_val.text = "%d" % pings
	if pings <= par_pings:
		_stat_pings_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70))
		_stat_pings_sub.text = "✓ STEALTH (≤ %d)" % par_pings
		_stat_pings_sub.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70))
	else:
		_stat_pings_val.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
		_stat_pings_sub.text = "PAR ≤ %d" % par_pings
		_stat_pings_sub.add_theme_color_override("font_color", Color(0.55, 0.70, 0.85))

	if alerts == 0:
		_stat_alerts_val.text = "0"
		_stat_alerts_val.add_theme_color_override("font_color", Color(0.35, 0.95, 0.65))
		_stat_alerts_sub.text = "✓ PERFECT GHOST"
		_stat_alerts_sub.add_theme_color_override("font_color", Color(0.35, 0.95, 0.65))
	else:
		_stat_alerts_val.text = "%d" % alerts
		_stat_alerts_val.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		_stat_alerts_sub.text = "DETECTIONS"
		_stat_alerts_sub.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))

	# Update condition subtitles
	_star_subs[0].text = "SURVIVED"
	_star_subs[1].text = "0 ALERTS (%d)" % alerts
	_star_subs[2].text = "≤ %0.0fs (%s)" % [par_time, time_str]

	# Overall Rank Banner & Stars Visibility
	var r_style := _rank_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if is_challenge:
		if _stars_row != null:
			_stars_row.visible = false
		_rank_badge.text = "◈ CHALLENGE SECTOR CLEARED • TIME: %s ◈" % time_str
		_rank_badge.add_theme_color_override("font_color", Color(1.0, 0.45, 0.85))
		if r_style != null:
			r_style.bg_color = Color(0.18, 0.05, 0.16, 0.88)
			r_style.border_color = Color(1.0, 0.45, 0.85, 0.85)
		if _card != null:
			_card.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 440.0)
	else:
		if _stars_row != null:
			_stars_row.visible = true
		match run_stars:
			3:
				_rank_badge.text = "★ ★ ★   RANK: S   •   ABYSSAL PHANTOM"
				_rank_badge.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
				if r_style != null:
					r_style.bg_color = Color(0.24, 0.15, 0.03, 0.94)
					r_style.border_color = Color(1.0, 0.84, 0.30, 0.95)
					r_style.set_border_width_all(2)
				_backdrop_fx.is_rank_s = true
				if _card_deco != null:
					_card_deco.corner_col = Color(1.0, 0.84, 0.30, 0.95)
					_card_deco.queue_redraw()
			2:
				_rank_badge.text = "★ ★ ☆   RANK: A   •   SILENT SHADOW"
				_rank_badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.85))
				if r_style != null:
					r_style.bg_color = Color(0.04, 0.18, 0.12, 0.90)
					r_style.border_color = Color(0.30, 0.94, 0.68, 0.85)
					r_style.set_border_width_all(1)
				_backdrop_fx.is_rank_s = false
				if _card_deco != null:
					_card_deco.corner_col = Color(0.30, 0.94, 0.68, 0.85)
					_card_deco.queue_redraw()
			_:
				_rank_badge.text = "★ ☆ ☆   RANK: B   •   CAVERN SURVIVOR"
				_rank_badge.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
				if r_style != null:
					r_style.bg_color = Color(0.04, 0.12, 0.20, 0.88)
					r_style.border_color = Color(0.35, 0.75, 1.0, 0.75)
					r_style.set_border_width_all(1)
				_backdrop_fx.is_rank_s = false
				if _card_deco != null:
					_card_deco.corner_col = Color(0.35, 0.75, 1.0, 0.75)
					_card_deco.queue_redraw()

	# Next button label for final depth
	if not GameState.has_next_level():
		_btn_next.text = "FINALE VICTORY >"
	elif is_challenge:
		_btn_next.text = "ABYSS MAP >"
	else:
		_btn_next.text = "NEXT SECTOR >"

	# Reset star visuals before animation (Story Mode only)
	if not is_challenge:
		for i in 3:
			var sc := _star_icons[i]
			sc.unlocked = false
			sc.star_color = Color(0.35, 0.45, 0.55, 0.5)
			sc.glow_alpha = 0.0
			sc.pulse_scale = 1.0
			sc.shockwave_r = 0.0
			sc.shockwave_alpha = 0.0
			sc.queue_redraw()
			var sc_style := _star_cards[i].get_theme_stylebox("panel") as StyleBoxFlat
			if sc_style != null:
				sc_style.border_color = Color(0.18, 0.32, 0.45, 0.65)
				sc_style.bg_color = Color(0.016, 0.038, 0.068, 0.88)

	# Smooth entrance animation
	_card.scale = Vector2(0.92, 0.92)
	_card.pivot_offset = Vector2(290.0, 260.0) if _card.size.x < 100.0 else _card.size * 0.5
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Sequenced star illumination with audio chimes (Story Mode only)
	if not is_challenge:
		var star_unlocked: Array[bool] = [is_surv, is_ghost, is_swift]
		var star_colors: Array[Color] = [
			Color(0.24, 0.88, 1.0),   # Radiant Cyan for Survivor
			Color(0.20, 0.96, 0.68),  # Vivid Emerald for Ghost
			Color(1.0, 0.84, 0.25)    # Radiant Gold for Swift
		]

		for i in 3:
			var delay := 0.35 + i * 0.26
			tw.tween_callback(func():
				if star_unlocked[i]:
					_animate_star_earn(i, star_colors[i])
			).set_delay(delay if i == 0 else 0.26)

	_start_hero_pulse()


func _start_hero_pulse() -> void:
	if _hero_pulse_tween != null and _hero_pulse_tween.is_valid():
		_hero_pulse_tween.kill()
	if _btn_next == null or not is_instance_valid(_btn_next):
		return
	_btn_next.pivot_offset = _btn_next.size * 0.5
	_hero_pulse_tween = create_tween().set_loops()
	_hero_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hero_pulse_tween.tween_property(_btn_next, "scale", Vector2(1.028, 1.028), 0.70).set_trans(Tween.TRANS_SINE)
	_hero_pulse_tween.tween_property(_btn_next, "scale", Vector2.ONE, 0.70).set_trans(Tween.TRANS_SINE)


func _stop_hero_pulse() -> void:
	if _hero_pulse_tween != null and _hero_pulse_tween.is_valid():
		_hero_pulse_tween.kill()
		_hero_pulse_tween = null
	if _btn_next != null and is_instance_valid(_btn_next):
		_btn_next.scale = Vector2.ONE


func _animate_star_earn(idx: int, star_color: Color) -> void:
	if not _is_open or idx < 0 or idx >= _star_icons.size():
		return
	if _sfx_mgr != null:
		_sfx_mgr.play_star_chime(idx)
	Input.vibrate_handheld(35)

	var star_canvas: StarBadgeCanvas = _star_icons[idx]
	if star_canvas != null:
		star_canvas.unlocked = true
		star_canvas.star_color = star_color
		star_canvas.glow_alpha = 1.0
		star_canvas.pulse_scale = 1.65
		star_canvas.shockwave_r = 10.0
		star_canvas.shockwave_alpha = 0.85
		star_canvas.queue_redraw()

		var s_tw := create_tween()
		s_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		s_tw.parallel().tween_property(star_canvas, "pulse_scale", 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		s_tw.parallel().tween_property(star_canvas, "shockwave_r", 56.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		s_tw.parallel().tween_property(star_canvas, "shockwave_alpha", 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		s_tw.tween_callback(func():
			if is_instance_valid(star_canvas):
				star_canvas.queue_redraw()
		)

	var sc_style := _star_cards[idx].get_theme_stylebox("panel") as StyleBoxFlat
	if sc_style != null:
		sc_style.border_color = star_color
		sc_style.bg_color = Color(star_color.r * 0.15, star_color.g * 0.15, star_color.b * 0.15, 0.94)

	# Punch scale on the whole badge card for tactile feedback
	var card := _star_cards[idx]
	card.pivot_offset = card.size * 0.5
	var c_tw := create_tween()
	c_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	c_tw.tween_property(card, "scale", Vector2(1.055, 1.055), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_property(card, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_next() -> void:
	_stop_hero_pulse()
	_is_open = false
	visible = false
	get_tree().paused = false
	next_pressed.emit()


func _on_retry() -> void:
	_stop_hero_pulse()
	_is_open = false
	visible = false
	get_tree().paused = false
	retry_pressed.emit()


func _on_select() -> void:
	_stop_hero_pulse()
	_is_open = false
	visible = false
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
	if _hms_sync_btn == null or _hms_row == null:
		return
	var is_challenge: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	_hms_row.visible = is_challenge
	if not is_challenge:
		return
	if HMSService.is_logged_in:
		var p_name: String = HMSService.get_player_name()
		_hms_sync_btn.text = "◈ HUAWEI ID: %s • SYNCED (VIEW LEADERBOARD)" % p_name
		_hms_sync_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
	else:
		_hms_sync_btn.text = "◈ JOIN GLOBAL SPEEDRUN RANKING (HUAWEI ID) ◈"
		_hms_sync_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))


func _on_hms_button_pressed() -> void:
	var modal_script: GDScript = load("res://ui/modals/LeaderboardModal.gd") as GDScript
	if modal_script != null:
		modal_script.open_leaderboard(self, _cur_lvl_num, func(): pass)
