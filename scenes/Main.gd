extends Node2D
## Game container: loads the current level, then wires the systems together.
## Supports LevelRoot tilemap levels with Water, Switch, Door, and Exit mechanisms.

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

# --- Level 0 Interactive Narrative State -------------------------------------
var _is_tutorial_level := false
var _tutorial_step := 0
var _tutorial_checkpoint := 0
var _tutorial_respawning := false
var _tutorial_beacon: Node2D = null
var _tutorial_sleeper: Enemy = null

class TutorialBeacon extends Node2D:
	var target_pos := Vector2.ZERO
	var beacon_label := ""
	var active := false
	var time := 0.0

	func _process(delta: float) -> void:
		if active:
			time += delta
			global_position = target_pos
			queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		var ring_wave := fposmod(time * 1.5, 1.0)
		var r_outer := 14.0 + ring_wave * 28.0
		var a_outer := (1.0 - ring_wave) * 0.75
		draw_arc(Vector2.ZERO, r_outer, 0.0, TAU, 36, Color(0.35, 0.90, 1.0, a_outer), 1.8)
		draw_circle(Vector2.ZERO, 6.0 + 2.0 * pulse, Color(0.2, 0.75, 1.0, 0.35 + 0.25 * pulse))
		draw_circle(Vector2.ZERO, 3.5, Color(0.9, 0.98, 1.0, 0.95))
		if beacon_label != "":
			draw_string(ThemeDB.fallback_font, Vector2(-60.0, -22.0), beacon_label, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.75, 0.96, 1.0, 0.95))



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
	if GameState.is_level_0_story_mode():
		_play_tutorial_level_0_sequence()
		return

	sfx.play_level_intro()

	# Format level title & evocative philosophical subtitle banner
	var cur_lvl: int = GameState.current_level
	var title_text: String = ""
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		title_text = GameState.get_level_name(cur_lvl + 1)
	else:
		title_text = GameState.get_level_name(cur_lvl)
	var subtitle_text: String = GameState.get_sector_log(cur_lvl)

	if _level_root != null:
		if _level_root.level_name != "" and _level_root.level_name != "UNTITLED" and _level_root.level_name != "未命名":
			title_text = _level_root.level_name
		if _level_root.hint != "":
			subtitle_text = _level_root.hint

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


func _set_tutorial_beacon(pos: Vector2, label: String) -> void:
	if _tutorial_beacon == null:
		_tutorial_beacon = TutorialBeacon.new()
		_tutorial_beacon.name = "TutorialBeacon"
		_tutorial_beacon.z_index = 25
		add_child(_tutorial_beacon)
	_tutorial_beacon.target_pos = pos
	_tutorial_beacon.beacon_label = label
	_tutorial_beacon.active = true
	_tutorial_beacon.visible = true


func _clear_tutorial_beacon() -> void:
	if _tutorial_beacon != null:
		_tutorial_beacon.active = false
		_tutorial_beacon.visible = false


func _play_tutorial_level_0_sequence() -> void:
	_is_tutorial_level = true
	_tutorial_step = 0
	_tutorial_checkpoint = 0
	_tutorial_respawning = false
	# Hide all gameplay HUD buttons initially
	if hud != null:
		hud.set_gameplay_buttons_visible(false)

	# Lock player movement and abilities initially
	if player != null:
		player.can_move = false
		player.can_sound = false
		player.can_sneak = false
		player.can_pebble = false
		player.modulate.a = 0.0
		if player.mic != null:
			player.mic.enabled = false

	# Hold on complete black for ~1.0 second in pure darkness and dead silence, then begin story
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_level_0_story_step_1)


func _level_0_story_step_1() -> void:
	if hud == null or hud.story_overlay == null:
		return
	hud.story_overlay.play_sequence([
		"Total darkness surrounds you.",
		"You try to call into the void."
	], _level_0_prompt_sound_button)


