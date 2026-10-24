extends Control

const MIX_RATE := 22050
const LEVEL_BUTTON_HEIGHT := 56.0
const BOTTOM_BUTTON_HEIGHT := 56.0
const TEST_LEVEL_PATH := "res://levels/level_test.tscn"

@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var level_grid: GridContainer = $MainArea/ScrollContainer/GridMargin/LevelGrid
@onready var depth_gauge: Control = $DepthGauge
@onready var intel_button: Button = $TopBar/IntelButton
@onready var settings_button: Button = $TopBar/SettingsButton
@onready var status_pill: PanelContainer = $TopBar/StatusPill
@onready var progress_label: Label = $TopBar/StatusPill/StatusBox/ProgressLabel
@onready var sonar_backdrop: Control = $SonarBackdrop

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _suppress_level_click := false
var _level_buttons: Dictionary = {}

var _depth_tag_alpha: float = 0.0
var _depth_tag_timer: float = 0.0
var _is_dragging_gauge: bool = false

const SECTORS: Array[Dictionary] = GameState.SECTORS

# Procedural UI Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_error: AudioStreamWAV

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

# Bestiary modal tracking & synthesis
var _bestiary_entries: Array[Dictionary] = []
var _sfx_mgr: SfxManager


func _ready() -> void:
	_build_ui_audio()
	_init_sfx_manager()
	_init_spores()

	# Background effects should not block button input.
	sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	# Connecting sonar route path drawn on LevelGrid
	level_grid.draw.connect(_draw_level_path)

	# Depth Gauge on the right side
	if depth_gauge != null:
		depth_gauge.mouse_filter = Control.MOUSE_FILTER_PASS
		depth_gauge.draw.connect(_draw_depth_gauge)
		depth_gauge.gui_input.connect(_on_depth_gauge_gui_input)

	# Two columns create the left-right staggered vertical map.
	level_grid.columns = 2

	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.gui_input.connect(_on_scroll_container_gui_input)

	level_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Hide the scrollbar visually while retaining scrolling.
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.modulate.a = 0.0
	scrollbar.value_changed.connect(func(_val: float) -> void:
		_depth_tag_timer = 1.0
		if depth_gauge != null and is_instance_valid(depth_gauge):
			depth_gauge.queue_redraw()
	)

	level_grid.add_theme_constant_override("h_separation", 16)
	level_grid.add_theme_constant_override("v_separation", 30)

	if status_pill != null:
		var pill_style := StyleBoxFlat.new()
		pill_style.bg_color = Color(0.03, 0.09, 0.16, 0.9)
		pill_style.border_color = Color(0.18, 0.45, 0.7, 0.8)
		pill_style.set_border_width_all(1)
		pill_style.set_corner_radius_all(12)
		status_pill.add_theme_stylebox_override("panel", pill_style)

	_style_bottom_button(intel_button)
	_style_bottom_button(settings_button)

	_setup_intel_button()
	_setup_settings_button()

	_create_level_buttons()

	intel_button.pressed.connect(_on_intel_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	_wire_button_Juice(intel_button)
	_wire_button_Juice(settings_button)

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


func _on_scroll_container_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)) or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		_depth_tag_timer = 1.0


func _format_depth_meters(meters: int) -> String:
	var abs_val := absi(meters)
	var sign_str := "-" if meters < 0 else ""
	if abs_val >= 1000:
		var thousands := abs_val / 1000
		var remainder := abs_val % 1000
		return "%s%d,%03d M" % [sign_str, thousands, remainder]
	else:
		return "%s%d M" % [sign_str, abs_val]


# --------------------------------------------------
# BUTTON STYLES
# --------------------------------------------------

