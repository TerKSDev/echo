extends Control

@onready var scroll_container: ScrollContainer = $MainArea/ScrollContainer
@onready var level_grid: GridContainer = $MainArea/ScrollContainer/GridMargin/LevelGrid
@onready var depth_gauge: Control = $DepthGauge
@onready var leaderboard_button: Button = $TopBar/LeaderboardButton
@onready var intel_button: Button = $TopBar/IntelButton
@onready var settings_button: Button = $TopBar/SettingsButton
@onready var status_pill: PanelContainer = $TopBar/StatusPill
@onready var progress_label: Label = $TopBar/StatusPill/StatusBox/ProgressLabel
@onready var mode_toggle: Button = get_node_or_null("TopBar/ModeToggle")
@onready var tracker_label: Label = get_node_or_null("HeaderBox/TrackerLabel") if has_node("HeaderBox/TrackerLabel") else get_node_or_null("MainArea/HeaderBox/TrackerLabel")
@onready var title_label: Label = get_node_or_null("HeaderBox/Title") if has_node("HeaderBox/Title") else get_node_or_null("MainArea/HeaderBox/Title")
@onready var subtitle_label: Label = get_node_or_null("HeaderBox/Subtitle") if has_node("HeaderBox/Subtitle") else get_node_or_null("MainArea/HeaderBox/Subtitle")
@onready var sector_label: Label = get_node_or_null("TopBar/StatusPill/StatusBox/SectorLabel")
@onready var sonar_backdrop: Control = $SonarBackdrop

var reset_run_button: Button = null

var _time := 0.0
var _ambient_wave_timer := 2.5
var _ripples: Array[Dictionary] = []
var _spores: Array[Dictionary] = []

var _suppress_level_click := false
var _level_buttons: Dictionary = {}

var _depth_tag_alpha: float = 0.0
var _depth_tag_timer: float = 0.0
var _is_dragging_gauge: bool = false
var _overscroll_dist: float = 0.0
var _abyss_arrow_canvas: Control = null
var _is_mode_transitioning: bool = false

# Procedural UI Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_error: AudioStreamWAV
var _wav_launch: AudioStreamWAV


func _ready() -> void:
	_build_ui_audio()
	GameState.start_menu_bgm()
	_init_spores()

	# Background effects should not block button input.
	sonar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_backdrop.draw.connect(_draw_sonar_backdrop)

	scroll_container.gui_input.connect(_on_scroll_container_gui_input)

	# Hide scrollbar visually while retaining smooth scrolling
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.modulate.a = 0.0
	scrollbar.value_changed.connect(func(_val: float) -> void:
		_depth_tag_timer = 1.0
		if depth_gauge != null and is_instance_valid(depth_gauge):
			depth_gauge.queue_redraw()
	)

	# Two columns create the left-right staggered vertical ascent map
	level_grid.columns = 2
	level_grid.add_theme_constant_override("h_separation", 16)
	level_grid.add_theme_constant_override("v_separation", 44)

	# Wire level grid path drawing
	level_grid.draw.connect(_draw_level_path)

	# Setup custom subterranean depth gauge
	if depth_gauge != null:
		depth_gauge.draw.connect(_draw_depth_gauge)
		depth_gauge.gui_input.connect(_on_depth_gauge_gui_input)

	# Status star display: hidden per user request to keep top bar clean and minimal
	if status_pill != null:
		status_pill.visible = false

	_setup_mode_toggle()
	_setup_reset_run_button()
	_setup_intel_button()
	_setup_settings_button()
	_setup_leaderboard_button()

	_create_level_buttons()
	_update_header_and_mode_ui()
	GameState.update_bgm_for_mode()

	# Auto-scroll directly to the highest active level on entry
	call_deferred("_scroll_to_current_level")
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
		if has_node("HeaderBox"):
			var hdr := $HeaderBox as Control
			hdr.offset_top = target_top + 66.0
		if has_node("MainArea"):
			var main := $MainArea as Control
			main.offset_top = target_top + 163.0
		if has_node("DepthGauge"):
			var gauge := $DepthGauge as Control
			gauge.offset_top = target_top + 76.0


# --------------------------------------------------
# NAVIGATION & LEVEL DATA
# --------------------------------------------------

func _get_playable_levels() -> Array[String]:
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		if GameState.challenge_highest_unlocked < 21:
			return GameState.CHALLENGE_LEVELS.slice(0, 20)
		return GameState.CHALLENGE_LEVELS
	return GameState.STORY_LEVELS


