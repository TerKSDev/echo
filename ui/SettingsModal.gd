extends Control

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var volume_slider: HSlider = $CenterContainer/Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_val: Label = $CenterContainer/Panel/VBox/VolumeHeader/VolumeVal
@onready var mic_toggle: Button = $CenterContainer/Panel/VBox/MicRow/MicToggle
@onready var resume_btn: Button = $CenterContainer/Panel/VBox/Actions/ResumeBtn
@onready var restart_btn: Button = $CenterContainer/Panel/VBox/Actions/RestartBtn
@onready var menu_btn: Button = $CenterContainer/Panel/VBox/Actions/MenuBtn
@onready var close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseBtn

var _is_open := false
var _player: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0

	# Setup volume from Master bus
	var bus_idx := AudioServer.get_bus_index("Master")
	var current_vol := db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	volume_slider.value = current_vol
	_update_volume_label(current_vol)

	volume_slider.value_changed.connect(_on_volume_changed)
	mic_toggle.pressed.connect(_on_mic_toggle_pressed)
	resume_btn.pressed.connect(close)
	restart_btn.pressed.connect(_on_restart_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	close_btn.pressed.connect(close)

	_player = get_tree().get_first_node_in_group("player")
	_update_mic_toggle_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	get_tree().paused = true

	_player = get_tree().get_first_node_in_group("player")
	_update_mic_toggle_ui()

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5 if panel.size.x > 50.0 else Vector2(240.0, 260.0)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close() -> void:
	if not _is_open:
		return
	_is_open = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	get_tree().paused = false

func _on_volume_changed(val: float) -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val))
	_update_volume_label(val)

func _update_volume_label(val: float) -> void:
	var pct := int(round(val * 100.0))
	volume_val.text = "%d%%" % pct

func _on_mic_toggle_pressed() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player) and _player.has_node("MicInput"):
		var mic = _player.get_node("MicInput")
		mic.enabled = not mic.enabled
	_update_mic_toggle_ui()

func _update_mic_toggle_ui() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var enabled := true
	if _player != null and is_instance_valid(_player) and _player.has_node("MicInput"):
		var mic = _player.get_node("MicInput")
		enabled = mic.enabled
	
	if enabled:
		mic_toggle.text = "ENABLED"
		mic_toggle.self_modulate = Color(0.35, 1.2, 1.8, 1.0)
	else:
		mic_toggle.text = "MUTED"
		mic_toggle.self_modulate = Color(0.7, 0.7, 0.7, 0.7)

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
