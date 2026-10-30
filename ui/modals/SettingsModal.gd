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

# Essential Quick Settings Controls
var _scheme_btn: Button = null
var _layout_btn: Button = null
var _quick_lbl: Label = null
var _vol_hdr_lbl: Label = null
var _mic_lbl: Label = null
var _scheme_lbl: Label = null
var _layout_lbl: Label = null
var _custom_lbl: Label = null
var _custom_btn: Button = null
var _div3: ColorRect = null
var _hint_lbl: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	visible = false
	modulate.a = 0.0
	panel.custom_minimum_size.x = ModalTemplate.CARD_WIDTH
	panel.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(ModalTemplate.ThemeKind.SONAR))
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

	_build_streamlined_ui()

	for b: Button in [resume_btn, restart_btn, menu_btn, mic_toggle, close_btn, _scheme_btn, _layout_btn, _custom_btn]:
		if b != null:
			_wire_btn_anim(b)

	_player = get_tree().get_first_node_in_group("player")
	_update_mic_toggle_ui()
	_refresh_scheme_btn_ui()
	_refresh_layout_btn_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	ModalTemplate.apply_full_rect(self)
	if has_node("Dimmer"):
		ModalTemplate.apply_full_rect($Dimmer)
	if has_node("CenterContainer"):
		ModalTemplate.apply_full_rect($CenterContainer)


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


func _build_streamlined_ui() -> void:
	# 1. Extract MenuBtn from Actions and prepare containers
	var actions_box := $CenterContainer/Panel/VBox/Actions
	if menu_btn.get_parent() == actions_box:
		actions_box.remove_child(menu_btn)

	var div2 := $CenterContainer/Panel/VBox/Divider2

	# Quick Settings Category Header
	_quick_lbl = Label.new()
	_quick_lbl.text = "QUICK SYSTEM & CONTROLS"
	_quick_lbl.add_theme_font_size_override("font_size", 11)

	# Volume Header & Slider
	var vol_hdr := $CenterContainer/Panel/VBox/VolumeHeader
	_vol_hdr_lbl = vol_hdr.get_node_or_null("VolumeLabel") as Label
	var vol_row := $CenterContainer/Panel/VBox/VolumeRow

	# Microphone Row
	var mic_row := $CenterContainer/Panel/VBox/MicRow
	_mic_lbl = mic_row.get_node_or_null("MicLabel") as Label
	if _mic_lbl != null:
		_mic_lbl.text = "ACOUSTIC SENSOR"
	mic_toggle.custom_minimum_size = Vector2(130, 32)
	mic_toggle.theme = close_btn.theme

	# Movement Scheme Row (Joystick vs Drag & Tap)
	var scheme_row := HBoxContainer.new()
	_scheme_lbl = Label.new()
	_scheme_lbl.text = "MOVEMENT SCHEME"
	_scheme_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scheme_lbl.add_theme_font_size_override("font_size", 13)
	scheme_row.add_child(_scheme_lbl)

	_scheme_btn = Button.new()
	_scheme_btn.custom_minimum_size = Vector2(130, 32)
	_scheme_btn.focus_mode = Control.FOCUS_NONE
	_scheme_btn.theme = close_btn.theme
	_scheme_btn.add_theme_font_size_override("font_size", 12)
	_scheme_btn.pressed.connect(func():
		GameState.virtual_joystick_enabled = not GameState.virtual_joystick_enabled
		GameState.save_settings()
		_refresh_scheme_btn_ui()
		var hud = get_parent()
		if hud != null and hud.has_method("update_controls_layout"):
			hud.update_controls_layout()
	)
	scheme_row.add_child(_scheme_btn)

	# Action Buttons Position (Right vs Left handedness)
	var layout_row := HBoxContainer.new()
	_layout_lbl = Label.new()
	_layout_lbl.text = "ACTION BUTTONS SIDE"
	_layout_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_lbl.add_theme_font_size_override("font_size", 13)
	layout_row.add_child(_layout_lbl)

	_layout_btn = Button.new()
	_layout_btn.custom_minimum_size = Vector2(130, 32)
	_layout_btn.focus_mode = Control.FOCUS_NONE
	_layout_btn.theme = close_btn.theme
	_layout_btn.add_theme_font_size_override("font_size", 12)
	_layout_btn.pressed.connect(func():
		GameState.controls_layout = "left" if GameState.controls_layout == "right" else "right"
		GameState.save_settings()
		_refresh_layout_btn_ui()
		var hud = get_parent()
		if hud != null and hud.has_method("update_controls_layout"):
			hud.update_controls_layout()
	)
	layout_row.add_child(_layout_btn)

	# Custom HUD Layout Row (In the settings block, strictly ABOVE Level Select!)
	var custom_row := HBoxContainer.new()
	_custom_lbl = Label.new()
	_custom_lbl.text = "HUD LAYOUT & BUTTONS"
	_custom_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_lbl.add_theme_font_size_override("font_size", 13)
	custom_row.add_child(_custom_lbl)

	_custom_btn = Button.new()
	_custom_btn.text = "CUSTOMIZE HUD"
	_custom_btn.custom_minimum_size = Vector2(130, 32)
	_custom_btn.focus_mode = Control.FOCUS_NONE
	_custom_btn.theme = close_btn.theme
	_custom_btn.add_theme_font_size_override("font_size", 12)
	_custom_btn.pressed.connect(_open_customizer)
	custom_row.add_child(_custom_btn)

	# Divider 3 (Separates settings block from the Abandon / Level Select button)
	_div3 = ColorRect.new()
	_div3.custom_minimum_size = Vector2(0, 1)

	# Footer hint
	_hint_lbl = Label.new()
	_hint_lbl.text = "FULL AUDIO & CALIBRATION SETTINGS IN MAIN MENU"
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_font_size_override("font_size", 10)

	# Explicitly organize children in exact sequential order:
	var ordered_children: Array[Node] = [
		$CenterContainer/Panel/VBox/Header,
		$CenterContainer/Panel/VBox/Divider1,
		actions_box,
		div2,
		_quick_lbl,
		vol_hdr,
		vol_row,
		mic_row,
		scheme_row,
		layout_row,
		custom_row,
		_div3,
		menu_btn,
		_hint_lbl
	]

	for i in range(ordered_children.size()):
		var child: Node = ordered_children[i]
		if child.get_parent() != vbox:
			vbox.add_child(child)
		vbox.move_child(child, i)

	_apply_mode_theme()


