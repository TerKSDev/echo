class_name ModalTemplate
extends RefCounted
## Unified Modal Design System for ECHO.
## Enforces consistent card width (592px, 64px side margins on 720px viewport), padding, corner radius, dimmer opacity,
## and restrained bioluminescent phosphor borders across all in-game modals.

const CARD_WIDTH: float = 592.0
const CORNER_RADIUS: int = 16
const BORDER_WIDTH: int = 2
const MARGIN_H: float = 28.0
const MARGIN_V: float = 24.0
const SHADOW_SIZE: int = 12
const DIMMER_COLOR: Color = Color(0.01, 0.02, 0.045, 0.86)

enum ThemeKind {
	SONAR,       ## System, Settings, Debrief, Intel, Guide/Credits
	ARCHIVE,     ## Lore Notes & Story Finale (Muted antique amber phosphor)
	CRIMSON,     ## Death Screen, Reset Confirm, Leaderboard
	SINGULARITY, ## Challenge Finale
}


static func apply_full_rect(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


static func hide_scrollbars(scroll: ScrollContainer) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbar := scroll.get_v_scroll_bar()
	if vbar != null and is_instance_valid(vbar):
		vbar.modulate.a = 0.0
		vbar.custom_minimum_size = Vector2.ZERO
	var hbar := scroll.get_h_scroll_bar()
	if hbar != null and is_instance_valid(hbar):
		hbar.modulate.a = 0.0
		hbar.custom_minimum_size = Vector2.ZERO


static func make_card_style(kind: int = ThemeKind.SONAR) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.content_margin_left = MARGIN_H
	s.content_margin_right = MARGIN_H
	s.content_margin_top = MARGIN_V
	s.content_margin_bottom = MARGIN_V
	s.set_border_width_all(BORDER_WIDTH)
	s.set_corner_radius_all(CORNER_RADIUS)
	s.shadow_size = SHADOW_SIZE

	match kind:
		ThemeKind.ARCHIVE:
			s.bg_color = Color(0.035, 0.05, 0.08, 0.97)
			s.border_color = Color(0.80, 0.64, 0.32, 0.72)
			s.shadow_color = Color(0.48, 0.34, 0.08, 0.18)
		ThemeKind.CRIMSON:
			s.bg_color = Color(0.05, 0.024, 0.042, 0.96)
			s.border_color = Color(0.80, 0.24, 0.30, 0.72)
			s.shadow_color = Color(0.45, 0.06, 0.12, 0.20)
		ThemeKind.SINGULARITY:
			s.bg_color = Color(0.045, 0.022, 0.065, 0.96)
			s.border_color = Color(0.80, 0.34, 0.64, 0.72)
			s.shadow_color = Color(0.42, 0.08, 0.32, 0.20)
		_:
			s.bg_color = Color(0.028, 0.068, 0.125, 0.96)
			s.border_color = Color(0.26, 0.60, 0.86, 0.72)
			s.shadow_color = Color(0.05, 0.26, 0.52, 0.20)
	return s


static func make_close_button(on_close: Callable, kind: int = ThemeKind.SONAR) -> Button:
	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 15)

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(18)
	var hover := StyleBoxFlat.new()
	hover.set_corner_radius_all(18)

	match kind:
		ThemeKind.ARCHIVE:
			normal.bg_color = Color(0.14, 0.12, 0.08, 0.55)
			hover.bg_color = Color(0.28, 0.22, 0.12, 0.78)
			close_btn.add_theme_color_override("font_color", Color(0.92, 0.84, 0.68, 0.88))
		ThemeKind.CRIMSON:
			normal.bg_color = Color(0.18, 0.06, 0.09, 0.55)
			hover.bg_color = Color(0.34, 0.10, 0.15, 0.78)
			close_btn.add_theme_color_override("font_color", Color(0.95, 0.75, 0.78, 0.88))
		_:
			normal.bg_color = Color(0.05, 0.14, 0.24, 0.50)
			hover.bg_color = Color(0.14, 0.30, 0.48, 0.75)
			close_btn.add_theme_color_override("font_color", Color(0.74, 0.88, 0.98, 0.88))

	close_btn.add_theme_stylebox_override("normal", normal)
	close_btn.add_theme_stylebox_override("hover", hover)
	close_btn.add_theme_stylebox_override("pressed", hover)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	close_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	if on_close.is_valid():
		close_btn.pressed.connect(on_close)
	return close_btn


