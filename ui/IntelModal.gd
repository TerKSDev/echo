extends Control
class_name IntelModal

const Monsters = preload("res://ui/icons/Monsters.gd")
## Survival Intel & Acoustic Bestiary Modal for ECHO.
## Displays Threat Archives (Sleeper, Patroller, Chaser, Screamer, Listener),
## interactive acoustic provocation preview, Core Non-Violence Ethos,
## and Dual-Spectrum Universal Accessibility guides.

signal closed

var _dimmer: ColorRect
var _center: CenterContainer
var _panel: PanelContainer
var _title_lbl: Label
var _subtitle_lbl: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _is_open := false
var _time := 0.0

var _bestiary_entries: Array[Dictionary] = []
var _sfx_mgr: SfxManager
var _wav_click: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_sync_viewport_size()
	_build_ui_audio()
	_init_sfx_manager()
	_build_modal_shell()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 50.0 and vp.y > 50.0:
		size = vp
		if _dimmer != null:
			_dimmer.size = vp
		if _center != null:
			_center.size = vp


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _is_open:
		return
	_time += delta

	for entry in _bestiary_entries:
		var timer: float = float(entry.get("timer", 0.0)) + delta
		entry["timer"] = timer
		var shake: float = maxf(0.0, float(entry.get("shake", 0.0)) - delta * 15.0)
		entry["shake"] = shake
		var shockwaves: Array = entry.get("shockwaves", [])
		for sw in shockwaves:
			sw["r"] = float(sw.get("r", 0.0)) + delta * 110.0
		entry["shockwaves"] = shockwaves.filter(func(sw): return float(sw.get("r", 0.0)) < float(sw.get("max_r", 90.0)))
		var canvas: Control = entry.get("canvas", null)
		if canvas != null and is_instance_valid(canvas):
			canvas.queue_redraw()


static func open_modal(parent: Node) -> Control:
	var existing = parent.get_node_or_null("IntelModal")
	if existing != null:
		existing.open()
		return existing
	var script: GDScript = load("res://ui/IntelModal.gd") as GDScript
	var modal := script.new() as Control
	modal.name = "IntelModal"
	parent.add_child(modal)
	modal.open()
	return modal


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_sync_viewport_size()
	_populate_content()

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel.scale = Vector2(0.93, 0.93)
	_panel.pivot_offset = Vector2(290.0, 300.0)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_bestiary_entries.clear()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	closed.emit()


func _build_modal_shell() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0.0, 0.02, 0.05, 0.85)
	_dimmer.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			close()
	)
	add_child(_dimmer)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(580, 620)
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 24.0
	card_style.content_margin_top = 20.0
	card_style.content_margin_right = 24.0
	card_style.content_margin_bottom = 22.0
	card_style.bg_color = Color(0.04, 0.11, 0.2, 0.96)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.28, 0.6, 0.88, 0.85)
	card_style.set_corner_radius_all(18)
	card_style.shadow_color = Color(0.08, 0.38, 0.72, 0.35)
	card_style.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", card_style)
	_center.add_child(_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	_title_lbl = Label.new()
	_title_lbl.text = "SURVIVAL INTEL"
	_title_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	_title_lbl.add_theme_font_size_override("font_size", 24)
	title_box.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = "ACOUSTIC BESTIARY • TAP ENTITY TO PROVOKE EFFECTS"
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.45, 0.76, 1.0, 0.78))
	_subtitle_lbl.add_theme_font_size_override("font_size", 11)
	title_box.add_child(_subtitle_lbl)

	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 16)
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.05, 0.14, 0.24, 0.45)
	close_normal.set_corner_radius_all(20)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.14, 0.32, 0.50, 0.7)
	close_hover.set_corner_radius_all(20)
	close_btn.add_theme_stylebox_override("normal", close_normal)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_color_override("font_color", Color(0.70, 0.85, 0.98, 0.85))
	close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var top_div := ColorRect.new()
	top_div.custom_minimum_size = Vector2(0, 1)
	top_div.color = Color(0.2, 0.48, 0.74, 0.45)
	outer_vbox.add_child(top_div)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(530, 480)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_vbox.add_child(_scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 8)
	scroll_margin.add_theme_constant_override("margin_right", 8)
	scroll_margin.add_theme_constant_override("margin_top", 4)
	scroll_margin.add_theme_constant_override("margin_bottom", 4)
	_scroll.add_child(scroll_margin)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll_margin.add_child(_body)