func _make_button_style(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1,
	corner_radius: int = 12,
	shadow_color: Color = Color(0, 0, 0, 0),
	shadow_size: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	if shadow_size > 0:
		style.shadow_color = shadow_color
		style.shadow_size = shadow_size
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


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


func _setup_intel_button() -> void:
	intel_button.text = ""
	intel_button.custom_minimum_size = Vector2(56, 56)
	for c in intel_button.get_children():
		c.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intel_button.add_child(center)

	var book := Control.new()
	book.custom_minimum_size = Vector2(26, 26)
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.draw.connect(_draw_book_icon.bind(book))
	center.add_child(book)


func _setup_settings_button() -> void:
	settings_button.text = ""
	settings_button.custom_minimum_size = Vector2(56, 56)
	for c in settings_button.get_children():
		c.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_button.add_child(center)

	var gear := Control.new()
	gear.custom_minimum_size = Vector2(26, 26)
	gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear.draw.connect(_draw_gear_icon.bind(gear))
	center.add_child(gear)


# --------------------------------------------------
# PROCEDURAL VECTOR ICONS (100% Cross-Platform)
# --------------------------------------------------

func _draw_gear_icon(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var r0 := 7.0
	var r1 := 11.0
	var num_teeth := 8
	var pitch := TAU / float(num_teeth)
	var w_base := pitch * 0.26
	var w_tip := pitch * 0.14
	var pts := PackedVector2Array()

	for i in range(num_teeth):
		var a := i * pitch
		var a1 := a - w_base
		pts.append(Vector2(c.x + cos(a1) * r0, c.y + sin(a1) * r0))
		var a2 := a - w_tip
		pts.append(Vector2(c.x + cos(a2) * r1, c.y + sin(a2) * r1))
		var a3 := a + w_tip
		pts.append(Vector2(c.x + cos(a3) * r1, c.y + sin(a3) * r1))
		var a4 := a + w_base
		pts.append(Vector2(c.x + cos(a4) * r0, c.y + sin(a4) * r0))
		var a5 := a + pitch * 0.5
		pts.append(Vector2(c.x + cos(a5) * (r0 - 0.2), c.y + sin(a5) * (r0 - 0.2)))

	var col_fill := Color(0.78, 0.92, 1.0, 0.95)
	var col_hole := Color(0.035, 0.09, 0.16, 1.0)
	var col_rim := Color(0.25, 0.55, 0.85, 0.8)

	# Solid gear teeth and body
	canvas.draw_colored_polygon(pts, col_fill)
	# Closed outline for crisp definition
	var closed_pts := pts.duplicate()
	closed_pts.append(pts[0])
	canvas.draw_polyline(closed_pts, Color(col_fill.r, col_fill.g, col_fill.b, 0.9), 1.2)

	# Axle center hole (knockout)
	canvas.draw_circle(c, 3.6, col_hole)
	canvas.draw_arc(c, 3.6, 0.0, TAU, 16, col_rim, 1.2)
	# Subtle recessed mechanical groove ring
	canvas.draw_arc(c, 5.5, 0.0, TAU, 20, Color(0.15, 0.35, 0.55, 0.65), 1.0)


func _draw_book_icon(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var col := Color(0.78, 0.92, 1.0, 0.95)
	var page_fill := Color(0.06, 0.16, 0.28, 0.95)

	# Left page polygon: curved top, vertical outer edge, curved bottom, center spine
	var left_poly := PackedVector2Array([
		Vector2(c.x - 0.5, c.y - 7.0),
		Vector2(c.x - 5.5, c.y - 8.5),
		Vector2(c.x - 10.5, c.y - 7.0),
		Vector2(c.x - 10.5, c.y + 6.5),
		Vector2(c.x - 5.5, c.y + 5.0),
		Vector2(c.x - 0.5, c.y + 6.5)
	])
	canvas.draw_colored_polygon(left_poly, page_fill)
	var left_closed := left_poly.duplicate()
	left_closed.append(left_poly[0])
	canvas.draw_polyline(left_closed, col, 1.6)

	# Right page polygon
	var right_poly := PackedVector2Array([
		Vector2(c.x + 0.5, c.y - 7.0),
		Vector2(c.x + 5.5, c.y - 8.5),
		Vector2(c.x + 10.5, c.y - 7.0),
		Vector2(c.x + 10.5, c.y + 6.5),
		Vector2(c.x + 5.5, c.y + 5.0),
		Vector2(c.x + 0.5, c.y + 6.5)
	])
	canvas.draw_colored_polygon(right_poly, page_fill)
	var right_closed := right_poly.duplicate()
	right_closed.append(right_poly[0])
	canvas.draw_polyline(right_closed, col, 1.6)

	# Center book spine
	canvas.draw_line(Vector2(c.x, c.y - 7.0), Vector2(c.x, c.y + 7.5), Color(0.35, 0.85, 1.0, 0.95), 2.0)

	# Left page text lines
	var line_col := Color(col.r, col.g, col.b, 0.75)
	canvas.draw_line(Vector2(c.x - 8.5, c.y - 3.0), Vector2(c.x - 2.5, c.y - 3.8), line_col, 1.4)
	canvas.draw_line(Vector2(c.x - 8.5, c.y + 0.5), Vector2(c.x - 2.5, c.y - 0.3), line_col, 1.4)
	canvas.draw_line(Vector2(c.x - 8.5, c.y + 4.0), Vector2(c.x - 3.5, c.y + 3.2), line_col, 1.4)

	# Right page text lines
	canvas.draw_line(Vector2(c.x + 2.5, c.y - 3.8), Vector2(c.x + 8.5, c.y - 3.0), line_col, 1.4)
	canvas.draw_line(Vector2(c.x + 2.5, c.y - 0.3), Vector2(c.x + 8.5, c.y + 0.5), line_col, 1.4)
	canvas.draw_line(Vector2(c.x + 3.5, c.y + 3.2), Vector2(c.x + 8.5, c.y + 4.0), line_col, 1.4)

	# Bottom cover spine base ridge
	var ridge := PackedVector2Array([
		Vector2(c.x - 10.5, c.y + 8.0),
		Vector2(c.x, c.y + 9.5),
		Vector2(c.x + 10.5, c.y + 8.0)
	])
	canvas.draw_polyline(ridge, Color(col.r, col.g, col.b, 0.5), 1.5)


func _draw_beacon_icon(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var col := Color(0.35, 0.95, 1.0)
	canvas.draw_circle(c, 3.2, col)
	canvas.draw_arc(c, 5.8, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.6), 1.8)


func _draw_check_icon(canvas: Control) -> void:
	var col := Color(0.35, 0.95, 0.65)
	var cy := canvas.size.y * 0.5
	# Visual baseline alignment with 13px uppercase font:
	# Bottom vertex sits right on the baseline, top vertex at cap height
	var p1 := Vector2(1.5, cy + 0.8)
	var p2 := Vector2(4.8, cy + 4.8)
	var p3 := Vector2(12.0, cy - 3.2)
	canvas.draw_line(p1, p2, col, 2.2)
	canvas.draw_line(p2, p3, col, 2.2)


func _draw_lock_icon(canvas: Control) -> void:
	var col := Color(0.55, 0.70, 0.85, 0.92)
	var cx := canvas.size.x * 0.5
	var cy := canvas.size.y * 0.5
	# Shackle
	canvas.draw_arc(Vector2(cx, cy - 2.5), 3.2, PI, TAU, 12, col, 1.6)
	canvas.draw_line(Vector2(cx - 3.2, cy - 2.5), Vector2(cx - 3.2, cy), col, 1.6)
	canvas.draw_line(Vector2(cx + 3.2, cy - 2.5), Vector2(cx + 3.2, cy), col, 1.6)
	# Padlock Body
	canvas.draw_rect(Rect2(cx - 5.0, cy, 10.0, 6.5), col, true)
	# Keyhole center dot
	canvas.draw_circle(Vector2(cx, cy + 3.0), 1.0, Color(0.04, 0.08, 0.12))


# --------------------------------------------------
# LEVEL CARDS & PROGRESSION
# --------------------------------------------------

func _draw_card_decorations(canvas: Control, is_active: bool, is_cleared: bool) -> void:
	var w := canvas.size.x
	var h := canvas.size.y

	# 1. Left neon accent bar (safely inset at x = 3.5 so it never bleeds or clips)
	if is_active:
		var bar_pulse := 0.85 + 0.15 * sin(_time * 4.0)
		canvas.draw_rect(Rect2(3.5, 12.0, 4.0, h - 24.0), Color(0.2, 0.65, 1.0, 0.35 * bar_pulse), true)
		canvas.draw_rect(Rect2(3.5, 12.0, 2.8, h - 24.0), Color(0.4, 0.95, 1.0, 0.98 * bar_pulse), true)
	elif is_cleared:
		canvas.draw_rect(Rect2(3.5, 14.0, 2.6, h - 28.0), Color(0.32, 0.88, 0.62, 0.85), true)
	else:
		# Muted dark slate indicator notch
		canvas.draw_rect(Rect2(3.5, 16.0, 2.0, h - 32.0), Color(0.24, 0.40, 0.58, 0.75), true)

		# 1. Subtle diagonal interference grid (Fog of War barrier)
		var step := 20.0
		var num_lines := int(w / step) + 3
		for idx in range(-1, num_lines):
			var x_start := idx * step
			var p_a := Vector2(x_start, 4.0)
			var p_b := Vector2(x_start + 16.0, h - 4.0)
			if p_a.x < w and p_b.x > 0:
				canvas.draw_line(p_a, p_b, Color(0.16, 0.28, 0.42, 0.20), 1.0)

		# 2. Smooth Subterranean Sensor Scan Beam (subtle, semi-transparent radar sweep)
		var card_seed: float = float(canvas.get_instance_id() % 11) * 0.28
		var scan_phase: float = fmod(_time * 0.42 + card_seed, 1.0)
		var scan_y: float = lerpf(5.0, h - 5.0, scan_phase)
		var beam_fade: float = sin(scan_phase * PI)

		# Soft, faint gradient trail above the beam
		for b in range(1, 5):
			var trail_y: float = scan_y - float(b) * 2.4
			if trail_y >= 3.0:
				var a: float = (1.0 - float(b) / 5.0) * 0.07 * beam_fade
				canvas.draw_line(Vector2(6.0, trail_y), Vector2(w - 6.0, trail_y), Color(0.20, 0.60, 0.90, a), 1.5)

		# Primary scanning laser line (delicate and semi-transparent)
		canvas.draw_line(Vector2(6.0, scan_y), Vector2(w - 6.0, scan_y), Color(0.35, 0.85, 1.0, 0.30 * beam_fade), 1.2)

		# Subtle boundary sensor dots
		canvas.draw_circle(Vector2(6.0, scan_y), 1.6, Color(0.55, 0.90, 1.0, 0.42 * beam_fade))
		canvas.draw_circle(Vector2(w - 6.0, scan_y), 1.6, Color(0.55, 0.90, 1.0, 0.42 * beam_fade))


func _on_locked_level_pressed(btn: Button, sub_lbl: Label, original_text: String) -> void:
	if _is_modal_open:
		return
	if _suppress_level_click:
		_suppress_level_click = false
		return

	_play_ui_sound(_wav_error, -4.0, randf_range(0.96, 1.04))

	# Haptic micro-shake animation
	var orig_pos := btn.position
	var tw := create_tween()
	tw.tween_property(btn, "position:x", orig_pos.x - 5.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x + 5.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x - 3.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x + 3.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x, 0.04)

	# Transient acoustic warning flash on subtitle
	if is_instance_valid(sub_lbl):
		sub_lbl.text = "Sensor Block"
		sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 0.95))

		var reset_tw := create_tween()
		reset_tw.tween_interval(1.4)
		reset_tw.tween_callback(func():
			if is_instance_valid(sub_lbl):
				sub_lbl.text = original_text
				sub_lbl.add_theme_color_override("font_color", Color(0.32, 0.42, 0.52, 0.7))
		)


func _build_level_card(level_number: int, total_levels: int) -> Button:
	var button := Button.new()
	var highest: int = GameState.highest_unlocked_level
	var stars: int = GameState.get_level_stars(level_number)
	var is_unlocked: bool = level_number <= highest
	var is_cleared: bool = stars > 0 or level_number < highest
	var is_active: bool = is_unlocked and not is_cleared

	button.custom_minimum_size = Vector2(290, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = false

	var sec_idx := level_number - 1
	var sector_name := "CAVERN SECTOR %02d" % level_number
	var raw_depth := "-%d M" % (level_number * 160)
	if sec_idx >= 0 and sec_idx < SECTORS.size():
		sector_name = SECTORS[sec_idx]["name"]
		raw_depth = SECTORS[sec_idx]["depth"]

	# Format depth string to '~2,680 M' without extra clutter
	var depth_str := "~" + raw_depth.replace("-", "").strip_edges()

	var display_title: String = sector_name
	var display_subtitle: String = depth_str

	if is_active:
		display_title = sector_name
	elif is_cleared:
		display_title = sector_name
	else:
		# Conceal locked level names with ??? for mystery
		display_title = "???"

	# Style the card frame
	if is_active:
		var norm := _make_button_style(
			Color(0.035, 0.11, 0.20, 0.95),
			Color(0.35, 0.88, 1.0, 0.95),
			2, 12,
			Color(0.08, 0.52, 0.95, 0.35), 8
		)
		var hov := _make_button_style(
			Color(0.05, 0.16, 0.28, 0.98),
			Color(0.55, 0.95, 1.0, 1.0),
			2, 12,
			Color(0.15, 0.65, 1.0, 0.55), 12
		)
		var prs := _make_button_style(
			Color(0.08, 0.22, 0.36, 1.0),
			Color(0.75, 1.0, 1.0, 1.0),
			2, 12,
			Color(0.25, 0.85, 1.0, 0.65), 14
		)
		button.add_theme_stylebox_override("normal", norm)
		button.add_theme_stylebox_override("hover", hov)
		button.add_theme_stylebox_override("pressed", prs)
		button.add_theme_stylebox_override("focus", norm)
	elif is_cleared:
		var norm := _make_button_style(
			Color(0.024, 0.065, 0.11, 0.92),
			Color(0.18, 0.52, 0.58, 0.75),
			1, 12
		)
		var hov := _make_button_style(
			Color(0.04, 0.12, 0.19, 0.96),
			Color(0.32, 0.78, 0.82, 0.95),
			2, 12
		)
		var prs := _make_button_style(
			Color(0.06, 0.16, 0.25, 1.0),
			Color(0.45, 0.88, 0.95, 1.0),
			2, 12
		)
		button.add_theme_stylebox_override("normal", norm)
		button.add_theme_stylebox_override("hover", hov)
		button.add_theme_stylebox_override("pressed", prs)
		button.add_theme_stylebox_override("focus", norm)
	else:
		# Locked level: deep solid dark abyss styling with high contrast borders
		var locked_box := _make_button_style(
			Color(0.018, 0.042, 0.075, 0.96),
			Color(0.18, 0.30, 0.44, 0.85),
			1, 12
		)
		var locked_hov := _make_button_style(
			Color(0.028, 0.062, 0.105, 0.98),
			Color(0.28, 0.46, 0.66, 0.95),
			1, 12
		)
		button.add_theme_stylebox_override("normal", locked_box)
		button.add_theme_stylebox_override("hover", locked_hov)
		button.add_theme_stylebox_override("pressed", locked_box)
		button.add_theme_stylebox_override("focus", locked_box)

	# Connect procedural drawing for tactical decorations
	button.draw.connect(_draw_card_decorations.bind(button, is_active, is_cleared))

	# Margin container inside the card (extra left padding to clear the accent bar)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	button.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# --- Row 1: Sector Name & Status Badge ---
	var row1 := HBoxContainer.new()
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_theme_constant_override("separation", 8)
	vbox.add_child(row1)

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.text = display_title
	if is_active:
		title_lbl.add_theme_font_size_override("font_size", 18)
		title_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		title_lbl.add_theme_color_override("font_shadow_color", Color(0.05, 0.48, 0.95, 0.9))
		title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	elif is_cleared:
		title_lbl.add_theme_font_size_override("font_size", 17)
		title_lbl.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0))
	else:
		title_lbl.add_theme_font_size_override("font_size", 16)
		title_lbl.add_theme_color_override("font_color", Color(0.65, 0.78, 0.90, 0.92))
	row1.add_child(title_lbl)

	# Status chip: only READY for the active mission and LOCKED for locked sectors.
	# Cleared levels speak for themselves with their earned stars in row 2 (no redundant ESCAPED badge needed).
	if is_active:
		var status_box := HBoxContainer.new()
		status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_box.add_theme_constant_override("separation", 6)
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row1.add_child(status_box)

		var icon_canvas := Control.new()
		icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_canvas.custom_minimum_size = Vector2(14, 14)
		icon_canvas.draw.connect(_draw_beacon_icon.bind(icon_canvas))
		status_box.add_child(icon_canvas)

		var status_chip := Label.new()
		status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_chip.add_theme_font_size_override("font_size", 13)
		status_chip.text = "READY"
		status_chip.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		status_box.add_child(status_chip)
	elif not is_unlocked:
		var status_box := HBoxContainer.new()
		status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_box.add_theme_constant_override("separation", 6)
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row1.add_child(status_box)

		var icon_canvas := Control.new()
		icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_canvas.custom_minimum_size = Vector2(13, 15)
		icon_canvas.draw.connect(_draw_lock_icon.bind(icon_canvas))
		status_box.add_child(icon_canvas)

		var status_chip := Label.new()
		status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_chip.add_theme_font_size_override("font_size", 13)
		status_chip.text = "LOCKED"
		status_chip.add_theme_color_override("font_color", Color(0.55, 0.68, 0.82, 0.90))
		status_box.add_child(status_chip)

	# --- Row 2: Depth & Telemetry Subtitle + Ghost Stars ---
	var row2 := HBoxContainer.new()
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row2)

	var sub_lbl := Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.clip_text = true
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.text = display_subtitle
	if is_active:
		sub_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0, 0.98))
	elif is_cleared:
		sub_lbl.add_theme_color_override("font_color", Color(0.45, 0.82, 0.92, 0.90))
	else:
		sub_lbl.add_theme_color_override("font_color", Color(0.46, 0.58, 0.72, 0.88))
	row2.add_child(sub_lbl)

	# Display earned stars and best time exclusively on cleared levels (no empty stars on READY)
	if is_unlocked and stars > 0:
		var best_time: float = GameState.get_level_best_time(level_number)
		var is_ghost: bool = GameState.is_level_ghost_cleared(level_number)

		var star_box := HBoxContainer.new()
		star_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_box.add_theme_constant_override("separation", 6)
		star_box.alignment = BoxContainer.ALIGNMENT_END
		star_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var s1 := "★" if stars >= 1 else "☆"
		var s2 := "★" if is_ghost else ("★" if stars >= 2 else "☆")
		var s3 := "★" if stars >= 3 else "☆"

		var star_lbl := Label.new()
		star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star_lbl.text = "%s%s%s" % [s1, s2, s3]
		star_lbl.add_theme_font_size_override("font_size", 14)
		# Consistent radiant golden star color across all cards
		star_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28))
		star_box.add_child(star_lbl)

		if best_time > 0.0 and best_time < 900.0:
			var m := int(best_time) / 60
			var s := int(best_time) % 60
			var time_lbl := Label.new()
			time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			time_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			time_lbl.text = "%02d:%02d" % [m, s]
			time_lbl.add_theme_font_size_override("font_size", 13)
			time_lbl.add_theme_color_override("font_color", Color(0.68, 0.84, 0.95, 0.90))
			star_box.add_child(time_lbl)

		row2.add_child(star_box)

	if is_unlocked:
		button.pressed.connect(_on_level_pressed.bind(level_number))
		_wire_button_Juice(button)
	else:
		# Interactive sensor rejection feedback on touch
		button.pressed.connect(_on_locked_level_pressed.bind(button, sub_lbl, display_subtitle))

	return button


