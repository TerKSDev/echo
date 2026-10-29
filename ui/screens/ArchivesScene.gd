extends Control
## Full-Screen Expedition Archives Screen for ECHO.
## Features a dedicated 4-Category Codex Hub (Player, Monsters, Story, Ethos)
## with custom vector drawn icons, detailed survival mechanics guide,
## interactive acoustic monster bestiary, Vanguard VII field logs, and accessibility doctrine.

@onready var back_button: Button = $TopBar/BackButton
@onready var title_lbl: Label = $TopBar/TitleBox/Title
@onready var subtitle_lbl: Label = $TopBar/TitleBox/Subtitle

@onready var sonar_backdrop: Control = $SonarBackdrop
@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var content_box: VBoxContainer = $MainArea/ScrollContainer/ContentMargin/ContentBox

var _current_section: String = "hub"
var _bestiary_entries: Array[Dictionary] = []

var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_back: AudioStreamWAV
var _monster_wavs: Dictionary = {}

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()
	WorkerThreadPool.add_task(func():
		for key in ["screamer_crack", "screamer_shriek", "echo_ping", "charge_full", "roar_sleeper", "roar_patroller", "roar_chaser", "listener_pip", "listener_alarm"]:
			_get_monster_sfx(key)
	)

	if sonar_backdrop != null:
		sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var vbar := scroll_container.get_v_scroll_bar()
		if vbar != null:
			vbar.modulate.a = 0.0
			vbar.custom_minimum_size = Vector2.ZERO
		var hbar := scroll_container.get_h_scroll_bar()
		if hbar != null:
			hbar.modulate.a = 0.0
			hbar.custom_minimum_size = Vector2.ZERO

	_setup_top_bar()

	var start_section := GameState.archives_target_section
	if start_section == "" or start_section == "hub":
		open_section("hub", false)
	else:
		open_section(start_section, false)

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
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 66.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta

	# Process bestiary active entities and shockwaves when in monsters section
	if _current_section == "monsters":
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


func open_section(section_name: String, play_sound: bool = true) -> void:
	if play_sound:
		_play_ui_sound(_wav_click, -6.0, 1.05)

	_current_section = section_name

	for child in content_box.get_children():
		child.queue_free()
	_bestiary_entries.clear()

	match _current_section:
		"hub":
			title_lbl.text = "EXPEDITION ARCHIVES"
			subtitle_lbl.text = "SURVIVAL CODEX, BESTIARY & FIELD RECORDS"
			_populate_hub()
		"player":
			title_lbl.text = "PLAYER ARCHIVE"
			subtitle_lbl.text = "EXPLORER SUIT, STEALTH & ACOUSTIC TECHNIQUES"
			_populate_player()
		"monsters":
			title_lbl.text = "THREAT BESTIARY"
			subtitle_lbl.text = "5 SPECIMENS • TAP ENTITY TO PROVOKE EFFECTS"
			_populate_monsters()
		"story":
			var col := GameState.get_collected_note_count()
			var tot := GameState.get_total_note_count()
			title_lbl.text = "VANGUARD VII LOGS"
			subtitle_lbl.text = "FIELD ARCHIVES • %d / %d RECOVERED" % [col, tot]
			_populate_story()
		"ethos":
			title_lbl.text = "ETHOS & ACCESS"
			subtitle_lbl.text = "NON-VIOLENCE PHILOSOPHY • DUAL-SPECTRUM DESIGN"
			_populate_ethos()

	if scroll_container != null:
		scroll_container.scroll_vertical = 0


# --- 1. HUB VIEW (4 LARGE ENTRY CARDS WITH DRAWN ICONS) -----------------------

