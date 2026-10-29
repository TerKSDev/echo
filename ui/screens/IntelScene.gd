extends Control
## Full-Screen Expedition Intel & Acoustic Bestiary Screen for ECHO.
## Displays Threat Archives (Sleeper, Patroller, Chaser, Screamer, Listener),
## interactive acoustic provocation preview, Vanguard VII Lore Archives,
## and Dual-Spectrum Universal Accessibility guides.

@onready var back_button: Button = $TopBar/BackButton
@onready var title_lbl: Label = $TopBar/TitleBox/Title
@onready var subtitle_lbl: Label = $TopBar/TitleBox/Subtitle
@onready var archive_pill: PanelContainer = $TopBar/ArchivePill
@onready var archive_pill_lbl: Label = $TopBar/ArchivePill/PillMargin/ArchivePillLabel

@onready var tab_bestiary_btn: Button = $TabBar/TabBestiary
@onready var tab_archives_btn: Button = $TabBar/TabArchives
@onready var tab_ethos_btn: Button = $TabBar/TabEthos

@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

var _tab_buttons: Array[Button] = []
var _current_tab: int = 0
var _bestiary_entries: Array[Dictionary] = []

var _sfx_mgr: SfxManager = null
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_back: AudioStreamWAV

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	_setup_top_bar()
	_setup_tab_bar()

	if archive_pill != null:
		var pill_style := StyleBoxFlat.new()
		pill_style.bg_color = Color(0.04, 0.12, 0.22, 0.85)
		pill_style.border_color = Color(0.35, 0.85, 1.0, 0.6)
		pill_style.set_border_width_all(1)
		pill_style.set_corner_radius_all(12)
		archive_pill.add_theme_stylebox_override("panel", pill_style)

	_update_archive_pill()
	_switch_tab(GameState.intel_default_tab)
	_apply_safe_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_safe_area()


func _apply_safe_area() -> void:
	if not OS.has_feature("mobile") and OS.get_name() != "Android":
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen_sz := DisplayServer.screen_get_size()
	var vp_sz := get_viewport_rect().size
	if screen_sz.y > 0 and safe.position.y > 0:
		var top_pad := (float(safe.position.y) / float(screen_sz.y)) * vp_sz.y
		var target_top := maxf(top_pad + 6.0, 29.0)
		if has_node("TopBar"):
			$TopBar.position.y = target_top
		if has_node("TabBar"):
			$TabBar.position.y = target_top + 70.0
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 126.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta

	# Process bestiary active entities and shockwaves
	if _current_tab == 0:
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

	# Ambient sonar ripples
	_ambient_wave_timer -= delta
	if _ambient_wave_timer <= 0.0:
		_ambient_wave_timer = randf_range(5.0, 8.5)
		var w_w: float = maxf(size.x, 720.0)
		var w_h: float = maxf(size.y, 1280.0)
		var rand_pos := Vector2(
			randf_range(w_w * 0.16, w_w * 0.84),
			randf_range(w_h * 0.18, w_h * 0.82)
		)
		var rand_r: float = randf_range(160.0, 240.0)
		_ripples.append({
			"pos": rand_pos,
			"age": 0.0,
			"max_r": rand_r,
			"alpha": 0.20,
			"dur": 2.2
		})

	for ripple in _ripples:
		ripple["age"] = float(ripple["age"]) + delta

	_ripples = _ripples.filter(
		func(ripple: Dictionary) -> bool:
			return float(ripple["age"]) < float(ripple.get("dur", 2.2))
	)

	# Ambient spore particles
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		pos.y -= float(spore["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(spore["phase"])) * 12.0 * delta
		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))
		spore["pos"] = pos

	if sonar_backdrop != null and is_instance_valid(sonar_backdrop):
		sonar_backdrop.queue_redraw()