static func style_button(btn: Button, is_primary: bool = false, kind: int = ThemeKind.SONAR) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = false
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0

	var hover := StyleBoxFlat.new()
	hover.set_corner_radius_all(10)
	hover.content_margin_left = 16.0
	hover.content_margin_right = 16.0
	hover.content_margin_top = 8.0
	hover.content_margin_bottom = 8.0

	var pressed := StyleBoxFlat.new()
	pressed.set_corner_radius_all(10)
	pressed.content_margin_left = 16.0
	pressed.content_margin_right = 16.0
	pressed.content_margin_top = 8.0
	pressed.content_margin_bottom = 8.0

	var border_col: Color
	var bg_col: Color
	var font_col: Color

	match kind:
		ThemeKind.CRIMSON:
			border_col = Color(0.92, 0.28, 0.35, 0.85) if is_primary else Color(0.70, 0.20, 0.26, 0.55)
			bg_col = Color(0.24, 0.05, 0.08, 0.90) if is_primary else Color(0.12, 0.03, 0.05, 0.70)
			font_col = Color(1.0, 0.92, 0.94, 1.0)
		ThemeKind.ARCHIVE:
			border_col = Color(0.85, 0.65, 0.30, 0.85) if is_primary else Color(0.60, 0.45, 0.20, 0.55)
			bg_col = Color(0.18, 0.12, 0.05, 0.90) if is_primary else Color(0.09, 0.06, 0.03, 0.70)
			font_col = Color(1.0, 0.95, 0.88, 1.0)
		ThemeKind.SINGULARITY:
			border_col = Color(0.85, 0.35, 0.75, 0.85) if is_primary else Color(0.60, 0.25, 0.55, 0.55)
			bg_col = Color(0.20, 0.05, 0.18, 0.90) if is_primary else Color(0.10, 0.03, 0.09, 0.70)
			font_col = Color(1.0, 0.92, 0.98, 1.0)
		_:
			border_col = Color(0.35, 0.78, 1.0, 0.85) if is_primary else Color(0.20, 0.50, 0.75, 0.55)
			bg_col = Color(0.05, 0.18, 0.32, 0.90) if is_primary else Color(0.03, 0.09, 0.16, 0.70)
			font_col = Color(0.88, 0.96, 1.0, 1.0)

	normal.bg_color = bg_col
	normal.border_color = border_col
	normal.set_border_width_all(2 if is_primary else 1)

	hover.bg_color = bg_col.lightened(0.12)
	hover.border_color = border_col.lightened(0.20)
	hover.set_border_width_all(2 if is_primary else 1)

	pressed.bg_color = bg_col.darkened(0.15)
	pressed.border_color = border_col
	pressed.set_border_width_all(2 if is_primary else 1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


## Capsule pill-shaped toggle switch button matching the Pause Modal design.
static func style_toggle_button(btn: Button, is_active: bool, on_text: String = "", off_text: String = "", kind: int = ThemeKind.SONAR) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = false
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 12)
	if btn.custom_minimum_size.y < 32.0:
		btn.custom_minimum_size.y = 32.0

	if is_active and not on_text.is_empty():
		btn.text = on_text
	elif not is_active and not off_text.is_empty():
		btn.text = off_text

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := StyleBoxFlat.new()
	hover.set_corner_radius_all(14)
	hover.content_margin_left = 14.0
	hover.content_margin_right = 14.0
	hover.content_margin_top = 4.0
	hover.content_margin_bottom = 4.0

	var pressed := StyleBoxFlat.new()
	pressed.set_corner_radius_all(14)
	pressed.content_margin_left = 14.0
	pressed.content_margin_right = 14.0
	pressed.content_margin_top = 4.0
	pressed.content_margin_bottom = 4.0

	var border_col: Color
	var bg_col: Color
	var font_col: Color

	if is_active:
		match kind:
			ThemeKind.CRIMSON:
				bg_col = Color(0.24, 0.05, 0.08, 0.90)
				border_col = Color(1.0, 0.35, 0.45, 0.95)
				font_col = Color(1.0, 0.88, 0.92, 1.0)
				normal.shadow_color = Color(0.85, 0.15, 0.25, 0.35)
				normal.shadow_size = 4
			ThemeKind.ARCHIVE:
				bg_col = Color(0.18, 0.12, 0.05, 0.90)
				border_col = Color(0.95, 0.75, 0.35, 0.95)
				font_col = Color(1.0, 0.95, 0.85, 1.0)
				normal.shadow_color = Color(0.65, 0.45, 0.10, 0.35)
				normal.shadow_size = 4
			ThemeKind.SINGULARITY:
				bg_col = Color(0.20, 0.05, 0.20, 0.90)
				border_col = Color(1.0, 0.45, 0.90, 0.95)
				font_col = Color(1.0, 0.90, 0.98, 1.0)
				normal.shadow_color = Color(0.75, 0.15, 0.65, 0.35)
				normal.shadow_size = 4
			_:
				bg_col = Color(0.04, 0.14, 0.26, 0.88)
				border_col = Color(0.35, 0.88, 1.0, 0.95)
				font_col = Color(0.40, 1.0, 1.0, 1.0)
				normal.shadow_color = Color(0.15, 0.55, 0.95, 0.35)
				normal.shadow_size = 4
		normal.set_border_width_all(2)
		hover.set_border_width_all(2)
		pressed.set_border_width_all(2)
	else:
		bg_col = Color(0.025, 0.07, 0.13, 0.80)
		border_col = Color(0.20, 0.42, 0.65, 0.50)
		font_col = Color(0.55, 0.72, 0.85, 0.75)
		normal.set_border_width_all(1)
		hover.set_border_width_all(1)
		pressed.set_border_width_all(1)

	normal.bg_color = bg_col
	normal.border_color = border_col

	hover.bg_color = bg_col.lightened(0.12)
	hover.border_color = border_col.lightened(0.20)
	hover.shadow_color = normal.shadow_color
	hover.shadow_size = normal.shadow_size + 2 if is_active else 0

	pressed.bg_color = bg_col.darkened(0.15)
	pressed.border_color = border_col

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


