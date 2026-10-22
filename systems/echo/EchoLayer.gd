extends Node2D

const RAY_COUNT := 160
const LIFETIME := 2.0
const WAVE_SPEED := 400.0
const MARK_HALF_LENGTH := 14.0
const MARK_WIDTH := 2.4
const MAX_POINTS := 550
const MAX_BOUNCES := 2
const BOUNCE_ATTENUATION := 0.58
const MIN_BOUNCE_REMAINING := 20.0
const WATER_COLOR := Color(0.35, 0.68, 1.0)
const SWITCH_COLOR := Color(1.0, 0.72, 0.18)
const DOOR_COLOR := Color(1.0, 0.85, 0.22)

var points: Array = []
var waves: Array = []
var marks: Array = []
var _was_active := false


func clear_all() -> void:
	points.clear()
	waves.clear()
	marks.clear()
	queue_redraw()

func emit_echo(origin: Vector2, radius: float, exclude: Array = [], show_wave: bool = true, wave_color: Color = Color(0.3, 1.0, 1.0)) -> void:
	if show_wave:
		waves.append({
			"pos": origin,
			"max_radius": radius,
			"age": 0.0,
			"col": wave_color
		})
	
	var space := get_world_2d().direct_space_state
	var exclude_rids: Array[RID] = []
	for item in exclude:
		if item is RID:
			exclude_rids.append(item)

	# Always exclude the player body (layer 1) so enemy waves don't spawn wall dots on the player
	var player = get_tree().get_first_node_in_group("player")
	if player is CollisionObject2D:
		var p_rid: RID = player.get_rid()
		if not exclude_rids.has(p_rid):
			exclude_rids.append(p_rid)

	# Exclude mobile/stationary enemy bodies from wall-dot raycasts so moving monsters don't leave floating wall dots behind
	var wall_exclude_rids: Array[RID] = exclude_rids.duplicate()
	for enemy_obj in get_tree().get_nodes_in_group("enemy"):
		if enemy_obj is CollisionObject2D and is_instance_valid(enemy_obj):
			var e_rid: RID = enemy_obj.get_rid()
			if not wall_exclude_rids.has(e_rid):
				wall_exclude_rids.append(e_rid)

	# Dynamic rays & bounce count by sound loudness to keep physics & drawing silky smooth
	var is_small_sound: bool = radius < 220.0
	var ray_count: int = 90 if is_small_sound else RAY_COUNT
	var max_allowed_bounces: int = 0 if is_small_sound else (MAX_BOUNCES if radius > 360.0 else 1)
	var last_primary_hit := Vector2(-99999.0, -99999.0)
	var last_bounce_hit := Vector2(-99999.0, -99999.0)
	for i in ray_count:
		var cur_origin: Vector2 = origin
		var cur_dir: Vector2 = Vector2.RIGHT.rotated(TAU * i / ray_count)
		var remaining_dist: float = radius
		var cum_dist: float = 0.0
		var cur_energy: float = 1.0

		for bounce in range(max_allowed_bounces + 1):
			if remaining_dist < MIN_BOUNCE_REMAINING or cur_energy < 0.12:
				break

			var query := PhysicsRayQueryParameters2D.create(cur_origin, cur_origin + cur_dir * remaining_dist)
			query.collision_mask = 1
			query.exclude = wall_exclude_rids

			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				break

			var hit_pos: Vector2 = hit.position
			var seg_len: float = cur_origin.distance_to(hit_pos)
			if seg_len < 1.0:
				break

			cum_dist += seg_len
			remaining_dist -= seg_len

			var normal: Vector2 = hit.get("normal", Vector2.ZERO)
			var tan_vec: Vector2 = normal.orthogonal().normalized() if normal != Vector2.ZERO else cur_dir.orthogonal().normalized()
			var d_ratio: float = clampf(cum_dist / radius, 0.0, 1.0)
			var dist_factor: float = clampf(1.0 - d_ratio * d_ratio, 0.08, 1.0)
			var hit_strength: float = cur_energy * dist_factor

			var should_record := true
			if bounce == 0:
				if hit_pos.distance_squared_to(last_primary_hit) < 22.0:
					should_record = false
				else:
					last_primary_hit = hit_pos
			else:
				if hit_pos.distance_squared_to(last_bounce_hit) < 26.0:
					should_record = false
				else:
					last_bounce_hit = hit_pos

			if should_record:
				var pt_col: Color = wave_color
				var col_obj: Object = hit.get("collider")
				if col_obj != null and col_obj.has_meta("echo_color"):
					pt_col = col_obj.get_meta("echo_color")
				points.append({
					"pos": hit_pos,
					"tan": tan_vec,
					"norm": normal,
					"age": -cum_dist / WAVE_SPEED,
					"strength": hit_strength,
					"col": pt_col,
					"bounce": bounce
				})

			if normal == Vector2.ZERO:
				break

			# Specular reflection: d_bounce = d - 2(d . n)n
			cur_dir = cur_dir.bounce(normal).normalized()
			cur_origin = hit_pos + normal * 0.75
			cur_energy *= BOUNCE_ATTENUATION

	if points.size() > MAX_POINTS:
		points = points.slice(points.size() - MAX_POINTS)

	_reveal_features(space, origin, radius, wall_exclude_rids)

	for enemy in get_tree().get_nodes_in_group("enemy"):
		var enemy_node := enemy as Node2D
		if enemy_node == null:
			continue
		var dist: float = origin.distance_to(enemy_node.global_position)
		if dist <= radius:
			# Direct line of sight check
			var occ_query := PhysicsRayQueryParameters2D.create(origin, enemy_node.global_position)
			occ_query.collision_mask = 1
			occ_query.exclude = exclude_rids
			var hit: Dictionary = space.intersect_ray(occ_query)

			var is_revealed := false
			var reveal_delay: float = dist / WAVE_SPEED
			var reveal_strength: float = 1.0

			if hit.is_empty():
				is_revealed = true
			elif radius >= 280.0:
				# Physical 1-bounce acoustic reflection around corners for loud sounds (voice/shrieks)
				var wall_pt: Vector2 = hit["position"]
				var wall_n: Vector2 = hit.get("normal", Vector2.ZERO)
				if wall_n != Vector2.ZERO:
					var bounce_start: Vector2 = wall_pt + wall_n * 1.5
					var bounce_query := PhysicsRayQueryParameters2D.create(bounce_start, enemy_node.global_position)
					bounce_query.collision_mask = 1
					bounce_query.exclude = exclude_rids
					var bounce_hit: Dictionary = space.intersect_ray(bounce_query)
					if bounce_hit.is_empty():
						var total_path: float = origin.distance_to(wall_pt) + wall_pt.distance_to(enemy_node.global_position)
						if total_path <= radius:
							is_revealed = true
							reveal_delay = total_path / WAVE_SPEED
							reveal_strength = 0.65

			if is_revealed:
				get_tree().create_timer(reveal_delay).timeout.connect(
					func():
						if is_instance_valid(enemy_node):
							enemy_node.reveal(reveal_strength)
				)