func _level_0_prompt_sound_button() -> void:
	# Reveal player light dot in the darkness and unlock sound/Space
	if player != null:
		player.can_sound = true
		var p_tw := create_tween()
		p_tw.tween_property(player, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var sound_btn := hud.get_node_or_null("SoundBtn") as Button
	if sound_btn == null:
		return

	# Reveal and beacon the dedicated sound button
	sound_btn.visible = true
	sound_btn.modulate.a = 0.0
	sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	sound_btn.set("tutorial_pulse", true)

	var tw := create_tween()
	tw.tween_property(sound_btn, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Listen for single voice sound emission via member Callable
	if is_instance_valid(player):
		if not player.sound_emitted.is_connected(_on_tutorial_sound_emitted):
			player.sound_emitted.connect(_on_tutorial_sound_emitted)


func _on_tutorial_sound_emitted(_pos: Vector2, _loudness: float, is_voice: bool, _is_sneak: bool = false) -> void:
	if not is_voice:
		return
	if is_instance_valid(player):
		player.can_sound = false
		if player.sound_emitted.is_connected(_on_tutorial_sound_emitted):
			player.sound_emitted.disconnect(_on_tutorial_sound_emitted)

	var sound_btn := hud.get_node_or_null("SoundBtn") as Button
	if sound_btn != null:
		sound_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sound_btn.set("tutorial_pulse", false)
		var b_tw := create_tween()
		b_tw.tween_interval(0.35)
		b_tw.tween_property(sound_btn, "modulate:a", 0.0, 0.4)
		b_tw.tween_callback(func(): sound_btn.visible = false)

	# Wait for sound wave and wall echoes to disperse into dead silence (total ~3.0s)
	get_tree().create_timer(3.0).timeout.connect(_level_0_story_step_2)


func _level_0_story_step_2() -> void:
	if hud == null or hud.story_overlay == null:
		return
	hud.story_overlay.play_sequence([
		"No one answers...",
		"Only your own echo returns.",
		"You must move forward."
	], _level_0_start_movement_teaching)


func _level_0_start_movement_teaching() -> void:
	if player != null:
		player.can_move = true
	_tutorial_step = 1
	_set_tutorial_beacon(Vector2(260.0, 144.0), "MOVE")


func _level_0_reached_first_marker() -> void:
	_clear_tutorial_beacon()
	_tutorial_step = 2
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Through the echoes, you sense an enclosed cavern.",
			"A dark pool of water blocks the way ahead."
		], func():
			if player != null:
				player.can_move = true
			_set_tutorial_beacon(Vector2(432.0, 144.0), "WATER")
			_tutorial_step = 3
		)


func _level_0_reached_water_edge() -> void:
	_clear_tutorial_beacon()
	_tutorial_step = 4
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	if sfx != null:
		sfx.play_sleeper_snore(Vector2(720.0, 208.0))

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"A guttural breathing rumbles from the other side.",
			"A presence that does not belong in the light..."
		], func():
			if player != null:
				player.can_move = true
			_tutorial_step = 5 # Waiting for player to wade into water
		)


func _level_0_trigger_chase() -> void:
	_tutorial_step = 6
	_clear_tutorial_beacon()
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO
		player.set_meta("tutorial_invulnerable", true)
		player.camera_shake(0.5, 6.0)

	if sfx != null:
		sfx.play_screamer_shriek(Vector2(720.0, 208.0))
	if hud != null:
		hud.flash_threat(1.2)

	# Wake up Sleeper but keep it frozen in roaring shock during dialogue (cinematic time-stop)
	var sleeper := get_tree().get_first_node_in_group("enemy") as Enemy
	if sleeper != null and is_instance_valid(sleeper):
		_tutorial_sleeper = sleeper
		sleeper.chase_speed = 105.0
		sleeper.state = Enemy.State.ALERT
		sleeper.alert_time = 999.0
		sleeper.velocity = Vector2.ZERO
		sleeper.reveal(1.0)

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"The splash echoed too loudly!",
			"IT HEARD YOU. RUN!"
		], func():
			# Time-stop ends: Sleeper charges, player flees
			if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
				_tutorial_sleeper.alert_time = 0.2
				if player != null:
					_tutorial_sleeper.force_alert_to(player.global_position)
			if player != null:
				player.can_move = true
			_set_tutorial_beacon(Vector2(120.0, 144.0), "RETREAT!")
			_tutorial_step = 7 # Chase active, player fleeing to x <= 200
		)


