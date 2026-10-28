extends Control

@export var bar_count := 5
var _energy := 0.0
var _flash := 0.0
var _player: Node = null

var _bg_box := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_tree().get_first_node_in_group("player")
	_bg_box.bg_color = Color(0.025, 0.075, 0.15, 0.72)
	_bg_box.border_color = Color(0.25, 0.54, 0.82, 0.48)
	_bg_box.set_border_width_all(1)
	_bg_box.set_corner_radius_all(16)
	if not GameState.mic_enabled:
		visible = false

func _process(delta: float) -> void:
	if not GameState.mic_enabled:
		if visible:
			visible = false
		return
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
				var trig_db: float = mic.get_trigger_db() if mic.has_method("get_trigger_db") else (mic.noise_floor_db + 14.0)
				var target_e: float = clampf(inverse_lerp(trig_db - 12.0, trig_db + 14.0, raw_level), 0.0, 1.0)
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
	var w := 96.0
	var h := 28.0
	var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
	var t := Time.get_ticks_msec() / 1000.0

	var is_muted := false
	var calibrating := false
	var is_stunned := false
	if _player != null and is_instance_valid(_player):
		if "_stun_timer" in _player and float(_player._stun_timer) > 0.0:
			is_stunned = true
		if _player.has_node("MicInput"):
			var mic = _player.get_node("MicInput")
			if mic != null:
				if not mic.enabled:
					is_muted = true
				elif mic.has_method("is_calibrating") and mic.is_calibrating():
					calibrating = true

	# 1. Subtle dark glass capsule background
	_bg_box.border_color = Color(1.0, 0.28, 0.5, 0.85) if is_stunned else Color(0.25, 0.52, 0.78, 0.42)
	draw_style_box(_bg_box, rect)

	# 2. 5 clean dynamic acoustic equalizer bars
	var bar_w := 2.8
	var gap := 10.5
	var max_h := 16.0
	var min_h := 5.5

	var bar_weights := [0.55, 0.8, 1.0, 0.8, 0.55]
	var base_col := Color(0.35, 0.75, 1.0, 0.75) if not is_muted else Color(0.5, 0.5, 0.5, 0.4)
	if is_stunned:
		base_col = Color(1.0, 0.28, 0.52, 0.85)
	var active_col := Color(0.9, 0.98, 1.0, 1.0)

	for i in range(5):
		var x_offset := (i - 2) * gap
		var idle_breathe := 0.5 + 0.5 * sin(t * (22.0 if is_stunned else 3.0) + i * 0.9) if not is_muted else 0.0
		var bar_h: float = lerpf(min_h + 2.2 * idle_breathe, max_h * bar_weights[i], _energy)
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
	if is_stunned:
		text = "SONIC STUNNED!"
		text_col = Color(1.0, 0.35, 0.58, 0.98)
	elif is_muted:
		text = "MIC MUTED"
		text_col = Color(0.7, 0.45, 0.45, 0.6)
	elif calibrating:
		text = "CALIBRATING..."
		text_col = Color(1.0, 0.85, 0.35, 0.95)
	elif _flash > 0.1:
		text = "VOICE ACTIVE"
		text_col = Color(0.4, 0.95, 1.0, 1.0)
	else:
		text = "VOICE SENSOR"
		text_col = Color(0.45, 0.72, 0.95, 0.55)

	draw_string(ThemeDB.fallback_font, Vector2(-w * 0.5, h * 0.5 + 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, int(w), 9, text_col)
