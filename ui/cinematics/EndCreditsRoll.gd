extends Control
class_name EndCreditsRoll
## Cinematic Movie-Style Rolling End Credits for ECHO: STAY SILENT.
## Features:
## - Absolute 50% Screen-Center Axis Alignment (zero lopsidedness)
## - Standalone Title Card at start, seamlessly matching ending cutscene
## - Second block held completely off-screen until scrolling commences
## - Symmetrical 2-column grid for playtesters
## - Fail-Safe Input: Hold to fast-forward (3.5x), Double-tap to skip (no dragging)
## - Final "THANK YOU FOR PLAYING" isolates in screen center, pauses, and fades to black.

signal credits_finished

const SCROLL_SPEED_NORMAL := 50.0
const SCROLL_SPEED_FAST := 185.0

var scroll_container: ScrollContainer = null
var content_box: VBoxContainer = null
var hint_label: Label = null
var curtain: ColorRect = null
var touch_input: Control = null

var _is_scrolling := false
var _is_holding := false
var _scroll_pos := 0.0
var _is_finished := false
var _is_stopping := false
var _stop_scroll_pos := 999999.0
var _last_press_time := -99999
var _tap_count := 0
var _time := 0.0
var _audio_player: AudioStreamPlayer = null
var _seamless_start := false


static func show_credits(parent: Node, on_complete: Callable = Callable(), play_audio: bool = true, seamless_start: bool = false) -> EndCreditsRoll:
	var roll := EndCreditsRoll.new()
	roll.name = "EndCreditsRoll"
	roll._seamless_start = seamless_start
	roll.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll.mouse_filter = Control.MOUSE_FILTER_STOP
	roll.z_index = 450
	parent.add_child(roll)
	if on_complete.is_valid():
		roll.credits_finished.connect(on_complete)
	if play_audio:
		roll.start_credits_audio()
	return roll


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_populate_credits()

	if _seamless_start:
		# Start completely transparent so the ending cutscene's title card carries over seamlessly
		curtain.color = Color(0.01, 0.015, 0.02, 0.0)
	else:
		# Fade in from black for main menu credits button
		curtain.color = Color(0.01, 0.015, 0.02, 1.0)
		var tw := create_tween()
		tw.tween_property(curtain, "color:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)

	# Standalone pause on title card: rests in center of screen for 1.6s before rolling begins
	get_tree().create_timer(1.6).timeout.connect(func():
		if not _is_finished:
			_is_scrolling = true
	)


func start_credits_audio() -> void:
	if _audio_player == null:
		_audio_player = AudioStreamPlayer.new()
		_audio_player.name = "CreditsAudio"
		_audio_player.bus = &"BGM"
		add_child(_audio_player)
	_audio_player.stream = SfxManager.get_surface_dawn_bgm_pad()
	_audio_player.volume_db = -24.0
	_audio_player.play()
	var tw := create_tween()
	tw.tween_property(_audio_player, "volume_db", -7.0, 2.0).set_trans(Tween.TRANS_SINE)


func _build_ui() -> void:
	# 1. Dark Void Backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.020, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 2. Scroll Container
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll_container)

	var vbar := scroll_container.get_v_scroll_bar()
	if vbar != null:
		vbar.modulate.a = 0.0

	# 3. Content Margin & VBox (Centered with 30px side padding)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_container.add_child(margin)

	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content_box.add_theme_constant_override("separation", 14)
	content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content_box)

	# 4. Input Overlay: captures click, hold & double-tap (no dragging)
	touch_input = Control.new()
	touch_input.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_input.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_input.gui_input.connect(_on_touch_input)
	add_child(touch_input)

	# 5. Interactive Hint Label (Bottom)
	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -68.0
	hint_label.offset_bottom = -28.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.90, 0.65))
	hint_label.text = "HOLD TO SPEED UP  •  DOUBLE TAP TO SKIP"
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	# 6. Fade Curtain
	curtain = ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.01, 0.015, 0.02, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(curtain)


