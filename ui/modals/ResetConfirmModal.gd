class_name ChallengeResetModal
extends RefCounted
## Confirmation Modal for Abandoning / Resetting a Roguelite Challenge Run in ECHO.
## Enforces anti-misclick protection before wiping active boons, curses, and progress.


static func open(parent: Node, on_confirmed: Callable) -> Control:
	if parent == null or not is_instance_valid(parent):
		return null

	var canvas := CanvasLayer.new()
	canvas.layer = 130
	canvas.name = "ResetConfirmCanvas"
	parent.add_child(canvas)

	var root := Control.new()
	root.name = "ResetConfirmModalRoot"
	ModalTemplate.apply_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(root)

	# 1. Dimmer Background
	var dimmer := ColorRect.new()
	ModalTemplate.apply_full_rect(dimmer)
	dimmer.color = Color(0.015, 0.008, 0.02, 0.88)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	# 2. Centered Card
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

	# Header: Title & Close
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text = "ABANDON EXPEDITION"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
	header.add_child(title_lbl)

	var close_func := func():
		var close_tw := root.create_tween().set_parallel(true)
		close_tw.tween_property(root, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.tween_property(frame, "scale", Vector2(0.94, 0.94), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.chain().tween_callback(func():
			canvas.queue_free()
		)

	var close_btn := ModalTemplate.make_close_button(close_func, ModalTemplate.ThemeKind.CRIMSON)
	header.add_child(close_btn)

	# Divider line
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(0.85, 0.25, 0.35, 0.35)
	vbox.add_child(divider)

	# Message body
	var msg_lbl := Label.new()
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.92, 0.82, 0.86, 0.95))
	msg_lbl.text = "Are you sure you want to abandon the current abyss run?\n\nAll acquired Abyssal Pacts (curses and boons) will be dissipated, and expedition progress will reset to Sector 01."
	vbox.add_child(msg_lbl)

	# Button actions row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	# Cancel Button (Safe)
	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(110, 42)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(cancel_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	cancel_btn.pressed.connect(close_func)
	btn_row.add_child(cancel_btn)

	# Confirm Abandon Button (Danger)
	var confirm_btn := Button.new()
	confirm_btn.text = "ABANDON RUN"
	confirm_btn.custom_minimum_size = Vector2(160, 42)
	confirm_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_danger_button(confirm_btn, true, false)
	confirm_btn.pressed.connect(func():
		close_func.call()
		if on_confirmed.is_valid():
			on_confirmed.call()
	)
	btn_row.add_child(confirm_btn)

	# Micro juice on hover
	for b: Button in [cancel_btn, confirm_btn]:
		b.mouse_entered.connect(func():
			b.pivot_offset = b.size * 0.5
			b.create_tween().tween_property(b, "scale", Vector2(1.03, 1.03), 0.08)
		)
		b.mouse_exited.connect(func():
			b.pivot_offset = b.size * 0.5
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08)
		)

	# Keyboard ESC support
	root.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			close_func.call()
	)

	# Pop-in animation
	root.modulate.a = 0.0
	frame.scale = Vector2(0.92, 0.92)
	frame.pivot_offset = Vector2(260.0, 140.0)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	return root
