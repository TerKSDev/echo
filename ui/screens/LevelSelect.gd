extends Control
class_name LevelSelect

const TEST_LEVEL_PATH := "res://levels/level_test.tscn"
const Icons = preload("res://ui/icons/Icons.gd")
const LevelPathRenderer = preload("res://ui/level_select/LevelPathRenderer.gd")
const DepthGaugeRenderer = preload("res://ui/level_select/DepthGaugeRenderer.gd")
const LevelCardBuilder = preload("res://ui/level_select/LevelCardBuilder.gd")

@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var level_grid: GridContainer = $MainArea/ScrollContainer/GridMargin/LevelGrid
@onready var depth_gauge: Control = $DepthGauge
@onready var leaderboard_button: Button = $TopBar/LeaderboardButton
@onready var intel_button: Button = $TopBar/IntelButton
@onready var settings_button: Button = $TopBar/SettingsButton
@onready var status_pill: PanelContainer = $TopBar/StatusPill
@onready var progress_label: Label = $TopBar/StatusPill/StatusBox/ProgressLabel
@onready var sonar_backdrop: Control = $SonarBackdrop

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _suppress_level_click := false
var _level_buttons: Dictionary = {}

var _depth_tag_alpha: float = 0.0
var _depth_tag_timer: float = 0.0
var _is_dragging_gauge: bool = false

# Procedural UI Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_error: AudioStreamWAV


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()

	# Background effects should not block button input.
	sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	scroll_container.gui_input.connect(_on_scroll_container_gui_input)

	# Hide scrollbar visually while retaining smooth scrolling
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.modulate.a = 0.0
	scrollbar.value_changed.connect(func(_val: float) -> void:
		_depth_tag_timer = 1.0
		if depth_gauge != null and is_instance_valid(depth_gauge):
			depth_gauge.queue_redraw()
	)

	# Two columns create the left-right staggered vertical ascent map
	level_grid.columns = 2
	level_grid.add_theme_constant_override("h_separation", 16)
	level_grid.add_theme_constant_override("v_separation", 30)

	# Wire level grid path drawing
	level_grid.draw.connect(_draw_level_path)

	# Setup custom subterranean depth gauge
	if depth_gauge != null:
		depth_gauge.draw.connect(_draw_depth_gauge)
		depth_gauge.gui_input.connect(_on_depth_gauge_gui_input)

	# Status pill stylish dark panel styling
	if status_pill != null:
		var pill_style := StyleBoxFlat.new()
		pill_style.bg_color = Color(0.03, 0.09, 0.16, 0.9)
		pill_style.border_color = Color(0.18, 0.45, 0.7, 0.8)
		pill_style.set_border_width_all(1)
		pill_style.set_corner_radius_all(12)
		status_pill.add_theme_stylebox_override("panel", pill_style)

	_setup_intel_button()
	_setup_settings_button()
	_setup_leaderboard_button()

	_create_level_buttons()

	# Update Top Status Bar progress text with sectors and stars
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()
	var highest: int = GameState.highest_unlocked_level
	var cur_unlocked := clampi(highest, 1, total_levels)
	var total_stars := 0
	for i in range(1, total_levels + 1):
		total_stars += GameState.get_level_stars(i)
	if progress_label != null:
		progress_label.text = "SECTORS: %02d/%02d   ★ %d/%d" % [cur_unlocked, total_levels, total_stars, total_levels * 3]

	# Auto-scroll directly to the highest active level on entry
	call_deferred("_scroll_to_current_level")
	_apply_safe_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_safe_area()


func _apply_safe_area() -> void:
	if not OS.has_feature("mobile") and OS.get_name() != "Android":
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen_sz := DisplayServer.screen_get_size()
	var vp_sz := get_viewport_rect().size
	if screen_sz.y > 0 and safe.position.y > 0:
		var top_pad := (float(safe.position.y) / float(screen_sz.y)) * vp_sz.y
		var target_top := maxf(top_pad + 8.0, 45.0)
		if has_node("TopBar"):
			$TopBar.position.y = target_top
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 68.0


# --------------------------------------------------
# NAVIGATION & LEVEL DATA
# --------------------------------------------------

func _get_playable_levels() -> Array[String]:
	return [
		"res://levels/level_01.tscn",
		"res://levels/level_02.tscn",
		"res://levels/level_03.tscn",
		"res://levels/level_04.tscn",
		"res://levels/level_05.tscn",
		"res://levels/level_06.tscn",
		"res://levels/level_07.tscn",
		"res://levels/level_08.tscn",
		"res://levels/level_09.tscn",
		"res://levels/level_10.tscn",
		"res://levels/level_11.tscn",
		"res://levels/level_12.tscn",
		"res://levels/level_13.tscn",
	]


