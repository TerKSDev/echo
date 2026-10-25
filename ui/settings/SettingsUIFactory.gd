class_name SettingsUIFactory
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
	hbox.add_theme_constant_override("separation", 8)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = Color(0.35, 0.85, 1.0, 0.95)
	hbox.add_child(bar)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.48, 0.84, 1.0, 0.95))
	lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(lbl)
	return hbox


static func create_category_divider() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 1)
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.color = Color(0.18, 0.35, 0.52, 0.25)
	c.add_child(line)
	return c


static func create_setting_row(title_text: String, desc_text: String, action_control: Control) -> Control:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88, 0.75))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_lbl)

	hbox.add_child(vbox)

	if action_control != null:
		action_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(action_control)

	return hbox


static func create_slider_row(
	title_text: String,
	desc_text: String,
	cur_val: float,
	is_percent: bool,
	on_val_changed: Callable
) -> Control:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88, 0.75))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_lbl)

	hbox.add_child(vbox)

	var right_box := HBoxContainer.new()
	right_box.custom_minimum_size = Vector2(210, 32)
	right_box.add_theme_constant_override("separation", 10)
	right_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = cur_val
	slider.custom_minimum_size = Vector2(150, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	right_box.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(45, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.48, 0.84, 1.0, 0.95))
	if is_percent:
		val_lbl.text = "%d%%" % int(cur_val * 100.0)
	else:
		val_lbl.text = "%.2f" % cur_val
	right_box.add_child(val_lbl)

	slider.value_changed.connect(func(v: float):
		if is_percent:
			val_lbl.text = "%d%%" % int(v * 100.0)
		else:
			val_lbl.text = "%.2f" % v
		if on_val_changed.is_valid():
			on_val_changed.call(v)
	)

	hbox.add_child(right_box)
	return hbox


static func refresh_toggle_btn(btn: Button, active: bool, on_text: String, off_text: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0

	if active:
		sb.bg_color = Color(0.06, 0.22, 0.38, 0.85)
		sb.border_color = Color(0.35, 0.85, 1.0, 0.85)
		sb.set_border_width_all(1)
		btn.text = on_text
		btn.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	else:
		sb.bg_color = Color(0.03, 0.08, 0.14, 0.80)
		sb.border_color = Color(0.22, 0.38, 0.52, 0.50)
		sb.set_border_width_all(1)
		btn.text = off_text
		btn.add_theme_color_override("font_color", Color(0.45, 0.60, 0.75))

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_font_size_override("font_size", 12)


static func style_action_button(btn: Button, border_col: Color, bg_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)


static func style_disabled_button(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.bg_color = Color(0.04, 0.08, 0.12, 0.5)
	sb.border_color = Color(0.2, 0.3, 0.4, 0.3)
	sb.set_border_width_all(1)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.45, 0.55, 0.6))
