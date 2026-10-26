class_name ResetConfirmModal
extends RefCounted
## Irreversible Data Reset Confirmation Modal Dialog.
## Warns user before wiping cavern sector progress, records, and stars.

const SettingsUIFactory = preload("res://ui/settings/SettingsUIFactory.gd")

static func show_modal(
	parent: Control,
	on_confirmed: Callable,
	on_cancelled: Callable,
	play_sound_cb: Callable,
	wire_juice_cb: Callable
) -> Control:
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.02, 0.05, 0.85)
	modal.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 26.0
	card_style.content_margin_top = 24.0
	card_style.content_margin_right = 26.0
	card_style.content_margin_bottom = 26.0
	card_style.bg_color = Color(0.09, 0.02, 0.04, 0.98)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.95, 0.28, 0.35, 0.95)
	card_style.set_corner_radius_all(14)
	card_style.shadow_color = Color(0.8, 0.1, 0.2, 0.25)
	card_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "RETURN TO ABYSS?"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.40, 1.0))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "WARNING: This action is completely IRREVERSIBLE.\n\nAll unlocked sector progression, speedrun records, and collected stars will be permanently erased. You will be placed back at Sector 01 (Abyss Origin)."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.95, 0.82, 0.85, 0.95))
	vbox.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.custom_minimum_size = Vector2(0, 42)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	SettingsUIFactory.style_action_button(cancel_btn, Color(0.3, 0.5, 0.7, 0.7), Color(0.05, 0.12, 0.2, 0.9))
	cancel_btn.pressed.connect(func():
		modal.queue_free()
		if on_cancelled.is_valid():
			on_cancelled.call()
	)
	if wire_juice_cb.is_valid():
		wire_juice_cb.call(cancel_btn)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "CONFIRM: RETURN TO ABYSS"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.custom_minimum_size = Vector2(0, 42)
	confirm_btn.add_theme_font_size_override("font_size", 13)
	SettingsUIFactory.style_action_button(confirm_btn, Color(0.95, 0.3, 0.35, 1.0), Color(0.28, 0.05, 0.08, 0.95))
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.8, 1.0))
	confirm_btn.pressed.connect(func():
		if play_sound_cb.is_valid():
			play_sound_cb.call()
		GameState.reset_progress()
		modal.queue_free()
		if on_confirmed.is_valid():
			on_confirmed.call()
	)
	if wire_juice_cb.is_valid():
		wire_juice_cb.call(confirm_btn)
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)
	parent.add_child(modal)
	return modal
