extends Control

const MIX_RATE := 22050

const LINES: Array[String] = [
	"You wake at the bottom of the abyss, with no memory of how you got here.",
	"In the dark, every sound is a light.",
	"But sound is also a call."
]

@onready var background: ColorRect = $Background
@onready var touch_area: Button = $TouchArea
@onready var ripple_layer: Control = $RippleLayer
@onready var content_box: Control = $CenterBox/Content
@onready var dialogue_label: Label = $CenterBox/Content/DialogueLabel
@onready var diamond_prompt: Control = $CenterBox/Content/PromptCenter/DiamondPrompt

var _current_index := 0
var _is_typing := false
var _is_advancing := false
var _type_tween: Tween = null
var _time := 0.0
var _last_char_count := 0
var _last_tap_pos := Vector2(360.0, 640.0)
var _ripples: Array[Dictionary] = []

var _wav_tick: AudioStreamWAV
var _wav_advance: AudioStreamWAV
var _wav_abyss: AudioStreamWAV


func _ready() -> void:
	_build_audio()

	# Connect drawing layers
	ripple_layer.draw.connect(_draw_ripples)
	diamond_prompt.draw.connect(_draw_diamond_prompt)

	# Full-screen touch area wiring
	touch_area.pressed.connect(_on_touch_area_pressed)
	touch_area.gui_input.connect(_on_touch_area_gui_input)

	# Pure black void waking rumble
	_play_sound(_wav_abyss, -12.0, 0.75)

	# Keep pure darkness initially
	if content_box != null:
		content_box.modulate.a = 0.0

	# Hold on pure blackness for ~1.0s, then display first line
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		_show_line(0)
	)


func _process(delta: float) -> void:
	_time += delta

	# Process typewriter character ticks
	if _is_typing and dialogue_label != null:
		var cur_chars := int(dialogue_label.visible_ratio * dialogue_label.text.length())
		if cur_chars > _last_char_count:
			if cur_chars % 2 == 0:
				_play_sound(_wav_tick, -22.0, randf_range(0.92, 1.08))
			_last_char_count = cur_chars

	# Redraw floating diamond prompt
	if diamond_prompt != null and diamond_prompt.visible:
		diamond_prompt.queue_redraw()

	# Animate acoustic ripples from touches
	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples = _ripples.filter(func(r): return float(r["age"]) < float(r.get("dur", 1.2)))

	ripple_layer.queue_redraw()


func _draw_ripples() -> void:
	for r in _ripples:
		var dur: float = float(r.get("dur", 1.2))
		var prog: float = clampf(float(r["age"]) / dur, 0.0, 1.0)
		var rad: float = prog * float(r["max_r"])
		var a: float = (1.0 - prog) * 0.45
		ripple_layer.draw_arc(r["pos"], rad, 0.0, TAU, 48, Color(0.35, 0.88, 1.0, a), 1.6)


func _draw_diamond_prompt() -> void:
	if _is_typing or diamond_prompt == null:
		return

	var c := diamond_prompt.size * 0.5
	# Floating bobbing motion
	var bob_y := sin(_time * 4.2) * 3.5
	var center := c + Vector2(0.0, bob_y)

	var pulse := 0.6 + 0.4 * sin(_time * 3.5)
	var r_w := 9.0
	var r_h := 12.0

	# 1. Soft glowing outer diamond halo
	var glow_col := Color(0.20, 0.65, 1.0, 0.28 * pulse)
	var glow_pts := PackedVector2Array([
		center + Vector2(0.0, -r_h - 3.5),
		center + Vector2(r_w + 3.5, 0.0),
		center + Vector2(0.0, r_h + 3.5),
		center + Vector2(-r_w - 3.5, 0.0)
	])
	diamond_prompt.draw_colored_polygon(glow_pts, glow_col)

	# 2. Main diamond body
	var pts := PackedVector2Array([
		center + Vector2(0.0, -r_h),
		center + Vector2(r_w, 0.0),
		center + Vector2(0.0, r_h),
		center + Vector2(-r_w, 0.0)
	])
	diamond_prompt.draw_colored_polygon(pts, Color(0.04, 0.18, 0.35, 0.90 * pulse))
	var closed := pts.duplicate()
	closed.append(pts[0])
	diamond_prompt.draw_polyline(closed, Color(0.45, 0.90, 1.0, 0.95 * pulse), 1.8)

	# 3. Inner brilliant core diamond
	var core_w := 3.6
	var core_h := 5.0
	var core_pts := PackedVector2Array([
		center + Vector2(0.0, -core_h),
		center + Vector2(core_w, 0.0),
		center + Vector2(0.0, core_h),
		center + Vector2(-core_w, 0.0)
	])
	diamond_prompt.draw_colored_polygon(core_pts, Color(1.0, 1.0, 1.0, 0.95 * pulse))


