extends Node2D
class_name PebbleProjectile

signal landed(pos: Vector2)

var path_points: Array[Vector2] = []
var cur_segment := 0
var seg_elapsed := 0.0
var seg_durations: Array[float] = []
var seg_heights: Array[float] = []
var _trail: Array[Vector2] = []
var _impact_time: float = -1.0
var _shards: Array[Dictionary] = []
var _wall_sparks: Array[Dictionary] = []


func setup(arg1, arg2 = null) -> void:
	if arg1 is Array:
		path_points = (arg1 as Array).duplicate()
	elif arg1 is Vector2 and arg2 is Vector2:
		path_points = [arg1, arg2]
	elif arg1 is Vector2:
		path_points = [global_position, arg1]
	else:
		path_points = [global_position, global_position]

	if path_points.size() < 2:
		path_points = [global_position, global_position]

	global_position = path_points[0]
	cur_segment = 0
	seg_elapsed = 0.0
	seg_durations.clear()
	seg_heights.clear()

	for i in range(path_points.size() - 1):
		var d: float = path_points[i].distance_to(path_points[i + 1])
		var dur: float = clampf(d / 240.0, 0.15 if i > 0 else 0.32, 0.85)
		seg_durations.append(dur)
		var h: float = clampf(d * 0.22, 10.0 if i > 0 else 22.0, 55.0) * (0.65 if i > 0 else 1.0)
		seg_heights.append(h)


func _process(delta: float) -> void:
	if _impact_time >= 0.0:
		_impact_time += delta
		for s in _shards:
			s["pos"] += s["vel"] * delta
			s["vel"] = s["vel"].move_toward(Vector2.ZERO, delta * 300.0)
		queue_redraw()
		if _impact_time >= 0.35:
			queue_free()
		return

	# Update transient wall bounce spark particles
	for ws in _wall_sparks:
		ws["pos"] += ws["vel"] * delta
		ws["life"] -= delta
	_wall_sparks = _wall_sparks.filter(func(ws): return ws["life"] > 0.0)

	if cur_segment < seg_durations.size():
		seg_elapsed += delta
		var dur: float = seg_durations[cur_segment]
		var t: float = clampf(seg_elapsed / dur, 0.0, 1.0)
		var p0: Vector2 = path_points[cur_segment]
		var p1: Vector2 = path_points[cur_segment + 1]
		var ground: Vector2 = p0.lerp(p1, t)
		var h: float = sin(t * PI) * seg_heights[cur_segment]
		var pebble_pos: Vector2 = ground - Vector2(0.0, h)
		global_position = ground

		_trail.push_front(pebble_pos)
		if _trail.size() > 8:
			_trail.pop_back()

		if t >= 1.0:
			if cur_segment < seg_durations.size() - 1:
				_on_bounce_wall(p1)
				cur_segment += 1
				seg_elapsed = 0.0
			else:
				_on_hit_ground()
	else:
		_on_hit_ground()

	queue_redraw()


func _on_bounce_wall(wall_pos: Vector2) -> void:
	var sb := get_tree().get_first_node_in_group("sound_bus") as SoundBus
	if sb != null and is_instance_valid(sb):
		# Calculate reflection normal away from wall back into playable room
		var in_dir: Vector2 = (wall_pos - path_points[cur_segment]).normalized() if cur_segment < path_points.size() else Vector2.ZERO
		var next_idx: int = cur_segment + 1
		var out_dir: Vector2 = (path_points[next_idx] - wall_pos).normalized() if next_idx < path_points.size() else -in_dir
		var n: Vector2 = (out_dir - in_dir).normalized()
		if n.is_zero_approx():
			n = -in_dir
		var sound_pos: Vector2 = wall_pos + n * 6.0
		# Emits sharp acoustic stone clink wave on wall impact
		sb.emit_decoy_sound(sound_pos, 0.24, 150.0, true)

	# Spawn wall spark chips directed back into room
	var p0 := path_points[cur_segment] if cur_segment < path_points.size() else wall_pos
	var spark_n := (p0 - wall_pos).normalized() if not (p0 - wall_pos).is_zero_approx() else Vector2.UP
	for i in 4:
		var ang := randf_range(-1.1, 1.1)
		_wall_sparks.append({
			"pos": to_local(wall_pos + spark_n * 2.0),
			"vel": spark_n.rotated(ang) * randf_range(30.0, 85.0),
			"life": randf_range(0.12, 0.22),
			"col": Color(1.0, 0.9, 0.5)
		})