func _setup_top_bar() -> void:
	if back_button != null:
		back_button.text = ""
		back_button.custom_minimum_size = Vector2(32, 44)
		back_button.focus_mode = Control.FOCUS_NONE
		var empty_sb := StyleBoxEmpty.new()
		back_button.add_theme_stylebox_override("normal", empty_sb)
		back_button.add_theme_stylebox_override("hover", empty_sb)
		back_button.add_theme_stylebox_override("pressed", empty_sb)
		back_button.add_theme_stylebox_override("focus", empty_sb)
		back_button.add_theme_stylebox_override("disabled", empty_sb)
		back_button.draw.connect(func(): Icons.draw_back_arrow(back_button))
		back_button.mouse_entered.connect(func(): back_button.queue_redraw())
		back_button.mouse_exited.connect(func(): back_button.queue_redraw())
		back_button.button_down.connect(func(): back_button.queue_redraw())
		back_button.button_up.connect(func(): back_button.queue_redraw())
		back_button.pressed.connect(_on_back_pressed)
		wire_juice(back_button)


func _setup_tab_bar() -> void:
	_tab_buttons = [tab_bestiary_btn, tab_archives_btn, tab_ethos_btn]
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if btn != null:
			btn.pressed.connect(_switch_tab.bind(i))
			wire_juice(btn)


func _update_archive_pill() -> void:
	var col_notes := GameState.get_collected_note_count()
	var tot_notes := GameState.get_total_note_count()
	if archive_pill_lbl != null:
		archive_pill_lbl.text = "◈ ARCHIVES: %d / %d" % [col_notes, tot_notes]
		if col_notes == tot_notes and tot_notes > 0:
			archive_pill_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75, 1.0))
		else:
			archive_pill_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.95))


func _switch_tab(tab_idx: int) -> void:
	_play_ui_sound(_wav_click, -7.0, 1.05)
	_current_tab = clampi(tab_idx, 0, _tab_buttons.size() - 1)

	var col_notes := GameState.get_collected_note_count()
	var tot_notes := GameState.get_total_note_count()
	var tab_names := [
		"THREAT BESTIARY",
		"SURVIVOR ARCHIVES (%d/%d)" % [col_notes, tot_notes],
		"ACCESSIBILITY & ETHOS"
	]

	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if btn == null:
			continue
		btn.text = tab_names[i]
		var is_active := (i == _current_tab)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		if is_active:
			if i == 1:
				style.bg_color = Color(0.24, 0.16, 0.05, 0.95)
				style.border_color = Color(1.0, 0.82, 0.35, 0.95)
				style.shadow_color = Color(0.65, 0.45, 0.10, 0.35)
				btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
			else:
				style.bg_color = Color(0.06, 0.22, 0.38, 0.95)
				style.border_color = Color(0.35, 0.88, 1.0, 1.0)
				style.shadow_color = Color(0.15, 0.55, 0.95, 0.35)
				btn.add_theme_color_override("font_color", Color(0.40, 1.0, 1.0, 1.0))
			style.set_border_width_all(2)
			style.shadow_size = 4
		else:
			style.bg_color = Color(0.025, 0.07, 0.13, 0.80)
			style.border_color = Color(0.18, 0.38, 0.60, 0.50)
			style.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color(0.55, 0.72, 0.85, 0.75))
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_font_size_override("font_size", 12)

	_populate_content()
	if scroll_container != null:
		scroll_container.scroll_vertical = 0


func _populate_content() -> void:
	for child in content_box.get_children():
		child.queue_free()
	_bestiary_entries.clear()

	match _current_tab:
		0:
			if subtitle_lbl != null:
				subtitle_lbl.text = "ACOUSTIC BESTIARY • TAP ENTITY TO PROVOKE EFFECTS"
			_populate_bestiary()
		1:
			var col := GameState.get_collected_note_count()
			var tot := GameState.get_total_note_count()
			if subtitle_lbl != null:
				subtitle_lbl.text = "VANGUARD VII EXPEDITION LOGS • %d / %d ARCHIVES RECOVERED" % [col, tot]
			_populate_lore_notes()
		2:
			if subtitle_lbl != null:
				subtitle_lbl.text = "NON-VIOLENT ETHOS • UNIVERSAL ACCESSIBILITY GUIDELINES"
			_populate_ethos()