func _on_scroll_container_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		_depth_tag_timer = 1.0
		var rel_y: float = event.relative.y

		var vbar := scroll_container.get_v_scroll_bar()
		var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
		var max_scroll := maxf(0.0, vbar.max_value - page)

		if GameState.current_mode == GameState.GameMode.STORY:
			# At bottom of story mode: dragging upwards pulls downward past the abyss (only active once challenge unlocked)
			if GameState.is_challenge_unlocked() and scroll_container.scroll_vertical >= max_scroll - 10.0 and rel_y < -3.0:
				_overscroll_dist += absf(rel_y)
				if _overscroll_dist >= 45.0:
					_overscroll_dist = 0.0
					_descend_to_challenge_mode()
			elif scroll_container.scroll_vertical < max_scroll - 25.0:
				_overscroll_dist = 0.0
		else:
			# At top of challenge mode: dragging downwards pulls upwards to ascend
			if scroll_container.scroll_vertical <= 10.0 and rel_y > 3.0:
				_overscroll_dist += rel_y
				if _overscroll_dist >= 45.0:
					_overscroll_dist = 0.0
					_ascend_to_story_mode()
			elif scroll_container.scroll_vertical > 25.0:
				_overscroll_dist = 0.0

	elif event is InputEventMouseButton and event.is_pressed():
		var vbar := scroll_container.get_v_scroll_bar()
		var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
		var max_scroll := maxf(0.0, vbar.max_value - page)

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if GameState.current_mode == GameState.GameMode.STORY and GameState.is_challenge_unlocked() and scroll_container.scroll_vertical >= max_scroll - 10.0:
				_overscroll_dist += 25.0
				if _overscroll_dist >= 45.0:
					_overscroll_dist = 0.0
					_descend_to_challenge_mode()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if GameState.current_mode == GameState.GameMode.CHALLENGE and scroll_container.scroll_vertical <= 10.0:
				_overscroll_dist += 25.0
				if _overscroll_dist >= 45.0:
					_overscroll_dist = 0.0
					_ascend_to_story_mode()


# --------------------------------------------------
# TOP BAR BUTTONS & MODE SETUP
# --------------------------------------------------

func _setup_mode_toggle() -> void:
	if mode_toggle == null:
		return
	# Challenge mode is completely hidden until all 21 story sectors are cleared!
	mode_toggle.visible = GameState.is_challenge_unlocked()
	mode_toggle.custom_minimum_size = Vector2(0, 50)
	mode_toggle.flat = true
	mode_toggle.focus_mode = Control.FOCUS_NONE
	mode_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty_sb := StyleBoxEmpty.new()
	mode_toggle.add_theme_stylebox_override("normal", empty_sb)
	mode_toggle.add_theme_stylebox_override("hover", empty_sb)
	mode_toggle.add_theme_stylebox_override("pressed", empty_sb)
	mode_toggle.add_theme_stylebox_override("focus", empty_sb)
	_style_mode_toggle(mode_toggle, GameState.current_mode == GameState.GameMode.CHALLENGE)
	mode_toggle.pressed.connect(_on_mode_toggle_pressed)
	_wire_button_Juice(mode_toggle)


func _style_mode_toggle(btn: Button, is_challenge: bool) -> void:
	if btn == null:
		return
	var empty_sb := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_font_size_override("font_size", 16)
	if is_challenge:
		btn.text = "◈ CHALLENGE"
		btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.80, 0.90))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.92, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.90, 0.25, 0.65, 1.0))
	else:
		btn.text = "◈ STORY"
		btn.add_theme_color_override("font_color", Color(0.78, 0.90, 1.0, 0.85))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.55, 0.88, 1.0, 1.0))


func _on_mode_toggle_pressed() -> void:
	if GameState.current_mode == GameState.GameMode.STORY:
		if GameState.is_challenge_unlocked():
			_descend_to_challenge_mode()
	else:
		_ascend_to_story_mode()


func _setup_intel_button() -> void:
	intel_button.custom_minimum_size = Vector2(48, 48)
	intel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intel_button.flat = true
	intel_button.focus_mode = Control.FOCUS_NONE
	var empty_sb := StyleBoxEmpty.new()
	intel_button.add_theme_stylebox_override("normal", empty_sb)
	intel_button.add_theme_stylebox_override("hover", empty_sb)
	intel_button.add_theme_stylebox_override("pressed", empty_sb)
	intel_button.add_theme_stylebox_override("focus", empty_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_book(icon_canvas))
	intel_button.add_child(icon_canvas)

	intel_button.mouse_entered.connect(func(): icon_canvas.queue_redraw())
	intel_button.mouse_exited.connect(func(): icon_canvas.queue_redraw())
	intel_button.pressed.connect(_on_intel_pressed)
	_wire_button_Juice(intel_button)


func _setup_settings_button() -> void:
	settings_button.custom_minimum_size = Vector2(48, 48)
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_button.flat = true
	settings_button.focus_mode = Control.FOCUS_NONE
	var empty_sb := StyleBoxEmpty.new()
	settings_button.add_theme_stylebox_override("normal", empty_sb)
	settings_button.add_theme_stylebox_override("hover", empty_sb)
	settings_button.add_theme_stylebox_override("pressed", empty_sb)
	settings_button.add_theme_stylebox_override("focus", empty_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_gear(icon_canvas))
	settings_button.add_child(icon_canvas)

	settings_button.mouse_entered.connect(func(): icon_canvas.queue_redraw())
	settings_button.mouse_exited.connect(func(): icon_canvas.queue_redraw())
	settings_button.pressed.connect(_on_settings_pressed)
	_wire_button_Juice(settings_button)


func _setup_leaderboard_button() -> void:
	leaderboard_button.custom_minimum_size = Vector2(48, 48)
	leaderboard_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leaderboard_button.flat = true
	leaderboard_button.focus_mode = Control.FOCUS_NONE
	# Leaderboard is exclusive to Challenge Mode
	leaderboard_button.visible = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	var empty_sb := StyleBoxEmpty.new()
	leaderboard_button.add_theme_stylebox_override("normal", empty_sb)
	leaderboard_button.add_theme_stylebox_override("hover", empty_sb)
	leaderboard_button.add_theme_stylebox_override("pressed", empty_sb)
	leaderboard_button.add_theme_stylebox_override("focus", empty_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_trophy(icon_canvas))
	leaderboard_button.add_child(icon_canvas)

	leaderboard_button.mouse_entered.connect(func(): icon_canvas.queue_redraw())
	leaderboard_button.mouse_exited.connect(func(): icon_canvas.queue_redraw())
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	_wire_button_Juice(leaderboard_button)