func _create_level_buttons() -> void:
	for child in level_grid.get_children():
		child.queue_free()
	_level_buttons.clear()

	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()

	if progress_label != null:
		var cur_unlocked := clampi(GameState.highest_unlocked_level, 1, total_levels)
		var total_stars := 0
		for i in range(1, total_levels + 1):
			total_stars += GameState.get_level_stars(i)
		progress_label.text = "SECTORS: %02d/%02d   ★ %d/%d" % [cur_unlocked, total_levels, total_stars, total_levels * 3]

	# Top padding in the grid (at top of cavern ascent)
	var top_pad_a := Control.new()
	top_pad_a.custom_minimum_size = Vector2(0, 20)
	top_pad_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_pad_b := Control.new()
	top_pad_b.custom_minimum_size = Vector2(0, 20)
	top_pad_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_grid.add_child(top_pad_a)
	level_grid.add_child(top_pad_b)

	# Levels progress from bottom (Depth 01) to top (Depth 13).
	# Because GridContainer lays out items from top to bottom,
	# we iterate downwards from total_levels down to 1.
	for i in range(total_levels, 0, -1):
		var card := _build_level_card(i, total_levels)
		_level_buttons[i] = card

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 60)
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Alternating zigzag:
		# If i % 2 == 1: Card on Left (col 0), Spacer on Right (col 1)
		# If i % 2 == 0: Spacer on Left (col 0), Card on Right (col 1)
		if i % 2 == 1:
			level_grid.add_child(card)
			level_grid.add_child(spacer)
		else:
			level_grid.add_child(spacer)
			level_grid.add_child(card)

	# Bottom padding in the grid (so Depth 01 has comfortable margin at bottom)
	var bot_pad_a := Control.new()
	bot_pad_a.custom_minimum_size = Vector2(0, 16)
	bot_pad_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bot_pad_b := Control.new()
	bot_pad_b.custom_minimum_size = Vector2(0, 16)
	bot_pad_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_grid.add_child(bot_pad_a)
	level_grid.add_child(bot_pad_b)

	call_deferred("_scroll_to_current_level")


func _scroll_to_current_level() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()
	var cur_lvl := clampi(GameState.highest_unlocked_level, 1, total_levels)
	var card: Button = _level_buttons.get(cur_lvl)
	if card != null and is_instance_valid(card):
		var vbar := scroll_container.get_v_scroll_bar()
		var max_scroll := maxf(0.0, vbar.max_value - scroll_container.size.y)
		# For starting levels (Depth 01 - 03), keep the bottom docked at the lower edge
		# so there is no large empty void underneath.
		if cur_lvl <= 3:
			scroll_container.scroll_vertical = int(max_scroll)
		else:
			var target_y := card.position.y - (scroll_container.size.y - card.size.y) * 0.5
			scroll_container.scroll_vertical = int(clampf(target_y, 0.0, max_scroll))


# --------------------------------------------------
# PROCEDURAL LEVEL CONNECTION CONDUITS
# --------------------------------------------------

