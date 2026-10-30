extends Button

var _press_scale := 1.0
var base_scale := 1.0

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pivot_offset = size * 0.5
	button_down.connect(_on_down)
	button_up.connect(_on_up)

func _on_down() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 0.9, 0.08).set_trans(Tween.TRANS_SINE)

func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press_scale", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	scale = Vector2(_press_scale * base_scale, _press_scale * base_scale)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var is_chal: bool = (GameState.current_mode == GameState.GameMode.CHALLENGE)

	# 1. Outer subtle halo
	var halo_col := Color(0.85, 0.20, 0.65, 0.14) if is_chal else Color(0.12, 0.45, 0.8, 0.12)
	draw_circle(center, radius + 3.0, halo_col)

	# 2. Cavern dark glass disc
	var disc_col := Color(0.16, 0.03, 0.13, 0.85) if is_chal else Color(0.04, 0.12, 0.22, 0.8)
	var inner_col := Color(0.25, 0.05, 0.20, 0.40) if is_chal else Color(0.08, 0.2, 0.35, 0.3)
	draw_circle(center, radius, disc_col)
	draw_circle(center, radius * 0.8, inner_col)

	# 3. Outer Rim
	var rim_col := Color(0.88, 0.32, 0.78, 0.85) if is_chal else Color(0.35, 0.65, 0.95, 0.85)
	draw_arc(center, radius, 0.0, TAU, 36, rim_col, 1.6)

	# 4. Pause Bars Icons (Two sleek vertical bars)
	var bar_w := 3.2
	var bar_h := 14.0
	var bar_gap := 4.5
	var col := Color(0.98, 0.90, 0.96, 0.92) if is_chal else Color(0.85, 0.94, 1.0, 0.9)

	draw_line(
		Vector2(center.x - bar_gap, center.y - bar_h * 0.5),
		Vector2(center.x - bar_gap, center.y + bar_h * 0.5),
		col,
		bar_w
	)
	draw_line(
		Vector2(center.x + bar_gap, center.y - bar_h * 0.5),
		Vector2(center.x + bar_gap, center.y + bar_h * 0.5),
		col,
		bar_w
	)
