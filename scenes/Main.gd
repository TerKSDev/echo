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
var note_cells: Dictionary = {}   # Vector2i -> String
var _read_notes_this_run: Dictionary = {} # Vector2i -> bool
var _temp_note_markers: Array[Vector2i] = []
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
	var player_ref: Node2D = null

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

		# Draw subtle directional guide chevrons near the player when the beacon is far away
		if player_ref != null and is_instance_valid(player_ref):
			var to_beacon: Vector2 = target_pos - player_ref.global_position
			var dist: float = to_beacon.length()
			if dist > 145.0:
				var dir: Vector2 = to_beacon / dist
				var perp: Vector2 = dir.orthogonal()
				var p_local: Vector2 = to_local(player_ref.global_position)
				for i in range(3):
					var wave_phase: float = fposmod(time * 2.4 - float(i) * 0.28, 1.0)
					var chev_alpha: float = sin(wave_phase * PI) * 0.65
					var tip: Vector2 = p_local + dir * (44.0 + float(i) * 18.0)
					var wing_a: Vector2 = tip - dir * 6.0 + perp * 5.5
					var wing_b: Vector2 = tip - dir * 6.0 - perp * 5.5
					var c_col := Color(0.40, 0.92, 1.0, chev_alpha)
					draw_line(wing_a, tip, c_col, 1.8)
					draw_line(wing_b, tip, c_col, 1.8)



func _ready() -> void:
	if GameState.current_mode == GameState.GameMode.CHALLENGE and GameState.current_level == 0:
		if not ChallengeModifiers.is_milestone_claimed(1):
			ChallengeModifiers.reset_challenge_run()

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
			if not enemy.screamed.is_connected(_on_enemy_alert):
				enemy.screamed.connect(func(_p, _r): _on_enemy_alert(enemy))
			if not enemy.alarmed.is_connected(_on_enemy_alert):
				enemy.alarmed.connect(func(_p, _t): _on_enemy_alert(enemy))


func _on_enemy_alert(enemy: Enemy) -> void:
	if not _changing:
		if enemy != null and is_instance_valid(enemy):
			# Ghost rating is only penalized by direct player noise (shout, steps, water splash, proximity)
			if "alert_caused_by_player" in enemy and not enemy.alert_caused_by_player:
				return
			if enemy.is_investigating_decoy:
				return
			if enemy.get_meta("scripted_wake", false) == true:
				enemy.set_meta("scripted_wake", false)
				return
			# Debounce: avoid counting repeated rapid triggers on the same enemy
			var now_msec := Time.get_ticks_msec()
			var last_alert_msec: int = int(enemy.get_meta("last_alert_msec", 0))
			if now_msec - last_alert_msec < 600:
				return
			enemy.set_meta("last_alert_msec", now_msec)

		_enemies_alerted += 1
		if is_instance_valid(player) and player.has_method("trigger_terror_shiver"):
			player.trigger_terror_shiver(3.0)


func _play_entry_sequence() -> void:
	if GameState.is_level_0_story_mode():
		_play_tutorial_level_0_sequence()
		return

	sfx.play_level_intro()

	# Format level title & evocative philosophical subtitle banner
	var cur_lvl: int = GameState.current_level
	var title_text: String = ""
	var subtitle_text: String = ""

	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		title_text = GameState.get_level_name(cur_lvl)
		if _level_root != null and _level_root.hint != "":
			subtitle_text = _level_root.hint
		else:
			subtitle_text = "Listen closely. The deepest chasm awaits."
	else:
		title_text = GameState.get_level_name(cur_lvl)
		subtitle_text = GameState.get_sector_log(cur_lvl)

	if title_text == "" and _level_root != null:
		if _level_root.level_name != "" and _level_root.level_name != "UNTITLED" and _level_root.level_name != "UNNAMED":
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
			var exclude: Array = [player.get_rid()]
			var w_col: Color = GameState.get_sonar_color()
			echo_layer.emit_echo(player.global_position, 220.0, exclude, true, w_col)
			if "pulse_scale" in player:
				player.pulse_scale = 1.25
			if "_burst_radius" in player:
				player._burst_radius = 8.0
				player._burst_alpha = 0.65
				player.queue_redraw()
			if sfx != null:
				sfx.play_echo_ping(0.28)
			if GameState.blind_assist_mode and player.has_method("_emit_wall_echos"):
				player._emit_wall_echos(0.35)
	)


