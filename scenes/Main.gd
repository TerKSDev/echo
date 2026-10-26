extends Node2D
## Game container: loads the current level, then wires the systems together.
## Supports both LevelRoot tilemap levels (level_01..level_13 with Water/Switch/Door/Exit)
## and freeform arena scenes (level_test.tscn).

const TILE := 32.0
const DOOR_COLOR := Color(1.0, 0.85, 0.2)

@onready var player: Node2D = $Player
@onready var echo_layer: Node2D = $EchoLayer
@onready var level_container: Node2D = $LevelContainer
@onready var sound_bus: SoundBus = $SoundBus
@onready var sfx: SfxManager = $SfxManager
@onready var hud: CanvasLayer = $Hud

var _level_root: LevelRoot = null
var _features: Node2D = null
var _enemies: Node2D = null
var _changing := false

var player_start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var has_exit := false
var water_cells: Dictionary = {}  # Vector2i -> true
var switch_cells: Dictionary = {} # Vector2i -> String
var door_nodes: Dictionary = {}   # String -> Array[StaticBody2D]
var pressed: Dictionary = {}
var _echo_features_cache: Array = []
var _echo_features_dirty := true

var _level_time := 0.0
var _sonar_pings := 0
var _enemies_alerted := 0
var _exit_beacon_timer := 0.6


func _ready() -> void:
	_load_level(GameState.current_level_path())

	sfx.set_player(player)
	sound_bus.setup(player, echo_layer, sfx)
	sound_bus.connect_enemies()
	sfx.beat.connect(hud.pulse_vignette)
	player.died.connect(_on_player_died)
	player.sound_emitted.connect(_on_player_sound_emitted)
	_connect_enemies_telemetry()
	_play_entry_sequence()


func _on_player_sound_emitted(_pos: Vector2, _loudness: float, is_voice: bool, _is_sneak: bool = false) -> void:
	if is_voice and not _changing:
		_sonar_pings += 1


func _connect_enemies_telemetry() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy):
			if not enemy.alert_triggered.is_connected(_on_enemy_alert):
				enemy.alert_triggered.connect(_on_enemy_alert)
			if not enemy.woke_up.is_connected(_on_enemy_alert):
				enemy.woke_up.connect(func(_p): _on_enemy_alert(enemy))
			if not enemy.screamed.is_connected(_on_enemy_alert):
				enemy.screamed.connect(func(_p, _r): _on_enemy_alert(enemy))
			if not enemy.alarmed.is_connected(_on_enemy_alert):
				enemy.alarmed.connect(func(_p, _t): _on_enemy_alert(enemy))


func _on_enemy_alert(_enemy: Enemy) -> void:
	if not _changing:
		_enemies_alerted += 1


func _play_entry_sequence() -> void:
	sfx.play_level_intro()

	# Format level title & evocative philosophical subtitle banner
	var cur_lvl := GameState.current_level
	var title_text: String = GameState.get_level_name(cur_lvl)
	var subtitle_text: String = GameState.get_sector_log(cur_lvl)

	if _level_root != null:
		if _level_root.level_name != "" and _level_root.level_name != "UNTITLED" and _level_root.level_name != "未命名":
			title_text = _level_root.level_name

	hud.play_level_intro(title_text, subtitle_text)

	if "pulse_scale" in player:
		player.pulse_scale = 0.25
		var p_tw := create_tween()
		p_tw.tween_property(player, "pulse_scale", 1.35, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p_tw.tween_property(player, "pulse_scale", 1.0, 0.35).set_trans(Tween.TRANS_SINE)

	# Emit a safe visual and acoustic awakening echo wave at 0.22s so the player senses their spawn surroundings
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(player) and is_instance_valid(echo_layer):
			var exclude: Array[RID] = [player.get_rid()]
			echo_layer.emit_echo(player.global_position, 220.0, exclude, true)
			if GameState.blind_assist_mode and player.has_method("_emit_wall_echos"):
				player._emit_wall_echos(0.35)
	)