func _process(delta: float) -> void:
	if _is_finished:
		return
	_time += delta

	# Process smooth auto-scrolling once started
	if _is_scrolling and not _is_stopping:
		var speed: float = SCROLL_SPEED_FAST if _is_holding else SCROLL_SPEED_NORMAL
		_scroll_pos += speed * delta

		# Check if the final message has reached the vertical center of the screen
		if _scroll_pos >= _stop_scroll_pos:
			_scroll_pos = _stop_scroll_pos
			_reach_final_dedication()

	if scroll_container != null:
		scroll_container.scroll_vertical = int(_scroll_pos)

	# Update hint label pulse & styling
	if hint_label != null and not _is_stopping:
		if _is_holding:
			hint_label.text = "»»   FAST FORWARDING (3.5X)   »»"
			hint_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45, 0.95))
		else:
			var pulse: float = 0.5 + 0.5 * sin(_time * 2.8)
			hint_label.text = "HOLD TO SPEED UP  •  DOUBLE TAP TO SKIP"
			hint_label.add_theme_color_override("font_color", Color(0.60, 0.75, 0.88, 0.35 + 0.35 * pulse))

	# Reset tap counter after double-tap window expires
	if _tap_count > 0 and Time.get_ticks_msec() - _last_press_time > 360:
		_tap_count = 0


func _reach_final_dedication() -> void:
	if _is_stopping:
		return
	_is_stopping = true

	# Fade out bottom hint label so the final screen is completely immaculate
	if hint_label != null:
		var tw := create_tween()
		tw.tween_property(hint_label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)

	# Hold on the centered dedication for 2.6 seconds, then fade out
	get_tree().create_timer(2.6).timeout.connect(func():
		_finish_credits()
	)


func _on_touch_input(event: InputEvent) -> void:
	if _is_finished:
		return

	var is_press := false
	var is_release := false
	var is_dbl := false

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_press = true
				if event.double_click:
					is_dbl = true
			else:
				is_release = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_press = true
			if event.double_tap:
				is_dbl = true
		else:
			is_release = true

	var now := Time.get_ticks_msec()

	if is_press:
		get_viewport().set_input_as_handled()

		# Immediately begin scrolling if touched during the initial title pause
		_is_scrolling = true

		if is_dbl:
			_skip_credits()
			return

		# Filter out duplicate mouse/touch emulation event occurring on same frame (< 75ms)
		var dt := now - _last_press_time
		if dt < 75:
			return

		# Human double tap
		if dt < 360 and _tap_count == 1:
			_tap_count = 0
			_skip_credits()
			return

		# Single press: start holding (fast-forward)
		_tap_count = 1
		_last_press_time = now
		_is_holding = true

	elif is_release:
		_is_holding = false
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _is_finished:
		return
	if event.is_action_pressed("ui_cancel"):
		_skip_credits()
	elif event.is_action_pressed("ui_accept"):
		_is_scrolling = true
		_is_holding = true
	elif event.is_action_released("ui_accept"):
		_is_holding = false


func _skip_credits() -> void:
	if _is_finished:
		return
	_finish_credits()


func _finish_credits() -> void:
	if _is_finished:
		return
	_is_finished = true

	# Fade out audio
	if _audio_player != null and _audio_player.playing:
		var a_tw := create_tween()
		a_tw.tween_property(_audio_player, "volume_db", -40.0, 1.2).set_trans(Tween.TRANS_QUAD)

	# Fade out screen to black
	var tw := create_tween()
	tw.tween_property(curtain, "color:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		credits_finished.emit()
		queue_free()
	)


# --- Content Population (Pure English & Laser Center Alignment) -------------

