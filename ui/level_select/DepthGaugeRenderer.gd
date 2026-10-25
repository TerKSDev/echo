class_name DepthGaugeRenderer
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
		{"label": "-1,300M", "ratio": 0.5},
		{"label": "-2,680M", "ratio": 1.0},
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
			10,
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
	if depth_tag_alpha > 0.01:
		var cur_y := lerpf(20.0, h - 20.0, scroll_ratio)
		var cur_meters := int(round(lerpf(-40.0, -2680.0, scroll_ratio)))
		var depth_str := format_depth_meters(cur_meters)

		# Bright live indicator tick & glowing bead on axis
		depth_gauge.draw_line(
			Vector2(x_axis - 7.0, cur_y),
			Vector2(x_axis + 4.0, cur_y),
			Color(0.35, 0.95, 1.0, 0.95 * depth_tag_alpha),
			2.2
		)
		depth_gauge.draw_circle(Vector2(x_axis, cur_y), 3.5, Color(0.75, 0.98, 1.0, depth_tag_alpha))

		# Clean, enlarged live readout tag
		var tag_w := 78.0
		var tag_h := 28.0
		var tag_x := x_axis - tag_w - 8.0
		var tag_y := clampf(cur_y - tag_h * 0.5, 6.0, h - tag_h - 6.0)
		var tag_rect := Rect2(tag_x, tag_y, tag_w, tag_h)

		# Glowing shadow behind badge
		depth_gauge.draw_rect(Rect2(tag_x - 3, tag_y - 3, tag_w + 6, tag_h + 6), Color(0.08, 0.45, 0.85, 0.3 * depth_tag_alpha), true)
		# Deep semi-translucent dark badge background
		depth_gauge.draw_rect(tag_rect, Color(0.02, 0.08, 0.16, 0.95 * depth_tag_alpha), true)
		# High-tech neon cyan border
		depth_gauge.draw_rect(tag_rect, Color(0.35, 0.9, 1.0, 0.95 * depth_tag_alpha), false, 1.5)
		# Connector notch from badge to the rail bead
		depth_gauge.draw_line(
			Vector2(tag_x + tag_w, cur_y),
			Vector2(x_axis - 3.0, cur_y),
			Color(0.35, 0.9, 1.0, 0.85 * depth_tag_alpha),
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
	var max_scroll := maxf(0.0, vbar.max_value - scroll_container.size.y)
	scroll_container.scroll_vertical = int(ratio * max_scroll)
	depth_gauge.queue_redraw()
