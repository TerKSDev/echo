extends Node2D

const RAY_COUNT := 144
const LIFETIME := 2.4
const WAVE_SPEED := 400.0
const MARK_HALF_LENGTH := 5.5
const MARK_WIDTH := 2.0
const MAX_POINTS := 520
const MAX_MARKS := 120
const MAX_BOUNCES := 2
const BOUNCE_ATTENUATION := 0.58
const MIN_BOUNCE_REMAINING := 20.0
const WATER_COLOR := Color(0.35, 0.68, 1.0)
const SWITCH_COLOR := Color(1.0, 0.72, 0.18)
const DOOR_COLOR := Color(1.0, 0.85, 0.22)
const MAX_MOTE_PARTICLES := 180
const SHOW_STATIC_ICONS := false  # false = icons only appear when an echo sweeps them
const ICON_KEY: Texture2D = preload("res://assets/icons/key.svg")
const ICON_DOOR_CLOSED: Texture2D = preload("res://assets/icons/door-closed.svg")
const ICON_DOOR_OPEN: Texture2D = preload("res://assets/icons/door-open.svg")

var points: Array = []
var waves: Array = []
var marks: Array = []
var motes: Array = []
var _was_active := false


func clear_all() -> void:
	points.clear()
	waves.clear()
	marks.clear()
	motes.clear()
	queue_redraw()

func emit_echo(origin: Vector2, radius: float, exclude: Array = [], show_wave: bool = true, wave_color: Color = Color(0.3, 1.0, 1.0)) -> void:
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
	var ray_count: int = 84 if is_small_sound else RAY_COUNT
	var max_allowed_bounces: int = 0 if is_small_sound else (MAX_BOUNCES if radius > 360.0 else 1)
	var wave_clip_dists := PackedFloat32Array()
	wave_clip_dists.resize(ray_count)
	var last_primary_hit := Vector2(-99999.0, -99999.0)
	var last_bounce_hit := Vector2(-99999.0, -99999.0)
	for i in ray_count:
		var cur_origin: Vector2 = origin
		var cur_dir: Vector2 = Vector2.RIGHT.rotated(TAU * i / ray_count)
		var remaining_dist: float = radius
		var cum_dist: float = 0.0
		var cur_energy: float = 1.0
		wave_clip_dists[i] = radius

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

			if bounce == 0:
				wave_clip_dists[i] = seg_len

			cum_dist += seg_len
			remaining_dist -= seg_len

			var normal: Vector2 = hit.get("normal", Vector2.ZERO)
			var tan_vec: Vector2 = normal.orthogonal().normalized() if normal != Vector2.ZERO else cur_dir.orthogonal().normalized()
			var d_ratio: float = clampf(cum_dist / radius, 0.0, 1.0)
			var dist_factor: float = clampf(1.0 - d_ratio * d_ratio, 0.08, 1.0)
			var hit_strength: float = cur_energy * dist_factor

			var should_record := true
			if bounce == 0:
				if hit_pos.distance_squared_to(last_primary_hit) < 36.0:
					should_record = false
				else:
					last_primary_hit = hit_pos
			else:
				if hit_pos.distance_squared_to(last_bounce_hit) < 42.0:
					should_record = false
				else:
					last_bounce_hit = hit_pos

			if should_record:
				var pt_col: Color = wave_color
				var col_obj: Object = hit.get("collider")
				if col_obj != null and col_obj.has_meta("echo_color"):
					pt_col = col_obj.get_meta("echo_color")
				elif bounce > 0:
					pt_col = wave_color.lerp(Color(0.18, 0.62, 0.98), 0.42)
				var arc_spacing: float = clampf(cum_dist * TAU / float(ray_count) * 0.58, 3.0, 6.8)
				var rock_angle_jitter: float = randf_range(-0.16, 0.16)
				var rock_tan: Vector2 = tan_vec.rotated(rock_angle_jitter)
				points.append({
					"pos": hit_pos,
					"tan": rock_tan,
					"norm": normal,
					"hlen": arc_spacing * randf_range(0.85, 1.15),
					"age": -cum_dist / WAVE_SPEED,
					"strength": hit_strength,
					"col": pt_col,
					"bounce": bounce,
					"crag": randf() # Natural rock fissure variation
				})

			if normal == Vector2.ZERO:
				break

			# Specular reflection: d_bounce = d - 2(d . n)n
			cur_dir = cur_dir.bounce(normal).normalized()
			cur_origin = hit_pos + normal * 0.75
			cur_energy *= BOUNCE_ATTENUATION

	if show_wave:
		waves.append({
			"pos": origin,
			"max_radius": radius,
			"age": 0.0,
			"col": wave_color,
			"clip": wave_clip_dists
		})

		# Spawn airborne cavern dust motes and moisture droplets along unblocked sound paths
		var mote_count := int(clampf(radius * 0.08, 6.0, 32.0))
		for _m in mote_count:
			var rand_angle := randf() * TAU
			var ray_idx: int = clampi(int(rand_angle / TAU * float(ray_count)), 0, ray_count - 1)
			var max_unblocked: float = wave_clip_dists[ray_idx]
			if max_unblocked > 20.0:
				var dist_along := randf_range(16.0, max_unblocked * 0.95)
				var mote_pos := origin + Vector2.from_angle(rand_angle) * dist_along
				motes.append({
					"pos": mote_pos,
					"vel": Vector2.from_angle(rand_angle) * randf_range(6.0, 22.0) + Vector2(randf_range(-4.0, 4.0), randf_range(-12.0, -3.0)),
					"age": -dist_along / WAVE_SPEED, # awakens right when the sound wave sweeps through
					"life": randf_range(0.9, 1.8),
					"size": randf_range(1.0, 2.2),
					"col": wave_color.lerp(Color(0.7, 0.92, 1.0), randf_range(0.2, 0.7))
				})
		if motes.size() > MAX_MOTE_PARTICLES:
			motes = motes.slice(motes.size() - MAX_MOTE_PARTICLES)

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
			var new_age: float = -path_len / WAVE_SPEED
			var is_pressed: bool = bool(f.get("pressed", false))
			var updated := false
			for existing in marks:
				if Vector2(existing["pos"]).distance_squared_to(f_pos) < 4.0:
					if existing["age"] >= 0.0:
						existing["age"] = minf(existing["age"], 0.08)
					else:
						existing["age"] = minf(existing["age"], new_age)
					existing["strength"] = maxf(float(existing["strength"]), s)
					existing["pressed"] = is_pressed
					existing["open"] = bool(f.get("open", false))
					existing["locked"] = bool(f.get("locked", false))
					existing["color"] = f.get("color", Color.WHITE)
					updated = true
					break
			if not updated:
				marks.append({
					"type": f_type,
					"pos": f_pos,
					"age": new_age,
					"strength": s,
					"pressed": is_pressed,
					"open": bool(f.get("open", false)),
					"locked": bool(f.get("locked", false)),
					"color": f.get("color", Color.WHITE)
				})
	if marks.size() > MAX_MARKS:
		marks = marks.slice(marks.size() - MAX_MARKS)


