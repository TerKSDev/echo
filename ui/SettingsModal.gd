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

# Dynamic Mic Sensitivity & Calibration UI nodes
var _sens_slider: HSlider
var _sens_val: Label
var _calib_btn: Button
var _meter_canvas: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0

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

	if has_node("Dimmer"):
		$Dimmer.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				close()
		)

	_build_mic_calibration_ui()

	for b: Button in [resume_btn, restart_btn, menu_btn, mic_toggle, close_btn, _calib_btn]:
		if b != null:
			_wire_btn_anim(b)

	_player = get_tree().get_first_node_in_group("player")
	_update_mic_toggle_ui()


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


func _build_mic_calibration_ui() -> void:
	var insert_idx: int = $CenterContainer/Panel/VBox/MicRow.get_index() + 1

	# 1. Mic Sensitivity Header + Value
	var sens_header := HBoxContainer.new()
	var sens_lbl := Label.new()
	sens_lbl.text = "MIC SENSITIVITY"
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

	# 2. Mic Sensitivity Slider
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

	# 3. Live Mic Meter + Calibrate Button Row
	var calib_row := HBoxContainer.new()
	calib_row.add_theme_constant_override("separation", 12)

	_meter_canvas = Control.new()
	_meter_canvas.custom_minimum_size = Vector2(0, 32)
	_meter_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter_canvas.draw.connect(_draw_mic_meter)
	calib_row.add_child(_meter_canvas)

	_calib_btn = Button.new()
	_calib_btn.custom_minimum_size = Vector2(142, 34)
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


func _draw_mic_meter() -> void:
	var w: float = _meter_canvas.size.x
	var h: float = _meter_canvas.size.y
	var bar_y: float = 6.0
	var bar_h: float = 12.0

	# Track background (-70 dB .. -5 dB range)
	_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.03, 0.08, 0.15, 0.9))

	var mic := _get_mic()
	var cur_db: float = mic.level_db if (mic != null and GameState.mic_enabled) else -80.0
	var trig_db: float = GameState.get_mic_trigger_db()

	var fill_frac: float = clampf(inverse_lerp(-70.0, -5.0, cur_db), 0.0, 1.0)
	var trig_frac: float = clampf(inverse_lerp(-70.0, -5.0, trig_db), 0.0, 1.0)

	var active: bool = cur_db >= trig_db
	var fill_col: Color = Color(0.35, 0.95, 1.0, 0.95) if active else Color(0.22, 0.58, 0.85, 0.75)
	if fill_frac > 0.01:
		_meter_canvas.draw_rect(Rect2(0.0, bar_y, w * fill_frac, bar_h), fill_col)

	# Border
	_meter_canvas.draw_rect(Rect2(0.0, bar_y, w, bar_h), Color(0.24, 0.52, 0.78, 0.6), false, 1.0)

	# Trigger threshold marker line
	var tx: float = w * trig_frac
	_meter_canvas.draw_line(Vector2(tx, bar_y - 3.0), Vector2(tx, bar_y + bar_h + 3.0), Color(1.0, 0.82, 0.28, 0.95), 2.0)

	var hint_text := "SPEAK TO TEST  (YELLOW LINE = TRIGGER)"
	_meter_canvas.draw_string(ThemeDB.fallback_font, Vector2(0.0, bar_y + bar_h + 12.0), hint_text, HORIZONTAL_ALIGNMENT_LEFT, int(w), 9, Color(0.55, 0.78, 0.95, 0.65))


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
	if _sens_slider != null:
		_sens_slider.value = GameState.mic_sensitivity
	_update_mic_toggle_ui()

	var subtitle_lbl := get_node_or_null("CenterContainer/Panel/VBox/Header/Titles/Subtitle") as Label
	if subtitle_lbl != null:
		var path: String = GameState.current_level_path()
		var depth_str := "TEST ARENA"
		if path.find("level_") != -1 and path.find("test") == -1:
			depth_str = "DEPTH %s" % path.get_file().get_basename().replace("level_", "").to_upper()
		elif GameState.current_level > 0:
			depth_str = "DEPTH %02d" % GameState.current_level
		subtitle_lbl.text = "%s   •   SETTINGS & SYSTEM" % depth_str

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5 if panel.size.x > 50.0 else Vector2(240.0, 260.0)
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
	GameState.go_to_menu()
