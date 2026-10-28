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
	modal.z_index = 110
	ModalTemplate.apply_full_rect(modal)

	var dimmer := ColorRect.new()
	dimmer.color = ModalTemplate.DIMMER_COLOR
	ModalTemplate.apply_full_rect(dimmer)
	modal.add_child(dimmer)

	var center := CenterContainer.new()
	ModalTemplate.apply_full_rect(center)
	modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", ModalTemplate.make_card_style(ModalTemplate.ThemeKind.CRIMSON))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var close_func := func():
		var tw := modal.create_tween().set_parallel(true)
		tw.tween_property(modal, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(panel, "scale", Vector2(0.92, 0.92), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			modal.queue_free()
			if on_cancelled.is_valid():
				on_cancelled.call()
		)

	# Header: Title + Close Button
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "RETURN TO ABYSS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.40, 1.0))
	header.add_child(title)

	var close_btn := ModalTemplate.make_close_button(close_func, ModalTemplate.ThemeKind.CRIMSON)
	header.add_child(close_btn)

	# Divider line
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.85, 0.25, 0.35, 0.35)
	vbox.add_child(div)

	var desc := Label.new()
	desc.text = "WARNING: This action is completely IRREVERSIBLE.\n\nStory Mode's 20 star-bearing sectors (Sectors 01–20) will be reset back to Sector 01. Challenge Mode access, high scores, and the tutorial remain unlocked."
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
	ModalTemplate.style_button(cancel_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	cancel_btn.pressed.connect(close_func)
	if wire_juice_cb.is_valid():
		wire_juice_cb.call(cancel_btn)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "CONFIRM: RETURN TO ABYSS"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.custom_minimum_size = Vector2(0, 42)
	confirm_btn.add_theme_font_size_override("font_size", 13)
	ModalTemplate.style_danger_button(confirm_btn, true, false)
	confirm_btn.pressed.connect(func():
		if play_sound_cb.is_valid():
			play_sound_cb.call()
		GameState.reset_progress()
		close_func.call()
		if on_confirmed.is_valid():
			on_confirmed.call()
	)
	if wire_juice_cb.is_valid():
		wire_juice_cb.call(confirm_btn)
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)

	# ESC key support
	modal.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			close_func.call()
	)

	# Enter animation
	modal.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = Vector2(ModalTemplate.CARD_WIDTH * 0.5, 150.0)
	var tw := modal.create_tween().set_parallel(true)
	tw.tween_property(modal, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	parent.add_child(modal)
	return modal
