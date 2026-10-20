extends Node2D
## Game container: loads the current level, then wires the systems together.
## Levels live in res://levels/ and are listed in the GameState autoload.

@onready var player: Node2D = $Player
@onready var echo_layer: Node2D = $EchoLayer
@onready var level_container: Node2D = $LevelContainer
@onready var sound_bus: SoundBus = $SoundBus
@onready var sfx: SfxManager = $SfxManager
@onready var hud: CanvasLayer = $Hud


func _ready() -> void:
	_load_level(GameState.current_level_path())

	sfx.set_player(player)
	sound_bus.setup(player, echo_layer, sfx)
	sound_bus.connect_enemies()
	sfx.beat.connect(hud.pulse_vignette)
	player.died.connect(_on_player_died)
	_play_entry_sequence()


func _play_entry_sequence() -> void:
	sfx.play_level_intro()

	# Format level title banner
	var path: String = GameState.current_level_path()
	var title_text := "TEST ARENA"
	if path.find("level_") != -1 and path.find("test") == -1:
		var num_str: String = path.get_file().get_basename().replace("level_", "")
		title_text = "DEPTH %s" % num_str.to_upper()
	elif GameState.current_level > 0:
		title_text = "DEPTH %02d" % GameState.current_level

	hud.play_level_intro(title_text)

	if "pulse_scale" in player:
		player.pulse_scale = 0.25
		var p_tw := create_tween()
		p_tw.tween_property(player, "pulse_scale", 1.35, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p_tw.tween_property(player, "pulse_scale", 1.0, 0.35).set_trans(Tween.TRANS_SINE)

	# Emit a safe visual-only awakening echo wave at 0.22s so the player sees their spawn surroundings
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(player) and is_instance_valid(echo_layer):
			var exclude: Array[RID] = [player.get_rid()]
			echo_layer.emit_echo(player.global_position, 220.0, exclude, true)
	)


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
	sfx.play_player_death()
	hud.flash_death()
	await get_tree().create_timer(0.55).timeout
	var killer_type: int = int(player.get("killed_by_type")) if "killed_by_type" in player else -1
	hud.show_death_screen(killer_type)