func _populate_hub() -> void:
	var col_notes := GameState.get_collected_note_count()
	var tot_notes := GameState.get_total_note_count()
	var pct: float = (float(col_notes) / float(tot_notes) * 100.0) if tot_notes > 0 else 0.0

	# 1. Player Card
	_add_hub_card(
		"player",
		"PLAYER",
		"EXPLORER SUIT & ACOUSTIC TECHNIQUES",
		"Echolocation pulses, stealth footsteps, pebble throws, and binaural cane feelers.",
		"5 CORE TECHNIQUES",
		Color(0.35, 0.88, 1.0),
		Callable(Icons, "draw_archives_player")
	)

	# 2. Monsters Card
	_add_hub_card(
		"monsters",
		"MONSTERS",
		"SUBTERRANEAN THREAT BESTIARY",
		"Sleeper, Patroller, Chaser, Screamer, Listener. Acoustic triggers and weaknesses.",
		"5 IDENTIFIED SPECIMENS",
		Color(1.0, 0.40, 0.35),
		Callable(Icons, "draw_archives_monsters")
	)

	# 3. Story Card
	_add_hub_card(
		"story",
		"STORY",
		"VANGUARD VII EXPEDITION LOGS",
		"Field journals and deep cavern recordings left by Dr. Thorne, Maya Lin, and Jarek.",
		"COLLECTED: %d / %d (%.0f%%)" % [col_notes, tot_notes, pct],
		Color(1.0, 0.82, 0.38),
		Callable(Icons, "draw_archives_story")
	)

	# 4. Ethos & Accessibility Card
	_add_hub_card(
		"ethos",
		"ETHOS & ACCESS",
		"NON-VIOLENT DOCTRINE & ACCESSIBILITY",
		"Core non-violence ethos, mindfulness survival, and full dual-spectrum blind/deaf guidance.",
		"BLIND PLAYABLE & DEAF INCLUSIVE",
		Color(0.35, 0.95, 0.72),
		Callable(Icons, "draw_archives_ethos")
	)


func _add_hub_card(
	section_id: String,
	title_text: String,
	subtitle_text: String,
	desc_text: String,
	badge_text: String,
	accent_color: Color,
	draw_icon_callable: Callable
) -> void:
	var card_btn := Button.new()
	card_btn.custom_minimum_size = Vector2(0, 114)
	card_btn.focus_mode = Control.FOCUS_NONE
	card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.02, 0.05, 0.09, 0.88)
	base_style.border_color = accent_color * Color(1, 1, 1, 0.55)
	base_style.set_border_width_all(1)
	base_style.set_corner_radius_all(12)
	base_style.content_margin_left = 18.0
	base_style.content_margin_right = 18.0
	base_style.content_margin_top = 14.0
	base_style.content_margin_bottom = 14.0

	var hover_style := base_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.04, 0.10, 0.18, 0.95)
	hover_style.border_color = accent_color
	hover_style.set_border_width_all(2)
	hover_style.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.35)
	hover_style.shadow_size = 6

	card_btn.add_theme_stylebox_override("normal", base_style)
	card_btn.add_theme_stylebox_override("hover", hover_style)
	card_btn.add_theme_stylebox_override("pressed", hover_style)
	card_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var card_margin := MarginContainer.new()
	card_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_margin.add_theme_constant_override("margin_left", 20)
	card_margin.add_theme_constant_override("margin_right", 20)
	card_margin.add_theme_constant_override("margin_top", 14)
	card_margin.add_theme_constant_override("margin_bottom", 14)
	card_btn.add_child(card_margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 18)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	card_margin.add_child(hbox)

	# Left Icon Canvas Container
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.clip_contents = true
	var ibox_style := StyleBoxFlat.new()
	ibox_style.bg_color = Color(0.012, 0.03, 0.055, 0.95)
	ibox_style.border_color = accent_color * Color(1, 1, 1, 0.6)
	ibox_style.set_border_width_all(1)
	ibox_style.set_corner_radius_all(10)
	icon_box.add_theme_stylebox_override("panel", ibox_style)
	hbox.add_child(icon_box)

	var icon_canvas := Control.new()
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if draw_icon_callable.is_valid():
		icon_canvas.draw.connect(func(): draw_icon_callable.call(icon_canvas))
		card_btn.mouse_entered.connect(func(): icon_canvas.queue_redraw())
		card_btn.mouse_exited.connect(func(): icon_canvas.queue_redraw())
	icon_box.add_child(icon_canvas)

	# Center Titles & Information
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	vbox.add_child(top_row)

	var title_lbl_node := Label.new()
	title_lbl_node.text = title_text
	title_lbl_node.add_theme_font_size_override("font_size", 16)
	title_lbl_node.add_theme_color_override("font_color", accent_color.lerp(Color.WHITE, 0.35))
	top_row.add_child(title_lbl_node)

	var badge_lbl := Label.new()
	badge_lbl.text = "[ %s ]" % badge_text
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_color_override("font_color", accent_color * Color(1, 1, 1, 0.85))
	badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(badge_lbl)

	var subtitle_lbl_node := Label.new()
	subtitle_lbl_node.text = subtitle_text
	subtitle_lbl_node.add_theme_font_size_override("font_size", 11)
	subtitle_lbl_node.add_theme_color_override("font_color", Color(0.75, 0.86, 0.96, 0.85))
	vbox.add_child(subtitle_lbl_node)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.68, 0.80, 0.80))
	vbox.add_child(desc_lbl)

	# Right Chevron Indicator
	var chevron_box := CenterContainer.new()
	chevron_box.custom_minimum_size = Vector2(28, 0)
	chevron_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chevron_lbl := Label.new()
	chevron_lbl.text = "▶"
	chevron_lbl.add_theme_font_size_override("font_size", 14)
	chevron_lbl.add_theme_color_override("font_color", accent_color * Color(1, 1, 1, 0.75))
	chevron_box.add_child(chevron_lbl)
	hbox.add_child(chevron_box)

	card_btn.pressed.connect(open_section.bind(section_id, true))
	wire_juice(card_btn)
	content_box.add_child(card_btn)


