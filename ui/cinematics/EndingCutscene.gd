extends Control
class_name EndingCutscene
## Grand First-Person Cinematic Ending Sequence for ECHO: STAY SILENT (Story Mode Level 20 Clear).
## Visual Flow:
## 1. Pure pitch-black void monologue (fully automatic, cannot skip or speed up).
## 2. Walking up a pitch-black narrow passage in first person:
##    - Background is 100% black (no pictures, no light beams).
##    - Starts with slow, cautious footsteps, accelerating into a full sprint towards the light.
##    - Light is a realistic distant opening with natural atmospheric diffusion & anamorphic bloom,
##      slowly growing bigger and brighter as you approach, until blinding white engulfs the screen.
##    - No BGM during the run; pure footsteps echoing in the dark.
## 3. Reaching the surface (到达地面):
##    - BGM starts at the moment the Dawn image appears.
##    - Dawn image starts at maximum zoom (2.4x) and smoothly pulls back to 1.0x (covering full screen).
##    - Pauses for 2.0s so the player can take a breather and admire the sunrise vista.
##    - "ECHO: STAY SILENT" slowly fades in, enlarged to fill almost the entire screen width, with NO subtitle.
##    - Holds for 1.8s, then background slowly dims to pure black while keeping the title.
##    - Seamless handover to rolling credits (with identical title styling and continuous Dawn BGM).
## 4. Main Menu return flags unified Challenge Abyss unlock modal.

const MIX_RATE := 44100
const RUN_DURATION := 9.5 # 9.5s total climb from slow walk to fast run

var bg_void: ColorRect = null
var light_canvas: Control = null
var bg_dawn: TextureRect = null
var white_veil: ColorRect = null
var black_veil: ColorRect = null

var title_box: VBoxContainer = null
var title_label: Label = null

var dialogue_center: CenterContainer = null
var dialogue_label: Label = null

var particle_layer: Control = null

var _time := 0.0
var _phase := 0 # 0=Black monologue, 1=Tunnel acceleration, 2=Dawn vista slam, 3=Title reveal, 4=Dim to black, 5=Credits, 6=Exit

# Running towards light parameters
var _walk_time := 0.0
var _step_phase := 0.0
var _last_step_int := -1
var _bob_y := 0.0
var _sway_x := 0.0

# Audio Players
var _dawn_bgm_player: AudioStreamPlayer
var _bird_player: AudioStreamPlayer
var _bird_timer := 1.2
var _step_players: Array[AudioStreamPlayer] = []
var _step_idx := 0
var _stone_step_wavs: Array[AudioStreamWAV] = []

var _sun_particles: Array[Dictionary] = []

# Monologue lines
var _mono_lines: Array[String] = [
	"Wait... What is that?",
	"Light...? Real light?",
	"The passage is ascending... toward the surface."
]
var _mono_idx := 0


static func start_ending(parent: Node) -> EndingCutscene:
	var cutscene := EndingCutscene.new()
	cutscene.name = "EndingCutscene"
	cutscene.set_anchors_preset(Control.PRESET_FULL_RECT)
	cutscene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene.z_index = 500
	parent.add_child(cutscene)
	return cutscene


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_init_particles()
	_setup_audio()
	_start_phase_0()


func _setup_audio() -> void:
	# Surface Dawn Melodic BGM (Starts only when Dawn image is revealed)
	_dawn_bgm_player = AudioStreamPlayer.new()
	_dawn_bgm_player.name = "DawnBgmPlayer"
	_dawn_bgm_player.stream = SfxManager.get_surface_dawn_bgm_pad()
	_dawn_bgm_player.bus = &"BGM"
	_dawn_bgm_player.volume_db = -5.0
	add_child(_dawn_bgm_player)

	# Morning Birdsong
	_bird_player = AudioStreamPlayer.new()
	_bird_player.name = "BirdPlayer"
	_bird_player.stream = SfxManager.get_birdsong_sfx()
	_bird_player.bus = &"SFX"
	_bird_player.volume_db = -8.5
	add_child(_bird_player)

	# Stone footsteps for the tunnel run
	for i in 3:
		_stone_step_wavs.append(_synth_stone_step(i))

	for i in 4:
		var p := AudioStreamPlayer.new()
		p.name = "StoneStepPlayer%d" % i
		p.bus = &"SFX"
		p.volume_db = -7.0
		add_child(p)
		_step_players.append(p)


