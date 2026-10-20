extends CanvasLayer

@onready var player = get_node_or_null("../Player")

var _base_inner_radius := 0.42
var _sector_badge: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sector_badge()
	var mat := _vignette_material()
	if mat != null:
		mat.set_shader_parameter("vignette_color", Color(0.01, 0.035, 0.07, 0.7))
		mat.set_shader_parameter("inner_radius", _base_inner_radius)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player != null:
		$SoundBtn.button_down.connect(player.start_charge)
		$SoundBtn.button_up.connect(player.release_charge)
		$SneakBtn.pressed.connect(player.toggle_sneak)
		if player.has_node("MicInput"):
			var mic = player.get_node("MicInput")
			if mic != null and mic.has_signal("voice_detected"):
				mic.voice_detected.connect(_on_voice_detected)

	if has_node("PauseBtn") and has_node("SettingsModal"):
		$PauseBtn.pressed.connect($SettingsModal.open)

func _on_voice_detected(_loudness: float) -> void:
	if has_node("MicIndicator"):
		$MicIndicator.pulse_flash()

# Vignette tightens on every heartbeat; stronger when more threatened
func pulse_vignette(threat: float) -> void:
	if threat < 0.2:
		return
	var mat := _vignette_material()
	if mat == null:
		return
	var pulse_r := clampf(_base_inner_radius - 0.12 * threat, 0.18, _base_inner_radius)
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/inner_radius", pulse_r, 0.08)
	tw.tween_property(mat, "shader_parameter/inner_radius", _base_inner_radius, 0.28)

# Crimson flash when the player dies
func flash_death() -> void:
	var mat := _vignette_material()
	if mat == null:
		return
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.65, 0.05, 0.08, 0.95), 0.08)
	tw.tween_property(mat, "shader_parameter/vignette_color", Color(0.28, 0.02, 0.04, 0.85), 0.6)

func show_death_screen(killer_type: int = -1) -> void:
	if has_node("SettingsModal") and $SettingsModal.visible:
		$SettingsModal.visible = false
	if _sector_badge != null:
		_sector_badge.visible = false
	if has_node("PauseBtn"):
		$PauseBtn.visible = false
	if has_node("SneakBtn"):
		$SneakBtn.visible = false
	if has_node("SoundBtn"):
		$SoundBtn.visible = false
	if has_node("DeathScreen"):
		$DeathScreen.open(killer_type)


func _build_sector_badge() -> void:
	_sector_badge = Label.new()
	_sector_badge.position = Vector2(38.0, 52.0)
	_sector_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sector_badge.add_theme_color_override("font_color", Color(0.45, 0.78, 0.98, 0.55))
	_sector_badge.add_theme_font_size_override("font_size", 12)
	_sector_badge.text = "◈  SECTOR"
	add_child(_sector_badge)


# Atmospheric fade-from-black + sonar title banner on level entry
func play_level_intro(title_text: String, subtitle_text: String = "Listen closely. Stay unseen.") -> void:
	if _sector_badge != null:
		_sector_badge.text = "◈  " + title_text
	# 1. Fullscreen abyss curtain fading out smoothly
	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.color = Color(0.0, 0.015, 0.035, 1.0)
	add_child(curtain)

	var c_tw := create_tween()
	c_tw.tween_property(curtain, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c_tw.tween_callback(curtain.queue_free)

	# 2. Floating sonar sector banner (non-blocking)
	var banner := VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 155.0
	banner.offset_left = -220.0
	banner.offset_right = 220.0
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", 6)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	add_child(banner)

	var tag := Label.new()
	tag.text = "((   A C O U S T I C   D E S C E N T   ))"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_color_override("font_color", Color(0.38, 0.85, 1.0, 0.82))
	tag.add_theme_font_size_override("font_size", 11)
	banner.add_child(tag)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.45, 0.82, 0.65))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_font_size_override("font_size", 32)
	banner.add_child(title_lbl)

	var line_holder := CenterContainer.new()
	line_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(line_holder)

	var scan_line := ColorRect.new()
	scan_line.custom_minimum_size = Vector2(16.0, 2.0)
	scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan_line.color = Color(0.38, 0.9, 1.0, 0.85)
	line_holder.add_child(scan_line)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle_text
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.84, 0.96, 0.8))
	sub_lbl.add_theme_font_size_override("font_size", 13)
	banner.add_child(sub_lbl)

	var b_tw := create_tween()
	b_tw.set_parallel(true)
	b_tw.tween_property(banner, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(banner, "offset_top", 138.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b_tw.tween_property(scan_line, "custom_minimum_size:x", 240.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var out_tw := create_tween()
	out_tw.tween_interval(1.65)
	out_tw.tween_property(banner, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tw.tween_callback(banner.queue_free)

func _vignette_material() -> ShaderMaterial:
	var vig := get_node_or_null("Vignette") as ColorRect
	if vig == null:
		return null
	return vig.material as ShaderMaterial