# --- 2. PLAYER SECTION (SURVIVAL TECHNIQUES & MECHANICS) ---------------------

func _populate_player() -> void:
	_add_section_header("EXPEDITION SUIT & ACOUSTIC SURVIVAL DOCTRINE")

	_add_technique_card(
		"ECHOLOCATION & PULSE WAVES",
		"Emit acoustic sonar pulses (Spacebar, Touch Pulse Button, or Microphone) to illuminate the dark abyss. Sound waves bounce off stone barriers, painting cavern walls in bioluminescent cyan phosphors.",
		"Pulse waves pierce utter darkness, but awaken and attract sound-sensitive beasts. Use with tactical caution.",
		Color(0.35, 0.88, 1.0)
	)

	_add_technique_card(
		"STEALTH & FOOTSTEP NOISE",
		"Hold SNEAK (or toggle) to damp all footfall decibels. Sneaking allows you to safely brush past sleeping monsters and slip through sentry patrol sightlines undetected.",
		"Never sprint or stomp near Sleeper halos or Patroller ears. Flooded water puddles amplify footstep noise!",
		Color(0.40, 1.0, 0.75)
	)

	_add_technique_card(
		"PEBBLE DIVERSION & RICOCHET",
		"Aim and fling stone pebbles across the cavern. When a pebble collides with a distant wall, it generates a sharp acoustic impact point that lures predators away from your extraction route.",
		"Pebbles are your primary non-violent distraction tool. Conserve stones for tight bottlenecks.",
		Color(1.0, 0.85, 0.35)
	)

	_add_technique_card(
		"BINAURAL AUDIO & CANE PROBING",
		"For visually-impaired or pure acoustic play: the explorer cane feels the path ahead and clicks softly against rock faces. True 3D stereo audio balance indicates the precise direction of exits and threats.",
		"Wear stereo headphones for full spatial awareness. Center the exit chime between your ears to escape.",
		Color(0.85, 0.70, 1.0)
	)

	_add_technique_card(
		"MICROPHONE VOICE SENSOR",
		"Use your actual voice, whispers, or handclaps to generate in-game sonar pulses. The room calibration system automatically samples your ambient room noise floor to prevent false triggers.",
		"Press [M] to instantly mute the mic sensor when playing in public or noisy environments.",
		Color(0.45, 0.75, 1.0)
	)


func _add_technique_card(tech_name: String, description: String, tip: String, col: Color) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.content_margin_left = 18.0
	style.content_margin_top = 12.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 12.0
	style.bg_color = Color(0.02, 0.05, 0.09, 0.88)
	style.border_color = col * Color(1, 1, 1, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var title_node := Label.new()
	title_node.text = tech_name
	title_node.add_theme_font_size_override("font_size", 14)
	title_node.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
	vbox.add_child(title_node)

	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98, 0.92))
	vbox.add_child(desc_lbl)

	var tip_lbl := Label.new()
	tip_lbl.text = "TACTICAL NOTE: " + tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", col * Color(1, 1, 1, 0.85))
	vbox.add_child(tip_lbl)

	content_box.add_child(card)


# --- 3. MONSTERS SECTION (ACOUSTIC BESTIARY) ---------------------------------

