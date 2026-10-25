extends Control

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var vbox: VBoxContainer = $CenterContainer/Panel/VBox
@onready var volume_slider: HSlider = $CenterContainer/Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_val: Label = $CenterContainer/Panel/VBox/VolumeHeader/VolumeVal
@onready var mic_toggle: Button = $CenterContainer/Panel/VBox/MicRow/MicToggle
@onready var resume_btn: Button = $CenterContainer/Panel/VBox/Actions/ResumeBtn
@onready var restart_btn: Button = $CenterContainer/Panel/VBox/Actions/RestartBtn
@onready var menu_btn: Button = $CenterContainer/Panel/VBox/Actions/MenuBtn
@onready var close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseBtn

var _is_open := false
var _player: Node = null

# Dynamic Audio & Mic Controls
var _mute_btn: Button
var _bgm_slider: HSlider
var _bgm_val: Label
var _sfx_slider: HSlider
var _sfx_val: Label
var _sens_slider: HSlider
var _sens_val: Label
var _calib_btn: Button
var _meter_canvas: Control
var _blind_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_sync_viewport_size()

	var bus_idx := AudioServer.get_bus_index("Master")
	var current_vol := db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	volume_slider.value = current_vol
	_update_volume_label(current_vol)

	volume_slider.value_changed.connect(_on_volume_changed)
	mic_toggle.pressed.connect(_on_mic_toggle_pressed)
	resume_btn.pressed.connect(close)
	restart_btn.pressed.connect(_on_restart_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	close_btn.pressed.connect(close)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if has_node("Dimmer"):
		$Dimmer.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				close()
		)

	_build_extra_ui()

	for b: Button in [resume_btn, restart_btn, menu_btn, mic_toggle, close_btn, _calib_btn, _mute_btn]:
		if b != null:
			_wire_btn_anim(b)

	_player = get_tree().get_first_node_in_group("player")
	_update_mute_toggle_ui()
	_update_mic_toggle_ui()
	_refresh_blind_btn_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 50.0 and vp.y > 50.0:
		size = vp
		if has_node("Dimmer"):
			$Dimmer.size = vp
		if has_node("CenterContainer"):
			$CenterContainer.size = vp


func _wire_btn_anim(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(1.02, 1.02), 0.08)
	)
	btn.mouse_exited.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2.ONE, 0.1)
	)
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(0.96, 0.96), 0.05)
	)
	btn.button_up.connect(func():
		btn.pivot_offset = btn.size * 0.5
		create_tween().tween_property(btn, "scale", Vector2(1.02, 1.02), 0.1)
	)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	var mic := _get_mic()
	if mic != null and _calib_btn != null:
		if mic.is_calibrating():
			_calib_btn.text = "SAMPLING..."
			_calib_btn.disabled = true
		else:
			_calib_btn.text = "CALIBRATE ROOM"
			_calib_btn.disabled = not GameState.mic_enabled
	if _meter_canvas != null:
		_meter_canvas.queue_redraw()