func _on_scroll_container_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		_depth_tag_timer = 1.0


# --------------------------------------------------
# TOP BAR BUTTONS SETUP
# --------------------------------------------------

func _setup_intel_button() -> void:
	intel_button.custom_minimum_size = Vector2(56, 56)
	var n_sb := LevelCardBuilder.make_button_style(Color(0.04, 0.12, 0.22, 0.85), Color(0.28, 0.72, 0.95, 0.8), 2, 12)
	var h_sb := LevelCardBuilder.make_button_style(Color(0.08, 0.22, 0.38, 0.95), Color(0.5, 0.92, 1.0, 1.0), 2, 12)
	var p_sb := LevelCardBuilder.make_button_style(Color(0.12, 0.30, 0.50, 1.0), Color(0.7, 1.0, 1.0, 1.0), 2, 12)
	intel_button.add_theme_stylebox_override("normal", n_sb)
	intel_button.add_theme_stylebox_override("hover", h_sb)
	intel_button.add_theme_stylebox_override("pressed", p_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_book(icon_canvas))
	intel_button.add_child(icon_canvas)

	intel_button.pressed.connect(_on_intel_pressed)
	_wire_button_Juice(intel_button)


func _setup_settings_button() -> void:
	settings_button.custom_minimum_size = Vector2(56, 56)
	var n_sb := LevelCardBuilder.make_button_style(Color(0.04, 0.12, 0.22, 0.85), Color(0.28, 0.72, 0.95, 0.8), 2, 12)
	var h_sb := LevelCardBuilder.make_button_style(Color(0.08, 0.22, 0.38, 0.95), Color(0.5, 0.92, 1.0, 1.0), 2, 12)
	var p_sb := LevelCardBuilder.make_button_style(Color(0.12, 0.30, 0.50, 1.0), Color(0.7, 1.0, 1.0, 1.0), 2, 12)
	settings_button.add_theme_stylebox_override("normal", n_sb)
	settings_button.add_theme_stylebox_override("hover", h_sb)
	settings_button.add_theme_stylebox_override("pressed", p_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_gear(icon_canvas))
	settings_button.add_child(icon_canvas)

	settings_button.pressed.connect(_on_settings_pressed)
	_wire_button_Juice(settings_button)


func _setup_leaderboard_button() -> void:
	leaderboard_button.custom_minimum_size = Vector2(56, 56)
	var n_sb := LevelCardBuilder.make_button_style(Color(0.04, 0.12, 0.22, 0.85), Color(0.28, 0.72, 0.95, 0.8), 2, 12)
	var h_sb := LevelCardBuilder.make_button_style(Color(0.08, 0.22, 0.38, 0.95), Color(0.5, 0.92, 1.0, 1.0), 2, 12)
	var p_sb := LevelCardBuilder.make_button_style(Color(0.12, 0.30, 0.50, 1.0), Color(0.7, 1.0, 1.0, 1.0), 2, 12)
	leaderboard_button.add_theme_stylebox_override("normal", n_sb)
	leaderboard_button.add_theme_stylebox_override("hover", h_sb)
	leaderboard_button.add_theme_stylebox_override("pressed", p_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_trophy(icon_canvas))
	leaderboard_button.add_child(icon_canvas)

	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	_wire_button_Juice(leaderboard_button)


func _on_leaderboard_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	var modal_script: GDScript = load("res://ui/modals/LeaderboardModal.gd") as GDScript
	if modal_script != null:
		modal_script.open_modal(self)


func _on_intel_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	var script: GDScript = load("res://ui/modals/IntelModal.gd") as GDScript
	if script != null:
		script.open_modal(self)


func _on_settings_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	GameState.go_to_settings("res://ui/screens/level_select.tscn")


func _on_back_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 0.9)
	GameState.go_to_menu()


# --------------------------------------------------
# LEVEL BUTTON GRID
# --------------------------------------------------

