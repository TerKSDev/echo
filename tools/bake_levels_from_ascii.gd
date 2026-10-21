extends SceneTree
## 一次性工具：把 Levels.gd 的 ASCII 烘焙成可编辑的 levels/level_XX.tscn
## 用法（项目根目录）:
##   Godot_v4.x --headless --path . -s res://tools/bake_levels_from_ascii.gd

const Levels = preload("res://scripts/Levels.gd")
const TILESET_PATH := "res://tilesets/echo_tileset.tres"
const OUT_DIR := "res://levels/"
const SOURCE_ID := 0
const TILE := 32.0


func _init() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var tileset: TileSet = load(TILESET_PATH)
	if tileset == null:
		push_error("缺少 tileset: %s" % TILESET_PATH)
		quit(1)
		return
	var marker_script: Script = load("res://scripts/level/LevelMarker.gd")
	var root_script: Script = load("res://scripts/level/LevelRoot.gd")
	var spawn_script: Script = load("res://scripts/level/EnemySpawn.gd")
	if marker_script == null or root_script == null or spawn_script == null:
		push_error("缺少 LevelMarker / LevelRoot / EnemySpawn 脚本")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var count := Levels.LEVELS.size()
	for i in count:
		var data: Dictionary = Levels.LEVELS[i]
		var path := "%slevel_%02d.tscn" % [OUT_DIR, i + 1]
		var packed := _build_level(data, tileset, root_script, marker_script, spawn_script)
		var err := ResourceSaver.save(packed, path)
		if err != OK:
			push_error("保存失败 %s err=%s" % [path, err])
			quit(1)
			return
		print("baked %s (%s)" % [path, data.get("name", "")])
	print("Done: %d levels -> %s" % [count, OUT_DIR])
	quit(0)


func _build_level(
	data: Dictionary,
	tileset: TileSet,
	root_script: Script,
	marker_script: Script,
	spawn_script: Script
) -> PackedScene:
	var root := Node2D.new()
	root.set_script(root_script)
	root.set("level_name", str(data.get("name", "未命名")))
	root.set("hint", str(data.get("hint", "")))
	root.name = "Level"

	var walls := TileMapLayer.new()
	walls.name = "Walls"
	walls.tile_set = tileset
	root.add_child(walls)
	walls.owner = root

	var markers := Node2D.new()
	markers.name = "Markers"
	root.add_child(markers)
	markers.owner = root

	var enemies := Node2D.new()
	enemies.name = "Enemies"
	root.add_child(enemies)
	enemies.owner = root

	# 放一个示例出生点（未指定 enemy_scene，不会生成），方便朋友对照
	var demo_spawn := Marker2D.new()
	demo_spawn.set_script(spawn_script)
	demo_spawn.name = "EnemySpawn_Example"
	demo_spawn.set("spawn_on_level_start", false)
	enemies.add_child(demo_spawn)
	demo_spawn.owner = root

	var rows: Array = data["rows"]
	var water_i := 0
	var switch_i := 0
	var door_i := 0
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var cell := Vector2i(x, y)
			var ch := row[x]
			var pos := walls.map_to_local(cell)
			match ch:
				"#":
					walls.set_cell(cell, SOURCE_ID, Vector2i(0, 0))
				"1", "2", "3", "4":
					walls.set_cell(cell, SOURCE_ID, Vector2i(int(ch), 0))
				"P":
					_add_marker(markers, marker_script, root, "PlayerStart", pos, 0, "")
				"E":
					_add_marker(markers, marker_script, root, "Exit", pos, 1, "")
				"~":
					water_i += 1
					_add_marker(markers, marker_script, root, "Water_%d" % water_i, pos, 2, "")
				"a", "b", "c", "d":
					switch_i += 1
					_add_marker(markers, marker_script, root, "Switch_%s_%d" % [ch, switch_i], pos, 3, ch)
				"A", "B", "C", "D":
					door_i += 1
					_add_marker(markers, marker_script, root, "Door_%s_%d" % [ch, door_i], pos, 4, ch)

	# 示例出生点放到玩家起点旁（若有）
	var start := markers.get_node_or_null("PlayerStart")
	if start:
		demo_spawn.position = start.position + Vector2(TILE * 2.0, 0.0)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %s" % err)
	root.free()
	return packed


func _add_marker(
	parent: Node,
	script: Script,
	root: Node,
	node_name: String,
	pos: Vector2,
	kind: int,
	link_id: String
) -> void:
	var m := Marker2D.new()
	m.set_script(script)
	m.name = node_name
	m.position = pos
	m.set("kind", kind)
	m.set("link_id", link_id)
	parent.add_child(m)
	m.owner = root