func _level_0_retreat_safe() -> void:
	_tutorial_step = 8
	_clear_tutorial_beacon()
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO
		player.set_meta("tutorial_invulnerable", false)

	# Sleeper drops aggro at the water line and turns into a slow patroller
	if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
		_tutorial_sleeper.chase_speed = 135.0
		_tutorial_sleeper.patrol_speed = 65.0
		_tutorial_sleeper.enemy_type = Enemy.EnemyType.PATROLLER
		_tutorial_sleeper.patrol_points = [Vector2(624.0, 208.0), Vector2(768.0, 208.0)]
		_tutorial_sleeper.state = Enemy.State.PATROL
		_tutorial_sleeper.target = Vector2(624.0, 208.0)

	if hud != null:
		hud.reset_vignette(0.5)

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"You barely escaped into the darkness.",
			"Exhaustion overwhelms you..."
		], _level_0_slumber_sequence)


func _create_blackout_curtain() -> ColorRect:
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color.BLACK
	curtain.modulate.a = 0.0
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud != null:
		hud.add_child(curtain)
		if hud.story_overlay != null:
			hud.story_overlay.z_index = 100
			hud.move_child(curtain, hud.story_overlay.get_index())
	else:
		add_child(curtain)
	return curtain


func _level_0_slumber_sequence() -> void:
	if hud != null:
		hud.reset_vignette(0.3)
	# Dream / Inner monologue on pure black
	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"In the cold silence, a voice within speaks...",
			"To surrender to the dark is worse than death."
		], func():
			# Reposition standing before the water pool
			if player != null:
				player.global_position = Vector2(432.0, 144.0)
				player.velocity = Vector2.ZERO
				player.can_move = false

			_tutorial_checkpoint = 1

			if sfx != null:
				sfx.play_enemy_step(Vector2(650.0, 208.0), false, true)

			hud.story_overlay.play_sequence([
				"It paces the passage on the other side.",
				"Walk softly. Water amplifies every sound."
			], func():
				# Unlock Sneak Button and start stealth crossing
				_tutorial_step = 9
				if player != null:
					player.can_move = true
					player.can_sneak = true
					player.can_sound = false
					player.can_pebble = false
				var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
				if sneak_btn != null:
					sneak_btn.visible = true
					sneak_btn.set("tutorial_pulse", true)
				# Clear guide beacon showing the way out through Room 2
				_set_tutorial_beacon(Vector2(912.0, 144.0), "WAY OUT")
			)
		)


func _seal_room_2_passage() -> void:
	if _level_root == null or _level_root.walls == null:
		return
	for x in range(25, 29):
		_level_root.walls.set_cell(Vector2i(x, 4), 0, Vector2i(0, 0))
	_echo_features_dirty = true


func _level_0_enter_room_3() -> void:
	_tutorial_checkpoint = 2
	_tutorial_step = 10
	_clear_tutorial_beacon()

	if player != null:
		player.can_move = false
		player.can_sound = false
		player.can_pebble = false
		player.velocity = Vector2.ZERO
		if player.sneaking:
			player.sneaking = false
			player.queue_redraw()

	var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
	if sneak_btn != null:
		sneak_btn.set("tutorial_pulse", false)

	# 1. Physically seal passage behind player with solid stone barrier
	_seal_room_2_passage()

	# 2. Safely neutralize Sleeper so it cannot detect or pursue from Room 2
	if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
		_tutorial_sleeper.state = Enemy.State.SLEEP
		_tutorial_sleeper.velocity = Vector2.ZERO
		_tutorial_sleeper.alert_time = 0.0

	# 3. Ensure threat vignette is completely reset to calm abyss
	if hud != null:
		hud.reset_vignette(0.3)

	# 4. Audio & tactile impact for the falling stone barrier
	if sfx != null:
		sfx.play_door_open(Vector2(864.0, 144.0))
	if player != null:
		player.camera_shake(0.35, 4.0)

	# 5. Narrative: Sealed passage
	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Fallen stone crashes down, sealing the passage behind you.",
			"There is no going back."
		], func():
			if player != null:
				player.can_move = true
			_set_tutorial_beacon(Vector2(1040.0, 144.0), "INVESTIGATE")
		)


