class_name HudLayoutCustomizer
extends Control
## Interactive HUD Layout Customizer for ECHO.
## Allows players to freely touch-drag and resize all 6 core HUD components:
## - SoundBtn (ECHO)
## - SneakBtn (SNEAK)
## - PebbleBtn (PEBBLE)
## - PauseBtn (PAUSE)
## - MicIndicator (Voice Acoustic Visualizer)
## - LevelInfo (Sector Badge & Depth Telemetry)

signal closed

var _vfx_canvas: Control
var _panel: PanelContainer
var _detail_vbox: VBoxContainer
var _is_collapsed: bool = false
var _fold_btn: Button
var _selection_tag: Label
var _scale_slider: HSlider
var _scale_val_lbl: Label
var _chips: Dictionary = {}
var _modified_elements: Dictionary = {}
var _initial_layout_snapshot: Dictionary = {}
var _confirm_dialog: Control = null

# Element definitions: id -> { "control": Control, "data": Dictionary, "base_size": Vector2, "title": String, "short": String }
var _elements: Dictionary = {}
var _selected_id: String = "SoundBtn"
var _dragging := false
var _drag_target_id: String = ""
var _drag_touch_offset := Vector2.ZERO
var _drag_touch_index: int = -1
var _time := 0.0

# Control Panel Dragging State
var _panel_dragging := false
var _panel_drag_offset := Vector2.ZERO
var _panel_drag_touch_index: int = -1
var _panel_manually_moved := false


static func open(parent: Node) -> HudLayoutCustomizer:
	var canvas := CanvasLayer.new()
	canvas.layer = 150
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.name = "HudCustomizerCanvas"
	parent.add_child(canvas)

	var customizer := HudLayoutCustomizer.new()
	ModalTemplate.apply_full_rect(customizer)
	canvas.add_child(customizer)
	return customizer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Ensure gameplay level remains paused during customization
	if get_tree().get_first_node_in_group("player") != null:
		get_tree().paused = true

	# 1. Fully opaque dark blueprint backdrop (100% covers settings & game scenes)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.012, 0.022, 0.040, 1.0)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	ModalTemplate.apply_full_rect(dimmer)
	add_child(dimmer)

	# 2. Procedural blueprint grid canvas
	_vfx_canvas = Control.new()
	_vfx_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ModalTemplate.apply_full_rect(_vfx_canvas)
	_vfx_canvas.draw.connect(_draw_blueprint_grid)
	add_child(_vfx_canvas)

	# 3. Create interactive proxies for all 6 HUD components
	_setup_hud_proxies()

	# 4. Build single unified floating control panel in upper-middle area (y = 92)
	_build_control_panel()

	# 5. Default selection
	_select_element("SoundBtn")

	# Entry fade animation
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		_sync_panel_layout()
		var vp_size := get_viewport().get_visible_rect().size
		for id: String in _elements:
			_update_proxy_transform(id, vp_size)


func _process(delta: float) -> void:
	_time += delta
	if _vfx_canvas != null and is_instance_valid(_vfx_canvas):
		_vfx_canvas.queue_redraw()
	for id: String in _elements:
		var c: Control = _elements[id]["control"]
		if c != null and is_instance_valid(c):
			c.queue_redraw()


func _draw_blueprint_grid() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var grid_step := 48.0
	var grid_col := Color(0.20, 0.50, 0.75, 0.07)

	# Subtle cross grid lines
	var x := 0.0
	while x < vp_size.x:
		_vfx_canvas.draw_line(Vector2(x, 0), Vector2(x, vp_size.y), grid_col, 1.0)
		x += grid_step

	var y := 0.0
	while y < vp_size.y:
		_vfx_canvas.draw_line(Vector2(0, y), Vector2(vp_size.x, y), grid_col, 1.0)
		y += grid_step

	# Screen center axes
	var axis_col := Color(0.35, 0.85, 1.0, 0.15)
	_vfx_canvas.draw_line(Vector2(vp_size.x * 0.5, 0), Vector2(vp_size.x * 0.5, vp_size.y), axis_col, 1.5)
	_vfx_canvas.draw_line(Vector2(0, vp_size.y * 0.5), Vector2(vp_size.x, vp_size.y * 0.5), axis_col, 1.5)

	# Safe area frame (16px inset)
	var safe_rect := Rect2(16.0, 16.0, vp_size.x - 32.0, vp_size.y - 32.0)
	_vfx_canvas.draw_rect(safe_rect, Color(0.4, 0.8, 1.0, 0.12), false, 1.0)


func _is_different_from_default(id: String, cur_data: Dictionary, defs: Dictionary) -> bool:
	if not defs.has(id):
		return true
	var def_data: Dictionary = defs[id]
	var d_ax: float = absf(float(cur_data.get("anchor_x", 0.0)) - float(def_data.get("anchor_x", 0.0)))
	var d_ay: float = absf(float(cur_data.get("anchor_y", 0.0)) - float(def_data.get("anchor_y", 0.0)))
	var d_ox: float = absf(float(cur_data.get("offset_x", 0.0)) - float(def_data.get("offset_x", 0.0)))
	var d_oy: float = absf(float(cur_data.get("offset_y", 0.0)) - float(def_data.get("offset_y", 0.0)))
	var d_sc: float = absf(float(cur_data.get("scale", 1.0)) - float(def_data.get("scale", 1.0)))
	return (d_ax > 0.001 or d_ay > 0.001 or d_ox > 2.0 or d_oy > 2.0 or d_sc > 0.02)


