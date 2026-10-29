extends Node2D
class_name EnemyVisual
## Draws an Enemy (body, auras, waves). Reads the enemy's state; changes nothing.
## Created by Enemy at runtime as a child, so it shares the enemy's position.

var enemy: Enemy


func _draw() -> void:
	if enemy == null:
		return
	var state := enemy.state
	var always_shown := state == Enemy.State.ALERT or state == Enemy.State.SCREAM or state == Enemy.State.ALARM
	if enemy.is_wall_occluded and enemy.visible_alpha < 0.02 and not always_shown:
		return

	var base := EnemyPresets.color_of(enemy.enemy_type)
	var t := Time.get_ticks_msec() / 1000.0

	# 1. Footstep ripples & sleeping breath ripples
	if not enemy.is_wall_occluded or enemy.visible_alpha >= 0.02 or state == Enemy.State.INVESTIGATE:
		var occ_mult: float = 0.55 if enemy.is_wall_occluded else 1.0
		for r in enemy.step_ripples:
			var prog: float = float(r["age"])
			var rad: float = prog * float(r["max_r"])
			var is_water: bool = (r.get("is_water", false) == true)
			var is_breath: bool = (r.get("is_breath", false) == true)
			if is_breath:
				var b_alpha := (1.0 - prog) * (1.0 - prog) * 0.38 * occ_mult
				var col_breath := Color(0.65, 0.32, 0.95, b_alpha)
				draw_arc(to_local(Vector2(r["pos"])), rad, 0.0, TAU, 24, col_breath, 1.2)
			else:
				var col_r := Color(0.28, 0.75, 1.0, (1.0 - prog) * 0.55 * occ_mult) if is_water else Color(base, (1.0 - prog) * 0.4 * occ_mult)
				draw_arc(to_local(Vector2(r["pos"])), rad, 0.0, TAU, 20, col_r, 1.6 if is_water else 1.2)
				if is_water and prog < 0.55:
					draw_arc(to_local(Vector2(r["pos"])), rad * 0.55, 0.0, TAU, 16, Color(0.5, 0.9, 1.0, (1.0 - prog) * 0.35 * occ_mult), 1.0)

	# 2. Chaser phantom trail
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

	# Acoustic mark pulse (boon_acoustic_amplifier feedback)
	if enemy.acoustic_mark_timer > 0.0 and not enemy.is_wall_occluded:
		var mark_ratio := clampf(enemy.acoustic_mark_timer / 4.0, 0.0, 1.0)
		var mark_pulse := 18.0 + 3.0 * sin(t * 12.0)
		var mark_col := Color(0.35, 0.88, 1.0, 0.65 * mark_ratio)
		draw_arc(Vector2.ZERO, mark_pulse, 0.0, TAU, 28, mark_col, 2.0)
		for i in 4:
			var ang := i * (PI * 0.5) + t * 3.5
			var spark_pt := Vector2.from_angle(ang) * mark_pulse
			draw_circle(spark_pt, 2.0, Color(0.7, 0.95, 1.0, 0.85 * mark_ratio))

	# Stunned reeling aura (boon_sonic_stagger & boon_second_wind feedback)
	if enemy._stun_timer > 0.0:
		var stun_pulse := 16.0 + 2.0 * sin(t * 22.0)
		draw_arc(Vector2.ZERO, stun_pulse, 0.0, TAU, 24, Color(1.0, 0.75, 0.25, 0.75), 1.8)

	# Body is hidden until revealed by an echo (or while alert/screaming/alarming)
	if enemy.visible_alpha < 0.02 and not always_shown:
		if enemy.eye_linger_timer > 0.0 and not enemy.is_wall_occluded:
			_draw_lingering_eyes(t, enemy.eye_linger_timer / 0.45)
		return

	var alpha := maxf(enemy.visible_alpha, 0.35 if always_shown else 0.0)
	var col := Color(base, alpha)

	# 5. Body per type (with startled twitch/spasm if sound wave struck from darkness)
	var has_spasm: bool = enemy.spasm_timer > 0.0
	if has_spasm:
		draw_set_transform(enemy.spasm_offset, 0.0, Vector2.ONE)
		var s_prog: float = enemy.spasm_timer / 0.16
		var shock_r := 12.0 + (1.0 - s_prog) * 10.0
		var shock_col := Color(base.r, base.g * 0.8, base.b * 0.8, s_prog * 0.65 * alpha)
		draw_arc(Vector2.ZERO, shock_r, 0.0, TAU, 18, shock_col, 1.5)

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

	if has_spasm:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 6. Active search scanning cone when monster is prowling in SEARCH state
	if state == Enemy.State.SEARCH:
		var sweep_ang: float = enemy.facing_dir.angle() + sin(t * 5.2) * 0.55
		draw_arc(Vector2.ZERO, 22.0, sweep_ang - 0.5, sweep_ang + 0.5, 14, Color(base, 0.55 * alpha), 2.0)
		draw_arc(Vector2.ZERO, 30.0, sweep_ang - 0.35, sweep_ang + 0.35, 12, Color(base, 0.3 * alpha), 1.4)

	# 7. Decoy Pebble curiosity indicator ("?" floating above head in warm amber)
	if enemy.is_investigating_decoy and alpha > 0.12:
		_draw_decoy_curiosity(t, alpha)


