class_name LevelBuilder
extends RefCounted
## Builds a level from the plain-text layout stored on a LevelRoot
## (`ascii_map` + optional `routes`), so levels can be read and tuned as text.
##
## ASCII LEGEND (one character = one 32px tile)
##   #  wall                 .  floor (a space also works)       ~  shallow water (floor)
##   P  player start         E  exit                             K  exit key (exit stays locked until stepped on)
##   A-D  doors              a-d  floor switches (a opens A, b opens B ...)
##   Z  sleeper              H  sleeping chaser (hunter)         X  screamer        L  listener
##   N  lore note / expedition journal
##   1-9, e-y   route waypoints, used by the `routes` block below
##
## ROUTES (one enemy per line):   <type> <waypoints> [wake=<switch id>]
##   type = patroller | chaser | sleeper | screamer | listener
##   waypoints = waypoint glyphs in visiting order, e.g. "1234" (the enemy spawns on the first one;
##               a single waypoint means a stationary guard)
##   wake=a   the enemy is alerted to the player the moment switch `a` is pressed
##   Example:   patroller 1234
##              chaser 5 wake=b

const TILE := 32.0

const SCENES := {
	"sleeper": preload("res://characters/enemy/enemy_sleeper.tscn"),
	"patroller": preload("res://characters/enemy/enemy_patroller.tscn"),
	"chaser": preload("res://characters/enemy/enemy_chaser.tscn"),
	"screamer": preload("res://characters/enemy/enemy_screamer.tscn"),
	"listener": preload("res://characters/enemy/enemy_listener.tscn"),
}

const STATIC_ENEMIES := {
	"Z": "sleeper",
	"H": "chaser",
	"X": "screamer",
	"L": "listener",
}

const TYPE_ALIASES := {
	"patrol": "patroller",
	"chase": "chaser",
	"hunter": "chaser",
}


static func build(root: Node2D) -> void:
	var walls := root.get_node_or_null("Walls") as TileMapLayer
	if walls == null:
		push_error("LevelBuilder: level has no Walls TileMapLayer")
		return
	walls.clear()

	var glyph_cells: Dictionary = {}  # waypoint glyph -> Vector2i
	var static_enemies: Array = []    # [type, Vector2i]

	var y := 0
	for raw_line: String in str(root.get("ascii_map")).split("\n"):
		var line := raw_line.strip_edges(false, true)
		if line.is_empty():
			continue
		for x in line.length():
			var ch := line[x]
			var cell := Vector2i(x, y)
			if ch == "#":
				walls.set_cell(cell, 0, Vector2i(0, 0))
				continue
			match ch:
				".", " ":
					pass
				"P":
					_marker(root, LevelMarker.Kind.PLAYER_START, cell)
				"E":
					_marker(root, LevelMarker.Kind.EXIT, cell)
				"K":
					_marker(root, LevelMarker.Kind.SWITCH, cell, "exit")
				"~":
					_marker(root, LevelMarker.Kind.WATER, cell)
				"A", "B", "C", "D":
					_marker(root, LevelMarker.Kind.DOOR, cell, ch)
				"a", "b", "c", "d":
					_marker(root, LevelMarker.Kind.SWITCH, cell, ch)
				"N":
					_marker(root, LevelMarker.Kind.NOTE, cell)
				"Z", "H", "X", "L":
					static_enemies.append([STATIC_ENEMIES[ch], cell])
				_:
					glyph_cells[ch] = cell
		y += 1

	# If the scene already has enemies manually placed in the editor scene tree,
	# respect them and do not overwrite or duplicate them!
	var has_manual_enemies := false
	if root.has_node("Enemies") and root.get_node("Enemies").get_child_count() > 0:
		has_manual_enemies = true
	for child in root.get_children():
		if child is Enemy:
			has_manual_enemies = true
			break

	if not has_manual_enemies:
		for entry: Array in static_enemies:
			var guard_point: Array[Vector2] = [_center(entry[1])]
			_spawn(root, str(entry[0]), guard_point)

		for raw_route: String in str(root.get("routes")).split("\n"):
			var text := raw_route.strip_edges()
			if text.is_empty() or text.begins_with("#"):
				continue
			var parts := text.split(" ", false)
			if parts.size() < 2:
				push_warning("LevelBuilder: bad route line '%s'" % text)
				continue
			var type_name: String = TYPE_ALIASES.get(parts[0], parts[0])
			if not SCENES.has(type_name):
				push_warning("LevelBuilder: unknown enemy type '%s'" % parts[0])
				continue
			var points: Array[Vector2] = []
			var wake := ""
			for i in range(1, parts.size()):
				var token: String = parts[i]
				if token.begins_with("wake="):
					wake = token.substr(5)
					continue
				for g in token.length():
					var glyph := token[g]
					if glyph_cells.has(glyph):
						points.append(_center(glyph_cells[glyph]))
					else:
						push_warning("LevelBuilder: waypoint '%s' is not on the map" % glyph)
			if points.is_empty():
				continue
			_spawn(root, type_name, points, wake)


static func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


static func _marker(root: Node2D, kind: int, cell: Vector2i, link: String = "") -> void:
	var m := LevelMarker.new()
	m.kind = kind
	m.link_id = link
	m.position = _center(cell)
	root.add_child(m)


static func _spawn(root: Node2D, type_name: String, points: Array[Vector2], wake: String = "") -> void:
	var scene: PackedScene = SCENES[type_name]
	var enemy := scene.instantiate() as Enemy
	enemy.position = points[0]
	if points.size() > 1:
		enemy.patrol_points = points
		var patrol_path := PatrolPath.new()
		patrol_path.name = "PatrolPath"
		patrol_path.is_closed = (points.size() > 2)
		for idx in range(points.size()):
			var marker := Marker2D.new()
			marker.name = "Path%02d" % (idx + 1)
			marker.position = points[idx] - points[0]
			patrol_path.add_child(marker)
		enemy.add_child(patrol_path)
	if wake != "":
		enemy.set_meta("wake_on", wake.to_lower())
	root.add_child(enemy)