func _populate_credits() -> void:
	var vp_h: float = size.y if size.y > 100.0 else 1280.0
	var title_approx_h := 70.0

	# 1. Top Spacer: Places the opening Title Card at the EXACT VERTICAL CENTER OF THE SCREEN at scroll_pos = 0
	var top_center_spacer: float = maxf(0.0, (vp_h - title_approx_h) * 0.5)
	_add_spacer(top_center_spacer)

	# 2. Main Title Card (Stands alone in the center of the dark screen at start)
	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(title_box)

	var l_title := Label.new()
	l_title.text = "ECHO: STAY SILENT"
	l_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_title.add_theme_font_size_override("font_size", 50)
	l_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78, 1.0))
	l_title.add_theme_color_override("font_shadow_color", Color(0.85, 0.65, 0.20, 0.60))
	l_title.add_theme_constant_override("shadow_offset_y", 2)
	l_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(l_title)

	# 3. Off-Screen Buffer Spacer: Pushes the second section completely below the bottom edge of the display!
	_add_spacer(vp_h * 1.05)

	# 4. Studio
	_add_section("DEVELOPED BY")
	_add_highlight("H U S H L I G H T", Color(0.55, 0.92, 1.0), 24)
	_add_spacer(110.0)

	# 5. AI Disclosure Section
	_add_section("ASSET DISCLOSURE & TRANSPARENCY")
	_add_paragraph(
		"In full compliance with open development transparency standards:\n\n" +
		"• Background Concept Art & Visual Illustrations: Generated using generative AI models (FLUX / Midjourney) and artistically post-processed for atmospheric continuity.\n\n" +
		"• Application Icon: Conceptually drafted and refined using generative AI.\n\n" +
		"• Human Craft: All core mechanics, acoustic physics, real-time procedural audio synthesis, level layouts, code architecture, and accessibility engineering are 100% human-designed."
	)
	_add_spacer(120.0)

	# 6. Core Team & Production Roles
	_add_section("CORE PRODUCTION & DEVELOPMENT")
	_add_credit_pair("Project Lead & Director", "[ Director Name ]")
	_add_credit_pair("Lead Gameplay Programmer", "[ Lead Programmer ]")
	_add_credit_pair("Systems & Architecture", "[ Systems Engineer ]")
	_add_credit_pair("Lead Game & Level Design", "[ Game Designer ]")
	_add_credit_pair("Sound Engine & Synthesis", "[ Audio Engineer ]")
	_add_credit_pair("Procedural Music & Ambience", "[ Music Composer ]")
	_add_credit_pair("Narrative & Worldbuilding", "[ Narrative Designer ]")
	_add_credit_pair("Art Direction & Concepts", "[ Art Director ]")
	_add_credit_pair("UI / UX & Interaction Design", "[ UI/UX Designer ]")
	_add_credit_pair("Mobile & Touch Optimization", "[ Mobile Engineer ]")
	_add_spacer(120.0)

	# 7. Playtesters & QA (Symmetric 2-Column Grid)
	_add_section("EXPEDITION PLAYTESTERS & QA")
	_add_credit_pair("QA Lead & Balance Testing", "[ QA Lead ]")
	_add_spacer(36.0)
	_add_subline("BETA EXPEDITION EXPLORERS", Color(1.0, 0.85, 0.45, 0.90), 13)
	_add_spacer(16.0)
	_add_playtesters_grid([
		"[ Playtester 01 ]", "[ Playtester 02 ]",
		"[ Playtester 03 ]", "[ Playtester 04 ]",
		"[ Playtester 05 ]", "[ Playtester 06 ]",
		"[ Playtester 07 ]", "[ Playtester 08 ]"
	])
	_add_spacer(16.0)
	_add_subline("... and all participants in our closed alpha expeditions.", Color(0.65, 0.75, 0.85, 0.60), 12)
	_add_spacer(120.0)

	# 8. Universal Accessibility Ethos
	_add_section("UNIVERSAL ACCESSIBILITY ETHOS")
	_add_paragraph(
		"Designed so sound can be seen, and darkness can be navigated:\n\n" +
		"• Blind & Low Vision Support: Real-time 3D spatial exit beacons, acoustic wall reflection echoes, and distance proximity feelers enable full completion without sight.\n\n" +
		"• Deaf & Hard of Hearing Support: Fully visualized acoustic waves, shockwave rings, and vibrational telemetry enable silent play.\n\n" +
		"• Zero Violence Ethos: Overcoming primal fear through silence, spatial awareness, and calm."
	)
	_add_spacer(120.0)

	# 9. Engine & Technology
	_add_section("ENGINE & TECHNOLOGY")
	_add_credit_pair("Game Engine", "Godot Engine 4 (GL / D3D12)")
	_add_credit_pair("Audio Synthesis", "Procedural In-Memory 16-bit PCM")
	_add_credit_pair("Physics Simulation", "Jolt Physics 2D/3D")
	_add_credit_pair("Platform Services", "Huawei Game Service SDK")
	_add_spacer(120.0)

	# 10. Special Thanks
	_add_section("SPECIAL THANKS")
	_add_credit_pair("Family, Mentors & Friends", "[ Family & Mentors ]")
	_add_credit_pair("Open Source Community", "Godot Foundation & Contributors")
	_add_credit_pair("Artistic Inspiration", "All creators of ambient, atmospheric games")
	_add_credit_pair("Belief in Silence", "Everyone who dared to listen in the dark")

	# 11. Huge Gap before Final Dedication (Ensures all previous text has scrolled completely out of view!)
	_add_spacer(vp_h * 1.1)

	# 12. The Final Curtain Call Dedication (Stops right in the center!)
	var final_box := VBoxContainer.new()
	final_box.name = "FinalDedicationBox"
	final_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	final_box.alignment = BoxContainer.ALIGNMENT_CENTER
	final_box.add_theme_constant_override("separation", 20)
	final_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(final_box)

	var t1 := Label.new()
	t1.text = "T H A N K   Y O U   F O R   P L A Y I N G"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_font_size_override("font_size", 24)
	t1.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80, 1.0))
	final_box.add_child(t1)

	var t2 := Label.new()
	t2.text = "“In the deepest abyss, silence is not absence.\nIt is understanding.”"
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_font_size_override("font_size", 14)
	t2.add_theme_color_override("font_color", Color(0.68, 0.85, 0.98, 0.85))
	final_box.add_child(t2)

	var sp_small := Control.new()
	sp_small.custom_minimum_size = Vector2(0.0, 16.0)
	final_box.add_child(sp_small)

	var t3 := Label.new()
	t3.text = "H U S H L I G H T   ©   2 0 2 6"
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t3.add_theme_font_size_override("font_size", 13)
	t3.add_theme_color_override("font_color", Color(0.50, 0.65, 0.78, 0.70))
	final_box.add_child(t3)

	# Bottom Padding
	_add_spacer(vp_h * 0.8)

	# Compute the exact scroll position where final_box is vertically centered on screen
	_compute_stop_position(final_box)
	call_deferred("_compute_stop_position", final_box)