# --- TAB 0: BESTIARY ---------------------------------------------------------

func _populate_bestiary() -> void:
	_add_section_header("THREAT ARCHIVE & ACOUSTIC SPECIMENS")

	_add_bestiary_card(
		"sleeper",
		Color(0.72, 0.45, 1.0),
		"SLEEPER",
		"DORMANT LURKER",
		"Remains in deep torpor within the subterranean shadows. Awakens only if you sprint or step directly into its immediate proximity halo.",
		"Hold SNEAK to quietly slip past its sleep radius without detection."
	)
	_add_bestiary_card(
		"patroller",
		Color(1.0, 0.82, 0.25),
		"PATROLLER",
		"ACOUSTIC SENTRY",
		"Relentlessly paces fixed cavern paths. Acute stereoscopic hearing allows it to detect even sneaking footsteps when within close range.",
		"Observe its patrol route; wait patiently behind solid stone corners until it turns away."
	)
	_add_bestiary_card(
		"chaser",
		Color(1.0, 0.28, 0.28),
		"CHASER",
		"APEX PREDATOR",
		"Deaf to subtle sneaking footfalls, but possesses lethal charge velocity. The moment an acoustic wave touches it, it charges straight toward the sound origin.",
		"Never shout or emit sonar when a Chaser lurks near. Throw pebbles elsewhere to deflect it."
	)
	_add_bestiary_card(
		"screamer",
		Color(0.95, 0.32, 0.72),
		"SCREAMER",
		"SONIC COCOON",
		"Stationary vocal entity. When disturbed by consecutive sound waves, it unleashes a deafening screech that reverberates across the entire cavern.",
		"Hide behind solid obstacles to block its concussive screech and prevent waking nearby beasts."
	)
	_add_bestiary_card(
		"listener",
		Color(0.22, 0.95, 0.68),
		"LISTENER",
		"THE HIVE EAR",
		"Completely deaf to normal footsteps. Accumulates sound waves; on reaching its 5th acoustic trigger, it transmits a global alarm to all beasts in the sector.",
		"Minimize voice and sonar usage; extract swiftly before the fifth pip fills."
	)


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
	card_style.content_margin_left = 18.0
	card_style.content_margin_top = 14.0
	card_style.content_margin_right = 18.0
	card_style.content_margin_bottom = 14.0
	card_style.bg_color = Color(0.02, 0.05, 0.09, 0.90)
	card_style.border_color = badge_color.lerp(Color.WHITE, 0.25)
	card_style.border_color.a = 0.55
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(hbox)

	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(104, 104)
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
	vb.add_theme_constant_override("separation", 5)
	hbox.add_child(vb)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	vb.add_child(r1)

	var name_lbl := Label.new()
	name_lbl.text = monster_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", badge_color.lerp(Color.WHITE, 0.45))
	r1.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = "[ %s ]" % role_text
	role_lbl.add_theme_font_size_override("font_size", 11)
	role_lbl.add_theme_color_override("font_color", Color(badge_color.r, badge_color.g, badge_color.b, 0.75))
	role_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(role_lbl)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 11)
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

	content_box.add_child(card)


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


# --- TAB 1: SURVIVOR ARCHIVES ------------------------------------------------

