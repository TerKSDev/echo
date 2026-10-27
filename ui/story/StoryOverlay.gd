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
var _type_tween: Tween = null
var _time := 0.0
var _last_char_count := 0
var _current_line_idx := 0
var _last_tap_pos := Vector2(360.0, 640.0)
var _ripples: Array[Dictionary] = []

var _wav_tick: AudioStreamWAV
var _wav_advance: AudioStreamWAV


func _ready() -> void:
	_build_audio()
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
	for r in _ripples:
		var dur: float = float(r.get("dur", 1.0))
		var prog: float = clampf(float(r["age"]) / dur, 0.0, 1.0)
		var rad: float = prog * float(r["max_r"])
		var a: float = (1.0 - prog) * 0.40
		ripple_layer.draw_arc(r["pos"], rad, 0.0, TAU, 48, Color(0.35, 0.88, 1.0, a), 1.6)


func _draw_diamond_prompt() -> void:
	if _is_typing or diamond_prompt == null:
		return
	var pulse := 0.6 + 0.4 * sin(_time * 3.5)
	var bob_y := sin(_time * 4.2) * 3.5
	diamond_prompt.draw_set_transform(Vector2(0.0, bob_y))
	Icons.draw_diamond(diamond_prompt, pulse)
	diamond_prompt.draw_set_transform(Vector2.ZERO)


## Start a sequential narrative sequence of dialogue lines
func play_sequence(lines: Array, on_finished: Callable = Callable(), dark_backdrop: bool = true) -> void:
	if lines.is_empty():
		if on_finished.is_valid():
			on_finished.call()
		return

	_queue.clear()
	for item in lines:
		_queue.append(str(item))
	_on_complete = on_finished
	_is_active = true
	_dark_backdrop = dark_backdrop
	_current_line_idx = 0
	visible = true
	modulate.a = 1.0
	touch_area.mouse_filter = Control.MOUSE_FILTER_STOP

	if _dark_backdrop and backdrop != null:
		backdrop.visible = true
		backdrop.modulate.a = 0.0
		var b_tw := create_tween()
		b_tw.tween_property(backdrop, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		b_tw.tween_callback(_show_next_in_queue)
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
	asp.bus = "Master"
	add_child(asp)
	asp.finished.connect(asp.queue_free)
	asp.play()