func _populate_content() -> void:
	for child in _body.get_children():
		child.queue_free()
	_bestiary_entries.clear()

	_add_section_header("THREAT ARCHIVE & ACOUSTIC SPECIMENS")

	_add_bestiary_card(
		"sleeper",
		Color(0.72, 0.45, 1.0),
		"SLEEPER",
		"DORMANT LURKER",
		"Remains in deep torpor within the shadows. Awakens only if you sprint or step directly into its immediate proximity halo.",
		"Hold SNEAK to quietly slip past its sleep radius."
	)
	_add_bestiary_card(
		"patroller",
		Color(1.0, 0.82, 0.25),
		"PATROLLER",
		"ACOUSTIC SENTRY",
		"Relentlessly paces fixed cavern paths. Acute stereoscopic hearing allows it to detect even sneaking footsteps when within close range.",
		"Observe its patrol route; wait behind solid stone corners."
	)
	_add_bestiary_card(
		"chaser",
		Color(1.0, 0.28, 0.28),
		"CHASER",
		"APEX PREDATOR",
		"Deaf to subtle sneaking footfalls, but possesses lethal charge velocity. The moment an acoustic wave touches it, it charges straight toward the sound origin.",
		"Never shout or emit sonar when a Chaser lurks near."
	)
	_add_bestiary_card(
		"screamer",
		Color(0.95, 0.32, 0.72),
		"SCREAMER",
		"SONIC COCOON",
		"Stationary vocal entity. When disturbed by consecutive sound waves, it unleashes a deafening screech that reverberates across the entire cavern.",
		"Hide behind solid obstacles to block its concussive screech."
	)
	_add_bestiary_card(
		"listener",
		Color(0.22, 0.95, 0.68),
		"LISTENER",
		"THE HIVE EAR",
		"Completely deaf to normal footsteps. Accumulates sound waves; on reaching its 5th acoustic trigger, it transmits a global alarm to all beasts in the sector.",
		"Minimize voice and sonar usage; extract swiftly."
	)

	_add_divider()
	_add_section_header("CORE ETHOS • 核心正向价值与非暴力生存")
	_add_guide_row(Color(0.35, 0.95, 0.75), "NON-VIOLENCE", "ECHO contains zero weapons and zero violence. Survival is achieved through mindfulness, calmness, and acoustic deflection rather than destruction.")
	_add_guide_row(Color(0.45, 0.82, 1.0), "INNER RESILIENCE", "The subterranean ascent represents overcoming mental darkness, anxiety, and panic. Silence is your shield; resonance is your compass.")

	_add_divider()
	_add_section_header("UNIVERSAL ACCESSIBILITY • 双向无障碍设计")
	_add_guide_row(Color(0.35, 0.95, 0.75), "BLIND PLAYABLE", "Full 3D binaural audio & haptic blind navigation: periodic exit beacons, acoustic wall reflection echoes, obstacle cane feelers, and directional keyboard controls enable players to navigate and complete sectors purely by ear.")
	_add_guide_row(Color(1.0, 0.78, 0.28), "DEAF INCLUSIVE", "100% of spatial sounds are translated into visual acoustic waveforms and off-screen indicators. Hearing-impaired players can achieve S-Rank mastery in pure silence.")
	_add_guide_row(Color(0.85, 0.70, 1.0), "TACTILE & SPEECH", "Full touch alternatives for voice input allow seamless play in public spaces or for players with vocal/speech considerations.")


func _add_bestiary_card(
	monster_type: String,
	badge_color: Color,
	monster_name: String,
	role_text: String,
	description: String,
	tip: String
) -> void:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 12.0
	card_style.content_margin_top = 10.0
	card_style.content_margin_right = 14.0
	card_style.content_margin_bottom = 10.0
	card_style.bg_color = Color(0.018, 0.048, 0.088, 0.92)
	card_style.border_color = badge_color.lerp(Color.WHITE, 0.25)
	card_style.border_color.a = 0.55
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(hbox)

	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(96, 96)
	preview_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pbox_style := StyleBoxFlat.new()
	pbox_style.bg_color = Color(0.012, 0.028, 0.052, 0.96)
	pbox_style.border_color = badge_color * Color(1.0, 1.0, 1.0, 0.65)
	pbox_style.set_border_width_all(1)
	pbox_style.set_corner_radius_all(10)
	preview_box.add_theme_stylebox_override("panel", pbox_style)
	hbox.add_child(preview_box)

	var preview_canvas := Control.new()
	preview_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	preview_box.add_child(preview_canvas)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	hbox.add_child(vb)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	vb.add_child(r1)

	var name_lbl := Label.new()
	name_lbl.text = monster_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", badge_color.lerp(Color.WHITE, 0.45))
	r1.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = "[ %s ]" % role_text
	role_lbl.add_theme_font_size_override("font_size", 10)
	role_lbl.add_theme_color_override("font_color", Color(badge_color.r, badge_color.g, badge_color.b, 0.75))
	role_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(role_lbl)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)
	r1.add_child(status_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98, 0.92))
	vb.add_child(desc_lbl)

	var tip_lbl := Label.new()
	tip_lbl.text = "SURVIVAL: " + tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", Color(0.40, 0.82, 1.0, 0.90))
	vb.add_child(tip_lbl)

	var hint_lbl := Label.new()
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", Color(0.52, 0.72, 0.88, 0.75))
	vb.add_child(hint_lbl)

	var entry := {
		"type": monster_type,
		"name": monster_name,
		"role": role_text,
		"color": badge_color,
		"stage": 0,
		"pips": 0,
		"timer": 0.0,
		"shake": 0.0,
		"shockwaves": [],
		"canvas": preview_canvas,
		"box": preview_box,
		"status_lbl": status_lbl,
		"hint_lbl": hint_lbl
	}
	_update_bestiary_entry_labels(entry)
	_bestiary_entries.append(entry)

	preview_canvas.draw.connect(func():
		Monsters.draw_monster_preview(preview_canvas, entry, _time)
	)
	preview_canvas.gui_input.connect(_on_monster_canvas_gui_input.bind(entry))

	_body.add_child(card)