func _apply_mode_theme() -> void:
	var is_chal := GameState.current_mode == GameState.GameMode.CHALLENGE
	var theme_kind: int = ModalTemplate.ThemeKind.SINGULARITY if is_chal else ModalTemplate.ThemeKind.SONAR

	# 1. Panel & Dimmer
	panel.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(theme_kind))
	if has_node("Dimmer"):
		$Dimmer.color = Color(0.02, 0.008, 0.025, 0.88) if is_chal else Color(0.01, 0.02, 0.045, 0.86)

	# 2. Header title & subtitle
	var title_lbl := get_node_or_null("CenterContainer/Panel/VBox/Header/Titles/Title") as Label
	if title_lbl != null:
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.96) if is_chal else Color(0.88, 0.95, 1.0))
	var sub_lbl := get_node_or_null("CenterContainer/Panel/VBox/Header/Titles/Subtitle") as Label
	if sub_lbl != null:
		sub_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.85, 0.85) if is_chal else Color(0.45, 0.75, 1.0, 0.75))

	# 3. Close button
	var close_norm := StyleBoxFlat.new()
	close_norm.set_corner_radius_all(19)
	var close_hov := StyleBoxFlat.new()
	close_hov.set_corner_radius_all(19)
	if is_chal:
		close_norm.bg_color = Color(0.20, 0.05, 0.18, 0.55)
		close_hov.bg_color = Color(0.38, 0.10, 0.32, 0.78)
		close_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.92, 0.88))
	else:
		close_norm.bg_color = Color(0.05, 0.14, 0.24, 0.50)
		close_hov.bg_color = Color(0.14, 0.30, 0.48, 0.75)
		close_btn.add_theme_color_override("font_color", Color(0.74, 0.88, 0.98, 0.88))
	close_btn.add_theme_stylebox_override("normal", close_norm)
	close_btn.add_theme_stylebox_override("hover", close_hov)
	close_btn.add_theme_stylebox_override("pressed", close_hov)

	# 4. Dividers
	var div1 := get_node_or_null("CenterContainer/Panel/VBox/Divider1") as ColorRect
	if div1 != null:
		div1.color = Color(0.85, 0.35, 0.75, 0.40) if is_chal else Color(0.2, 0.45, 0.7, 0.45)
	var div2 := get_node_or_null("CenterContainer/Panel/VBox/Divider2") as ColorRect
	if div2 != null:
		div2.color = Color(0.85, 0.35, 0.75, 0.40) if is_chal else Color(0.2, 0.45, 0.7, 0.45)
	if _div3 != null:
		_div3.color = Color(0.85, 0.35, 0.75, 0.35) if is_chal else Color(0.2, 0.45, 0.7, 0.35)

	# 5. Category Header & Label Colors
	if _quick_lbl != null:
		_quick_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.85, 0.95) if is_chal else Color(0.35, 0.78, 1.0, 0.95))
	var row_col := Color(0.95, 0.80, 0.92, 0.90) if is_chal else Color(0.65, 0.85, 1.0, 0.9)
	if _vol_hdr_lbl != null:
		_vol_hdr_lbl.add_theme_color_override("font_color", row_col)
	if _mic_lbl != null:
		_mic_lbl.add_theme_color_override("font_color", row_col)
	if _scheme_lbl != null:
		_scheme_lbl.add_theme_color_override("font_color", row_col)
	if _layout_lbl != null:
		_layout_lbl.add_theme_color_override("font_color", row_col)
	if _custom_lbl != null:
		_custom_lbl.add_theme_color_override("font_color", row_col)
	if _hint_lbl != null:
		_hint_lbl.add_theme_color_override("font_color", Color(0.70, 0.45, 0.65, 0.55) if is_chal else Color(0.35, 0.55, 0.75, 0.55))

	# 6. Sliders & Utility Buttons
	ModalTemplate.style_slider(volume_slider, theme_kind)
	if _custom_btn != null:
		ModalTemplate.style_button(_custom_btn, false, theme_kind)
	_update_volume_label(volume_slider.value)
	_update_mic_toggle_ui()
	_refresh_scheme_btn_ui()
	_refresh_layout_btn_ui()

	# 7. Action Buttons (Story vs Challenge Anti-Scumming)
	resume_btn.text = "RESUME GAME"
	resume_btn.custom_minimum_size = Vector2(0, 44)
	ModalTemplate.style_button(resume_btn, true, theme_kind)

	if is_chal:
		# Roguelite anti-scumming: Restart Sector completely removed to prevent resetting mistakes/damage
		restart_btn.visible = false
		menu_btn.text = "ABANDON RUN"
		menu_btn.custom_minimum_size = Vector2(0, 38)
		ModalTemplate.style_danger_button(menu_btn, false, false)
	else:
		restart_btn.visible = true
		restart_btn.text = "RESTART"
		restart_btn.custom_minimum_size = Vector2(0, 40)
		ModalTemplate.style_danger_button(restart_btn, false, false)
		menu_btn.text = "RETURN MAP"
		menu_btn.custom_minimum_size = Vector2(0, 36)
		ModalTemplate.style_button(menu_btn, false, ModalTemplate.ThemeKind.SONAR)