func _draw_decoy_curiosity(t: float, alpha: float) -> void:
	var bob := sin(t * 6.0) * 2.5
	var pos := Vector2(0.0, -26.0 + bob)
	var q_col := Color(1.0, 0.78, 0.28, alpha * 0.95)
	var glow_col := Color(1.0, 0.65, 0.15, alpha * 0.25)
	draw_circle(pos + Vector2(0, -3), 7.0, glow_col)
	draw_arc(pos + Vector2(0, -5), 3.8, -PI * 0.8, PI * 0.35, 12, q_col, 2.0)
	draw_line(pos + Vector2(2.5, -4.0), pos + Vector2(0.0, -1.0), q_col, 1.8)
	draw_circle(pos + Vector2(0.0, 3.2), 1.5, q_col)


# Sleeper: violet orb, closed eye slit while asleep
func _draw_sleeper(t: float, col: Color, alpha: float) -> void:
	var gaze: Vector2 = enemy.facing_dir * 3.0
	match enemy.state:
		Enemy.State.SLEEP:
			draw_circle(Vector2.ZERO, 13.0, Color(col, 0.5 * alpha))
			draw_line(Vector2(-9, 0), Vector2(9, 0), Color(0.18, 0.05, 0.3, alpha), 2.5)
		Enemy.State.ALERT:
			_draw_alert_roar(t, col, alpha)
		Enemy.State.INVESTIGATE:
			draw_circle(Vector2.ZERO, 13.0, col)
			draw_circle(gaze, 6.0, Color(1.0, 0.9, 1.0, alpha))
			draw_arc(Vector2.ZERO, 18.0 + 2.0 * sin(t * 8.0), 0.0, TAU, 24, Color(col, 0.6 * alpha), 2.0)
		_:
			draw_circle(Vector2.ZERO, 12.0, col)
			draw_circle(gaze * 0.7, 5.0, Color(1.0, 1.0, 1.0, alpha))


# Patroller: amber orb with 3 orbiting scanner dots
func _draw_patroller(t: float, col: Color, alpha: float) -> void:
	if enemy.state == Enemy.State.ALERT:
		_draw_alert_roar(t, col, alpha)
		return
	var gaze: Vector2 = enemy.facing_dir * 2.8
	draw_circle(Vector2.ZERO, 12.0, col)
	draw_circle(gaze, 5.0, Color(1.0, 0.95, 0.85, alpha))
	var orbit_r := 18.0
	var orbit_speed := 6.0 if enemy.state == Enemy.State.INVESTIGATE else 3.5
	draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 24, Color(col, 0.35 * alpha), 1.2)
	for i in 3:
		var ang := t * orbit_speed + i * TAU / 3.0
		draw_circle(Vector2.from_angle(ang) * orbit_r, 2.5, Color(1.0, 0.95, 0.5, alpha))


# Chaser: crimson core with 6 spiky barbs and a directional slit pupil
func _draw_chaser(t: float, col: Color, alpha: float) -> void:
	if enemy.state == Enemy.State.ALERT:
		_draw_alert_roar(t, col, alpha)
		return
	var spike_count := 6
	var vib := sin(t * 24.0) * 2.0
	var core_r := 12.0
	var spin := 4.5 if enemy.state == Enemy.State.INVESTIGATE else 1.5
	for i in spike_count:
		var ang := i * TAU / float(spike_count) + t * spin
		var p_base := Vector2.from_angle(ang) * core_r
		var p_tip := Vector2.from_angle(ang) * (core_r + 8.0 + vib)
		draw_line(p_base, p_tip, Color(1.0, 0.2, 0.2, alpha), 2.4)
	draw_circle(Vector2.ZERO, core_r, col)
	var gaze: Vector2 = enemy.facing_dir * 2.2
	var slit_dir: Vector2 = enemy.facing_dir.orthogonal() * 7.0
	draw_line(gaze - slit_dir, gaze + slit_dir, Color(0.1, 0.0, 0.0, alpha), 2.8)
	draw_circle(gaze, 2.2, Color(1.0, 0.8, 0.8, alpha))


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


# Listener: sonar dish with 3 pips (one per sound counted)
func _draw_listener(col: Color, alpha: float) -> void:
	draw_arc(Vector2.ZERO, 15.0, -PI * 0.8, PI * 0.8, 24, col, 2.5)
	draw_circle(Vector2.ZERO, 8.0, Color(col, 0.4 * alpha))
	for i in 3:
		var ang := -PI * 0.65 + i * (PI * 1.30 / 2.0)
		var pip_pos := Vector2.from_angle(ang) * 22.0
		if enemy.listener_count > i:
			draw_circle(pip_pos, 4.5, Color(0.2, 1.0, 0.7, alpha))
			draw_circle(pip_pos, 2.0, Color(1.0, 1.0, 1.0, alpha))
		else:
			draw_circle(pip_pos, 3.0, Color(col, 0.3 * alpha))