func _load_level(path: String) -> void:
	water_cells.clear()
	switch_cells.clear()
	door_nodes.clear()
	pressed.clear()
	_echo_features_cache.clear()
	_echo_features_dirty = true
	has_exit = false
	_changing = false
	_level_root = null

	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Cannot load level: %s" % path)
		return
	var level := scene.instantiate()
	level_container.add_child(level)

	if level is LevelRoot:
		_level_root = level as LevelRoot
		if _level_root.walls != null:
			_level_root.walls.modulate.a = 0.0
		_features = Node2D.new()
		_features.name = "RuntimeFeatures"
		_level_root.add_child(_features)
		_enemies = Node2D.new()
		_enemies.name = "RuntimeEnemies"
		_level_root.add_child(_enemies)
		_ingest_markers()
		_spawn_enemies()
		player.global_position = cell_to_world(player_start_cell)
		if player.has_method("reset_for_level"):
			player.reset_for_level()
		elif "water_count" in player:
			player.water_count = 0
	else:
		# Optional spawn point: a Marker2D named "PlayerStart" inside the level
		var start := level.get_node_or_null("PlayerStart") as Marker2D
		if start != null:
			player.global_position = start.global_position
		if player.has_method("reset_for_level"):
			player.reset_for_level()


func _ingest_markers() -> void:
	if _level_root == null or _level_root.walls == null:
		return
	var walls: TileMapLayer = _level_root.walls
	for m: LevelMarker in _level_root.get_markers():
		var cell: Vector2i = walls.local_to_map(walls.to_local(m.global_position))
		match m.kind:
			LevelMarker.Kind.PLAYER_START:
				player_start_cell = cell
			LevelMarker.Kind.EXIT:
				exit_cell = cell
				has_exit = true
			LevelMarker.Kind.WATER:
				water_cells[cell] = true
			LevelMarker.Kind.SWITCH:
				var sid: String = m.link_id.strip_edges().to_lower()
				if sid != "":
					switch_cells[cell] = sid
			LevelMarker.Kind.DOOR:
				var did: String = m.link_id.strip_edges().to_upper()
				if did != "":
					_make_door(cell, did)


func _make_door(cell: Vector2i, id: String) -> void:
	var walls: TileMapLayer = _level_root.walls
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = walls.map_to_local(cell)
	body.set_meta("echo_color", DOOR_COLOR)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	body.add_child(shape)
	_features.add_child(body)
	if not door_nodes.has(id):
		door_nodes[id] = []
	door_nodes[id].append(body)


func _spawn_enemies() -> void:
	if _level_root == null:
		return
	for spawn: EnemySpawn in _level_root.get_enemy_spawns():
		if not spawn.spawn_on_level_start:
			continue
		spawn.spawn_enemy(_enemies)


func _physics_process(delta: float) -> void:
	if _changing or _level_root == null or _level_root.walls == null or player == null or not is_instance_valid(player):
		return
	if "alive" in player and not bool(player.get("alive")):
		return

	_level_time += delta

	# Periodic spatial exit beacon pulse only when approaching the exit zone (< 380px)
	if has_exit and not _changing and is_instance_valid(player) and bool(player.get("alive")):
		var exit_pos := cell_to_world(exit_cell)
		var dist: float = player.global_position.distance_to(exit_pos)
		var max_beacon_dist: float = 380.0 if GameState.blind_assist_mode else 280.0
		if dist <= max_beacon_dist:
			_exit_beacon_timer -= delta
			if _exit_beacon_timer <= 0.0:
				_exit_beacon_timer = lerpf(1.8, 3.0, clampf(dist / max_beacon_dist, 0.0, 1.0))
				var is_near: bool = dist < 110.0
				if sfx != null:
					sfx.play_exit_beacon(exit_pos, is_near, dist, max_beacon_dist)
		else:
			_exit_beacon_timer = 0.4

	var c: Vector2i = _level_root.walls.local_to_map(_level_root.walls.to_local(player.global_position))
	if "water_count" in player:
		player.water_count = 1 if water_cells.has(c) else 0

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Enemy and is_instance_valid(enemy):
			var ec: Vector2i = _level_root.walls.local_to_map(_level_root.walls.to_local(enemy.global_position))
			enemy.is_in_water = water_cells.has(ec)

	if switch_cells.has(c) and not pressed.has(c):
		_press_switch(c)
	if has_exit and c == exit_cell and not is_exit_locked():
		_changing = true
		var debrief_data := GameState.record_level_clear(
			GameState.current_level,
			_level_time,
			_sonar_pings,
			_enemies_alerted
		)
		hud.show_debrief(
			debrief_data,
			func(): # On Next
				if GameState.has_next_level():
					hud.play_level_exit_transition(func():
						GameState.next_level()
					)
				else:
					hud.show_victory_screen(),
			func(): # On Retry
				GameState.restart_level(),
			func(): # On Level Select
				GameState.go_to_level_select()
		)

