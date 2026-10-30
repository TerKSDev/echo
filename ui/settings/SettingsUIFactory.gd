class_name SettingsUIFactory
extends RefCounted
## UI Component Factory for ECHO Settings System.
## Procedurally constructs responsive sliders, toggle chips, section headers,
## category dividers, and action buttons.

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


static func create_section_header(title: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = Color(0.35, 0.85, 1.0, 0.95)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(bar)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.48, 0.84, 1.0, 0.95))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox


static func create_section_card(header_title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.016, 0.042, 0.075, 0.88)
	style.border_color = Color(0.20, 0.42, 0.65, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 18.0
	style.shadow_color = Color(0.02, 0.08, 0.16, 0.20)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	if not header_title.is_empty():
		vbox.add_child(create_section_header(header_title))
		vbox.add_child(create_category_divider())

	return {
		"card": panel,
		"content": vbox
	}


static func create_category_divider() -> Control:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.color = Color(0.24, 0.48, 0.72, 0.40)
	return line


static func create_setting_row(title_text: String, desc_text: String, action_control: Control) -> Control:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.text = title_text
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88, 0.75))
	desc_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc_lbl)

	hbox.add_child(vbox)

	if action_control != null:
		if action_control.custom_minimum_size.y < 38.0:
			action_control.custom_minimum_size.y = 38.0
		action_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(action_control)

	return hbox


static func create_slider_row(
	title_text: String,
	desc_text: String,
	cur_val: float,
	is_percent: bool,
	on_val_changed: Callable,
	min_val: float = 0.0,
	max_val: float = 1.0,
	step_val: float = 0.05
) -> Control:
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# Header: Title on Left, Value Indicator on Right
	var hdr := HBoxContainer.new()
	hdr.mouse_filter = Control.MOUSE_FILTER_PASS
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.text = title_text
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 14)
	hdr.add_child(title_lbl)

	var val_lbl := Label.new()
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 0.95))
	if is_percent:
		val_lbl.text = "%d%%" % int(round(cur_val * 100.0))
	else:
		val_lbl.text = "%.2f" % cur_val
	hdr.add_child(val_lbl)
	vbox.add_child(hdr)

	# Optional Description Subtitle
	if not desc_text.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.text = desc_text
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.52, 0.70, 0.86, 0.75))
		desc_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(desc_lbl)

	# Slider Row: Full-width glowing HSlider matching Pause Modal
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = cur_val
	slider.custom_minimum_size = Vector2(0, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_slider(slider, ModalTemplate.ThemeKind.SONAR)
	vbox.add_child(slider)

	slider.value_changed.connect(func(v: float):
		if is_percent:
			val_lbl.text = "%d%%" % int(round(v * 100.0))
		else:
			val_lbl.text = "%.2f" % v
		if on_val_changed.is_valid():
			on_val_changed.call(v)
	)

	vbox.set_meta("slider", slider)
	vbox.set_meta("val_lbl", val_lbl)
	vbox.set_meta("title_lbl", title_lbl)
	vbox.set_meta("is_percent", is_percent)

	return vbox


static func set_slider_row_enabled(row: Control, enabled: bool) -> void:
	if row == null or not is_instance_valid(row):
		return
	var slider: HSlider = row.get_meta("slider", null)
	if slider != null and is_instance_valid(slider):
		slider.editable = enabled
		slider.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 1.0 if enabled else 0.38
	row.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE


static func refresh_toggle_btn(btn: Button, active: bool, on_text: String, off_text: String) -> void:
	if btn != null and is_instance_valid(btn):
		if btn.custom_minimum_size.y < 38.0:
			btn.custom_minimum_size.y = 38.0
	ModalTemplate.style_toggle_button(btn, active, on_text, off_text, ModalTemplate.ThemeKind.SONAR)


static func style_action_button(btn: Button, border_col: Color, bg_col: Color, is_pill: bool = false) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if btn.custom_minimum_size.y < 38.0:
		btn.custom_minimum_size.y = 38.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var rad := 14 if is_pill else 10
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(rad)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)

	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = bg_col.lightened(0.12)
	hov.border_color = border_col.lightened(0.20)

	var prs := sb.duplicate() as StyleBoxFlat
	prs.bg_color = bg_col.darkened(0.15)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", prs)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


static func style_danger_button(btn: Button, is_primary: bool = false, is_pill: bool = false) -> void:
	ModalTemplate.style_danger_button(btn, is_primary, is_pill)


static func style_disabled_button(btn: Button, is_pill: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	var rad := 14 if is_pill else 10
	sb.set_corner_radius_all(rad)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.bg_color = Color(0.04, 0.08, 0.12, 0.5)
	sb.border_color = Color(0.2, 0.3, 0.4, 0.3)
	sb.set_border_width_all(1)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.45, 0.55, 0.6))
	btn.add_theme_font_size_override("font_size", 12)
