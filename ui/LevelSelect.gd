
extends Control

const MIX_RATE := 22050
const LEVEL_BUTTON_HEIGHT := 56.0
const BOTTOM_BUTTON_HEIGHT := 46.0
const TEST_LEVEL_PATH := "res://levels/level_test.tscn"

@onready var level_grid: GridContainer = $CenterContainer/Content/ScrollContainer/LevelGrid
@onready var test_arena_button: Button = $TopBar/TestArenaButton
@onready var back_button: Button = $TopBar/BackButton
@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $CenterContainer/Content/ScrollContainer

var _time := 0.0
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _suppress_level_click := false

var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV


func _ready() -> void:
	_build_ui_audio()
	_init_spores()

	# Background effects should not block button input.
	sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	# Two columns create the left-right staggered vertical map.
	level_grid.columns = 2

	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	level_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Hide the scrollbar visually while retaining scrolling.
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.modulate.a = 0.0

	level_grid.add_theme_constant_override("h_separation", 12)
	level_grid.add_theme_constant_override("v_separation", 20)

	_style_bottom_button(test_arena_button)
	_style_bottom_button(back_button)

	_create_level_buttons()

	test_arena_button.pressed.connect(_on_test_arena_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_wire_button_Juice(test_arena_button)
	_wire_button_Juice(back_button)


# --------------------------------------------------
# GET PLAYABLE LEVELS
# --------------------------------------------------

func _get_playable_levels() -> Array[String]:
	var playable_levels: Array[String] = []

	for level_path in GameState.LEVELS:
		var path := str(level_path)

		# Exclude the test arena from the level selection map.
		if path == TEST_LEVEL_PATH:
			continue

		playable_levels.append(path)

	return playable_levels


# --------------------------------------------------
# BUTTON STYLES
# --------------------------------------------------

func _make_button_style(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _style_level_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override(
		"font_color",
		Color(0.76, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.45, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.9, 0.97, 1.0)
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.94),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(
			Color(0.06, 0.18, 0.29, 0.98),
			Color(0.25, 0.78, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(
			Color(0.08, 0.24, 0.36, 1.0),
			Color(0.4, 0.86, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"focus",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.94),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)


func _style_bottom_button(button: Button) -> void:
	button.custom_minimum_size.y = BOTTOM_BUTTON_HEIGHT

	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override(
		"font_color",
		Color(0.76, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.45, 0.88, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.9, 0.97, 1.0)
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.96),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(
			Color(0.06, 0.18, 0.29, 1.0),
			Color(0.25, 0.78, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(
			Color(0.08, 0.24, 0.36, 1.0),
			Color(0.4, 0.86, 1.0, 1.0),
			2
		)
	)

	button.add_theme_stylebox_override(
		"focus",
		_make_button_style(
			Color(0.035, 0.09, 0.16, 0.96),
			Color(0.12, 0.43, 0.68, 0.95)
		)
	)


# --------------------------------------------------
# LEVEL BUTTONS
# --------------------------------------------------

func _create_level_buttons() -> void:
	# Only create buttons for playable levels.
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()

	for i in range(1, total_levels + 1):
		var button := Button.new()
		var unlocked: bool = i <= GameState.highest_unlocked_level

		if unlocked:
			button.text = "◉\nDEPTH %02d" % i
			button.disabled = false
		else:
			button.text = "🔒\nDEPTH %02d" % i
			button.disabled = true

		button.custom_minimum_size = Vector2(
			110,
			LEVEL_BUTTON_HEIGHT
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.focus_mode = Control.FOCUS_NONE

		_style_level_button(button)

		if unlocked:
			button.pressed.connect(_on_level_pressed.bind(i))
			_wire_button_Juice(button)
		else:
			button.modulate = Color(0.45, 0.50, 0.58, 0.8)

		# Spacer creates the staggered left-right map.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(
			0,
			LEVEL_BUTTON_HEIGHT + 100.0
		)
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if i % 2 == 1:
			level_grid.add_child(button)
			level_grid.add_child(spacer)
		else:
			level_grid.add_child(spacer)
			level_grid.add_child(button)


func _on_level_pressed(level_number: int) -> void:
	# Ignore clicks if the player dragged the map.
	if _suppress_level_click:
		_suppress_level_click = false
		return

	var playable_levels := _get_playable_levels()
	var playable_index: int = level_number - 1

	if playable_index < 0 or playable_index >= playable_levels.size():
		push_error("Invalid level number: %d" % level_number)
		return

	# Find the actual index in GameState.LEVELS.
	var actual_level_index: int = GameState.LEVELS.find(
		playable_levels[playable_index]
	)

	if actual_level_index == -1:
		push_error(
			"Level not found in GameState.LEVELS: "
			+ playable_levels[playable_index]
		)
		return

	GameState.start_game(actual_level_index)


func _on_test_arena_pressed() -> void:
	# Keep the separate TEST button working as before.
	GameState.start_game(0)


func _on_back_pressed() -> void:
	GameState.go_to_menu()
	var mouse_pos := get_global_mouse_position()

	var map_rect := Rect2(
		scroll_container.global_position,
		scroll_container.size
	)

	return map_rect.has_point(mouse_pos)


# --------------------------------------------------
# AMBIENT SONAR AND FLOATING PARTICLES
# --------------------------------------------------

func _process(delta: float) -> void:
	_time += delta

	# Create an ambient sonar wave every 2.6 seconds.
	if fmod(_time, 2.6) < delta:
		var title_center := Vector2(
			size.x * 0.5,
			size.y * 0.245
		)

		_ripples.append({
			"pos": title_center,
			"age": 0.0,
			"max_r": 320.0,
			"alpha": 0.35
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(
		func(ripple: Dictionary) -> bool:
			return float(ripple["age"]) < 2.8
	)

	for spore in _spores:
		var pos: Vector2 = spore["pos"]

		pos.y -= float(spore["speed"]) * delta
		pos.x += (
			sin(_time * 1.4 + float(spore["phase"]))
			* 12.0
			* delta
		)

		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(
				0.0,
				maxf(size.x, 600.0)
			)

		spore["pos"] = pos

	sonar_backdrop.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Clicking empty space creates an ECHO wave.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_ripples.append({
				"pos": event.position,
				"age": 0.0,
				"max_r": 180.0,
				"alpha": 0.45
			})


func _init_spores() -> void:
	for i in range(26):
		_spores.append({
			"pos": Vector2(
				randf_range(40.0, 760.0),
				randf_range(40.0, 960.0)
			),
			"r": randf_range(1.2, 2.8),
			"speed": randf_range(12.0, 28.0),
			"phase": randf() * TAU
		})


func _draw_sonar_backdrop() -> void:
	# Draw floating glowing particles.
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		var radius: float = float(spore["r"])

		var twinkle := 0.35 + 0.35 * sin(
			_time * 2.5 + float(spore["phase"])
		)

		sonar_backdrop.draw_circle(
			pos,
			radius * 2.4,
			Color(0.2, 0.75, 1.0, twinkle * 0.18)
		)

		sonar_backdrop.draw_circle(
			pos,
			radius,
			Color(0.55, 0.92, 1.0, twinkle)
		)

	# Draw expanding sonar rings.
	for ripple in _ripples:
		var progress := clampf(
			float(ripple["age"]) / 2.8,
			0.0,
			1.0
		)

		var radius := progress * float(ripple["max_r"])
		var alpha := (
			(1.0 - progress)
			* float(ripple["alpha"])
		)

		sonar_backdrop.draw_arc(
			ripple["pos"],
			radius,
			0.0,
			TAU,
			64,
			Color(0.35, 0.88, 1.0, alpha),
			1.8
		)


# --------------------------------------------------
# BUTTON HOVER AND CLICK EFFECTS
# --------------------------------------------------

func _wire_button_Juice(btn: Button) -> void:
	btn.mouse_entered.connect(func() -> void:
		_play_ui_sound(
			_wav_hover,
			-14.0,
			randf_range(0.98, 1.04)
		)

		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(1.03, 1.03),
			0.1
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	btn.mouse_exited.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2.ONE,
			0.12
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	btn.button_down.connect(func() -> void:
		_play_ui_sound(_wav_click, -5.0, 1.0)

		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(0.96, 0.96),
			0.06
		)
	)

	btn.button_up.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5

		var tween := create_tween()
		tween.tween_property(
			btn,
			"scale",
			Vector2(1.02, 1.02),
			0.12
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


# --------------------------------------------------
# PROCEDURAL UI AUDIO
# --------------------------------------------------

func _build_ui_audio() -> void:
	_wav_click = _synth_tone(620.0, 920.0, 0.14)
	_wav_hover = _synth_tone(480.0, 540.0, 0.06)


func _synth_tone(
	f_start: float,
	f_end: float,
	dur: float
) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)

	var phase := 0.0

	for i in range(count):
		var t: float = float(i) / MIX_RATE
		var envelope := minf(t / 0.004, 1.0) * exp(-t * 24.0)
		var frequency := lerpf(f_start, f_end, t / dur)

		phase += TAU * frequency / MIX_RATE

		var sample := clampf(
			sin(phase) * envelope * 0.7,
			-1.0,
			1.0
		)

		bytes.encode_s16(
			i * 2,
			int(sample * 32767.0)
		)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes

	return wav


func _play_ui_sound(
	stream: AudioStreamWAV,
	vol_db: float,
	pitch: float
) -> void:
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"Master"

	add_child(player)

	player.finished.connect(player.queue_free)
	player.play()
