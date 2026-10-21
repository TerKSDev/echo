extends Node2D
## 加载 levels/level_XX.tscn，处理机关 / 出口 / 敌人出生。
## 地图请在编辑器里改对应关卡场景，不要再改 ASCII。

const TILE := 32.0
const DOOR_COLOR := Color(1.0, 0.85, 0.2)
const LEVEL_DIR := "res://levels/"

@export var player_path: NodePath = ^"../Player"
@export var echo_layer_path: NodePath = ^"../EchoLayer"
@export var show_walls := false
@export var start_level := 0
@export var loop_after_last := true
@export var debug_keys := true
## 按顺序填关卡场景；空则自动扫描 res://levels/level_*.tscn
@export var level_scenes: Array[PackedScene] = []

signal exit_reached
signal level_loaded(index: int)
signal all_levels_completed
signal enemy_spawned(enemy: Node)

var level_index := 0
var player_start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var water_cells := {} # Vector2i -> true
var switch_cells := {} # Vector2i -> String
var door_nodes := {} # String -> Array[StaticBody2D]
var pressed := {}
var _level: LevelRoot
var _features: Node2D
var _enemies: Node2D
var _changing := false
var _resolved_scenes: Array[PackedScene] = []
@onready var _player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	exit_reached.connect(_on_exit_reached)
	_resolved_scenes = _build_scene_list()
	if _resolved_scenes.is_empty():
		push_error("LevelController: 没有找到关卡场景（res://levels/level_*.tscn）")
		return
	load_level(start_level)


func level_count() -> int:
	return _resolved_scenes.size()


func get_walls() -> TileMapLayer:
	if _level:
		return _level.walls
	return null


func load_level(index: int) -> void:
	if _resolved_scenes.is_empty():
		_resolved_scenes = _build_scene_list()
	if _resolved_scenes.is_empty():
		return
	level_index = clampi(index, 0, _resolved_scenes.size() - 1)
	_clear_runtime()
	var packed: PackedScene = _resolved_scenes[level_index]
	_level = packed.instantiate() as LevelRoot
	if _level == null:
		push_error("关卡根节点必须挂 LevelRoot.gd: %s" % packed.resource_path)
		return
	add_child(_level)
	if _level.walls:
		_level.walls.modulate.a = 1.0 if show_walls else 0.0
	_features = Node2D.new()
	_features.name = "RuntimeFeatures"
	_level.add_child(_features)
	_enemies = Node2D.new()
	_enemies.name = "RuntimeEnemies"
	_level.add_child(_enemies)
	_ingest_markers()
	_spawn_enemies()
	_place_player()
	_clear_echo()
	_changing = false
	print("关卡 %d/%d: %s —— %s" % [
		level_index + 1, _resolved_scenes.size(), _level.level_name, _level.hint
	])
	level_loaded.emit(level_index)


