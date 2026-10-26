class_name Icons
extends RefCounted
## Centralized Procedural Vector Icons Renderer for ECHO.
## Draws high-DPI resolution-independent vector icons using Godot CanvasItem draw calls.

static func draw_trophy(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var gold := Color(1.0, 0.82, 0.28, 0.98)
	var gold_shadow := Color(0.85, 0.62, 0.15, 0.95)
	var cup_fill := Color(0.35, 0.22, 0.05, 0.95)

	# Cup body (trapezoid cup)
	var cup_pts := PackedVector2Array([
		Vector2(c.x - 7.0, c.y - 7.5),
		Vector2(c.x + 7.0, c.y - 7.5),
		Vector2(c.x + 5.0, c.y + 0.5),
		Vector2(c.x - 5.0, c.y + 0.5)
	])
	canvas.draw_colored_polygon(cup_pts, cup_fill)
	var cup_closed := cup_pts.duplicate()
	cup_closed.append(cup_pts[0])
	canvas.draw_polyline(cup_closed, gold, 1.6)

	# Handles (Left and Right loops)
	canvas.draw_arc(Vector2(c.x - 7.0, c.y - 3.5), 3.2, -PI * 0.5, PI * 0.5, 12, gold, 1.4)
	canvas.draw_arc(Vector2(c.x + 7.0, c.y - 3.5), 3.2, PI * 0.5, PI * 1.5, 12, gold, 1.4)

	# Stem
	canvas.draw_line(Vector2(c.x, c.y + 0.5), Vector2(c.x, c.y + 5.0), gold, 2.0)

	# Base / Pedestal
	var base_pts := PackedVector2Array([
		Vector2(c.x - 5.5, c.y + 5.0),
		Vector2(c.x + 5.5, c.y + 5.0),
		Vector2(c.x + 7.0, c.y + 8.5),
		Vector2(c.x - 7.0, c.y + 8.5)
	])
	canvas.draw_colored_polygon(base_pts, gold_shadow)
	var base_closed := base_pts.duplicate()
	base_closed.append(base_pts[0])
	canvas.draw_polyline(base_closed, gold, 1.4)

	# Little star or badge in cup center
	canvas.draw_circle(Vector2(c.x, c.y - 3.5), 1.8, Color(1.0, 0.95, 0.6, 1.0))


static func draw_gear(canvas: Control) -> void:
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


static func draw_book(canvas: Control) -> void:
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


static func draw_beacon(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var col := Color(0.35, 0.95, 1.0)
	canvas.draw_circle(c, 3.2, col)
	canvas.draw_arc(c, 5.8, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.6), 1.8)


static func draw_check(canvas: Control) -> void:
	var col := Color(0.35, 0.95, 0.65)
	var cy := canvas.size.y * 0.5
	var p1 := Vector2(1.5, cy + 0.8)
	var p2 := Vector2(4.8, cy + 4.8)
	var p3 := Vector2(12.0, cy - 3.2)
	canvas.draw_line(p1, p2, col, 2.2)
	canvas.draw_line(p2, p3, col, 2.2)


static func draw_lock(canvas: Control) -> void:
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


static func draw_back_arrow(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var is_hovered: bool = false
	if canvas is BaseButton:
		var btn := canvas as BaseButton
		is_hovered = btn.is_hovered() or btn.button_pressed
	var col := Color(0.92, 0.98, 1.0, 1.0) if is_hovered else Color(0.68, 0.86, 1.0, 0.90)
	if is_hovered:
		canvas.draw_circle(c, 16.0, Color(0.20, 0.65, 1.0, 0.16))
	var tip := Vector2(c.x - 8.0, c.y)
	var wing_top := Vector2(c.x - 1.0, c.y - 7.0)
	var wing_bot := Vector2(c.x - 1.0, c.y + 7.0)
	var stem_end := Vector2(c.x + 8.0, c.y)
	canvas.draw_line(wing_top, tip, col, 2.4, true)
	canvas.draw_line(wing_bot, tip, col, 2.4, true)
	canvas.draw_line(tip, stem_end, col, 2.4, true)


static func draw_headphone(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var col := Color(0.35, 0.88, 1.0, 0.95)
	# Arch headband
	canvas.draw_arc(c + Vector2(0, -3), 14.0, PI * 0.85, PI * 2.15, 24, col, 2.4)
	# Left ear cup
	canvas.draw_rect(Rect2(c.x - 17, c.y - 5, 5, 12), col, true)
	# Right ear cup
	canvas.draw_rect(Rect2(c.x + 12, c.y - 5, 5, 12), col, true)


static func draw_pebble(canvas: CanvasItem, center: Vector2, col: Color, is_empty: bool) -> void:
	# Scaled stone skip arc
	canvas.draw_arc(center + Vector2(0, 7), 16.0, -PI * 0.85, -PI * 0.15, 16, Color(col, 0.45), 1.4)
	var stone_pos := center + Vector2(1.5, -3.0)
	canvas.draw_circle(stone_pos, 6.2, col)
	canvas.draw_circle(stone_pos + Vector2(-1.8, -1.8), 2.2, Color.WHITE if not is_empty else Color(col, 0.5))
	canvas.draw_circle(center + Vector2(-11.0, 4.5), 2.5, Color(col, 0.7))
	canvas.draw_circle(center + Vector2(12.0, 6.0), 1.8, Color(col, 0.5))


static func draw_stealth(canvas: CanvasItem, center: Vector2, col: Color) -> void:
	# Stylized Sound Dampener: 3 curved horizontal stealth ripples with a center mute bar
	# Top arc
	canvas.draw_arc(center + Vector2(0, -9), 10.0, PI * 0.2, PI * 0.8, 12, Color(col, 0.5), 1.6)
	# Middle arc
	canvas.draw_arc(center, 15.0, PI * 0.15, PI * 0.85, 16, col, 2.0)
	# Center silent footstep core
	canvas.draw_circle(center + Vector2(0, 4), 3.5, col)
	canvas.draw_arc(center + Vector2(0, 4), 8.0, -PI * 0.8, -PI * 0.2, 12, col, 1.8)


# --------------------------------------------------
# ALIASES WITH _ICON SUFFIX
# --------------------------------------------------

static func draw_trophy_icon(canvas: Control) -> void:
	draw_trophy(canvas)


static func draw_gear_icon(canvas: Control) -> void:
	draw_gear(canvas)


static func draw_book_icon(canvas: Control) -> void:
	draw_book(canvas)


static func draw_beacon_icon(canvas: Control) -> void:
	draw_beacon(canvas)


static func draw_check_icon(canvas: Control) -> void:
	draw_check(canvas)


static func draw_lock_icon(canvas: Control) -> void:
	draw_lock(canvas)


static func draw_back_arrow_icon(canvas: Control) -> void:
	draw_back_arrow(canvas)


static func draw_headphone_icon(canvas: Control) -> void:
	draw_headphone(canvas)