# Reveal interactive map features (water, switches, doors, exit) when swept by a sound wave
func _reveal_features(space: PhysicsDirectSpaceState2D, origin: Vector2, max_dist: float, exclude: Array[RID]) -> void:
	var main_node := get_parent()
	if main_node == null or not main_node.has_method("echo_features"):
		return
	for f in main_node.echo_features():
		var f_pos: Vector2 = Vector2(f["pos"])
		var d: float = origin.distance_to(f_pos)
		if d > max_dist:
			continue
		var q := PhysicsRayQueryParameters2D.create(origin, f_pos, 1, exclude)
		var hit: Dictionary = space.intersect_ray(q)
		var ok: bool = hit.is_empty()
		if not ok and f.has("body"):
			ok = hit.get("collider") == f["body"]
		if not ok:
			ok = Vector2(hit["position"]).distance_to(f_pos) < 14.0

		var path_len := d
		var s_mult := 1.0
		if not ok and max_dist >= 280.0 and not hit.is_empty():
			# 1-bounce acoustic sweep around corner
			var wall_pt: Vector2 = hit["position"]
			var wall_n: Vector2 = hit.get("normal", Vector2.ZERO)
			if wall_n != Vector2.ZERO:
				var b_query := PhysicsRayQueryParameters2D.create(wall_pt + wall_n * 1.5, f_pos, 1, exclude)
				var b_hit: Dictionary = space.intersect_ray(b_query)
				if b_hit.is_empty() or (f.has("body") and b_hit.get("collider") == f["body"]):
					var total_path: float = origin.distance_to(wall_pt) + wall_pt.distance_to(f_pos)
					if total_path <= max_dist:
						ok = true
						path_len = total_path
						s_mult = 0.65

		if ok:
			var f_type: String = String(f["type"])
			var s: float = (1.0 if f_type == "exit" else clampf(1.0 - path_len / max_dist, 0.38, 1.0)) * s_mult
			marks.append({
				"type": f_type,
				"pos": f_pos,
				"age": -path_len / WAVE_SPEED,
				"strength": s,
				"pressed": bool(f.get("pressed", false))
			})