func _setup_hud_proxies() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 10.0:
		vp_size = Vector2(720, 1280)

	var defs := GameState.get_default_hud_layout()
	var current_layout: Dictionary = GameState.custom_hud_layout

	_modified_elements.clear()
	for id: String in current_layout:
		if _is_different_from_default(id, current_layout[id], defs):
			_modified_elements[id] = true

	var items_meta := [
		{ "id": "SoundBtn", "title": "ECHO", "short": "ECHO", "size": Vector2(110, 136) },
		{ "id": "SneakBtn", "title": "SNEAK", "short": "SNEAK", "size": Vector2(110, 136) },
		{ "id": "PebbleBtn", "title": "PEBBLE", "short": "PEBBLE", "size": Vector2(88, 104) },
		{ "id": "PauseBtn", "title": "PAUSE", "short": "PAUSE", "size": Vector2(45, 45) },
		{ "id": "MicIndicator", "title": "VOICE SENSOR", "short": "MIC", "size": Vector2(96, 28) },
		{ "id": "LevelInfo", "title": "SECTOR INFO", "short": "SECTOR", "size": Vector2(160, 42) },
	]

	for item in items_meta:
		var id: String = str(item["id"])
		var b_size: Vector2 = item["size"]
		var title_str: String = str(item["title"])
		var short_str: String = str(item["short"])

		# Retrieve saved layout or fallback to default
		var data: Dictionary = {}
		if current_layout.has(id):
			data = current_layout[id].duplicate()
		elif defs.has(id):
			data = defs[id].duplicate()
		else:
			data = { "anchor_x": 0.5, "offset_x": 0.0, "anchor_y": 0.5, "offset_y": 0.0, "scale": 1.0 }

		var ctrl := Control.new()
		ctrl.name = "Proxy_" + id
		ctrl.custom_minimum_size = b_size
		ctrl.size = b_size
		ctrl.pivot_offset = b_size * 0.5
		ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		ctrl.draw.connect(func(): _draw_proxy_element(ctrl, id))
		ctrl.gui_input.connect(func(ev: InputEvent): _handle_proxy_input(ev, id))

		add_child(ctrl)

		_elements[id] = {
			"control": ctrl,
			"data": data,
			"base_size": b_size,
			"title": title_str,
			"short": short_str
		}

		_update_proxy_transform(id, vp_size)

	_initial_layout_snapshot.clear()
	for id: String in _elements:
		_initial_layout_snapshot[id] = _elements[id]["data"].duplicate()


func _update_proxy_transform(id: String, vp_size: Vector2) -> void:
	if not _elements.has(id):
		return
	var elem: Dictionary = _elements[id]
	var ctrl: Control = elem["control"]
	var data: Dictionary = elem["data"]
	var b_size: Vector2 = elem["base_size"]

	var ax: float = float(data.get("anchor_x", 0.0))
	var ay: float = float(data.get("anchor_y", 0.0))
	var ox: float = float(data.get("offset_x", 0.0))
	var oy: float = float(data.get("offset_y", 0.0))
	var sc: float = clampf(float(data.get("scale", 1.0)), 0.6, 1.8)

	ctrl.scale = Vector2(sc, sc)
	var target_center := Vector2(ax * vp_size.x + ox, ay * vp_size.y + oy)
	ctrl.position = target_center - b_size * 0.5


func _handle_proxy_input(event: InputEvent, id: String) -> void:
	if not _elements.has(id):
		return
	var ctrl: Control = _elements[id]["control"]

	var is_press := false
	var touch_idx := -1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		is_press = true
		touch_idx = -1
	elif event is InputEventScreenTouch and event.pressed:
		is_press = true
		touch_idx = event.index

	if is_press:
		_select_element(id)
		_dragging = true
		_drag_target_id = id
		_drag_touch_index = touch_idx
		var touch_global: Vector2 = ctrl.get_global_transform() * event.position
		var ctrl_center: Vector2 = ctrl.global_position + ctrl.size * 0.5
		_drag_touch_offset = touch_global - ctrl_center
		accept_event()


func _handle_panel_drag_input(event: InputEvent) -> void:
	var is_press := false
	var touch_idx := -1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		is_press = true
		touch_idx = -1
	elif event is InputEventScreenTouch and event.pressed:
		is_press = true
		touch_idx = event.index

	if is_press:
		_panel_dragging = true
		_panel_drag_touch_index = touch_idx
		var touch_global: Vector2 = _panel.get_global_transform() * event.position
		_panel_drag_offset = touch_global - _panel.global_position
		accept_event()