func _create_level_buttons() -> void:
	for child in level_grid.get_children():
		child.queue_free()
	_level_buttons.clear()

	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()

	# Top padding in the grid (at top of cavern ascent, near surface)
	var top_pad_a := Control.new()
	top_pad_a.custom_minimum_size = Vector2(0, 20)
	top_pad_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_pad_b := Control.new()
	top_pad_b.custom_minimum_size = Vector2(0, 20)
	top_pad_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_grid.add_child(top_pad_a)
	level_grid.add_child(top_pad_b)

	# Levels progress from bottom (Depth 01 - Abyss Origin) to top (Depth 13 - Surface Breach).
	# Because GridContainer lays out items from top to bottom,
	# we iterate downwards from total_levels down to 1 with alternating spacers for a zigzag trail.
	for level_number in range(total_levels, 0, -1):
		var button := LevelCardBuilder.build_level_card(
			level_number,
			func() -> float: return _time,
			_on_level_pressed,
			_wire_button_Juice,
			_play_ui_sound,
			_wav_error
		)
		_level_buttons[level_number] = button

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 60)
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Alternating zigzag:
		# If level_number is odd (1, 3, 5, ...): Card on Left (col 0), Spacer on Right (col 1)
		# If level_number is even (2, 4, 6, ...): Spacer on Left (col 0), Card on Right (col 1)
		if level_number % 2 == 1:
			level_grid.add_child(button)
			level_grid.add_child(spacer)
		else:
			level_grid.add_child(spacer)
			level_grid.add_child(button)

	# Bottom padding in the grid (so Depth 01 has comfortable margin at bottom)
	var bot_pad_a := Control.new()
	bot_pad_a.custom_minimum_size = Vector2(0, 16)
	bot_pad_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bot_pad_b := Control.new()
	bot_pad_b.custom_minimum_size = Vector2(0, 16)
	bot_pad_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_grid.add_child(bot_pad_a)
	level_grid.add_child(bot_pad_b)


func _scroll_to_current_level() -> void:
	var highest: int = GameState.highest_unlocked_level
	var btn: Button = _level_buttons.get(highest)
	if btn != null and is_instance_valid(btn):
		var target_y := btn.position.y - 120.0
		var vbar := scroll_container.get_v_scroll_bar()
		var max_scroll := maxf(0.0, vbar.max_value - scroll_container.size.y)
		var final_y := clampf(target_y, 0.0, max_scroll)
		var tw := create_tween()
		tw.tween_property(scroll_container, "scroll_vertical", int(final_y), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw_level_path() -> void:
	var playable_levels := _get_playable_levels()
	LevelPathRenderer.draw_level_path(
		level_grid,
		_level_buttons,
		playable_levels.size(),
		GameState.highest_unlocked_level,
		_time
	)


func _draw_depth_gauge() -> void:
	DepthGaugeRenderer.draw_depth_gauge(depth_gauge, scroll_container, _depth_tag_alpha)


func _on_depth_gauge_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and not event.pressed):
		_is_dragging_gauge = false
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)) or (event is InputEventScreenDrag):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0

	if _is_dragging_gauge:
		DepthGaugeRenderer.scrub_to_position(event.position.y, depth_gauge, scroll_container)


func _on_level_pressed(level_number: int) -> void:
	if _suppress_level_click:
		_suppress_level_click = false
		return

	var playable_levels := _get_playable_levels()
	var playable_index: int = level_number - 1
	if playable_index < 0 or playable_index >= playable_levels.size():
		return

	var level_path := playable_levels[playable_index]
	var actual_level_index: int = GameState.LEVELS.find(level_path)
	_play_ui_sound(_wav_click, -4.0, 1.0)
	if actual_level_index != -1:
		GameState.start_game(actual_level_index)
	else:
		GameState.change_level(level_path)