func _level_0_prompt_charge_sound() -> void:
	_clear_tutorial_beacon()
	_tutorial_step = 11

	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	if sfx != null:
		sfx.play_assist_toggle(true)

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Ahead, an ancient resonator key rests in stillness.",
			"A gentle sound will not wake it.",
			"Hold [SOUND] or [SPACE] to unleash a resonant surge!"
		], func():
			var sound_btn := hud.get_node_or_null("SoundBtn") as Button
			if sound_btn != null:
				sound_btn.visible = true
				sound_btn.modulate.a = 1.0 # Fully visible and opaque!
				sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP
				sound_btn.set("tutorial_pulse", true)
				sound_btn.set("tutorial_hold_mode", true)

			_set_tutorial_beacon(Vector2(1104.0, 144.0), "RESONATE")

			if is_instance_valid(player):
				player.can_move = true
				player.can_sound = true
				if not player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
					player.sound_emitted.connect(_on_tutorial_charge_emitted)
		)


func _on_tutorial_charge_emitted(_pos: Vector2, loudness: float, is_voice: bool, _is_sneak: bool = false) -> void:
	if not is_voice or loudness < 0.55:
		return
	if is_instance_valid(player) and player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
		player.sound_emitted.disconnect(_on_tutorial_charge_emitted)

	var sound_btn := hud.get_node_or_null("SoundBtn") as Button
	if sound_btn != null:
		sound_btn.set("tutorial_pulse", false)
		sound_btn.set("tutorial_hold_mode", false)
		sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	if sfx != null:
		sfx.play_assist_toggle(true)

	_clear_tutorial_beacon()

	get_tree().create_timer(1.2).timeout.connect(func():
		if hud != null and hud.story_overlay != null:
			hud.story_overlay.play_sequence([
				"The resonator key awakened!",
				"Step on it to unseal the stone gate."
			], func():
				_tutorial_step = 12
				if player != null:
					player.can_move = true
				_set_tutorial_beacon(Vector2(1104.0, 144.0), "KEY")
			)
	)


func _level_0_key_activated() -> void:
	_clear_tutorial_beacon()
	_tutorial_step = 13
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"The ancient stone gate dissolves open.",
			"The path upward is clear."
		], func():
			_tutorial_step = 14
			if player != null:
				player.can_move = true
			_set_tutorial_beacon(Vector2(1488.0, 144.0), "ASCENT")
		)


func _level_0_cinematic_exit() -> void:
	_changing = true
	_clear_tutorial_beacon()
	if is_instance_valid(player):
		player.can_move = false
		player.velocity = Vector2.ZERO

	if sfx != null:
		sfx.play_level_exit()

	GameState.mark_story_tutorial_completed()
	GameState.complete_level(1)

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Stone stairs wind upward into the dark.",
			"Step by step, you begin the ascent.",
			"Hoping this path leads out of the abyss..."
		], func():
			GameState.go_to_level_select()
		)