func _build_ui() -> void:
	var vp_w: float = size.x if size.x > 100.0 else 720.0
	var vp_h: float = size.y if size.y > 100.0 else 1280.0

	# 1. Base Pitch-Black Void (Zero pictures, 100% black)
	bg_void = ColorRect.new()
	bg_void.name = "BgVoid"
	bg_void.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_void.color = Color(0.01, 0.015, 0.02, 1.0)
	bg_void.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_void)

	# 2. Light Canvas (Photorealistic atmospheric light opening growing in the dark)
	light_canvas = Control.new()
	light_canvas.name = "LightCanvas"
	light_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	light_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light_canvas.draw.connect(_draw_realistic_light)
	light_canvas.visible = false
	add_child(light_canvas)

	# 3. Surface Dawn Horizon Vista
	bg_dawn = TextureRect.new()
	bg_dawn.name = "BgDawn"
	bg_dawn.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_dawn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_dawn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_dawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_dawn.pivot_offset = Vector2(vp_w * 0.5, vp_h * 0.42)
	bg_dawn.texture = _load_texture("res://assets/bg_surface_dawn.jpg")
	bg_dawn.modulate.a = 0.0
	add_child(bg_dawn)

	# 4. Floating Sun Dust Particles (Active only on surface)
	particle_layer = Control.new()
	particle_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	particle_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	particle_layer.draw.connect(_draw_particles)
	add_child(particle_layer)

	# 5. Black Veil (Dims dawn vista to black while retaining title)
	black_veil = ColorRect.new()
	black_veil.name = "BlackVeil"
	black_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_veil.color = Color(0.01, 0.015, 0.02, 0.0)
	black_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black_veil)

	# 6. Title Card Box (Enlarged to almost fill the screen width, pure title, NO subtitle)
	title_box = VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.set_anchors_preset(Control.PRESET_CENTER)
	title_box.offset_left = -340.0
	title_box.offset_top = -60.0
	title_box.offset_right = 340.0
	title_box.offset_bottom = 60.0
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.modulate.a = 0.0
	add_child(title_box)

	title_label = Label.new()
	title_label.text = "ECHO: STAY SILENT"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 50)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(0.85, 0.65, 0.20, 0.60))
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(title_label)

	# 7. Blinding White Bloom Veil
	white_veil = ColorRect.new()
	white_veil.name = "WhiteVeil"
	white_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	white_veil.color = Color(1.0, 0.98, 0.92, 0.0)
	white_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(white_veil)

	# 8. Monologue Layer in Pure Darkness (Screen-centered text)
	dialogue_center = CenterContainer.new()
	dialogue_center.name = "DialogueCenter"
	dialogue_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialogue_center)

	dialogue_label = Label.new()
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialogue_label.add_theme_font_size_override("font_size", 21)
	dialogue_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.95))
	dialogue_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.90))
	dialogue_label.add_theme_constant_override("shadow_offset_y", 2)
	dialogue_label.modulate.a = 0.0
	dialogue_center.add_child(dialogue_label)