func _input(event: InputEvent) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 10.0:
		vp_size = Vector2(720, 1280)

	# Handle dragging the floating HUD Customizer control panel itself
	if _panel_dragging:
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			var new_pos: Vector2 = mm.position - _panel_drag_offset
			var panel_w: float = _panel.size.x
			var panel_h: float = _panel.size.y
			new_pos.x = clampf(new_pos.x, 8.0, vp_size.x - panel_w - 8.0)
			new_pos.y = clampf(new_pos.y, 8.0, vp_size.y - panel_h - 8.0)
			_panel.position = new_pos
			_panel_manually_moved = true
			accept_event()
		elif event is InputEventScreenDrag:
			var sd := event as InputEventScreenDrag
			if _panel_drag_touch_index == -1 or sd.index == _panel_drag_touch_index:
				var new_pos: Vector2 = sd.position - _panel_drag_offset
				var panel_w: float = _panel.size.x
				var panel_h: float = _panel.size.y
				new_pos.x = clampf(new_pos.x, 8.0, vp_size.x - panel_w - 8.0)
				new_pos.y = clampf(new_pos.y, 8.0, vp_size.y - panel_h - 8.0)
				_panel.position = new_pos
				_panel_manually_moved = true
				accept_event()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_panel_dragging = false
			_panel_drag_touch_index = -1
		elif event is InputEventScreenTouch and not event.pressed:
			if _panel_drag_touch_index == -1 or event.index == _panel_drag_touch_index:
				_panel_dragging = false
				_panel_drag_touch_index = -1
		return

	# Handle dragging individual HUD proxy elements
	if not _dragging:
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var new_center: Vector2 = mm.position - _drag_touch_offset
		_clamp_and_store_position(_drag_target_id, new_center, vp_size)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _drag_touch_index == -1 or sd.index == _drag_touch_index:
			var new_center: Vector2 = sd.position - _drag_touch_offset
			_clamp_and_store_position(_drag_target_id, new_center, vp_size)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		_drag_target_id = ""
		_drag_touch_index = -1
	elif event is InputEventScreenTouch and not event.pressed:
		if _drag_touch_index == -1 or event.index == _drag_touch_index:
			_dragging = false
			_drag_target_id = ""
			_drag_touch_index = -1


func _clamp_and_store_position(id: String, new_center: Vector2, vp_size: Vector2) -> void:
	if not _elements.has(id):
		return
	var elem: Dictionary = _elements[id]
	var ctrl: Control = elem["control"]
	var data: Dictionary = elem["data"]
	var b_size: Vector2 = elem["base_size"]
	var sc: float = float(data.get("scale", 1.0))

	var half_w := b_size.x * 0.5 * sc
	var half_h := b_size.y * 0.5 * sc

	# Enforce 16px screen safe margins
	new_center.x = clampf(new_center.x, half_w + 16.0, vp_size.x - half_w - 16.0)
	new_center.y = clampf(new_center.y, half_h + 16.0, vp_size.y - half_h - 16.0)

	# Compute closest adaptive anchors
	var ax := 0.5
	var ox := new_center.x - vp_size.x * 0.5
	if new_center.x < vp_size.x * 0.38:
		ax = 0.0
		ox = new_center.x
	elif new_center.x > vp_size.x * 0.62:
		ax = 1.0
		ox = new_center.x - vp_size.x

	var ay := 0.0
	var oy := new_center.y
	if new_center.y >= vp_size.y * 0.5:
		ay = 1.0
		oy = new_center.y - vp_size.y

	data["anchor_x"] = ax
	data["offset_x"] = ox
	data["anchor_y"] = ay
	data["offset_y"] = oy

	ctrl.position = new_center - b_size * 0.5

	_modified_elements[id] = true
	_update_chip_styles()


func _select_element(id: String) -> void:
	_selected_id = id
	if not _elements.has(id):
		return
	var elem: Dictionary = _elements[id]
	var data: Dictionary = elem["data"]
	var title_str: String = elem["title"]
	var cur_scale: float = float(data.get("scale", 1.0))

	if _selection_tag != null:
		_selection_tag.text = "SELECTED:  %s" % title_str
	if _scale_slider != null:
		_scale_slider.set_value_no_signal(cur_scale)
	if _scale_val_lbl != null:
		_scale_val_lbl.text = "%d%%" % int(round(cur_scale * 100.0))

	_update_chip_styles()

	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_pact_reroll()


func _update_chip_styles() -> void:
	for chip_id: String in _chips:
		var btn: Button = _chips[chip_id]
		var is_active: bool = (chip_id == _selected_id)
		var is_mod: bool = _modified_elements.has(chip_id)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		if is_active:
			sb.bg_color = Color(0.08, 0.28, 0.46, 0.95)
			sb.border_color = Color(0.38, 0.90, 1.0, 1.0)
			btn.add_theme_color_override("font_color", Color(0.50, 1.0, 1.0, 1.0))
		elif is_mod:
			sb.bg_color = Color(0.05, 0.16, 0.28, 0.85)
			sb.border_color = Color(0.28, 0.70, 0.88, 0.75)
			btn.add_theme_color_override("font_color", Color(0.70, 0.90, 1.0, 0.95))
		else:
			sb.bg_color = Color(0.025, 0.07, 0.13, 0.70)
			sb.border_color = Color(0.20, 0.40, 0.60, 0.40)
			btn.add_theme_color_override("font_color", Color(0.55, 0.75, 0.90, 0.75))
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)