func _populate_lore_notes() -> void:
	var col_count: int = GameState.get_collected_note_count()
	var tot_count: int = GameState.get_total_note_count()
	var pct: float = (float(col_count) / float(tot_count) * 100.0) if tot_count > 0 else 0.0

	var banner := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.content_margin_left = 18.0
	b_style.content_margin_top = 12.0
	b_style.content_margin_right = 18.0
	b_style.content_margin_bottom = 12.0
	b_style.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	b_style.border_color = Color(0.9, 0.75, 0.35, 0.75)
	b_style.set_border_width_all(1)
	b_style.set_corner_radius_all(10)
	banner.add_theme_stylebox_override("panel", b_style)
	content_box.add_child(banner)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 4)
	banner.add_child(b_vbox)

	var b_top := HBoxContainer.new()
	b_vbox.add_child(b_top)

	var b_title := Label.new()
	b_title.text = "FIELD LOGS OF VANGUARD VII EXPEDITION"
	b_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_title.add_theme_font_size_override("font_size", 14)
	b_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55, 1.0))
	b_top.add_child(b_title)

	var b_badge := Label.new()
	b_badge.text = "COLLECTED: %d / %d (%.0f%%)" % [col_count, tot_count, pct]
	b_badge.add_theme_font_size_override("font_size", 12)
	b_badge.add_theme_color_override("font_color", Color(0.4, 0.95, 0.75, 1.0) if col_count == tot_count else Color(1.0, 0.82, 0.35, 0.9))
	b_top.add_child(b_badge)

	var b_desc := Label.new()
	b_desc.text = "Subterranean archives left by Dr. Thorne, Maya Lin, Scout Jarek, and Elena. Hidden across the 20 Story Mode Sectors. Touch them during cavern ascents to recover."
	b_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b_desc.add_theme_font_size_override("font_size", 11)
	b_desc.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92, 0.8))
	b_vbox.add_child(b_desc)

	var all_notes := GameState.get_all_notes()
	for note_data in all_notes:
		_add_lore_note_card(note_data)


func _add_lore_note_card(note_data: Dictionary) -> void:
	var is_collected: bool = (note_data.get("collected", false) == true)
	var lvl_num: int = int(note_data.get("level", 1))
	var depth_str: String = str(note_data.get("depth", ""))
	var author_str: String = str(note_data.get("author", "Unknown Survivor"))
	var title_str: String = str(note_data.get("title", "LOST ARCHIVE"))
	var text_str: String = str(note_data.get("text", ""))

	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 16.0
	card_style.content_margin_top = 10.0
	card_style.content_margin_right = 16.0
	card_style.content_margin_bottom = 10.0
	card_style.set_corner_radius_all(8)
	card_style.set_border_width_all(1)

	if is_collected:
		card_style.bg_color = Color(0.02, 0.045, 0.08, 0.94)
		card_style.border_color = Color(0.85, 0.68, 0.28, 0.6)
	else:
		card_style.bg_color = Color(0.012, 0.02, 0.035, 0.75)
		card_style.border_color = Color(0.18, 0.28, 0.38, 0.35)
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	card.add_child(hbox)

	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(32, 32)
	hbox.add_child(icon_box)

	var icon_lbl := Label.new()
	icon_lbl.text = "◈" if is_collected else "◇"
	icon_lbl.add_theme_font_size_override("font_size", 18)
	icon_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if is_collected else Color(0.4, 0.5, 0.6, 0.5))
	icon_box.add_child(icon_lbl)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	vbox.add_child(meta_row)

	var sec_lbl := Label.new()
	sec_lbl.text = "SECTOR %02d  •  %s" % [lvl_num, depth_str]
	sec_lbl.add_theme_font_size_override("font_size", 11)
	sec_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.35, 0.9) if is_collected else Color(0.45, 0.55, 0.65, 0.6))
	meta_row.add_child(sec_lbl)

	if is_collected and author_str != "":
		var sep := Label.new()
		sep.text = "•"
		sep.add_theme_font_size_override("font_size", 11)
		sep.add_theme_color_override("font_color", Color(0.4, 0.55, 0.7, 0.6))
		meta_row.add_child(sep)

		var auth_lbl := Label.new()
		auth_lbl.text = author_str
		auth_lbl.add_theme_font_size_override("font_size", 11)
		auth_lbl.add_theme_color_override("font_color", Color(0.65, 0.82, 0.95, 0.8))
		meta_row.add_child(auth_lbl)

	var title_node := Label.new()
	if is_collected:
		title_node.text = title_str
		title_node.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90, 1.0))
	else:
		title_node.text = "??? [UNDISCOVERED LOG]"
		title_node.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 0.65))
	title_node.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_node)

	var excerpt_lbl := Label.new()
	excerpt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	excerpt_lbl.add_theme_font_size_override("font_size", 11)
	if is_collected:
		var snippet := text_str.substr(0, 120)
		if text_str.length() > 120:
			snippet += "..."
		excerpt_lbl.text = snippet
		excerpt_lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.88, 0.85))
	else:
		excerpt_lbl.text = "Locate and touch this expedition log in Story Mode Sector %02d to decrypt." % lvl_num
		excerpt_lbl.add_theme_color_override("font_color", Color(0.38, 0.46, 0.55, 0.6))
	vbox.add_child(excerpt_lbl)

	var right_box := CenterContainer.new()
	right_box.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(right_box)

	if is_collected:
		var read_btn := Button.new()
		read_btn.text = "READ"
		read_btn.custom_minimum_size = Vector2(80, 30)
		read_btn.focus_mode = Control.FOCUS_NONE
		read_btn.add_theme_font_size_override("font_size", 11)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.20, 0.16, 0.05, 0.85)
		btn_style.border_color = Color(0.95, 0.80, 0.35, 0.85)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(6)
		read_btn.add_theme_stylebox_override("normal", btn_style)
		read_btn.add_theme_color_override("font_color", Color(1.0, 0.90, 0.65))
		read_btn.pressed.connect(func():
			_play_ui_sound(_wav_click, -4.0, 1.2)
			var script: GDScript = load("res://ui/modals/NoteReadModal.gd") as GDScript
			if script != null:
				script.open_note(self, note_data)
		)
		wire_juice(read_btn)
		right_box.add_child(read_btn)
	else:
		var lock_lbl := Label.new()
		lock_lbl.text = "LOCKED"
		lock_lbl.add_theme_font_size_override("font_size", 11)
		lock_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.5))
		right_box.add_child(lock_lbl)

	content_box.add_child(card)


