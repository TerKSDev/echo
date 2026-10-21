extends Marker2D
class_name EnemySpawn
## 敌人出生点：你朋友把敌人场景拖到 enemy_scene，再把本节点放到关卡里即可。
## 运行时 LevelController 会实例化敌人并加入 group "enemies"。

@export var enemy_scene: PackedScene
@export var spawn_on_level_start := true
## 可选：给敌人的额外参数（由敌人脚本自行读取 get_meta）
@export var enemy_id: String = ""
@export var hear_multiplier: float = 1.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	visible = false

func spawn_enemy(parent: Node) -> Node:
	if enemy_scene == null:
		push_warning("EnemySpawn '%s' 未设置 enemy_scene" % name)
		return null
	var enemy := enemy_scene.instantiate()
	enemy.global_position = global_position
	if enemy_id != "":
		enemy.set_meta("enemy_id", enemy_id)
	enemy.set_meta("hear_multiplier", hear_multiplier)
	if enemy.has_method("setup_from_spawn"):
		enemy.call("setup_from_spawn", self)
	parent.add_child(enemy)
	if not enemy.is_in_group("enemies"):
		enemy.add_to_group("enemies")
	return enemy
