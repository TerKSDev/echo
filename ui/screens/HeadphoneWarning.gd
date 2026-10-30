extends Control

@onready var content: Control = $Content
@onready var headphone_icon: Control = $Content/IconCenter/HeadphoneIcon

var _transitioning := false
var _permission_pending := false
var _warning_started := false
var _time := 0.0

func _ready() -> void:
	content.modulate.a = 0.0
	headphone_icon.draw.connect(_draw_headphone_icon)

	if OS.get_name() == "Android":
		if not GameState.is_mic_permission_granted() and not GameState.mic_permission_prompted:
			# First-time boot: request permission
			_permission_pending = true
			GameState.request_mic_permission(func(_granted: bool) -> void:
				_permission_pending = false
				_start_headphone_warning()
			)
		else:
			# If permission was revoked in Android OS settings, safely reflect it
			if not GameState.is_mic_permission_granted():
				GameState.mic_enabled = false
			# If permission is granted, respect the player's saved GameState.mic_enabled!
			_start_headphone_warning()
	else:
		_start_headphone_warning()

func _start_headphone_warning() -> void:
	if _warning_started or _transitioning:
		return
	_warning_started = true

	var tw := create_tween()
	# 1. Subtle smooth fade-in (0.6s)
	tw.tween_property(content, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Comfortable short display (1.8s)
	tw.tween_interval(1.8)
	# 3. Fade out into pitch black (0.6s)
	tw.tween_property(content, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 4. Smooth transition to Main Menu
	tw.tween_callback(_go_to_menu)

func _process(delta: float) -> void:
	_time += delta
	if headphone_icon != null:
		headphone_icon.queue_redraw()

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

	# 6. Sleek animated acoustic ripples beaming from both sides
	for i in 2:
		var phase := fposmod(_time * 0.9 + float(i) * 0.5, 1.0)
		var r := lerpf(7.0, 21.0, phase)
		var a := sin(phase * PI) * 0.78
		var w := lerpf(2.0, 1.2, phase)
		headphone_icon.draw_arc(center + Vector2(-42.0, 14.0), r, PI * 0.74, PI * 1.26, 16, Color(0.4, 0.88, 1.0, a), w)
		headphone_icon.draw_arc(center + Vector2(42.0, 14.0), r, -PI * 0.26, PI * 0.26, 16, Color(0.4, 0.88, 1.0, a), w)

func _gui_input(event: InputEvent) -> void:
	if _permission_pending or not _warning_started:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_go_to_menu()

func _unhandled_input(event: InputEvent) -> void:
	if _permission_pending or not _warning_started:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE)):
		get_viewport().set_input_as_handled()
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

	get_tree().change_scene_to_file("res://ui/screens/menu.tscn")

	var fade_tw := curtain.create_tween()
	fade_tw.tween_interval(0.1)
	fade_tw.tween_property(curtain, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_tw.tween_callback(curtain.queue_free)
