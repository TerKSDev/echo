class_name NoteReadModal
extends Control
## Atmospheric Expedition Journal & Lore Note Reader Modal for ECHO.
## Displays parchment-styled lore notes with sound effects, depth stamps,
## author tags, and automatic archive collection tracking.

signal closed

var _dimmer: ColorRect
var _center: CenterContainer
var _panel: PanelContainer
var _is_open := false
var _time := 0.0

var _title_lbl: Label
var _tag_lbl: Label
var _author_lbl: Label
var _depth_lbl: Label
var _body_lbl: Label
var _close_prompt: Label
var _type_tween: Tween = null
var _is_typing := false

var _wav_paper: AudioStreamWAV
var _wav_close: AudioStreamWAV


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	z_index = 110
	visible = false
	modulate.a = 0.0
	_build_ui_audio()
	_build_modal_shell()
	_sync_viewport_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	ModalTemplate.apply_full_rect(self)
	if _dimmer != null:
		ModalTemplate.apply_full_rect(_dimmer)
	if _center != null:
		ModalTemplate.apply_full_rect(_center)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE)):
		if _is_typing and event.keycode != KEY_ESCAPE:
			_finish_typing_immediately()
		else:
			close()
		get_viewport().set_input_as_handled()


func _finish_typing_immediately() -> void:
	_is_typing = false
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	if _body_lbl != null:
		_body_lbl.visible_ratio = 1.0


func _process(delta: float) -> void:
	if not _is_open:
		return
	_time += delta
	if _close_prompt != null and is_instance_valid(_close_prompt):
		var pulse := 0.6 + 0.4 * sin(_time * 4.0)
		_close_prompt.modulate.a = pulse


static func open_note(parent: Node, note_data: Dictionary, on_closed: Callable = Callable()) -> Control:
	var host: Node = parent
	if host is Node2D and host.has_node("Hud"):
		host = host.get_node("Hud")
	var existing = host.get_node_or_null("NoteReadModal")
	if existing != null:
		existing.display_note(note_data, on_closed)
		return existing
	var script: GDScript = load("res://ui/modals/NoteReadModal.gd") as GDScript
	var modal := script.new() as Control
	modal.name = "NoteReadModal"
	host.add_child(modal)
	modal.display_note(note_data, on_closed)
	return modal