func _draw_proxy_element(ctrl: Control, id: String) -> void:
	var w: float = ctrl.size.x
	var h: float = ctrl.size.y
	var is_sel: bool = (_selected_id == id)
	var t: float = _time
	var is_chal: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)

	match id:
		"SoundBtn":
			var c := Vector2(w * 0.5, 48.0)
			var r := 44.0
			# Cavern disc
			var disc_col := Color(0.16, 0.03, 0.13, 0.88) if is_chal else Color(0.04, 0.12, 0.22, 0.78)
			var inner_col := Color(0.25, 0.05, 0.20, 0.45) if is_chal else Color(0.08, 0.22, 0.36, 0.35)
			ctrl.draw_circle(c, r, disc_col)
			ctrl.draw_circle(c, r * 0.78, inner_col)
			# Border rim & cardinal ticks
			var rim_col := Color(0.85, 0.25, 0.75, 0.78) if is_chal else Color(0.26, 0.54, 0.82, 0.65)
			ctrl.draw_arc(c, r, 0.0, TAU, 48, rim_col, 1.8)
			for i in range(4):
				var ang := i * PI * 0.5
				var dir := Vector2.from_angle(ang)
				ctrl.draw_line(c + dir * (r - 5.5), c + dir * (r - 1.5), Color(rim_col, 0.38), 1.4)
			# Concentric Echo waves (( · ))
			var icon_col := Color(0.85, 0.94, 1.0, 0.92)
			ctrl.draw_circle(c, 4.5, icon_col)
			ctrl.draw_arc(c, 13.0, -PI * 0.32, PI * 0.32, 16, icon_col, 2.0)
			ctrl.draw_arc(c, 13.0, PI * 0.68, PI * 1.32, 16, icon_col, 2.0)
			ctrl.draw_arc(c, 22.0, -PI * 0.28, PI * 0.28, 16, Color(icon_col, 0.6), 1.8)
			ctrl.draw_arc(c, 22.0, PI * 0.72, PI * 1.28, 16, Color(icon_col, 0.6), 1.8)
			# Clean label below
			var font := ThemeDB.fallback_font
			var lbl_col := Color(0.95, 0.65, 0.88, 0.75) if is_chal else Color(0.55, 0.80, 1.0, 0.75)
			ctrl.draw_string(font, Vector2(0, 114.0), "ECHO", HORIZONTAL_ALIGNMENT_CENTER, int(w), 11, lbl_col)
			ctrl.draw_string(font, Vector2(0, 127.0), "[E]", HORIZONTAL_ALIGNMENT_CENTER, int(w), 9, Color(lbl_col, 0.45))

		"SneakBtn":
			var c := Vector2(w * 0.5, 48.0)
			var r := 44.0
			# Cavern disc
			var disc_col := Color(0.16, 0.03, 0.13, 0.88) if is_chal else Color(0.04, 0.12, 0.22, 0.78)
			var inner_col := Color(0.25, 0.05, 0.20, 0.45) if is_chal else Color(0.08, 0.22, 0.36, 0.35)
			ctrl.draw_circle(c, r, disc_col)
			ctrl.draw_circle(c, r * 0.78, inner_col)
			# Border rim & cardinal ticks
			var rim_col := Color(0.85, 0.25, 0.75, 0.78) if is_chal else Color(0.26, 0.54, 0.82, 0.65)
			ctrl.draw_arc(c, r, 0.0, TAU, 48, rim_col, 1.8)
			for i in range(4):
				var ang := i * PI * 0.5
				var dir := Vector2.from_angle(ang)
				ctrl.draw_line(c + dir * (r - 5.5), c + dir * (r - 1.5), Color(rim_col, 0.38), 1.4)
			# Stealth feather icon
			var icon_col := Color(1.0, 0.90, 0.96, 0.92) if is_chal else Color(0.85, 0.94, 1.0, 0.88)
			Icons.draw_stealth(ctrl, c, icon_col)
			# Labels
			var font := ThemeDB.fallback_font
			var lbl_col := Color(0.95, 0.65, 0.88, 0.75) if is_chal else Color(0.55, 0.80, 1.0, 0.72)
			ctrl.draw_string(font, Vector2(0, 114.0), "SNEAK", HORIZONTAL_ALIGNMENT_CENTER, int(w), 11, lbl_col)
			ctrl.draw_string(font, Vector2(0, 127.0), "[SHIFT]", HORIZONTAL_ALIGNMENT_CENTER, int(w), 9, Color(lbl_col, 0.45))

		"PebbleBtn":
			var c := Vector2(w * 0.5, 36.0)
			var r := 32.0
			# Warm amber disc
			var col_disc := Color(0.12, 0.09, 0.04, 0.82)
			var col_rim := Color(1.0, 0.78, 0.28, 0.75)
			ctrl.draw_circle(c, r, col_disc)
			ctrl.draw_circle(c, r * 0.78, Color(col_rim, 0.10))
			ctrl.draw_arc(c, r, 0.0, TAU, 36, col_rim, 1.6)
			# Pebble skip-stone icon
			Icons.draw_pebble(ctrl, c, Color(1.0, 0.88, 0.6, 0.9), false)
			# Notch count badge 3
			var badge_pos := c + Vector2(25.0, -23.0)
			ctrl.draw_circle(badge_pos, 11.5, Color(0.015, 0.025, 0.04, 0.98))
			ctrl.draw_circle(badge_pos, 10.0, Color(0.12, 0.09, 0.03, 0.98))
			ctrl.draw_arc(badge_pos, 10.0, 0.0, TAU, 24, col_rim, 1.6)
			var font := ThemeDB.fallback_font
			ctrl.draw_string(font, badge_pos + Vector2(-9.0, 4.0), "3", HORIZONTAL_ALIGNMENT_CENTER, 18, 11, Color(1.0, 0.96, 0.82))
			# Labels
			ctrl.draw_string(font, Vector2(0, 84.0), "PEBBLE", HORIZONTAL_ALIGNMENT_CENTER, int(w), 10, col_rim)
			ctrl.draw_string(font, Vector2(0, 96.0), "[P]", HORIZONTAL_ALIGNMENT_CENTER, int(w), 8, Color(col_rim, 0.45))

		"PauseBtn":
			var c := Vector2(w * 0.5, h * 0.5)
			var r := minf(w, h) * 0.44
			# Outer subtle halo
			var halo_col := Color(0.85, 0.20, 0.65, 0.14) if is_chal else Color(0.12, 0.45, 0.8, 0.12)
			ctrl.draw_circle(c, r + 3.0, halo_col)
			# Cavern dark glass disc
			var disc_col := Color(0.16, 0.03, 0.13, 0.85) if is_chal else Color(0.04, 0.12, 0.22, 0.8)
			var inner_col := Color(0.25, 0.05, 0.20, 0.40) if is_chal else Color(0.08, 0.2, 0.35, 0.3)
			ctrl.draw_circle(c, r, disc_col)
			ctrl.draw_circle(c, r * 0.8, inner_col)
			# Crisp Outer Rim
			var rim_col := Color(0.88, 0.32, 0.78, 0.85) if is_chal else Color(0.35, 0.65, 0.95, 0.85)
			ctrl.draw_arc(c, r, 0.0, TAU, 36, rim_col, 1.6)
			# Two vertical pause bars
			var bar_w := 3.2
			var bar_h := 14.0
			var bar_gap := 4.5
			var col := Color(0.98, 0.90, 0.96, 0.92) if is_chal else Color(0.85, 0.94, 1.0, 0.95)
			ctrl.draw_line(Vector2(c.x - bar_gap, c.y - bar_h * 0.5), Vector2(c.x - bar_gap, c.y + bar_h * 0.5), col, bar_w)
			ctrl.draw_line(Vector2(c.x + bar_gap, c.y - bar_h * 0.5), Vector2(c.x + bar_gap, c.y + bar_h * 0.5), col, bar_w)

		"MicIndicator":
			var rect := Rect2(0, 0, w, h)
			var bg_sb := StyleBoxFlat.new()
			bg_sb.bg_color = Color(0.025, 0.075, 0.15, 0.85)
			bg_sb.border_color = Color(0.85, 0.25, 0.75, 0.65) if is_chal else Color(0.30, 0.70, 0.95, 0.65)
			bg_sb.set_border_width_all(1)
			bg_sb.set_corner_radius_all(14)
			ctrl.draw_style_box(bg_sb, rect)
			var bar_col := Color(0.95, 0.45, 0.85, 0.85) if is_chal else Color(0.40, 0.85, 1.0, 0.85)
			for i in range(5):
				var bx: float = w * 0.5 + (i - 2) * 10.5
				var bh: float = 6.0 + 8.0 * (1.0 - absf(i - 2) * 0.3)
				ctrl.draw_line(Vector2(bx, h * 0.5 - bh * 0.5), Vector2(bx, h * 0.5 + bh * 0.5), bar_col, 2.8)

		"LevelInfo":
			# Clean typography matching native _badge_container (no card panel box!)
			var font := ThemeDB.fallback_font
			var title_col := Color(1.0, 0.94, 0.98, 0.95) if is_chal else Color(0.90, 0.96, 1.0, 0.90)
			var depth_col := Color(0.92, 0.55, 0.82, 0.75) if is_chal else Color(0.45, 0.78, 0.96, 0.65)
			var lvl_title := "ABYSS DESCENT I" if is_chal else "SHALLOW RING"
			var lvl_depth := "~4,500 M" if is_chal else "~4,200 M"
			ctrl.draw_string(font, Vector2(0.0, 18.0), lvl_title, HORIZONTAL_ALIGNMENT_LEFT, int(w), 15, title_col)
			ctrl.draw_string(font, Vector2(0.0, 34.0), lvl_depth, HORIZONTAL_ALIGNMENT_LEFT, int(w), 11, depth_col)

	# Selection highlight border and bounding brackets
	if is_sel:
		var sel_rect := Rect2(-6, -6, w + 12, h + 12)
		var glow_a: float = 0.75 + 0.25 * sin(t * 6.0)
		var sel_col := Color(0.35, 0.95, 1.0, glow_a)
		ctrl.draw_rect(sel_rect, sel_col, false, 2.0)

		# Bracket corners
		var clen := 9.0
		# Top-left
		ctrl.draw_line(sel_rect.position, sel_rect.position + Vector2(clen, 0), Color.WHITE, 2.5)
		ctrl.draw_line(sel_rect.position, sel_rect.position + Vector2(0, clen), Color.WHITE, 2.5)
		# Top-right
		var top_right := sel_rect.position + Vector2(sel_rect.size.x, 0)
		ctrl.draw_line(top_right, top_right - Vector2(clen, 0), Color.WHITE, 2.5)
		ctrl.draw_line(top_right, top_right + Vector2(0, clen), Color.WHITE, 2.5)
		# Bottom-left
		var bl := sel_rect.position + Vector2(0, sel_rect.size.y)
		ctrl.draw_line(bl, bl + Vector2(clen, 0), Color.WHITE, 2.5)
		ctrl.draw_line(bl, bl - Vector2(0, clen), Color.WHITE, 2.5)
		# Bottom-right
		var br := sel_rect.position + sel_rect.size
		ctrl.draw_line(br, br - Vector2(clen, 0), Color.WHITE, 2.5)
		ctrl.draw_line(br, br - Vector2(0, clen), Color.WHITE, 2.5)


