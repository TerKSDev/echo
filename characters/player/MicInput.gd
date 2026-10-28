extends Node
class_name MicInput

# Handles microphone input, user calibration, and voice activity detection.
signal voice_detected(loudness: float)
signal calibration_finished(floor_db: float)

const BUS_NAME := "MicCapture"
const PERMISSION := "android.permission.RECORD_AUDIO"
const WARMUP_TIME := 0.15
const CALIBRATE_TIME := 1.0
const MAX_MARGIN_DB := 24.0
const ATTACK_WINDOW := 0.09
const COOLDOWN := 0.85

enum State {
	CALIBRATING,
	IDLE,
	ATTACK,
	COOLDOWN
}

var enabled := false
var level_db := -80.0
var noise_floor_db := -48.0
var suppress_timer := 0.0

var _capture: AudioEffectCapture
var _state := State.IDLE
var _timer := 0.0
var _peak_db := -80.0
var _calib_peak := -80.0
var _calib_sum := 0.0
var _calib_count := 0


func _ready() -> void:
	# Allow MicInput to run while paused so the Settings Modal can show live mic levels & calibrate
	process_mode = Node.PROCESS_MODE_ALWAYS


func start() -> void:
	if enabled:
		return
	if OS.get_name() == "Android" and not PERMISSION in OS.get_granted_permissions():
		if not get_tree().on_request_permissions_result.is_connected(_on_permission_result):
			get_tree().on_request_permissions_result.connect(_on_permission_result)
		OS.request_permissions()
	else:
		_setup()


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission != PERMISSION:
		return
	get_tree().on_request_permissions_result.disconnect(_on_permission_result)
	if granted:
		_setup()
	else:
		print("Microphone permission denied. Only button press detection will work.")


func _setup() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	elif AudioServer.get_bus_effect_count(idx) == 0:
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())

	# Ensure bus is unmuted so AudioEffectCapture receives samples,
	# but keep volume at -80 dB to prevent speaker/headphone feedback loop!
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, -80.0)
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	if _capture != null:
		_capture.clear_buffer()

	var player_mic := AudioStreamPlayer.new()
	player_mic.stream = AudioStreamMicrophone.new()
	player_mic.bus = BUS_NAME
	add_child(player_mic)
	player_mic.play()

	enabled = GameState.mic_enabled
	noise_floor_db = GameState.mic_noise_floor_db
	if not GameState.mic_calibrated:
		recalibrate()
	else:
		_state = State.IDLE
		_timer = 0.0


# Starts a fresh 1.0s room ambient noise calibration
func recalibrate() -> void:
	if _capture != null:
		_capture.clear_buffer()
	_state = State.CALIBRATING
	_timer = 0.0
	_calib_peak = -80.0
	_calib_sum = 0.0
	_calib_count = 0


func is_calibrating() -> bool:
	return _state == State.CALIBRATING


func suppress(duration: float) -> void:
	suppress_timer = maxf(suppress_timer, duration)
	if _capture != null:
		_capture.clear_buffer()
	if _state == State.ATTACK:
		_state = State.IDLE
		_timer = 0.0


func get_trigger_db() -> float:
	return GameState.get_mic_trigger_db()


func get_current_db() -> float:
	return level_db


func is_input_allowed() -> bool:
	if get_tree().paused or suppress_timer > 0.0:
		return false
	var p := get_parent()
	if p == null or not is_instance_valid(p):
		return false
	if ("alive" in p and not p.alive) or ("can_sound" in p and not p.can_sound):
		return false
	var main := p.get_parent()
	if main != null and is_instance_valid(main):
		if "_changing" in main and main._changing:
			return false
		if main.has_node("Hud"):
			var hud = main.get_node("Hud")
			if hud != null:
				if hud.has_node("StoryOverlay"):
					var so = hud.get_node("StoryOverlay")
					if so != null and (so.visible or (so.has_method("is_active") and so.is_active()) or so.get("_is_active") == true):
						return false
				if hud.has_node("DebriefModal") and hud.get_node("DebriefModal").visible:
					return false
				if hud.get("_debrief_modal") != null and is_instance_valid(hud.get("_debrief_modal")) and hud.get("_debrief_modal").visible:
					return false
				if hud.has_node("DeathScreen") and hud.get_node("DeathScreen").visible:
					return false
				if hud.has_node("VictoryScreen") and hud.get_node("VictoryScreen").visible:
					return false
				if hud.has_node("NoteReadModal") and hud.get_node("NoteReadModal").visible:
					return false
	return true


func _process(delta: float) -> void:
	if suppress_timer > 0.0:
		suppress_timer = maxf(0.0, suppress_timer - delta)
		if _capture != null:
			_capture.clear_buffer()
		level_db = -80.0
		if _state != State.CALIBRATING:
			_state = State.IDLE
		return

	if not enabled:
		if _capture != null:
			_capture.clear_buffer()
		level_db = -80.0
		return

	var peak := 0.0
	if _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			var buf := _capture.get_buffer(frames)
			var stride := 4 if frames > 256 else 1
			for i in range(0, frames, stride):
				var sample: Vector2 = buf[i]
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
			level_db = linear_to_db(maxf(peak, 0.00001))
		else:
			level_db = move_toward(level_db, -80.0, delta * 95.0)

	_timer += delta
	var trigger_db: float = get_trigger_db()

	match _state:
		State.CALIBRATING:
			if _timer >= WARMUP_TIME and level_db > -78.0:
				var clamped_sample: float = minf(level_db, -32.0)
				_calib_peak = maxf(_calib_peak, clamped_sample)
				_calib_sum += clamped_sample
				_calib_count += 1
			if _timer >= CALIBRATE_TIME:
				var avg_db: float = (_calib_sum / float(_calib_count)) if _calib_count > 0 else -50.0
				# Blend average and peak of ambient noise so breathing/hum stays safely below floor
				var measured_floor: float = lerpf(avg_db, maxf(_calib_peak, avg_db), 0.6)
				noise_floor_db = clampf(measured_floor, -54.0, -34.0)
				GameState.mic_noise_floor_db = noise_floor_db
				GameState.mic_calibrated = true
				GameState.save_settings()
				_state = State.IDLE
				_timer = 0.0
				calibration_finished.emit(noise_floor_db)

		State.IDLE:
			# Do not emit gameplay voice echoes while paused, suppressed, or when sound is locked
			if not is_input_allowed():
				return
			if level_db > trigger_db:
				_state = State.ATTACK
				_timer = 0.0
				_peak_db = level_db

		State.ATTACK:
			if not is_input_allowed():
				_state = State.IDLE
				return
			_peak_db = maxf(_peak_db, level_db)
			# Discard brief transient clicks/spikes (chassis taps, speaker pop) that do not sustain
			if level_db < trigger_db - 4.0:
				_state = State.IDLE
				return
			if _timer >= ATTACK_WINDOW:
				var lowest: float = trigger_db
				var highest: float = maxf(minf(lowest + MAX_MARGIN_DB, -1.0), lowest + 1.0)
				var k: float = clampf(inverse_lerp(lowest, highest, _peak_db), 0.0, 1.0)

				voice_detected.emit(k)
				suppress(1.20) # Self-acoustic ducking: blocks echo ping and cavern reverb feedback loop!
				_state = State.COOLDOWN
				_timer = 0.0

		State.COOLDOWN:
			if _timer >= COOLDOWN:
				_state = State.IDLE
