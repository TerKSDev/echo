class_name LevelPathRenderer
extends RefCounted
## Procedural Bezier Conduit & Animated Sonar Pulse Renderer for Level Select.
## Connects cavern sectors with biome-specific conduit paths and energy surges.

static func get_connection_spec(lvl: int, is_left: bool = true) -> Dictionary:
	# Consistent, regular conduit topology:
	# - Left card exits right edge at center (0.50) -> connects to the bottom of the right card.
	# - Right card exits left edge at center (0.50) -> connects to the bottom of the left card.
	# - The entry point on the bottom edge has slight deterministic jitter (+/- 0.08) so it feels organic
	var seed_val := float((lvl * 9301 + 49297) % 233280) / 233280.0
	var jitter := (seed_val - 0.5) * 0.16 # Range [-0.08, +0.08]

	if is_left:
		return {
			"a_exit": "right",
			"a_frac": 0.50,
			"b_entry": "bottom",
			"b_frac": clampf(0.38 + jitter, 0.28, 0.48)
		}
	else:
		return {
			"a_exit": "left",
			"a_frac": 0.50,
			"b_entry": "bottom",
			"b_frac": clampf(0.62 + jitter, 0.52, 0.72)
		}


static func get_dock_point(btn: Button, side: String, frac: float) -> Vector2:
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


static func eval_curved_path_point(pts: PackedVector2Array, t: float) -> Vector2:
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


static func draw_level_path(
	canvas: Control,
	level_buttons: Dictionary,
	total_levels: int,
	highest: int,
	time: float
) -> void:
	for lvl in range(1, total_levels):
		var btn_a: Button = level_buttons.get(lvl)
		var btn_b: Button = level_buttons.get(lvl + 1)
		if btn_a == null or btn_b == null:
			continue
		if not is_instance_valid(btn_a) or not is_instance_valid(btn_b):
			continue

		var is_unlocked_path := (lvl + 1) <= highest
		var is_discovery_path := (lvl == highest)

		# Keep distant locked sectors uncluttered and dark
		if not is_unlocked_path and not is_discovery_path:
			continue

		var is_left := btn_a.position.x < btn_b.position.x
		var spec := get_connection_spec(lvl, is_left)
		var a_exit: String = spec["a_exit"]
		var a_frac: float = spec["a_frac"]
		var b_entry: String = spec["b_entry"]
		var b_frac: float = spec["b_frac"]

		var going_down := btn_b.position.y > btn_a.position.y
		if going_down:
			if a_exit == "top": a_exit = "bottom"
			elif a_exit == "bottom": a_exit = "top"
			if b_entry == "bottom": b_entry = "top"
			elif b_entry == "top": b_entry = "bottom"

		# Multi-edge docking points
		var start_pt := get_dock_point(btn_a, a_exit, a_frac)
		var end_pt := get_dock_point(btn_b, b_entry, b_frac)

		var dx := end_pt.x - start_pt.x
		var dy := absf(start_pt.y - end_pt.y)
		var dir_y := 1.0 if end_pt.y >= start_pt.y else -1.0

		# Perpendicular tangent control handles matching dock geometry
		var cp1: Vector2
		match a_exit:
			"top", "bottom":
				cp1 = start_pt + Vector2(dx * 0.12, dir_y * dy * 0.50)
			"right":
				# Exits rightward horizontally into the chasm
				cp1 = start_pt + Vector2(absf(dx) * 0.45, dir_y * dy * 0.08)
			"left":
				# Exits leftward horizontally into the chasm
				cp1 = start_pt + Vector2(-absf(dx) * 0.45, dir_y * dy * 0.08)
			_:
				cp1 = start_pt + Vector2(dx * 0.20, dir_y * dy * 0.50)

		var cp2: Vector2
		match b_entry:
			"bottom", "top":
				cp2 = end_pt + Vector2(-dx * 0.10, -dir_y * dy * 0.50)
			"left":
				# Enters from the left horizontally into the card
				cp2 = end_pt + Vector2(-absf(dx) * 0.45, -dir_y * dy * 0.08)
			"right":
				# Enters from the right horizontally into the card
				cp2 = end_pt + Vector2(absf(dx) * 0.45, -dir_y * dy * 0.08)
			_:
				cp2 = end_pt + Vector2(-dx * 0.20, -dir_y * dy * 0.50)

		# Sample smooth Bezier points
		var segments := 28
		var pts: PackedVector2Array = []
		pts.resize(segments + 1)
		for s in range(segments + 1):
			var t := float(s) / float(segments)
			pts[s] = start_pt.bezier_interpolate(cp1, cp2, end_pt, t)

		var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE
		# Connection terminal nodes on card edges
		var node_col := (Color(1.0, 0.45, 0.85, 0.95) if is_challenge else Color(0.35, 0.88, 1.0, 0.95)) if is_unlocked_path else (Color(0.55, 0.25, 0.50, 0.55) if is_challenge else Color(0.28, 0.55, 0.75, 0.55))
		canvas.draw_circle(start_pt, 3.2, node_col)
		canvas.draw_circle(start_pt, 6.0, Color(node_col.r, node_col.g, node_col.b, 0.25))
		canvas.draw_circle(end_pt, 3.2, node_col)
		canvas.draw_circle(end_pt, 6.0, Color(node_col.r, node_col.g, node_col.b, 0.25))

		if is_unlocked_path:
			# Solid Line with bioluminescent glow for cleared/unlocked sectors
			var glow_col := Color(0.65, 0.12, 0.45, 0.35) if is_challenge else Color(0.12, 0.45, 0.75, 0.30)
			var core_col := Color(1.0, 0.55, 0.88, 0.95) if is_challenge else Color(0.35, 0.90, 1.0, 0.95)
			canvas.draw_polyline(pts, glow_col, 5.5)
			canvas.draw_polyline(pts, core_col, 2.4)

			# Traveling sonar acoustic pulse along the curve
			var pulse_t := fmod(time * 0.55 + float(lvl) * 0.35, 1.0)
			var pulse_pt := eval_curved_path_point(pts, pulse_t)
			canvas.draw_circle(pulse_pt, 4.0, Color(1.0, 0.95, 0.98, 0.98) if is_challenge else Color(0.90, 0.98, 1.0, 0.98))
			canvas.draw_circle(pulse_pt, 8.5, Color(0.85, 0.25, 0.65, 0.45) if is_challenge else Color(0.25, 0.75, 1.0, 0.35))
		elif is_discovery_path:
			# Subtle dashed discovery trail leading into the next locked sector
			var pulse_a := 0.35 + 0.3 * sin(time * 3.0)
			var col := Color(0.95, 0.45, 0.85, pulse_a) if is_challenge else Color(0.35, 0.75, 1.0, pulse_a)
			for p in range(pts.size() - 1):
				if p % 2 == 0:
					canvas.draw_line(pts[p], pts[p + 1], col, 1.8)
