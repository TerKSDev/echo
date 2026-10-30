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
var _overscroll_dist_king: float = 0.0
var _abyss_arrow_canvas: Control = null
var _king_arrow_canvas: Control = null
var _is_mode_transitioning: bool = false
var _king_cinematic_layer: CanvasLayer = null

var _is_dragging_scroll := false
var _drag_touch_id := -1
var _drag_start_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _drag_velocity := 0.0
var _drag_last_time := 0.0

# Procedural UI Audio
var _wav_click: AudioStreamWAV
var _wav_hover: AudioStreamWAV
var _wav_error: AudioStreamWAV
var _wav_launch: AudioStreamWAV


func _ready() -> void:
	_setup_main_background()
	_build_ui_audio()
	if not GameState.pending_sp_king_sector_cinematic:
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
	if not GameState.pending_sp_king_sector_cinematic:
		GameState.update_bgm_for_mode()

	# Auto-scroll directly to the highest active level on entry
	call_deferred("_scroll_to_current_level")
	_apply_safe_area()

	# Check if coming from Story clear to unlock Challenge Mode
	if GameState.pending_challenge_unlock_modal:
		GameState.set_pending_challenge_unlock_modal(false)
		call_deferred("_show_challenge_unlock_celebration_modal")

	# Check if arriving directly after Level 20 pact selection to trigger King Sector cinematic
	if GameState.pending_sp_king_sector_cinematic:
		GameState.pending_sp_king_sector_cinematic = false
		call_deferred("_play_king_sector_cinematic", true)


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


func _setup_main_background() -> void:
	var bg_node := get_node_or_null("Background") as TextureRect
	if bg_node != null:
		var is_chal := (GameState.current_mode == GameState.GameMode.CHALLENGE)
		var bg_path := "res://assets/bg_challenge_abyss.jpg" if is_chal else "res://assets/bg_cave_abyss.jpg"
		var tex: Texture2D = null
		if ResourceLoader.exists(bg_path):
			tex = load(bg_path)
		if tex == null:
			var global_path := ProjectSettings.globalize_path(bg_path)
			var img := Image.new()
			if img.load(global_path) == OK:
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			bg_node.texture = tex
			bg_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


# --------------------------------------------------
# NAVIGATION & LEVEL DATA
# --------------------------------------------------

func _get_playable_levels() -> Array[String]:
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		return GameState.CHALLENGE_LEVELS.slice(0, 20)
	return GameState.STORY_LEVELS


func _apply_scroll_delta(dy: float) -> void:
	if scroll_container == null or not is_instance_valid(scroll_container):
		return
	_depth_tag_timer = 1.0
	var vbar := scroll_container.get_v_scroll_bar()
	var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
	var max_scroll := maxf(0.0, vbar.max_value - page)

	var new_scroll: float = clampf(scroll_container.scroll_vertical - dy, 0.0, max_scroll)
	scroll_container.scroll_vertical = int(new_scroll)

	_check_overscroll(dy, max_scroll)


func _check_overscroll(rel_y: float, max_scroll: float) -> void:
	if scroll_container == null or not is_instance_valid(scroll_container):
		return

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
		# At top of challenge mode: dragging downwards pulls upwards to ascend to story mode
		if scroll_container.scroll_vertical <= 10.0 and rel_y > 3.0:
			_overscroll_dist += rel_y
			if _overscroll_dist >= 45.0:
				_overscroll_dist = 0.0
				_ascend_to_story_mode()
		elif scroll_container.scroll_vertical > 25.0:
			_overscroll_dist = 0.0

		# At bottom of challenge mode: dragging upwards pulls downward to enter King Sector (only if Level 20 cleared)
		if GameState.challenge_highest_unlocked >= 21 and scroll_container.scroll_vertical >= max_scroll - 10.0 and rel_y < -3.0:
			_overscroll_dist_king += absf(rel_y)
			if _overscroll_dist_king >= 45.0:
				_overscroll_dist_king = 0.0
				_show_king_sector_confirmation_modal()
		elif scroll_container.scroll_vertical < max_scroll - 25.0:
			_overscroll_dist_king = 0.0


func _reset_all_button_press_states() -> void:
	for btn: Button in _level_buttons.values():
		if btn != null and is_instance_valid(btn):
			btn.button_pressed = false
			if btn.scale != Vector2.ONE:
				var tw := btn.create_tween()
				tw.tween_property(btn, "scale", Vector2.ONE, 0.08)