func is_exit_locked() -> bool:
	for c in switch_cells:
		if str(switch_cells[c]) == "exit" and not pressed.has(c):
			return true
	return false



func _press_switch(cell: Vector2i) -> void:
	pressed[cell] = true
	_echo_features_dirty = true
	var id: String = str(switch_cells[cell]).to_upper()
	for body in door_nodes.get(id, []):
		if is_instance_valid(body) and not body.has_meta("open"):
			body.set_meta("open", true)
			body.get_child(0).set_deferred("disabled", true)
			if sfx != null:
				sfx.play_door_open(body.global_position)
	if sfx != null:
		sfx.play_sneak_toggle(false)
	if player != null and player.has_method("make_sound"):
		player.make_sound(0.06, false)


func echo_features() -> Array:
	if _level_root == null or _level_root.walls == null:
		return []
	if not _echo_features_dirty:
		return _echo_features_cache
	_echo_features_cache.clear()
	for c in water_cells:
		_echo_features_cache.append({"type": "water", "pos": cell_to_world(c)})
	for c in switch_cells:
		var sid: String = str(switch_cells[c]).to_upper()
		_echo_features_cache.append({"type": "switch", "pos": cell_to_world(c), "pressed": pressed.has(c), "id": sid, "color": link_color(sid)})
	for id in door_nodes:
		for body in door_nodes[id]:
			if not is_instance_valid(body):
				continue
			if body.has_meta("open"):
				_echo_features_cache.append({"type": "door", "pos": body.global_position, "open": true, "id": id, "color": link_color(id)})
			else:
				_echo_features_cache.append({"type": "door", "pos": body.global_position, "body": body, "open": false, "id": id, "color": link_color(id)})
	if has_exit:
		_echo_features_cache.append({"type": "exit", "pos": cell_to_world(exit_cell), "locked": is_exit_locked()})
	_echo_features_dirty = false
	return _echo_features_cache


# Door and key with the same link id share one colour.
const LINK_COLORS := {
	"A": Color(1.0, 0.82, 0.2),
	"B": Color(0.3, 0.9, 1.0),
	"C": Color(1.0, 0.4, 0.85),
	"D": Color(0.45, 1.0, 0.4),
	"E": Color(1.0, 0.35, 0.3),
	"F": Color(0.7, 0.5, 1.0),
	"G": Color(1.0, 0.6, 0.2),
	"H": Color(0.95, 0.95, 0.95),
	"EXIT": Color(1.0, 1.0, 1.0),
}


func link_color(id: String) -> Color:
	var key: String = id.strip_edges().to_upper()
	if LINK_COLORS.has(key):
		return LINK_COLORS[key]
	return Color.from_hsv(fmod(float(absi(key.hash()) % 360) / 360.0, 1.0), 0.6, 1.0)


func cell_to_world(cell: Vector2i) -> Vector2:
	if _level_root != null and _level_root.walls != null:
		return _level_root.walls.to_global(_level_root.walls.map_to_local(cell))
	return Vector2.ZERO


func _on_player_died() -> void:
	sfx.play_player_death()
	hud.flash_death()
	await get_tree().create_timer(0.55).timeout
	var killer_type: int = int(player.get("killed_by_type")) if "killed_by_type" in player else -1
	hud.show_death_screen(killer_type)
