class_name AbyssVortexFx
extends Control
## Procedural Pink-Purple Abyss Vortex / Turbine Reset FX for ECHO Challenge Mode.
## Renders a spinning logarithmic vortex turbine that accelerates progressively
## from slow rotation into an acoustic singularity at the midpoint to reboot the run,
## followed by an expanding shockwave ripple.

const TOTAL_DURATION: float = 1.45
const MIDPOINT_FRAC: float = 0.586 # 0.85s / 1.45s

var _progress: float = 0.0
var _on_midpoint: Callable
var _on_complete: Callable
var _midpoint_fired: bool = false
var _audio_player: AudioStreamPlayer = null


static func play(parent: Node, on_midpoint: Callable = Callable(), on_complete: Callable = Callable()) -> void:
	if parent == null or not is_instance_valid(parent):
		if on_midpoint.is_valid():
			on_midpoint.call()
		if on_complete.is_valid():
			on_complete.call()
		return

	var canvas := CanvasLayer.new()
	canvas.layer = 140
	canvas.name = "AbyssVortexCanvas"
	parent.add_child(canvas)

	var fx := AbyssVortexFx.new()
	fx.name = "AbyssVortexFx"
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_STOP
	fx._on_midpoint = on_midpoint
	fx._on_complete = on_complete
	canvas.add_child(fx)

	# Sound effect
	var sfx_wav: AudioStreamWAV = SfxManager.get_abyss_vortex_sfx()
	if sfx_wav != null:
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.stream = sfx_wav
		sfx_player.bus = &"SFX"
		sfx_player.volume_db = -3.0
		canvas.add_child(sfx_player)
		sfx_player.play()
		fx._audio_player = sfx_player

	# Animation Tween: 1.45s total duration
	var tw := fx.create_tween()
	tw.tween_method(fx._set_progress, 0.0, 1.0, TOTAL_DURATION).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func():
		if fx._on_complete.is_valid():
			fx._on_complete.call()
		canvas.queue_free()
	)