func _on_scroll_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var vbar := scroll_container.get_v_scroll_bar()
		var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
		var max_scroll := maxf(0.0, vbar.max_value - page)

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if GameState.current_mode == GameState.GameMode.STORY and GameState.is_challenge_unlocked() and scroll_container.scroll_vertical >= max_scroll - 10.0:
				_overscroll_dist += 25.0
				if _overscroll_dist >= 45.0:
					_overscroll_dist = 0.0
					_descend_to_challenge_mode()
			elif GameState.current_mode == GameState.GameMode.CHALLENGE and GameState.challenge_highest_unlocked >= 21 and scroll_container.scroll_vertical >= max_scroll - 10.0:
				_overscroll_dist_king += 25.0
				if _overscroll_dist_king >= 45.0:
					_overscroll_dist_king = 0.0
					_show_king_sector_confirmation_modal()
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
	GameState.go_to_leaderboard("res://ui/screens/level_select.tscn", clampi(GameState.current_level, 1, GameState.LEVELS.size()))


func _on_intel_pressed() -> void:
	_play_ui_sound(_wav_click, -5.0, 1.0)
	GameState.go_to_archives("res://ui/screens/level_select.tscn")


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
		# Delving downwards from Level 1 (-4,500M) down to Level 20 (-9,250M)!
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

		# If player has cleared Sector 20, add King Sector descent prompt below Sector 20
		if GameState.challenge_highest_unlocked >= 21:
			var king_prompt := Control.new()
			king_prompt.name = "KingSectorDescentPrompt"
			king_prompt.custom_minimum_size = Vector2(290, 110)
			king_prompt.mouse_filter = Control.MOUSE_FILTER_PASS
			king_prompt.draw.connect(func(): _draw_king_sector_descent_prompt(king_prompt))
			king_prompt.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and not ev.pressed):
					if not _suppress_level_click:
						_show_king_sector_confirmation_modal()
			)

			var king_spacer := Control.new()
			king_spacer.custom_minimum_size = Vector2(290, 110)
			king_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
			king_spacer.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and not ev.pressed):
					if not _suppress_level_click:
						_show_king_sector_confirmation_modal()
			)

			level_grid.add_child(king_prompt)
			level_grid.add_child(king_spacer)
			_king_arrow_canvas = king_prompt

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
				if (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and not ev.pressed):
					if not _suppress_level_click:
						_descend_to_challenge_mode()
			)

			var arrow_spacer := Control.new()
			arrow_spacer.custom_minimum_size = Vector2(290, 110)
			arrow_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
			arrow_spacer.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and not ev.pressed):
					if not _suppress_level_click:
						_descend_to_challenge_mode()
			)

			level_grid.add_child(arrow_canvas)
			level_grid.add_child(arrow_spacer)
			_abyss_arrow_canvas = arrow_canvas


func _update_header_and_mode_ui() -> void:
	_setup_main_background()
	var is_challenge := GameState.current_mode == GameState.GameMode.CHALLENGE
	if is_challenge:
		if tracker_label != null:
			tracker_label.text = "((   F O R B I D D E N   A B Y S S   ))"
			tracker_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.75, 0.9))
		if title_label != null:
			title_label.text = "CHALLENGE THE ABYSS"
			title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.95))
			title_label.add_theme_color_override("font_shadow_color", Color(0.48, 0.05, 0.22, 0.95))
			title_label.add_theme_color_override("font_outline_color", Color(0.85, 0.25, 0.65, 0.7))
		if subtitle_label != null:
			subtitle_label.text = "Plunge into the silent depths. Face the abyss."
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
		canvas.draw_string(font, Vector2(cx - 110.0, cy + 38.0), "PULL DOWN FOR CHALLENGE THE ABYSS", HORIZONTAL_ALIGNMENT_CENTER, 220.0, 11, text_col)


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

	var highest: int = mini(GameState.highest_unlocked_level, 20)
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


func _draw_king_sector_descent_prompt(canvas: Control) -> void:
	if canvas == null or not is_instance_valid(canvas):
		return
	var grid_w := level_grid.size.x if (level_grid != null and level_grid.size.x > 100.0) else 600.0
	var cx: float = grid_w * 0.5 - canvas.position.x
	var bob: float = sin(_time * 3.0) * 5.0
	var cy: float = 46.0 + bob

	var a: float = 0.45 + 0.15 * sin(_time * 3.0)
	if _overscroll_dist_king > 0.0:
		a = clampf(a + (_overscroll_dist_king / 45.0) * 0.55, 0.0, 1.0)

	var chevron_col := Color(1.0, 0.22, 0.35, a)
	var tip := Vector2(cx, cy + 14.0)
	var arm_l := Vector2(cx - 28.0, cy - 8.0)
	var arm_r := Vector2(cx + 28.0, cy - 8.0)
	canvas.draw_line(arm_l, tip, chevron_col, 2.5)
	canvas.draw_line(arm_r, tip, chevron_col, 2.5)

	# Secondary faint chevron
	var tip2 := Vector2(cx, cy + 3.0)
	var arm2_l := Vector2(cx - 18.0, cy - 14.0)
	var arm2_r := Vector2(cx + 18.0, cy - 14.0)
	var echo_col := Color(chevron_col.r, chevron_col.g, chevron_col.b, a * 0.48)
	canvas.draw_line(arm2_l, tip2, echo_col, 1.6)
	canvas.draw_line(arm2_r, tip2, echo_col, 1.6)

	# Prompt text
	var text_col := Color(1.0, 0.65, 0.78, a * 0.85)
	var font := ThemeDB.fallback_font
	if font != null:
		canvas.draw_string(font, Vector2(cx - 130.0, cy + 38.0), "PULL DOWN FOR KING SECTOR", HORIZONTAL_ALIGNMENT_CENTER, 260.0, 11, text_col)