func display_note(note_data: Dictionary, on_closed: Callable = Callable()) -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_sync_viewport_size()

	_title_lbl.text = str(note_data.get("title", "LOST ARCHIVE"))
	_author_lbl.text = str(note_data.get("author", "Unknown Explorer"))
	_depth_lbl.text = str(note_data.get("depth", "Depth Unknown"))
	_body_lbl.text = str(note_data.get("text", "The ink has faded into darkness..."))

	# Save to collected archives persistently
	var nid: String = str(note_data.get("id", ""))
	if nid != "":
		GameState.collect_note(nid)

	if _tag_lbl != null:
		var col_c: int = GameState.get_collected_note_count()
		var tot_c: int = GameState.get_total_note_count()
		_tag_lbl.text = "◈   E X P E D I T I O N   A R C H I V E   •   %d / %d   ◈" % [col_c, tot_c]

	if on_closed.is_valid():
		closed.connect(on_closed, CONNECT_ONE_SHOT)

	_play_sound(_wav_paper, -4.0, 1.0)
	Input.vibrate_handheld(30)

	_body_lbl.visible_ratio = 0.0
	_is_typing = true
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(_body_lbl, "visible_ratio", 1.0, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_type_tween.tween_callback(func(): _is_typing = false)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = Vector2(ModalTemplate.CARD_WIDTH * 0.5, 220.0)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_play_sound(_wav_close, -6.0, 1.1)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	closed.emit()


func _build_modal_shell() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = ModalTemplate.DIMMER_COLOR
	_dimmer.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			if _is_typing:
				_finish_typing_immediately()
			else:
				close()
	)
	add_child(_dimmer)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 440)
	_panel.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(ModalTemplate.ThemeKind.ARCHIVE))
	_center.add_child(_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(outer_vbox)

	# --- Header Row: Tag & Close Button ---
	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var tag := Label.new()
	tag.text = "◈   E X P E D I T I O N   A R C H I V E   ◈"
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.add_theme_color_override("font_color", Color(0.92, 0.76, 0.36, 0.85))
	tag.add_theme_font_size_override("font_size", 11)
	header.add_child(tag)
	_tag_lbl = tag

	var close_btn := ModalTemplate.make_close_button(close, ModalTemplate.ThemeKind.ARCHIVE)
	header.add_child(close_btn)

	# --- Note Title ---
	_title_lbl = Label.new()
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82, 1.0))
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.5, 0.35, 0.1, 0.7))
	_title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_title_lbl.add_theme_font_size_override("font_size", 20)
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer_vbox.add_child(_title_lbl)

	# --- Subtitle: Author & Depth ---
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 10)
	outer_vbox.add_child(meta_row)

	_author_lbl = Label.new()
	_author_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_author_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.96, 0.78))
	_author_lbl.add_theme_font_size_override("font_size", 12)
	meta_row.add_child(_author_lbl)

	_depth_lbl = Label.new()
	_depth_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.40, 0.9))
	_depth_lbl.add_theme_font_size_override("font_size", 12)
	meta_row.add_child(_depth_lbl)

	# --- Gold Divider Line ---
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1.5)
	div.color = Color(0.85, 0.68, 0.28, 0.55)
	outer_vbox.add_child(div)

	# --- Scrollable Body Text ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_vbox.add_child(scroll)

	var text_margin := MarginContainer.new()
	text_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.add_theme_constant_override("margin_top", 4)
	text_margin.add_theme_constant_override("margin_bottom", 6)
	text_margin.add_theme_constant_override("margin_right", 8)
	scroll.add_child(text_margin)

	_body_lbl = Label.new()
	_body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96, 0.95))
	_body_lbl.add_theme_constant_override("line_spacing", 6)
	_body_lbl.add_theme_font_size_override("font_size", 14)
	text_margin.add_child(_body_lbl)

	# --- Footer: Close Prompt ---
	_close_prompt = Label.new()
	_close_prompt.text = "✦   A R C H I V E   R E C O R D E D   •   T A P   T O   C L O S E   ✦"
	_close_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_prompt.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 0.85))
	_close_prompt.add_theme_font_size_override("font_size", 11)
	outer_vbox.add_child(_close_prompt)


func _build_ui_audio() -> void:
	const MIX_RATE := 22050
	# Procedural parchment leaf unfold + warm D5-A5-D6 crystalline archive chime
	var dur := 0.48
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var lp_paper := 0.0
	var hp_paper := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var raw_n := randf() * 2.0 - 1.0
		lp_paper = lerpf(lp_paper, raw_n, 0.32)
		hp_paper = lerpf(hp_paper, lp_paper, 0.09)
		var rustle_env := sin(clampf(t / 0.13, 0.0, 1.0) * PI) * exp(-t * 24.0)
		var rustle := (lp_paper - hp_paper) * rustle_env * 0.42
		var chime_env := minf(t / 0.008, 1.0) * exp(-t * 8.2)
		var chime := (0.55 * sin(TAU * 587.33 * t) + 0.35 * sin(TAU * 880.0 * t) + 0.18 * sin(TAU * 1174.66 * t)) * chime_env
		out[i] = clampf((rustle + chime) * 0.52, -1.0, 1.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	var b := PackedByteArray()
	b.resize(count * 2)
	for i in count:
		var val := clampi(int(out[i] * 32767.0), -32768, 32767)
		b.encode_s16(i * 2, val)
	wav.data = b
	_wav_paper = wav

	# Procedural soft close click
	var c_dur := 0.18
	var c_count := int(c_dur * MIX_RATE)
	var c_out := PackedFloat32Array()
	c_out.resize(c_count)
	for i in c_count:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 22.0)
		var s := sin(TAU * 440.0 * t) * env * 0.35
		c_out[i] = clampf(s, -1.0, 1.0)
	var c_wav := AudioStreamWAV.new()
	c_wav.format = AudioStreamWAV.FORMAT_16_BITS
	c_wav.mix_rate = MIX_RATE
	var cb := PackedByteArray()
	cb.resize(c_count * 2)
	for i in c_count:
		var val := clampi(int(c_out[i] * 32767.0), -32768, 32767)
		cb.encode_s16(i * 2, val)
	c_wav.data = cb
	_wav_close = c_wav


func _play_sound(wav: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if wav == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
