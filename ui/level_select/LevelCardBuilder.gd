class_name LevelCardBuilder
extends RefCounted
## Modular Sector Button Card Builder for Level Select.
## Constructs high-contrast glassmorphic level cards, star indicators,
## telemetry subtitles, procedural radar scanlines, and tactile haptic feedback.

const Icons = preload("res://ui/icons/Icons.gd")


static func make_button_style(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1,
	corner_radius: int = 12,
	shadow_color: Color = Color(0, 0, 0, 0),
	shadow_size: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	if shadow_size > 0:
		style.shadow_color = shadow_color
		style.shadow_size = shadow_size
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func draw_card_decorations(canvas: Control, is_active: bool, is_cleared: bool, time: float) -> void:
	var w := canvas.size.x
	var h := canvas.size.y

	# 1. Left neon accent bar (safely inset at x = 3.5 so it never bleeds or clips)
	if is_active:
		var bar_pulse := 0.85 + 0.15 * sin(time * 4.0)
		canvas.draw_rect(Rect2(3.5, 12.0, 4.0, h - 24.0), Color(0.2, 0.65, 1.0, 0.35 * bar_pulse), true)
		canvas.draw_rect(Rect2(3.5, 12.0, 2.8, h - 24.0), Color(0.4, 0.95, 1.0, 0.98 * bar_pulse), true)
	elif is_cleared:
		canvas.draw_rect(Rect2(3.5, 14.0, 2.6, h - 28.0), Color(0.32, 0.88, 0.62, 0.85), true)
	else:
		# Muted dark slate indicator notch
		canvas.draw_rect(Rect2(3.5, 16.0, 2.0, h - 32.0), Color(0.24, 0.40, 0.58, 0.75), true)

		# 1. Subtle diagonal interference grid (Fog of War barrier)
		var step := 20.0
		var num_lines := int(floor(w / step)) + 3
		for idx in range(-1, num_lines):
			var x_start := float(idx) * step
			var p_a := Vector2(x_start, 4.0)
			var p_b := Vector2(x_start + 16.0, h - 4.0)
			if p_a.x < w and p_b.x > 0:
				canvas.draw_line(p_a, p_b, Color(0.16, 0.28, 0.42, 0.20), 1.0)




static func play_locked_feedback(
	btn: Button,
	sub_lbl: Label,
	original_text: String,
	play_sound: Callable,
	wav_error: AudioStreamWAV
) -> void:
	if play_sound.is_valid() and wav_error != null:
		play_sound.call(wav_error, -4.0, randf_range(0.96, 1.04))

	# Mobile haptic feedback on rejection
	if OS.has_feature("mobile") or OS.get_name() == "Android":
		Input.vibrate_handheld(35)

	# Haptic micro-shake animation
	var orig_pos := btn.position
	var tw := btn.create_tween()
	tw.tween_property(btn, "position:x", orig_pos.x - 5.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x + 5.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x - 3.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x + 3.0, 0.04)
	tw.tween_property(btn, "position:x", orig_pos.x, 0.04)

	# Transient acoustic warning flash on subtitle
	if is_instance_valid(sub_lbl):
		sub_lbl.text = "Sensor Block"
		sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 0.95))

		var reset_tw := btn.create_tween()
		reset_tw.tween_interval(1.4)
		reset_tw.tween_callback(func():
			if is_instance_valid(sub_lbl):
				sub_lbl.text = original_text
				sub_lbl.add_theme_color_override("font_color", Color(0.32, 0.42, 0.52, 0.7))
		)