func _load_texture(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Texture2D:
			return res
	var global_path := ProjectSettings.globalize_path(res_path)
	var img := Image.new()
	var err := img.load(global_path)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null


func _init_particles() -> void:
	var vp_w: float = size.x if size.x > 100.0 else 720.0
	var vp_h: float = size.y if size.y > 100.0 else 1280.0
	for i in 40:
		_sun_particles.append({
			"pos": Vector2(randf_range(30.0, vp_w - 30.0), randf_range(50.0, vp_h - 50.0)),
			"r": randf_range(1.6, 3.8),
			"speed": randf_range(22.0, 48.0),
			"phase": randf() * TAU,
			"alpha": randf_range(0.35, 0.85)
		})


func _process(delta: float) -> void:
	_time += delta

	# Phase 1: Accelerating from Slow Walk to Full Sprint Toward the Light
	if _phase == 1:
		_walk_time += delta
		var prog: float = clampf(_walk_time / RUN_DURATION, 0.0, 1.0)

		# Step frequency accelerates over time: from slow walk (1.1 steps/s) to full sprint (4.6 steps/s)
		var step_rate: float = lerpf(1.1, 4.6, pow(prog, 1.55))
		_step_phase += step_rate * delta

		# Camera bobbing & sway: amplitude increases as player breaks into a run
		var bob_amp: float = lerpf(6.0, 14.5, prog)
		var sway_amp: float = lerpf(2.8, 7.5, prog)
		_bob_y = sin(_step_phase * TAU) * bob_amp
		_sway_x = sin(_step_phase * PI) * sway_amp

		# Trigger footsteps on step contact (frequency accelerates naturally)
		var step_int := int(_step_phase)
		if step_int > _last_step_int:
			_last_step_int = step_int
			_play_accelerating_step(prog)

		# Redraw photorealistic light aperture
		if light_canvas != null:
			light_canvas.queue_redraw()

		# Final bloom into blinding white as player reaches the aperture (last 1.8s)
		if _walk_time >= RUN_DURATION - 1.8:
			var white_t: float = (_walk_time - (RUN_DURATION - 1.8)) / 1.8
			white_veil.color.a = clampf(pow(white_t, 1.4), 0.0, 1.0)

		if prog >= 1.0:
			_start_phase_2()

	# Process floating sun particles on surface
	if _phase >= 2:
		var vp_w: float = size.x if size.x > 100.0 else 720.0
		var vp_h: float = size.y if size.y > 100.0 else 1280.0
		for p in _sun_particles:
			var pos: Vector2 = p["pos"]
			pos.y -= float(p["speed"]) * delta
			pos.x += sin(_time * 1.5 + float(p["phase"])) * 14.0 * delta
			if pos.y < -20.0:
				pos.y = vp_h + 20.0
				pos.x = randf_range(30.0, vp_w - 30.0)
			p["pos"] = pos
		if particle_layer != null:
			particle_layer.queue_redraw()

	# Procedural morning birdsong chirps
	if _phase >= 2 and _phase < 5:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = randf_range(2.8, 5.2)
			if _bird_player != null and not _bird_player.playing:
				_bird_player.pitch_scale = randf_range(0.96, 1.08)
				_bird_player.volume_db = randf_range(-10.0, -7.0)
				_bird_player.play()

	# Gentle breathing on title glow
	if title_label != null and _phase >= 3:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
		title_label.modulate = Color(1.0, 1.0, 1.0, 0.92 + 0.08 * pulse)


func _play_accelerating_step(prog: float) -> void:
	if _step_players.is_empty() or _stone_step_wavs.is_empty():
		return
	var p := _step_players[_step_idx]
	_step_idx = (_step_idx + 1) % _step_players.size()
	p.stream = _stone_step_wavs[randi() % _stone_step_wavs.size()]
	# Footsteps get punchier and slightly higher pitched as running pace quickens
	p.pitch_scale = lerpf(0.92, 1.08, prog) + randf_range(-0.03, 0.03)
	p.volume_db = lerpf(-8.5, -4.5, prog)
	p.play()


# --- Phase 0: Pure Black Monologue (100% Automatic, Zero Images) -------------

func _start_phase_0() -> void:
	_phase = 0
	_mono_idx = 0
	var init_tw := create_tween()
	init_tw.tween_interval(1.0)
	init_tw.tween_callback(_play_next_monologue_line)


func _play_next_monologue_line() -> void:
	if _mono_idx >= _mono_lines.size():
		_start_phase_1()
		return

	dialogue_label.text = _mono_lines[_mono_idx]
	_mono_idx += 1

	var tw := create_tween()
	tw.tween_property(dialogue_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(2.2) # Hold line in center
	tw.tween_property(dialogue_label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.4)
	tw.tween_callback(_play_next_monologue_line)


# --- Phase 1: Walking Up the Pitch-Black Passage (Pure footsteps, NO BGM) ----

func _start_phase_1() -> void:
	_phase = 1
	_walk_time = 0.0
	_step_phase = 0.0
	_last_step_int = -1

	dialogue_center.visible = false
	light_canvas.visible = true


# --- Phase 2: Emerging on Surface (Dawn image zoom-out slam & rest) ----------

func _start_phase_2() -> void:
	_phase = 2
	light_canvas.visible = false

	# 1. Reveal Surface Dawn Vista at MAXIMUM ZOOM (2.4x)
	bg_dawn.modulate.a = 1.0
	bg_dawn.scale = Vector2(2.4, 2.4)

	# 2. START DAWN MELODIC BGM (Only now does the music begin!)
	if _dawn_bgm_player != null:
		_dawn_bgm_player.volume_db = -5.0
		_dawn_bgm_player.play()

	# First morning birdsong chirp
	get_tree().create_timer(0.8).timeout.connect(func():
		if _bird_player != null and not _bird_player.playing:
			_bird_player.play()
	)

	# 3. Pull back to original size (刚刚好覆盖全屏) over 1.2s
	var slam_tw := create_tween()
	slam_tw.set_parallel(true)
	slam_tw.tween_property(bg_dawn, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slam_tw.tween_property(white_veil, "color:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. PAUSE FOR 2.0 SECONDS: Let the player take a breather and admire the panoramic vista
	slam_tw.chain().tween_interval(2.0)
	slam_tw.tween_callback(_start_phase_3)


# --- Phase 3: Title Reveal (Enlarged, fills screen width, NO subtitle) -------

func _start_phase_3() -> void:
	_phase = 3
	var tw := create_tween()
	# Title slowly fades in over 2.0s
	tw.tween_property(title_box, "modulate:a", 1.0, 2.0).set_trans(Tween.TRANS_SINE)
	# Holds for 1.8s
	tw.tween_interval(1.8)
	tw.tween_callback(_start_phase_4)


# --- Phase 4: Dim Surface to Black (Slowly, keeping title in center) ---------

func _start_phase_4() -> void:
	_phase = 4
	# Over 2.5s, background slowly dims until pure black, title stays glowing!
	var tw := create_tween()
	tw.tween_property(black_veil, "color:a", 1.0, 2.5).set_trans(Tween.TRANS_SINE)
	# Hold on title in pure black for 1.0s
	tw.tween_interval(1.0)
	tw.tween_callback(_start_phase_5)


# --- Phase 5: Launch Movie Rolling End Credits (Dawn BGM continues seamlessly)

func _start_phase_5() -> void:
	_phase = 5
	var on_credits_done := func():
		_start_phase_6()
	# Handover to credits: play_audio=false because our _dawn_bgm_player keeps playing!
	EndCreditsRoll.show_credits(self, on_credits_done, false, true)
	title_box.visible = false


# --- Phase 6: Exit to Main Menu & Flag Challenge Unlock ---------------------

func _start_phase_6() -> void:
	_phase = 6
	GameState.story_completed = true
	GameState.challenge_unlocked = true
	GameState.pending_challenge_unlock_modal = true

	# Fade out Dawn BGM gently as we return to Main Menu
	if _dawn_bgm_player != null and _dawn_bgm_player.playing:
		var a_tw := create_tween()
		a_tw.tween_property(_dawn_bgm_player, "volume_db", -40.0, 1.2)

	GameState.go_to_menu()


# --- Visual Drawing: Photorealistic Atmospheric Light Opening ---------------

func _draw_realistic_light() -> void:
	if _phase != 1:
		return

	var vp_w: float = size.x if size.x > 100.0 else 720.0
	var vp_h: float = size.y if size.y > 100.0 else 1280.0

	var prog: float = clampf(_walk_time / RUN_DURATION, 0.0, 1.0)

	# Upward passage perspective: light opening is positioned above center, bobbing with steps
	var center_x: float = vp_w * 0.5 + _sway_x
	var center_y: float = vp_h * 0.38 + _bob_y
	var center := Vector2(center_x, center_y)

	# Aperture radius grows from tiny distant speck (2.5px) to screen-filling opening
	var core_r: float = lerpf(2.5, vp_w * 0.95, pow(prog, 2.8))
	var halo_r: float = lerpf(16.0, vp_w * 1.75, pow(prog, 1.9))

	# 1. Atmospheric Inverse-Square Volumetric Diffusion (36 fine translucent gradient layers)
	# Soft, continuous, photographic optical falloff with zero harsh steps
	var num_layers := 36
	for i in range(num_layers, 0, -1):
		var frac: float = float(i) / float(num_layers)
		var r_layer: float = halo_r * frac
		# Inverse-square optical density curve
		var density: float = 1.0 / (1.0 + pow(frac * 3.5, 2.0))
		var a_layer: float = density * lerpf(0.018, 0.055, prog)
		# Warm morning sky color gradient (amber on outskirts to golden-white near center)
		var col_layer := Color(1.0, 0.84, 0.55).lerp(Color(1.0, 0.96, 0.88), 1.0 - frac)
		col_layer.a = a_layer
		light_canvas.draw_circle(center, r_layer, col_layer)

	# 2. Cinematic Horizontal Anamorphic Lens Flare Bloom (Soft elliptical glow)
	if prog > 0.15:
		var flare_prog: float = (prog - 0.15) / 0.85
		var flare_w: float = halo_r * (1.8 + 0.8 * flare_prog)
		var flare_h: float = core_r * 1.5 + halo_r * 0.25
		for f in range(6, 0, -1):
			var f_frac: float = float(f) / 6.0
			var fw: float = flare_w * f_frac
			var fh: float = flare_h * f_frac
			var f_alpha: float = (1.0 - f_frac) * 0.04 * flare_prog
			var flare_col := Color(1.0, 0.92, 0.72, f_alpha)
			# Draw smooth horizontal ellipse
			var poly := PackedVector2Array()
			for p in 20:
				var ang: float = float(p) / 20.0 * TAU
				poly.append(center + Vector2(cos(ang) * fw, sin(ang) * fh))
			light_canvas.draw_colored_polygon(poly, flare_col)

	# 3. Organic Cavern Aperture Core (Slight natural rock contours, not a computer circle)
	var poly_core := PackedVector2Array()
	var core_steps := 32
	for k in core_steps:
		var ang: float = float(k) / float(core_steps) * TAU
		# Organic rock opening contour perturbation
		var contour: float = 1.0 + 0.04 * cos(ang * 3.0) - 0.03 * sin(ang * 5.0)
		var r_k: float = core_r * contour
		poly_core.append(center + Vector2(cos(ang) * r_k, sin(ang) * (r_k * 0.92)))

	# Overexposed pure white core of morning sky
	var core_alpha: float = clampf(0.88 + 0.12 * prog, 0.0, 1.0)
	light_canvas.draw_colored_polygon(poly_core, Color(1.0, 0.99, 0.95, core_alpha))

	# Inner incandescent halo right at aperture boundary
	light_canvas.draw_circle(center, core_r * 1.25, Color(1.0, 0.96, 0.82, 0.45 * core_alpha))


func _draw_particles() -> void:
	if _phase < 2 or _phase >= 5:
		return
	for p in _sun_particles:
		var pos: Vector2 = p["pos"]
		var r: float = float(p["r"])
		var a: float = float(p["alpha"]) * (1.0 - black_veil.color.a)
		if a > 0.02:
			var twinkle: float = 0.6 + 0.4 * sin(_time * 2.5 + float(p["phase"]))
			var col := Color(1.0, 0.92, 0.62, a * twinkle)
			particle_layer.draw_circle(pos, r * 1.8, Color(col.r, col.g, col.b, col.a * 0.35))
			particle_layer.draw_circle(pos, r, col)


# --- Procedural Stone Footstep Synthesizer -----------------------------------

static func _make_wav(samples: PackedFloat32Array, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	var byte_count := samples.size() * 2
	var bytes := PackedByteArray()
	bytes.resize(byte_count)
	for i in samples.size():
		var s := clampi(int(clampf(samples[i], -1.0, 1.0) * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s)
	wav.data = bytes
	return wav


static func _synth_stone_step(variant: int = 0) -> AudioStreamWAV:
	var dur := 0.16
	var count := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var f_heel_start: float = [140.0, 152.0, 130.0][clampi(variant, 0, 2)]
	var f_heel_end: float = 44.0
	var f_toe_start: float = 95.0
	var bp_freq: float = [750.0, 900.0, 680.0][clampi(variant, 0, 2)]
	var phase_h := 0.0
	var phase_t := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var a_lp: float = clampf(TAU * (bp_freq * 1.6) / MIX_RATE, 0.05, 0.50)
	var a_hp: float = clampf(TAU * bp_freq / MIX_RATE, 0.02, 0.35)

	for i in count:
		var t: float = float(i) / MIX_RATE
		var h_att: float = minf(t / 0.002, 1.0)
		var f_h: float = lerpf(f_heel_start, f_heel_end, clampf(t / 0.045, 0.0, 1.0))
		phase_h += TAU * f_h / MIX_RATE
		var heel: float = sin(phase_h) * h_att * exp(-t * 38.0)

		var toe := 0.0
		if t >= 0.038:
			var tt: float = t - 0.038
			var t_att: float = minf(tt / 0.003, 1.0)
			var f_t: float = lerpf(f_toe_start, 36.0, clampf(tt / 0.040, 0.0, 1.0))
			phase_t += TAU * f_t / MIX_RATE
			toe = sin(phase_t) * t_att * exp(-tt * 42.0) * 0.42

		var n: float = randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, n, a_lp)
		lp2 = lerpf(lp2, lp1, a_hp)
		var grit: float = (lp1 - lp2) * 1.8 * exp(-t * 54.0)

		out[i] = tanh((heel * 0.78 + toe + grit * 0.48) * 1.3) * 0.85
	return _make_wav(out)