func _compute_stop_position(final_node: Control) -> void:
	if final_node == null or not is_instance_valid(final_node) or content_box == null:
		return
	var vp_h: float = size.y if size.y > 100.0 else 1280.0

	var cum_y := 0.0
	var sep: float = float(content_box.get_theme_constant("separation"))
	for child in content_box.get_children():
		if child == final_node:
			break
		if child is Control and child.visible:
			var h: float = child.custom_minimum_size.y
			if h <= 0.0:
				h = child.get_combined_minimum_size().y
			cum_y += h + sep

	var final_h: float = 160.0
	if final_node.get_combined_minimum_size().y > 20.0:
		final_h = final_node.get_combined_minimum_size().y

	_stop_scroll_pos = maxf(0.0, cum_y - (vp_h - final_h) * 0.5)


# --- Helper Builder Functions -----------------------------------------------

func _add_subline(text: String, col: Color, sz: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(l)


func _add_highlight(text: String, col: Color, sz: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(l)


func _add_section(title: String) -> void:
	var l := Label.new()
	l.text = "—   %s   —" % title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.48, 1.0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(l)


# Laser 50% Screen-Center Axis Alignment (Dot is strictly at x = 360px on 720px width)
func _add_credit_pair(role: String, person: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var l_role := Label.new()
	l_role.text = role.to_upper()
	l_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_role.add_theme_font_size_override("font_size", 13)
	l_role.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95, 0.85))
	l_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l_role)

	var div := Label.new()
	div.text = "   •   "
	div.custom_minimum_size = Vector2(40.0, 0.0)
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	div.add_theme_font_size_override("font_size", 12)
	div.add_theme_color_override("font_color", Color(0.40, 0.55, 0.70, 0.60))
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)

	var l_name := Label.new()
	l_name.text = person
	l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l_name.add_theme_font_size_override("font_size", 14)
	var is_placeholder: bool = person.begins_with("[")
	if is_placeholder:
		l_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.50, 0.95))
	else:
		l_name.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.95))
	l_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l_name)

	content_box.add_child(row)


# Perfectly balanced 2-Column Grid for Playtesters
func _add_playtesters_grid(names: Array[String]) -> void:
	var center_wrap := CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(center_wrap)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_wrap.add_child(grid)

	for name_str in names:
		var l := Label.new()
		l.text = name_str
		l.custom_minimum_size = Vector2(230.0, 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.50, 0.95) if name_str.begins_with("[") else Color(0.96, 0.98, 1.0, 0.95))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(l)


func _add_paragraph(text: String) -> void:
	var center_wrap := CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var p := Label.new()
	p.text = text
	p.custom_minimum_size = Vector2(580.0, 0.0)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_theme_font_size_override("font_size", 12)
	p.add_theme_color_override("font_color", Color(0.70, 0.82, 0.92, 0.82))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_wrap.add_child(p)

	content_box.add_child(center_wrap)


func _add_spacer(height: float) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0.0, height)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(sp)