func _set_tutorial_beacon(pos: Vector2, label: String) -> void:
	if _tutorial_beacon == null:
		_tutorial_beacon = TutorialBeacon.new()
		_tutorial_beacon.name = "TutorialBeacon"
		_tutorial_beacon.z_index = 25
		add_child(_tutorial_beacon)
	_tutorial_beacon.player_ref = player
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
		if player.mic != null:
			player.mic.enabled = false

	# Play cinematic waking-up sequence (blinking eyelids, blurry double-vision to focus, slowly rising from the ground)
	if hud != null:
		hud.play_wake_up_sequence(player, sfx, _level_0_story_step_1)
	else:
		_level_0_story_step_1()


func _level_0_story_step_1() -> void:
	if hud == null or hud.story_overlay == null:
		return
	hud.story_overlay.play_sequence([
		"Total darkness surrounds you.",
		"You try to call into the void."
	], _level_0_prompt_sound_button, false)


func _level_0_prompt_sound_button() -> void:
	# Unlock sound/Space
	if player != null:
		player.can_sound = true

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

	if hud != null:
		var title: String = "TAP [SOUND] BUTTON" if GameState.is_touch_or_mobile() else "TAP [SPACE] OR [SOUND]"
		hud.show_tutorial_callout(0, title, "Emit a sound wave to illuminate the dark")

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

	if hud != null:
		hud.hide_tutorial_callout()

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
	], _level_0_start_movement_teaching, false)


func _level_0_start_movement_teaching() -> void:
	if player != null:
		player.can_move = true
	_tutorial_step = 1
	_set_tutorial_beacon(Vector2(456.0, 144.0), "EXPLORE")
	if hud != null:
		var title: String = "TOUCH & DRAG TO MOVE" if GameState.is_touch_or_mobile() else "[WASD] / ARROW KEYS"
		var sub: String = "Slide anywhere to guide your explorer" if GameState.is_touch_or_mobile() else "Or touch & drag anywhere to move"
		hud.show_tutorial_callout(2, title, sub)


func _level_0_reached_water_edge() -> void:
	_clear_tutorial_beacon()
	if hud != null:
		hud.hide_tutorial_callout()
	_tutorial_step = 4
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	# Visually reveal the water pool ahead and the sleeping beast's rhythmic breathing across the pool
	if is_instance_valid(echo_layer):
		echo_layer.emit_echo(Vector2(544.0, 144.0), 145.0, [], false)
		echo_layer.emit_echo(Vector2(720.0, 208.0), 125.0, [], false)

	if sfx != null:
		sfx.play_sleeper_snore(Vector2(720.0, 208.0))

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Through the echoes, a dark pool of water blocks the way ahead.",
			"From the far shore, a guttural breathing rumbles in the dark..."
		], func():
			if player != null:
				player.can_move = true
			_set_tutorial_beacon(Vector2(620.0, 144.0), "CROSS")
			_tutorial_step = 5 # Waiting for player to wade into water
		, false)


func _level_0_trigger_chase() -> void:
	_tutorial_step = 7
	_clear_tutorial_beacon()

	# Emit an unmistakable loud water splash wave from the player's feet so cause-and-effect is 100% clear
	if player != null and player.has_method("make_sound"):
		player.make_sound(0.55, false, false)

	if hud != null:
		hud.hide_tutorial_callout()
		hud.flash_threat(1.2)
		hud.show_tutorial_callout(2, "THE SPLASH WOKE IT! RUN!", "Retreat left into the narrow passage!")

	if player != null:
		player.set_meta("tutorial_invulnerable", true)
		player.camera_shake(0.5, 6.0)

	if sfx != null:
		sfx.play_monster_roar(Vector2(720.0, 208.0), 0)

	var sleeper := get_tree().get_first_node_in_group("enemy") as Enemy
	if sleeper != null and is_instance_valid(sleeper):
		_tutorial_sleeper = sleeper
		sleeper.chase_speed = 105.0
		sleeper.state = Enemy.State.ALERT
		sleeper.alert_time = 0.65
		sleeper.reveal(1.0)
		sleeper.set_meta("scripted_wake", true)
		if player != null:
			sleeper.force_alert_to(player.global_position)

	_set_tutorial_beacon(Vector2(180.0, 144.0), "RETREAT!")