static func build_level_card(
	level_number: int,
	time_provider: Callable,
	on_select: Callable,
	wire_juice: Callable,
	play_sound: Callable,
	wav_error: AudioStreamWAV,
	level_path: String = ""
) -> Button:
	var button := Button.new()
	var highest: int = GameState.highest_unlocked_level
	var stars: int = GameState.get_level_stars(level_number)
	var is_unlocked: bool = level_number <= highest
	var is_cleared: bool = stars > 0 or level_number < highest
	var is_active: bool = is_unlocked and not is_cleared

	button.custom_minimum_size = Vector2(290, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = false

	var sector_name := "CAVERN SECTOR %02d" % level_number
	var raw_depth := "-%d M" % (level_number * 160)
	var is_king_sector := false

	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		if level_path.ends_with("level_SP.tscn") or level_number == 21:
			is_king_sector = true
			sector_name = "THE FINAL ECHO"
			raw_depth = "-9,999 M"
		elif level_path != "":
			var filename := level_path.get_file().get_basename()
			var num := int(filename.replace("level_", ""))
			var c_idx := num - 1
			if c_idx >= 0 and c_idx < GameState.CHALLENGE_SECTORS.size():
				sector_name = GameState.CHALLENGE_SECTORS[c_idx]["name"]
				raw_depth = GameState.CHALLENGE_SECTORS[c_idx]["depth"]
		else:
			var c_idx := level_number - 1
			if c_idx >= 0 and c_idx < GameState.CHALLENGE_SECTORS.size():
				sector_name = GameState.CHALLENGE_SECTORS[c_idx]["name"]
				raw_depth = GameState.CHALLENGE_SECTORS[c_idx]["depth"]
	else:
		# Story Mode
		if level_path.ends_with("level_0.tscn") or (level_number == 1 and level_path == ""):
			sector_name = "FIRST STEPS"
			raw_depth = "TRAINING"
		elif level_path != "":
			var filename := level_path.get_file().get_basename()
			if filename.begins_with("level_"):
				var num := int(filename.replace("level_", ""))
				var sec_idx := num - 1
				if sec_idx >= 0 and sec_idx < GameState.STORY_SECTORS.size():
					sector_name = GameState.STORY_SECTORS[sec_idx]["name"]
					raw_depth = GameState.STORY_SECTORS[sec_idx]["depth"]
				else:
					sector_name = "SECTOR %02d" % num
		elif (level_number - 1) >= 0 and (level_number - 1) < GameState.STORY_SECTORS.size():
			sector_name = GameState.STORY_SECTORS[level_number - 1]["name"]
			raw_depth = GameState.STORY_SECTORS[level_number - 1]["depth"]

	# Format depth string without extra clutter
	var depth_str := raw_depth
	if raw_depth.ends_with("M"):
		depth_str = "~" + raw_depth.replace("-", "").strip_edges()

	var display_title: String = sector_name
	var display_subtitle: String = depth_str

	if not is_unlocked:
		# Conceal locked level names and depths for unprobed sectors
		if is_king_sector:
			display_title = "👑 KING SECTOR"
			display_subtitle = "---"
		else:
			display_title = "???"
			display_subtitle = "---"

	# Style the card frame
	if is_king_sector:
		# Regal crimson/gold boss styling for Level SP
		var k_norm := make_button_style(
			Color(0.14, 0.02, 0.05, 0.98),
			Color(1.0, 0.80, 0.28, 0.98),
			2, 14,
			Color(0.9, 0.15, 0.20, 0.55), 10
		)
		var k_hov := make_button_style(
			Color(0.20, 0.03, 0.07, 0.98),
			Color(1.0, 0.92, 0.50, 1.0),
			2, 14,
			Color(1.0, 0.25, 0.30, 0.75), 14
		)
		button.add_theme_stylebox_override("normal", k_norm)
		button.add_theme_stylebox_override("hover", k_hov)
		button.add_theme_stylebox_override("pressed", k_norm)
		button.add_theme_stylebox_override("focus", k_norm)
	elif is_active:
		var norm := make_button_style(
			Color(0.035, 0.11, 0.20, 0.95),
			Color(0.35, 0.88, 1.0, 0.95),
			2, 12,
			Color(0.08, 0.52, 0.95, 0.35), 8
		)
		var hov := make_button_style(
			Color(0.05, 0.16, 0.28, 0.98),
			Color(0.55, 0.95, 1.0, 1.0),
			2, 12,
			Color(0.15, 0.65, 1.0, 0.55), 12
		)
		var prs := make_button_style(
			Color(0.08, 0.22, 0.36, 1.0),
			Color(0.75, 1.0, 1.0, 1.0),
			2, 12,
			Color(0.25, 0.85, 1.0, 0.65), 14
		)
		button.add_theme_stylebox_override("normal", norm)
		button.add_theme_stylebox_override("hover", hov)
		button.add_theme_stylebox_override("pressed", prs)
		button.add_theme_stylebox_override("focus", norm)
	elif is_cleared:
		var norm := make_button_style(
			Color(0.024, 0.065, 0.11, 0.92),
			Color(0.18, 0.52, 0.58, 0.75),
			1, 12
		)
		var hov := make_button_style(
			Color(0.04, 0.12, 0.19, 0.96),
			Color(0.32, 0.78, 0.82, 0.95),
			2, 12
		)
		var prs := make_button_style(
			Color(0.06, 0.16, 0.25, 1.0),
			Color(0.45, 0.88, 0.95, 1.0),
			2, 12
		)
		button.add_theme_stylebox_override("normal", norm)
		button.add_theme_stylebox_override("hover", hov)
		button.add_theme_stylebox_override("pressed", prs)
		button.add_theme_stylebox_override("focus", norm)
	else:
		# Locked level: deep solid dark abyss styling with high contrast borders
		var locked_box := make_button_style(
			Color(0.018, 0.042, 0.075, 0.96),
			Color(0.18, 0.30, 0.44, 0.85),
			1, 12
		)
		var locked_hov := make_button_style(
			Color(0.028, 0.062, 0.105, 0.98),
			Color(0.28, 0.46, 0.66, 0.95),
			1, 12
		)
		button.add_theme_stylebox_override("normal", locked_box)
		button.add_theme_stylebox_override("hover", locked_hov)
		button.add_theme_stylebox_override("pressed", locked_box)
		button.add_theme_stylebox_override("focus", locked_box)

	# Connect procedural drawing for tactical decorations
	button.draw.connect(func():
		var t: float = time_provider.call() if time_provider.is_valid() else 0.0
		draw_card_decorations(button, is_active, is_cleared, t)
	)

	# Margin container inside the card
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	button.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# --- Row 1: Sector Name & Status Badge ---
	var row1 := HBoxContainer.new()
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_theme_constant_override("separation", 8)
	vbox.add_child(row1)

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.text = ("👑 " + display_title) if is_king_sector else display_title
	if is_king_sector:
		title_lbl.add_theme_font_size_override("font_size", 18)
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		title_lbl.add_theme_color_override("font_shadow_color", Color(0.75, 0.12, 0.20, 0.95))
		title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	elif is_active:
		title_lbl.add_theme_font_size_override("font_size", 18)
		title_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		title_lbl.add_theme_color_override("font_shadow_color", Color(0.05, 0.48, 0.95, 0.9))
		title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	elif is_cleared:
		title_lbl.add_theme_font_size_override("font_size", 17)
		title_lbl.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0))
	else:
		title_lbl.add_theme_font_size_override("font_size", 16)
		title_lbl.add_theme_color_override("font_color", Color(0.65, 0.78, 0.90, 0.92))
	row1.add_child(title_lbl)

	# Status chip: READY / BOSS for active sector, LOCKED for locked sectors
	if is_active:
		var status_box := HBoxContainer.new()
		status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_box.add_theme_constant_override("separation", 6)
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row1.add_child(status_box)

		var icon_canvas := Control.new()
		icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_canvas.custom_minimum_size = Vector2(14, 14)
		if is_king_sector:
			icon_canvas.draw.connect(func(): Icons.draw_trophy(icon_canvas))
		else:
			icon_canvas.draw.connect(func(): Icons.draw_beacon(icon_canvas))
		status_box.add_child(icon_canvas)

		var status_chip := Label.new()
		status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_chip.add_theme_font_size_override("font_size", 13)
		status_chip.text = "BOSS" if is_king_sector else "READY"
		status_chip.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if is_king_sector else Color(0.35, 0.95, 1.0))
		status_box.add_child(status_chip)
	elif not is_unlocked:
		var status_box := HBoxContainer.new()
		status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_box.add_theme_constant_override("separation", 6)
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row1.add_child(status_box)

		var icon_canvas := Control.new()
		icon_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_canvas.custom_minimum_size = Vector2(13, 15)
		icon_canvas.draw.connect(func(): Icons.draw_lock(icon_canvas))
		status_box.add_child(icon_canvas)

		var status_chip := Label.new()
		status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_chip.add_theme_font_size_override("font_size", 13)
		status_chip.text = "KING" if is_king_sector else "LOCKED"
		status_chip.add_theme_color_override("font_color", Color(0.95, 0.55, 0.65) if is_king_sector else Color(0.55, 0.68, 0.82, 0.90))
		status_box.add_child(status_chip)

	# --- Row 2: Depth Subtitle + Stars/Time ---
	var row2 := HBoxContainer.new()
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row2)

	var sub_lbl := Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.clip_text = true
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.text = display_subtitle
	if is_active:
		sub_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0, 0.98))
	elif is_cleared:
		sub_lbl.add_theme_color_override("font_color", Color(0.45, 0.82, 0.92, 0.90))
	else:
		sub_lbl.add_theme_color_override("font_color", Color(0.46, 0.58, 0.72, 0.88))
	row2.add_child(sub_lbl)

	# Display earned stars and best time on cleared levels
	if is_unlocked and stars > 0:
		var best_time: float = GameState.get_level_best_time(level_number)
		var is_ghost: bool = GameState.is_level_ghost_cleared(level_number)

		var star_box := HBoxContainer.new()
		star_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_box.add_theme_constant_override("separation", 6)
		star_box.alignment = BoxContainer.ALIGNMENT_END
		star_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var s1 := "★" if stars >= 1 else "☆"
		var s2 := "★" if is_ghost else ("★" if stars >= 2 else "☆")
		var s3 := "★" if stars >= 3 else "☆"

		var star_lbl := Label.new()
		star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star_lbl.text = "%s%s%s" % [s1, s2, s3]
		star_lbl.add_theme_font_size_override("font_size", 14)
		star_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28))
		star_box.add_child(star_lbl)

		if best_time > 0.0 and best_time < 900.0:
			var m := floori(best_time / 60.0)
			var s := int(best_time) % 60
			var time_lbl := Label.new()
			time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			time_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			time_lbl.text = "%02d:%02d" % [m, s]
			time_lbl.add_theme_font_size_override("font_size", 13)
			time_lbl.add_theme_color_override("font_color", Color(0.68, 0.84, 0.95, 0.90))
			star_box.add_child(time_lbl)

		row2.add_child(star_box)
	elif is_unlocked and is_cleared:
		var clear_lbl := Label.new()
		clear_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clear_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		clear_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		clear_lbl.text = "CLEARED"
		clear_lbl.add_theme_font_size_override("font_size", 12)
		clear_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.7, 0.9))
		row2.add_child(clear_lbl)

	if is_unlocked:
		button.pressed.connect(func(): on_select.call(level_number))
		if wire_juice.is_valid():
			wire_juice.call(button)
	else:
		button.pressed.connect(func():
			play_locked_feedback(button, sub_lbl, display_subtitle, play_sound, wav_error)
		)

	return button
