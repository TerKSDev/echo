extends Control
class_name StoryOverlay
## Reusable in-game story & dialogue presentation overlay for ECHO.
## Immerses the screen in atmospheric pure darkness, displaying poetic
## typewriter narration with acoustic ripples, procedural audio, and glowing diamond prompt.

const Icons = preload("res://ui/icons/Icons.gd")
const MIX_RATE := 22050

signal sequence_finished
signal line_finished(index: int)

@onready var backdrop: ColorRect = $Backdrop
@onready var ripple_layer: Control = $RippleLayer
@onready var touch_area: Button = $TouchArea
@onready var content_box: Control = $CenterBox/Content
@onready var dialogue_label: Label = $CenterBox/Content/DialogueLabel
@onready var diamond_prompt: Control = $CenterBox/Content/PromptCenter/DiamondPrompt

var _queue: Array[String] = []
var _on_complete: Callable = Callable()
var _is_active := false
var _is_typing := false
var _is_advancing := false
var _dark_backdrop := true
var _theme_mode := ""
var _header_label: Label = null
var _total_lines := 1
var _type_tween: Tween = null
var _time := 0.0
var _last_char_count := 0
var _current_line_idx := 0
var _last_tap_pos := Vector2(360.0, 640.0)
var _ripples: Array[Dictionary] = []

var _wav_tick: AudioStreamWAV
var _wav_advance: AudioStreamWAV


func is_active() -> bool:
	return _is_active


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 110
	_build_audio()
	_setup_header_label()
	ripple_layer.draw.connect(_draw_ripples)
	diamond_prompt.draw.connect(_draw_diamond_prompt)
	touch_area.pressed.connect(_on_touch_pressed)
	touch_area.gui_input.connect(_on_touch_gui_input)

	# Initially dormant and pass-through
	visible = false
	if backdrop != null:
		backdrop.modulate.a = 0.0
	if content_box != null:
		content_box.modulate.a = 0.0
	touch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_header_label() -> void:
	if content_box == null:
		return
	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.add_theme_color_override("font_color", Color(0.42, 0.88, 1.0, 0.88))
	_header_label.visible = false
	content_box.add_child(_header_label)
	content_box.move_child(_header_label, 0)


func _process(delta: float) -> void:
	if not _is_active:
		return
	_time += delta

	# Process typewriter acoustic micro-ticks
	if _is_typing and dialogue_label != null:
		var cur_chars := int(dialogue_label.visible_ratio * dialogue_label.text.length())
		if cur_chars > _last_char_count:
			if cur_chars % 2 == 0:
				_play_sound(_wav_tick, -22.0, randf_range(0.92, 1.08))
			_last_char_count = cur_chars

	# Floating diamond prompt animation
	if diamond_prompt != null and diamond_prompt.visible:
		diamond_prompt.queue_redraw()

	# Animate acoustic ripples from touches
	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples = _ripples.filter(func(r): return float(r["age"]) < float(r.get("dur", 1.0)))

	ripple_layer.queue_redraw()


func _draw_ripples() -> void:
	var vp_center := size * 0.5
	if _theme_mode == "daylight" and _total_lines > 0:
		var prog_sun := clampf(float(_current_line_idx) / float(maxi(_total_lines - 1, 1)), 0.0, 1.0)
		if prog_sun > 0.05:
			var sun_pulse := 0.88 + 0.12 * sin(_time * 1.8)
			var base_r := (120.0 + prog_sun * 220.0) * sun_pulse
			ripple_layer.draw_circle(vp_center, base_r * 1.35, Color(1.0, 0.82, 0.35, prog_sun * 0.08))
			ripple_layer.draw_circle(vp_center, base_r * 0.85, Color(1.0, 0.90, 0.55, prog_sun * 0.11))
			ripple_layer.draw_arc(vp_center, base_r, 0.0, TAU, 64, Color(1.0, 0.88, 0.45, prog_sun * 0.28), 1.8)
	elif _theme_mode == "singularity":
		var core_pulse := 0.85 + 0.15 * sin(_time * 2.2)
		ripple_layer.draw_circle(vp_center, 150.0 * core_pulse, Color(0.85, 0.20, 0.55, 0.07))
		ripple_layer.draw_arc(vp_center, 165.0 * core_pulse, 0.0, TAU, 64, Color(1.0, 0.42, 0.78, 0.22), 1.5)

	var base_col := Color(0.35, 0.88, 1.0)
	if _theme_mode == "daylight":
		base_col = Color(1.0, 0.86, 0.42)
	elif _theme_mode == "singularity":
		base_col = Color(1.0, 0.45, 0.78)

	for r in _ripples:
		var dur: float = float(r.get("dur", 1.0))
		var prog: float = clampf(float(r["age"]) / dur, 0.0, 1.0)
		var rad: float = prog * float(r["max_r"])
		var a: float = (1.0 - prog) * 0.40
		var r_col: Color = r.get("col", base_col)
		ripple_layer.draw_arc(r["pos"], rad, 0.0, TAU, 48, Color(r_col.r, r_col.g, r_col.b, a), 1.6)


