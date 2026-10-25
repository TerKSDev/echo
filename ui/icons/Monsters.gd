class_name Monsters
## Procedural Monster Specimen & Shockwave Preview Renderer for ECHO Bestiary.
## Offloaded from LevelSelect to keep UI controllers lean and modular.

static func draw_monster_preview(canvas: Control, entry: Dictionary, time: float) -> void:
	var shake: float = float(entry.get("shake", 0.0))
	var jitter := Vector2.ZERO
	if shake > 0.01:
		jitter = Vector2(sin(time * 50.0), cos(time * 43.0)) * shake
	var c := canvas.size * 0.5 + jitter

	# 1. Subtle radar containment reticle background
	canvas.draw_arc(c, 40.0, 0.0, TAU, 32, Color(0.14, 0.28, 0.42, 0.22), 1.0)
	canvas.draw_arc(c, 24.0, 0.0, TAU, 24, Color(0.14, 0.28, 0.42, 0.16), 1.0)
	canvas.draw_line(c + Vector2(-42, 0), c + Vector2(-34, 0), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(34, 0), c + Vector2(42, 0), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(0, -42), c + Vector2(0, -34), Color(0.2, 0.45, 0.65, 0.35), 1.0)
	canvas.draw_line(c + Vector2(0, 34), c + Vector2(0, 42), Color(0.2, 0.45, 0.65, 0.35), 1.0)

	# 2. Expanding shockwave rings (Screamer screech / Roar / Listener Alarm)
	for sw in entry.get("shockwaves", []):
		var r: float = float(sw.get("r", 0.0))
		var max_r: float = float(sw.get("max_r", 80.0))
		if r > 0.0:
			var frac := clampf(1.0 - r / max_r, 0.0, 1.0)
			var sw_col: Color = sw.get("col", Color(1, 1, 1, 1))
			var col := Color(sw_col.r, sw_col.g, sw_col.b, sw_col.a * frac)
			canvas.draw_arc(c, r, 0.0, TAU, 36, col, 2.2)

	# 3. Monster specimen rendering
	var m_type: String = str(entry.get("type", ""))
	var stage: int = int(entry.get("stage", 0))
	var base_col: Color = entry.get("color", Color.WHITE)

	match m_type:
		"screamer":
			draw_preview_screamer(canvas, c, stage, base_col, time)
		"sleeper":
			draw_preview_sleeper(canvas, c, stage, base_col, time)
		"patroller":
			draw_preview_patroller(canvas, c, stage, base_col, time)
		"chaser":
			draw_preview_chaser(canvas, c, stage, base_col, time)
		"listener":
			draw_preview_listener(canvas, c, stage, base_col, int(entry.get("pips", 0)), time)


static func draw_preview_screamer(canvas: Control, c: Vector2, stage: int, col: Color, time: float) -> void:
	if stage == 2:
		var pulse := 1.0 + 0.16 * sin(time * 24.0)
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			canvas.draw_line(c, c + Vector2.from_angle(ang) * (34.0 * pulse), Color(1.0, 0.3, 0.6, 0.95), 3.2)
		canvas.draw_circle(c, 13.0, Color(1.0, 0.1, 0.35, 1.0))
		canvas.draw_circle(c, 5.0, Color(1.0, 1.0, 1.0, 1.0))
		var w_r := 18.0 + fmod(time * 45.0, 30.0)
		canvas.draw_arc(c, w_r, 0.0, TAU, 24, Color(1.0, 0.2, 0.45, 0.65), 1.8)
	else:
		var pulse_freq: float = 20.0 if stage == 1 else 2.5
		var pulse: float = 1.0 + (0.22 if stage == 1 else 0.12) * sin(time * pulse_freq)
		var r: float = 16.0 * pulse
		canvas.draw_arc(c, r, 0.0, TAU, 24, col, 2.2)
		canvas.draw_circle(c, r * 0.72, Color(col.r, col.g, col.b, 0.38))
		if stage == 1:
			var flash := Color(1.0, 0.25, 0.45, 0.95)
			canvas.draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), flash, 2.2)
			canvas.draw_line(c + Vector2(10, -10), c + Vector2(-10, 10), flash, 2.2)
			canvas.draw_line(c + Vector2(-3, -12), c + Vector2(2, 12), Color(1.0, 0.4, 0.6, 0.85), 1.6)
			canvas.draw_circle(c, 5.5, flash)
		else:
			canvas.draw_circle(c, 4.5, Color(0.2, 0.05, 0.15, 0.9))


static func draw_preview_sleeper(canvas: Control, c: Vector2, stage: int, col: Color, time: float) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + time * 4.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 25.0 + sin(time * 40.0 + i) * 5.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(col.r, col.g * 0.6, col.b * 0.6, 0.95), 2.6)
		canvas.draw_circle(c, 15.0, Color(col, 0.95))
		canvas.draw_circle(c, 7.0, Color(1.0, 1.0, 1.0, 1.0))
		var pupil_dir := Vector2.DOWN * 8.0
		canvas.draw_line(c - pupil_dir, c + pupil_dir, Color(0.1, 0.0, 0.0, 1.0), 3.2)
		canvas.draw_circle(c, 2.5, Color(1.0, 0.2, 0.2, 1.0))
		var r_wave := 16.0 + fmod(time * 42.0, 28.0)
		canvas.draw_arc(c, r_wave, 0.0, TAU, 24, Color(col, 0.6), 1.8)
	elif stage == 1:
		canvas.draw_arc(c, 21.0 + 3.0 * sin(time * 8.0), 0.0, TAU, 24, Color(col, 0.5), 1.8)
		canvas.draw_circle(c, 15.0, col)
		canvas.draw_circle(c, 7.0, Color(1.0, 0.92, 1.0))
		var gaze := Vector2(cos(time * 2.5), sin(time * 2.5)) * 3.0
		canvas.draw_circle(c + gaze, 3.5, Color(0.18, 0.05, 0.3))
	else:
		var breathe := 0.5 + 0.5 * sin(time * 1.8)
		canvas.draw_circle(c, 16.0 + 4.0 * breathe, Color(col, 0.18))
		canvas.draw_circle(c, 15.0, Color(col, 0.65))
		canvas.draw_line(c + Vector2(-11, 0), c + Vector2(11, 0), Color(0.18, 0.05, 0.3, 0.95), 2.8)