# Varied multi-edge connection map:
# Not all lines are top-to-bottom. Some exit from the side wall (e.g. right of left card),
# some enter the side wall, creating a natural, hand-charted expedition route.
const CONNECTIONS: Dictionary = {
	1:  {"a_exit": "right", "a_frac": 0.45, "b_entry": "bottom", "b_frac": 0.30}, # Level 1 (Left): exits right side -> enters bottom of Level 2
	2:  {"a_exit": "top",   "a_frac": 0.30, "b_entry": "bottom", "b_frac": 0.70}, # Level 2 (Right): exits top -> enters bottom of Level 3
	3:  {"a_exit": "top",   "a_frac": 0.65, "b_entry": "left",   "b_frac": 0.65}, # Level 3 (Left): exits top -> enters left side of Level 4
	4:  {"a_exit": "left",  "a_frac": 0.40, "b_entry": "bottom", "b_frac": 0.68}, # Level 4 (Right): exits left side -> enters bottom of Level 5
	5:  {"a_exit": "right", "a_frac": 0.50, "b_entry": "bottom", "b_frac": 0.35}, # Level 5 (Left): exits right side -> enters bottom of Level 6
	6:  {"a_exit": "top",   "a_frac": 0.35, "b_entry": "bottom", "b_frac": 0.60}, # Level 6 (Right): exits top -> enters bottom of Level 7
	7:  {"a_exit": "top",   "a_frac": 0.70, "b_entry": "left",   "b_frac": 0.55}, # Level 7 (Left): exits top -> enters left side of Level 8
	8:  {"a_exit": "left",  "a_frac": 0.35, "b_entry": "bottom", "b_frac": 0.75}, # Level 8 (Right): exits left side -> enters bottom of Level 9
	9:  {"a_exit": "right", "a_frac": 0.45, "b_entry": "bottom", "b_frac": 0.25}, # Level 9 (Left): exits right side -> enters bottom of Level 10
	10: {"a_exit": "top",   "a_frac": 0.25, "b_entry": "right",  "b_frac": 0.65}, # Level 10 (Right): exits top -> enters right side of Level 11
	11: {"a_exit": "right", "a_frac": 0.40, "b_entry": "bottom", "b_frac": 0.40}, # Level 11 (Left): exits right side -> enters bottom of Level 12
	12: {"a_exit": "top",   "a_frac": 0.45, "b_entry": "bottom", "b_frac": 0.55}, # Level 12 (Right): exits top -> enters bottom of Level 13 (Surface Breach)
}


func _get_connection_spec(lvl: int) -> Dictionary:
	if CONNECTIONS.has(lvl):
		return CONNECTIONS[lvl]
	return {"a_exit": "top", "a_frac": 0.5, "b_entry": "bottom", "b_frac": 0.5}


func _get_dock_point(btn: Button, side: String, frac: float) -> Vector2:
	var pos := btn.position
	var sz := btn.size
	match side:
		"top":
			return Vector2(pos.x + sz.x * frac, pos.y)
		"bottom":
			return Vector2(pos.x + sz.x * frac, pos.y + sz.y)
		"left":
			return Vector2(pos.x, pos.y + sz.y * frac)
		"right":
			return Vector2(pos.x + sz.x, pos.y + sz.y * frac)
		_:
			return pos + sz * 0.5


func _eval_curved_path_point(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or t <= 0.0:
		return pts[0]
	if t >= 1.0:
		return pts[pts.size() - 1]
	var max_idx := pts.size() - 1
	var float_idx := clampf(t, 0.0, 1.0) * float(max_idx)
	var base_idx := int(floor(float_idx))
	var frac := float_idx - float(base_idx)
	if base_idx >= max_idx:
		return pts[max_idx]
	return pts[base_idx].lerp(pts[base_idx + 1], frac)


func _draw_level_path() -> void:
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()
	var highest: int = GameState.highest_unlocked_level

	for lvl in range(1, total_levels):
		var btn_a: Button = _level_buttons.get(lvl)
		var btn_b: Button = _level_buttons.get(lvl + 1)
		if btn_a == null or btn_b == null:
			continue
		if not is_instance_valid(btn_a) or not is_instance_valid(btn_b):
			continue

		var is_unlocked_path := (lvl + 1) <= highest
		var is_discovery_path := (lvl == highest)

		# Keep distant locked sectors uncluttered and dark
		if not is_unlocked_path and not is_discovery_path:
			continue

		var spec := _get_connection_spec(lvl)
		var a_exit: String = spec["a_exit"]
		var a_frac: float = spec["a_frac"]
		var b_entry: String = spec["b_entry"]
		var b_frac: float = spec["b_frac"]

		# Multi-edge docking points
		var start_pt := _get_dock_point(btn_a, a_exit, a_frac)
		var end_pt := _get_dock_point(btn_b, b_entry, b_frac)

		var dx := end_pt.x - start_pt.x
		var dy := absf(start_pt.y - end_pt.y)

		# Perpendicular tangent control handles matching dock geometry
		var cp1: Vector2
		match a_exit:
			"top":
				cp1 = start_pt + Vector2(dx * 0.12, -dy * 0.50)
			"bottom":
				cp1 = start_pt + Vector2(dx * 0.12, dy * 0.50)
			"right":
				# Exits rightward horizontally into the chasm
				cp1 = start_pt + Vector2(absf(dx) * 0.45, -dy * 0.08)
			"left":
				# Exits leftward horizontally into the chasm
				cp1 = start_pt + Vector2(-absf(dx) * 0.45, -dy * 0.08)
			_:
				cp1 = start_pt + Vector2(dx * 0.20, -dy * 0.50)

		var cp2: Vector2
		match b_entry:
			"bottom":
				# Enters from below upward into the bottom
				cp2 = end_pt + Vector2(-dx * 0.10, dy * 0.50)
			"top":
				# Enters from above downward into the top
				cp2 = end_pt + Vector2(-dx * 0.10, -dy * 0.50)
			"left":
				# Enters from the left horizontally into the card
				cp2 = end_pt + Vector2(-absf(dx) * 0.45, dy * 0.08)
			"right":
				# Enters from the right horizontally into the card
				cp2 = end_pt + Vector2(absf(dx) * 0.45, dy * 0.08)
			_:
				cp2 = end_pt + Vector2(-dx * 0.20, dy * 0.50)

		# Sample smooth Bezier points
		var segments := 28
		var pts: PackedVector2Array = []
		pts.resize(segments + 1)
		for s in range(segments + 1):
			var t := float(s) / float(segments)
			pts[s] = start_pt.bezier_interpolate(cp1, cp2, end_pt, t)

		# Connection terminal nodes on card edges
		var node_col := Color(0.35, 0.88, 1.0, 0.95) if is_unlocked_path else Color(0.28, 0.55, 0.75, 0.55)
		level_grid.draw_circle(start_pt, 3.2, node_col)
		level_grid.draw_circle(start_pt, 6.0, Color(node_col.r, node_col.g, node_col.b, 0.25))
		level_grid.draw_circle(end_pt, 3.2, node_col)
		level_grid.draw_circle(end_pt, 6.0, Color(node_col.r, node_col.g, node_col.b, 0.25))

		if is_unlocked_path:
			# 实线 (Solid Line) with bioluminescent glow for cleared/unlocked sectors
			level_grid.draw_polyline(pts, Color(0.12, 0.45, 0.75, 0.30), 5.5)
			level_grid.draw_polyline(pts, Color(0.35, 0.90, 1.0, 0.95), 2.4)

			# Traveling sonar acoustic pulse along the curve
			var pulse_t := fmod(_time * 0.55 + float(lvl) * 0.35, 1.0)
			var pulse_pt := _eval_curved_path_point(pts, pulse_t)
			level_grid.draw_circle(pulse_pt, 4.0, Color(0.90, 0.98, 1.0, 0.98))
			level_grid.draw_circle(pulse_pt, 8.5, Color(0.25, 0.75, 1.0, 0.35))
		elif is_discovery_path:
			# Subtle dashed discovery trail leading into the next locked sector
			var pulse_a := 0.35 + 0.3 * sin(_time * 3.0)
			var col := Color(0.35, 0.75, 1.0, pulse_a)
			for p in range(pts.size() - 1):
				if p % 2 == 0:
					level_grid.draw_line(pts[p], pts[p + 1], col, 1.8)


# --------------------------------------------------
# DYNAMIC DEPTH GAUGE (Real-Time Subterranean Altimeter)
# --------------------------------------------------

func _draw_depth_gauge() -> void:
	if depth_gauge == null or not is_instance_valid(depth_gauge):
		return

	var w := depth_gauge.size.x
	var h := depth_gauge.size.y
	if h <= 40.0:
		return

	var vbar := scroll_container.get_v_scroll_bar()
	var max_scroll := maxf(1.0, vbar.max_value - scroll_container.size.y)
	# scroll_ratio: 0.0 at top (Surface Breach), 1.0 at bottom (Abyss Origin)
	var scroll_ratio := clampf(float(scroll_container.scroll_vertical) / max_scroll, 0.0, 1.0)

	# Main vertical guideline axis (right-aligned)
	var x_axis := w - 8.0
	depth_gauge.draw_line(
		Vector2(x_axis, 20.0),
		Vector2(x_axis, h - 20.0),
		Color(0.22, 0.46, 0.68, 0.35),
		1.5
	)

	# Minimal Reference Milestones: 0M, -1300M, -2680M
	var milestones = [
		{"label": "0M", "ratio": 0.0},
		{"label": "-1300M", "ratio": 0.5},
		{"label": "-2680M", "ratio": 1.0},
	]

	for ms in milestones:
		var my := lerpf(20.0, h - 20.0, float(ms["ratio"]))
		# Milestone tick
		depth_gauge.draw_line(
			Vector2(x_axis - 5.0, my),
			Vector2(x_axis + 2.0, my),
			Color(0.35, 0.68, 0.9, 0.6),
			1.5
		)
		# Compact label left of the tick
		depth_gauge.draw_string(
			ThemeDB.fallback_font,
			Vector2(0.0, my + 4.0),
			str(ms["label"]),
			HORIZONTAL_ALIGNMENT_RIGHT,
			int(x_axis - 7.0),
			11,
			Color(0.5, 0.72, 0.9, 0.6)
		)

	# Subtle minor graduation ticks (every 10%)
	for i in range(1, 10):
		if i == 5:
			continue
		var frac := float(i) / 10.0
		var my := lerpf(20.0, h - 20.0, frac)
		depth_gauge.draw_line(
			Vector2(x_axis - 2.5, my),
			Vector2(x_axis, my),
			Color(0.2, 0.42, 0.6, 0.25),
			1.0
		)

	# Live Depth Cursor Tracking (Only displayed during active dragging / scrolling)
	if _depth_tag_alpha > 0.01:
		var cur_y := lerpf(20.0, h - 20.0, scroll_ratio)
		var cur_meters := int(round(lerpf(-40.0, -2680.0, scroll_ratio)))
		var depth_str := _format_depth_meters(cur_meters)

		# Bright live indicator tick & glowing bead on axis
		depth_gauge.draw_line(
			Vector2(x_axis - 7.0, cur_y),
			Vector2(x_axis + 4.0, cur_y),
			Color(0.35, 0.95, 1.0, 0.95 * _depth_tag_alpha),
			2.2
		)
		depth_gauge.draw_circle(Vector2(x_axis, cur_y), 3.5, Color(0.75, 0.98, 1.0, _depth_tag_alpha))

		# Clean, enlarged live readout tag
		var tag_w := 78.0
		var tag_h := 28.0
		var tag_x := x_axis - tag_w - 8.0
		var tag_y := clampf(cur_y - tag_h * 0.5, 6.0, h - tag_h - 6.0)
		var tag_rect := Rect2(tag_x, tag_y, tag_w, tag_h)

		# Glowing shadow behind badge
		depth_gauge.draw_rect(Rect2(tag_x - 3, tag_y - 3, tag_w + 6, tag_h + 6), Color(0.08, 0.45, 0.85, 0.3 * _depth_tag_alpha), true)
		# Deep semi-translucent dark badge background
		depth_gauge.draw_rect(tag_rect, Color(0.02, 0.08, 0.16, 0.95 * _depth_tag_alpha), true)
		# High-tech neon cyan border
		depth_gauge.draw_rect(tag_rect, Color(0.35, 0.9, 1.0, 0.95 * _depth_tag_alpha), false, 1.5)
		# Connector notch from badge to the rail bead
		depth_gauge.draw_line(
			Vector2(tag_x + tag_w, cur_y),
			Vector2(x_axis - 3.0, cur_y),
			Color(0.35, 0.9, 1.0, 0.85 * _depth_tag_alpha),
			1.6
		)
		# Centered depth string in crisp bold 14px font
		depth_gauge.draw_string(
			ThemeDB.fallback_font,
			Vector2(tag_x, tag_y + 19.5),
			depth_str,
			HORIZONTAL_ALIGNMENT_CENTER,
			int(tag_w),
			14,
			Color(0.95, 0.98, 1.0, _depth_tag_alpha)
		)


func _on_depth_gauge_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and not event.pressed):
		_is_dragging_gauge = false
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)) or (event is InputEventScreenDrag):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0

	if _is_dragging_gauge:
		var h := depth_gauge.size.y
		if h <= 40.0:
			return
		var ratio := clampf((event.position.y - 20.0) / (h - 40.0), 0.0, 1.0)
		var vbar := scroll_container.get_v_scroll_bar()
		var max_scroll := maxf(0.0, vbar.max_value - scroll_container.size.y)
		scroll_container.scroll_vertical = int(ratio * max_scroll)
		depth_gauge.queue_redraw()


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
	GameState.go_to_menu()


