class_name DepthGaugeRenderer
extends RefCounted
## Dynamic Subterranean Altimeter & Drag Scrubber for Level Select.
## Displays elevation milestones (0M to -2680M) and tracks live depth cursor.

static func format_depth_meters(meters: int) -> String:
	var abs_val := absi(meters)
	var sign_str := "-" if meters < 0 else ""
	var s := str(abs_val)
	if s.length() > 3:
		var insert_idx := s.length() - 3
		s = s.substr(0, insert_idx) + "," + s.substr(insert_idx)
	return sign_str + s + " M"


static func draw_depth_gauge(
	depth_gauge: Control,
	scroll_container: ScrollContainer,
	depth_tag_alpha: float
) -> void:
	if depth_gauge == null or not is_instance_valid(depth_gauge):
		return

	var w := depth_gauge.size.x
	var h := depth_gauge.size.y
	if h <= 40.0:
		return

	var vbar := scroll_container.get_v_scroll_bar()
	var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
	var max_scroll := maxf(1.0, vbar.max_value - page)
	# scroll_ratio: 0.0 at top (Surface Breach 0M), 1.0 at bottom (Abyss Origin -2680M)
	var scroll_ratio := clampf(float(scroll_container.scroll_vertical) / max_scroll, 0.0, 1.0)

	var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE

	# Color scheme based on active mode
	var axis_col := Color(0.55, 0.25, 0.55, 0.45) if is_challenge else Color(0.22, 0.46, 0.68, 0.35)
	var tick_col := Color(0.85, 0.45, 0.75, 0.7) if is_challenge else Color(0.35, 0.68, 0.9, 0.6)
	var label_col := Color(0.95, 0.75, 0.90, 0.85) if is_challenge else Color(0.65, 0.82, 0.98, 0.85)
	var minor_tick_col := Color(0.45, 0.20, 0.45, 0.35) if is_challenge else Color(0.2, 0.42, 0.6, 0.25)

	# Main vertical guideline axis (right-aligned)
	var x_axis := w - 8.0
	depth_gauge.draw_line(
		Vector2(x_axis, 20.0),
		Vector2(x_axis, h - 20.0),
		axis_col,
		1.5
	)

	# Reference Milestones
	var milestones: Array[Dictionary] = []
	if is_challenge:
		var has_sp := GameState.challenge_highest_unlocked >= 21
		var bottom_lbl := "-9,999M" if has_sp else "-9,250M"
		var mid_lbl := "-7,250M" if has_sp else "-6,875M"
		milestones = [
			{"label": "-4,500M", "ratio": 0.0},
			{"label": mid_lbl, "ratio": 0.5},
			{"label": bottom_lbl, "ratio": 1.0},
		]
	else:
		milestones = [
			{"label": "0M", "ratio": 0.0},
			{"label": "-2,100M", "ratio": 0.5},
			{"label": "-4,200M", "ratio": 1.0},
		]

	for ms in milestones:
		var my := lerpf(20.0, h - 20.0, float(ms["ratio"]))
		# Milestone tick
		depth_gauge.draw_line(
			Vector2(x_axis - 5.0, my),
			Vector2(x_axis + 2.0, my),
			tick_col,
			1.5
		)
		# Compact label left of the tick (enlarged to 13px for enhanced legibility)
		depth_gauge.draw_string(
			ThemeDB.fallback_font,
			Vector2(0.0, my + 5.0),
			str(ms["label"]),
			HORIZONTAL_ALIGNMENT_RIGHT,
			int(x_axis - 7.0),
			13,
			label_col
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
			minor_tick_col,
			1.0
		)

	# Live Depth Cursor Tracking (Only displayed during active dragging / scrolling)
	if depth_tag_alpha > 0.01:
		var cur_y := lerpf(20.0, h - 20.0, scroll_ratio)
		var cur_meters: int = 0
		if is_challenge:
			var max_depth := -9999.0 if GameState.challenge_highest_unlocked >= 21 else -9250.0
			cur_meters = int(round(lerpf(-4500.0, max_depth, scroll_ratio)))
		else:
			cur_meters = int(round(lerpf(0.0, -4200.0, scroll_ratio)))
		var depth_str := format_depth_meters(cur_meters)

		var cursor_glow := Color(1.0, 0.4, 0.75, 0.95 * depth_tag_alpha) if is_challenge else Color(0.35, 0.95, 1.0, 0.95 * depth_tag_alpha)
		var cursor_bead := Color(1.0, 0.85, 0.95, depth_tag_alpha) if is_challenge else Color(0.75, 0.98, 1.0, depth_tag_alpha)
		var badge_border := Color(1.0, 0.5, 0.85, 0.95 * depth_tag_alpha) if is_challenge else Color(0.35, 0.9, 1.0, 0.95 * depth_tag_alpha)
		var badge_glow := Color(0.65, 0.15, 0.45, 0.35 * depth_tag_alpha) if is_challenge else Color(0.08, 0.45, 0.85, 0.3 * depth_tag_alpha)

		# Bright live indicator tick & glowing bead on axis
		depth_gauge.draw_line(
			Vector2(x_axis - 7.0, cur_y),
			Vector2(x_axis + 4.0, cur_y),
			cursor_glow,
			2.2
		)
		depth_gauge.draw_circle(Vector2(x_axis, cur_y), 3.5, cursor_bead)

		# Clean, enlarged live readout tag
		var tag_w := 82.0
		var tag_h := 28.0
		var tag_x := x_axis - tag_w - 8.0
		var tag_y := clampf(cur_y - tag_h * 0.5, 6.0, h - tag_h - 6.0)
		var tag_rect := Rect2(tag_x, tag_y, tag_w, tag_h)

		# Glowing shadow behind badge
		depth_gauge.draw_rect(Rect2(tag_x - 3, tag_y - 3, tag_w + 6, tag_h + 6), badge_glow, true)
		# Deep semi-translucent dark badge background
		depth_gauge.draw_rect(tag_rect, Color(0.02, 0.05, 0.12, 0.95 * depth_tag_alpha), true)
		# High-tech neon border
		depth_gauge.draw_rect(tag_rect, badge_border, false, 1.5)
		# Connector notch from badge to the rail bead
		depth_gauge.draw_line(
			Vector2(tag_x + tag_w, cur_y),
			Vector2(x_axis - 3.0, cur_y),
			badge_border,
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
			Color(0.95, 0.98, 1.0, depth_tag_alpha)
		)


static func scrub_to_position(pos_y: float, depth_gauge: Control, scroll_container: ScrollContainer) -> void:
	var h := depth_gauge.size.y
	if h <= 40.0:
		return
	var ratio := clampf((pos_y - 20.0) / (h - 40.0), 0.0, 1.0)
	var vbar := scroll_container.get_v_scroll_bar()
	var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
	var max_scroll := maxf(1.0, vbar.max_value - page)
	scroll_container.scroll_vertical = int(round(ratio * max_scroll))
	depth_gauge.queue_redraw()
