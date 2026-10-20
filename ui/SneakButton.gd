extends Button

var _player: Node = null
var _press_scale := 1.0
var _timer := 0.0

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pivot_offset = Vector2(size.x * 0.5, 48.0)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	_player = get_tree().get_first_node_in_group("player")

func _on_down() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 0.92, 0.08).set_trans(Tween.TRANS_SINE)

func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_timer += delta
	scale = Vector2(_press_scale, _press_scale)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 48.0)
	var radius := 44.0
	var is_sneaking := false
	if _player != null and is_instance_valid(_player):
		is_sneaking = bool(_player.get("sneaking"))

	if is_sneaking:
		# --- Active Sneak State: Luminous breathing glow ---
		var pulse := 0.5 + 0.5 * sin(_timer * 3.5)
		# Outer pulsing aura
		draw_circle(center, radius + 4.0 + 3.0 * pulse, Color(0.18, 0.65, 1.0, 0.15 + 0.12 * pulse))
		# Luminous glass disc
		draw_circle(center, radius, Color(0.06, 0.22, 0.36, 0.9))
		# Vibrant cyan border rim
		draw_arc(center, radius, 0.0, TAU, 40, Color(0.38, 0.88, 1.0, 0.95), 2.2)

		# Center Icon: Soft footprint/dampener lines in bright cyan
		var icon_col := Color(0.5, 0.95, 1.0, 1.0)
		_draw_stealth_icon(center, icon_col)

		# Label with ample padding below the circle
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 114.0), "SNEAKING", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 11, Color(0.5, 0.95, 1.0, 0.95))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 127.0), "[SHIFT]", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 9, Color(0.5, 0.95, 1.0, 0.45))
	else:
		# --- Normal Walk State: Discreet dark glass ---
		# Subtle glow
		draw_circle(center, radius + 3.0, Color(0.1, 0.35, 0.6, 0.1))
		# Dark cavern glass disc
		draw_circle(center, radius, Color(0.04, 0.11, 0.2, 0.72))
		# Subtle rim
		draw_arc(center, radius, 0.0, TAU, 40, Color(0.24, 0.48, 0.72, 0.55), 1.6)

		# Center Icon in dim ice blue
		var icon_col := Color(0.7, 0.85, 0.98, 0.6)
		_draw_stealth_icon(center, icon_col)

		# Label with ample padding below the circle
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 114.0), "SNEAK", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 11, Color(0.48, 0.72, 0.92, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 127.0), "[SHIFT]", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), 9, Color(0.48, 0.72, 0.92, 0.4))

func _draw_stealth_icon(center: Vector2, col: Color) -> void:
	# Stylized Sound Dampener: 3 curved horizontal stealth ripples with a center mute bar
	# Top arc
	draw_arc(center + Vector2(0, -9), 10.0, PI * 0.2, PI * 0.8, 12, Color(col, 0.5), 1.6)
	# Middle arc
	draw_arc(center, 15.0, PI * 0.15, PI * 0.85, 16, col, 2.0)
	# Center silent footstep core
	draw_circle(center + Vector2(0, 4), 3.5, col)
	draw_arc(center + Vector2(0, 4), 8.0, -PI * 0.8, -PI * 0.2, 12, col, 1.8)