# --------------------------------------------------
# SETTINGS & INTEL / BESTIARY MODALS
# --------------------------------------------------

func _on_settings_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	GameState.go_to_settings("res://ui/level_select.tscn")


func _on_intel_pressed() -> void:
	_open_modal("SURVIVAL INTEL", "ACOUSTIC BESTIARY • TAP ENTITY TO PROVOKE EFFECTS", 520.0)
	_modal_body.add_theme_constant_override("separation", 10)
	_bestiary_entries.clear()

	_add_section_header("THREAT ARCHIVE & ACOUSTIC SPECIMENS")

	_add_bestiary_card(
		"sleeper",
		Color(0.72, 0.45, 1.0),
		"SLEEPER",
		"DORMANT LURKER",
		"Remains in deep torpor within the shadows. Awakens only if you sprint or step directly into its immediate proximity halo.",
		"Hold SNEAK to quietly slip past its sleep radius."
	)
	_add_bestiary_card(
		"patroller",
		Color(1.0, 0.82, 0.25),
		"PATROLLER",
		"ACOUSTIC SENTRY",
		"Relentlessly paces fixed cavern paths. Acute stereoscopic hearing allows it to detect even sneaking footsteps when within close range.",
		"Observe its patrol route; wait behind solid stone corners."
	)
	_add_bestiary_card(
		"chaser",
		Color(1.0, 0.28, 0.28),
		"CHASER",
		"APEX PREDATOR",
		"Deaf to subtle sneaking footfalls, but possesses lethal charge velocity. The moment an acoustic wave touches it, it charges straight toward the sound origin.",
		"Never shout or emit sonar when a Chaser lurks near."
	)
	_add_bestiary_card(
		"screamer",
		Color(0.95, 0.32, 0.72),
		"SCREAMER",
		"SONIC COCOON",
		"Stationary vocal entity. When disturbed by consecutive sound waves, it unleashes a deafening screech that reverberates across the entire cavern.",
		"Hide behind solid obstacles to block its concussive screech."
	)
	_add_bestiary_card(
		"listener",
		Color(0.22, 0.95, 0.68),
		"LISTENER",
		"THE HIVE EAR",
		"Completely deaf to normal footsteps. Accumulates sound waves; on reaching its 5th acoustic trigger, it transmits a global alarm to all beasts in the sector.",
		"Minimize voice and sonar usage; extract swiftly."
	)


func _add_bestiary_card(
	monster_type: String,
	badge_color: Color,
	monster_name: String,
	role_text: String,
	description: String,
	tip: String
) -> void:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 12.0
	card_style.content_margin_top = 10.0
	card_style.content_margin_right = 14.0
	card_style.content_margin_bottom = 10.0
	card_style.bg_color = Color(0.018, 0.048, 0.088, 0.92)
	card_style.border_color = badge_color.lerp(Color.WHITE, 0.25)
	card_style.border_color.a = 0.55
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(12)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	card_style.shadow_size = 4
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(hbox)

	# Left: Interactive Animated Monster Viewport
	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(96, 96)
	preview_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pbox_style := StyleBoxFlat.new()
	pbox_style.bg_color = Color(0.012, 0.028, 0.052, 0.96)
	pbox_style.border_color = badge_color * Color(1.0, 1.0, 1.0, 0.65)
	pbox_style.set_border_width_all(1)
	pbox_style.set_corner_radius_all(10)
	preview_box.add_theme_stylebox_override("panel", pbox_style)
	hbox.add_child(preview_box)

	var preview_canvas := Control.new()
	preview_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	preview_box.add_child(preview_canvas)

	# Right: Specimen Details & Tactical Intel
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	hbox.add_child(vb)

	# Row 1: Name + Role + Interactive State Tag
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	vb.add_child(r1)

	var name_lbl := Label.new()
	name_lbl.text = monster_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", badge_color.lerp(Color.WHITE, 0.45))
	r1.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = "[ %s ]" % role_text
	role_lbl.add_theme_font_size_override("font_size", 10)
	role_lbl.add_theme_color_override("font_color", Color(badge_color.r, badge_color.g, badge_color.b, 0.75))
	role_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(role_lbl)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)
	r1.add_child(status_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98, 0.92))
	vb.add_child(desc_lbl)

	# Tactical Tip
	var tip_lbl := Label.new()
	tip_lbl.text = "SURVIVAL: " + tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", Color(0.40, 0.82, 1.0, 0.90))
	vb.add_child(tip_lbl)

	# Interactive Prompt Hint
	var hint_lbl := Label.new()
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", Color(0.52, 0.72, 0.88, 0.75))
	vb.add_child(hint_lbl)

	var entry := {
		"type": monster_type,
		"name": monster_name,
		"role": role_text,
		"color": badge_color,
		"stage": 0,
		"pips": 0,
		"timer": 0.0,
		"shake": 0.0,
		"shockwaves": [],
		"canvas": preview_canvas,
		"box": preview_box,
		"status_lbl": status_lbl,
		"hint_lbl": hint_lbl
	}
	_update_bestiary_entry_labels(entry)
	_bestiary_entries.append(entry)

	preview_canvas.draw.connect(_draw_monster_preview.bind(preview_canvas, entry))
	preview_canvas.gui_input.connect(_on_monster_canvas_gui_input.bind(entry))

	_modal_body.add_child(card)