static func draw_preview_patroller(canvas: Control, c: Vector2, stage: int, col: Color, time: float) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + time * 4.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 25.0 + sin(time * 40.0 + i) * 5.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.5, 0.2, 0.95), 2.6)
		canvas.draw_circle(c, 15.0, Color(1.0, 0.6, 0.2, 0.95))
		canvas.draw_circle(c, 6.0, Color(1.0, 1.0, 1.0, 1.0))
	else:
		canvas.draw_circle(c, 14.0, col)
		canvas.draw_circle(c + Vector2(2, 0), 6.0, Color(1.0, 0.95, 0.85))
		var orbit_r := 22.0
		var orbit_speed: float = 7.0 if stage == 1 else 3.2
		canvas.draw_arc(c, orbit_r, 0.0, TAU, 28, Color(col, 0.4), 1.4)
		for i in 3:
			var ang := time * orbit_speed + i * TAU / 3.0
			canvas.draw_circle(c + Vector2.from_angle(ang) * orbit_r, 3.4, Color(1.0, 0.95, 0.5, 1.0))
		if stage == 1:
			var sweep_ang: float = time * 3.2
			canvas.draw_arc(c, 30.0, sweep_ang - 0.55, sweep_ang + 0.55, 16, Color(col, 0.75), 2.2)
			canvas.draw_arc(c, 38.0, sweep_ang - 0.38, sweep_ang + 0.38, 14, Color(col, 0.45), 1.6)


static func draw_preview_chaser(canvas: Control, c: Vector2, stage: int, col: Color, time: float) -> void:
	if stage == 2:
		var barb_count := 8
		for i in barb_count:
			var ang := i * TAU / float(barb_count) + time * 5.0
			var p_base := c + Vector2.from_angle(ang) * 14.0
			var spike_len := 27.0 + sin(time * 45.0 + i) * 6.0
			var p_tip := c + Vector2.from_angle(ang) * spike_len
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.15, 0.15, 0.95), 2.8)
		canvas.draw_circle(c, 15.0, Color(1.0, 0.15, 0.15, 1.0))
		canvas.draw_circle(c, 6.0, Color(1.0, 0.9, 0.9, 1.0))
		var pupil_dir := Vector2.UP * 8.0
		canvas.draw_line(c - pupil_dir, c + pupil_dir, Color(0.1, 0.0, 0.0, 1.0), 3.2)
	else:
		var spike_count := 6
		var spin: float = 6.0 if stage == 1 else 1.8
		var vib: float = sin(time * 30.0) * (3.5 if stage == 1 else 1.2)
		var core_r := 14.0
		for i in spike_count:
			var ang := i * TAU / float(spike_count) + time * spin
			var p_base := c + Vector2.from_angle(ang) * core_r
			var p_tip := c + Vector2.from_angle(ang) * (core_r + 10.0 + vib)
			canvas.draw_line(p_base, p_tip, Color(1.0, 0.25, 0.25, 0.95), 2.6)
		if stage == 1:
			for trail_idx in 3:
				var tr_ang := time * spin - (trail_idx + 1) * 0.22
				canvas.draw_circle(c + Vector2.from_angle(tr_ang) * 12.0, 8.0 - trail_idx * 2.0, Color(1.0, 0.1, 0.1, 0.25 - trail_idx * 0.07))
		canvas.draw_circle(c, core_r, col)
		var slit_dir := Vector2.UP * 7.0
		canvas.draw_line(c - slit_dir, c + slit_dir, Color(0.1, 0.0, 0.0, 0.95), 3.0)
		canvas.draw_circle(c, 2.5, Color(1.0, 0.8, 0.8, 1.0))


static func draw_preview_listener(canvas: Control, c: Vector2, stage: int, col: Color, pips: int, time: float) -> void:
	canvas.draw_arc(c, 18.0, -PI * 0.8, PI * 0.8, 28, col, 2.8)
	canvas.draw_circle(c, 9.5, Color(col, 0.45))
	for i in 5:
		var ang := -PI * 0.72 + i * (PI * 1.44 / 4.0)
		var pip_pos := c + Vector2.from_angle(ang) * 28.0
		if pips > i:
			var flare: float = 1.0 + (0.35 * sin(time * 20.0) if pips == 5 else 0.0)
			canvas.draw_circle(pip_pos, 4.8 * flare, Color(0.2, 1.0, 0.7, 1.0))
			canvas.draw_circle(pip_pos, 2.2 * flare, Color(1.0, 1.0, 1.0, 1.0))
		else:
			canvas.draw_circle(pip_pos, 3.2, Color(col, 0.28))
	if stage == 2:
		var a_r := 22.0 + fmod(time * 50.0, 32.0)
		canvas.draw_arc(c, a_r, 0.0, TAU, 28, Color(0.2, 1.0, 0.7, 0.7), 2.0)
