extends Node2D

const RAY_COUNT := 180
const LIFETIME := 2.0
const WAVE_SPEED := 400.0
const DOT_SIZE := 3.0
const MAX_POINTS := 900
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

	# Perform raycasts in a circular pattern to detect obstacles (deduplicating ultra-close hits)
	var last_hit_pos := Vector2(-99999.0, -99999.0)
	for i in RAY_COUNT:
		var dir := Vector2.RIGHT.rotated(TAU * i / RAY_COUNT)
		var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * radius)
		
		query.collision_mask = 1
		query.exclude = wall_exclude_rids
		
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var hit_pos: Vector2 = hit.position
			if hit_pos.distance_squared_to(last_hit_pos) < 20.0:
				continue
			last_hit_pos = hit_pos
			var dist: float = origin.distance_to(hit_pos)
			var pt_col: Color = wave_color
			var col_obj: Object = hit.get("collider")
			if col_obj != null and col_obj.has_meta("echo_color"):
				pt_col = col_obj.get_meta("echo_color")
			points.append({
				"pos": hit_pos,
				"age": -dist / WAVE_SPEED,
				"col": pt_col
			})

	if points.size() > MAX_POINTS:
		points = points.slice(points.size() - MAX_POINTS)

	_reveal_features(space, origin, radius, wall_exclude_rids)
	
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var enemy_node := enemy as Node2D
		if enemy_node == null:
			continue
		var dist: float = origin.distance_to(enemy_node.global_position)
		if dist <= radius:
			# Echoes bounce off walls; cannot reveal an enemy hidden behind a solid wall
			var occ_query := PhysicsRayQueryParameters2D.create(origin, enemy_node.global_position)
			occ_query.collision_mask = 1
			occ_query.exclude = exclude_rids
			var hit: Dictionary = space.intersect_ray(occ_query)
			if not hit.is_empty():
				continue

			get_tree().create_timer(dist / WAVE_SPEED).timeout.connect(
				func():
					if is_instance_valid(enemy_node):
						enemy_node.reveal(1.0)
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
		if ok:
			var f_type: String = String(f["type"])
			var s: float = 1.0 if f_type == "exit" else clampf(1.0 - d / max_dist, 0.38, 1.0)
			marks.append({
				"type": f_type,
				"pos": f_pos,
				"age": -d / WAVE_SPEED,
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
	for p in points:
		var age: float = float(p["age"])
		if age < 0.0:
			continue
		var alpha: float = clampf(1.0 - age / LIFETIME, 0.0, 1.0)
		var base_col: Color = p.get("col", Color(0.3, 1.0, 1.0))
		var lp: Vector2 = to_local(Vector2(p["pos"]))
		# Crisp impact flash when the sound wave first strikes the wall
		var impact: float = clampf(1.0 - age / 0.18, 0.0, 1.0)
		var dot_col: Color = base_col.lerp(Color.WHITE, impact * 0.65)
		if impact > 0.05:
			draw_circle(lp, DOT_SIZE * (1.8 + impact * 0.8), Color(base_col.r, base_col.g, base_col.b, alpha * impact * 0.28))
		draw_circle(lp, DOT_SIZE * (1.0 + impact * 0.35), Color(dot_col.r, dot_col.g, dot_col.b, alpha))

	for w in waves:
		var radius: float = float(w["age"]) * WAVE_SPEED
		var fade: float = clampf(1.0 - radius / float(w["max_radius"]), 0.0, 1.0)
		var w_col: Color = w.get("col", Color(0.3, 1.0, 1.0))
		var lw: Vector2 = to_local(Vector2(w["pos"]))
		draw_arc(lw, radius, 0.0, TAU, 64, Color(w_col.r, w_col.g, w_col.b, fade * 0.9), 2.2)
		if radius > 8.0:
			draw_arc(lw, radius - 5.0, 0.0, TAU, 64, Color(w_col.r, w_col.g, w_col.b, fade * 0.25), 4.0)

	for m in marks:
		var m_age: float = float(m["age"])
		if m_age < 0.0:
			continue
		var a: float = float(m["strength"]) * clampf(1.0 - m_age / (LIFETIME * 1.35), 0.0, 1.0)
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