func _update_bestiary_entry_labels(entry: Dictionary) -> void:
	var m_type: String = str(entry.get("type", ""))
	var stage: int = int(entry.get("stage", 0))
	var col: Color = entry.get("color", Color.WHITE)
	var status_lbl: Label = entry.get("status_lbl", null)
	var hint_lbl: Label = entry.get("hint_lbl", null)
	if status_lbl == null or not is_instance_valid(status_lbl):
		return

	match m_type:
		"screamer":
			if stage == 0:
				status_lbl.text = "[ STABLE COCOON ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: 1st Sound Fracture"
			elif stage == 1:
				status_lbl.text = "[ FRACTURED / WARNING ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
				hint_lbl.text = "▶ TAP AGAIN: 2nd Sound (DEAFENING SCREAM)"
			else:
				status_lbl.text = "[ DEAFENING SCREAM ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.35))
				hint_lbl.text = "▶ ACOUSTIC SHOCKWAVE ACTIVE (TAP TO CALM)"
		"sleeper":
			if stage == 0:
				status_lbl.text = "[ DEEP TORPOR ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Provoke Sleeper"
			elif stage == 1:
				status_lbl.text = "[ EYE OPEN / STIRRING ]"
				status_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0))
				hint_lbl.text = "▶ TAP AGAIN: Trigger Alert Roar"
			else:
				status_lbl.text = "[ ALERT ROAR ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
				hint_lbl.text = "▶ LURKER AWAKENED (TAP TO CALM)"
		"patroller":
			if stage == 0:
				status_lbl.text = "[ FIXED PATROL ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Trigger Radar Sweep"
			elif stage == 1:
				status_lbl.text = "[ ACTIVE RADAR SWEEP ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
				hint_lbl.text = "▶ TAP AGAIN: Sentry Detection Roar"
			else:
				status_lbl.text = "[ SENTRY ALERT ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
				hint_lbl.text = "▶ TARGET ACQUIRED (TAP TO CALM)"
		"chaser":
			if stage == 0:
				status_lbl.text = "[ DORMANT STALKER ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Agitate Apex Predator"
			elif stage == 1:
				status_lbl.text = "[ FRENZIED SPIN ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
				hint_lbl.text = "▶ TAP AGAIN: Lethal Apex Charge Roar"
			else:
				status_lbl.text = "[ APEX RUSH ROAR ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.2))
				hint_lbl.text = "▶ CHARGING AT FULL SPEED (TAP TO CALM)"
		"listener":
			var pips: int = int(entry.get("pips", 0))
			if pips == 0:
				status_lbl.text = "[ PASSIVE (0/5 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Accumulate Acoustic Sound"
			elif pips < 4:
				status_lbl.text = "[ ACOUSTIC PIPS %d/5 ]" % pips
				status_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75))
				hint_lbl.text = "▶ TAP AGAIN: Sound Pip (%d/5)" % (pips + 1)
			elif pips == 4:
				status_lbl.text = "[ CRITICAL (4/5 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
				hint_lbl.text = "▶ TAP AGAIN: 5/5 GLOBAL HIVE ALARM!"
			else:
				status_lbl.text = "[ GLOBAL ALARM TRANSMITTED ]"
				status_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.65))
				hint_lbl.text = "▶ HIVE ALARM REVERBERATING (TAP TO RESET)"


func _on_monster_canvas_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_on_bestiary_entity_clicked(entry)


func _on_bestiary_entity_clicked(entry: Dictionary) -> void:
	var m_type: String = str(entry.get("type", ""))
	var cur_stage: int = int(entry.get("stage", 0))

	# Punch bounce animation on the specimen frame
	var box: PanelContainer = entry.get("box", null)
	if box != null and is_instance_valid(box):
		box.pivot_offset = box.size * 0.5
		var tw := create_tween()
		tw.tween_property(box, "scale", Vector2(1.10, 1.10), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(box, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var sfx := _get_or_create_sfx_mgr()

	match m_type:
		"screamer":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_screamer_crack, 1.5, randf_range(0.96, 1.04))
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.45, 0.95)},
					{"r": -22.0, "max_r": 95.0, "col": Color(1.0, 0.35, 0.65, 0.85)},
					{"r": -44.0, "max_r": 95.0, "col": Color(1.0, 0.5, 0.8, 0.75)}
				]
				_play_ui_sound(sfx._wav_screamer_shriek, 3.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"sleeper":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.5
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_echo_ping, -10.0, 0.75)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 10.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(0.72, 0.45, 1.0, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(0.85, 0.65, 1.0, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_sleeper, 2.5, 0.95)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"patroller":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_echo_ping, -8.0, 1.35)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 9.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(1.0, 0.82, 0.25, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(1.0, 0.95, 0.5, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_patroller, 2.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"chaser":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_charge_full, -6.0, 0.85)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.2, 0.95)},
					{"r": -25.0, "max_r": 95.0, "col": Color(1.0, 0.4, 0.4, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_chaser, 3.0, 1.05)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"listener":
			var pips: int = int(entry.get("pips", 0))
			if pips < 4:
				entry["pips"] = pips + 1
				entry["stage"] = 1
				entry["shake"] = 2.5
				var pip_pitch: float = 0.85 + float(entry["pips"]) * 0.12
				_play_ui_sound(sfx._wav_listener_pip, 1.0, pip_pitch)
			elif pips == 4:
				entry["pips"] = 5
				entry["stage"] = 2
				entry["shake"] = 14.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 100.0, "col": Color(0.2, 0.95, 0.7, 0.95)},
					{"r": -25.0, "max_r": 100.0, "col": Color(0.35, 1.0, 0.85, 0.85)},
					{"r": -50.0, "max_r": 100.0, "col": Color(0.55, 1.0, 0.95, 0.75)}
				]
				_play_ui_sound(sfx._wav_listener_alarm, 3.5, 1.0)
			else:
				entry["pips"] = 0
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

	_update_bestiary_entry_labels(entry)
	var canvas: Control = entry.get("canvas", null)
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_redraw()


func _draw_monster_preview(canvas: Control, entry: Dictionary) -> void:
	var shake: float = float(entry.get("shake", 0.0))
	var jitter := Vector2.ZERO
	if shake > 0.01:
		jitter = Vector2(sin(_time * 50.0), cos(_time * 43.0)) * shake
	var c := canvas.size * 0.5 + jitter

	# 1. Subtle radar containment reticle background
	canvas.draw_arc(c, 40.0, 0.0, TAU, 32, Color(0.14, 0.28, 0.42, 0.22), 1.0)
	canvas.draw_arc(c, 24.0, 0.0, TAU, 24, Color(0.14, 0.28, 0.42, 0.16), 1.0)
	canvas.draw_line(c + Vector2(-42, 0), c + Vector2(-34, 0), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(34, 0), c + Vector2(42, 0), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(0, -42), c + Vector2(0, -34), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(0, 34), c + Vector2(0, 42), Color(0.2, 0.45, 0.65, 0.35), 1.0)

	# 2. Expanding shockwave rings (Screamer screech / Roar / Listener Alarm)
	for sw in entry.get("shockwaves", []):
		var r: float = float(sw.get("r", 0.0))
		var max_r: float = float(sw.get("max_r", 80.0))
		if r > 0.0:
			var frac := clampf(1.0 - r / max_r, 0.0, 1.0)
			var base_col: Color = sw.get("col", Color(1, 1, 1, 1))
			var col := Color(base_col.r, base_col.g, base_col.b, base_col.a * frac)
			canvas.draw_arc(c, r, 0.0, TAU, 36, col, 2.2)

	# 3. Monster specimen rendering
	var m_type: String = str(entry.get("type", ""))
	var stage: int = int(entry.get("stage", 0))
	var base_col: Color = entry.get("color", Color.WHITE)

	match m_type:
		"screamer":
			_draw_preview_screamer(canvas, c, stage, base_col)
		"sleeper":
			_draw_preview_sleeper(canvas, c, stage, base_col)
		"patroller":
			_draw_preview_patroller(canvas, c, stage, base_col)
		"chaser":
			_draw_preview_chaser(canvas, c, stage, base_col)
		"listener":
			_draw_preview_listener(canvas, c, stage, base_col, int(entry.get("pips", 0)))