func _sync_panel_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 10.0:
		vp_size = Vector2(720, 1280)
	var panel_w := minf(vp_size.x - 32.0, 560.0)
	if _panel != null and is_instance_valid(_panel):
		_panel.custom_minimum_size = Vector2(panel_w, 0)
		_panel.size = Vector2(panel_w, 0)
		if not _panel_manually_moved:
			_panel.position = Vector2((vp_size.x - panel_w) * 0.5, 92.0)
		else:
			var px := clampf(_panel.position.x, 8.0, vp_size.x - panel_w - 8.0)
			var py := clampf(_panel.position.y, 8.0, vp_size.y - _panel.size.y - 8.0)
			_panel.position = Vector2(px, py)


func _build_control_panel() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_handle_panel_drag_input)

	var card_sb := ModalTemplate.make_card_style(ModalTemplate.ThemeKind.SONAR)
	card_sb.content_margin_left = 14.0
	card_sb.content_margin_right = 14.0
	card_sb.content_margin_top = 8.0
	card_sb.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", card_sb)
	add_child(_panel)

	_sync_panel_layout()

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(main_vbox)

	# Row 1: Header (Title + Minimize/Expand + Action Buttons)
	var hdr_row := HBoxContainer.new()
	hdr_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_theme_constant_override("separation", 8)
	hdr_row.mouse_filter = Control.MOUSE_FILTER_STOP
	hdr_row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	hdr_row.gui_input.connect(_handle_panel_drag_input)
	main_vbox.add_child(hdr_row)

	var title_lbl := Label.new()
	title_lbl.text = "⋮⋮  HUD CUSTOMIZER"
	title_lbl.tooltip_text = "Drag header to move control panel"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 1.0))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	hdr_row.add_child(title_lbl)

	# Fold / Minimize toggle button
	_fold_btn = Button.new()
	_fold_btn.text = "▲"
	_fold_btn.custom_minimum_size = Vector2(30, 28)
	_fold_btn.focus_mode = Control.FOCUS_NONE
	_fold_btn.add_theme_font_size_override("font_size", 11)
	ModalTemplate.style_button(_fold_btn, false, ModalTemplate.ThemeKind.SONAR)
	_fold_btn.pressed.connect(_toggle_fold)
	hdr_row.add_child(_fold_btn)

	# Action Buttons: RESET ALL, CANCEL, SAVE
	var reset_btn := Button.new()
	reset_btn.text = "RESET ALL"
	reset_btn.custom_minimum_size = Vector2(76, 28)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_font_size_override("font_size", 11)
	ModalTemplate.style_button(reset_btn, false, ModalTemplate.ThemeKind.CRIMSON)
	reset_btn.pressed.connect(_on_reset_all_pressed)
	hdr_row.add_child(reset_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(64, 28)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.add_theme_font_size_override("font_size", 11)
	ModalTemplate.style_button(cancel_btn, false, ModalTemplate.ThemeKind.SONAR)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	hdr_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.custom_minimum_size = Vector2(68, 28)
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.add_theme_font_size_override("font_size", 11)
	ModalTemplate.style_button(save_btn, true, ModalTemplate.ThemeKind.SONAR)
	save_btn.pressed.connect(_on_save_pressed)
	hdr_row.add_child(save_btn)

	# Collapsible detail container (Rows 2, 3, 4)
	_detail_vbox = VBoxContainer.new()
	_detail_vbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(_detail_vbox)

	# Row 2: Component Quick-Select Chips
	var chips_row := HBoxContainer.new()
	chips_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_row.add_theme_constant_override("separation", 6)
	_detail_vbox.add_child(chips_row)

	_chips.clear()
	for id: String in _elements:
		var elem: Dictionary = _elements[id]
		var short_name: String = str(elem.get("short", id))
		var chip := Button.new()
		chip.text = short_name
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, 26)
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", 10)
		chip.pressed.connect(func(): _select_element(id))
		chips_row.add_child(chip)
		_chips[id] = chip

	# Row 3: Element Scale Adjustment + Per-Element Reset
	var scale_row := HBoxContainer.new()
	scale_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_theme_constant_override("separation", 10)
	_detail_vbox.add_child(scale_row)

	_selection_tag = Label.new()
	_selection_tag.text = "SELECTED:  ECHO"
	_selection_tag.custom_minimum_size = Vector2(150, 0)
	_selection_tag.add_theme_font_size_override("font_size", 11)
	_selection_tag.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	scale_row.add_child(_selection_tag)

	var scale_lbl := Label.new()
	scale_lbl.text = "SCALE:"
	scale_lbl.add_theme_font_size_override("font_size", 11)
	scale_lbl.add_theme_color_override("font_color", Color(0.50, 0.75, 0.95, 0.8))
	scale_row.add_child(scale_lbl)

	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.70
	_scale_slider.max_value = 1.50
	_scale_slider.step = 0.05
	_scale_slider.value = 1.0
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale_slider.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_slider(_scale_slider, ModalTemplate.ThemeKind.SONAR)
	_scale_slider.value_changed.connect(_on_scale_slider_changed)
	scale_row.add_child(_scale_slider)

	_scale_val_lbl = Label.new()
	_scale_val_lbl.text = "100%"
	_scale_val_lbl.custom_minimum_size = Vector2(40, 0)
	_scale_val_lbl.add_theme_font_size_override("font_size", 11)
	_scale_val_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 0.95))
	scale_row.add_child(_scale_val_lbl)

	var reset_scale_btn := Button.new()
	reset_scale_btn.text = "100% SIZE"
	reset_scale_btn.custom_minimum_size = Vector2(70, 24)
	reset_scale_btn.focus_mode = Control.FOCUS_NONE
	reset_scale_btn.add_theme_font_size_override("font_size", 10)
	ModalTemplate.style_button(reset_scale_btn, false, ModalTemplate.ThemeKind.SONAR)
	reset_scale_btn.pressed.connect(func():
		_on_scale_slider_changed(1.0)
		_scale_slider.value = 1.0
	)
	scale_row.add_child(reset_scale_btn)

	var reset_elem_btn := Button.new()
	reset_elem_btn.text = "RESET ELEM"
	reset_elem_btn.custom_minimum_size = Vector2(76, 24)
	reset_elem_btn.focus_mode = Control.FOCUS_NONE
	reset_elem_btn.add_theme_font_size_override("font_size", 10)
	ModalTemplate.style_button(reset_elem_btn, false, ModalTemplate.ThemeKind.ARCHIVE)
	reset_elem_btn.pressed.connect(_reset_current_element)
	scale_row.add_child(reset_elem_btn)

	# Row 4: Subtle Guidance Hint
	var hint_lbl := Label.new()
	hint_lbl.text = "Drag elements to reposition • Only modified elements are saved • 16px screen safe margins enforced"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", Color(0.42, 0.65, 0.85, 0.6))
	_detail_vbox.add_child(hint_lbl)


