extends Node2D

const RAY_COUNT := 96
const LIFETIME := 2.0
const WAVE_SPEED := 200.0
const DOT_SIZE := 3.0

var points: Array = []
var waves: Array = []

func emit_echo(origin: Vector2, radius: float, exclude: Array[RID] = [], show_wave: bool = true) -> void:
	if show_wave:
		waves.append({
			"pos": origin,
			"max_radius": radius,
			"age": 0.0
		})
	
	var space = get_world_2d().direct_space_state
	var hits := 0

	# Perform raycasts in a circular pattern to detect obstacles
	for i in RAY_COUNT:
		var dir = Vector2.RIGHT.rotated(TAU * i / RAY_COUNT)
		var query = PhysicsRayQueryParameters2D.create(origin, origin + dir * radius)
		
		query.collision_mask = 1
		query.exclude = exclude
		
		var hit = space.intersect_ray(query)
		if hit:
			hits += 1
			var dist := origin.distance_to(hit.position)
			points.append({
				"pos": hit.position,
				"age": -dist / WAVE_SPEED,
			})
	
# Update the age of each point and remove old points
func _process(delta):
	for p in points:
		p["age"] += delta
	points = points.filter(func(p): return p["age"] < LIFETIME)

	for w in waves:
		w["age"] += delta
	waves = waves.filter(func(w): return w["age"] * WAVE_SPEED < w["max_radius"])
	
	queue_redraw()

# Draw the points with fading alpha based on their age
func _draw():
	for p in points:
		if p["age"] < 0.0:
			continue
		var alpha = 1.0 - p["age"] / LIFETIME
		draw_circle(to_local(p["pos"]), DOT_SIZE, Color(0.3, 1.0, 1.0, alpha))

	for w in waves:
		var radius: float = w["age"] * WAVE_SPEED
		var fade: float = 1.0 - radius / float(w["max_radius"])
		draw_arc(to_local(w["pos"]), radius, 0.0, TAU, 64, Color(0.3, 1.0, 1.0, fade), 2.0)