func _level_0_retreat_safe() -> void:
	_tutorial_step = 8
	_clear_tutorial_beacon()
	if hud != null:
		hud.hide_tutorial_callout()
	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO
		player.set_meta("tutorial_invulnerable", false)

	# Sleeper loses the acoustic trail in the dark corridor and smoothly returns to its alcove to sleep
	if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
		_tutorial_sleeper.state = Enemy.State.RETURN
		_tutorial_sleeper.target = Vector2(720.0, 208.0)
		_tutorial_sleeper.home = Vector2(720.0, 208.0)
		_tutorial_sleeper.velocity = Vector2.ZERO
		var s_tw := create_tween()
		s_tw.tween_property(_tutorial_sleeper, "global_position", Vector2(720.0, 208.0), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		s_tw.tween_callback(func():
			if is_instance_valid(_tutorial_sleeper):
				_tutorial_sleeper.state = Enemy.State.SLEEP
				_tutorial_sleeper.velocity = Vector2.ZERO
				_tutorial_sleeper.alert_time = 0.85
		)

	if hud != null:
		hud.reset_vignette(0.6)

	if sfx != null:
		sfx.play_sleeper_snore(Vector2(720.0, 208.0))

	# Cohesive narrative: the beast settles down, player learns that enemies are blind and water amplifies sound
	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"You barely escaped into the narrow stone passage.",
			"Blind in the dark, the beast hunts only by sound—and slips back into slumber.",
			"Water amplifies every footstep. Tread softly to cross unheard."
		], func():
			_tutorial_checkpoint = 1
			_tutorial_step = 9
			if player != null:
				player.can_move = true
				player.can_sneak = true
				player.can_sound = false
				player.can_pebble = false

			var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
			if sneak_btn != null:
				sneak_btn.visible = true
				sneak_btn.modulate.a = 1.0
				sneak_btn.set("tutorial_pulse", true)

			if hud != null:
				var title: String
				if GameState.sneak_hold_mode:
					title = "HOLD [SNEAK] BUTTON" if GameState.is_touch_or_mobile() else "HOLD [SHIFT] OR [SNEAK]"
				else:
					title = "TAP [SNEAK] BUTTON" if GameState.is_touch_or_mobile() else "PRESS [SHIFT] OR [SNEAK]"
				hud.show_tutorial_callout(1, title, "Move silently to cross the water without waking it")

			_set_tutorial_beacon(Vector2(560.0, 144.0), "SNEAK ACROSS")
		, false)


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


func _seal_room_2_passage() -> void:
	if _level_root == null or _level_root.walls == null:
		return
	for x in range(25, 29):
		_level_root.walls.set_cell(Vector2i(x, 4), 0, Vector2i(0, 0))
	_echo_features_dirty = true


func _level_0_enter_room_3() -> void:
	_tutorial_checkpoint = 2
	_tutorial_step = 11
	_clear_tutorial_beacon()
	if hud != null:
		hud.hide_tutorial_callout()

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

	# 4. Audio, tactile & visual echo impact for the falling stone barrier + faint key shimmer ahead
	if sfx != null:
		sfx.play_door_open(Vector2(864.0, 144.0))
	if player != null:
		player.camera_shake(0.35, 4.0)
	if is_instance_valid(echo_layer):
		echo_layer.emit_echo(Vector2(864.0, 144.0), 220.0, [], false)
		echo_layer.emit_echo(Vector2(1104.0, 144.0), 120.0, [], false)

	# 5. Unified Narrative: Sealed passage & sensing the dormant resonator key ahead
	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"Fallen stone crashes down, sealing the passage behind you.",
			"Ahead in the dark, an ancient resonator key hums faintly.",
			"A weak call cannot wake it. Hold to unleash a full echo."
		], _level_0_activate_charge_prompt, false)
	else:
		_level_0_activate_charge_prompt()


func _level_0_activate_charge_prompt() -> void:
	_tutorial_step = 11
	if sfx != null:
		sfx.play_assist_toggle(true)

	var sound_btn := hud.get_node_or_null("SoundBtn") as Button
	if sound_btn != null:
		sound_btn.visible = true
		sound_btn.modulate.a = 1.0
		sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		sound_btn.set("tutorial_pulse", true)
		sound_btn.set("tutorial_hold_mode", true)

	if hud != null:
		var title: String = "HOLD [SOUND] BUTTON" if GameState.is_touch_or_mobile() else "HOLD [SPACE] OR [SOUND]"
		hud.show_tutorial_callout(0, title, "Hold until full charge, then release to awaken the key")

	_set_tutorial_beacon(Vector2(1104.0, 144.0), "RESONATE")

	if is_instance_valid(player):
		player.can_move = false
		player.can_sound = true
		if not player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
			player.sound_emitted.connect(_on_tutorial_charge_emitted)


