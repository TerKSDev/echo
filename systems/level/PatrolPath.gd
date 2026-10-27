@tool
class_name PatrolPath
extends Node2D
## Visual patrol path for enemies in the editor and in-game.
## Shows waypoints, trajectory lines, and direction arrows in Godot's 2D scene editor,
## allowing designers to visually inspect and drag patrol points directly in the viewport.

@export var is_closed: bool = true:
	set(val):
		is_closed = val
		queue_redraw()

@export var line_color: Color = Color(1.0, 0.82, 0.25, 0.8):
	set(val):
		line_color = val
		queue_redraw()

@export var line_width: float = 3.0:
	set(val):
		line_width = val
		queue_redraw()

@export var waypoints: Array[Vector2] = []:
	set(val):
		waypoints = val
		queue_redraw()

@export var show_in_game: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		var parent_enemy := get_parent() as Enemy
		if parent_enemy != null:
			var pts := get_global_waypoints()
			if pts.size() > 0:
				parent_enemy.patrol_points = pts
				parent_enemy.home = pts[0]
				if pts.size() > 1:
					parent_enemy.state = Enemy.State.PATROL
					parent_enemy.init_state = Enemy.State.PATROL


func get_global_waypoints() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D:
			markers.append(child)
	if not markers.is_empty():
		for m in markers:
			out.append(m.global_position)
	elif not waypoints.is_empty():
		for p in waypoints:
			out.append(to_global(p))
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_DRAW:
		queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Continuously sync in editor when dragging markers
		var markers: Array[Marker2D] = []
		for child in get_children():
			if child is Marker2D:
				markers.append(child)
		if not markers.is_empty():
			var pts: Array[Vector2] = []
			for m in markers:
				pts.append(to_local(m.global_position))
			if pts != waypoints:
				waypoints = pts
				queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() and not show_in_game:
		return

	var pts: Array[Vector2] = []
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D:
			markers.append(child)

	if not markers.is_empty():
		for m in markers:
			pts.append(to_local(m.global_position))
	else:
		pts = waypoints

	if pts.size() < 2:
		if pts.size() == 1:
			draw_circle(pts[0], 6.0, line_color)
		return

	var total := pts.size()
	var seg_count := total if is_closed else total - 1

	# 1. Draw patrol path lines & arrows
	for i in range(seg_count):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % total]
		# Soft glowing back-line
		draw_line(a, b, Color(line_color.r, line_color.g, line_color.b, 0.25), line_width + 4.0, true)
		# Crisp foreground trajectory line
		draw_line(a, b, line_color, line_width, true)

		# Direction arrow at 60% of segment length
		var mid: Vector2 = a.lerp(b, 0.58)
		var dir: Vector2 = (b - a).normalized()
		if not dir.is_zero_approx():
			var normal: Vector2 = Vector2(-dir.y, dir.x)
			var arrow_size := 8.0
			var tip: Vector2 = mid + dir * (arrow_size * 0.9)
			var left: Vector2 = mid - dir * (arrow_size * 0.6) + normal * (arrow_size * 0.65)
			var right: Vector2 = mid - dir * (arrow_size * 0.6) - normal * (arrow_size * 0.65)
			draw_colored_polygon([tip, left, right], line_color)

	# 2. Draw waypoint node halos and numbers
	for i in range(total):
		var p: Vector2 = pts[i]
		# Halo
		draw_circle(p, 8.0, Color(line_color.r, line_color.g, line_color.b, 0.3))
		# Main point dot
		draw_circle(p, 4.5, line_color)
		# Inner white beacon for starting point (index 0)
		if i == 0:
			draw_circle(p, 2.0, Color.WHITE)
