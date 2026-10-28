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

	# 1. Outer subtle halo
	draw_circle(center, radius + 3.0, Color(0.12, 0.45, 0.8, 0.12))

	# 2. Cavern dark glass disc
	draw_circle(center, radius, Color(0.04, 0.12, 0.22, 0.8))
	draw_circle(center, radius * 0.8, Color(0.08, 0.2, 0.35, 0.3))

	# 3. Outer Rim
	draw_arc(center, radius, 0.0, TAU, 36, Color(0.35, 0.65, 0.95, 0.85), 1.6)

	# 4. Pause Bars Icons (Two sleek vertical bars)
	var bar_w := 3.2
	var bar_h := 14.0
	var bar_gap := 4.5
	var col := Color(0.85, 0.94, 1.0, 0.9)

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