func _setup_reset_run_button() -> void:
	if reset_run_button != null and is_instance_valid(reset_run_button):
		return
	var top_bar := get_node_or_null("TopBar") as HBoxContainer
	if top_bar == null:
		return

	reset_run_button = Button.new()
	reset_run_button.name = "ResetRunButton"
	reset_run_button.text = "RESET RUN"
	reset_run_button.custom_minimum_size = Vector2(104, 32)
	reset_run_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_run_button.focus_mode = Control.FOCUS_NONE
	reset_run_button.add_theme_font_size_override("font_size", 12)
	ModalTemplate.style_danger_button(reset_run_button, false, true)

	top_bar.add_child(reset_run_button)
	if mode_toggle != null:
		top_bar.move_child(reset_run_button, mode_toggle.get_index() + 1)

	var is_chal: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)
	var can_reset: bool = is_chal and (GameState.challenge_highest_unlocked > 1 or GameState.challenge_records.size() > 0)
	reset_run_button.visible = can_reset
	reset_run_button.pressed.connect(_on_reset_run_pressed)
	_wire_button_Juice(reset_run_button)


func _on_reset_run_pressed() -> void:
	_play_ui_sound(_wav_click, -4.0, 1.0)
	var modal_script: GDScript = load("res://ui/modals/ResetConfirmModal.gd") as GDScript
	if modal_script != null:
		modal_script.open(self, _on_confirm_reset_run)


func _on_confirm_reset_run() -> void:
	var vortex_script: GDScript = load("res://ui/level_select/AbyssVortexFx.gd") as GDScript
	if vortex_script != null:
		vortex_script.play(
			self,
			func():
				GameState.reset_challenge_run()
				_create_level_buttons()
				_update_header_and_mode_ui()
				scroll_container.scroll_vertical = 0
				call_deferred("_scroll_to_current_level")
		)
	else:
		GameState.reset_challenge_run()
		_create_level_buttons()
		_update_header_and_mode_ui()
		scroll_container.scroll_vertical = 0
		call_deferred("_scroll_to_current_level")


func _on_leaderboard_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	var modal_script: GDScript = load("res://ui/modals/LeaderboardModal.gd") as GDScript
	if modal_script != null:
		modal_script.open_modal(self)


func _on_intel_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	var script: GDScript = load("res://ui/modals/IntelModal.gd") as GDScript
	if script != null:
		script.open_modal(self)


func _on_settings_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	GameState.go_to_settings("res://ui/screens/level_select.tscn")


func _on_back_pressed() -> void:
	if _is_mode_transitioning or _suppress_level_click:
		return
	_suppress_level_click = true
	_play_ui_sound(_wav_click, -5.0, 0.9)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		GameState.go_to_menu()
	)


# --------------------------------------------------
# LEVEL BUTTON GRID
# --------------------------------------------------

func _create_level_buttons() -> void:
	for child in level_grid.get_children():
		child.queue_free()
	_level_buttons.clear()

	var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()

	if is_challenge:
		# Levels in Challenge Mode:
		# Delving downwards from Level 1 (-4,500M) down to Level 21 (-9,999M King Sector SP)!
		for level_number in range(1, total_levels + 1):
			var p_idx := level_number - 1
			var lvl_path: String = playable_levels[p_idx] if (p_idx >= 0 and p_idx < playable_levels.size()) else ""
			var button: Button = LevelCardBuilder.build_level_card(
				level_number,
				func() -> float: return _time,
				_on_level_pressed,
				_wire_button_Juice,
				_play_ui_sound,
				_wav_error,
				lvl_path
			)
			_level_buttons[level_number] = button

			if level_number == 21 and not GameState.challenge_sp_revealed:
				button.modulate.a = 0.0
				button.scale = Vector2(0.5, 0.5)
				button.pivot_offset = button.custom_minimum_size * 0.5

			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 78)
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Challenge Mode staggered layout: Level 1 Right, Level 2 Left, Level 3 Right... ("右左右左")
			if level_number % 2 == 1:
				level_grid.add_child(spacer)
				level_grid.add_child(button)
			else:
				level_grid.add_child(button)
				level_grid.add_child(spacer)

	else:
		# Story Mode:
		# Iterate from total_levels (Level 21: Surface Breach) down to 1 (Level 1: First Steps / Training)
		for level_number in range(total_levels, 0, -1):
			var p_idx := level_number - 1
			var lvl_path: String = playable_levels[p_idx] if (p_idx >= 0 and p_idx < playable_levels.size()) else ""
			var button: Button = LevelCardBuilder.build_level_card(
				level_number,
				func() -> float: return _time,
				_on_level_pressed,
				_wire_button_Juice,
				_play_ui_sound,
				_wav_error,
				lvl_path
			)
			_level_buttons[level_number] = button

			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 78)
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Story Mode staggered layout: Level 1 Left, Level 2 Right, Level 3 Left... ("左右左右")
			if level_number % 2 == 1:
				level_grid.add_child(button)
				level_grid.add_child(spacer)
			else:
				level_grid.add_child(spacer)
				level_grid.add_child(button)

		# At the deepest bottom of Story Mode:
		var is_unlocked: bool = GameState.is_challenge_unlocked()
		if is_unlocked:
			# Large subtle downward arrow indicating players can pull down to descend into Challenge Mode
			var arrow_canvas := Control.new()
			arrow_canvas.name = "AbyssDescentPrompt"
			arrow_canvas.custom_minimum_size = Vector2(290, 110)
			arrow_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
			arrow_canvas.draw.connect(func(): _draw_abyss_descent_prompt(arrow_canvas))
			arrow_canvas.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
					_descend_to_challenge_mode()
			)

			var arrow_spacer := Control.new()
			arrow_spacer.custom_minimum_size = Vector2(290, 110)
			arrow_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
			arrow_spacer.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
					_descend_to_challenge_mode()
			)

			level_grid.add_child(arrow_canvas)
			level_grid.add_child(arrow_spacer)
			_abyss_arrow_canvas = arrow_canvas