func _build_scene_list() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	if not level_scenes.is_empty():
		for s in level_scenes:
			if s:
				out.append(s)
		return out
	var paths: PackedStringArray = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.begins_with("level_") and fname.ends_with(".tscn"):
				paths.append(LEVEL_DIR + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	paths.sort()
	for p in paths:
		var packed := load(p) as PackedScene
		if packed:
			out.append(packed)
	return out


func _clear_runtime() -> void:
	water_cells.clear()
	switch_cells.clear()
	door_nodes.clear()
	pressed.clear()
	if _level:
		_level.queue_free()
		_level = null
	_features = null
	_enemies = null


func _ingest_markers() -> void:
	var walls := _level.walls
	if walls == null:
		push_error("关卡缺少 Walls (TileMapLayer)")
		return
	for m in _level.get_markers():
		var cell := walls.local_to_map(walls.to_local(m.global_position))
		match m.kind:
			LevelMarker.Kind.PLAYER_START:
				player_start_cell = cell
			LevelMarker.Kind.EXIT:
				exit_cell = cell
			LevelMarker.Kind.WATER:
				water_cells[cell] = true
			LevelMarker.Kind.SWITCH:
				var sid := m.link_id.strip_edges().to_lower()
				if sid == "":
					push_warning("SWITCH 缺少 link_id: %s" % m.name)
				else:
					switch_cells[cell] = sid
			LevelMarker.Kind.DOOR:
				var did := m.link_id.strip_edges().to_upper()
				if did == "":
					push_warning("DOOR 缺少 link_id: %s" % m.name)
				else:
					_make_door(cell, did)


func _make_door(cell: Vector2i, id: String) -> void:
	var walls := _level.walls
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
	for spawn in _level.get_enemy_spawns():
		if not spawn.spawn_on_level_start:
			continue
		var enemy := spawn.spawn_enemy(_enemies)
		if enemy:
			enemy_spawned.emit(enemy)


func _place_player() -> void:
	if _player == null or _level == null or _level.walls == null:
		return
	_player.global_position = cell_to_world(player_start_cell)
	if "velocity" in _player:
		_player.velocity = Vector2.ZERO
	if "water_count" in _player:
		_player.water_count = 0


func _clear_echo() -> void:
	var echo := get_node_or_null(echo_layer_path)
	if echo and echo.has_method("clear_all"):
		echo.clear_all()


func _physics_process(_delta: float) -> void:
	if _changing or _player == null or _level == null or _level.walls == null:
		return
	var c := _level.walls.local_to_map(_level.walls.to_local(_player.global_position))
	if "water_count" in _player:
		_player.water_count = 1 if water_cells.has(c) else 0
	if switch_cells.has(c) and not pressed.has(c):
		_press(c)
	if c == exit_cell:
		exit_reached.emit()


func _press(cell: Vector2i) -> void:
	pressed[cell] = true
	var id: String = str(switch_cells[cell]).to_upper()
	for body in door_nodes.get(id, []):
		if is_instance_valid(body) and not body.has_meta("open"):
			body.set_meta("open", true)
			body.get_child(0).set_deferred("disabled", true)
	if _player and _player.has_method("make_sound"):
		_player.make_sound(0.06, false)
	print("开关 %s 触发, 门 %s 已打开" % [switch_cells[cell], id])


func echo_features() -> Array:
	var out: Array = []
	for c in water_cells:
		out.append({"type": "water", "pos": cell_to_world(c)})
	for c in switch_cells:
		out.append({"type": "switch", "pos": cell_to_world(c), "pressed": pressed.has(c)})
	for id in door_nodes:
		for body in door_nodes[id]:
			if is_instance_valid(body) and not body.has_meta("open"):
				out.append({"type": "door", "pos": body.global_position, "body": body})
	out.append({"type": "exit", "pos": cell_to_world(exit_cell)})
	# 敌人可被回声照亮：敌人脚本设 meta echo_color，或加入 group echo_reveal
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			out.append({"type": "enemy", "pos": enemy.global_position, "body": enemy})
	return out


func _on_exit_reached() -> void:
	if _changing:
		return
	_changing = true
	call_deferred("_advance_level")


func _advance_level() -> void:
	var next := level_index + 1
	if next >= _resolved_scenes.size():
		all_levels_completed.emit()
		if not loop_after_last:
			return
		next = 0
	load_level(next)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys or _changing:
		return
	if event.is_action_pressed("ui_page_down"):
		load_level(mini(level_index + 1, _resolved_scenes.size() - 1))
	elif event.is_action_pressed("ui_page_up"):
		load_level(maxi(level_index - 1, 0))
	elif event.is_action_pressed("ui_end") and _player:
		_player.global_position = cell_to_world(exit_cell)


func cell_to_world(cell: Vector2i) -> Vector2:
	if _level and _level.walls:
		return _level.walls.to_global(_level.walls.map_to_local(cell))
	return Vector2.ZERO


## 兼容旧 EchoLayer / 调试代码：把格子坐标映射到世界坐标。
func map_to_local(cell: Vector2i) -> Vector2:
	if _level and _level.walls:
		return _level.walls.map_to_local(cell)
	return Vector2.ZERO


func local_to_map(local_pos: Vector2) -> Vector2i:
	if _level and _level.walls:
		return _level.walls.local_to_map(local_pos)
	return Vector2i.ZERO