func _toggle_fold() -> void:
	_is_collapsed = not _is_collapsed
	_detail_vbox.visible = not _is_collapsed
	_fold_btn.text = "▼" if _is_collapsed else "▲"


func _on_scale_slider_changed(val: float) -> void:
	if not _elements.has(_selected_id):
		return
	var elem: Dictionary = _elements[_selected_id]
	var data: Dictionary = elem["data"]
	data["scale"] = val
	if _scale_val_lbl != null:
		_scale_val_lbl.text = "%d%%" % int(round(val * 100.0))

	var vp_size := get_viewport().get_visible_rect().size
	_update_proxy_transform(_selected_id, vp_size)

	_modified_elements[_selected_id] = true
	_update_chip_styles()


func _reset_current_element() -> void:
	if not _elements.has(_selected_id):
		return
	var defs := GameState.get_default_hud_layout()
	if defs.has(_selected_id):
		_elements[_selected_id]["data"] = defs[_selected_id].duplicate()
	else:
		_elements[_selected_id]["data"] = { "anchor_x": 0.5, "offset_x": 0.0, "anchor_y": 0.5, "offset_y": 0.0, "scale": 1.0 }

	_modified_elements.erase(_selected_id)
	var vp_size := get_viewport().get_visible_rect().size
	_update_proxy_transform(_selected_id, vp_size)
	_select_element(_selected_id)

	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_deny_tick()