func _update_header_and_mode_ui() -> void:
	var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE
	if is_challenge:
		if tracker_label != null:
			tracker_label.text = "((   F O R B I D D E N   A B Y S S   ))"
			tracker_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.75, 0.9))
		if title_label != null:
			title_label.text = "CHALLENGE SECTORS"
			title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.95))
			title_label.add_theme_color_override("font_shadow_color", Color(0.48, 0.05, 0.22, 0.95))
			title_label.add_theme_color_override("font_outline_color", Color(0.85, 0.25, 0.65, 0.7))
		if subtitle_label != null:
			subtitle_label.text = "Enter the deep void. Conquer the King Sector."
			subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.65, 0.85, 0.85))
		if sector_label != null:
			sector_label.visible = false
		if mode_toggle != null:
			mode_toggle.visible = true
			_style_mode_toggle(mode_toggle, true)
	else:
		if tracker_label != null:
			tracker_label.text = "((   E S C A P E   T H E   A B Y S S   ))"
			tracker_label.add_theme_color_override("font_color", Color(0.38, 0.75, 1, 0.85))
		if title_label != null:
			title_label.text = "ESCAPE THE ABYSS"
			title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1, 1))
			title_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.22, 0.48, 0.85))
			title_label.add_theme_color_override("font_outline_color", Color(0.25, 0.68, 0.95, 0.55))
		if subtitle_label != null:
			subtitle_label.text = "Stay calm. Stay silent. Find the way out."
			subtitle_label.add_theme_color_override("font_color", Color(0.55, 0.76, 0.92, 0.8))
		if sector_label != null:
			sector_label.visible = false
		if mode_toggle != null:
			mode_toggle.visible = GameState.is_challenge_unlocked()
			_style_mode_toggle(mode_toggle, false)

	# Leaderboard and Reset Run are exclusive to Challenge Mode
	if leaderboard_button != null:
		leaderboard_button.visible = is_challenge
	if reset_run_button != null and is_instance_valid(reset_run_button):
		var can_reset: bool = is_challenge and (GameState.challenge_highest_unlocked > 1 or GameState.challenge_records.size() > 0)
		reset_run_button.visible = can_reset

	# Update Top Status Bar: cleanly display current total star count without clutter
	var playable_levels := _get_playable_levels()
	var total_levels: int = playable_levels.size()
	var total_stars := 0
	for i in range(1, total_levels + 1):
		total_stars += GameState.get_level_stars(i)
	if progress_label != null:
		progress_label.text = str(total_stars)
		progress_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
		progress_label.add_theme_font_size_override("font_size", 15)

	if depth_gauge != null and is_instance_valid(depth_gauge):
		depth_gauge.queue_redraw()


func _on_rift_descend_triggered() -> void:
	if GameState.is_challenge_unlocked():
		_descend_to_challenge_mode()


func _draw_abyss_descent_prompt(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas):
		return
	var grid_w := level_grid.size.x if (level_grid != null and level_grid.size.x > 100.0) else 600.0
	var cx: float = grid_w * 0.5 - canvas.position.x
	var bob: float = sin(_time * 3.2) * 5.0
	var cy: float = 46.0 + bob

	var a: float = 0.35 + 0.12 * sin(_time * 3.2)
	if _overscroll_dist > 0.0:
		a = clampf(a + (_overscroll_dist / 45.0) * 0.55, 0.0, 1.0)

	var chevron_col := Color(0.85, 0.45, 0.95, a)
	var tip := Vector2(cx, cy + 14.0)
	var arm_l := Vector2(cx - 28.0, cy - 8.0)
	var arm_r := Vector2(cx + 28.0, cy - 8.0)
	canvas.draw_line(arm_l, tip, chevron_col, 2.5)
	canvas.draw_line(arm_r, tip, chevron_col, 2.5)

	# Faint secondary echo chevron
	var tip2 := Vector2(cx, cy + 3.0)
	var arm2_l := Vector2(cx - 18.0, cy - 14.0)
	var arm2_r := Vector2(cx + 18.0, cy - 14.0)
	var echo_col := Color(chevron_col.r, chevron_col.g, chevron_col.b, a * 0.48)
	canvas.draw_line(arm2_l, tip2, echo_col, 1.6)
	canvas.draw_line(arm2_r, tip2, echo_col, 1.6)

	# Subtle guidance text
	var text_col := Color(0.85, 0.65, 0.95, a * 0.78)
	var font := ThemeDB.fallback_font
	if font != null:
		canvas.draw_string(font, Vector2(cx - 110.0, cy + 38.0), "PULL DOWN FOR CHALLENGE ABYSS", HORIZONTAL_ALIGNMENT_CENTER, 220.0, 11, text_col)