func _on_tutorial_charge_emitted(_pos: Vector2, loudness: float, is_voice: bool, _is_sneak: bool = false) -> void:
	if not is_voice or loudness < 0.55:
		return
	if is_instance_valid(player) and player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
		player.sound_emitted.disconnect(_on_tutorial_charge_emitted)

	if hud != null:
		hud.hide_tutorial_callout()

	var sound_btn := hud.get_node_or_null("SoundBtn") as Button
	if sound_btn != null:
		sound_btn.set("tutorial_pulse", false)
		sound_btn.set("tutorial_hold_mode", false)
		sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	if sfx != null:
		sfx.play_assist_toggle(true)
	if is_instance_valid(echo_layer):
		echo_layer.emit_echo(Vector2(1104.0, 144.0), 210.0, [], false)

	_clear_tutorial_beacon()

	get_tree().create_timer(0.85).timeout.connect(func():
		_tutorial_step = 12
		if is_instance_valid(player):
			player.can_move = true
		_set_tutorial_beacon(Vector2(1104.0, 144.0), "TOUCH KEY")
	)


func _level_0_key_activated() -> void:
	if _tutorial_step >= 13:
		return
	_tutorial_step = 13
	_clear_tutorial_beacon()
	if hud != null:
		hud.hide_tutorial_callout()

	var key_cell := Vector2i(34, 4)
	if switch_cells.has(key_cell) and not pressed.has(key_cell):
		pressed[key_cell] = true
		_echo_features_dirty = true

	if player != null:
		player.can_move = false
		player.velocity = Vector2.ZERO

	if sfx != null:
		sfx.play_door_open(Vector2(1264.0, 144.0))
	if is_instance_valid(echo_layer):
		echo_layer.emit_echo(Vector2(1264.0, 144.0), 260.0, [], false)

	# Ensure door 'A' opens visually and functionally
	for body in door_nodes.get("A", []):
		if is_instance_valid(body) and not body.has_meta("open"):
			body.set_meta("open", true)
			var tw := create_tween()
			tw.tween_property(body, "modulate:a", 0.0, 0.45)
			tw.tween_callback(func():
				if is_instance_valid(body):
					body.process_mode = Node.PROCESS_MODE_DISABLED
					body.visible = false
			)

	if hud != null and hud.story_overlay != null:
		hud.story_overlay.play_sequence([
			"The ancient stone gate dissolves open.",
			"The path upward is clear."
		], func():
			_tutorial_step = 14
			if player != null:
				player.can_move = true
				player.can_sound = true
				player.can_sneak = true
			_set_tutorial_beacon(Vector2(1488.0, 144.0), "ASCENT")
		, false)
	else:
		_tutorial_step = 14
		if player != null:
			player.can_move = true
			player.can_sound = true
			player.can_sneak = true
		_set_tutorial_beacon(Vector2(1488.0, 144.0), "ASCENT")


func _level_0_cinematic_exit() -> void:
	_changing = true
	_clear_tutorial_beacon()
	if hud != null:
		hud.hide_tutorial_callout()
		hud.set_gameplay_buttons_visible(false)
	if is_instance_valid(player):
		player.can_move = false
		player.can_sound = false
		player.can_sneak = false
		player.can_pebble = false
		player.velocity = Vector2.ZERO
		if player.has_node("MicInput"):
			var mic = player.get_node("MicInput")
			if mic != null and mic.has_method("suppress"):
				mic.suppress(9999.0)

	if sfx != null:
		sfx.play_level_exit()

	GameState.mark_story_tutorial_completed()
	GameState.complete_level(1)

	if not GameState.has_seen_act_milestone(0):
		GameState.mark_act_milestone_seen(0)
		if hud != null and hud.story_overlay != null:
			hud.story_overlay.play_sequence([
				"Stone stairs wind upward into the dark.",
				"Step by step, you begin the ascent.",
				"Hoping this path leads out of the abyss..."
			], func():
				GameState.go_to_level_select()
			, true, "", "", 0.95)
			return

	GameState.go_to_level_select()