func _update_bestiary_entry_labels(entry: Dictionary) -> void:
	var m_type: String = str(entry.get("type", ""))
	var stage: int = int(entry.get("stage", 0))
	var col: Color = entry.get("color", Color.WHITE)
	var status_lbl: Label = entry.get("status_lbl", null)
	var hint_lbl: Label = entry.get("hint_lbl", null)
	if status_lbl == null or not is_instance_valid(status_lbl):
		return

	match m_type:
		"screamer":
			if stage == 0:
				status_lbl.text = "[ STABLE COCOON ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: 1st Sound Fracture"
			elif stage == 1:
				status_lbl.text = "[ FRACTURED / WARNING ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
				hint_lbl.text = "▶ TAP AGAIN: 2nd Sound (DEAFENING SCREAM)"
			else:
				status_lbl.text = "[ DEAFENING SCREAM ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.35))
				hint_lbl.text = "▶ ACOUSTIC SHOCKWAVE ACTIVE (TAP TO CALM)"
		"sleeper":
			if stage == 0:
				status_lbl.text = "[ DEEP TORPOR ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Provoke Sleeper"
			elif stage == 1:
				status_lbl.text = "[ EYE OPEN / STIRRING ]"
				status_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0))
				hint_lbl.text = "▶ TAP AGAIN: Trigger Alert Roar"
			else:
				status_lbl.text = "[ ALERT ROAR ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
				hint_lbl.text = "▶ LURKER AWAKENED (TAP TO CALM)"
		"patroller":
			if stage == 0:
				status_lbl.text = "[ FIXED PATROL ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Trigger Radar Sweep"
			elif stage == 1:
				status_lbl.text = "[ ACTIVE RADAR SWEEP ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
				hint_lbl.text = "▶ TAP AGAIN: Sentry Detection Roar"
			else:
				status_lbl.text = "[ SENTRY ALERT ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
				hint_lbl.text = "▶ TARGET ACQUIRED (TAP TO CALM)"
		"chaser":
			if stage == 0:
				status_lbl.text = "[ DORMANT STALKER ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Agitate Apex Predator"
			elif stage == 1:
				status_lbl.text = "[ FRENZIED SPIN ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
				hint_lbl.text = "▶ TAP AGAIN: Lethal Apex Charge Roar"
			else:
				status_lbl.text = "[ APEX RUSH ROAR ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.2))
				hint_lbl.text = "▶ CHARGING AT FULL SPEED (TAP TO CALM)"
		"listener":
			var pips: int = int(entry.get("pips", 0))
			if pips == 0:
				status_lbl.text = "[ PASSIVE (0/5 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: Accumulate Acoustic Sound"
			elif pips < 4:
				status_lbl.text = "[ ACOUSTIC PIPS %d/5 ]" % pips
				status_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75))
				hint_lbl.text = "▶ TAP AGAIN: Sound Pip (%d/5)" % (pips + 1)
			elif pips == 4:
				status_lbl.text = "[ CRITICAL (4/5 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
				hint_lbl.text = "▶ TAP AGAIN: 5/5 GLOBAL HIVE ALARM!"
			else:
				status_lbl.text = "[ GLOBAL ALARM TRANSMITTED ]"
				status_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.65))
				hint_lbl.text = "▶ HIVE ALARM REVERBERATING (TAP TO RESET)"