func _descend_to_challenge_mode() -> void:
	_transition_mode(true)


func _ascend_to_story_mode() -> void:
	_transition_mode(false)


func _transition_mode(to_challenge: bool) -> void:
	if _is_mode_transitioning:
		return
	_is_mode_transitioning = true

	var main_node := get_node_or_null("MainArea") as Control
	var header_node := get_node_or_null("HeaderBox") as Control
	var top_bar := get_node_or_null("TopBar") as Control
	var orig_main_y: float = main_node.position.y if main_node != null else 192.0
	var orig_hdr_y: float = header_node.position.y if header_node != null else 95.0

	# 1. Starting Atmospheric Audio
	if to_challenge:
		# Deep low rumble plunge into the abyss
		_play_ui_sound(_wav_click, -1.0, 0.40)
	else:
		# Bright soaring ascension echo back to caverns
		_play_ui_sound(_wav_click, -1.5, 1.25)

	# 2. VFX Fullscreen Canvas
	var vfx := Control.new()
	vfx.name = "ModeTransitionOverlay"
	vfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	vfx.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(vfx)

	var vp_w: float = size.x if size.x > 100.0 else 720.0
	var vp_h: float = size.y if size.y > 100.0 else 1280.0

	# Speed streaks dataset
	var streaks: Array[Dictionary] = []
	for i in 32:
		streaks.append({
			"x": randf_range(16.0, vp_w - 16.0),
			"y": randf_range(0.0, vp_h),
			"len": randf_range(110.0, 260.0),
			"speed": randf_range(2200.0, 3600.0),
			"width": randf_range(1.6, 2.8),
			"alpha": randf_range(0.4, 0.9)
		})

	var vfx_state := {
		"dark_alpha": 0.0,
		"streak_fade": 0.0,
		"ring_radius": 0.0,
		"ring_alpha": 0.0
	}
	var start_ms := Time.get_ticks_msec()

	# Custom draw function for continuous, buttery-smooth 60+ FPS motion
	vfx.draw.connect(func():
		var elapsed := (Time.get_ticks_msec() - start_ms) * 0.001

		# 1. Background dark veil
		var bg_col: Color
		if to_challenge:
			bg_col = Color(0.02, 0.006, 0.022, float(vfx_state["dark_alpha"]))
		else:
			bg_col = Color(0.006, 0.018, 0.032, float(vfx_state["dark_alpha"]))
		vfx.draw_rect(Rect2(0.0, 0.0, vp_w, vp_h), bg_col, true)

		# 2. Flowing speed streaks
		if float(vfx_state["streak_fade"]) > 0.01:
			var base_col: Color = Color(1.0, 0.40, 0.88) if to_challenge else Color(0.38, 0.88, 1.0)
			for s: Dictionary in streaks:
				var cur_y: float
				var p1: Vector2
				var p2: Vector2
				var l_len: float = float(s["len"])
				var spd: float = float(s["speed"])
				var w: float = float(s["width"])
				var a: float = float(s["alpha"]) * float(vfx_state["streak_fade"])

				if to_challenge:
					# Plunging: streaks fly UPWARD
					cur_y = fmod(float(s["y"]) - spd * elapsed, vp_h)
					if cur_y < 0.0:
						cur_y += vp_h
					p1 = Vector2(float(s["x"]), cur_y)
					p2 = Vector2(float(s["x"]), cur_y - l_len)
				else:
					# Ascending: streaks fly DOWNWARD
					cur_y = fmod(float(s["y"]) + spd * elapsed, vp_h)
					p1 = Vector2(float(s["x"]), cur_y)
					p2 = Vector2(float(s["x"]), cur_y + l_len)

				var col := Color(base_col.r, base_col.g, base_col.b, a)
				vfx.draw_line(p1, p2, col, w)

		# 3. Acoustic Arrival Sonar Ring (expands outwards from center)
		if float(vfx_state["ring_alpha"]) > 0.01 and float(vfx_state["ring_radius"]) > 1.0:
			var center := Vector2(vp_w * 0.5, vp_h * 0.5)
			var ring_col: Color = Color(1.0, 0.40, 0.88, float(vfx_state["ring_alpha"])) if to_challenge else Color(0.38, 0.88, 1.0, float(vfx_state["ring_alpha"]))
			vfx.draw_arc(center, float(vfx_state["ring_radius"]), 0.0, TAU, 36, ring_col, 2.5)
			if float(vfx_state["ring_radius"]) > 30.0:
				var echo_col := Color(ring_col.r, ring_col.g, ring_col.b, float(vfx_state["ring_alpha"]) * 0.45)
				vfx.draw_arc(center, float(vfx_state["ring_radius"]) * 0.65, 0.0, TAU, 28, echo_col, 1.5)
	)

	# Animation sequence
	var tw := create_tween()

	# --- PHASE 1: Departure & Dissolve (0.26s) ---
	var drift_dist := 75.0
	var out_dir := -1.0 if to_challenge else 1.0
	if top_bar != null:
		tw.parallel().tween_property(top_bar, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if main_node != null:
		tw.parallel().tween_property(main_node, "position:y", orig_main_y + out_dir * drift_dist, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(main_node, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if header_node != null:
		tw.parallel().tween_property(header_node, "position:y", orig_hdr_y + out_dir * (drift_dist * 0.5), 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(header_node, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.parallel().tween_method(func(v: float):
		vfx_state["dark_alpha"] = v
		vfx_state["streak_fade"] = v
		vfx.queue_redraw()
	, 0.0, 1.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# --- PHASE 2: Mid-Transition Singularity (Screen is 100% covered) ---
	tw.tween_callback(func():
		if to_challenge:
			GameState.current_mode = GameState.GameMode.CHALLENGE
			_create_level_buttons()
			_update_header_and_mode_ui()
			scroll_container.scroll_vertical = 0
			call_deferred(&"_reset_scroll_to_top")
			# Arrival impact audio (deep cavern sub-thud)
			_play_ui_sound(_wav_click, 2.0, 0.48)
			GameState.update_bgm_for_mode()
		else:
			GameState.current_mode = GameState.GameMode.STORY
			_create_level_buttons()
			_update_header_and_mode_ui()
			call_deferred(&"_scroll_to_level_1")
			# Surface breach chime (crisp cavern echo)
			_play_ui_sound(_wav_click, 0.5, 1.45)
			GameState.update_bgm_for_mode()

		# Set up arrival entry positions (glide into place from opposite direction)
		var in_dir := 1.0 if to_challenge else -1.0
		if top_bar != null:
			top_bar.modulate.a = 0.0
		if main_node != null:
			main_node.position.y = orig_main_y + in_dir * 55.0
			main_node.modulate.a = 0.0
		if header_node != null:
			header_node.position.y = orig_hdr_y + in_dir * 30.0
			header_node.modulate.a = 0.0
	)

	# Brief micro-hold (0.03s) to allow Godot to settle scroll & layout before opening the veil
	tw.tween_interval(0.03)

	# --- PHASE 3: Arrival Emergence & Sonar Echo (0.34s) ---
	if top_bar != null:
		tw.parallel().tween_property(top_bar, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if main_node != null:
		tw.tween_property(main_node, "position:y", orig_main_y, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(main_node, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_interval(0.0) # anchor step
	if header_node != null:
		tw.parallel().tween_property(header_node, "position:y", orig_hdr_y, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(header_node, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.parallel().tween_method(func(v: float):
		vfx_state["dark_alpha"] = v
		vfx_state["streak_fade"] = v * 0.5
		vfx.queue_redraw()
	, 1.0, 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Expanding acoustic arrival ripple
	tw.parallel().tween_method(func(r: float):
		vfx_state["ring_radius"] = r
		vfx.queue_redraw()
	, 0.0, 420.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tw.parallel().tween_method(func(a: float):
		vfx_state["ring_alpha"] = a
		vfx.queue_redraw()
	, 0.85, 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- FINISH ---
	tw.tween_callback(func():
		if top_bar != null:
			top_bar.modulate.a = 1.0
		if main_node != null:
			main_node.position.y = orig_main_y
			main_node.modulate.a = 1.0
		if header_node != null:
			header_node.position.y = orig_hdr_y
			header_node.modulate.a = 1.0
		_is_mode_transitioning = false
		vfx.queue_free()
	)


func _reset_scroll_to_top() -> void:
	if scroll_container != null and is_instance_valid(scroll_container):
		scroll_container.scroll_vertical = 0
	if is_inside_tree():
		await get_tree().process_frame
		if scroll_container != null and is_instance_valid(scroll_container):
			scroll_container.scroll_vertical = 0


func _scroll_to_level_1() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var vbar := scroll_container.get_v_scroll_bar()
	var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
	var max_scroll := maxf(0.0, vbar.max_value - page)
	var btn: Button = _level_buttons.get(1)
	if btn != null and is_instance_valid(btn) and btn.position.y > 0.0:
		var target_y := btn.position.y - 120.0
		scroll_container.scroll_vertical = int(clampf(target_y, 0.0, max_scroll))
	else:
		scroll_container.scroll_vertical = int(max_scroll)


func _scroll_to_current_level() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE
	if is_challenge and GameState.challenge_highest_unlocked >= 21 and not GameState.challenge_sp_revealed:
		_play_sp_unsealed_reveal_sequence()
		return

	var highest: int = GameState.highest_unlocked_level
	var btn: Button = _level_buttons.get(highest)
	if btn != null and is_instance_valid(btn):
		var target_y := btn.position.y - 120.0
		var vbar := scroll_container.get_v_scroll_bar()
		var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
		var max_scroll := maxf(0.0, vbar.max_value - page)
		var final_y := clampf(target_y, 0.0, max_scroll)
		var tw := create_tween()
		tw.tween_property(scroll_container, "scroll_vertical", int(final_y), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			if btn != null and is_instance_valid(btn):
				var pulse_tw := btn.create_tween()
				pulse_tw.tween_property(btn, "scale", Vector2(1.035, 1.035), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				pulse_tw.tween_property(btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)
		)


func _play_sp_unsealed_reveal_sequence() -> void:
	var sp_btn: Button = _level_buttons.get(21)
	if sp_btn == null or not is_instance_valid(sp_btn):
		return

	_suppress_level_click = true

	# Position camera near Level 20 initially
	var btn_20: Button = _level_buttons.get(20)
	var vbar := scroll_container.get_v_scroll_bar()
	var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
	var max_scroll := maxf(0.0, vbar.max_value - page)
	if btn_20 != null and is_instance_valid(btn_20):
		scroll_container.scroll_vertical = int(clampf(btn_20.position.y - 120.0, 0.0, max_scroll))

	await get_tree().create_timer(0.45).timeout

	# 1. Deep seismic descent camera scroll to SP
	var target_y := clampf(sp_btn.position.y - 120.0, 0.0, max_scroll)
	var scroll_tw := create_tween()
	scroll_tw.tween_property(scroll_container, "scroll_vertical", int(target_y), 1.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# 2. Subterranean rumble screen shake & deep acoustic vibration
	_play_ui_sound(_wav_click, 2.5, 0.32)
	var shake_tw := create_tween()
	for i in range(16):
		var dx := randf_range(-4.5, 4.5)
		var dy := randf_range(-3.5, 3.5)
		shake_tw.tween_property(level_grid, "position", Vector2(dx, dy), 0.04)
	shake_tw.tween_property(level_grid, "position", Vector2.ZERO, 0.08)

	await scroll_tw.finished

	# 3. SP King Sector Unsealed scale punch & shockwave
	_play_ui_sound(_wav_launch if _wav_launch != null else _wav_click, 3.5, 0.72)
	sp_btn.pivot_offset = sp_btn.size * 0.5
	var reveal_tw := sp_btn.create_tween()
	reveal_tw.set_parallel(true)
	reveal_tw.tween_property(sp_btn, "modulate:a", 1.0, 0.22)
	reveal_tw.tween_property(sp_btn, "scale", Vector2(1.22, 1.22), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal_tw.chain().tween_property(sp_btn, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	level_grid.queue_redraw()
	if depth_gauge != null and is_instance_valid(depth_gauge):
		depth_gauge.queue_redraw()

	# 4. Cinematic Unsealed Announcement Banner Overlay
	_show_sp_unsealed_banner()

	GameState.mark_challenge_sp_revealed()
	_suppress_level_click = false


func _show_sp_unsealed_banner() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 200
	get_tree().root.add_child(canvas)

	var overlay := CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)

	var banner_box := PanelContainer.new()
	banner_box.custom_minimum_size = Vector2(560, 140)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.pivot_offset = Vector2(280, 70)
	banner_box.scale = Vector2(0.8, 0.8)
	banner_box.modulate.a = 0.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.02, 0.04, 0.94)
	sb.border_color = Color(1.0, 0.82, 0.35, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0.9, 0.15, 0.30, 0.55)
	sb.shadow_size = 20
	banner_box.add_theme_stylebox_override("panel", sb)
	overlay.add_child(banner_box)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	banner_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var tag_lbl := Label.new()
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.text = "◈  KING SECTOR UNSEALED  ◈"
	tag_lbl.add_theme_font_size_override("font_size", 13)
	tag_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	vbox.add_child(tag_lbl)

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.text = "THE FINAL ECHO"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.92))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.9, 0.12, 0.25, 0.95))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.text = "DEPTH: -9,999 M  •  ABYSSAL APEX"
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.78, 0.88))
	vbox.add_child(sub_lbl)

	var b_tw := banner_box.create_tween()
	b_tw.set_parallel(true)
	b_tw.tween_property(banner_box, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(banner_box, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b_tw.chain().tween_interval(2.2)
	b_tw.chain().tween_property(banner_box, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	b_tw.tween_callback(func():
		canvas.queue_free()
	)


func _draw_level_path() -> void:
	var playable_levels := _get_playable_levels()
	LevelPathRenderer.draw_level_path(
		level_grid,
		_level_buttons,
		playable_levels.size(),
		GameState.highest_unlocked_level,
		_time
	)


func _draw_depth_gauge() -> void:
	DepthGaugeRenderer.draw_depth_gauge(depth_gauge, scroll_container, _depth_tag_alpha)


func _on_depth_gauge_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and not event.pressed):
		_is_dragging_gauge = false
		_depth_tag_timer = 1.0
	elif (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)) or (event is InputEventScreenDrag):
		_is_dragging_gauge = true
		_depth_tag_timer = 1.0

	if _is_dragging_gauge:
		DepthGaugeRenderer.scrub_to_position(event.position.y, depth_gauge, scroll_container)


func _on_level_pressed(level_number: int) -> void:
	if _suppress_level_click:
		return

	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		if level_number < GameState.challenge_highest_unlocked:
			return # Cleared levels in challenge mode cannot be re-entered

	var playable_levels := _get_playable_levels()
	var playable_index: int = level_number - 1
	if playable_index < 0 or playable_index >= playable_levels.size():
		return

	_suppress_level_click = true
	var level_path := playable_levels[playable_index]
	var actual_level_index: int = GameState.get_current_levels().find(level_path)

	# Tactile launch sequence on the selected level button
	var btn: Button = _level_buttons.get(level_number)
	if btn != null and is_instance_valid(btn):
		btn.pivot_offset = btn.size * 0.5
		_play_ui_sound(_wav_launch if _wav_launch != null else _wav_click, -2.0, 1.0)
		var launch_tw := btn.create_tween()
		launch_tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.05).set_trans(Tween.TRANS_QUAD)
		launch_tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		launch_tw.tween_interval(0.04)
		launch_tw.tween_callback(func():
			if actual_level_index != -1:
				GameState.start_game(actual_level_index)
			else:
				GameState.change_level(level_path)
		)
	else:
		_play_ui_sound(_wav_click, -4.0, 1.0)
		if actual_level_index != -1:
			GameState.start_game(actual_level_index)
		else:
			GameState.change_level(level_path)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
		_launch_ready_level()
		get_viewport().set_input_as_handled()


func _launch_ready_level() -> void:
	var playable_levels := _get_playable_levels()
	var cur_lvl := clampi(GameState.highest_unlocked_level, 1, playable_levels.size())
	_on_level_pressed(cur_lvl)


# --------------------------------------------------
# AMBIENT SONAR AND FLOATING PARTICLES
# --------------------------------------------------

func _process(delta: float) -> void:
	_time += delta

	# Periodic ambient sonar wave - low frequency, random position, faint bioluminescent color
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

	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		pos.y -= float(spore["speed"]) * delta
		pos.x += sin(_time * 1.4 + float(spore["phase"])) * 12.0 * delta

		if pos.y < -20.0:
			pos.y = size.y + 20.0
			pos.x = randf_range(0.0, maxf(size.x, 600.0))

		spore["pos"] = pos

	# Smooth fade transition for live depth readout tag
	if _is_dragging_gauge:
		_depth_tag_timer = 1.0
	elif _depth_tag_timer > 0.0:
		_depth_tag_timer = maxf(0.0, _depth_tag_timer - delta)

	var target_alpha: float = 1.0 if _depth_tag_timer > 0.0 else 0.0
	var fade_speed: float = 14.0 if target_alpha > _depth_tag_alpha else 3.5
	_depth_tag_alpha = move_toward(_depth_tag_alpha, target_alpha, delta * fade_speed)

	sonar_backdrop.queue_redraw()
	if level_grid != null and is_instance_valid(level_grid):
		level_grid.queue_redraw()
	if depth_gauge != null and is_instance_valid(depth_gauge):
		if _depth_tag_alpha > 0.001 or _is_dragging_gauge:
			depth_gauge.queue_redraw()
	if _abyss_arrow_canvas != null and is_instance_valid(_abyss_arrow_canvas):
		_abyss_arrow_canvas.queue_redraw()

	# Redraw active level card (pulsing glow) and visible locked cards (scanning laser effect)
	for lvl in _level_buttons:
		var btn: Button = _level_buttons[lvl]
		if btn != null and is_instance_valid(btn):
			if lvl == GameState.highest_unlocked_level and btn.is_visible_in_tree():
				btn.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Clicking/touching empty space creates an ECHO wave
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_ripples.append({
			"pos": event.position,
			"age": 0.0,
			"max_r": randf_range(160.0, 240.0),
			"alpha": 0.28,
			"dur": 2.2
		})
		sonar_backdrop.queue_redraw()


func _init_spores() -> void:
	_spores.clear()
	for i in range(24):
		_spores.append({
			"pos": Vector2(
				randf_range(0.0, maxf(size.x, 720.0)),
				randf_range(0.0, maxf(size.y, 1280.0))
			),
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

		var center: Vector2 = ripple["pos"]
		sonar_backdrop.draw_arc(
			center,
			radius,
			0.0,
			TAU,
			48,
			Color(0.35, 0.85, 1.0, alpha),
			1.4
		)


# --------------------------------------------------
# MICRO-INTERACTION POLISH (JUICE)
# --------------------------------------------------

func _wire_button_Juice(btn: Button) -> void:
	btn.pivot_offset = btn.custom_minimum_size * 0.5

	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.025, 1.025), 0.12)
		_play_ui_sound(_wav_hover, -9.0, 1.05)
	)

	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.14)
	)

	btn.button_down.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.06)
		_play_ui_sound(_wav_click, -5.0, 1.0)
	)

	btn.button_up.connect(func():
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.10)
	)


# --------------------------------------------------
# PROCEDURAL UI AUDIO
# --------------------------------------------------

func _build_ui_audio() -> void:
	_wav_click = _synth_tone(880.0, 0.045, 0.28, 0.003, 0.038)
	_wav_hover = _synth_tone(1320.0, 0.030, 0.10, 0.002, 0.024)
	_wav_error = _synth_tone(180.0, 0.120, 0.40, 0.005, 0.090)
	_wav_launch = _synth_tone(520.0, 0.220, 0.45, 0.006, 0.160)


func _synth_tone(
	freq: float,
	duration: float,
	volume: float,
	attack: float = 0.005,
	release: float = 0.05
) -> AudioStreamWAV:
	var sample_rate := 22050
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)

	var phase := 0.0
	var phase_inc := TAU * freq / float(sample_rate)

	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := 1.0
		if t < attack:
			env = t / maxf(0.0001, attack)
		elif t > duration - release:
			env = maxf(0.0, (duration - t) / maxf(0.0001, release))

		var sample_val := sin(phase) * volume * env
		phase += phase_inc

		var s16 := int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _play_ui_sound(wav: AudioStreamWAV, vol_db: float, pitch: float = 1.0) -> void:
	if wav == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