func _on_reset_all_pressed() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var defs := GameState.get_default_hud_layout()

	_modified_elements.clear()
	for id: String in _elements:
		if defs.has(id):
			_elements[id]["data"] = defs[id].duplicate()
			_update_proxy_transform(id, vp_size)

	_select_element(_selected_id)

	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_deny_tick()


func _has_unsaved_changes() -> bool:
	if _initial_layout_snapshot.is_empty():
		return false
	for id: String in _elements:
		if not _initial_layout_snapshot.has(id):
			return true
		var init_d: Dictionary = _initial_layout_snapshot[id]
		var cur_d: Dictionary = _elements[id]["data"]
		var d_ax: float = absf(float(cur_d.get("anchor_x", 0.0)) - float(init_d.get("anchor_x", 0.0)))
		var d_ay: float = absf(float(cur_d.get("anchor_y", 0.0)) - float(init_d.get("anchor_y", 0.0)))
		var d_ox: float = absf(float(cur_d.get("offset_x", 0.0)) - float(init_d.get("offset_x", 0.0)))
		var d_oy: float = absf(float(cur_d.get("offset_y", 0.0)) - float(init_d.get("offset_y", 0.0)))
		var d_sc: float = absf(float(cur_d.get("scale", 1.0)) - float(init_d.get("scale", 1.0)))
		if d_ax > 0.001 or d_ay > 0.001 or d_ox > 2.0 or d_oy > 2.0 or d_sc > 0.01:
			return true
	return false