# Update the age of each point and remove old points
func _process(delta):
	var is_active: bool = not points.is_empty() or not waves.is_empty() or not marks.is_empty() or not motes.is_empty()
	if not is_active:
		if _was_active:
			_was_active = false
			queue_redraw()
		elif SHOW_STATIC_ICONS:
			# Static icons need a redraw when the camera moves or a door opens.
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

	for mt in motes:
		mt["age"] += delta
		if mt["age"] > 0.0:
			mt["pos"] = Vector2(mt["pos"]) + Vector2(mt["vel"]) * delta
			mt["vel"] = Vector2(mt["vel"]).move_toward(Vector2(0.0, -4.0), delta * 12.0)
	motes = motes.filter(func(mt): return mt["age"] < float(mt["life"]))

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

	var glow_boost: float = GameState.sonar_glow_boost

	for p in points:
		var pos_v := Vector2(p["pos"])
		if has_cull and not cull_rect.has_point(pos_v):
			continue
		var age: float = float(p["age"])
		if age < 0.0:
			continue
		var strength: float = float(p.get("strength", 1.0))
		var t_norm: float = clampf(age / LIFETIME, 0.0, 1.0)

		# Primary acoustic strike decay (rapid attenuation over initial ~0.9s)
		var primary_decay: float = (exp(-t_norm * 3.4) - exp(-3.4)) / (1.0 - exp(-3.4))
		var primary_alpha: float = clampf(primary_decay, 0.0, 1.0) * strength

		# Phosphor persistence: faint, soft bioluminescent afterglow lingering up to ~2.4s then dissolving
		var phosphor_factor: float = clampf(1.0 - t_norm, 0.0, 1.0)
		var phosphor_alpha: float = pow(phosphor_factor, 1.9) * 0.19 * glow_boost * strength

		var total_alpha: float = clampf(primary_alpha * glow_boost + phosphor_alpha, 0.0, 1.0)
		if total_alpha <= 0.005:
			continue

		var base_col: Color = p.get("col", Color(0.3, 1.0, 1.0))
		var lp: Vector2 = to_local(pos_v)
		var tan_vec: Vector2 = p.get("tan", Vector2.UP)
		var norm_vec: Vector2 = p.get("norm", Vector2.ZERO)
		var half_len: float = float(p.get("hlen", MARK_HALF_LENGTH))
		var p1: Vector2 = lp - tan_vec * half_len
		var p2: Vector2 = lp + tan_vec * half_len

		# Crisp impact pulse when the wavefront first strikes the wall
		var impact: float = clampf(1.0 - age / 0.24, 0.0, 1.0)

		# 1. Soft inner/outer sonar rim glow + Phosphor halo
		if norm_vec != Vector2.ZERO:
			var rim_a: float = primary_alpha * 0.24 + phosphor_alpha * 0.45
			draw_line(p1 + norm_vec * 1.2, p2 + norm_vec * 1.2, Color(base_col.r, base_col.g, base_col.b, rim_a), 3.8)
			# Subtle rebound ripple line lifting off the wall during initial impact
			if impact > 0.04:
				var reb_dist: float = (1.0 - impact) * 9.0 + 1.5
				var reb_half: float = half_len * (0.55 + 0.35 * impact)
				var rp: Vector2 = lp + norm_vec * reb_dist
				draw_line(rp - tan_vec * reb_half, rp + tan_vec * reb_half, Color(0.75, 0.98, 1.0, total_alpha * impact * 0.52), 1.4)

		# 2. Surface contour line + hot white-cyan contact core on arrival
		var line_col: Color = base_col.lerp(Color.WHITE, 0.20 + impact * 0.75)
		draw_line(p1, p2, Color(line_col.r, line_col.g, line_col.b, total_alpha * 0.95), MARK_WIDTH + impact * 0.8)
		if impact > 0.08:
			draw_circle(lp, 1.6 + impact * 1.2, Color(1.0, 1.0, 1.0, total_alpha * impact * 0.75))

		# Faint phosphor mineral glitter along segment tips during afterglow phase
		if phosphor_alpha > 0.04 and norm_vec != Vector2.ZERO:
			draw_circle(p1, 0.85, Color(base_col.r, base_col.g, base_col.b, phosphor_alpha * 0.9))
			draw_circle(p2, 0.85, Color(base_col.r, base_col.g, base_col.b, phosphor_alpha * 0.9))

		# 3. Natural cavern cliff fracture: tiny rock crevices & mineral speckle
		var crag_val: float = float(p.get("crag", 0.0))
		if crag_val > 0.45 and norm_vec != Vector2.ZERO:
			var crack_len: float = (crag_val - 0.45) * 8.0
			var crack_tip: Vector2 = lp - norm_vec * crack_len + tan_vec * ((crag_val - 0.7) * 6.0)
			draw_line(lp, crack_tip, Color(line_col.r, line_col.g, line_col.b, total_alpha * 0.45), 1.0)

	# 3. Airborne cavern moisture motes and bio-dust awakened in unblocked areas
	for mt in motes:
		var mt_age: float = float(mt["age"])
		if mt_age <= 0.0:
			continue
		var mt_pos := Vector2(mt["pos"])
		if has_cull and not cull_rect.has_point(mt_pos):
			continue
		var life: float = float(mt["life"])
		var progress: float = clampf(mt_age / life, 0.0, 1.0)
		var mote_alpha: float = sin(progress * PI) * 0.75
		var m_lp: Vector2 = to_local(mt_pos)
		var m_sz: float = float(mt["size"])
		var m_col: Color = mt.get("col", Color(0.6, 0.9, 1.0))
		draw_circle(m_lp, m_sz * 1.8, Color(m_col.r, m_col.g, m_col.b, mote_alpha * 0.22))
		draw_circle(m_lp, m_sz, Color(m_col.r, m_col.g, m_col.b, mote_alpha * 0.9))

	for w in waves:
		var radius: float = float(w["age"]) * WAVE_SPEED
		var w_pos := Vector2(w["pos"])
		if has_cull and not cull_rect.grow(radius).has_point(w_pos):
			continue
		var fade: float = clampf(1.0 - radius / float(w["max_radius"]), 0.0, 1.0)
		var w_col: Color = w.get("col", Color(0.3, 1.0, 1.0))
		var lw: Vector2 = to_local(w_pos)
		var clip_arr: PackedFloat32Array = w.get("clip", PackedFloat32Array())
		var n_seg: int = clip_arr.size()
		if n_seg > 0 and radius > 2.0:
			var main_c := Color(w_col.r, w_col.g, w_col.b, fade * 0.85)
			var trail_c := Color(w_col.r, w_col.g, w_col.b, fade * 0.22)
			var draw_trail: bool = radius > 7.0
			var step_ang: float = TAU / float(n_seg)
			for i in n_seg:
				if radius <= clip_arr[i] + 2.0:
					var a0: float = i * step_ang
					var a1: float = (i + 1) * step_ang
					var d0 := Vector2.from_angle(a0)
					var d1 := Vector2.from_angle(a1)
					draw_line(lw + d0 * radius, lw + d1 * radius, main_c, 2.0)
					if draw_trail:
						draw_line(lw + d0 * (radius - 4.5), lw + d1 * (radius - 4.5), trail_c, 3.2)
		else:
			draw_arc(lw, radius, 0.0, TAU, 48, Color(w_col.r, w_col.g, w_col.b, fade * 0.85), 2.0)

	# Always-visible (dim) door / key icons; the echo makes them flash brighter.
	if SHOW_STATIC_ICONS:
		var main_node := get_parent()
		if main_node != null and main_node.has_method("echo_features"):
			for f in main_node.echo_features():
				var f_type: String = String(f["type"])
				if f_type != "door" and f_type != "switch":
					continue
				var f_pos := Vector2(f["pos"])
				if has_cull and not cull_rect.has_point(f_pos):
					continue
				var base: Color = f.get("color", Color.WHITE)
				var lp := to_local(f_pos)
				if f_type == "door":
					var is_open: bool = bool(f.get("open", false))
					var tex: Texture2D = ICON_DOOR_OPEN if is_open else ICON_DOOR_CLOSED
					draw_texture_rect(tex, Rect2(lp - Vector2(16, 16), Vector2(32, 32)), false,
						Color(base.r, base.g, base.b, 0.35 if is_open else 0.6))
				else:
					var used: bool = bool(f.get("pressed", false))
					draw_texture_rect(ICON_KEY, Rect2(lp - Vector2(15, 15), Vector2(30, 30)), false,
						Color(base.r, base.g, base.b, 0.22 if used else 0.6))

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
			var c := Color(WATER_COLOR.r, WATER_COLOR.g, WATER_COLOR.b, a * 0.85)
			draw_line(p + Vector2(-10.0, -5.0), p + Vector2(-3.0, -6.5), c, 1.5)
			draw_line(p + Vector2(-3.0, -6.5), p + Vector2(4.0, -3.5), c, 1.5)
			draw_line(p + Vector2(4.0, -3.5), p + Vector2(10.0, -5.0), c, 1.5)
			draw_line(p + Vector2(-11.0, 0.5), p + Vector2(-4.0, -1.2), c, 1.5)
			draw_line(p + Vector2(-4.0, -1.2), p + Vector2(4.0, 1.8), c, 1.5)
			draw_line(p + Vector2(4.0, 1.8), p + Vector2(11.0, 0.0), c, 1.5)
			draw_line(p + Vector2(-9.0, 6.0), p + Vector2(-2.0, 4.5), c, 1.5)
			draw_line(p + Vector2(-2.0, 4.5), p + Vector2(5.0, 7.2), c, 1.5)
			draw_line(p + Vector2(5.0, 7.2), p + Vector2(9.5, 5.5), c, 1.5)
		"switch":
			# Key icon, tinted with the link colour; dimmed once collected.
			var is_pressed: bool = bool(m.get("pressed", false))
			var base: Color = m.get("color", SWITCH_COLOR)
			var c := Color(base.r, base.g, base.b, a * (0.4 if is_pressed else 1.0))
			draw_texture_rect(ICON_KEY, Rect2(p - Vector2(15, 15), Vector2(30, 30)), false, c)
		"door":
			# Closed-door icon, or the open-door icon once its key has been used.
			var base: Color = m.get("color", DOOR_COLOR)
			var is_open: bool = bool(m.get("open", false))
			var c := Color(base.r, base.g, base.b, a * (0.7 if is_open else 1.0))
			var tex: Texture2D = ICON_DOOR_OPEN if is_open else ICON_DOOR_CLOSED
			draw_texture_rect(tex, Rect2(p - Vector2(16, 16), Vector2(32, 32)), false, c)
		"exit":
			# Red while locked (no exit key yet), teal once unlocked.
			var ec: Color = Color(1.0, 0.2, 0.2) if bool(m.get("locked", false)) else Color(0.55, 1.0, 0.92)
			draw_rect(Rect2(p - Vector2(16, 16), Vector2(32, 32)), Color(ec.r, ec.g, ec.b, a), false, 3.0)
			draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(ec.r, ec.g, ec.b, a * 0.5), false, 1.5)