# --- TAB 2: ETHOS & ACCESSIBILITY --------------------------------------------

func _populate_ethos() -> void:
	_add_section_header("CORE ETHOS • POSITIVE VALUES & MINDFUL SURVIVAL")
	_add_guide_row(Color(0.35, 0.95, 0.75), "NON-VIOLENCE", "ECHO contains zero weapons, zero guns, and zero violence. Survival is achieved through mindfulness, calmness, and acoustic deflection rather than destruction.")
	_add_guide_row(Color(0.45, 0.82, 1.0), "INNER RESILIENCE", "The subterranean ascent represents overcoming mental darkness, anxiety, and panic. Silence is your shield; resonance is your compass.")

	_add_divider()
	_add_section_header("UNIVERSAL ACCESSIBILITY • DUAL-SPECTRUM DESIGN")
	_add_guide_row(Color(0.35, 0.95, 0.75), "BLIND PLAYABLE", "Full 3D binaural audio & haptic blind navigation: periodic exit beacons, acoustic wall reflection echoes, obstacle cane feelers, and directional keyboard controls enable players to navigate and complete sectors purely by ear.")
	_add_guide_row(Color(1.0, 0.78, 0.28), "DEAF INCLUSIVE", "100% of spatial sounds are translated into visual acoustic waveforms and off-screen indicators. Hearing-impaired players can achieve S-Rank mastery in pure silence.")
	_add_guide_row(Color(0.85, 0.70, 1.0), "TACTILE & SPEECH", "Full touch alternatives for voice input allow seamless play in public spaces or for players with vocal/speech considerations.")


func _add_section_header(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.45, 0.82, 1.0, 0.92))
	lbl.add_theme_font_size_override("font_size", 13)
	content_box.add_child(lbl)


func _add_divider() -> void:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color = Color(0.2, 0.45, 0.7, 0.35)
	content_box.add_child(d)