func _show_unsaved_changes_confirm() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		return

	var root := Control.new()
	root.name = "UnsavedChangesConfirmRoot"
	root.z_index = 20
	ModalTemplate.apply_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_confirm_dialog = root

	var dimmer := ColorRect.new()
	ModalTemplate.apply_full_rect(dimmer)
	dimmer.color = Color(0.01, 0.02, 0.04, 0.88)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	var center := CenterContainer.new()
	ModalTemplate.apply_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(ModalTemplate.CARD_WIDTH, 0)
	var card_sb := ModalTemplate.make_card_style(ModalTemplate.ThemeKind.SONAR)
	frame.add_theme_stylebox_override("panel", card_sb)
	center.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	frame.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text = "UNSAVED CHANGES"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	header.add_child(title_lbl)

	var close_dialog := func():
		if _confirm_dialog == null or not is_instance_valid(_confirm_dialog):
			return
		var close_tw := root.create_tween().set_parallel(true)
		close_tw.tween_property(root, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.tween_property(frame, "scale", Vector2(0.95, 0.95), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		close_tw.chain().tween_callback(func():
			if root != null and is_instance_valid(root):
				root.queue_free()
			_confirm_dialog = null
		)

	var close_btn := ModalTemplate.make_close_button(close_dialog, ModalTemplate.ThemeKind.SONAR)
	header.add_child(close_btn)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(0.25, 0.55, 0.85, 0.35)
	vbox.add_child(divider)

	var msg_lbl := Label.new()
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.88, 0.94, 0.98, 0.95))
	msg_lbl.text = "You have modified button positions or scale in the HUD layout.\n\nExiting now will discard your adjustments. Would you like to save your changes before leaving?"
	vbox.add_child(msg_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var discard_btn := Button.new()
	discard_btn.text = "DISCARD CHANGES"
	discard_btn.custom_minimum_size = Vector2(160, 42)
	discard_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_danger_button(discard_btn, false, false)
	discard_btn.pressed.connect(func():
		var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
		if sfx != null and is_instance_valid(sfx):
			sfx.play_deny_tick()
		_confirm_dialog = null
		root.queue_free()
		_close()
	)
	btn_row.add_child(discard_btn)

	var save_btn := Button.new()
	save_btn.text = "SAVE & EXIT"
	save_btn.custom_minimum_size = Vector2(140, 42)
	save_btn.focus_mode = Control.FOCUS_NONE
	ModalTemplate.style_button(save_btn, true, ModalTemplate.ThemeKind.SONAR)
	save_btn.pressed.connect(func():
		_confirm_dialog = null
		root.queue_free()
		_on_save_pressed()
	)
	btn_row.add_child(save_btn)

	# Smooth entry pop animation
	root.modulate.a = 0.0
	frame.scale = Vector2(0.94, 0.94)
	frame.pivot_offset = Vector2(ModalTemplate.CARD_WIDTH * 0.5, 110.0)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_cancel_pressed() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		_confirm_dialog.queue_free()
		_confirm_dialog = null
		return
	if _has_unsaved_changes():
		_show_unsaved_changes_confirm()
		return
	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_pact_reroll()
	_close()


func _on_save_pressed() -> void:
	# Commit ONLY elements that were actually modified by the player
	var final_layout: Dictionary = {}
	for id: String in _modified_elements:
		if _elements.has(id):
			final_layout[id] = _elements[id]["data"].duplicate()

	GameState.custom_hud_layout = final_layout
	GameState.save_settings()

	# Live-apply to running HUD if currently in a level
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("apply_custom_hud_layout"):
		hud.apply_custom_hud_layout()

	var sfx := get_tree().get_first_node_in_group("sfx_manager") as SfxManager
	if sfx != null and is_instance_valid(sfx):
		sfx.play_pact_seal()

	_close()


func _close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		var parent_node := get_parent()
		if parent_node is CanvasLayer and parent_node.name == "HudCustomizerCanvas":
			parent_node.queue_free()
		else:
			queue_free()
		emit_signal("closed")
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
