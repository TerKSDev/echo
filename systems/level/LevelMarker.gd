extends Marker2D
class_name LevelMarker
## 关卡标记：在编辑器里拖到格子中心即可，运行时由 LevelController 读取。

enum Kind {
	PLAYER_START,
	EXIT,
	WATER,
	SWITCH,
	DOOR,
	NOTE,
}

@export var kind: Kind = Kind.EXIT
## SWITCH / DOOR 共用：a↔A、b↔B…（填 a/b/c/d 或 A/B/C/D 均可）
@export var link_id: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 运行时标记本身不可见
	visible = false