func _level_0_physics_process(_delta: float) -> void:
	if not _is_tutorial_level or not is_instance_valid(player):
		return
	var px: float = player.global_position.x

	match _tutorial_step:
		1:
			if px >= 235.0:
				_level_0_reached_first_marker()
		3:
			if px >= 415.0:
				_level_0_reached_water_edge()
		5:
			if px >= 485.0:
				_level_0_trigger_chase()
		7:
			if px <= 200.0:
				_level_0_retreat_safe()
		9:
			if player.sneaking:
				var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
				if sneak_btn != null and sneak_btn.get("tutorial_pulse"):
					sneak_btn.set("tutorial_pulse", false)
			if px >= 912.0:
				_level_0_enter_room_3()
		10:
			if px >= 1020.0:
				_level_0_prompt_charge_sound()
		14:
			if px >= 1470.0:
				_level_0_cinematic_exit()



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

	if _is_tutorial_level:
		_level_0_physics_process(delta)

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Enemy and is_instance_valid(enemy):
			var ec: Vector2i = _level_root.walls.local_to_map(_level_root.walls.to_local(enemy.global_position))
			enemy.is_in_water = water_cells.has(ec)

	if switch_cells.has(c) and not pressed.has(c):
		_press_switch(c)
	if has_exit and c == exit_cell and not is_exit_locked():
		if _is_tutorial_level:
			_level_0_cinematic_exit()
			return
		_changing = true
		var level_num: int = GameState.current_level + 1
		var debrief_data := GameState.record_level_clear(
			level_num,
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
		if str(switch_cells[c]).strip_edges().to_lower() == "exit" and not pressed.has(c):
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

	# Text-defined levels can flag monsters with `wake=<switch id>`: stepping on that switch alerts them
	if player != null and is_instance_valid(player):
		for node in get_tree().get_nodes_in_group("enemy"):
			var sleeper_enemy := node as Enemy
			if sleeper_enemy != null and is_instance_valid(sleeper_enemy) and str(sleeper_enemy.get_meta("wake_on", "")).to_upper() == id:
				sleeper_enemy.force_alert_to(player.global_position)

	if _is_tutorial_level and _tutorial_step == 12:
		_level_0_key_activated()


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
	if _is_tutorial_level and _tutorial_checkpoint > 0:
		_handle_tutorial_checkpoint_respawn()
		return
	await get_tree().create_timer(0.55).timeout
	var killer_type: int = int(player.get("killed_by_type")) if "killed_by_type" in player else -1
	hud.show_death_screen(killer_type)


func _handle_tutorial_checkpoint_respawn() -> void:
	if _tutorial_respawning:
		return
	_tutorial_respawning = true

	var curtain := _create_blackout_curtain()
	var c_tw := curtain.create_tween()
	c_tw.tween_property(curtain, "modulate:a", 1.0, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_interval(0.35)
	c_tw.tween_callback(func():
		if hud != null:
			hud.reset_vignette(0.2)

		var respawn_pos: Vector2
		if _tutorial_checkpoint == 1:
			respawn_pos = Vector2(432.0, 144.0)
			_tutorial_step = 9
			# Reset Sleeper to patrol state in Room 2
			if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
				_tutorial_sleeper.global_position = Vector2(720.0, 208.0)
				_tutorial_sleeper.enemy_type = Enemy.EnemyType.PATROLLER
				_tutorial_sleeper.chase_speed = 135.0
				_tutorial_sleeper.patrol_speed = 65.0
				_tutorial_sleeper.patrol_points = [Vector2(624.0, 208.0), Vector2(768.0, 208.0)]
				_tutorial_sleeper.state = Enemy.State.PATROL
				_tutorial_sleeper.target = Vector2(624.0, 208.0)
				_tutorial_sleeper.velocity = Vector2.ZERO
				_tutorial_sleeper.alert_time = 0.0
				_tutorial_sleeper.reveal(0.0)
			# Ensure Sneak button is visible & enabled
			var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
			if sneak_btn != null:
				sneak_btn.visible = true
				sneak_btn.set("tutorial_pulse", true)
			_set_tutorial_beacon(Vector2(912.0, 144.0), "WAY OUT")
		else:
			respawn_pos = Vector2(980.0, 144.0)
			_seal_room_2_passage()
			if _tutorial_step <= 11:
				_tutorial_step = 11
				var sound_btn := hud.get_node_or_null("SoundBtn") as Button
				if sound_btn != null:
					sound_btn.visible = true
					sound_btn.modulate.a = 1.0
					sound_btn.set("tutorial_pulse", true)
					sound_btn.set("tutorial_hold_mode", true)
					sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP
				_set_tutorial_beacon(Vector2(1104.0, 144.0), "RESONATE")
				if is_instance_valid(player) and not player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
					player.sound_emitted.connect(_on_tutorial_charge_emitted)
			elif _tutorial_step == 12 or _tutorial_step == 13:
				_tutorial_step = 12
				_set_tutorial_beacon(Vector2(1104.0, 144.0), "KEY")
			else:
				_tutorial_step = 14
				_set_tutorial_beacon(Vector2(1488.0, 144.0), "ASCENT")

		if is_instance_valid(player):
			player.reset(respawn_pos)
			player.can_move = true
			player.can_pebble = false
			player.can_sneak = true
			player.can_sound = (_tutorial_checkpoint == 2)
			player.modulate.a = 1.0

		var f_tw := curtain.create_tween()
		f_tw.tween_property(curtain, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		f_tw.tween_callback(func():
			curtain.queue_free()
			_tutorial_respawning = false
		)
	)