func _on_hit_ground() -> void:
	_impact_time = 0.0
	var final_pos: Vector2 = path_points[path_points.size() - 1]
	global_position = final_pos
	var in_water := false
	var main_node := get_parent()
	if main_node != null and "water_cells" in main_node and "_level_root" in main_node and main_node._level_root != null and main_node._level_root.walls != null:
		var wc: Vector2i = main_node._level_root.walls.local_to_map(main_node._level_root.walls.to_local(final_pos))
		in_water = main_node.water_cells.has(wc)
	var sb := get_tree().get_first_node_in_group("sound_bus") as SoundBus
	if sb != null and is_instance_valid(sb):
		if in_water:
			sb.emit_decoy_sound(final_pos, 0.58, 360.0)
		else:
			sb.emit_decoy_sound(final_pos, 0.4, 280.0)
	landed.emit(final_pos)

	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_ricochet_pebble"):
		var origin_pt: Vector2 = path_points[0] if path_points.size() > 0 else final_pos
		var bounce_dir := (final_pos - origin_pt).normalized().rotated(randf_range(-0.35, 0.35))
		if bounce_dir.is_zero_approx():
			bounce_dir = Vector2.RIGHT
		var raw_dest := final_pos + bounce_dir * randf_range(65.0, 105.0)
		var space := get_world_2d().direct_space_state
		var q := PhysicsRayQueryParameters2D.create(final_pos, raw_dest)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var bounce_dest: Vector2 = (Vector2(hit.position) - bounce_dir * 8.0) if not hit.is_empty() else raw_dest
		get_tree().create_timer(0.25).timeout.connect(func():
			var bus := get_tree().get_first_node_in_group("sound_bus") as SoundBus
			if bus != null and is_instance_valid(bus):
				bus.emit_decoy_sound(bounce_dest, 0.42, 290.0)
		)

	# Spawn subtle stone impact chips
	for i in 6:
		var ang := randf() * TAU
		var spd := randf_range(40.0, 120.0)
		_shards.append({
			"pos": to_local(final_pos),
			"vel": Vector2.from_angle(ang) * spd,
			"size": randf_range(1.2, 2.5),
			"col": Color(1.0, 0.85, 0.45).lerp(Color(0.8, 0.7, 0.6), randf())
		})


func _draw() -> void:
	# Draw wall sparks
	for ws in _wall_sparks:
		draw_circle(ws["pos"], 1.5, ws["col"])

	if _impact_time >= 0.0:
		var fade := 1.0 - clampf(_impact_time / 0.35, 0.0, 1.0)
		for s in _shards:
			draw_circle(s["pos"], s["size"] * fade, Color(s["col"], fade))
		var r := _impact_time * 65.0
		var final_pos := path_points[path_points.size() - 1]
		draw_arc(to_local(final_pos), r, 0.0, TAU, 20, Color(1.0, 0.8, 0.35, fade * 0.7), 1.6)
		return

	if cur_segment >= seg_durations.size():
		return

	var dur: float = seg_durations[cur_segment]
	var t: float = clampf(seg_elapsed / dur, 0.0, 1.0)
	var h: float = sin(t * PI) * seg_heights[cur_segment]
	var local_pebble := to_local(global_position) - Vector2(0.0, h)
	var local_shadow := to_local(global_position)

	# 1. Ground shadow (expands as pebble gets closer to ground)
	var shadow_scale := clampf(1.0 - h / (seg_heights[cur_segment] * 1.4), 0.35, 1.0)
	draw_circle(local_shadow, 4.0 * shadow_scale, Color(0.0, 0.0, 0.0, 0.45 * shadow_scale))

	# 2. Motion trail
	for i in range(_trail.size()):
		var p := to_local(_trail[i])
		var frac := 1.0 - float(i) / float(_trail.size())
		draw_circle(p, 2.5 * frac, Color(1.0, 0.82, 0.35, 0.35 * frac))

	# 3. Flying Stone
	# Subtle glowing halo
	draw_circle(local_pebble, 5.0, Color(1.0, 0.75, 0.25, 0.3))
	# Main stone body
	draw_circle(local_pebble, 3.5, Color(0.9, 0.8, 0.65))
	# Specular highlight
	draw_circle(local_pebble + Vector2(-1.0, -1.0), 1.4, Color(1.0, 1.0, 0.95))