func _add_guide_row(dot_color: Color, label_text: String, desc_text: String) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	style.bg_color = Color(0.02, 0.05, 0.09, 0.80)
	style.border_color = dot_color * Color(1, 1, 1, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = dot_color
	row.add_child(dot)

	var key_lbl := Label.new()
	key_lbl.custom_minimum_size = Vector2(140, 0)
	key_lbl.text = label_text
	key_lbl.add_theme_color_override("font_color", dot_color.lerp(Color.WHITE, 0.35))
	key_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_lbl.text = desc_text
	val_lbl.add_theme_color_override("font_color", Color(0.78, 0.88, 0.96, 0.9))
	val_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(val_lbl)

	content_box.add_child(card)


# --- HELPERS & AMBIENT DRAW --------------------------------------------------

func _init_sfx_manager() -> void:
	_sfx_mgr = SfxManager.new()
	_sfx_mgr.name = "IntelSfxManager"
	add_child(_sfx_mgr)


func _get_or_create_sfx_mgr() -> SfxManager:
	if _sfx_mgr != null and is_instance_valid(_sfx_mgr):
		return _sfx_mgr
	var existing = get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if existing != null:
		return existing
	_init_sfx_manager()
	return _sfx_mgr


func _init_spores() -> void:
	_spores.clear()
	var w := maxf(size.x, 720.0)
	var h := maxf(size.y, 1280.0)
	for i in range(36):
		_spores.append({
			"pos": Vector2(randf_range(0.0, w), randf_range(0.0, h)),
			"speed": randf_range(12.0, 32.0),
			"phase": randf_range(0.0, TAU),
			"r": randf_range(1.2, 2.8),
			"alpha": randf_range(0.12, 0.40)
		})


func _draw_sonar_backdrop() -> void:
	var w := size.x
	var h := size.y
	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		if pos.x < -10.0 or pos.x > w + 10.0 or pos.y < -10.0 or pos.y > h + 10.0:
			continue
		var col := Color(0.4, 0.85, 1.0, float(spore["alpha"]))
		sonar_backdrop.draw_circle(pos, float(spore["r"]), col)

	for ripple in _ripples:
		var age: float = float(ripple["age"])
		var dur: float = float(ripple.get("dur", 2.2))
		var max_r: float = float(ripple.get("max_r", 200.0))
		var peak_a: float = float(ripple.get("alpha", 0.25))
		var progress: float = clampf(age / dur, 0.0, 1.0)
		var radius: float = progress * max_r
		var fade := 1.0 - progress
		fade = fade * fade
		var alpha := peak_a * fade
		sonar_backdrop.draw_arc(ripple["pos"], radius, 0.0, TAU, 48, Color(0.35, 0.85, 1.0, alpha), 1.4)


func _on_back_pressed() -> void:
	_play_ui_sound(_wav_back, -4.0, 0.95)
	GameState.go_to_previous_scene()


func wire_juice(btn: Button) -> void:
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.02, 1.02), 0.1)
		_play_ui_sound(_wav_hover, -10.0, 1.05)
	)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12)
	)
	btn.button_down.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.05)
	)
	btn.button_up.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
	)


func _build_ui_audio() -> void:
	_wav_click = _synth_tone(720.0, 1080.0, 0.045)
	_wav_hover = _synth_tone(1100.0, 1320.0, 0.030)
	_wav_back = _synth_tone(540.0, 360.0, 0.065)


func _synth_tone(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var n_samples := int(sample_rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(n_samples * 2)

	var phase := 0.0
	for i in range(n_samples):
		var t := float(i) / float(n_samples)
		var freq := lerpf(f_start, f_end, t)
		var env := sin(t * PI)
		var sample := sin(phase) * env * 0.35
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s16)
		phase += TAU * freq / float(sample_rate)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _play_ui_sound(stream: AudioStreamWAV, vol_db: float, pitch: float, bus_name: StringName = &"SFX") -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = bus_name
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