func _open_customizer() -> void:
	# Hide SettingsModal while keeping the level paused!
	visible = false
	_is_open = false
	var customizer := HudLayoutCustomizer.open(get_tree().root)
	customizer.closed.connect(func():
		# When returning from Customizer, re-open pause menu (still paused!)
		open()
	)


func _get_mic() -> MicInput:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and _player.has_node("MicInput"):
		return _player.get_node("MicInput") as MicInput
	return null


func is_pause_allowed() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and "alive" in _player and not _player.alive:
		return false
	var main := get_tree().current_scene
	if main != null and is_instance_valid(main) and main.get("_changing") == true:
		return false
	var hud := get_parent()
	if hud != null:
		if hud.has_node("DeathScreen") and hud.get_node("DeathScreen").visible:
			return false
		if hud.has_node("NoteReadModal") and hud.get_node("NoteReadModal").visible:
			return false
		if hud.has_node("DebriefModal") and hud.get_node("DebriefModal").visible:
			return false
		if hud.get("_debrief_modal") != null and is_instance_valid(hud.get("_debrief_modal")) and hud.get("_debrief_modal").visible:
			return false
		if hud.has_node("VictoryScreen") and hud.get_node("VictoryScreen").visible:
			return false
		if hud.get("story_overlay") != null and hud.story_overlay.has_method("is_active") and hud.story_overlay.is_active():
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _is_open:
			close()
			get_viewport().set_input_as_handled()
		elif not get_tree().paused and is_pause_allowed():
			open()
			get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open or not is_pause_allowed():
		return
	_is_open = true
	visible = true
	_sync_viewport_size()
	get_tree().paused = true

	_apply_mode_theme()

	volume_slider.value = GameState.master_volume
	_update_volume_ui_state()
	_update_mic_toggle_ui()
	_refresh_scheme_btn_ui()
	_refresh_layout_btn_ui()

	var subtitle_lbl := get_node_or_null("CenterContainer/Panel/VBox/Header/Titles/Subtitle") as Label
	if subtitle_lbl != null:
		var cur_lvl := GameState.current_level
		var sec_name := GameState.get_level_name(cur_lvl)
		var depth_str := GameState.get_level_depth_str(cur_lvl)
		subtitle_lbl.text = "%s   •   DEPTH %s" % [sec_name, depth_str]

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5 if panel.size.x > 50.0 else Vector2(ModalTemplate.CARD_WIDTH * 0.5, 200.0)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	if _player == null or not is_instance_valid(_player) or _player.get("alive") == true:
		get_tree().paused = false


