extends Node
class_name MicInput

# Handles microphone input and detects voice activity based on loudness.
signal voice_detected(loudness: float)

const BUS_NAME := "MicCapture"
const PERMISSION := "android.permission.RECORD_AUDIO"
const CALIBRATE_TIME := 1.0 # Time in seconds to calibrate the microphone
const TRIGGER_MARGIN_DB := 10.0 # Margin in dB above the calibrated noise floor to trigger voice detection
const MAX_MARGIN_DB := 30.0 # Maximum margin in dB to avoid false positives
const ATTACK_WINDOW := 0.1 # Time in seconds to consider as an attack window for voice detection
const COOLDOWN := 0.5 # Time in seconds to wait before allowing another voice detection

enum State {
	CALIBRATING,
	IDLE,
	ATTACK,
	COOLDOWN
}

var enabled := false
var level_db := -80.0
var noise_floor_db := -50.0

var _capture: AudioEffectCapture
var _state := State.CALIBRATING
var _timer := 0.0
var _peak_db := -80.0
var _calib_max := -80.0

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
	if enabled:
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_mute(idx, true)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture

	var player_mic := AudioStreamPlayer.new()
	player_mic.stream = AudioStreamMicrophone.new()
	player_mic.bus = BUS_NAME
	add_child(player_mic)
	player_mic.play()

	_state = State.CALIBRATING
	_timer = 0.0
	_calib_max = -80.0
	enabled = true

func _process(delta: float) -> void:
	if not enabled:
		return

	var peak := 0.0
	var frame := _capture.get_frames_available()
	if frame > 0:
		for buffer in _capture.get_buffer(frame):
			peak = maxf(peak, maxf(absf(buffer.x), absf(buffer.y)))
	level_db = linear_to_db(maxf(peak, 0.00001)) # Avoid log(0) by using a small value
	_timer += delta

	match _state:
		State.CALIBRATING:
			_calib_max = max(_calib_max, level_db)
			if _timer >= CALIBRATE_TIME:
				noise_floor_db = maxf(_calib_max, -50.0)
				_state = State.IDLE
				print("Calibration complete. Noise floor set to:", noise_floor_db, "dB")

		State.IDLE:
			if level_db > noise_floor_db + TRIGGER_MARGIN_DB:
				_state = State.ATTACK
				_timer = 0.0
				_peak_db = level_db
		
		State.ATTACK:
			_peak_db = maxf(_peak_db, level_db)
			if _timer >= ATTACK_WINDOW:
				var lowest := noise_floor_db + TRIGGER_MARGIN_DB
				# A peak can never exceed 0 dB, so keep the upper bound reachable
				var highest := maxf(minf(noise_floor_db + MAX_MARGIN_DB, -1.0), lowest + 1.0)
				var k := clampf(inverse_lerp(lowest, highest, _peak_db), 0.0, 1.0)

				voice_detected.emit(k)
				_state = State.COOLDOWN
				_timer = 0.0
		State.COOLDOWN:
			if _timer >= COOLDOWN:
				_state = State.IDLE