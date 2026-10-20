extends Control

@export var bar_count := 5
var _energy := 0.0
var _flash := 0.0
var _player: Node = null

var _bg_box := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_tree().get_first_node_in_group("player")
	_bg_box.bg_color = Color(0.03, 0.08, 0.16, 0.65)
	_bg_box.border_color = Color(0.25, 0.52, 0.78, 0.45)
	_bg_box.set_border_width_all(1)
	_bg_box.set_corner_radius_all(16)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	var raw_level := -80.0
	var is_muted := false
	if _player.has_node("MicInput"):
		var mic = _player.get_node("MicInput")
		if mic != null:
			if not mic.enabled:
				is_muted = true
			else:
				raw_level = mic.level_db
				var floor_db: float = mic.noise_floor_db
				var target_e: float = clampf(inverse_lerp(floor_db + 2.0, floor_db + 25.0, raw_level), 0.0, 1.0)
				_energy = lerpf(_energy, target_e, delta * 16.0)

	if is_muted:
		_energy = 0.0
	else:
		_energy = move_toward(_energy, 0.0, delta * 0.9)
	_flash = move_toward(_flash, 0.0, delta * 2.5)
	queue_redraw()

func pulse_flash() -> void:
	_flash = 1.0

func _draw() -> void:
	var w := 120.0
	var h := 32.0
	var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
	var t := Time.get_ticks_msec() / 1000.0

	var is_muted := false
	if _player != null and is_instance_valid(_player) and _player.has_node("MicInput"):
		var mic = _player.get_node("MicInput")
		if mic != null and not mic.enabled:
			is_muted = true

	# 1. Subtle dark glass capsule background
	draw_style_box(_bg_box, rect)

	# 2. 5 dynamic acoustic equalizer bars
	var bar_w := 3.0
	var gap := 12.0
	var max_h := 18.0
	var min_h := 6.0

	var bar_weights := [0.55, 0.8, 1.0, 0.8, 0.55]
	var base_col := Color(0.35, 0.75, 1.0, 0.75) if not is_muted else Color(0.5, 0.5, 0.5, 0.4)
	var active_col := Color(0.9, 0.98, 1.0, 1.0)

	for i in range(5):
		var x_offset := (i - 2) * gap
		var idle_breathe := 0.5 + 0.5 * sin(t * 3.0 + i * 0.9) if not is_muted else 0.0
		var bar_h: float = lerpf(min_h + 2.5 * idle_breathe, max_h * bar_weights[i], _energy)
		var c := base_col.lerp(active_col, _energy + _flash)
		draw_line(
			Vector2(x_offset, -bar_h * 0.5),
			Vector2(x_offset, bar_h * 0.5),
			c,
			bar_w
		)

	# 3. Micro text status below
	var text: String
	var text_col: Color
	if is_muted:
		text = "MIC MUTED"
		text_col = Color(0.7, 0.45, 0.45, 0.6)
	elif _energy > 0.15 or _flash > 0.1:
		text = "VOICE ACTIVE"
		text_col = Color(0.4, 0.95, 1.0, 1.0)
	else:
		text = "VOICE SENSOR"
		text_col = Color(0.45, 0.72, 0.95, 0.65)

	draw_string(ThemeDB.fallback_font, Vector2(-w * 0.5, h * 0.5 + 14.0), text, HORIZONTAL_ALIGNMENT_CENTER, int(w), 11, text_col)
