extends Node2D

const RAY_COUNT := 180
const LIFETIME := 2.0
const WAVE_SPEED := 400.0
const DOT_SIZE := 3.0

var points: Array = []
var waves: Array = []

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

	# Perform raycasts in a circular pattern to detect obstacles
	for i in RAY_COUNT:
		var dir := Vector2.RIGHT.rotated(TAU * i / RAY_COUNT)
		var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * radius)
		
		query.collision_mask = 1
		query.exclude = exclude_rids
		
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var dist: float = origin.distance_to(hit.position)
			points.append({
				"pos": hit.position,
				"age": -dist / WAVE_SPEED,
				"col": wave_color
			})
	
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
	
# Update the age of each point and remove old points
func _process(delta):
	for p in points:
		p["age"] += delta
	points = points.filter(func(p): return p["age"] < LIFETIME)

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
