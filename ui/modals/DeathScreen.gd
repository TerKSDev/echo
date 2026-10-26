extends Control
## Atmospheric "SILENCED" death overlay with a live flatlining acoustic waveform,
## killer monster identification + survival tip, and Try Again / Main Menu actions.

@onready var wave_canvas: Control = $CenterContainer/Panel/VBox/WaveCanvas
@onready var killer_dot: ColorRect = $CenterContainer/Panel/VBox/TipBox/HBox/KillerDot
@onready var killer_label: Label = $CenterContainer/Panel/VBox/TipBox/HBox/TextVBox/KillerLabel
@onready var tip_label: Label = $CenterContainer/Panel/VBox/TipBox/HBox/TextVBox/TipLabel
@onready var retry_btn: Button = $CenterContainer/Panel/VBox/Actions/RetryBtn
@onready var menu_btn: Button = $CenterContainer/Panel/VBox/Actions/MenuBtn
@onready var panel: PanelContainer = $CenterContainer/Panel

const KILLER_INFO: Array[Dictionary] = [
	{
		"name": "HUNTED BY: SLEEPER",
		"color": Color(0.68, 0.42, 0.98),
		"tip": "Sleepers awaken when you walk loudly or step too close. Sneak past them at a safe distance.",
	},
	{
		"name": "HUNTED BY: PATROLLER",
		"color": Color(1.0, 0.82, 0.25),
		"tip": "Patrollers have acute hearing and can detect even sneaking nearby. Wait behind walls for them to pass.",
	},
	{
		"name": "HUNTED BY: CHASER",
		"color": Color(1.0, 0.22, 0.22),
		"tip": "Chasers outrun normal footsteps, but they are completely deaf to sneaking ([SHIFT]).",
	},
	{
		"name": "HUNTED BY: SCREAMER",
		"color": Color(0.95, 0.28, 0.72),
		"tip": "Take cover behind a solid wall before the Screamer's 2nd sonic shriek hits you.",
	},
	{
		"name": "HUNTED BY: LISTENER",
		"color": Color(0.2, 0.94, 0.68),
		"tip": "Listeners ignore footsteps, but 5 shouts trigger a map-wide alarm that summons every monster.",
	},
]

var _is_open := false
var _anim_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	wave_canvas.draw.connect(_draw_flatline_wave)
	retry_btn.pressed.connect(_on_retry_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	for b: Button in [retry_btn, menu_btn]:
		b.mouse_entered.connect(func():
			b.pivot_offset = b.size * 0.5
			create_tween().tween_property(b, "scale", Vector2(1.02, 1.02), 0.08)
		)
		b.mouse_exited.connect(func():
			b.pivot_offset = b.size * 0.5
			create_tween().tween_property(b, "scale", Vector2.ONE, 0.1)
		)
		b.button_down.connect(func():
			b.pivot_offset = b.size * 0.5
			create_tween().tween_property(b, "scale", Vector2(0.96, 0.96), 0.05)
		)
		b.button_up.connect(func():
			b.pivot_offset = b.size * 0.5
			create_tween().tween_property(b, "scale", Vector2(1.02, 1.02), 0.1)
		)


func _process(delta: float) -> void:
	if not _is_open:
		return
	_anim_time += delta
	wave_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _anim_time < 0.25:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R):
		get_viewport().set_input_as_handled()
		_on_retry_pressed()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_menu_pressed()


func open(killer_type: int = -1) -> void:
	if _is_open:
		return
	_is_open = true
	_anim_time = 0.0
	visible = true
	get_tree().paused = true

	if killer_type >= 0 and killer_type < KILLER_INFO.size():
		var info: Dictionary = KILLER_INFO[killer_type]
		var col: Color = info["color"]
		killer_dot.color = col
		killer_label.text = String(info["name"])
		killer_label.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
		tip_label.text = String(info["tip"])
	else:
		killer_dot.color = Color(1.0, 0.28, 0.32)
		killer_label.text = "DEVOURED BY THE ABYSS"
		killer_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.58))
		tip_label.text = "Every sound illuminates the cave, yet draws the attention of what lurks in the dark."

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = Vector2(230.0, 210.0)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Draws an acoustic pulse that decays into a crimson flatline
func _draw_flatline_wave() -> void:
	var w: float = wave_canvas.size.x
	var h: float = wave_canvas.size.y
	var mid_y: float = h * 0.5
	var segs := 64
	var pts := PackedVector2Array()
	pts.resize(segs + 1)

	# Decay factor: starts with a dying spike, settles into a faint trembling flatline
	var decay: float = exp(-_anim_time * 1.6)
	var scan_x: float = fmod(_anim_time * 140.0, maxf(w, 1.0))

	for i in range(segs + 1):
		var frac: float = float(i) / float(segs)
		var x: float = frac * w
		var center_env: float = sin(frac * PI)
		var burst: float = sin(frac * TAU * 4.0 - _anim_time * 12.0) * 18.0 * decay * center_env
		var tremor: float = sin(frac * 35.0 + _anim_time * 8.0) * 1.2 * center_env
		pts[i] = Vector2(x, mid_y + burst + tremor)

	wave_canvas.draw_polyline(pts, Color(1.0, 0.22, 0.28, 0.28), 4.0)
	wave_canvas.draw_polyline(pts, Color(1.0, 0.42, 0.46, 0.9), 1.8)
	wave_canvas.draw_circle(Vector2(scan_x, mid_y), 3.0, Color(1.0, 0.75, 0.78, 0.85))


func _on_retry_pressed() -> void:
	GameState.restart_level()


func _on_menu_pressed() -> void:
	GameState.go_to_level_select()
