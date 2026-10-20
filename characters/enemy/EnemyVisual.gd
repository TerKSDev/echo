extends Node2D
class_name EnemyVisual
## Draws an Enemy (body, auras, waves). Reads the enemy's state; changes nothing.
## Created by Enemy at runtime as a child, so it shares the enemy's position.

var enemy: Enemy


func _draw() -> void:
	if enemy == null:
		return
	var base := EnemyPresets.color_of(enemy.enemy_type)
	var t := Time.get_ticks_msec() / 1000.0
	var state := enemy.state

	# 1. Footstep ripples (mobile enemies)
	for r in enemy.step_ripples:
		var prog: float = r["age"]
		var rad: float = prog * float(r["max_r"])
		draw_arc(to_local(r["pos"]), rad, 0.0, TAU, 20, Color(base, (1.0 - prog) * 0.4), 1.2)

	# 2. Proximity aura and pulse
	var proximity := enemy.proximity
	if proximity > 0.0:
		var beat := 0.5 + 0.5 * sin(t * (4.0 + 10.0 * proximity))
		draw_arc(Vector2.ZERO, 20.0 + 8.0 * beat * proximity, 0.0, TAU, 32, Color(base, 0.15 + 0.45 * proximity), 2.0)
		if state == Enemy.State.SLEEP:
			var breathe := 0.5 + 0.5 * sin(t * 1.8)
			draw_circle(Vector2.ZERO, 14.0 + 3.0 * breathe, Color(base, 0.12 * proximity))

	# 3. Chaser phantom trail
	if enemy.enemy_type == Enemy.EnemyType.CHASER and enemy.trail_points.size() > 0:
		for i in range(enemy.trail_points.size()):
			var p := to_local(enemy.trail_points[i])
			var frac := 1.0 - float(i) / enemy.trail_points.size()
			draw_circle(p, (11.0 - i * 0.8), Color(1.0, 0.15, 0.15, 0.25 * frac * maxf(enemy.visible_alpha, 0.5)))

	# 4. Screamer / Listener shockwaves
	if state == Enemy.State.SCREAM and enemy.scream_wave_radius > 0.0:
		var fade := clampf(1.0 - enemy.scream_wave_radius / 550.0, 0.0, 1.0)
		for ring in 3:
			var r_offset := enemy.scream_wave_radius - ring * 35.0
			if r_offset > 0.0:
				draw_arc(Vector2.ZERO, r_offset, 0.0, TAU, 48, Color(0.98, 0.2, 0.4, fade * 0.8), 2.5)

	if state == Enemy.State.ALARM and enemy.alarm_wave_radius > 0.0:
		var fade := clampf(1.0 - enemy.alarm_wave_radius / 500.0, 0.0, 1.0)
		for ring in 3:
			var r_offset := enemy.alarm_wave_radius - ring * 40.0
			if r_offset > 0.0:
				draw_arc(Vector2.ZERO, r_offset, 0.0, TAU, 48, Color(0.2, 0.95, 0.7, fade * 0.75), 2.0)

	# Speed boost aura
	if enemy.speed_boost_timer > 0.0:
		var boost_pulse := 16.0 + 3.0 * sin(t * 18.0)
		draw_arc(Vector2.ZERO, boost_pulse, 0.0, TAU, 24, Color(1.0, 0.45, 0.1, 0.65 * maxf(enemy.visible_alpha, 0.5)), 1.8)

	# Body is hidden until revealed by an echo (or while alert/screaming/alarming)
	var always_shown := state == Enemy.State.ALERT or state == Enemy.State.SCREAM or state == Enemy.State.ALARM
	if enemy.visible_alpha < 0.02 and not always_shown:
		return

	var alpha := maxf(enemy.visible_alpha, 0.35 if always_shown else 0.0)
	var col := Color(base, alpha)

	# 5. Body per type
	match enemy.enemy_type:
		Enemy.EnemyType.SLEEPER:
			_draw_sleeper(t, col, alpha)
		Enemy.EnemyType.PATROLLER:
			_draw_patroller(t, col, alpha)
		Enemy.EnemyType.CHASER:
			_draw_chaser(t, col, alpha)
		Enemy.EnemyType.SCREAMER:
			_draw_screamer(t, col, alpha)
		Enemy.EnemyType.LISTENER:
			_draw_listener(col, alpha)


# Sleeper: violet orb, closed eye slit while asleep
func _draw_sleeper(t: float, col: Color, alpha: float) -> void:
	match enemy.state:
		Enemy.State.SLEEP:
			draw_circle(Vector2.ZERO, 13.0, Color(col, 0.5 * alpha))
			draw_line(Vector2(-9, 0), Vector2(9, 0), Color(0.18, 0.05, 0.3, alpha), 2.5)
		Enemy.State.ALERT:
			_draw_alert_eye(t, col, alpha)
		Enemy.State.INVESTIGATE:
			draw_circle(Vector2.ZERO, 13.0, col)
			draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.9, 1.0, alpha))
			draw_arc(Vector2.ZERO, 18.0 + 2.0 * sin(t * 8.0), 0.0, TAU, 24, Color(col, 0.6 * alpha), 2.0)
		_:
			draw_circle(Vector2.ZERO, 12.0, col)
			draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 1.0, alpha))