func _build_extra_ui() -> void:
	# Category Header 1: AUDIO OUTPUT
	var audio_idx: int = $CenterContainer/Panel/VBox/VolumeHeader.get_index()
	var audio_lbl := Label.new()
	audio_lbl.text = "AUDIO OUTPUT"
	audio_lbl.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 0.95))
	audio_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(audio_lbl)
	vbox.move_child(audio_lbl, audio_idx)
	audio_idx += 1

	# Master Audio Output Mute Toggle Row
	var mute_row := HBoxContainer.new()
	var mute_lbl := Label.new()
	mute_lbl.text = "MASTER AUDIO OUTPUT"
	mute_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	mute_lbl.add_theme_font_size_override("font_size", 13)

	_mute_btn = Button.new()
	_mute_btn.custom_minimum_size = Vector2(130, 32)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	_mute_btn.theme = close_btn.theme
	_mute_btn.add_theme_font_size_override("font_size", 12)
	_mute_btn.pressed.connect(_on_mute_toggle_pressed)
	mute_row.add_child(mute_lbl)
	mute_row.add_child(_mute_btn)
	vbox.add_child(mute_row)
	vbox.move_child(mute_row, audio_idx)

	# After VolumeRow: insert BGM and SFX volume sliders
	var audio_insert: int = $CenterContainer/Panel/VBox/VolumeRow.get_index() + 1

	# Ambience & Music (BGM)
	var bgm_header := HBoxContainer.new()
	var bgm_lbl := Label.new()
	bgm_lbl.text = "AMBIENCE & MUSIC"
	bgm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	bgm_lbl.add_theme_font_size_override("font_size", 13)

	_bgm_val = Label.new()
	_bgm_val.text = "%d%%" % int(round(GameState.bgm_volume * 100.0))
	_bgm_val.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_bgm_val.add_theme_font_size_override("font_size", 13)
	bgm_header.add_child(bgm_lbl)
	bgm_header.add_child(_bgm_val)
	vbox.add_child(bgm_header)
	vbox.move_child(bgm_header, audio_insert)
	audio_insert += 1

	_bgm_slider = HSlider.new()
	_bgm_slider.custom_minimum_size = Vector2(0, 24)
	_bgm_slider.max_value = 1.0
	_bgm_slider.step = 0.01
	_bgm_slider.value = GameState.bgm_volume
	_bgm_slider.focus_mode = Control.FOCUS_NONE
	_bgm_slider.theme = close_btn.theme
	_bgm_slider.value_changed.connect(func(v: float):
		GameState.set_bgm_volume(v)
		_bgm_val.text = "%d%%" % int(round(v * 100.0))
	)
	vbox.add_child(_bgm_slider)
	vbox.move_child(_bgm_slider, audio_insert)
	audio_insert += 1

	# Sound Effects (SFX)
	var sfx_header := HBoxContainer.new()
	var sfx_lbl := Label.new()
	sfx_lbl.text = "SOUND EFFECTS (SFX)"
	sfx_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	sfx_lbl.add_theme_font_size_override("font_size", 13)

	_sfx_val = Label.new()
	_sfx_val.text = "%d%%" % int(round(GameState.sfx_volume * 100.0))
	_sfx_val.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_sfx_val.add_theme_font_size_override("font_size", 13)
	sfx_header.add_child(sfx_lbl)
	sfx_header.add_child(_sfx_val)
	vbox.add_child(sfx_header)
	vbox.move_child(sfx_header, audio_insert)
	audio_insert += 1

	_sfx_slider = HSlider.new()
	_sfx_slider.custom_minimum_size = Vector2(0, 24)
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.01
	_sfx_slider.value = GameState.sfx_volume
	_sfx_slider.focus_mode = Control.FOCUS_NONE
	_sfx_slider.theme = close_btn.theme
	_sfx_slider.value_changed.connect(func(v: float):
		GameState.set_sfx_volume(v)
		_sfx_val.text = "%d%%" % int(round(v * 100.0))
	)
	vbox.add_child(_sfx_slider)
	vbox.move_child(_sfx_slider, audio_insert)
	audio_insert += 1

	# Divider + Category Header 2: MICROPHONE INPUT
	var mic_idx: int = $CenterContainer/Panel/VBox/MicRow.get_index()
	var mic_div := ColorRect.new()
	mic_div.custom_minimum_size = Vector2(0, 1)
	mic_div.color = Color(0.2, 0.45, 0.7, 0.45)
	vbox.add_child(mic_div)
	vbox.move_child(mic_div, mic_idx)

	var mic_sec_lbl := Label.new()
	mic_sec_lbl.text = "MICROPHONE INPUT"
	mic_sec_lbl.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 0.95))
	mic_sec_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(mic_sec_lbl)
	vbox.move_child(mic_sec_lbl, mic_idx + 1)

	var insert_idx: int = $CenterContainer/Panel/VBox/MicRow.get_index() + 1

	# 1. Microphone Sensitivity Header + Value (unified: MICROPHONE SENSITIVITY)
	var sens_header := HBoxContainer.new()
	var sens_lbl := Label.new()
	sens_lbl.text = "MICROPHONE SENSITIVITY"
	sens_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	sens_lbl.add_theme_font_size_override("font_size", 13)

	_sens_val = Label.new()
	_sens_val.text = "%d%%" % int(round(GameState.mic_sensitivity * 100.0))
	_sens_val.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_sens_val.add_theme_font_size_override("font_size", 13)

	sens_header.add_child(sens_lbl)
	sens_header.add_child(_sens_val)
	vbox.add_child(sens_header)
	vbox.move_child(sens_header, insert_idx)
	insert_idx += 1

	# 2. Microphone Sensitivity Slider
	_sens_slider = HSlider.new()
	_sens_slider.custom_minimum_size = Vector2(0, 24)
	_sens_slider.max_value = 1.0
	_sens_slider.step = 0.01
	_sens_slider.value = GameState.mic_sensitivity
	_sens_slider.focus_mode = Control.FOCUS_NONE
	_sens_slider.theme = close_btn.theme
	_sens_slider.value_changed.connect(func(v: float):
		GameState.mic_sensitivity = v
		_sens_val.text = "%d%%" % int(round(v * 100.0))
		GameState.save_settings()
	)
	vbox.add_child(_sens_slider)
	vbox.move_child(_sens_slider, insert_idx)
	insert_idx += 1

	# 3. Live Microphone Meter + Calibrate Button Row
	var calib_row := HBoxContainer.new()
	calib_row.add_theme_constant_override("separation", 10)

	_meter_canvas = Control.new()
	_meter_canvas.custom_minimum_size = Vector2(0, 32)
	_meter_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter_canvas.draw.connect(_draw_mic_meter)
	calib_row.add_child(_meter_canvas)

	mic_toggle.custom_minimum_size = Vector2(130, 32)

	_calib_btn = Button.new()
	_calib_btn.custom_minimum_size = Vector2(130, 32)
	_calib_btn.focus_mode = Control.FOCUS_NONE
	_calib_btn.theme = close_btn.theme
	_calib_btn.add_theme_font_size_override("font_size", 12)
	_calib_btn.text = "CALIBRATE ROOM"
	_calib_btn.pressed.connect(func():
		var mic := _get_mic()
		if mic != null:
			mic.recalibrate()
	)
	calib_row.add_child(_calib_btn)

	vbox.add_child(calib_row)
	vbox.move_child(calib_row, insert_idx)
	insert_idx += 1

	var hint_lbl := Label.new()
	hint_lbl.text = "SPEAK TO TEST  •  YELLOW LINE = TRIGGER THRESHOLD"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", Color(0.42, 0.65, 0.85, 0.65))
	vbox.add_child(hint_lbl)
	vbox.move_child(hint_lbl, insert_idx)

	# Divider + Category Header: ACCESSIBILITY & BLIND NAVIGATION
	var act_idx: int = $CenterContainer/Panel/VBox/Actions.get_index()
	var assist_div := ColorRect.new()
	assist_div.custom_minimum_size = Vector2(0, 1)
	assist_div.color = Color(0.2, 0.45, 0.7, 0.45)
	vbox.add_child(assist_div)
	vbox.move_child(assist_div, act_idx)
	act_idx += 1

	var blind_row := HBoxContainer.new()
	var blind_lbl := Label.new()
	blind_lbl.text = "BLIND ASSIST / 视障声学导航"
	blind_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blind_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	blind_lbl.add_theme_font_size_override("font_size", 13)
	blind_row.add_child(blind_lbl)

	_blind_btn = Button.new()
	_blind_btn.custom_minimum_size = Vector2(130, 32)
	_blind_btn.focus_mode = Control.FOCUS_NONE
	_blind_btn.theme = close_btn.theme
	_blind_btn.add_theme_font_size_override("font_size", 12)
	_refresh_blind_btn_ui()
	_blind_btn.pressed.connect(func():
		GameState.blind_assist_mode = not GameState.blind_assist_mode
		GameState.save_settings()
		_refresh_blind_btn_ui()
		var sfx_mgr = get_tree().get_first_node_in_group("sfx_manager")
		if sfx_mgr == null:
			sfx_mgr = get_node_or_null("../SfxManager")
		if sfx_mgr != null and sfx_mgr.has_method("play_assist_toggle"):
			sfx_mgr.play_assist_toggle(GameState.blind_assist_mode)
	)
	_wire_btn_anim(_blind_btn)
	blind_row.add_child(_blind_btn)
	vbox.add_child(blind_row)
	vbox.move_child(blind_row, act_idx)
	act_idx += 1

	# Category Header 3: EXPEDITION NAVIGATION
	var act_lbl := Label.new()
	act_lbl.text = "EXPEDITION NAVIGATION"
	act_lbl.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 0.95))
	act_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(act_lbl)
	vbox.move_child(act_lbl, act_idx)


