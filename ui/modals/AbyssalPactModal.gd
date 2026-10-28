class_name AbyssalPactModal
extends RefCounted
## Roguelite Abyssal Pact Modal for ECHO Challenge Mode.
## Triggered at milestones (Level 1, 5, 10, 15, 20).
## Presents 1 Curse (Debuff) + 1 Boon (Buff), granting 1 Reroll chance (either curse OR boon).
## Adheres strictly to ModalTemplate standard CARD_WIDTH (592px) and Singularity theme.


static func _get_sfx(node: Node) -> SfxManager:
	if node == null or not is_instance_valid(node):
		return null
	var tree := node.get_tree()
	if tree != null and tree.current_scene != null:
		var s := tree.current_scene.get_node_or_null("SfxManager") as SfxManager
		if s != null:
			return s
	return null


static func open_pact(parent: Node, milestone_lvl: int, on_accepted: Callable) -> Control:
	if parent == null or not is_instance_valid(parent):
		if on_accepted.is_valid():
			on_accepted.call()
		return null

	var sfx := _get_sfx(parent)
	if sfx != null:
		sfx.play_pact_reveal()

	var candidates: Dictionary = ChallengeModifiers.generate_pact_candidates(milestone_lvl)
	var pact_state := {
		"curse": candidates["curse"],
		"boon": candidates["boon"],
		"reroll_used": ChallengeModifiers.reroll_used_milestones.get(milestone_lvl, false)
	}

	var milestone_idx := 1
	var m_idx_find := ChallengeModifiers.MILESTONES.find(milestone_lvl)
	if m_idx_find >= 0:
		milestone_idx = m_idx_find + 1

	var canvas := CanvasLayer.new()
	canvas.layer = 130
	canvas.name = "AbyssalPactCanvas"
	parent.add_child(canvas)

	var root := Control.new()
	root.name = "AbyssalPactModalRoot"
	ModalTemplate.apply_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(root)

	# 1. Dimmer Background
	var dimmer := ColorRect.new()
	ModalTemplate.apply_full_rect(dimmer)
	dimmer.color = Color(0.015, 0.008, 0.024, 0.94)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	# 2. Centered Container & Frame (Strict ModalTemplate.CARD_WIDTH = 592px)
	var center := CenterContainer.new()
	ModalTemplate.apply_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 0)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.025, 0.010, 0.038, 0.98)
	card_sb.border_color = Color(1.0, 0.42, 0.88, 0.90)
	card_sb.set_border_width_all(ModalTemplate.BORDER_WIDTH)
	card_sb.set_corner_radius_all(ModalTemplate.CORNER_RADIUS)
	card_sb.content_margin_left = 22.0
	card_sb.content_margin_right = 22.0
	card_sb.content_margin_top = 22.0
	card_sb.content_margin_bottom = 22.0
	card_sb.shadow_size = 22
	card_sb.shadow_color = Color(0.70, 0.08, 0.48, 0.40)
	frame.add_theme_stylebox_override("panel", card_sb)
	center.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	frame.add_child(vbox)

	# ==========================================
	# HEADER SECTION (Generous breathing room)
	# ==========================================
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 6)
	header_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_vbox)

	var tag_holder := CenterContainer.new()
	header_vbox.add_child(tag_holder)

	var tag_panel := PanelContainer.new()
	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = Color(0.25, 0.04, 0.20, 0.70)
	tag_sb.border_color = Color(1.0, 0.45, 0.88, 0.80)
	tag_sb.set_border_width_all(1)
	tag_sb.set_corner_radius_all(10)
	tag_sb.content_margin_left = 14.0
	tag_sb.content_margin_right = 14.0
	tag_sb.content_margin_top = 3.0
	tag_sb.content_margin_bottom = 3.0
	tag_panel.add_theme_stylebox_override("panel", tag_sb)
	tag_holder.add_child(tag_panel)

	var tag_lbl := Label.new()
	tag_lbl.text = "◈   EXPEDITION PACT   •   TIER %02d / 05   ◈" % milestone_idx
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.92))
	tag_panel.add_child(tag_lbl)

	var title_lbl := Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.text = "THE ABYSSAL PACT"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.98))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.85, 0.15, 0.65, 0.90))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	header_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.text = "Accept a deepening curse to assimilate forbidden abyssal technology."
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.82, 0.72, 0.88, 0.85))
	header_vbox.add_child(sub_lbl)

	# ==========================================
	# CARDS CONTAINER (Left Curse, Right Boon)
	# ==========================================
	var cards_hbox := HBoxContainer.new()
	cards_hbox.add_theme_constant_override("separation", 14)
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cards_hbox)

	var curse_card_ref := { "panel": null, "title": null, "sub": null, "desc": null, "btn": null }
	var boon_card_ref := { "panel": null, "title": null, "sub": null, "desc": null, "btn": null }

	# ------------------------------------------
	# 1. Left Card: Abyssal Curse (Debuff)
	# ------------------------------------------
	var curse_panel := PanelContainer.new()
	curse_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curse_panel.custom_minimum_size = Vector2(267, 280)
	var c_sb := StyleBoxFlat.new()
	c_sb.bg_color = Color(0.085, 0.014, 0.032, 0.96)
	c_sb.border_color = Color(1.0, 0.28, 0.45, 0.95)
	c_sb.set_border_width_all(2)
	c_sb.set_corner_radius_all(12)
	c_sb.content_margin_left = 14.0
	c_sb.content_margin_right = 14.0
	c_sb.content_margin_top = 14.0
	c_sb.content_margin_bottom = 14.0
	c_sb.shadow_size = 12
	c_sb.shadow_color = Color(0.85, 0.08, 0.20, 0.35)
	curse_panel.add_theme_stylebox_override("panel", c_sb)
	cards_hbox.add_child(curse_panel)
	curse_card_ref["panel"] = curse_panel

	var c_vbox := VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 8)
	curse_panel.add_child(c_vbox)

	# Header row
	var c_header_row := HBoxContainer.new()
	c_header_row.add_theme_constant_override("separation", 6)
	c_header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	c_vbox.add_child(c_header_row)

	var c_icon_canvas := Control.new()
	c_icon_canvas.custom_minimum_size = Vector2(16, 16)
	c_icon_canvas.draw.connect(func():
		Icons.draw_curse_sigil(c_icon_canvas, Color(1.0, 0.32, 0.48))
	)
	c_header_row.add_child(c_icon_canvas)

	var c_tag_lbl := Label.new()
	c_tag_lbl.text = "CURSE"
	c_tag_lbl.add_theme_font_size_override("font_size", 11)
	c_tag_lbl.add_theme_color_override("font_color", Color(1.0, 0.38, 0.50))
	c_header_row.add_child(c_tag_lbl)

	var c_spacer := Control.new()
	c_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_header_row.add_child(c_spacer)

	var c_badge := Label.new()
	c_badge.text = "DEBUFF"
	c_badge.add_theme_font_size_override("font_size", 10)
	c_badge.add_theme_color_override("font_color", Color(1.0, 0.25, 0.45, 0.85))
	c_header_row.add_child(c_badge)

	# Title
	var c_title := Label.new()
	c_title.text = String(pact_state.curse.get("title_en", "CURSE"))
	c_title.add_theme_font_size_override("font_size", 14)
	c_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.95))
	c_title.add_theme_color_override("font_shadow_color", Color(0.70, 0.08, 0.18, 0.90))
	c_title.add_theme_constant_override("shadow_offset_y", 1)
	c_vbox.add_child(c_title)
	curse_card_ref["title"] = c_title

	# Hairline divider
	var c_line := ColorRect.new()
	c_line.custom_minimum_size = Vector2(0, 1)
	c_line.color = Color(1.0, 0.28, 0.45, 0.35)
	c_vbox.add_child(c_line)

	# Effect Container
	var c_effect_panel := PanelContainer.new()
	var c_eff_sb := StyleBoxFlat.new()
	c_eff_sb.bg_color = Color(0.18, 0.03, 0.07, 0.65)
	c_eff_sb.border_color = Color(1.0, 0.25, 0.45, 0.30)
	c_eff_sb.set_border_width_all(1)
	c_eff_sb.set_corner_radius_all(6)
	c_eff_sb.content_margin_left = 8.0
	c_eff_sb.content_margin_right = 8.0
	c_eff_sb.content_margin_top = 8.0
	c_eff_sb.content_margin_bottom = 8.0
	c_effect_panel.add_theme_stylebox_override("panel", c_eff_sb)
	c_vbox.add_child(c_effect_panel)

	var c_desc := Label.new()
	c_desc.text = "• " + String(pact_state.curse.get("desc_en", pact_state.curse.get("description", "")))
	c_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_desc.add_theme_font_size_override("font_size", 11)
	c_desc.add_theme_color_override("font_color", Color(1.0, 0.55, 0.65))
	c_effect_panel.add_child(c_desc)
	curse_card_ref["desc"] = c_desc

	# Lore flavor text
	var c_flavor := Label.new()
	c_flavor.text = String(pact_state.curse.get("flavor_en", pact_state.curse.get("flavor", "")))
	c_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_flavor.add_theme_font_size_override("font_size", 10)
	c_flavor.add_theme_color_override("font_color", Color(0.80, 0.65, 0.72, 0.70))
	c_flavor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c_vbox.add_child(c_flavor)
	curse_card_ref["sub"] = c_flavor

	# Reroll button
	var c_reroll_btn := Button.new()
	c_reroll_btn.custom_minimum_size = Vector2(0, 32)
	c_reroll_btn.text = "REROLL CURSE" if not pact_state.reroll_used else "LOCKED"
	c_reroll_btn.disabled = pact_state.reroll_used
	c_reroll_btn.focus_mode = Control.FOCUS_NONE
	c_vbox.add_child(c_reroll_btn)
	curse_card_ref["btn"] = c_reroll_btn

	# ------------------------------------------
	# 2. Right Card: Abyssal Boon (Buff)
	# ------------------------------------------
	var boon_panel := PanelContainer.new()
	boon_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boon_panel.custom_minimum_size = Vector2(267, 280)
	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = Color(0.012, 0.052, 0.082, 0.96)
	b_sb.border_color = Color(0.28, 0.90, 1.0, 0.95)
	b_sb.set_border_width_all(2)
	b_sb.set_corner_radius_all(12)
	b_sb.content_margin_left = 14.0
	b_sb.content_margin_right = 14.0
	b_sb.content_margin_top = 14.0
	b_sb.content_margin_bottom = 14.0
	b_sb.shadow_size = 12
	b_sb.shadow_color = Color(0.08, 0.45, 0.70, 0.35)
	boon_panel.add_theme_stylebox_override("panel", b_sb)
	cards_hbox.add_child(boon_panel)
	boon_card_ref["panel"] = boon_panel

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 8)
	boon_panel.add_child(b_vbox)

	# Header row
	var b_header_row := HBoxContainer.new()
	b_header_row.add_theme_constant_override("separation", 6)
	b_header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	b_vbox.add_child(b_header_row)

	var b_icon_canvas := Control.new()
	b_icon_canvas.custom_minimum_size = Vector2(16, 16)
	b_icon_canvas.draw.connect(func():
		Icons.draw_boon_sigil(b_icon_canvas, Color(0.35, 0.95, 1.0))
	)
	b_header_row.add_child(b_icon_canvas)

	var b_tag_lbl := Label.new()
	b_tag_lbl.text = "BOON"
	b_tag_lbl.add_theme_font_size_override("font_size", 11)
	b_tag_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	b_header_row.add_child(b_tag_lbl)

	var b_spacer := Control.new()
	b_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_header_row.add_child(b_spacer)

	var b_badge := Label.new()
	b_badge.text = "BUFF"
	b_badge.add_theme_font_size_override("font_size", 10)
	b_badge.add_theme_color_override("font_color", Color(0.40, 0.85, 0.95, 0.85))
	b_header_row.add_child(b_badge)

	# Title
	var b_title := Label.new()
	b_title.text = String(pact_state.boon.get("title_en", "BOON"))
	b_title.add_theme_font_size_override("font_size", 14)
	b_title.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
	b_title.add_theme_color_override("font_shadow_color", Color(0.05, 0.35, 0.55, 0.90))
	b_title.add_theme_constant_override("shadow_offset_y", 1)
	b_vbox.add_child(b_title)
	boon_card_ref["title"] = b_title

	# Hairline divider
	var b_line := ColorRect.new()
	b_line.custom_minimum_size = Vector2(0, 1)
	b_line.color = Color(0.28, 0.90, 1.0, 0.35)
	b_vbox.add_child(b_line)

	# Effect Container
	var b_effect_panel := PanelContainer.new()
	var b_eff_sb := StyleBoxFlat.new()
	b_eff_sb.bg_color = Color(0.03, 0.14, 0.18, 0.65)
	b_eff_sb.border_color = Color(0.25, 0.88, 1.0, 0.30)
	b_eff_sb.set_border_width_all(1)
	b_eff_sb.set_corner_radius_all(6)
	b_eff_sb.content_margin_left = 8.0
	b_eff_sb.content_margin_right = 8.0
	b_eff_sb.content_margin_top = 8.0
	b_eff_sb.content_margin_bottom = 8.0
	b_effect_panel.add_theme_stylebox_override("panel", b_eff_sb)
	b_vbox.add_child(b_effect_panel)

	var b_desc := Label.new()
	b_desc.text = "• " + String(pact_state.boon.get("desc_en", pact_state.boon.get("description", "")))
	b_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b_desc.add_theme_font_size_override("font_size", 11)
	b_desc.add_theme_color_override("font_color", Color(0.40, 0.95, 0.85))
	b_effect_panel.add_child(b_desc)
	boon_card_ref["desc"] = b_desc

	# Lore flavor text
	var b_flavor := Label.new()
	b_flavor.text = String(pact_state.boon.get("flavor_en", pact_state.boon.get("flavor", "")))
	b_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b_flavor.add_theme_font_size_override("font_size", 10)
	b_flavor.add_theme_color_override("font_color", Color(0.68, 0.85, 0.92, 0.70))
	b_flavor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b_vbox.add_child(b_flavor)
	boon_card_ref["sub"] = b_flavor

	# Reroll button
	var b_reroll_btn := Button.new()
	b_reroll_btn.custom_minimum_size = Vector2(0, 32)
	b_reroll_btn.text = "REROLL BOON" if not pact_state.reroll_used else "LOCKED"
	b_reroll_btn.disabled = pact_state.reroll_used
	b_reroll_btn.focus_mode = Control.FOCUS_NONE
	b_vbox.add_child(b_reroll_btn)
	boon_card_ref["btn"] = b_reroll_btn

	# Style Reroll Buttons (Pill Toggle Aesthetic matching Pause Modal)
	var style_reroll_btn := func(btn: Button, col: Color):
		btn.add_theme_font_size_override("font_size", 11)
		var n_sb := StyleBoxFlat.new()
		n_sb.bg_color = Color(col.r * 0.15, col.g * 0.15, col.b * 0.15, 0.85)
		n_sb.border_color = Color(col.r, col.g, col.b, 0.90)
		n_sb.set_border_width_all(2)
		n_sb.set_corner_radius_all(14)
		n_sb.shadow_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.3)
		n_sb.shadow_size = 4

		var h_sb := StyleBoxFlat.new()
		h_sb.bg_color = Color(col.r * 0.28, col.g * 0.28, col.b * 0.28, 0.98)
		h_sb.border_color = Color(col.r, col.g, col.b, 1.0).lightened(0.2)
		h_sb.set_border_width_all(2)
		h_sb.set_corner_radius_all(14)
		h_sb.shadow_color = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.45)
		h_sb.shadow_size = 6

		var d_sb := StyleBoxFlat.new()
		d_sb.bg_color = Color(0.04, 0.06, 0.08, 0.60)
		d_sb.border_color = Color(0.25, 0.30, 0.35, 0.40)
		d_sb.set_border_width_all(1)
		d_sb.set_corner_radius_all(14)

		btn.add_theme_stylebox_override("normal", n_sb)
		btn.add_theme_stylebox_override("hover", h_sb)
		btn.add_theme_stylebox_override("pressed", h_sb)
		btn.add_theme_stylebox_override("disabled", d_sb)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", col.lightened(0.15))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.50, 0.55, 0.55))

	style_reroll_btn.call(c_reroll_btn, Color(1.0, 0.45, 0.55))
	style_reroll_btn.call(b_reroll_btn, Color(0.35, 0.88, 1.0))

	# ==========================================
	# FOOTER SECTION (Pill, Progression, Button)
	# ==========================================
	var footer_vbox := VBoxContainer.new()
	footer_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(footer_vbox)

	var reroll_pill_holder := CenterContainer.new()
	footer_vbox.add_child(reroll_pill_holder)

	var reroll_panel := PanelContainer.new()
	var reroll_sb := StyleBoxFlat.new()
	reroll_sb.set_corner_radius_all(8)
	reroll_sb.set_border_width_all(1)
	reroll_sb.content_margin_left = 14.0
	reroll_sb.content_margin_right = 14.0
	reroll_sb.content_margin_top = 4.0
	reroll_sb.content_margin_bottom = 4.0
	reroll_panel.add_theme_stylebox_override("panel", reroll_sb)
	reroll_pill_holder.add_child(reroll_panel)

	var reroll_info_lbl := Label.new()
	reroll_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reroll_info_lbl.add_theme_font_size_override("font_size", 11)
	reroll_panel.add_child(reroll_info_lbl)

	var update_reroll_info := func():
		if pact_state.reroll_used:
			reroll_sb.bg_color = Color(0.08, 0.08, 0.10, 0.60)
			reroll_sb.border_color = Color(0.45, 0.45, 0.50, 0.50)
			reroll_info_lbl.text = "◈  REROLL SPENT FOR THIS TIER (0 / 1)  ◈"
			reroll_info_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75, 0.75))
		else:
			reroll_sb.bg_color = Color(0.18, 0.12, 0.04, 0.70)
			reroll_sb.border_color = Color(1.0, 0.80, 0.35, 0.85)
			reroll_info_lbl.text = "◈  1 REROLL AVAILABLE: REROLL EITHER (1 / 1)  ◈"
			reroll_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 0.98))

	update_reroll_info.call()

	# Stack Progression Row
	var active_c_count := ChallengeModifiers.active_curses.size()
	var active_b_count := ChallengeModifiers.active_boons.size()

	var prog_hbox := HBoxContainer.new()
	prog_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prog_hbox.add_theme_constant_override("separation", 14)
	footer_vbox.add_child(prog_hbox)

	var curse_meter_lbl := Label.new()
	curse_meter_lbl.text = "CURSES: %d / 5" % active_c_count
	curse_meter_lbl.add_theme_font_size_override("font_size", 11)
	curse_meter_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.55, 0.85))
	prog_hbox.add_child(curse_meter_lbl)

	var dot_sep := Label.new()
	dot_sep.text = "•"
	dot_sep.add_theme_font_size_override("font_size", 11)
	dot_sep.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 0.5))
	prog_hbox.add_child(dot_sep)

	var boon_meter_lbl := Label.new()
	boon_meter_lbl.text = "BOONS: %d / 5" % active_b_count
	boon_meter_lbl.add_theme_font_size_override("font_size", 11)
	boon_meter_lbl.add_theme_color_override("font_color", Color(0.35, 0.88, 1.0, 0.85))
	prog_hbox.add_child(boon_meter_lbl)

	# --- CONFIRM ACTION BUTTON ---
	var confirm_btn := Button.new()
	confirm_btn.custom_minimum_size = Vector2(0, 46)
	confirm_btn.text = "◈   SEAL PACT & DESCEND   ◈"
	confirm_btn.add_theme_font_size_override("font_size", 14)
	confirm_btn.focus_mode = Control.FOCUS_NONE

	var cnf_norm := StyleBoxFlat.new()
	cnf_norm.bg_color = Color(0.24, 0.05, 0.20, 0.95)
	cnf_norm.border_color = Color(1.0, 0.45, 0.90, 0.95)
	cnf_norm.set_border_width_all(2)
	cnf_norm.set_corner_radius_all(10)
	cnf_norm.shadow_size = 14
	cnf_norm.shadow_color = Color(0.85, 0.15, 0.65, 0.45)
	var cnf_hov := StyleBoxFlat.new()
	cnf_hov.bg_color = Color(0.35, 0.08, 0.28, 1.0)
	cnf_hov.border_color = Color(1.0, 0.75, 0.98, 1.0)
	cnf_hov.set_border_width_all(2)
	cnf_hov.set_corner_radius_all(10)
	cnf_hov.shadow_size = 18
	cnf_hov.shadow_color = Color(1.0, 0.25, 0.85, 0.65)
	confirm_btn.add_theme_stylebox_override("normal", cnf_norm)
	confirm_btn.add_theme_stylebox_override("hover", cnf_hov)
	confirm_btn.add_theme_stylebox_override("pressed", cnf_hov)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.98))
	confirm_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	confirm_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	footer_vbox.add_child(confirm_btn)

	# Connect Reroll logic
	c_reroll_btn.pressed.connect(func():
		if pact_state.reroll_used:
			return
		pact_state.reroll_used = true
		ChallengeModifiers.reroll_used_milestones[milestone_lvl] = true
		if sfx != null:
			sfx.play_pact_reroll()
		pact_state.curse = ChallengeModifiers.reroll_single_item(true, pact_state.curse.id)
		c_title.text = String(pact_state.curse.get("title_en", "CURSE"))
		c_desc.text = "• " + String(pact_state.curse.get("desc_en", pact_state.curse.get("description", "")))
		c_flavor.text = String(pact_state.curse.get("flavor_en", pact_state.curse.get("flavor", "")))
		c_reroll_btn.text = "REROLLED"
		c_reroll_btn.disabled = true
		b_reroll_btn.text = "LOCKED"
		b_reroll_btn.disabled = true
		update_reroll_info.call()

		# Card flip punch animation (scale without modifying position.x)
		curse_panel.pivot_offset = curse_panel.size * 0.5
		var punch_tw := curse_panel.create_tween()
		punch_tw.tween_property(curse_panel, "scale", Vector2(0.95, 0.95), 0.06).set_trans(Tween.TRANS_QUAD)
		punch_tw.tween_property(curse_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	)

	b_reroll_btn.pressed.connect(func():
		if pact_state.reroll_used:
			return
		pact_state.reroll_used = true
		ChallengeModifiers.reroll_used_milestones[milestone_lvl] = true
		if sfx != null:
			sfx.play_pact_reroll()
		pact_state.boon = ChallengeModifiers.reroll_single_item(false, pact_state.boon.id)
		b_title.text = String(pact_state.boon.get("title_en", "BOON"))
		b_desc.text = "• " + String(pact_state.boon.get("desc_en", pact_state.boon.get("description", "")))
		b_flavor.text = String(pact_state.boon.get("flavor_en", pact_state.boon.get("flavor", "")))
		b_reroll_btn.text = "REROLLED"
		b_reroll_btn.disabled = true
		c_reroll_btn.text = "LOCKED"
		c_reroll_btn.disabled = true
		update_reroll_info.call()

		# Card flip punch animation (scale without modifying position.x)
		boon_panel.pivot_offset = boon_panel.size * 0.5
		var punch_tw := boon_panel.create_tween()
		punch_tw.tween_property(boon_panel, "scale", Vector2(0.95, 0.95), 0.06).set_trans(Tween.TRANS_QUAD)
		punch_tw.tween_property(boon_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	)

	# ==========================================
	# CINEMATIC ENTRANCE (Safe Container Tweens)
	# ==========================================
	dimmer.modulate.a = 0.0
	frame.modulate.a = 0.0
	frame.scale = Vector2(0.88, 0.88)
	frame.pivot_offset = Vector2(ModalTemplate.CARD_WIDTH * 0.5, 260.0)

	curse_panel.modulate.a = 0.0
	boon_panel.modulate.a = 0.0
	curse_panel.pivot_offset = Vector2(133.5, 140.0)
	boon_panel.pivot_offset = Vector2(133.5, 140.0)
	curse_panel.scale = Vector2(0.92, 0.92)
	boon_panel.scale = Vector2(0.92, 0.92)

	var open_tw := root.create_tween()
	open_tw.parallel().tween_property(dimmer, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	open_tw.parallel().tween_property(frame, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	open_tw.parallel().tween_property(frame, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Staggered card reveals (animates scale & alpha without corrupting HBoxContainer X offsets)
	var card_tw := root.create_tween()
	card_tw.tween_interval(0.08)
	card_tw.parallel().tween_property(curse_panel, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD)
	card_tw.parallel().tween_property(curse_panel, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	card_tw.tween_interval(0.08)
	card_tw.parallel().tween_property(boon_panel, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD)
	card_tw.parallel().tween_property(boon_panel, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ==========================================
	# CONFIRM & CINEMATIC EXIT
	# ==========================================
	confirm_btn.pressed.connect(func():
		confirm_btn.disabled = true
		c_reroll_btn.disabled = true
		b_reroll_btn.disabled = true
		ChallengeModifiers.claim_pact(milestone_lvl, pact_state.curse.id, pact_state.boon.id)
		if sfx != null:
			sfx.play_pact_seal()

		var close_tw := root.create_tween()
		close_tw.parallel().tween_property(frame, "scale", Vector2(0.92, 0.92), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.parallel().tween_property(root, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.tween_callback(func():
			canvas.queue_free()
			if on_accepted.is_valid():
				on_accepted.call()
		)
	)

	return root