func _level_0_physics_process(_delta: float) -> void:
	if not _is_tutorial_level or not is_instance_valid(player):
		return
	var px: float = player.global_position.x

	match _tutorial_step:
		1:
			if px >= 240.0 and hud != null:
				hud.hide_tutorial_callout()
			if px >= 448.0:
				_level_0_reached_water_edge()
		5:
			if px >= 532.0:
				_level_0_trigger_chase()
		7:
			if px <= 210.0:
				_level_0_retreat_safe()
		9:
			if player.sneaking:
				var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
				if sneak_btn != null and sneak_btn.get("tutorial_pulse"):
					sneak_btn.set("tutorial_pulse", false)
				if hud != null:
					hud.hide_tutorial_callout()
			elif _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper) and _tutorial_sleeper.state != Enemy.State.SLEEP and px <= 210.0:
				# Player retreated again after waking it: Sleeper loses sound and smoothly returns to sleep
				_tutorial_sleeper.state = Enemy.State.RETURN
				_tutorial_sleeper.target = Vector2(720.0, 208.0)
				_tutorial_sleeper.home = Vector2(720.0, 208.0)
				_tutorial_sleeper.velocity = Vector2.ZERO
				var s_tw := create_tween()
				s_tw.tween_property(_tutorial_sleeper, "global_position", Vector2(720.0, 208.0), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				s_tw.tween_callback(func():
					if is_instance_valid(_tutorial_sleeper):
						_tutorial_sleeper.state = Enemy.State.SLEEP
						_tutorial_sleeper.velocity = Vector2.ZERO
				)
				if hud != null:
					hud.reset_vignette(0.5)
			if px >= 540.0 and _tutorial_beacon != null and _tutorial_beacon.beacon_label == "SNEAK ACROSS":
				_set_tutorial_beacon(Vector2(940.0, 144.0), "PASSAGE")
			if px >= 936.0:
				_level_0_enter_room_3()
		12:
			if player.global_position.distance_to(Vector2(1104.0, 144.0)) <= 26.0:
				_level_0_key_activated()
		14:
			if px >= 1470.0:
				_level_0_cinematic_exit()



func _load_level(path: String) -> void:
	water_cells.clear()
	switch_cells.clear()
	door_nodes.clear()
	pressed.clear()
	note_cells.clear()
	_read_notes_this_run.clear()
	_temp_note_markers.clear()
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
			LevelMarker.Kind.NOTE:
				if GameState.current_mode == GameState.GameMode.STORY:
					_temp_note_markers.append(cell)

	if GameState.current_mode == GameState.GameMode.STORY and _temp_note_markers.size() > 0:
		_temp_note_markers.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		var cur_lvl: int = GameState.current_level
		for idx in range(_temp_note_markers.size()):
			var mcell: Vector2i = _temp_note_markers[idx]
			var nid := "L%02d_%d" % [cur_lvl, idx + 1]
			if not GameState.LORE_NOTES.has(nid):
				nid = "L%02d_1" % cur_lvl
			# Only place notes that haven't been collected yet; once collected, permanently gone
			if not GameState.is_note_collected(nid):
				note_cells[mcell] = nid


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
	if "alive" in player and not player.alive:
		return

	_level_time += delta

	# Periodic spatial exit beacon pulse only when approaching the exit zone (< 380px)
	if has_exit and not _changing and is_instance_valid(player) and player.alive:
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
	if note_cells.has(c) and not _read_notes_this_run.has(c):
		_trigger_read_note(c)
	if has_exit and c == exit_cell and not is_exit_locked():
		if _is_tutorial_level:
			_level_0_cinematic_exit()
			return
		_play_level_clear_sequence()


func _play_level_clear_sequence() -> void:
	_changing = true
	var cur_sector: int = GameState.current_level
	var level_num: int = cur_sector + 1

	# 1. Freeze player controls immediately and hide gameplay buttons
	if hud != null:
		hud.set_gameplay_buttons_visible(false)
	if is_instance_valid(player):
		player.can_move = false
		player.can_sound = false
		player.can_sneak = false
		player.can_pebble = false
		player.velocity = Vector2.ZERO
		player.set_deferred("collision_layer", 0)
		player.set_deferred("collision_mask", 0)
		if player.has_node("CollisionShape2D"):
			var col := player.get_node("CollisionShape2D") as CollisionShape2D
			if col != null:
				col.set_deferred("disabled", true)
		if player.has_node("MicInput"):
			var mic = player.get_node("MicInput")
			if mic != null and mic.has_method("suppress"):
				mic.suppress(9999.0)

	# 1b. Immediately pacify/disable all enemies so they cease chasing or attacking
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e != null and is_instance_valid(e):
			e.velocity = Vector2.ZERO
			e.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

	# 2. Play ascension / level exit chime
	if sfx != null:
		sfx.play_level_exit()

	# 3. Sonar resonance rings bursting from exit portal
	var exit_pos := cell_to_world(exit_cell)
	if echo_layer != null:
		echo_layer.emit_echo(exit_pos, 280.0, [], false)

	# 4. Player ascension animation: glides to center of exit, pulses gently and dissolves into light
	if is_instance_valid(player):
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(player, "global_position", exit_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(player, "scale", Vector2(1.22, 1.22), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(player, "modulate:a", 0.0, 0.55).set_delay(0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 5. After player dissolves (0.45s), record clear and proceed with transition
	get_tree().create_timer(0.45).timeout.connect(func():
		var debrief_data := GameState.record_level_clear(
			level_num,
			_level_time,
			_sonar_pings,
			_enemies_alerted
		)

		if GameState.current_mode == GameState.GameMode.CHALLENGE:
			# Roguelite flow: non-blocking clear banner (shows sector & time automatically), no retry or level-select buttons
			if hud != null:
				var on_chal_clear := func():
					_on_challenge_clear_next(cur_sector)
				hud.show_challenge_clear_banner(
					GameState.get_level_name(cur_sector),
					_level_time,
					on_chal_clear
				)
			else:
				_on_challenge_clear_next(cur_sector)
		else:
			# Story Mode flow:
			# 1. Screen fades completely to black (holds on black briefly for ~0.95s)
			# 2. Displays pure typewriter story narration (all black, only text, like game intro)
			# 3. When narrative sequence finishes, fades back to level cavern and displays the 3-star DebriefModal
			_play_story_clear_sequence(cur_sector, debrief_data)
	)


func _play_story_clear_sequence(cur_sector: int, debrief_data: Dictionary) -> void:
	var is_final_level: bool = not GameState.has_next_level()
	if is_final_level:
		# Only play the grand first-person ending cutscene on the FIRST completion (or after a reset).
		# Subsequent clears of Level 20 display the debrief evaluation screen normally like other levels.
		if not GameState.has_seen_campaign_ending("story"):
			GameState.complete_level(cur_sector + 1)
			GameState.set_pending_challenge_unlock_modal(true)
			GameState.mark_campaign_ending_seen("story")
			var cutscene_parent: Node = hud
			if cutscene_parent == null:
				cutscene_parent = self
			EndingCutscene.start_ending(cutscene_parent)
			return
		else:
			_show_story_debrief_modal(debrief_data, true)
			return

	var story_lines: Array = []
	if not GameState.has_seen_act_milestone(cur_sector):
		story_lines = GameState.get_sector_story_lines(cur_sector)
		GameState.mark_act_milestone_seen(cur_sector)

	if story_lines.size() > 0 and hud != null and hud.story_overlay != null:
		var on_story_finished := func():
			_show_story_debrief_modal(debrief_data, false)
		hud.story_overlay.play_sequence(story_lines, on_story_finished, true, "", "", 0.95)
	else:
		_show_story_debrief_modal(debrief_data, false)


func _show_story_debrief_modal(debrief_data: Dictionary, is_final_level: bool) -> void:
	if hud == null:
		return
	var on_next := func():
		if is_final_level:
			if hud != null and hud.has_method("show_victory_screen"):
				hud.show_victory_screen()
		else:
			GameState.next_level()
	var on_retry := func():
		GameState.restart_level(0.24, 0.28)
	var on_select := func():
		GameState.go_to_level_select()

	hud.show_debrief(debrief_data, on_next, on_retry, on_select)


func _on_challenge_clear_next(cur_sector: int) -> void:
	var level_num: int = cur_sector + 1
	if ChallengeModifiers.is_milestone_sector(level_num) and not ChallengeModifiers.is_milestone_claimed(level_num):
		var on_pact_done := func():
			_proceed_challenge_after_pact(cur_sector)
		var pact_parent: Node = hud
		if pact_parent == null:
			pact_parent = self
		AbyssalPactModal.open_pact(pact_parent, level_num, on_pact_done)
		return
	_proceed_challenge_after_pact(cur_sector)


func _proceed_challenge_after_pact(cur_sector: int) -> void:
	if not GameState.has_next_level():
		var total_t: float = GameState.get_total_challenge_time()
		if total_t > 0.0:
			HMSService.submit_challenge_run(total_t)
		var ending_lines: Array = []
		if not GameState.has_seen_campaign_ending("challenge"):
			ending_lines = GameState.get_campaign_ending_lines()
			GameState.mark_campaign_ending_seen("challenge")
		if ending_lines.size() > 0 and hud != null and hud.story_overlay != null:
			var end_hdr: String = "◈   K I N G   S E C T O R   •   D E P T H   - 9 , 9 9 9   M   ◈"
			var end_theme: String = "singularity"
			var on_chal_victory := func():
				hud.show_victory_screen()
			hud.story_overlay.play_sequence(ending_lines, on_chal_victory, true, end_hdr, end_theme, 0.8)
		else:
			hud.show_victory_screen()
	elif cur_sector == 19:
		# Player cleared Sector 20 and sealed pact: trigger King Sector entrance cinematic
		GameState.challenge_highest_unlocked = maxi(GameState.challenge_highest_unlocked, 21)
		GameState.current_mode = GameState.GameMode.CHALLENGE
		GameState.pending_sp_king_sector_cinematic = true
		var cfg := ConfigFile.new()
		if cfg.load(GameState.PROGRESS_PATH) == OK:
			cfg.set_value("progress", "challenge_highest_unlocked", GameState.challenge_highest_unlocked)
			cfg.save(GameState.PROGRESS_PATH)

		var curtain := _create_blackout_curtain()
		curtain.modulate.a = 0.0
		curtain.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(curtain, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		GameState.stop_menu_bgm(1.2)
		tw.chain().tween_callback(func():
			GameState.transition_to_scene(GameState.LEVEL_SELECT_SCENE, 0.05, 0.05)
		)
	else:
		if hud != null:
			var on_exit_done := func():
				GameState.go_to_level_select()
			hud.play_level_exit_transition(on_exit_done)
		else:
			GameState.go_to_level_select()

func is_exit_locked() -> bool:
	for c in switch_cells:
		if str(switch_cells[c]).strip_edges().to_lower() == "exit" and not pressed.has(c):
			return true
	return false



func _press_switch(cell: Vector2i) -> void:
	pressed[cell] = true
	_echo_features_dirty = true
	if GameState.current_mode == GameState.GameMode.CHALLENGE and ChallengeModifiers.has_boon("boon_deep_pockets") and is_instance_valid(player):
		var cap: int = player.get_max_pebbles() if player.has_method("get_max_pebbles") else 4
		player.pebbles = mini(player.pebbles + 1, cap)
		player.pebble_count_changed.emit(player.pebbles)
	var id: String = str(switch_cells[cell]).to_upper()
	for body in door_nodes.get(id, []):
		if is_instance_valid(body) and not body.has_meta("open"):
			body.set_meta("open", true)
			if body.get_child_count() > 0:
				body.get_child(0).set_deferred("disabled", true)
			if sfx != null:
				sfx.play_door_open(body.global_position)
	if sfx != null:
		sfx.play_sneak_toggle(false)
	var switch_world_pos := cell_to_world(cell)
	if echo_layer != null:
		echo_layer.emit_echo(switch_world_pos, 180.0, [], false, Color(1.0, 0.82, 0.25))

	# Text-defined levels can flag monsters with `wake=<switch id>`: stepping on that switch alerts them
	if player != null and is_instance_valid(player):
		for node in get_tree().get_nodes_in_group("enemy"):
			var sleeper_enemy := node as Enemy
			if sleeper_enemy != null and is_instance_valid(sleeper_enemy) and str(sleeper_enemy.get_meta("wake_on", "")).to_upper() == id:
				sleeper_enemy.set_meta("scripted_wake", true)
				sleeper_enemy.force_alert_to(player.global_position)

	if _is_tutorial_level:
		_level_0_key_activated()


func _trigger_read_note(cell: Vector2i) -> void:
	_read_notes_this_run[cell] = true
	var nid: String = str(note_cells.get(cell, ""))
	if nid == "" or not GameState.LORE_NOTES.has(nid):
		return
	var note_data: Dictionary = GameState.LORE_NOTES[nid].duplicate()
	note_data["id"] = nid
	GameState.collect_note(nid)
	note_cells.erase(cell)
	_echo_features_dirty = true

	if echo_layer != null and is_instance_valid(echo_layer):
		var exclude: Array = []
		if player != null and is_instance_valid(player):
			exclude.append(player.get_rid())
		echo_layer.emit_echo(cell_to_world(cell), 190.0, exclude, true, Color(1.0, 0.84, 0.35))

	get_tree().paused = true
	if player != null and is_instance_valid(player):
		player.can_move = false
		player.velocity = Vector2.ZERO

	var script: GDScript = load("res://ui/modals/NoteReadModal.gd") as GDScript
	var modal_parent: Node = hud
	if modal_parent == null or not is_instance_valid(modal_parent):
		modal_parent = self
	if script != null:
		if hud != null and is_instance_valid(hud):
			hud.set_gameplay_buttons_visible(false)
		script.open_note(modal_parent, note_data, func():
			get_tree().paused = false
			if hud != null and is_instance_valid(hud):
				hud.set_gameplay_buttons_visible(true)
			if player != null and is_instance_valid(player):
				player.can_move = true
		)
	else:
		get_tree().paused = false
		if player != null and is_instance_valid(player):
			player.can_move = true


func echo_features() -> Array:
	if _level_root == null or _level_root.walls == null:
		return []
	if not _echo_features_dirty:
		return _echo_features_cache
	_echo_features_cache.clear()
	for c in water_cells:
		_echo_features_cache.append({"type": "water", "pos": cell_to_world(c)})
	for c in note_cells:
		var nid: String = str(note_cells[c])
		_echo_features_cache.append({
			"type": "note",
			"pos": cell_to_world(c),
			"id": nid,
			"collected": GameState.is_note_collected(nid)
		})
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
	if _changing:
		return
	if sfx != null:
		sfx.play_player_death()
	if hud != null:
		hud.flash_death()
	if _is_tutorial_level and _tutorial_checkpoint > 0:
		_handle_tutorial_checkpoint_respawn()
		return
	await get_tree().create_timer(0.55).timeout
	if _changing:
		return
	var killer_type: int = int(player.get("killed_by_type")) if (player != null and is_instance_valid(player) and "killed_by_type" in player) else -1
	if hud != null:
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
			respawn_pos = Vector2(456.0, 144.0)
			_tutorial_step = 9
			# Reset Sleeper to dormant state in its alcove
			if _tutorial_sleeper != null and is_instance_valid(_tutorial_sleeper):
				_tutorial_sleeper.global_position = Vector2(720.0, 208.0)
				_tutorial_sleeper.home = Vector2(720.0, 208.0)
				_tutorial_sleeper.enemy_type = Enemy.EnemyType.SLEEPER
				_tutorial_sleeper.state = Enemy.State.SLEEP
				_tutorial_sleeper.velocity = Vector2.ZERO
				_tutorial_sleeper.alert_time = 0.85
				_tutorial_sleeper.reveal(0.0)
			# Ensure Sneak button is visible & enabled
			var sneak_btn := hud.get_node_or_null("SneakBtn") as Button
			if sneak_btn != null:
				sneak_btn.visible = true
				sneak_btn.set("tutorial_pulse", true)
			if hud != null:
				var title: String
				if GameState.sneak_hold_mode:
					title = "HOLD [SNEAK] BUTTON" if GameState.is_touch_or_mobile() else "HOLD [SHIFT] OR [SNEAK]"
				else:
					title = "TAP [SNEAK] BUTTON" if GameState.is_touch_or_mobile() else "PRESS [SHIFT] OR [SNEAK]"
				hud.show_tutorial_callout(1, title, "Move silently to cross the water without waking it")
			_set_tutorial_beacon(Vector2(560.0, 144.0), "SNEAK ACROSS")
		else:
			respawn_pos = Vector2(960.0, 144.0)
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
				if hud != null:
					var title: String = "HOLD [SOUND] BUTTON" if GameState.is_touch_or_mobile() else "HOLD [SPACE] OR [SOUND]"
					hud.show_tutorial_callout(0, title, "Hold until full charge, then release to awaken the key")
				_set_tutorial_beacon(Vector2(1104.0, 144.0), "RESONATE")
				if is_instance_valid(player) and not player.sound_emitted.is_connected(_on_tutorial_charge_emitted):
					player.sound_emitted.connect(_on_tutorial_charge_emitted)
			elif _tutorial_step == 12 or _tutorial_step == 13:
				_tutorial_step = 12
				_set_tutorial_beacon(Vector2(1104.0, 144.0), "TOUCH KEY")
			else:
				_tutorial_step = 14
				_set_tutorial_beacon(Vector2(1488.0, 144.0), "ASCENT")

		if is_instance_valid(player):
			player.reset(respawn_pos)
			player.can_move = (_tutorial_checkpoint != 2 or _tutorial_step >= 12)
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