func _populate_monsters() -> void:
	_add_section_header("THREAT ARCHIVE & ACOUSTIC SPECIMENS")

	_add_bestiary_card(
		"sleeper",
		Color(0.72, 0.45, 1.0),
		"SLEEPER",
		"DORMANT LURKER",
		"Remains in deep torpor within subterranean shadows. Awakens only if you sprint or step directly into its immediate proximity halo.",
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
		"Completely deaf to normal footsteps. Accumulates acoustic triggers; on reaching its 3rd sound wave, it unleashes a map-wide alarm buffing all beasts.",
		"Minimize voice and sonar usage; navigate carefully before the third pip fills."
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
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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
				status_lbl.text = "[ PASSIVE (0/3 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", col)
				hint_lbl.text = "▶ TAP ENTITY: 1st Acoustic Sound"
			elif pips == 1:
				status_lbl.text = "[ ACOUSTIC PIPS 1/3 ]"
				status_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75))
				hint_lbl.text = "▶ TAP AGAIN: 2nd Acoustic Sound"
			elif pips == 2:
				status_lbl.text = "[ CRITICAL (2/3 PIPS) ]"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
				hint_lbl.text = "▶ TAP AGAIN: 3rd Sound (GLOBAL HIVE ALARM!)"
			else:
				status_lbl.text = "[ GLOBAL ALARM TRANSMITTED ]"
				status_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.65))
				hint_lbl.text = "▶ HIVE ALARM REVERBERATING (TAP TO RESET)"


func _on_monster_canvas_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if not ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)):
		return

	# Frame-level debounce to catch simultaneously emitted mouse & emulated touch events
	var cur_frame: int = Engine.get_process_frames()
	if cur_frame == int(entry.get("last_click_frame", -1)):
		accept_event()
		return
	entry["last_click_frame"] = cur_frame

	# Time debounce (400ms) to ensure double taps don't misfire
	var now: int = Time.get_ticks_msec()
	if now - int(entry.get("last_click_ms", 0)) < 400:
		accept_event()
		return
	entry["last_click_ms"] = now
	accept_event()
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

	match m_type:
		"screamer":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(_get_monster_sfx("screamer_crack"), 1.5, randf_range(0.96, 1.04))
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.45, 0.95)},
					{"r": -22.0, "max_r": 95.0, "col": Color(1.0, 0.35, 0.65, 0.85)},
					{"r": -44.0, "max_r": 95.0, "col": Color(1.0, 0.5, 0.8, 0.75)}
				]
				_play_ui_sound(_get_monster_sfx("screamer_shriek"), 3.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"sleeper":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.5
				entry["timer"] = 0.0
				_play_ui_sound(_get_monster_sfx("echo_ping"), -10.0, 0.75)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 10.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(0.72, 0.45, 1.0, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(0.85, 0.65, 1.0, 0.8)}
				]
				_play_ui_sound(_get_monster_sfx("roar_sleeper"), 2.5, 0.95)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"patroller":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 2.0
				entry["timer"] = 0.0
				_play_ui_sound(_get_monster_sfx("echo_ping"), -8.0, 1.35)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 9.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 90.0, "col": Color(1.0, 0.82, 0.25, 0.95)},
					{"r": -25.0, "max_r": 90.0, "col": Color(1.0, 0.95, 0.5, 0.8)}
				]
				_play_ui_sound(_get_monster_sfx("roar_patroller"), 2.5, 1.0)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"chaser":
			if cur_stage == 0:
				entry["stage"] = 1
				entry["shake"] = 4.0
				entry["timer"] = 0.0
				_play_ui_sound(_get_monster_sfx("charge_full"), -6.0, 0.85)
			elif cur_stage == 1:
				entry["stage"] = 2
				entry["shake"] = 12.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 95.0, "col": Color(1.0, 0.2, 0.2, 0.95)},
					{"r": -25.0, "max_r": 95.0, "col": Color(1.0, 0.4, 0.4, 0.8)}
				]
				_play_ui_sound(_get_monster_sfx("roar_chaser"), 3.0, 1.05)
			else:
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

		"listener":
			var pips: int = int(entry.get("pips", 0))
			if pips < 2:
				entry["pips"] = pips + 1
				entry["stage"] = 1
				entry["shake"] = 2.5
				var pip_pitch: float = 0.90 + float(entry["pips"]) * 0.18
				_play_ui_sound(_get_monster_sfx("listener_pip"), 1.0, pip_pitch)
			elif pips == 2:
				entry["pips"] = 3
				entry["stage"] = 2
				entry["shake"] = 14.0
				entry["timer"] = 0.0
				entry["shockwaves"] = [
					{"r": 0.0, "max_r": 100.0, "col": Color(0.2, 0.95, 0.7, 0.95)},
					{"r": -25.0, "max_r": 100.0, "col": Color(0.35, 1.0, 0.85, 0.85)},
					{"r": -50.0, "max_r": 100.0, "col": Color(0.55, 1.0, 0.95, 0.75)}
				]
				_play_ui_sound(_get_monster_sfx("listener_alarm"), 3.5, 1.0)
			else:
				entry["pips"] = 0
				entry["stage"] = 0
				entry["shake"] = 0.0
				_play_ui_sound(_wav_click, -6.0, 1.2)

	_update_bestiary_entry_labels(entry)
	var canvas: Control = entry.get("canvas", null)
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_redraw()