# Patroller: amber orb with 3 orbiting scanner dots
func _draw_patroller(t: float, col: Color, alpha: float) -> void:
	if enemy.state == Enemy.State.ALERT:
		_draw_alert_eye(t, col, alpha)
		return
	draw_circle(Vector2.ZERO, 12.0, col)
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.95, 0.85, alpha))
	var orbit_r := 18.0
	draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 24, Color(col, 0.35 * alpha), 1.2)
	for i in 3:
		var ang := t * 3.5 + i * TAU / 3.0
		draw_circle(Vector2.from_angle(ang) * orbit_r, 2.5, Color(1.0, 0.95, 0.5, alpha))


# Chaser: crimson core with 6 spiky barbs and a slit pupil
func _draw_chaser(t: float, col: Color, alpha: float) -> void:
	var spike_count := 6
	var vib := sin(t * 24.0) * 2.0
	var core_r := 12.0
	var spin := 4.0 if enemy.state == Enemy.State.INVESTIGATE else 1.5
	for i in spike_count:
		var ang := i * TAU / float(spike_count) + t * spin
		var p_base := Vector2.from_angle(ang) * core_r
		var p_tip := Vector2.from_angle(ang) * (core_r + 8.0 + vib)
		draw_line(p_base, p_tip, Color(1.0, 0.2, 0.2, alpha), 2.4)
	draw_circle(Vector2.ZERO, core_r, col)
	draw_line(Vector2(0, -7), Vector2(0, 7), Color(0.1, 0.0, 0.0, alpha), 2.8)
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.8, 0.8, alpha))


# Screamer: crystal cocoon; cracks after the 1st sound, bursts when screaming
func _draw_screamer(t: float, col: Color, alpha: float) -> void:
	var pulse := 1.0 + 0.15 * sin(t * (18.0 if enemy.screamer_count > 0 else 2.5))
	if enemy.state == Enemy.State.SCREAM:
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			draw_line(Vector2.ZERO, Vector2.from_angle(ang) * (24.0 * pulse), Color(1.0, 0.3, 0.6, alpha), 3.0)
		draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.1, 0.3, alpha))
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, alpha))
		return

	var r := 13.0 * pulse
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, col, 2.0)
	draw_circle(Vector2.ZERO, r * 0.7, Color(col, 0.4 * alpha))
	if enemy.screamer_count >= 1:
		var flash := Color(1.0, 0.2, 0.4, alpha)
		draw_line(Vector2(-8, -8), Vector2(8, 8), flash, 2.0)
		draw_line(Vector2(8, -8), Vector2(-8, 8), flash, 2.0)
		draw_circle(Vector2.ZERO, 4.0, flash)
	else:
		draw_circle(Vector2.ZERO, 3.5, Color(0.2, 0.05, 0.15, alpha))


# Listener: sonar dish with 5 pips (one per sound counted)
func _draw_listener(col: Color, alpha: float) -> void:
	draw_arc(Vector2.ZERO, 15.0, -PI * 0.8, PI * 0.8, 24, col, 2.5)
	draw_circle(Vector2.ZERO, 8.0, Color(col, 0.4 * alpha))
	for i in 5:
		var ang := -PI * 0.72 + i * (PI * 1.44 / 4.0)
		var pip_pos := Vector2.from_angle(ang) * 22.0
		if enemy.listener_count > i:
			draw_circle(pip_pos, 4.0, Color(0.2, 1.0, 0.7, alpha))
			draw_circle(pip_pos, 1.8, Color(1.0, 1.0, 1.0, alpha))
		else:
			draw_circle(pip_pos, 3.0, Color(col, 0.3 * alpha))


# Shared "woken up" eye with radial spikes
func _draw_alert_eye(t: float, col: Color, alpha: float) -> void:
	var eye_alpha := maxf(alpha, 0.8)
	draw_arc(Vector2(0, 11), 15.0, -PI * 0.72, -PI * 0.28, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
	draw_arc(Vector2(0, -11), 15.0, PI * 0.28, PI * 0.72, 16, Color(1.0, 1.0, 1.0, eye_alpha), 2.5)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color(col, eye_alpha), 3.0)
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.9, 0.9, eye_alpha))
	for i in 6:
		var ang := i * TAU / 6.0 + t * 5.0
		var p1 := Vector2.from_angle(ang) * 16.0
		var p2 := Vector2.from_angle(ang) * (25.0 + 4.0 * sin(t * 22.0))
		draw_line(p1, p2, Color(col, 0.9 * eye_alpha), 2.0)
