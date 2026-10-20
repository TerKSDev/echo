extends Node2D
## Game container: loads the current level, then wires the systems together.
## Levels live in res://levels/ and are listed in the GameState autoload.

@onready var player: Node2D = $Player
@onready var echo_layer: Node2D = $EchoLayer
@onready var level_container: Node2D = $LevelContainer
@onready var sound_bus: SoundBus = $SoundBus
@onready var heartbeat: HeartbeatManager = $HeartbeatManager
@onready var hud: CanvasLayer = $Hud


func _ready() -> void:
	_load_level(GameState.current_level_path())

	sound_bus.setup(player, echo_layer)
	sound_bus.connect_enemies()
	heartbeat.beat.connect(hud.pulse_vignette)
	player.died.connect(_on_player_died)


func _load_level(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Cannot load level: %s" % path)
		return
	var level := scene.instantiate()
	level_container.add_child(level)

	# Optional spawn point: a Marker2D named "PlayerStart" inside the level
	var start := level.get_node_or_null("PlayerStart") as Marker2D
	if start != null:
		player.global_position = start.global_position


func _on_player_died() -> void:
	hud.flash_death()
	await get_tree().create_timer(1.1).timeout
	GameState.restart_level()