# Update the age of each point and remove old points
func _process(delta):
	var is_active: bool = not points.is_empty() or not waves.is_empty() or not marks.is_empty()
	if not is_active:
		if _was_active:
			_was_active = false
			queue_redraw()
		return
	_was_active = true

	for p in points:
		p["age"] += delta
	points = points.filter(func(p): return p["age"] < LIFETIME)

	for m in marks:
		m["age"] += delta
	marks = marks.filter(func(m): return m["age"] < LIFETIME * 1.35)

	for w in waves:
		w["age"] += delta
	waves = waves.filter(func(w): return w["age"] * WAVE_SPEED < w["max_radius"])
	
	queue_redraw()

# Draw the points with arrival shimmer and fading alpha based on their age
func _draw():
	var cam := get_viewport().get_camera_2d()
	var cull_rect := Rect2()
	var has_cull := false
	if cam != null:
		var cam_pos: Vector2 = cam.global_position
		var vp_size: Vector2 = get_viewport_rect().size / cam.zoom
		cull_rect = Rect2(cam_pos - vp_size * 0.58, vp_size * 1.16)
		has_cull = true

	for p in points:
		var pos_v := Vector2(p["pos"])
		if has_cull and not cull_rect.has_point(pos_v):
			continue
		var age: float = float(p["age"])
		if age < 0.0:
			continue
		var strength: float = float(p.get("strength", 1.0))
		var t_norm: float = clampf(age / LIFETIME, 0.0, 1.0)
		var decay: float = (exp(-t_norm * 2.5) - exp(-2.5)) / (1.0 - exp(-2.5))
		var alpha: float = clampf(decay, 0.0, 1.0) * strength
		var base_col: Color = p.get("col", Color(0.3, 1.0, 1.0))
		var lp: Vector2 = to_local(Vector2(p["pos"]))
		var tan_vec: Vector2 = p.get("tan", Vector2.UP)
		var norm_vec: Vector2 = p.get("norm", Vector2.ZERO)
		var half_len: float = MARK_HALF_LENGTH * clampf(0.7 + 0.3 * strength, 0.6, 1.0)
		var p1: Vector2 = lp - tan_vec * half_len
		var p2: Vector2 = lp + tan_vec * half_len

		# Crisp impact flash when the sound wave first strikes the wall
		var impact: float = clampf(1.0 - age / 0.18, 0.0, 1.0) * strength

		# 1. Directional light wash facing the sound source (zero-allocation hardware-batched strokes)
		if norm_vec != Vector2.ZERO:
			# Outer soft ambient light wash facing the player
			draw_line(p1 + norm_vec * 5.0, p2 + norm_vec * 5.0, Color(base_col.r, base_col.g, base_col.b, alpha * 0.16), 8.0)
			# Mid vibrant illuminated glow
			draw_line(p1 + norm_vec * 2.2, p2 + norm_vec * 2.2, Color(base_col.r * 0.85 + 0.15, base_col.g * 0.95 + 0.05, base_col.b, alpha * 0.38), 4.5)
			# Solid wall depth (subtle dark backing into wall along -norm_vec)
			draw_line(p1 - norm_vec * 2.0, p2 - norm_vec * 2.0, Color(base_col.r * 0.4, base_col.g * 0.5, base_col.b * 0.65, alpha * 0.22), 3.5)

		# 2. Razor-sharp physical surface contact line (bright illuminated barrier core)
		var line_col: Color = base_col.lerp(Color.WHITE, 0.35 + impact * 0.65)
		if impact > 0.05:
			draw_line(p1, p2, Color(1.0, 1.0, 1.0, alpha * impact * 0.6), MARK_WIDTH + 1.8)
		draw_line(p1, p2, Color(line_col.r, line_col.g, line_col.b, alpha), MARK_WIDTH + impact * 0.4)

	for w in waves:
		var radius: float = float(w["age"]) * WAVE_SPEED
		var w_pos := Vector2(w["pos"])
		if has_cull and not cull_rect.grow(radius).has_point(w_pos):
			continue
		var fade: float = clampf(1.0 - radius / float(w["max_radius"]), 0.0, 1.0)
		var w_col: Color = w.get("col", Color(0.3, 1.0, 1.0))
		var lw: Vector2 = to_local(w_pos)
		draw_arc(lw, radius, 0.0, TAU, 48, Color(w_col.r, w_col.g, w_col.b, fade * 0.9), 2.2)
		if radius > 8.0:
			draw_arc(lw, radius - 5.0, 0.0, TAU, 48, Color(w_col.r, w_col.g, w_col.b, fade * 0.25), 4.0)

	for m in marks:
		var m_pos := Vector2(m["pos"])
		if has_cull and not cull_rect.has_point(m_pos):
			continue
		var m_age: float = float(m["age"])
		if m_age < 0.0:
			continue
		var mt_norm: float = clampf(m_age / (LIFETIME * 1.35), 0.0, 1.0)
		var m_decay: float = (exp(-mt_norm * 2.2) - exp(-2.2)) / (1.0 - exp(-2.2))
		var a: float = float(m["strength"]) * clampf(m_decay, 0.0, 1.0)
		_draw_mark(m, a)