func _show_line(index: int) -> void:
	if index < 0 or index >= LINES.size():
		return
	_current_index = index
	_is_typing = true
	_is_advancing = false
	_last_char_count = 0

	dialogue_label.text = LINES[index]
	dialogue_label.visible_ratio = 0.0
	diamond_prompt.visible = false
	diamond_prompt.modulate.a = 0.0
	content_box.modulate.a = 1.0

	var text_len := dialogue_label.text.length()
	var char_speed := 0.036 # ~28 characters/second
	var dur: float = clampf(text_len * char_speed, 1.3, 2.6)

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
		p_tw.tween_property(diamond_prompt, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_touch_area_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_last_tap_pos = event.position


func _on_touch_area_pressed() -> void:
	_on_screen_tapped(_last_tap_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
		_on_screen_tapped(Vector2(size.x * 0.5, size.y * 0.5))
		get_viewport().set_input_as_handled()


func _on_screen_tapped(tap_pos: Vector2) -> void:
	if _is_advancing:
		return

	# Emit acoustic visual sonar ring from touch
	_ripples.append({
		"pos": tap_pos,
		"age": 0.0,
		"dur": 1.1,
		"max_r": 190.0
	})

	if _is_typing:
		# User tapped while typing: immediately finish current sentence
		if _type_tween != null and _type_tween.is_valid():
			_type_tween.kill()
		_on_typing_finished()
		_play_sound(_wav_tick, -14.0, 1.25)
		return

	# Sentence is already fully revealed: proceed to next or tutorial
	if _current_index < LINES.size() - 1:
		_advance_to_next_line()
	else:
		_finish_intro()


func _advance_to_next_line() -> void:
	_is_advancing = true
	_play_sound(_wav_advance, -6.0, 1.0)
	Input.vibrate_handheld(25)

	var tw := create_tween()
	tw.tween_property(content_box, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.08)
	tw.tween_callback(func():
		_show_line(_current_index + 1)
	)


func _finish_intro() -> void:
	_is_advancing = true
	_play_sound(_wav_abyss, -3.0, 0.88)
	Input.vibrate_handheld(50)

	# Mark intro as seen persistently
	GameState.mark_intro_seen()

	# Smooth black fade-out directly entering Level 0 (Tutorial)
	var tw := create_tween()
	tw.tween_property(content_box, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.18)
	tw.tween_callback(func():
		GameState.current_mode = GameState.GameMode.STORY
		GameState.force_level_0_story = true
		GameState.start_game(0)
	)


# --- Procedural Audio Generation ---------------------------------------------

func _build_audio() -> void:
	_wav_tick = _synth_tick()
	_wav_advance = _synth_advance()
	_wav_abyss = _synth_abyss()


func _synth_tick() -> AudioStreamWAV:
	var dur := 0.022
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-t * 220.0)
		var s: float = sin(t * TAU * 1150.0) * env * 0.3
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _synth_advance() -> AudioStreamWAV:
	var dur := 0.38
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 8.5)
		var s: float = (sin(t * TAU * 523.25) * 0.52 + sin(t * TAU * 1046.5) * 0.28) * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _synth_abyss() -> AudioStreamWAV:
	var dur := 1.25
	var count := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / 0.06, 1.0) * exp(-t * 2.4)
		var s: float = (sin(t * TAU * 55.0) * 0.58 + sin(t * TAU * 110.0) * 0.32) * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav


func _play_sound(stream: AudioStream, vol_db: float = -6.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = &"SFX"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