func _show_king_sector_confirmation_modal() -> void:
	if _is_mode_transitioning or _suppress_level_click:
		return
	_suppress_level_click = true
	_play_ui_sound(_wav_click, -2.0, 0.75)

	var canvas := CanvasLayer.new()
	canvas.layer = 160
	canvas.name = "KingSectorConfirmCanvas"
	add_child(canvas)

	var root := Control.new()
	root.name = "KingSectorConfirmRoot"
	ModalTemplate.apply_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(root)

	var dimmer := ColorRect.new()
	ModalTemplate.apply_full_rect(dimmer)
	dimmer.color = Color(0.015, 0.005, 0.012, 0.90)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	var center := CenterContainer.new()
	ModalTemplate.apply_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 0)
	var card_sb := ModalTemplate.make_card_style(ModalTemplate.ThemeKind.CRIMSON)
	frame.add_theme_stylebox_override("panel", card_sb)
	center.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	frame.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text = "POINT OF NO RETURN"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
	header.add_child(title_lbl)

	var close_func := func():
		var close_tw := root.create_tween().set_parallel(true)
		close_tw.tween_property(root, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.tween_property(frame, "scale", Vector2(0.94, 0.94), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.chain().tween_callback(func():
			_suppress_level_click = false
			canvas.queue_free()
		)

	var close_btn := ModalTemplate.make_close_button(close_func, ModalTemplate.ThemeKind.CRIMSON)
	header.add_child(close_btn)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(0.85, 0.25, 0.35, 0.35)
	vbox.add_child(divider)

	var msg_lbl := Label.new()
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.94, 0.84, 0.88, 0.95))
	msg_lbl.text = "You stand before the deepest threshold of the abyss: -9,999 Meters.\n\nOnce entered, you cannot turn back until the final echo is silenced.\n\nAre you prepared to face the King Sector?"
	vbox.add_child(msg_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var stay_btn := Button.new()
	stay_btn.text = "STAY"
	stay_btn.custom_minimum_size = Vector2(100, 42)
	stay_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(stay_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	stay_btn.pressed.connect(close_func)
	btn_row.add_child(stay_btn)

	var descend_btn := Button.new()
	descend_btn.text = "DESCEND"
	descend_btn.custom_minimum_size = Vector2(140, 42)
	descend_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(descend_btn, true, ModalTemplate.ThemeKind.CRIMSON)
	descend_btn.pressed.connect(func():
		descend_btn.disabled = true
		stay_btn.disabled = true
		var close_tw := root.create_tween().set_parallel(true)
		close_tw.tween_property(root, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.chain().tween_callback(func():
			canvas.queue_free()
			_play_king_sector_cinematic(false)
		)
	)
	btn_row.add_child(descend_btn)


func _play_king_sector_cinematic(is_from_level_clear: bool = false) -> void:
	_suppress_level_click = true

	# 1. Hide all standard UI except the settings button
	if scroll_container != null:
		scroll_container.visible = false
	if depth_gauge != null:
		depth_gauge.visible = false
	if tracker_label != null:
		tracker_label.visible = false
	if title_label != null:
		title_label.visible = false
	if subtitle_label != null:
		subtitle_label.visible = false
	if mode_toggle != null:
		mode_toggle.visible = false
	if leaderboard_button != null:
		leaderboard_button.visible = false
	if intel_button != null:
		intel_button.visible = false
	if reset_run_button != null and is_instance_valid(reset_run_button):
		reset_run_button.visible = false
	if status_pill != null:
		status_pill.visible = false

	# 2. Setup Cinematic CanvasLayer
	if _king_cinematic_layer != null and is_instance_valid(_king_cinematic_layer):
		_king_cinematic_layer.queue_free()

	var canvas := CanvasLayer.new()
	canvas.layer = 180
	canvas.name = "KingSectorCinematicLayer"
	add_child(canvas)
	_king_cinematic_layer = canvas

	var vp_w: float = size.x if size.x > 100.0 else 720.0
	var vp_h: float = size.y if size.y > 100.0 else 1280.0

	# Blackout curtain covering screen
	var curtain := ColorRect.new()
	ModalTemplate.apply_full_rect(curtain)
	curtain.color = Color.BLACK
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(curtain)

	# Silence background music completely
	GameState.stop_menu_bgm(1.2)

	if is_from_level_clear:
		curtain.modulate.a = 1.0
	else:
		curtain.modulate.a = 0.0
		var tw_curtain := curtain.create_tween()
		tw_curtain.tween_property(curtain, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Dedicated Settings Button at top-right
	var safe_top: float = 32.0
	if OS.has_feature("mobile") or OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var screen_sz := DisplayServer.screen_get_size()
		if screen_sz.y > 0 and safe.position.y > 0:
			safe_top = maxf((float(safe.position.y) / float(screen_sz.y)) * vp_h + 6.0, 32.0)

	var cin_settings_btn := Button.new()
	cin_settings_btn.name = "CinematicSettingsButton"
	cin_settings_btn.custom_minimum_size = Vector2(48, 48)
	cin_settings_btn.position = Vector2(vp_w - 68, safe_top)
	cin_settings_btn.flat = true
	cin_settings_btn.focus_mode = Control.FOCUS_NONE
	var empty_sb := StyleBoxEmpty.new()
	cin_settings_btn.add_theme_stylebox_override("normal", empty_sb)
	cin_settings_btn.add_theme_stylebox_override("hover", empty_sb)
	cin_settings_btn.add_theme_stylebox_override("pressed", empty_sb)
	cin_settings_btn.add_theme_stylebox_override("focus", empty_sb)

	var icon_canvas := Control.new()
	icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_canvas.draw.connect(func(): Icons.draw_gear(icon_canvas))
	cin_settings_btn.add_child(icon_canvas)
	cin_settings_btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -4.0, 1.0)
		_on_settings_pressed()
	)
	canvas.add_child(cin_settings_btn)

	# 4. Solitary cavern water droplets in absolute silence
	var drop_stream := SfxManager.get_menu_bgm_droplet()
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(canvas):
			_play_ui_sound(drop_stream, -14.0, 0.82)
	)
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(canvas):
			_play_ui_sound(drop_stream, -16.0, 0.94)
	)

	# 5. At t = 2.4s: Crimson Eye & Abyssal Edge Corruption Awaken, Tense Music Starts
	var tension_player := AudioStreamPlayer.new()
	tension_player.stream = SfxManager.get_king_sector_tension_bgm()
	tension_player.bus = &"BGM"
	tension_player.volume_db = -32.0
	canvas.add_child(tension_player)

	var eye_view := CrimsonEyeView.new()
	eye_view.name = "CrimsonEye"
	eye_view.custom_minimum_size = Vector2(300, 150)
	eye_view.position = Vector2(vp_w * 0.5 - 150.0, vp_h * 0.28 - 75.0)
	eye_view.pivot_offset = Vector2(150.0, 75.0)
	eye_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eye_view.eye_open = 0.0
	canvas.add_child(eye_view)

	var corruption_view := AbyssalCorruptionCanvas.new()
	corruption_view.name = "AbyssalCorruption"
	ModalTemplate.apply_full_rect(corruption_view)
	corruption_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corruption_view.intensity = 0.0
	canvas.add_child(corruption_view)

	# Move settings button above eye and corruption
	canvas.move_child(cin_settings_btn, canvas.get_child_count() - 1)

	get_tree().create_timer(2.4).timeout.connect(func():
		if not is_instance_valid(canvas):
			return
		# Start tense adrenaline music
		tension_player.play()
		var music_tw := canvas.create_tween()
		music_tw.tween_property(tension_player, "volume_db", -5.5, 1.2).set_trans(Tween.TRANS_SINE)

		# Awakening sound whoosh
		_play_ui_sound(_wav_launch, -2.0, 0.42)

		# Snap eye open menacingly
		var eye_tw := canvas.create_tween().set_parallel(true)
		eye_tw.tween_property(eye_view, "eye_open", 1.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		eye_tw.tween_property(corruption_view, "intensity", 1.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	# 6. At t = 3.8s: Central King Sector Level Card Reveal
	var card_container := CenterContainer.new()
	ModalTemplate.apply_full_rect(card_container)
	card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(card_container)

	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = Vector2(340, 220)
	card_wrapper.pivot_offset = Vector2(170, 110)
	card_wrapper.modulate.a = 0.0
	card_wrapper.scale = Vector2(0.90, 0.90)
	card_container.add_child(card_wrapper)

	# Position card in lower half below the eye
	card_wrapper.position.y += 90.0

	var card_btn := Button.new()
	card_btn.custom_minimum_size = Vector2(340, 220)
	card_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_btn.focus_mode = Control.FOCUS_NONE

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.06, 0.012, 0.024, 0.96)
	normal_sb.border_color = Color(0.95, 0.22, 0.32, 0.95)
	normal_sb.set_border_width_all(2)
	normal_sb.set_corner_radius_all(14)
	normal_sb.shadow_color = Color(0.9, 0.1, 0.2, 0.45)
	normal_sb.shadow_size = 24

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.09, 0.018, 0.035, 0.98)
	hover_sb.border_color = Color(1.0, 0.38, 0.48, 1.0)
	hover_sb.shadow_size = 32

	card_btn.add_theme_stylebox_override("normal", normal_sb)
	card_btn.add_theme_stylebox_override("hover", hover_sb)
	card_btn.add_theme_stylebox_override("pressed", hover_sb)
	card_wrapper.add_child(card_btn)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	card_btn.add_child(margin)

	var card_vbox := VBoxContainer.new()
	card_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(card_vbox)

	var card_pill := Label.new()
	card_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_pill.text = "◈   K I N G   S E C T O R   ◈"
	card_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_pill.add_theme_font_size_override("font_size", 12)
	card_pill.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45, 0.95))
	card_vbox.add_child(card_pill)

	var card_title := Label.new()
	card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_title.text = "THE FINAL ECHO"
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_title.add_theme_font_size_override("font_size", 24)
	card_title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.96, 1.0))
	card_title.add_theme_color_override("font_shadow_color", Color(0.9, 0.1, 0.25, 0.95))
	card_title.add_theme_constant_override("shadow_offset_y", 2)
	card_vbox.add_child(card_title)

	var card_depth := Label.new()
	card_depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_depth.text = "DEPTH: -9,999 M  •  ABYSSAL APEX"
	card_depth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_depth.add_theme_font_size_override("font_size", 13)
	card_depth.add_theme_color_override("font_color", Color(1.0, 0.55, 0.75, 0.90))
	card_vbox.add_child(card_depth)

	var card_sep := HSeparator.new()
	card_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_sep.custom_minimum_size = Vector2(180, 2)
	card_sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_vbox.add_child(card_sep)

	var card_prompt := Label.new()
	card_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_prompt.text = "CONFRONT THE VOID"
	card_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_prompt.add_theme_font_size_override("font_size", 13)
	card_prompt.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45, 0.95))
	card_vbox.add_child(card_prompt)

	# Reveal card tween
	get_tree().create_timer(3.8).timeout.connect(func():
		if not is_instance_valid(canvas):
			return
		_play_ui_sound(_wav_launch, -3.0, 0.85)
		var card_tw := canvas.create_tween().set_parallel(true)
		card_tw.tween_property(card_wrapper, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		card_tw.tween_property(card_wrapper, "scale", Vector2.ONE, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_suppress_level_click = false
	)

	# 7. Card Click: Rapid perspective zoom and transition into Level SP
	card_btn.pressed.connect(func():
		if _suppress_level_click:
			return
		_suppress_level_click = true
		card_btn.disabled = true
		_play_ui_sound(_wav_launch, 2.0, 0.65)

		var zoom_tw := canvas.create_tween().set_parallel(true)
		zoom_tw.tween_property(card_wrapper, "scale", Vector2(5.5, 5.5), 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		zoom_tw.tween_property(card_wrapper, "modulate:a", 0.0, 0.48).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		zoom_tw.tween_property(eye_view, "scale", Vector2(3.5, 3.5), 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		zoom_tw.tween_property(curtain, "color", Color.BLACK, 0.55)
		zoom_tw.tween_property(curtain, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if tension_player != null and is_instance_valid(tension_player):
			zoom_tw.tween_property(tension_player, "volume_db", -45.0, 0.50).set_trans(Tween.TRANS_QUAD)

		zoom_tw.chain().tween_callback(func():
			if tension_player != null and is_instance_valid(tension_player):
				tension_player.stop()
				tension_player.queue_free()
			canvas.queue_free()
			GameState.current_mode = GameState.GameMode.CHALLENGE
			GameState.start_game(20)
		)
	)


# --------------------------------------------------
# CINEMATIC PROCEDURAL VIEWS
# --------------------------------------------------

class CrimsonEyeView extends Control:
	var eye_open: float = 0.0
	var eye_glow: float = 1.0
	var pupil_dilation: float = 1.0
	var eye_alpha: float = 1.0
	var _pulse_time: float = 0.0

	func _process(delta: float) -> void:
		if eye_open > 0.02:
			_pulse_time += delta
			eye_glow = 1.0 + 0.16 * sin(_pulse_time * 2.4)
			pupil_dilation = 1.0 + 0.10 * cos(_pulse_time * 1.8)
			queue_redraw()

	func _draw() -> void:
		if eye_alpha <= 0.01:
			return

		var center := size * 0.5
		var w: float = 240.0
		var h: float = 110.0 * clampf(eye_open, 0.02, 1.0)

		# 1. Atmospheric radial crimson glow
		var glow_col := Color(0.95, 0.08, 0.18, 0.05 * eye_glow * eye_alpha)
		for i in range(6, 0, -1):
			var r: float = (w * 0.65) * (float(i) / 6.0)
			draw_circle(center, r * 1.4, Color(glow_col.r, glow_col.g, glow_col.b, glow_col.a * (1.2 / float(i))))

		# 2. Eye Sclera / contour
		var points_upper := PackedVector2Array()
		var points_lower := PackedVector2Array()
		var segments := 20
		var half_w := w * 0.5
		var max_h := h * 0.5

		for i in range(segments + 1):
			var t: float = float(i) / float(segments)
			var x: float = lerpf(-half_w, half_w, t)
			var arch: float = sin(t * PI)
			points_upper.append(center + Vector2(x, -max_h * arch))
			points_lower.append(center + Vector2(x, max_h * arch))

		var poly_points := PackedVector2Array()
		poly_points.append_array(points_upper)
		var lower_rev := points_lower.duplicate()
		lower_rev.reverse()
		poly_points.append_array(lower_rev)

		draw_colored_polygon(poly_points, Color(0.10, 0.008, 0.02, 0.96 * eye_alpha))

		var rim_col := Color(1.0, 0.22, 0.32, 0.90 * eye_alpha)
		for i in range(points_upper.size() - 1):
			draw_line(points_upper[i], points_upper[i + 1], rim_col, 2.5)
			draw_line(points_lower[i], points_lower[i + 1], rim_col, 2.5)

		# 3. Glowing Iris & Slit Pupil
		if eye_open > 0.08:
			var iris_r: float = 44.0 * eye_open
			draw_circle(center, iris_r, Color(0.95, 0.12, 0.20, 0.88 * eye_alpha))
			draw_circle(center, iris_r * 0.70, Color(1.0, 0.35, 0.30, 0.92 * eye_alpha))
			draw_arc(center, iris_r, 0.0, TAU, 32, Color(1.0, 0.72, 0.42, 0.85 * eye_alpha), 1.8)

			var pupil_w: float = 8.5 * pupil_dilation
			var pupil_h: float = 45.0 * eye_open
			var pupil_pts := PackedVector2Array([
				center + Vector2(0, -pupil_h),
				center + Vector2(pupil_w, 0),
				center + Vector2(0, pupil_h),
				center + Vector2(-pupil_w, 0)
			])
			draw_colored_polygon(pupil_pts, Color(0.01, 0.0, 0.0, 0.98 * eye_alpha))
			draw_line(center + Vector2(0, -pupil_h), center + Vector2(pupil_w, 0), Color(1.0, 0.6, 0.5, 0.7 * eye_alpha), 1.2)
			draw_line(center + Vector2(0, -pupil_h), center + Vector2(-pupil_w, 0), Color(1.0, 0.6, 0.5, 0.7 * eye_alpha), 1.2)


class AbyssalCorruptionCanvas extends Control:
	var intensity: float = 0.0
	var _anim_time: float = 0.0

	func _process(delta: float) -> void:
		if intensity > 0.01:
			_anim_time += delta
			queue_redraw()

	func _draw() -> void:
		if intensity <= 0.01:
			return
		var vp := size
		var pulse: float = 0.85 + 0.15 * sin(_anim_time * 2.2)
		var cur_int: float = intensity * pulse

		var v_thick: float = 140.0
		var h_thick: float = 100.0

		for i in range(10):
			var frac: float = float(i) / 10.0
			var band_a: float = (1.0 - frac) * 0.55 * cur_int
			var band_col := Color(0.18, 0.01, 0.04, band_a)
			draw_rect(Rect2(0, frac * v_thick, vp.x, v_thick / 10.0 + 1.0), band_col)
			draw_rect(Rect2(0, vp.y - (frac + 1.0 / 10.0) * v_thick, vp.x, v_thick / 10.0 + 1.0), band_col)
			draw_rect(Rect2(frac * h_thick, 0, h_thick / 10.0 + 1.0, vp.y), band_col)
			draw_rect(Rect2(vp.x - (frac + 1.0 / 10.0) * h_thick, 0, h_thick / 10.0 + 1.0, vp.y), band_col)

		var tendril_col := Color(0.78, 0.12, 0.24, 0.55 * cur_int)
		var tendril_dark := Color(0.24, 0.02, 0.05, 0.75 * cur_int)

		for k in range(5):
			var tx: float = vp.x * (0.15 + float(k) * 0.18) + sin(_anim_time + float(k)) * 6.0
			var tlen: float = (38.0 + sin(float(k) * 3.1) * 18.0) * cur_int
			draw_line(Vector2(tx, 0), Vector2(tx + 5.0, tlen * 0.6), tendril_dark, 2.8)
			draw_line(Vector2(tx + 5.0, tlen * 0.6), Vector2(tx + 10.0, tlen), tendril_col, 1.8)
			draw_line(Vector2(tx + 5.0, tlen * 0.6), Vector2(tx - 7.0, tlen * 0.8), tendril_col, 1.2)

		for k in range(5):
			var bx: float = vp.x * (0.12 + float(k) * 0.19) + cos(_anim_time + float(k)) * 6.0
			var blen: float = (42.0 + cos(float(k) * 2.7) * 20.0) * cur_int
			draw_line(Vector2(bx, vp.y), Vector2(bx - 5.0, vp.y - blen * 0.6), tendril_dark, 2.8)
			draw_line(Vector2(bx - 5.0, vp.y - blen * 0.6), Vector2(bx - 10.0, vp.y - blen), tendril_col, 1.8)
			draw_line(Vector2(bx - 5.0, vp.y - blen * 0.6), Vector2(bx + 6.0, vp.y - blen * 0.75), tendril_col, 1.2)

		for k in range(4):
			var ly: float = vp.y * (0.20 + float(k) * 0.20) + sin(_anim_time * 1.2 + float(k)) * 5.0
			var llen: float = (32.0 + sin(float(k) * 1.9) * 14.0) * cur_int
			draw_line(Vector2(0, ly), Vector2(llen * 0.6, ly + 3.0), tendril_dark, 2.6)
			draw_line(Vector2(llen * 0.6, ly + 3.0), Vector2(llen, ly + 6.0), tendril_col, 1.6)

			var ry: float = vp.y * (0.28 + float(k) * 0.20) + cos(_anim_time * 1.2 + float(k)) * 5.0
			var rlen: float = (32.0 + cos(float(k) * 2.3) * 14.0) * cur_int
			draw_line(Vector2(vp.x, ry), Vector2(vp.x - rlen * 0.6, ry - 3.0), tendril_dark, 2.6)
			draw_line(Vector2(vp.x - rlen * 0.6, ry - 3.0), Vector2(vp.x - rlen, ry - 6.0), tendril_col, 1.6)


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


func _input(event: InputEvent) -> void:
	if _is_mode_transitioning or _is_dragging_gauge:
		return
	if has_node("KingSectorConfirmModal") or has_node("ChallengeUnlockModal") or has_node("ResetConfirmModal"):
		return
	if scroll_container == null or not is_instance_valid(scroll_container) or not scroll_container.is_visible_in_tree():
		return

	var scroll_rect: Rect2 = scroll_container.get_global_rect()

	if event is InputEventScreenTouch:
		if event.pressed:
			if scroll_rect.has_point(event.position):
				_drag_touch_id = event.index
				_drag_start_pos = event.position
				_drag_last_pos = event.position
				_is_dragging_scroll = false
				_drag_velocity = 0.0
				_drag_last_time = Time.get_ticks_msec() / 1000.0
		elif not event.pressed and event.index == _drag_touch_id:
			_drag_touch_id = -1
			if _is_dragging_scroll:
				_is_dragging_scroll = false
				get_viewport().set_input_as_handled()
				var tw := create_tween()
				tw.tween_interval(0.12)
				tw.tween_callback(func(): _suppress_level_click = false)
			else:
				_suppress_level_click = false

	elif event is InputEventScreenDrag:
		if event.index == _drag_touch_id:
			var total_dy: float = absf(event.position.y - _drag_start_pos.y)
			var total_dx: float = absf(event.position.x - _drag_start_pos.x)
			if not _is_dragging_scroll:
				if total_dy > 8.0 or total_dx > 14.0:
					_is_dragging_scroll = true
					_suppress_level_click = true
					_reset_all_button_press_states()

			if _is_dragging_scroll:
				var dy: float = event.position.y - _drag_last_pos.y
				_apply_scroll_delta(dy)
				var now := Time.get_ticks_msec() / 1000.0
				var dt := now - _drag_last_time
				if dt > 0.001:
					_drag_velocity = -dy / dt
				_drag_last_time = now
				_drag_last_pos = event.position
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if scroll_rect.has_point(event.position):
				_drag_touch_id = -999
				_drag_start_pos = event.position
				_drag_last_pos = event.position
				_is_dragging_scroll = false
				_drag_velocity = 0.0
				_drag_last_time = Time.get_ticks_msec() / 1000.0
		elif not event.pressed and _drag_touch_id == -999:
			_drag_touch_id = -1
			if _is_dragging_scroll:
				_is_dragging_scroll = false
				get_viewport().set_input_as_handled()
				var tw := create_tween()
				tw.tween_interval(0.12)
				tw.tween_callback(func(): _suppress_level_click = false)
			else:
				_suppress_level_click = false

	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if _drag_touch_id == -999:
			var total_dy: float = absf(event.position.y - _drag_start_pos.y)
			var total_dx: float = absf(event.position.x - _drag_start_pos.x)
			if not _is_dragging_scroll:
				if total_dy > 8.0 or total_dx > 14.0:
					_is_dragging_scroll = true
					_suppress_level_click = true
					_reset_all_button_press_states()

			if _is_dragging_scroll:
				var dy: float = event.position.y - _drag_last_pos.y
				_apply_scroll_delta(dy)
				var now := Time.get_ticks_msec() / 1000.0
				var dt := now - _drag_last_time
				if dt > 0.001:
					_drag_velocity = -dy / dt
				_drag_last_time = now
				_drag_last_pos = event.position
				get_viewport().set_input_as_handled()


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

	# Smooth kinetic inertia scroll deceleration
	if not _is_dragging_scroll and absf(_drag_velocity) > 15.0:
		var vbar := scroll_container.get_v_scroll_bar()
		var page := vbar.page if vbar.page > 0.0 else scroll_container.size.y
		var max_scroll := maxf(0.0, vbar.max_value - page)
		var new_v := clampf(scroll_container.scroll_vertical + _drag_velocity * delta, 0.0, max_scroll)
		scroll_container.scroll_vertical = int(new_v)
		_drag_velocity = move_toward(_drag_velocity, 0.0, delta * 2400.0)
		_depth_tag_timer = 1.0
		if new_v <= 0.0 or new_v >= max_scroll:
			_drag_velocity = 0.0
	elif not _is_dragging_scroll:
		_drag_velocity = 0.0

	sonar_backdrop.queue_redraw()
	if level_grid != null and is_instance_valid(level_grid):
		level_grid.queue_redraw()
	if depth_gauge != null and is_instance_valid(depth_gauge):
		if _depth_tag_alpha > 0.001 or _is_dragging_gauge:
			depth_gauge.queue_redraw()
	if _abyss_arrow_canvas != null and is_instance_valid(_abyss_arrow_canvas):
		_abyss_arrow_canvas.queue_redraw()
	if _king_arrow_canvas != null and is_instance_valid(_king_arrow_canvas):
		_king_arrow_canvas.queue_redraw()

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
	var is_chal := (GameState.current_mode == GameState.GameMode.CHALLENGE)

	for spore in _spores:
		var pos: Vector2 = spore["pos"]
		if pos.x < -10.0 or pos.x > w + 10.0 or pos.y < -10.0 or pos.y > h + 10.0:
			continue
		var col: Color = Color(0.95, 0.45, 0.85, float(spore["alpha"])) if is_chal else Color(0.4, 0.85, 1.0, float(spore["alpha"]))
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
		var rip_col: Color = Color(0.95, 0.45, 0.85, alpha) if is_chal else Color(0.35, 0.85, 1.0, alpha)
		sonar_backdrop.draw_arc(
			center,
			radius,
			0.0,
			TAU,
			48,
			rip_col,
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


# --- Challenge Mode Unlock Celebration Modal ---------------------------------

func _show_challenge_unlock_celebration_modal() -> void:
	if GameState.current_mode != GameState.GameMode.STORY:
		GameState.current_mode = GameState.GameMode.STORY
		_update_header_and_mode_ui()
		_create_level_buttons()

	var modal_layer := Control.new()
	modal_layer.name = "ChallengeUnlockModal"
	ModalTemplate.apply_full_rect(modal_layer)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.z_index = 350
	add_child(modal_layer)

	var dimmer := ColorRect.new()
	ModalTemplate.apply_full_rect(dimmer)
	dimmer.color = ModalTemplate.DIMMER_COLOR
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dimmer)

	var center := CenterContainer.new()
	ModalTemplate.apply_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(ModalTemplate.ThemeKind.SONAR))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var pill := Label.new()
	pill.text = "◈   C H A L L E N G E   M O D E   U N L O C K E D   ◈"
	pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_theme_font_size_override("font_size", 12)
	pill.add_theme_color_override("font_color", Color(0.85, 0.72, 0.40, 0.90))
	vbox.add_child(pill)

	var title := Label.new()
	title.text = "CHALLENGE ABYSS UNLOCKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "THE DESCENT AWAITS  •  -4,500M  TO  -9,250M"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.40, 0.75, 0.95, 0.80))
	vbox.add_child(sub)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(240.0, 2.0)
	vbox.add_child(sep)

	var desc1 := Label.new()
	desc1.text = "◈ 20 Subterranean Abyss Sectors: Face absolute silence & apex blind predators\n◈ Abyssal Pacts: Balance grueling curses against powerful ancient boons\n◈ Global Leaderboard: Log total speedrun clear time on Huawei Game Service"
	desc1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc1.add_theme_font_size_override("font_size", 13)
	desc1.add_theme_color_override("font_color", Color(0.72, 0.84, 0.94, 0.85))
	vbox.add_child(desc1)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "ENTER THE ABYSS"
	btn.custom_minimum_size = Vector2(280.0, 48.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ModalTemplate.style_button(btn, true, ModalTemplate.ThemeKind.SONAR)
	vbox.add_child(btn)

	_wire_button_Juice(btn)

	_play_ui_sound(_wav_launch, -3.0, 1.0)

	btn.pressed.connect(func():
		_play_ui_sound(_wav_click, -2.0, 1.1)
		var tw := modal_layer.create_tween()
		tw.tween_property(modal_layer, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func():
			modal_layer.queue_free()
			_descend_to_challenge_mode()
		)
	)