func _draw_mic_meter() -> void:
	var w: float = _meter_canvas.size.x
	var h: float = _meter_canvas.size.y
	var bar_h: float = 16.0
	var bar_y: float = (h - bar_h) * 0.5

	# Track background (-70 dB .. -5 dB range)
	_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.02, 0.06, 0.12, 0.95), true)

	var mic := _get_mic()
	var cur_db: float = mic.level_db if (mic != null and GameState.mic_enabled) else -80.0
	var trig_db: float = GameState.get_mic_trigger_db()

	var fill_frac: float = clampf(inverse_lerp(-70.0, -5.0, cur_db), 0.0, 1.0)
	var trig_frac: float = clampf(inverse_lerp(-70.0, -5.0, trig_db), 0.0, 1.0)

	var active: bool = cur_db >= trig_db
	var fill_col: Color = Color(0.35, 0.95, 1.0, 0.95) if active else Color(0.20, 0.55, 0.80, 0.80)
	if fill_frac > 0.01:
		_meter_canvas.draw_rect(Rect2(0.0, bar_y, w * fill_frac, bar_h), fill_col, true)

	# Border
	_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.24, 0.52, 0.78, 0.65), false, 1.0)

	# Trigger threshold marker line
	var tx: float = clampf(w * trig_frac, 2.0, w - 2.0)
	_meter_canvas.draw_line(Vector2(tx, bar_y - 2.5), Vector2(tx, bar_y + bar_h + 2.5), Color(1.0, 0.85, 0.30, 1.0), 2.0)


