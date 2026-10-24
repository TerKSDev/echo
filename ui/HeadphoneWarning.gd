extends Control

@onready var content: Control = $Content
@onready var headphone_icon: Control = $Content/IconCenter/HeadphoneIcon

var _transitioning := false

func _ready() -> void:
	content.modulate.a = 0.0
	headphone_icon.draw.connect(_draw_headphone_icon)

	var tw := create_tween()
	# 1. Subtle smooth fade-in (0.6s)
	tw.tween_property(content, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Comfortable short display (1.8s)
	tw.tween_interval(1.8)
	# 3. Fade out into pitch black (0.6s)
	tw.tween_property(content, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 4. Smooth transition to Main Menu
	tw.tween_callback(_go_to_menu)

func _draw_headphone_icon() -> void:
	var center := Vector2(48.0, 48.0)
	var main_col := Color(0.85, 0.95, 1.0, 0.95)
	var glow_col := Color(0.35, 0.75, 1.0, 0.35)
	var pad_col := Color(0.18, 0.42, 0.65, 0.85)

	# 1. Subtle soft glow around headphones
	headphone_icon.draw_circle(center, 44.0, Color(0.15, 0.55, 0.9, 0.08))

	# 2. Outer Headband (smooth double-arc with gradient thickness)
	headphone_icon.draw_arc(center + Vector2(0.0, 4.0), 32.0, PI + 0.12, TAU - 0.12, 40, glow_col, 5.0)
	headphone_icon.draw_arc(center + Vector2(0.0, 4.0), 32.0, PI + 0.12, TAU - 0.12, 40, main_col, 2.6)

	# 3. Headband top padding cushion
	headphone_icon.draw_arc(center + Vector2(0.0, 4.0), 34.0, PI * 1.25, PI * 1.75, 24, Color(main_col.r, main_col.g, main_col.b, 0.65), 1.5)

	# 4. Metal Yoke / Swivel forks
	headphone_icon.draw_line(center + Vector2(-31.0, 2.0), center + Vector2(-31.0, 14.0), main_col, 2.0)
	headphone_icon.draw_line(center + Vector2(31.0, 2.0), center + Vector2(31.0, 14.0), main_col, 2.0)

	# 5. Over-ear Cushioned Ear Cups (rounded capsule with inner & outer shell)
	var cup_w := 12.0
	var cup_h := 28.0
	var left_rect := Rect2(center + Vector2(-37.0, 0.0), Vector2(cup_w, cup_h))
	var right_rect := Rect2(center + Vector2(25.0, 0.0), Vector2(cup_w, cup_h))

	# Outer cup bodies
	headphone_icon.draw_rect(left_rect, pad_col, true)
	headphone_icon.draw_rect(left_rect, main_col, false, 2.0)
	headphone_icon.draw_rect(right_rect, pad_col, true)
	headphone_icon.draw_rect(right_rect, main_col, false, 2.0)

	# Inner core sound chambers
	headphone_icon.draw_rect(Rect2(center + Vector2(-34.0, 4.0), Vector2(6.0, 20.0)), Color(0.05, 0.18, 0.32, 0.9), true)
	headphone_icon.draw_rect(Rect2(center + Vector2(28.0, 4.0), Vector2(6.0, 20.0)), Color(0.05, 0.18, 0.32, 0.9), true)

	# 6. Sleek acoustic ripples beaming from both sides
	headphone_icon.draw_arc(center + Vector2(-42.0, 14.0), 9.0, PI * 0.72, PI * 1.28, 16, Color(0.4, 0.88, 1.0, 0.75), 1.8)
	headphone_icon.draw_arc(center + Vector2(-42.0, 14.0), 16.0, PI * 0.78, PI * 1.22, 16, Color(0.4, 0.88, 1.0, 0.35), 1.4)
	headphone_icon.draw_arc(center + Vector2(42.0, 14.0), 9.0, -PI * 0.28, PI * 0.28, 16, Color(0.4, 0.88, 1.0, 0.75), 1.8)
	headphone_icon.draw_arc(center + Vector2(42.0, 14.0), 16.0, -PI * 0.22, PI * 0.22, 16, Color(0.4, 0.88, 1.0, 0.35), 1.4)

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_go_to_menu()

func _go_to_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color.BLACK
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain.top_level = true
	curtain.z_index = 4096

	var root := get_tree().root
	root.add_child(curtain)

	get_tree().change_scene_to_file("res://ui/menu.tscn")

	var fade_tw := curtain.create_tween()
	fade_tw.tween_interval(0.1)
	fade_tw.tween_property(curtain, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_tw.tween_callback(curtain.queue_free)