func _on_test_arena_pressed() -> void:
	_play_ui_sound(_wav_click, -4.0, 1.0)
	GameState.start_game(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
		_launch_ready_level()
		get_viewport().set_input_as_handled()


func _launch_ready_level() -> void:
	var playable_levels := _get_playable_levels()
	var cur_lvl := clampi(GameState.highest_unlocked_level, 1, playable_levels.size())
	_on_level_pressed(cur_lvl)


# --------------------------------------------------
# AMBIENT SONAR AND FLOATING PARTICLES
# --------------------------------------------------

func _process(delta: float) -> void:
	_time += delta

	# Periodic ambient sonar wave - low frequency, random position, faint bioluminescent color
	_ambient_wave_timer -= delta
	if _ambient_wave_timer <= 0.0:
		_ambient_wave_timer = randf_range(5.0, 8.5)
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		var rand_pos := Vector2(
			randf_range(w_w * 0.16, w_w * 0.84),
			randf_range(w_h * 0.18, w_h * 0.82)
		)
		var rand_r: float = randf_range(160.0, 240.0)
		_ripples.append({
			"pos": rand_pos,
			"age": 0.0,
			"max_r": rand_r,
			"alpha": 0.20,
			"dur": 2.2
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(
		func(ripple: Dictionary) -> bool:
			return float(ripple["age"]) < float(ripple.get("dur", 2.2))
	)

	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		pos.y -= float(spore["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(spore["phase"])) * 12.0 * delta

		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))

		spore["pos"] = pos

	# Smooth fade transition for live depth readout tag
	if _is_dragging_gauge:
		_depth_tag_timer = 1.0
	elif _depth_tag_timer > 0.0:
		_depth_tag_timer = maxf(0.0, _depth_tag_timer - delta)

	var target_alpha: float = 1.0 if _depth_tag_timer > 0.0 else 0.0
	var fade_speed: float = 14.0 if target_alpha > _depth_tag_alpha else 3.5
	_depth_tag_alpha = move_toward(_depth_tag_alpha, target_alpha, delta * fade_speed)

	sonar_backdrop.queue_redraw()
	if level_grid != null and is_instance_valid(level_grid):
		level_grid.queue_redraw()
	if depth_gauge != null and is_instance_valid(depth_gauge):
		if _depth_tag_alpha > 0.001 or _is_dragging_gauge:
			depth_gauge.queue_redraw()

	# Redraw active level card (pulsing glow) and visible locked cards (scanning laser effect)
	for lvl in _level_buttons:
		var btn: Button = _level_buttons[lvl]
		if btn != null and is_instance_valid(btn):
			if lvl == GameState.highest_unlocked_level and btn.is_visible_in_tree():
				btn.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Clicking/touching empty space creates an ECHO wave
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_ripples.append({
			"pos": event.position,
			"age": 0.0,
			"max_r": randf_range(160.0, 240.0),
			"alpha": 0.28,
			"dur": 2.2
		})
		sonar_backdrop.queue_redraw()


func _init_spores() -> void:
	_spores.clear()
	for i in range(24):
		_spores.append({
			"pos": Vector2(
				randf_range(0.0, maxf(size.x, 720.0)),
				randf_range(0.0, maxf(size.y, 1280.0))
			),
			"speed": randf_range(12.0, 32.0),
			"phase": randf_range(0.0, TAU),
			"r": randf_range(1.2, 2.8),
			"alpha": randf_range(0.12, 0.40)
		})


func _draw_sonar_backdrop() -> void:
	var w := size.x
	var h := size.y

	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		if pos.x < -10.0 or pos.x > w + 10.0 or pos.y < -10.0 or pos.y > h + 10.0:
			continue
		var col := Color(0.4, 0.85, 1.0, float(spore["alpha"]))
		sonar_backdrop.draw_circle(pos, float(spore["r"]), col)

	for ripple in _ripples:
		var age: float = float(ripple["age"])
		var dur: float = float(ripple.get("dur", 2.2))
		var max_r: float = float(ripple.get("max_r", 200.0))
		var peak_a: float = float(ripple.get("alpha", 0.25))

		var progress: float = clampf(age / dur, 0.0, 1.0)
		var radius: float = progress * max_r

		var fade := 1.0 - progress
		fade = fade * fade
		var alpha := peak_a * fade

		var center: Vector2 = ripple["pos"]
		sonar_backdrop.draw_arc(
			center,
			radius,
			0.0,
			TAU,
			48,
			Color(0.35, 0.85, 1.0, alpha),
			1.4
		)


# --------------------------------------------------
# MICRO-INTERACTION POLISH (JUICE)
# --------------------------------------------------

func _wire_button_Juice(btn: Button) -> void:
	btn.pivot_offset = btn.custom_minimum_size * 0.5

	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.025, 1.025), 0.12)
		_play_ui_sound(_wav_hover, -9.0, 1.05)
	)

	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.14)
	)

	btn.button_down.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.06)
		_play_ui_sound(_wav_click, -5.0, 1.0)
	)

	btn.button_up.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.10)
	)


# --------------------------------------------------
# PROCEDURAL UI AUDIO
# --------------------------------------------------

func _build_ui_audio() -> void:
	_wav_click = _synth_tone(880.0, 0.045, 0.28, 0.003, 0.038)
	_wav_hover = _synth_tone(1320.0, 0.030, 0.10, 0.002, 0.024)
	_wav_error = _synth_tone(180.0, 0.120, 0.40, 0.005, 0.090)


func _synth_tone(
	freq: float,
	duration: float,
	volume: float,
	attack: float = 0.005,
	release: float = 0.05
) -> AudioStreamWAV:
	var sample_rate := 22050
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)

	var phase := 0.0
	var phase_inc := TAU * freq / float(sample_rate)

	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := 1.0
		if t < attack:
			env = t / maxf(0.0001, attack)
		elif t > duration - release:
			env = maxf(0.0, (duration - t) / maxf(0.0001, release))

		var sample_val := sin(phase) * volume * env
		phase += phase_inc

		var s16 := int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _play_ui_sound(wav: AudioStreamWAV, vol_db: float, pitch: float = 1.0) -> void:
	if wav == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