## Dark crimson glass warning button matching RESTART SECTOR in Pause Modal.
static func style_danger_button(btn: Button, is_primary: bool = false, is_pill: bool = false) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = false
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var rad := 14 if is_pill else 10
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(rad)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0

	var hover := StyleBoxFlat.new()
	hover.set_corner_radius_all(rad)
	hover.content_margin_left = 16.0
	hover.content_margin_right = 16.0
	hover.content_margin_top = 6.0
	hover.content_margin_bottom = 6.0

	var pressed := StyleBoxFlat.new()
	pressed.set_corner_radius_all(rad)
	pressed.content_margin_left = 16.0
	pressed.content_margin_right = 16.0
	pressed.content_margin_top = 6.0
	pressed.content_margin_bottom = 6.0

	var bg_col := Color(0.20, 0.04, 0.07, 0.90) if is_primary else Color(0.14, 0.035, 0.055, 0.85)
	var border_col := Color(0.95, 0.30, 0.38, 0.92) if is_primary else Color(0.75, 0.22, 0.28, 0.75)
	var b_width := 2 if is_primary else 1

	normal.bg_color = bg_col
	normal.border_color = border_col
	normal.set_border_width_all(b_width)
	if is_primary:
		normal.shadow_color = Color(0.85, 0.15, 0.25, 0.35)
		normal.shadow_size = 6

	hover.bg_color = bg_col.lightened(0.15)
	hover.border_color = border_col.lightened(0.22)
	hover.set_border_width_all(b_width)
	if is_primary:
		hover.shadow_color = Color(1.0, 0.20, 0.30, 0.50)
		hover.shadow_size = 8

	pressed.bg_color = bg_col.darkened(0.18)
	pressed.border_color = border_col
	pressed.set_border_width_all(b_width)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1.0, 0.86, 0.90, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


## Sleek glowing slider matching Master Volume in Pause Modal.
static func style_slider(slider: HSlider, kind: int = ThemeKind.SONAR) -> void:
	if slider == null or not is_instance_valid(slider):
		return
	slider.focus_mode = Control.FOCUS_NONE
	slider.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Active glowing fill line
	var fill := StyleBoxFlat.new()
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	fill.set_corner_radius_all(4)

	# Trough / Background slot
	var slot := StyleBoxFlat.new()
	slot.content_margin_top = 4.0
	slot.content_margin_bottom = 4.0
	slot.set_border_width_all(1)
	slot.set_corner_radius_all(4)

	match kind:
		ThemeKind.ARCHIVE:
			fill.bg_color = Color(0.92, 0.72, 0.32, 0.95)
			slot.bg_color = Color(0.12, 0.08, 0.04, 0.85)
			slot.border_color = Color(0.55, 0.40, 0.18, 0.50)
		ThemeKind.CRIMSON:
			fill.bg_color = Color(0.95, 0.30, 0.38, 0.95)
			slot.bg_color = Color(0.14, 0.04, 0.06, 0.85)
			slot.border_color = Color(0.65, 0.20, 0.28, 0.50)
		_:
			fill.bg_color = Color(0.32, 0.75, 1.0, 0.95)
			slot.bg_color = Color(0.06, 0.14, 0.24, 0.85)
			slot.border_color = Color(0.20, 0.45, 0.70, 0.50)

	slider.add_theme_stylebox_override("slider", slot)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