func _draw_preview_screamer(canvas: Control, c: Vector2, stage: int, col: Color) -> void:
	if stage == 2:
		var pulse := 1.0 + 0.16 * sin(_time * 24.0)
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			canvas.draw_line(c, c + Vector2.from_angle(ang) * (34.0 * pulse), Color(1.0, 0.3, 0.6, 0.95), 3.2)
		canvas.draw_circle(c, 13.0, Color(1.0, 0.1, 0.35, 1.0))
		canvas.draw_circle(c, 5.0, Color(1.0, 1.0, 1.0, 1.0))
		var w_r := 18.0 + fmod(_time * 45.0, 30.0)
		canvas.draw_arc(c, w_r, 0.0, TAU, 24, Color(1.0, 0.2, 0.45, 0.65), 1.8)
	else:
		var pulse_freq: float = 20.0 if stage == 1 else 2.5
		var pulse: float = 1.0 + (0.22 if stage == 1 else 0.12) * sin(_time * pulse_freq)
		var r: float = 16.0 * pulse
		canvas.draw_arc(c, r, 0.0, TAU, 24, col, 2.2)
		canvas.draw_circle(c, r * 0.72, Color(col.r, col.g, col.b, 0.38))
		if stage == 1:
			var flash := Color(1.0, 0.25, 0.45, 0.95)
			canvas.draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), flash, 2.2)
			canvas.draw_line(c + Vector2(10, -10), c + Vector2(-10, 10), flash, 2.2)
			canvas.draw_line(c + Vector2(-3, -12), c + Vector2(2, 12), Color(1.0, 0.4, 0.6, 0.85), 1.6)
			canvas.draw_circle(c, 5.5, flash)
		else:
			canvas.draw_circle(c, 4.5, Color(0.2, 0.05, 0.15, 0.9))


func _draw_preview_sleeper(canvas: Control, c: Vector2, stage: int, col: Color) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + _time * 4.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 25.0 + sin(_time * 40.0 + i) * 5.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(col.r, col.g * 0.6, col.b * 0.6, 0.95), 2.6)
		canvas.draw_circle(c, 15.0, Color(col, 0.95))
		canvas.draw_circle(c, 7.0, Color(1.0, 1.0, 1.0, 1.0))
		var pupil_dir := Vector2.DOWN * 8.0
		canvas.draw_line(c - pupil_dir, c + pupil_dir, Color(0.1, 0.0, 0.0, 1.0), 3.2)
		canvas.draw_circle(c, 2.5, Color(1.0, 0.2, 0.2, 1.0))
		var r_wave := 16.0 + fmod(_time * 42.0, 28.0)
		canvas.draw_arc(c, r_wave, 0.0, TAU, 24, Color(col, 0.6), 1.8)
	elif stage == 1:
		canvas.draw_arc(c, 21.0 + 3.0 * sin(_time * 8.0), 0.0, TAU, 24, Color(col, 0.5), 1.8)
		canvas.draw_circle(c, 15.0, col)
		canvas.draw_circle(c, 7.0, Color(1.0, 0.92, 1.0))
		var gaze := Vector2(cos(_time * 2.5), sin(_time * 2.5)) * 3.0
		canvas.draw_circle(c + gaze, 3.5, Color(0.18, 0.05, 0.3))
	else:
		var breathe := 0.5 + 0.5 * sin(_time * 1.8)
		canvas.draw_circle(c, 16.0 + 4.0 * breathe, Color(col, 0.18))
		canvas.draw_circle(c, 15.0, Color(col, 0.65))
		canvas.draw_line(c + Vector2(-11, 0), c + Vector2(11, 0), Color(0.18, 0.05, 0.3, 0.95), 2.8)


func _draw_preview_patroller(canvas: Control, c: Vector2, stage: int, col: Color) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + _time * 4.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 25.0 + sin(_time * 40.0 + i) * 5.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.5, 0.2, 0.95), 2.6)
		canvas.draw_circle(c, 15.0, Color(1.0, 0.6, 0.2, 0.95))
		canvas.draw_circle(c, 6.0, Color(1.0, 1.0, 1.0, 1.0))
	else:
		canvas.draw_circle(c, 14.0, col)
		canvas.draw_circle(c + Vector2(2, 0), 6.0, Color(1.0, 0.95, 0.85))
		var orbit_r := 22.0
		var orbit_speed: float = 7.0 if stage == 1 else 3.2
		canvas.draw_arc(c, orbit_r, 0.0, TAU, 28, Color(col, 0.4), 1.4)
		for i in 3:
			var ang := _time * orbit_speed + i * TAU / 3.0
			canvas.draw_circle(c + Vector2.from_angle(ang) * orbit_r, 3.4, Color(1.0, 0.95, 0.5, 1.0))
		if stage == 1:
			var sweep_ang: float = _time * 3.2
			canvas.draw_arc(c, 30.0, sweep_ang - 0.55, sweep_ang + 0.55, 16, Color(col, 0.75), 2.2)
			canvas.draw_arc(c, 38.0, sweep_ang - 0.38, sweep_ang + 0.38, 14, Color(col, 0.45), 1.6)


func _draw_preview_chaser(canvas: Control, c: Vector2, stage: int, col: Color) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + _time * 5.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 27.0 + sin(_time * 45.0 + i) * 6.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.15, 0.15, 0.95), 2.8)
		canvas.draw_circle(c, 15.0, Color(1.0, 0.15, 0.15, 1.0))
		canvas.draw_circle(c, 6.0, Color(1.0, 0.9, 0.9, 1.0))
		var pupil_dir := Vector2.UP * 8.0
		canvas.draw_line(c - pupil_dir, c + pupil_dir, Color(0.1, 0.0, 0.0, 1.0), 3.2)
	else:
		var spike_count := 6
		var spin: float = 6.0 if stage == 1 else 1.8
		var vib: float = sin(_time * 30.0) * (3.5 if stage == 1 else 1.2)
		var core_r := 14.0
		for i in spike_count:
			var ang := i * TAU / float(spike_count) + _time * spin
			var p_base := c + Vector2.from_angle(ang) * core_r
			var p_tip := c + Vector2.from_angle(ang) * (core_r + 10.0 + vib)
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.25, 0.25, 0.95), 2.6)
		if stage == 1:
			for tr in 3:
				var tr_ang := _time * spin - (tr + 1) * 0.22
				canvas.draw_circle(c + Vector2.from_angle(tr_ang) * 12.0, 8.0 - tr * 2.0, Color(1.0, 0.1, 0.1, 0.25 - tr * 0.07))
		canvas.draw_circle(c, core_r, col)
		var slit_dir := Vector2.UP * 7.0
		canvas.draw_line(c - slit_dir, c + slit_dir, Color(0.1, 0.0, 0.0, 0.95), 3.0)
		canvas.draw_circle(c, 2.5, Color(1.0, 0.8, 0.8, 1.0))


func _draw_preview_listener(canvas: Control, c: Vector2, stage: int, col: Color, pips: int) -> void:
	canvas.draw_arc(c, 18.0, -PI * 0.8, PI * 0.8, 28, col, 2.8)
	canvas.draw_circle(c, 9.5, Color(col, 0.45))
	for i in 5:
		var ang := -PI * 0.72 + i * (PI * 1.44 / 4.0)
		var pip_pos := c + Vector2.from_angle(ang) * 28.0
		if pips > i:
			var flare: float = 1.0 + (0.35 * sin(_time * 20.0) if pips == 5 else 0.0)
			canvas.draw_circle(pip_pos, 4.8 * flare, Color(0.2, 1.0, 0.7, 1.0))
			canvas.draw_circle(pip_pos, 2.2 * flare, Color(1.0, 1.0, 1.0, 1.0))
		else:
			canvas.draw_circle(pip_pos, 3.2, Color(col, 0.28))
	if stage == 2:
		var a_r := 22.0 + fmod(_time * 50.0, 32.0)
		canvas.draw_arc(c, a_r, 0.0, TAU, 28, Color(0.2, 1.0, 0.7, 0.7), 2.0)


func _draw_menu_mic_meter(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas) or canvas.is_queued_for_deletion():
		return
	var w: float = canvas.size.x
	var h: float = canvas.size.y
	var bar_h := 16.0
	var bar_y := (h - bar_h) * 0.5

	# Recessed slot background
	canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.02, 0.06, 0.12, 0.95), true)

	var cur_db: float = _menu_mic.level_db if (_menu_mic != null and is_instance_valid(_menu_mic) and GameState.mic_enabled) else -80.0
	var trig_db: float = GameState.get_mic_trigger_db()

	var fill_frac: float = clampf(inverse_lerp(-70.0, -5.0, cur_db), 0.0, 1.0)
	var trig_frac: float = clampf(inverse_lerp(-70.0, -5.0, trig_db), 0.0, 1.0)

	var active: bool = cur_db >= trig_db
	var fill_col: Color = Color(0.35, 0.95, 1.0, 0.95) if active else Color(0.20, 0.55, 0.80, 0.80)
	if fill_frac > 0.01:
		canvas.draw_rect(Rect2(0.0, bar_y, w * fill_frac, bar_h), fill_col, true)

	# Clean metallic border
	canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.24, 0.52, 0.78, 0.65), false, 1.0)

	# Trigger needle
	var tx: float = clampf(w * trig_frac, 2.0, w - 2.0)
	canvas.draw_line(Vector2(tx, bar_y - 2.5), Vector2(tx, bar_y + bar_h + 2.5), Color(1.0, 0.85, 0.30, 1.0), 2.0)