func _on_monster_canvas_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_on_bestiary_entity_clicked(entry)


func _on_bestiary_entity_clicked(entry: Dictionary) -> void:
	var m_type: String = str(entry.get("type", ""))
	var cur_stage: int = int(entry.get("stage", 0))

	var box: PanelContainer = entry.get("box", null)
	if box != null and is_instance_valid(box):
		box.pivot_offset = box.size * 0.5
		var tw := create_tween()
		tw.tween_property(box, "scale", Vector2(1.10, 1.10), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(box, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var sfx := _get_or_create_sfx_mgr()

	match m_type:
		"screamer":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_screamer_crack, 1.5, randf_range(0.96, 1.04))
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.45, 0.95)},
					{"r": -22.0, "max_r": 95.0, "col": Color(1.0, 0.35, 0.65, 0.85)},
					{"r": -44.0, "max_r": 95.0, "col": Color(1.0, 0.5, 0.8, 0.75)}
				]
				_play_ui_sound(sfx._wav_screamer_shriek, 3.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"sleeper":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.5
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_echo_ping, -10.0, 0.75)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 10.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(0.72, 0.45, 1.0, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(0.85, 0.65, 1.0, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_sleeper, 2.5, 0.95)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"patroller":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_echo_ping, -8.0, 1.35)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 9.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(1.0, 0.82, 0.25, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(1.0, 0.95, 0.5, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_patroller, 2.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"chaser":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(sfx._wav_charge_full, -6.0, 0.85)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.2, 0.95)},
					{"r": -25.0, "max_r": 95.0, "col": Color(1.0, 0.4, 0.4, 0.8)}
				]
				_play_ui_sound(sfx._wav_roar_chaser, 3.0, 1.05)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"listener":
			var pips: int = int(entry.get("pips", 0))
			if pips < 4:
				entry["pips"] = pips + 1
				entry["stage"] = 1
				entry["shake"] = 2.5
				var pip_pitch: float = 0.85 + float(entry["pips"]) * 0.12
				_play_ui_sound(sfx._wav_listener_pip, 1.0, pip_pitch)
			elif pips == 4:
				entry["pips"] = 5
				entry["stage"] = 2
				entry["shake"] = 14.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 100.0, "col": Color(0.2, 0.95, 0.7, 0.95)},
					{"r": -25.0, "max_r": 100.0, "col": Color(0.35, 1.0, 0.85, 0.85)},
					{"r": -50.0, "max_r": 100.0, "col": Color(0.55, 1.0, 0.95, 0.75)}
				]
				_play_ui_sound(sfx._wav_listener_alarm, 3.5, 1.0)
			else:
				entry["pips"] = 0
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

	_update_bestiary_entry_labels(entry)
	var canvas: Control = entry.get("canvas", null)
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_redraw()


func _add_section_header(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.45, 0.82, 1.0, 0.92))
	lbl.add_theme_font_size_override("font_size", 12)
	_body.add_child(lbl)


func _add_divider() -> void:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color = Color(0.2, 0.45, 0.7, 0.35)
	_body.add_child(d)


func _add_guide_row(dot_color: Color, label_text: String, desc_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = dot_color
	row.add_child(dot)

	var key_lbl := Label.new()
	key_lbl.custom_minimum_size = Vector2(110, 0)
	key_lbl.text = label_text
	key_lbl.add_theme_color_override("font_color", dot_color.lerp(Color.WHITE, 0.35))
	key_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_lbl.text = desc_text
	val_lbl.add_theme_color_override("font_color", Color(0.78, 0.88, 0.96, 0.9))
	val_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(val_lbl)

	_body.add_child(row)


func _init_sfx_manager() -> void:
	_sfx_mgr = SfxManager.new()
	_sfx_mgr.name = "IntelSfxManager"
	add_child(_sfx_mgr)


func _get_or_create_sfx_mgr() -> SfxManager:
	if _sfx_mgr == null or not is_instance_valid(_sfx_mgr):
		_init_sfx_manager()
	return _sfx_mgr


func _build_ui_audio() -> void:
	var rate := 22050
	var dur := 0.04
	var total_frames := int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(total_frames * 2)

	for i in total_frames:
		var t := float(i) / float(rate)
		var freq := lerpf(1200.0, 400.0, float(i) / float(total_frames))
		var env := exp(-t * 80.0)
		var val := int(clampf(sin(TAU * freq * t) * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	_wav_click = AudioStreamWAV.new()
	_wav_click.format = AudioStreamWAV.FORMAT_16_BITS
	_wav_click.mix_rate = rate
	_wav_click.data = data


func _play_ui_sound(stream: AudioStreamWAV, vol_db: float, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = &"SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
