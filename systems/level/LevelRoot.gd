extends Node2D
class_name LevelRoot
## 单关场景的根节点。在编辑器中打开 levels/level_XX.tscn 即可改地形与标记。

@export var level_name: String = "UNTITLED"
@export_multiline var hint: String = ""

@onready var walls: TileMapLayer = $Walls

func get_markers() -> Array[LevelMarker]:
	var out: Array[LevelMarker] = []
	_collect_markers(self, out)
	return out

func get_enemy_spawns() -> Array[EnemySpawn]:
	var out: Array[EnemySpawn] = []
	_collect_spawns(self, out)
	return out

func _collect_markers(n: Node, out: Array[LevelMarker]) -> void:
	if n is LevelMarker:
		out.append(n)
	for c in n.get_children():
		_collect_markers(c, out)

func _collect_spawns(n: Node, out: Array[EnemySpawn]) -> void:
	if n is EnemySpawn:
		out.append(n)
	for c in n.get_children():
		_collect_spawns(c, out)