func _draw_mark(m: Dictionary, a: float) -> void:
	var p: Vector2 = to_local(Vector2(m["pos"]))
	var m_type: String = String(m["type"])
	match m_type:
		"water":
			var c := Color(WATER_COLOR.r, WATER_COLOR.g, WATER_COLOR.b, a * 0.9)
			for oy: float in [-6.0, 0.0, 6.0]:
				var pts := PackedVector2Array()
				for i in range(0, 25, 3):
					var x: float = float(i) - 12.0
					pts.append(p + Vector2(x, oy + sin(x * 0.5 + oy) * 2.0))
				draw_polyline(pts, c, 1.5)
		"switch":
			var is_pressed: bool = bool(m.get("pressed", false))
			var c := Color(SWITCH_COLOR.r, SWITCH_COLOR.g, SWITCH_COLOR.b, a * (0.45 if is_pressed else 1.0))
			draw_arc(p, 8.0, 0.0, TAU, 20, c, 2.0)
			if not is_pressed:
				draw_circle(p, 3.5, c)
		"door":
			var c := Color(DOOR_COLOR.r, DOOR_COLOR.g, DOOR_COLOR.b, a)
			draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), c, false, 2.0)
			draw_line(p - Vector2(15, 15), p + Vector2(15, 15), c, 1.0)
			draw_line(p + Vector2(-15, 15), p + Vector2(15, -15), c, 1.0)
		"exit":
			var c := Color(0.55, 1.0, 0.92, a)
			draw_rect(Rect2(p - Vector2(16, 16), Vector2(32, 32)), c, false, 3.0)
			draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(0.55, 1.0, 0.92, a * 0.5), false, 1.5)