# --- 4. STORY SECTION (VANGUARD VII FIELD LOGS) ------------------------------

func _populate_story() -> void:
	var col_count: int = GameState.get_collected_note_count()
	var tot_count: int = GameState.get_total_note_count()
	var pct: float = (float(col_count) / float(tot_count) * 100.0) if tot_count > 0 else 0.0

	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_PASS
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
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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


# --- 5. ETHOS & ACCESSIBILITY SECTION ----------------------------------------

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
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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
	if _current_section != "hub":
		open_section("hub", false)
	else:
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


# --- MONSTER PREVIEW PROCEDURAL AUDIO -----------------------------------------

func _get_monster_sfx(key: String) -> AudioStreamWAV:
	if _monster_wavs.has(key):
		return _monster_wavs[key]
	var wav: AudioStreamWAV = null
	match key:
		"screamer_crack":
			wav = _synth_screamer_crack()
		"screamer_shriek":
			wav = _synth_screamer_shriek()
		"echo_ping":
			wav = _synth_echo_ping()
		"charge_full":
			wav = _synth_charge_full()
		"roar_sleeper":
			wav = _synth_monster_roar(95.0, 0.78, 0.35)
		"roar_patroller":
			wav = _synth_monster_roar(135.0, 0.68, 0.55)
		"roar_chaser":
			wav = _synth_monster_roar(185.0, 0.62, 0.85)
		"listener_pip":
			wav = _synth_listener_pip()
		"listener_alarm":
			wav = _synth_listener_alarm()
	if wav != null:
		_monster_wavs[key] = wav
	return wav


static func _make_wav_from_samples(samples: PackedFloat32Array, sample_rate: int = 22050) -> AudioStreamWAV:
	var byte_data := PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in samples.size():
		var s: float = clampf(samples[i], -1.0, 1.0)
		var pcm: int = int(s * 32767.0)
		byte_data.encode_s16(i * 2, pcm)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_data
	return wav


func _synth_screamer_crack() -> AudioStreamWAV:
	var dur := 0.38
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / 22050.0
		var snap1: float = randf_range(-1.0, 1.0) * exp(-t * 55.0)
		var snap2: float = randf_range(-1.0, 1.0) * exp(-maxf(t - 0.07, 0.0) * 65.0) if t >= 0.07 else 0.0
		var ring: float = (sin(TAU * 1480.0 * t) + 0.6 * sin(TAU * 2120.0 * t)) * exp(-t * 9.5)
		out[i] = clampf((snap1 * 0.8 + snap2 * 0.7 + ring * 0.45) * 0.85, -1.0, 1.0)
	return _make_wav_from_samples(out)


func _synth_screamer_shriek() -> AudioStreamWAV:
	var dur := 1.15
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := 0.0
	var p2 := 0.0
	for i in count:
		var t: float = float(i) / 22050.0
		var norm_t: float = t / dur
		var env: float = clampf(t / 0.03, 0.0, 1.0) * exp(-norm_t * 2.2)
		var fm: float = sin(TAU * 38.0 * t) * 65.0
		var f1: float = lerpf(1180.0, 760.0, norm_t) + fm
		var f2: float = lerpf(1790.0, 1120.0, norm_t) - fm * 0.7
		p1 += TAU * f1 / 22050.0
		p2 += TAU * f2 / 22050.0
		var shriek: float = sin(p1) * 0.55 + sin(p2) * 0.4 + randf_range(-0.35, 0.35) * exp(-t * 2.5)
		var boom: float = sin(TAU * lerpf(160.0, 45.0, clampf(t / 0.25, 0.0, 1.0)) * t) * exp(-t * 8.0) * 0.5
		out[i] = tanh((shriek + boom) * 1.6) * env * 0.82
	return _make_wav_from_samples(out)


