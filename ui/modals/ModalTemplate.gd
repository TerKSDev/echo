class_name ModalTemplate
extends RefCounted
## Unified Modal Design System for ECHO.
## Enforces consistent card width (560px), padding, corner radius, dimmer opacity,
## and restrained bioluminescent phosphor borders across all in-game modals.

const CARD_WIDTH: float = 560.0
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
	if on_close.is_valid():
		close_btn.pressed.connect(on_close)
	return close_btn