func _draw_diamond_prompt() -> void:
	if _is_typing or diamond_prompt == null:
		return
	var pulse := 0.6 + 0.4 * sin(_time * 3.5)
	var bob_y := sin(_time * 4.2) * 3.5
	diamond_prompt.draw_set_transform(Vector2(0.0, bob_y))
	Icons.draw_diamond(diamond_prompt, pulse)
	diamond_prompt.draw_set_transform(Vector2.ZERO)


func _suppress_game_mic(duration: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var players = tree.get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p.has_node("MicInput"):
			var mic = p.get_node("MicInput")
			if mic != null and mic.has_method("suppress"):
				mic.suppress(duration)


## Start a sequential narrative sequence of dialogue lines
func play_sequence(lines: Array, on_finished: Callable = Callable(), dark_backdrop: bool = true, header_text: String = "", theme_mode: String = "", black_hold: float = 0.0) -> void:
	if lines.is_empty():
		if on_finished.is_valid():
			on_finished.call()
		return

	_suppress_game_mic(9999.0)
	_queue.clear()
	for item in lines:
		_queue.append(str(item))
	_total_lines = _queue.size()
	_on_complete = on_finished
	_is_active = true
	_dark_backdrop = dark_backdrop
	_theme_mode = theme_mode
	_current_line_idx = 0
	visible = true
	modulate.a = 1.0
	touch_area.mouse_filter = Control.MOUSE_FILTER_STOP

	if _header_label != null:
		if header_text != "":
			_header_label.text = header_text
			_header_label.visible = true
			if _theme_mode == "daylight":
				_header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40, 0.92))
			elif _theme_mode == "singularity":
				_header_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.80, 0.92))
			else:
				_header_label.add_theme_color_override("font_color", Color(0.42, 0.88, 1.0, 0.88))
		else:
			_header_label.visible = false

	var center_box := get_node_or_null("CenterBox") as Control
	if center_box != null:
		if _dark_backdrop:
			center_box.offset_top = 0.0
			center_box.offset_bottom = 0.0
		else:
			# Position narration cleanly in the upper-middle above the centered player core
			center_box.offset_top = -220.0
			center_box.offset_bottom = -60.0

	if _dark_backdrop and backdrop != null:
		backdrop.visible = true
		backdrop.color = Color(0.03, 0.01, 0.04, 1.0) if _theme_mode == "singularity" else Color(0.0, 0.0, 0.0, 1.0)
		backdrop.modulate.a = 0.0
		if content_box != null:
			content_box.modulate.a = 0.0
		var b_tw := create_tween()
		var fade_in_dur: float = 0.45 if black_hold > 0.0 else 0.28
		b_tw.tween_property(backdrop, "modulate:a", 1.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if black_hold > 0.0:
			b_tw.tween_interval(black_hold)
		b_tw.tween_callback(func():
			_show_next_in_queue()
		)
	else:
		if backdrop != null:
			backdrop.visible = false
		_show_next_in_queue()


## Show a single dialogue line
func play_line(line: String, on_finished: Callable = Callable(), dark_backdrop: bool = true) -> void:
	play_sequence([line], on_finished, dark_backdrop)


func _show_next_in_queue() -> void:
	if _queue.is_empty():
		_finish_sequence()
		return

	var text: String = _queue.pop_front()
	_is_typing = true
	_is_advancing = false
	_last_char_count = 0

	# Progressive atmospheric backdrop evolution during Campaign Endings & Act Milestones
	if _dark_backdrop and backdrop != null:
		if _theme_mode == "daylight" and _total_lines > 1:
			var prog := clampf(float(_current_line_idx) / float(_total_lines - 1), 0.0, 1.0)
			var target_bg := Color(0.0, 0.01, 0.02, 1.0).lerp(Color(0.20, 0.15, 0.06, 1.0), prog)
			create_tween().tween_property(backdrop, "color", target_bg, 0.85).set_trans(Tween.TRANS_SINE)
			if dialogue_label != null:
				var target_font := Color(0.92, 0.96, 1.0, 1.0).lerp(Color(1.0, 0.96, 0.84, 1.0), prog)
				dialogue_label.add_theme_color_override("font_color", target_font)
		elif dialogue_label != null:
			dialogue_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))

	if _theme_mode != "":
		var vp_center := size * 0.5 if size.x > 50.0 else Vector2(360.0, 320.0)
		_ripples.append({
			"pos": vp_center,
			"age": 0.0,
			"dur": 1.6,
			"max_r": 260.0
		})

	dialogue_label.text = text
	dialogue_label.visible_ratio = 0.0
	diamond_prompt.visible = false
	diamond_prompt.modulate.a = 0.0
	content_box.modulate.a = 0.0

	var f_tw := create_tween()
	f_tw.tween_property(content_box, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var text_len := text.length()
	var char_speed := 0.036 # ~28 chars per second for thoughtful pacing
	var dur: float = clampf(text_len * char_speed, 1.0, 2.6)

	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()

	_type_tween = create_tween()
	_type_tween.tween_property(dialogue_label, "visible_ratio", 1.0, dur).set_trans(Tween.TRANS_LINEAR)
	_type_tween.tween_callback(_on_typing_finished)


func _on_typing_finished() -> void:
	_is_typing = false
	if dialogue_label != null:
		dialogue_label.visible_ratio = 1.0
	if diamond_prompt != null:
		diamond_prompt.visible = true
		var p_tw := create_tween()
		p_tw.tween_property(diamond_prompt, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_touch_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_last_tap_pos = event.position


func _on_touch_pressed() -> void:
	if not _is_active or _is_advancing:
		return

	# Acoustic ripple ring from touch position
	_ripples.append({
		"pos": _last_tap_pos,
		"age": 0.0,
		"dur": 1.0,
		"max_r": 180.0
	})

	if _is_typing:
		# Fast-forward current line
		if _type_tween != null and _type_tween.is_valid():
			_type_tween.kill()
		_on_typing_finished()
		_play_sound(_wav_tick, -14.0, 1.25)
		return

	# Line is fully visible: advance to next
	_advance_line()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active or _is_advancing:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
		_last_tap_pos = Vector2(size.x * 0.5, size.y * 0.5)
		_on_touch_pressed()
		get_viewport().set_input_as_handled()


func _advance_line() -> void:
	_is_advancing = true
	_play_sound(_wav_advance, -6.0, 1.0)
	Input.vibrate_handheld(25)
	line_finished.emit(_current_line_idx)
	_current_line_idx += 1

	var tw := create_tween()
	tw.tween_property(content_box, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.06)
	tw.tween_callback(func():
		_show_next_in_queue()
	)


func _finish_sequence() -> void:
	_is_active = false
	touch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suppress_game_mic(0.4)

	var tw := create_tween()
	tw.tween_property(content_box, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _dark_backdrop and backdrop != null and backdrop.visible:
		tw.parallel().tween_property(backdrop, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		visible = false
		sequence_finished.emit()
		if _on_complete.is_valid():
			var cb := _on_complete
			_on_complete = Callable()
			cb.call()
	)


func hide_overlay(fade_dur: float = 0.22) -> void:
	_is_active = false
	touch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suppress_game_mic(0.4)
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()

	if fade_dur > 0.0 and visible:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, fade_dur).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			visible = false
			modulate.a = 1.0
		)
	else:
		visible = false


# --- Procedural Audio Generation ---------------------------------------------

func _build_audio() -> void:
	_wav_tick = _synth_tick()
	_wav_advance = _synth_advance()


func _synth_tick() -> AudioStreamWAV:
	var dur := 0.022
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 220.0)
		var freq := 880.0
		var sample := sin(TAU * freq * t) * env * 0.45
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _synth_advance() -> AudioStreamWAV:
	var dur := 0.28
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 12.0)
		var f := 320.0 + 180.0 * (1.0 - t / dur)
		var sample := sin(TAU * f * t) * env * 0.5
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _play_sound(wav: AudioStreamWAV, volume_db: float = -12.0, pitch: float = 1.0) -> void:
	if wav == null:
		return
	var asp := AudioStreamPlayer.new()
	asp.stream = wav
	asp.volume_db = volume_db
	asp.pitch_scale = pitch
	asp.bus = &"SFX"
	add_child(asp)
	asp.finished.connect(asp.queue_free)
	asp.play()