# Discovery roar & stiff (Resident Evil style discovery windup)
func _draw_alert_roar(t: float, col: Color, alpha: float) -> void:
	var to_target: Vector2 = (enemy.target - enemy.global_position).normalized()
	if to_target.is_zero_approx():
		to_target = Vector2.UP
	var face_ang: float = to_target.angle()

	# 1. High frequency body tremor / twitching in shock & fury
	var jitter := Vector2(sin(t * 55.0), cos(t * 47.0)) * 2.5
	var eye_alpha := maxf(alpha, 0.85)

	# 2. Expanding acoustic roar shockwaves blasting toward the player
	var progress: float = clampf(enemy.timer / maxf(enemy.alert_time, 0.1), 0.0, 1.0)
	var wave_r := 12.0 + progress * 48.0
	var wave_a := (1.0 - progress) * 0.95 * eye_alpha
	draw_arc(jitter + to_target * 8.0, wave_r, face_ang - 0.75, face_ang + 0.75, 16, Color(col, wave_a), 2.5)
	if wave_r > 18.0:
		draw_arc(jitter + to_target * 8.0, wave_r - 14.0, face_ang - 0.55, face_ang + 0.55, 12, Color(1.0, 0.95, 0.8, wave_a * 0.7), 1.8)

	# 3. Flaring spiky barbs / acoustic mandible corona
	var barb_count := 8
	for i in barb_count:
		var ang := i * TAU / float(barb_count) + t * 4.0
		var p_base := jitter + Vector2.from_angle(ang) * 12.0
		var spike_len := 22.0 + sin(t * 40.0 + i) * 4.0
		var p_tip := jitter + Vector2.from_angle(ang) * spike_len
		draw_line(p_base, p_tip, Color(col.r, col.g * 0.6, col.b * 0.6, 0.95 * eye_alpha), 2.4)

	# 4. Central dilated core
	draw_circle(jitter, 13.0, Color(col, 0.9 * eye_alpha))
	draw_circle(jitter, 6.0, Color(1.0, 1.0, 1.0, eye_alpha))

	# 5. Demonic vertical slit pupil locked onto target
	var pupil_dir := to_target.orthogonal() * 7.0
	draw_line(jitter - pupil_dir, jitter + pupil_dir, Color(0.1, 0.0, 0.0, eye_alpha), 3.0)
	draw_circle(jitter, 2.0, Color(1.0, 0.2, 0.2, eye_alpha))


# Lingering sinister eyes after body dissolves into the dark
func _draw_lingering_eyes(_t: float, factor: float) -> void:
	var a: float = clampf(factor, 0.0, 1.0)
	match enemy.enemy_type:
		Enemy.EnemyType.SLEEPER:
			if enemy.state == Enemy.State.SLEEP:
				var slit_half: float = 7.0 * factor
				draw_line(Vector2(-slit_half, 0.0), Vector2(slit_half, 0.0), Color(0.75, 0.2, 0.9, a * 0.8), 2.0)
				draw_circle(Vector2.ZERO, 1.8 * factor, Color(0.95, 0.4, 0.95, a))
			else:
				var gaze: Vector2 = enemy.facing_dir * 3.0
				draw_circle(gaze, 3.5 * factor, Color(0.85, 0.25, 0.95, a * 0.9))
				draw_circle(gaze, 1.6 * factor, Color(1.0, 0.9, 1.0, a))
		Enemy.EnemyType.PATROLLER:
			var gaze: Vector2 = enemy.facing_dir * 2.8
			draw_circle(gaze, 4.0 * factor, Color(1.0, 0.7, 0.2, a * 0.85))
			draw_circle(gaze, 1.8 * factor, Color(1.0, 0.95, 0.8, a))
		Enemy.EnemyType.CHASER:
			var gaze: Vector2 = enemy.facing_dir * 2.2
			var slit_dir: Vector2 = enemy.facing_dir.orthogonal() * (6.5 * factor)
			draw_circle(gaze, 6.0 * factor, Color(0.9, 0.05, 0.05, a * 0.28))
			draw_line(gaze - slit_dir, gaze + slit_dir, Color(1.0, 0.15, 0.15, a * 0.95), 2.4)
			draw_circle(gaze, 1.6 * factor, Color(1.0, 0.85, 0.85, a))
		Enemy.EnemyType.SCREAMER:
			draw_circle(Vector2.ZERO, 4.5 * factor, Color(1.0, 0.15, 0.45, a * 0.9))
			draw_circle(Vector2.ZERO, 1.8 * factor, Color(1.0, 0.9, 0.95, a))
		Enemy.EnemyType.LISTENER:
			draw_circle(Vector2.ZERO, 4.0 * factor, Color(0.2, 1.0, 0.7, a * 0.85))
			draw_circle(Vector2.ZERO, 1.5 * factor, Color(0.9, 1.0, 0.95, a))