func _on_volume_changed(val: float) -> void:
	GameState.set_master_volume(val)
	_update_volume_label(val)


func _update_volume_ui_state() -> void:
	var muted: bool = GameState.master_muted
	volume_slider.editable = not muted
	volume_slider.mouse_filter = Control.MOUSE_FILTER_STOP if not muted else Control.MOUSE_FILTER_IGNORE
	var vol_row: Control = get_node_or_null("CenterContainer/Panel/VBox/VolumeRow")
	if vol_row != null:
		vol_row.modulate.a = 0.38 if muted else 1.0
	_update_volume_label(volume_slider.value)


func _update_volume_label(val: float) -> void:
	var pct := int(round(val * 100.0))
	var is_chal := GameState.current_mode == GameState.GameMode.CHALLENGE
	if GameState.master_muted:
		volume_val.text = "%d%% (MUTED)" % pct
		volume_val.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75, 0.65))
	else:
		volume_val.text = "%d%%" % pct
		var font_col := Color(1.0, 0.60, 0.90, 0.95) if is_chal else Color(0.40, 0.90, 1.0, 0.95)
		volume_val.add_theme_color_override("font_color", font_col)


func _on_mic_toggle_pressed() -> void:
	if not GameState.mic_enabled:
		if OS.get_name() == "Android" and not GameState.is_mic_permission_granted():
			mic_toggle.disabled = true
			mic_toggle.text = "REQUESTING..."
			GameState.request_mic_permission(func(granted: bool) -> void:
				mic_toggle.disabled = false
				if granted:
					GameState.mic_enabled = true
					GameState.save_settings()
					var mic := _get_mic()
					if mic != null:
						mic.start()
				else:
					GameState.mic_enabled = false
					GameState.save_settings()
				_update_mic_toggle_ui()
				var hud := get_parent()
				if hud != null and hud.has_node("MicIndicator"):
					hud.get_node("MicIndicator").visible = GameState.mic_enabled
			)
			return

		GameState.mic_enabled = true
		GameState.save_settings()
		var mic := _get_mic()
		if mic != null:
			mic.start()
	else:
		GameState.mic_enabled = false
		GameState.save_settings()
		var mic := _get_mic()
		if mic != null:
			mic.enabled = false

	_update_mic_toggle_ui()
	var hud := get_parent()
	if hud != null and hud.has_node("MicIndicator"):
		hud.get_node("MicIndicator").visible = GameState.mic_enabled


func _update_mic_toggle_ui() -> void:
	var mic := _get_mic()
	var enabled: bool = GameState.mic_enabled and GameState.is_mic_permission_granted()
	if mic != null:
		if enabled:
			mic.start()
		else:
			mic.enabled = false
	mic_toggle.self_modulate = Color.WHITE
	var kind: int = ModalTemplate.ThemeKind.SINGULARITY if GameState.current_mode == GameState.GameMode.CHALLENGE else ModalTemplate.ThemeKind.SONAR
	ModalTemplate.style_toggle_button(mic_toggle, enabled, "ENABLED", "MUTED", kind)


func _on_restart_pressed() -> void:
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		return
	GameState.restart_level()


func _on_menu_pressed() -> void:
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		ChallengeResetModal.open(self, func():
			GameState.reset_challenge_run()
			get_tree().paused = false
			GameState.go_to_level_select()
		)
	else:
		get_tree().paused = false
		GameState.go_to_level_select()


func _refresh_scheme_btn_ui() -> void:
	if _scheme_btn == null:
		return
	_scheme_btn.self_modulate = Color.WHITE
	var kind: int = ModalTemplate.ThemeKind.SINGULARITY if GameState.current_mode == GameState.GameMode.CHALLENGE else ModalTemplate.ThemeKind.SONAR
	ModalTemplate.style_toggle_button(_scheme_btn, GameState.virtual_joystick_enabled, "JOYSTICK", "DRAG & TAP", kind)


func _refresh_layout_btn_ui() -> void:
	if _layout_btn == null:
		return
	_layout_btn.self_modulate = Color.WHITE
	var kind: int = ModalTemplate.ThemeKind.SINGULARITY if GameState.current_mode == GameState.GameMode.CHALLENGE else ModalTemplate.ThemeKind.SONAR
	ModalTemplate.style_toggle_button(_layout_btn, GameState.controls_layout == "right", "RIGHT SIDE", "LEFT SIDE", kind)