func _refresh_mic_btn(btn: Button) -> void:
	btn.self_modulate = Color.WHITE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	if GameState.mic_enabled:
		btn.text = "ENABLED"
		btn.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		style.bg_color = Color(0.04, 0.14, 0.24, 0.90)
		style.border_color = Color(0.28, 0.75, 1.0, 0.85)
	else:
		btn.text = "MUTED"
		btn.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80, 0.75))
		style.bg_color = Color(0.06, 0.08, 0.12, 0.80)
		style.border_color = Color(0.24, 0.35, 0.46, 0.65)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)


func _refresh_mute_btn(btn: Button) -> void:
	btn.self_modulate = Color.WHITE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	if not GameState.master_muted:
		btn.text = "ENABLED"
		btn.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		style.bg_color = Color(0.04, 0.14, 0.24, 0.90)
		style.border_color = Color(0.28, 0.75, 1.0, 0.85)
	else:
		btn.text = "MUTED"
		btn.add_theme_color_override("font_color", Color(0.92, 0.45, 0.45, 0.90))
		style.bg_color = Color(0.12, 0.05, 0.07, 0.85)
		style.border_color = Color(0.55, 0.25, 0.30, 0.75)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)


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
	close_btn.add_theme_font_size_override("font_size", 16)
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.05, 0.14, 0.24, 0.45)
	close_normal.set_corner_radius_all(20)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.14, 0.32, 0.50, 0.7)
	close_hover.set_corner_radius_all(20)
	close_btn.add_theme_stylebox_override("normal", close_normal)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_color_override("font_color", Color(0.70, 0.85, 0.98, 0.85))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	close_btn.add_theme_color_override("font_pressed_color", Color(0.4, 0.95, 1.0, 1.0))
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

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 8)
	scroll_margin.add_theme_constant_override("margin_right", 8)
	scroll_margin.add_theme_constant_override("margin_top", 4)
	scroll_margin.add_theme_constant_override("margin_bottom", 4)
	_modal_scroll.add_child(scroll_margin)

	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 12)
	scroll_margin.add_child(_modal_body)


func _open_modal(title_text: String, subtitle_text: String, scroll_height: float = 460.0, allow_scroll: bool = true) -> void:
	for child in _modal_body.get_children():
		child.queue_free()

	_menu_meter_canvas = null
	_menu_calib_btn = null
	_modal_scroll.custom_minimum_size.y = scroll_height
	_modal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if allow_scroll else ScrollContainer.SCROLL_MODE_DISABLED
	var vbar := _modal_scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.modulate.a = 1.0 if allow_scroll else 0.0
	_modal_title.text = title_text
	_modal_subtitle.text = subtitle_text
	_is_modal_open = true
	_modal_root.visible = true
	_modal_scroll.scroll_vertical = 0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_modal_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_modal_panel.scale = Vector2(0.93, 0.93)
	_modal_panel.pivot_offset = Vector2(290.0, (scroll_height + 90.0) * 0.5)
	tw.tween_property(_modal_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_modal() -> void:
	if not _is_modal_open:
		return
	_play_ui_sound(_wav_click, -8.0, 0.9)
	_is_modal_open = false
	_bestiary_entries.clear()
	_menu_meter_canvas = null
	_menu_calib_btn = null
	if _menu_mic != null and is_instance_valid(_menu_mic):
		_menu_mic.queue_free()
		_menu_mic = null
	var tw := create_tween()
	tw.tween_property(_modal_root, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_modal_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _is_modal_open:
			_close_modal()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _create_section_header(title: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 13)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = Color(0.35, 0.85, 1.0, 0.95)
	hbox.add_child(bar)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.48, 0.84, 1.0, 0.95))
	lbl.add_theme_font_size_override("font_size", 11)
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


func _create_volume_slider_row(
	title: String,
	current_val: float,
	on_val_changed: Callable
) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.95))
	lbl.add_theme_font_size_override("font_size", 13)
	header.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(round(current_val * 100.0))
	val_lbl.custom_minimum_size = Vector2(46, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 1.0))
	val_lbl.add_theme_font_size_override("font_size", 13)
	header.add_child(val_lbl)

	box.add_child(header)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 20)
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = current_val
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%d%%" % int(round(v * 100.0))
		on_val_changed.call(v)
	)
	box.add_child(slider)

	return box


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
	if _is_modal_open and _menu_meter_canvas != null and is_instance_valid(_menu_meter_canvas) and not _menu_meter_canvas.is_queued_for_deletion():
		_menu_meter_canvas.queue_redraw()
		if _menu_calib_btn != null and is_instance_valid(_menu_calib_btn) and _menu_mic != null and is_instance_valid(_menu_mic):
			if _menu_mic.is_calibrating():
				_menu_calib_btn.text = "SAMPLING..."
				_menu_calib_btn.disabled = true
			else:
				_menu_calib_btn.text = "CALIBRATE ROOM"
				_menu_calib_btn.disabled = not GameState.mic_enabled

	# Animate active monster bestiary viewports if open
	if _is_modal_open and not _bestiary_entries.is_empty():
		for entry in _bestiary_entries:
			var shake: float = float(entry.get("shake", 0.0))
			if shake > 0.0:
				entry["shake"] = maxf(0.0, shake - delta * 14.0)

			var active_sw: Array = []
			for sw in entry.get("shockwaves", []):
				sw["r"] = float(sw.get("r", 0.0)) + delta * 140.0
				if float(sw.get("r", 0.0)) < float(sw.get("max_r", 90.0)):
					active_sw.append(sw)
			entry["shockwaves"] = active_sw

			var cur_stage: int = int(entry.get("stage", 0))
			if cur_stage == 2:
				entry["timer"] = float(entry.get("timer", 0.0)) + delta
				if float(entry["timer"]) > 3.2:
					entry["stage"] = 0
					entry["timer"] = 0.0
					entry["pips"] = 0
					_update_bestiary_entry_labels(entry)

			var cv: Control = entry.get("canvas", null)
			if cv != null and is_instance_valid(cv):
				cv.queue_redraw()

	# Periodic ambient sonar wave - matching Main Menu design (low frequency, random position, faint bioluminescent color)
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

	# Smooth fade transition for live depth readout tag
	if _is_dragging_gauge:
		_depth_tag_timer = 1.0
	elif _depth_tag_timer > 0.0:
		_depth_tag_timer = maxf(0.0, _depth_tag_timer - delta)

	var target_alpha: float = 1.0 if _depth_tag_timer > 0.0 else 0.0
	var fade_speed: float = 14.0 if target_alpha > _depth_tag_alpha else 3.5
	_depth_tag_alpha = move_toward(_depth_tag_alpha, target_alpha, delta * fade_speed)

	sonar_backdrop.queue_redraw()
	if level_grid != null and is_instance_valid(level_grid):
		level_grid.queue_redraw()
	if depth_gauge != null and is_instance_valid(depth_gauge):
		depth_gauge.queue_redraw()

	# Redraw active level card (pulsing glow) and locked cards (scanning laser effect)
	for lvl in _level_buttons:
		var btn: Button = _level_buttons[lvl]
		if btn != null and is_instance_valid(btn):
			if lvl >= GameState.highest_unlocked_level:
				btn.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _is_modal_open:
		return

	# Clicking/touching empty space creates an ECHO wave.
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_ripples.append({
			"pos": event.position,
			"age": 0.0,
			"max_r": 180.0,
			"alpha": 0.45,
			"dur": 2.0
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
		var dur: float = float(ripple.get("dur", 2.2))
		var progress := clampf(
			float(ripple["age"]) / dur,
			0.0,
			1.0
		)

		var radius := progress * float(ripple["max_r"])
		var alpha := (
			(1.0 - progress)
			* float(ripple.get("alpha", 0.45))
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
			Vector2(1.02, 1.02),
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
			Vector2(0.97, 0.97),
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
	_wav_error = _synth_tone(220.0, 140.0, 0.22)


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
	player.bus = &"SFX"

	add_child(player)

	player.finished.connect(player.queue_free)
	player.play()


func _init_sfx_manager() -> void:
	if _sfx_mgr == null:
		_sfx_mgr = SfxManager.new()
		_sfx_mgr._build_all_streams()
		add_child(_sfx_mgr)


func _get_or_create_sfx_mgr() -> SfxManager:
	if _sfx_mgr == null or not is_instance_valid(_sfx_mgr):
		_init_sfx_manager()
	return _sfx_mgr