func _synth_echo_ping() -> AudioStreamWAV:
	var dur := 0.68
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / 22050.0
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 5.4)
		var f1 := 528.0
		var f2 := 792.0
		var f3 := 1056.0
		var f4 := 1584.0
		var sig: float = sin(TAU * f1 * t) * 0.55 + sin(TAU * f2 * t) * 0.24 * exp(-t * 7.5) + sin(TAU * f3 * t) * 0.16 * exp(-t * 11.0) + sin(TAU * f4 * t) * 0.09 * exp(-t * 15.0)
		var sub: float = sin(TAU * 132.0 * t) * exp(-t * 12.0) * 0.38
		out[i] = clampf((sig * env + sub) * 0.85, -1.0, 1.0)
	return _make_wav_from_samples(out)


func _synth_charge_full() -> AudioStreamWAV:
	var dur := 0.28
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / 22050.0
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 11.0)
		out[i] = (sin(TAU * 880.0 * t) * 0.55 + sin(TAU * 1320.0 * t) * 0.35) * env * 0.7
	return _make_wav_from_samples(out)


func _synth_monster_roar(base_freq: float, dur: float, aggression: float) -> AudioStreamWAV:
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var noise_lp := 0.0
	for i in count:
		var t: float = float(i) / 22050.0
		var norm_t: float = t / dur
		var attack: float = clampf(t / 0.04, 0.0, 1.0)
		var decay: float = clampf((1.0 - norm_t) / 0.28, 0.0, 1.0)
		var env: float = attack * decay

		var pitch_curve: float = 1.0 + 0.28 * sin(norm_t * PI) - 0.22 * norm_t
		var vibrato: float = 1.0 + 0.06 * sin(TAU * 26.0 * t)
		var f: float = base_freq * pitch_curve * vibrato

		p1 += TAU * f / 22050.0
		p2 += TAU * (f * 1.48) / 22050.0
		p3 += TAU * (f * 0.5) / 22050.0

		var cords: float = sin(p1) + 0.55 * sin(p1 * 2.0) + 0.35 * sin(p2) + 0.6 * sin(p3)
		var raw_noise: float = randf_range(-1.0, 1.0)
		noise_lp = lerpf(noise_lp, raw_noise, 0.18 + 0.22 * aggression)
		var rasp: float = noise_lp * (0.65 + 0.5 * sin(p1))

		var mixed: float = tanh((cords * 0.7 + rasp * (0.6 + 0.4 * aggression)) * (1.8 + aggression))
		out[i] = mixed * env * 0.85
	return _make_wav_from_samples(out)


func _synth_listener_pip() -> AudioStreamWAV:
	var dur := 0.24
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t: float = float(i) / 22050.0
		var env: float = minf(t / 0.005, 1.0) * exp(-t * 14.0)
		var sig: float = sin(TAU * 740.0 * t) * 0.7 + sin(TAU * 1480.0 * t) * 0.3
		out[i] = sig * env * 0.75
	return _make_wav_from_samples(out)


func _synth_listener_alarm() -> AudioStreamWAV:
	var dur := 1.6
	var count := int(dur * 22050.0)
	var out := PackedFloat32Array()
	out.resize(count)
	var p_horn := 0.0
	var p_sweep := 0.0
	for i in count:
		var t: float = float(i) / 22050.0
		var norm_t: float = t / dur
		var env: float = clampf(t / 0.05, 0.0, 1.0) * clampf((1.0 - norm_t) / 0.2, 0.0, 1.0)
		var horn_f: float = 110.0 * (1.0 - 0.12 * norm_t)
		var sweep_f: float = 440.0 + 320.0 * sin(TAU * 3.0 * t)
		p_horn += TAU * horn_f / 22050.0
		p_sweep += TAU * sweep_f / 22050.0
		var horn: float = sin(p_horn) + 0.5 * sin(p_horn * 2.0) + 0.3 * sin(p_horn * 3.0)
		var radar: float = sin(p_sweep) * 0.35 * (0.5 + 0.5 * sin(TAU * 6.0 * t))
		out[i] = tanh((horn * 0.65 + radar) * 1.5) * env * 0.85
	return _make_wav_from_samples(out)