func _get_mic() -> MicInput:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and _player.has_node("MicInput"):
		return _player.get_node("MicInput") as MicInput
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and not _player.get("alive"):
		return
	var hud := get_parent()
	if hud != null and hud.has_node("DeathScreen") and hud.get_node("DeathScreen").visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and not _player.get("alive"):
		return
	_is_open = true
	visible = true
	get_tree().paused = true

	volume_slider.value = GameState.master_volume
	_update_volume_label(GameState.master_volume)
	if _bgm_slider != null:
		_bgm_slider.value = GameState.bgm_volume
		_bgm_val.text = "%d%%" % int(round(GameState.bgm_volume * 100.0))
	if _sfx_slider != null:
		_sfx_slider.value = GameState.sfx_volume
		_sfx_val.text = "%d%%" % int(round(GameState.sfx_volume * 100.0))
	if _sens_slider != null:
		_sens_slider.value = GameState.mic_sensitivity
	_update_mute_toggle_ui()
	_update_mic_toggle_ui()
	_refresh_blind_btn_ui()

	var subtitle_lbl := get_node_or_null("CenterContainer/Panel/VBox/Header/Titles/Subtitle") as Label
	if subtitle_lbl != null:
		var cur_lvl := GameState.current_level
		var sec_name := GameState.get_level_name(cur_lvl)
		subtitle_lbl.text = "%s   •   SETTINGS & SYSTEM" % sec_name

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5 if panel.size.x > 50.0 else Vector2(290.0, 260.0)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	if _player == null or not is_instance_valid(_player) or bool(_player.get("alive")):
		get_tree().paused = false


func _on_volume_changed(val: float) -> void:
	GameState.set_master_volume(val)
	_update_volume_label(val)


func _update_volume_label(val: float) -> void:
	var pct := int(round(val * 100.0))
	volume_val.text = "%d%%" % pct


func _on_mute_toggle_pressed() -> void:
	GameState.set_master_muted(not GameState.master_muted)
	_update_mute_toggle_ui()


func _update_mute_toggle_ui() -> void:
	if _mute_btn == null:
		return
	if not GameState.master_muted:
		_mute_btn.text = "ENABLED"
		_mute_btn.self_modulate = Color(0.35, 1.2, 1.8, 1.0)
	else:
		_mute_btn.text = "MUTED"
		_mute_btn.self_modulate = Color(0.9, 0.45, 0.45, 0.9)


func _on_mic_toggle_pressed() -> void:
	GameState.mic_enabled = not GameState.mic_enabled
	GameState.save_settings()
	var mic := _get_mic()
	if mic != null:
		mic.enabled = GameState.mic_enabled
	_update_mic_toggle_ui()


func _update_mic_toggle_ui() -> void:
	var mic := _get_mic()
	var enabled: bool = GameState.mic_enabled
	if mic != null:
		mic.enabled = enabled
	if enabled:
		mic_toggle.text = "ENABLED"
		mic_toggle.self_modulate = Color(0.35, 1.2, 1.8, 1.0)
	else:
		mic_toggle.text = "MUTED"
		mic_toggle.self_modulate = Color(0.7, 0.7, 0.7, 0.7)


func _on_restart_pressed() -> void:
	GameState.restart_level()


func _on_menu_pressed() -> void:
	GameState.go_to_level_select()


func _refresh_blind_btn_ui() -> void:
	if _blind_btn == null:
		return
	if GameState.blind_assist_mode:
		_blind_btn.text = "ACTIVE"
		_blind_btn.self_modulate = Color(0.35, 1.2, 1.8, 1.0)
	else:
		_blind_btn.text = "OFF"
		_blind_btn.self_modulate = Color(0.7, 0.7, 0.7, 0.7)