func _set_progress(val: float) -> void:
	_progress = val
	queue_redraw()

	if not _midpoint_fired and _progress >= MIDPOINT_FRAC:
		_midpoint_fired = true
		if _on_midpoint.is_valid():
			_on_midpoint.call()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var c := Vector2(w * 0.5, h * 0.5)
	var max_r: float = maxf(w, h) * 0.75

	if _progress < MIDPOINT_FRAC:
		# --- Phase 1: Singularity Implosion & Slow-to-Fast Turbine Spin-Up (0.0 .. 0.586) ---
		var p_in: float = _progress / MIDPOINT_FRAC
		# Progressive acceleration curve: starts very slow and graceful, then whips into hyper-speed
		var ease_in: float = pow(p_in, 2.6)
		var spin_rot: float = (p_in * 1.8) + pow(p_in, 3.4) * 26.0

		# 1. Dark vignette background
		var bg_alpha: float = minf(p_in * 1.20, 0.88)
		draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.01, 0.045, bg_alpha), true)

		# 2. Spinning Turbine Blades (8 logarithmic spiral blades)
		var num_blades := 8
		var cur_radius: float = lerpf(max_r, 40.0, ease_in)

		for b in num_blades:
			var base_angle: float = float(b) / float(num_blades) * TAU + spin_rot
			var pts_left := PackedVector2Array()
			var pts_right := PackedVector2Array()
			var steps := 24

			for s in range(steps + 1):
				var frac: float = float(s) / float(steps)
				var r: float = lerpf(18.0, cur_radius, frac)
				var swirl_ang: float = base_angle + pow(frac, 1.35) * 2.6 * (1.0 - ease_in * 0.35)
				var blade_width: float = sin(frac * PI) * lerpf(20.0, 3.5, ease_in)
				var normal := Vector2(-sin(swirl_ang), cos(swirl_ang))
				var pt := c + Vector2(cos(swirl_ang), sin(swirl_ang)) * r
				pts_left.append(pt - normal * blade_width * 0.5)
				pts_right.append(pt + normal * blade_width * 0.5)

			# Draw blade polygon
			var poly := PackedVector2Array()
			poly.append_array(pts_left)
			pts_right.reverse()
			poly.append_array(pts_right)

			var blade_alpha: float = (0.28 + 0.65 * p_in) * 0.78
			var blade_col := Color(0.95, 0.22, 0.75, blade_alpha)
			draw_polygon(poly, [blade_col])

			# Neon edge spine line
			var spine := PackedVector2Array()
			for s in range(steps + 1):
				var frac: float = float(s) / float(steps)
				var r: float = lerpf(18.0, cur_radius, frac)
				var swirl_ang: float = base_angle + pow(frac, 1.35) * 2.6 * (1.0 - ease_in * 0.35)
				spine.append(c + Vector2(cos(swirl_ang), sin(swirl_ang)) * r)
			var spine_col := Color(1.0, 0.60, 0.94, 0.95 * (0.35 + 0.65 * p_in))
			draw_polyline(spine, spine_col, 2.2)

		# 3. Concentric contracting rings (collapsing inward faster and faster)
		for ring_idx in 4:
			var r_prog: float = fmod(pow(p_in, 1.5) * 1.5 + float(ring_idx) * 0.25, 1.0)
			var ring_r: float = lerpf(max_r * 0.85, 12.0, r_prog)
			var ring_a: float = sin(r_prog * PI) * (0.45 + 0.45 * p_in)
			draw_arc(c, ring_r, 0.0, TAU, 40, Color(1.0, 0.45, 0.90, ring_a), 2.2)

		# 4. Center Singularity Core
		var core_r: float = lerpf(6.0, 42.0, ease_in)
		draw_circle(c, core_r + 18.0, Color(0.85, 0.15, 0.65, 0.38 * p_in))
		draw_circle(c, core_r, Color(1.0, 0.82, 0.98, 0.95))

	else:
		# --- Phase 2: Shockwave Expansion & Reboot Reveal (0.586 .. 1.0) ---
		var p_out: float = (_progress - MIDPOINT_FRAC) / (1.0 - MIDPOINT_FRAC)
		var fade: float = 1.0 - p_out

		# 1. Fading background overlay
		draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.01, 0.045, fade * 0.80), true)

		# 2. Outward Expanding Shockwave Rings
		var blast_r1: float = lerpf(38.0, max_r * 1.18, pow(p_out, 0.72))
		var blast_a1: float = pow(fade, 1.3) * 0.95
		draw_arc(c, blast_r1, 0.0, TAU, 48, Color(1.0, 0.40, 0.88, blast_a1), 3.8)

		var blast_r2: float = lerpf(18.0, max_r * 0.98, pow(maxf(p_out - 0.10, 0.0) / 0.90, 0.78))
		var blast_a2: float = pow(fade, 1.7) * 0.70
		if blast_r2 > 20.0:
			draw_arc(c, blast_r2, 0.0, TAU, 44, Color(0.85, 0.20, 0.65, blast_a2), 2.4)

		# 3. Residual Dissolving Turbine Whispers
		var num_blades := 8
		var residual_rot: float = 28.0 + p_out * TAU * 0.6
		var cur_radius: float = lerpf(45.0, max_r * 0.85, p_out)
		for b in num_blades:
			var base_angle: float = float(b) / float(num_blades) * TAU + residual_rot
			var pts := PackedVector2Array()
			var steps := 18
			for s in range(steps + 1):
				var frac: float = float(s) / float(steps)
				var r: float = lerpf(15.0, cur_radius, frac)
				var swirl_ang: float = base_angle + frac * 1.8
				pts.append(c + Vector2(cos(swirl_ang), sin(swirl_ang)) * r)
			var col := Color(1.0, 0.45, 0.85, fade * 0.35 * (1.0 - p_out))
			draw_polyline(pts, col, 1.8)

		# 4. Center Singularity Flash Decay
		if p_out < 0.32:
			var flash_p: float = 1.0 - (p_out / 0.32)
			draw_circle(c, 52.0 * flash_p, Color(1.0, 0.92, 0.98, flash_p * 0.90))
			draw_circle(c, 98.0 * flash_p, Color(0.95, 0.25, 0.75, flash_p * 0.38))
