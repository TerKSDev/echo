extends Node2D
## Dark Echo 式回声:射线反弹显示墙面,声波扫过时显示水、开关、门、出口。
const RAY_COUNT := 96
const RAYS_PER_PIXEL := 0.5
const MAX_RAYS := 360
const MAX_BOUNCES := 3
const BOUNCE_ENERGY := 0.6
const RANGE_MULT := 1.8
const LIFETIME := 3.0
const WAVE_SPEED := 300.0
const MARK_HALF_LENGTH := 4.0
const MARK_WIDTH := 2.0
const MAX_POINTS := 6000
const WALL_MASK := 1
const ECHO_COLOR := Color(1, 1, 1)
const WATER_COLOR := Color(0.35, 0.65, 1.0)
const SWITCH_COLOR := Color(1.0, 0.7, 0.15)
const DOOR_COLOR := Color(1.0, 0.85, 0.2)

@export var level_path: NodePath = ^"../LevelController"

var points: Array = []
var waves: Array = []
var marks: Array = []


func clear_all() -> void:
	points.clear()
	waves.clear()
	marks.clear()
	queue_redraw()


func emit_echo(origin: Vector2, radius: float, exclude_in: Array = [], show_wave := true) -> void:
	var exclude: Array[RID] = []
	for r in exclude_in:
		exclude.append(r)
	var space := get_world_2d().direct_space_state
	var max_dist := radius * RANGE_MULT
	var n := clampi(int(TAU * radius * RAYS_PER_PIXEL), RAY_COUNT, MAX_RAYS)
	for i in n:
		var dir := Vector2.RIGHT.rotated(TAU * i / n)
		var pos := origin
		var travelled := 0.0
		var energy := 1.0
		for b in MAX_BOUNCES + 1:
			var remaining := max_dist - travelled
			if remaining <= 1.0:
				break
			var q := PhysicsRayQueryParameters2D.create(pos, pos + dir * remaining, WALL_MASK, exclude)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var normal: Vector2 = hit["normal"]
			if normal == Vector2.ZERO:
				break
			travelled += pos.distance_to(hit["position"])
			var col := ECHO_COLOR
			var obj: Object = hit["collider"]
			if obj and obj.has_meta("echo_color"):
				col = obj.get_meta("echo_color")
			points.append({"pos": hit["position"], "tan": normal.orthogonal(), "age": -travelled / WAVE_SPEED,
					"strength": energy * clampf(1.0 - travelled / max_dist, 0.15, 1.0), "color": col})
			dir = dir.bounce(normal)
			pos = hit["position"] + normal * 0.5
			energy *= BOUNCE_ENERGY
	if points.size() > MAX_POINTS:
		points = points.slice(points.size() - MAX_POINTS)
	_reveal_features(space, origin, max_dist, exclude)
	if show_wave:
		waves.append({"origin": origin, "age": 0.0, "max": max_dist})


func _reveal_features(space: PhysicsDirectSpaceState2D, origin: Vector2, max_dist: float, exclude: Array[RID]) -> void:
	var gen := get_node_or_null(level_path)
	if gen == null or not gen.has_method("echo_features"):
		return
	for f in gen.echo_features():
		var d: float = origin.distance_to(f["pos"])
		if d > max_dist:
			continue
		var q := PhysicsRayQueryParameters2D.create(origin, f["pos"], WALL_MASK, exclude)
		var hit := space.intersect_ray(q)
		var ok: bool = hit.is_empty()
		if not ok and f.has("body"):
			ok = hit["collider"] == f["body"]
		if not ok:
			ok = (hit["position"] as Vector2).distance_to(f["pos"]) < 12.0
		if ok:
			var s := 1.0 if f["type"] == "exit" else clampf(1.0 - d / max_dist, 0.35, 1.0)
			marks.append({"type": f["type"], "pos": f["pos"], "age": -d / WAVE_SPEED, "strength": s,
					"pressed": f.get("pressed", false)})


func _process(delta: float) -> void:
	var keep: Array = []
	for p in points:
		p["age"] += delta
		if p["age"] < LIFETIME:
			keep.append(p)
	points = keep
	var keep_m: Array = []
	for m in marks:
		m["age"] += delta
		if m["age"] < LIFETIME * 1.3:
			keep_m.append(m)
	marks = keep_m
	var keep_w: Array = []
	for w in waves:
		w["age"] += delta
		if w["age"] * WAVE_SPEED < w["max"]:
			keep_w.append(w)
	waves = keep_w
	queue_redraw()


func _draw() -> void:
	for w in waves:
		var r: float = w["age"] * WAVE_SPEED
		var a: float = 0.18 * (1.0 - r / float(w["max"]))
		draw_arc(w["origin"], r, 0.0, TAU, 64, Color(1, 1, 1, a), 1.5)
	for p in points:
		if p["age"] < 0.0:
			continue
		var a: float = p["strength"] * (1.0 - p["age"] / LIFETIME)
		var c: Color = p["color"]
		c.a = a
		draw_line(p["pos"] - p["tan"] * MARK_HALF_LENGTH, p["pos"] + p["tan"] * MARK_HALF_LENGTH, c, MARK_WIDTH)
	for m in marks:
		if m["age"] < 0.0:
			continue
		var a: float = m["strength"] * (1.0 - m["age"] / (LIFETIME * 1.3))
		_draw_mark(m, a)


func _draw_mark(m: Dictionary, a: float) -> void:
	var p: Vector2 = m["pos"]
	match m["type"]:
		"water":
			var c := WATER_COLOR
			c.a = a * 0.9
			for oy in [-6.0, 0.0, 6.0]:
				var pts := PackedVector2Array()
				for i in range(0, 25, 3):
					var x := i - 12.0
					pts.append(p + Vector2(x, oy + sin(x * 0.5 + oy) * 2.0))
				draw_polyline(pts, c, 1.5)
		"switch":
			var c := SWITCH_COLOR
			c.a = a * (0.45 if m["pressed"] else 1.0)
			draw_arc(p, 8.0, 0.0, TAU, 20, c, 2.0)
			if not m["pressed"]:
				draw_circle(p, 3.5, c)
		"door":
			var c := DOOR_COLOR
			c.a = a
			draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), c, false, 2.0)
			draw_line(p - Vector2(15, 15), p + Vector2(15, 15), c, 1.0)
			draw_line(p + Vector2(-15, 15), p + Vector2(15, -15), c, 1.0)
		"exit":
			var c := Color(1, 1, 1, a)
			draw_rect(Rect2(p - Vector2(17, 17), Vector2(34, 34)), c, false, 3.5)
			draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(1, 1, 1, a * 0.5), false, 1.5)
