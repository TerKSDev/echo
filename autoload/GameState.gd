extends Node
## Global game state (Autoload as "GameState").
## Keeps the level list, current level, and persistent audio/microphone settings
## automatically saved to `user://settings.cfg`.

const MENU_SCENE := "res://ui/screens/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL_SELECT_SCENE := "res://ui/screens/level_select.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://level_progress.cfg"

enum GameMode { STORY, CHALLENGE }
var current_mode: GameMode = GameMode.STORY

const TEST_LEVEL_PATH := "res://levels/level_test.tscn"

# Story Mode: 21 Levels (Level 0: Tutorial + Level 01 ~ Level 20)
const STORY_LEVELS: Array[String] = [
	"res://levels/level_0.tscn",
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
]

# Challenge Mode (Rogue-like Abyss): 21 Levels (Level 01 ~ Level 20 + Level SP as King/Boss Sector)
const CHALLENGE_LEVELS: Array[String] = [
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
	"res://levels/level_SP.tscn",
]

# Backwards compatibility list containing all registered game scenes
const LEVELS: Array[String] = [
	"res://levels/level_test.tscn",
	"res://levels/level_0.tscn",
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
	"res://levels/level_SP.tscn",
]

# Story Mode: Even, satisfying ~220m depth steps ascending from -4,200M (Abyss Origin) to -40M (Surface Breach)
const STORY_SECTORS: Array[Dictionary] = [
	{"name": "ABYSS ORIGIN", "depth": "-4,200 M"},
	{"name": "VOID CAVITY", "depth": "-3,980 M"},
	{"name": "SUB-CRUST TRENCH", "depth": "-3,760 M"},
	{"name": "LURKING VAULT", "depth": "-3,540 M"},
	{"name": "OBSIDIAN LABYRINTH", "depth": "-3,320 M"},
	{"name": "ECHO CHAMBER", "depth": "-3,100 M"},
	{"name": "BASALT TUNNELS", "depth": "-2,880 M"},
	{"name": "SCREAMER NEST", "depth": "-2,660 M"},
	{"name": "THE SILENT POOL", "depth": "-2,440 M"},
	{"name": "CRYSTAL DRIFT", "depth": "-2,220 M"},
	{"name": "BONE HOLLOW", "depth": "-2,000 M"},
	{"name": "WHISPER CHASM", "depth": "-1,780 M"},
	{"name": "MUDDY DUNGEON", "depth": "-1,560 M"},
	{"name": "BLIND SHAFTS", "depth": "-1,340 M"},
	{"name": "THE LISTENING EYE", "depth": "-1,120 M"},
	{"name": "DROWNED RETURN", "depth": "-900 M"},
	{"name": "THREE CROSSINGS", "depth": "-680 M"},
	{"name": "RIPPLES IN THE DARK", "depth": "-460 M"},
	{"name": "ECHOING PASSAGE", "depth": "-240 M"},
	{"name": "SURFACE BREACH", "depth": "-40 M"},
]

# Challenge Mode: Plunges from -4,500M down to -9,999M (King Sector: The Final Echo)
const CHALLENGE_SECTORS: Array[Dictionary] = [
	{"name": "ABYSS DESCENT I", "depth": "-4,500 M"},
	{"name": "HOLLOW VOID", "depth": "-4,750 M"},
	{"name": "DEEP RIFT", "depth": "-5,000 M"},
	{"name": "OBSIDIAN CHASM", "depth": "-5,250 M"},
	{"name": "SILENT LABYRINTH", "depth": "-5,500 M"},
	{"name": "ECHO SANCTUARY", "depth": "-5,750 M"},
	{"name": "SCREAMING VEIN", "depth": "-6,000 M"},
	{"name": "SUB-OCEAN TRENCH", "depth": "-6,250 M"},
	{"name": "STILLWATER ABYSS", "depth": "-6,500 M"},
	{"name": "FORBIDDEN DRIFT", "depth": "-6,750 M"},
	{"name": "ANCIENT HOLLOW", "depth": "-7,000 M"},
	{"name": "VOID NEXUS", "depth": "-7,250 M"},
	{"name": "SPECTRAL VAULT", "depth": "-7,500 M"},
	{"name": "SHADOW WELL", "depth": "-7,750 M"},
	{"name": "BLIND ABYSS", "depth": "-8,000 M"},
	{"name": "CRIMSON STRATA", "depth": "-8,250 M"},
	{"name": "FORGOTTEN CRYPT", "depth": "-8,500 M"},
	{"name": "PRIMORDIAL TRENCH", "depth": "-8,750 M"},
	{"name": "THE DARK SPINE", "depth": "-9,000 M"},
	{"name": "VOID THRESHOLD", "depth": "-9,250 M"},
	{"name": "KING SECTOR • THE FINAL ECHO", "depth": "-9,999 M"},
]

# Alias for backwards compatibility
const SECTORS: Array[Dictionary] = STORY_SECTORS

var current_level := 0
var story_highest_unlocked := 1
var challenge_highest_unlocked := 1
var story_completed := false

var highest_unlocked_level: int:
	get:
		if current_mode == GameMode.CHALLENGE:
			return challenge_highest_unlocked
		return story_highest_unlocked
	set(val):
		if current_mode == GameMode.CHALLENGE:
			challenge_highest_unlocked = val
		else:
			story_highest_unlocked = val

func is_story_completed() -> bool:
	return story_completed or story_highest_unlocked > STORY_LEVELS.size()

func get_current_levels() -> Array[String]:
	if current_mode == GameMode.CHALLENGE:
		return CHALLENGE_LEVELS
	return STORY_LEVELS

func get_level_name(lvl: int) -> String:
	if current_mode == GameMode.CHALLENGE:
		var c_idx := lvl - 1 if lvl > 0 else 0
		if c_idx >= 0 and c_idx < CHALLENGE_SECTORS.size():
			return str(CHALLENGE_SECTORS[c_idx]["name"])
		return "CHALLENGE SECTOR %02d" % lvl

	# Story Mode
	if lvl == 0:
		return "TRAINING GROUNDS"
	var idx := lvl - 1
	if idx >= 0 and idx < STORY_SECTORS.size():
		return str(STORY_SECTORS[idx]["name"])
	return "CAVERN SECTOR %02d" % lvl

func get_level_depth_str(lvl: int) -> String:
	if current_mode == GameMode.CHALLENGE:
		var c_idx := lvl - 1 if lvl > 0 else 0
		if c_idx >= 0 and c_idx < CHALLENGE_SECTORS.size():
			var raw: String = str(CHALLENGE_SECTORS[c_idx]["depth"])
			return "~" + raw.replace("-", "").strip_edges()
		return "~4,500 M"

	# Story Mode
	if lvl == 0:
		return "TRAINING BASE"
	var idx := lvl - 1
	if idx >= 0 and idx < STORY_SECTORS.size():
		var raw: String = str(STORY_SECTORS[idx]["depth"])
		return "~" + raw.replace("-", "").strip_edges()
	return "~0 M"

# Evocative philosophical explorer recovery logs (convey positive psychological resilience & mindfulness)
const SECTOR_LOGS: Dictionary = {
	1: "In deepest dark, silence is not emptiness—it is your canvas.",
	2: "Sound travels far down straight halls, but calmness travels further.",
	3: "Move gently. The abyss reflects only what you project.",
	4: "A quiet diversion overcomes sheer brute force.",
	5: "Patience unmasks every wall; panic only builds more.",
	6: "Listen closely: every obstacle has an echo that reveals the path forward.",
	7: "Walk with care. Subterranean pressure turns rough stone into steadfast resolve.",
	8: "Seek shelter before the scream hits. Protection is never weakness.",
	9: "Still your waters. Inner peace disarms the raging tempest.",
	10: "In the crystalline cold, clarity shines through the dark.",
	11: "Step past dormant fears; they only awaken if you tread in haste.",
	12: "The hardest chasm is crossed not by speed, but by unwavering focus.",
	13: "Listen closely: the sound of wind returning. The light awaits.",
}

func get_sector_log(lvl: int) -> String:
	if SECTOR_LOGS.has(lvl):
		return str(SECTOR_LOGS[lvl])
	return "Stay calm. Stay silent. Follow the light."

# Level Par Benchmarks: { level_number: { "par_time": float, "par_pings": int } }
const LEVEL_PARS: Dictionary = {
	0: { "par_time": 20.0, "par_pings": 6 },    # Tutorial
	1: { "par_time": 22.0, "par_pings": 6 },    # Sector 01: Abyss Origin
	2: { "par_time": 35.0, "par_pings": 10 },   # Sector 02: Void Cavity
	3: { "par_time": 32.0, "par_pings": 8 },    # Sector 03: Sub-Crust Trench
	4: { "par_time": 40.0, "par_pings": 10 },   # Sector 04: Lurking Vault
	5: { "par_time": 45.0, "par_pings": 12 },   # Sector 05: Obsidian Labyrinth
	6: { "par_time": 48.0, "par_pings": 14 },   # Sector 06: Echo Chamber
	7: { "par_time": 52.0, "par_pings": 14 },   # Sector 07: Basalt Tunnels
	8: { "par_time": 62.0, "par_pings": 16 },   # Sector 08: Screamer Nest
	9: { "par_time": 58.0, "par_pings": 15 },   # Sector 09: The Silent Pool
	10: { "par_time": 72.0, "par_pings": 18 },  # Sector 10: Crystal Drift
	11: { "par_time": 85.0, "par_pings": 20 },  # Sector 11: Bone Hollow
	12: { "par_time": 98.0, "par_pings": 24 },  # Sector 12: Whisper Chasm
	13: { "par_time": 90.0, "par_pings": 22 },  # Sector 13: Surface Breach
}

var level_records: Dictionary = {}

# Audio Settings
var master_volume := 1.0
var master_muted := false
var bgm_volume := 0.8
var sfx_volume := 1.0

# Microphone Settings
var mic_enabled := true
var mic_sensitivity := 0.5        # 0.0 (low/strict) .. 1.0 (high/sensitive)
var mic_noise_floor_db := -48.0   # Calibrated ambient floor in dB
var mic_calibrated := false
var mic_push_to_talk := false

# Gameplay & Controls Settings
var sneak_hold_mode := false      # false = Toggle Sneak, true = Hold to Sneak
var fast_pulse_mode := false      # Double-tap / fast ping support
var sound_indicator_enabled := true # Off-screen directional sound pulse visualizer
var blind_assist_mode := true     # Visually impaired acoustic navigation (exit beacon, wall echoes, obstacle cane radar)

# Display & Graphics Settings
var fullscreen_enabled := false
var screen_shake_intensity := 1.0  # 0.0 .. 1.0 (0%, 50%, 100%)
var sonar_glow_boost := 1.0        # 0.6 .. 1.4
var vignette_enabled := true       # Pulse vignette & chromatic threat shading
var vsync_enabled := true
var max_fps := 60                  # 60, 120, 0 (uncapped)

# Advanced Settings
var sonar_palette := "cyan"        # "cyan", "emerald", "amber", "white"

# Navigation tracking
const SETTINGS_SCENE := "res://ui/screens/settings_scene.tscn"
var previous_scene_path: String = LEVEL_SELECT_SCENE

# Global Procedural Subterranean Menu & UI BGM System
const BGM_SCALE: Array[float] = [0.75, 1.0, 1.125, 1.2, 1.333, 1.5, 1.6, 1.8, 2.0]
var _bgm_pad_player: AudioStreamPlayer = null
var _wav_bgm_note: AudioStreamWAV = null
var _wav_bgm_droplet: AudioStreamWAV = null
var _bgm_note_timer := 1.2
var _bgm_drop_timer := 2.8
var _bgm_note_step := 0
var _bgm_active := false


func _ready() -> void:
	_init_audio_buses()
	load_settings()
	load_progress()
	apply_display_settings()


func _init_audio_buses() -> void:
	# 1. Master Bus Studio Limiter (prevents digital clipping/harshness during loud acoustic bursts)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		var has_limiter := false
		for eff_i in AudioServer.get_bus_effect_count(master_idx):
			if AudioServer.get_bus_effect(master_idx, eff_i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var limiter := AudioEffectLimiter.new()
			limiter.ceiling_db = -0.5
			limiter.threshold_db = 0.0
			AudioServer.add_bus_effect(master_idx, limiter)

	# 2. BGM Bus
	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx == -1:
		AudioServer.add_bus()
		bgm_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bgm_idx, "BGM")
		AudioServer.set_bus_send(bgm_idx, "Master")

	# 3. SFX Bus + Environmental Subterranean Cavern Reverb
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx == -1:
		AudioServer.add_bus()
		sfx_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")

	var has_reverb := false
	for eff_i in AudioServer.get_bus_effect_count(sfx_idx):
		if AudioServer.get_bus_effect(sfx_idx, eff_i) is AudioEffectReverb:
			has_reverb = true
			break
	if not has_reverb:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.46       # Medium-large subterranean cavern
		reverb.damping = 0.42         # Natural limestone absorption
		reverb.spread = 0.88          # Stereo immersion
		reverb.hipass = 0.12          # Retain clean punchy sub-bass
		reverb.predelay_msec = 22.0   # 22ms early reflection gap
		reverb.dry = 0.88             # Crisp direct acoustic attack
		reverb.wet = 0.16             # Delicate, lush subterranean acoustic tail
		AudioServer.add_bus_effect(sfx_idx, reverb)

	apply_audio_settings()


func apply_audio_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_mute(master_idx, master_muted)
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))

	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx != -1:
		AudioServer.set_bus_volume_db(bgm_idx, linear_to_db(maxf(bgm_volume, 0.0001)))

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_volume, 0.0001)))


# Effective dB threshold required to trigger a voice echo
func get_mic_trigger_db() -> float:
	var margin: float = lerpf(24.0, 7.0, clampf(mic_sensitivity, 0.0, 1.0))
	return clampf(mic_noise_floor_db + margin, -44.0, -14.0)


func apply_display_settings() -> void:
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


func get_sonar_color() -> Color:
	match sonar_palette:
		"emerald":
			return Color(0.20, 0.95, 0.65, 1.0)
		"amber":
			return Color(1.0, 0.78, 0.28, 1.0)
		"white":
			return Color(0.95, 0.98, 1.0, 1.0)
		_:
			return Color(0.25, 0.75, 1.0, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)

	cfg.set_value("mic", "enabled", mic_enabled)
	cfg.set_value("mic", "sensitivity", mic_sensitivity)
	cfg.set_value("mic", "noise_floor_db", mic_noise_floor_db)
	cfg.set_value("mic", "calibrated", mic_calibrated)
	cfg.set_value("mic", "push_to_talk", mic_push_to_talk)

	cfg.set_value("controls", "sneak_hold_mode", sneak_hold_mode)
	cfg.set_value("controls", "fast_pulse_mode", fast_pulse_mode)
	cfg.set_value("controls", "sound_indicator_enabled", sound_indicator_enabled)
	cfg.set_value("controls", "blind_assist_mode", blind_assist_mode)

	cfg.set_value("display", "fullscreen_enabled", fullscreen_enabled)
	cfg.set_value("display", "screen_shake_intensity", screen_shake_intensity)
	cfg.set_value("display", "sonar_glow_boost", sonar_glow_boost)
	cfg.set_value("display", "vignette_enabled", vignette_enabled)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("display", "max_fps", max_fps)

	cfg.set_value("advanced", "sonar_palette", sonar_palette)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		apply_audio_settings()
		apply_display_settings()
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	master_muted = bool(cfg.get_value("audio", "master_muted", false))
	bgm_volume = clampf(float(cfg.get_value("audio", "bgm_volume", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)

	mic_enabled = bool(cfg.get_value("mic", "enabled", true))
	mic_sensitivity = clampf(float(cfg.get_value("mic", "sensitivity", 0.5)), 0.0, 1.0)
	mic_noise_floor_db = clampf(float(cfg.get_value("mic", "noise_floor_db", -48.0)), -54.0, -34.0)
	mic_calibrated = bool(cfg.get_value("mic", "calibrated", false))
	mic_push_to_talk = bool(cfg.get_value("mic", "push_to_talk", false))

	sneak_hold_mode = bool(cfg.get_value("controls", "sneak_hold_mode", false))
	fast_pulse_mode = bool(cfg.get_value("controls", "fast_pulse_mode", false))
	sound_indicator_enabled = bool(cfg.get_value("controls", "sound_indicator_enabled", true))
	blind_assist_mode = bool(cfg.get_value("controls", "blind_assist_mode", true))

	fullscreen_enabled = bool(cfg.get_value("display", "fullscreen_enabled", false))
	screen_shake_intensity = clampf(float(cfg.get_value("display", "screen_shake_intensity", 1.0)), 0.0, 1.0)
	sonar_glow_boost = clampf(float(cfg.get_value("display", "sonar_glow_boost", 1.0)), 0.6, 1.4)
	vignette_enabled = bool(cfg.get_value("display", "vignette_enabled", true))
	vsync_enabled = bool(cfg.get_value("display", "vsync_enabled", true))
	max_fps = int(cfg.get_value("display", "max_fps", 60))

	sonar_palette = str(cfg.get_value("advanced", "sonar_palette", "cyan"))

	apply_audio_settings()
	apply_display_settings()


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func set_master_muted(muted: bool) -> void:
	master_muted = muted
	apply_audio_settings()
	save_settings()


func set_bgm_volume(val: float) -> void:
	bgm_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func current_level_path() -> String:
	var lvls := get_current_levels()
	if current_level >= 0 and current_level < lvls.size():
		return lvls[current_level]
	return lvls[0]


func has_next_level() -> bool:
	return current_level + 1 < get_current_levels().size()


var _is_transitioning := false


func transition_to_scene(scene_path: String, fade_out_dur: float = 0.22, fade_in_dur: float = 0.28, on_mid_transition: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var curtain_layer := CanvasLayer.new()
	curtain_layer.layer = 256
	curtain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(curtain_layer)

	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.01, 0.02, 0.04, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain_layer.add_child(curtain)

	var tw := curtain.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(curtain, "color:a", 1.0, fade_out_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		get_tree().paused = false
		if on_mid_transition.is_valid():
			on_mid_transition.call()
		var err := get_tree().change_scene_to_file(scene_path)
		if err != OK:
			push_error("Failed to change scene to %s: %s" % [scene_path, err])
		_sync_bgm_for_scene(scene_path)
		var fade_in := curtain.create_tween()
		fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_in.tween_interval(0.04)
		fade_in.tween_property(curtain, "color:a", 0.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(func():
			_is_transitioning = false
			curtain_layer.queue_free()
		)
	)


func change_level(target) -> void:
	if target is int:
		start_game(target)
	elif target is String:
		var lvls := get_current_levels()
		var actual_idx: int = lvls.find(target)
		if actual_idx != -1:
			start_game(actual_idx)
		else:
			if target == "res://levels/level_SP.tscn":
				current_mode = GameMode.CHALLENGE
				var sp_idx: int = CHALLENGE_LEVELS.find(target)
				start_game(sp_idx if sp_idx != -1 else 0)
			else:
				var glob_idx: int = LEVELS.find(target)
				if glob_idx != -1:
					start_game(glob_idx)
				else:
					transition_to_scene(target)


func start_game(level_index: int = 0) -> void:
	current_level = level_index
	transition_to_scene(MAIN_SCENE, 0.22, 0.28)


func next_level() -> void:
	if has_next_level():
		start_game(current_level + 1)
	else:
		go_to_level_select()


func restart_level(fade_out_dur: float = 0.18, fade_in_dur: float = 0.22) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var curtain_layer := CanvasLayer.new()
	curtain_layer.layer = 256
	curtain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(curtain_layer)

	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.01, 0.02, 0.04, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain_layer.add_child(curtain)

	var tw := curtain.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(curtain, "color:a", 1.0, fade_out_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
		var fade_in := curtain.create_tween()
		fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_in.tween_interval(0.04)
		fade_in.tween_property(curtain, "color:a", 0.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(func():
			_is_transitioning = false
			curtain_layer.queue_free()
		)
	)


func go_to_level_select() -> void:
	transition_to_scene(LEVEL_SELECT_SCENE, 0.22, 0.28)


func go_to_menu() -> void:
	transition_to_scene(MENU_SCENE, 0.22, 0.28)


func go_to_settings(from_scene: String = "") -> void:
	if from_scene != "":
		previous_scene_path = from_scene
	else:
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != "":
			previous_scene_path = cur.scene_file_path
	transition_to_scene(SETTINGS_SCENE, 0.22, 0.28)


func return_from_settings() -> void:
	var target := previous_scene_path
	if target.is_empty():
		target = LEVEL_SELECT_SCENE
	transition_to_scene(target, 0.22, 0.28)


func go_to_previous_scene() -> void:
	return_from_settings()


func reset_to_defaults() -> void:
	master_muted = false
	master_volume = 1.0
	bgm_volume = 0.8
	sfx_volume = 1.0
	mic_enabled = true
	mic_sensitivity = 0.5
	mic_push_to_talk = false
	sneak_hold_mode = false
	fast_pulse_mode = false
	sound_indicator_enabled = true
	blind_assist_mode = true
	fullscreen_enabled = false
	screen_shake_intensity = 1.0
	sonar_glow_boost = 1.0
	vignette_enabled = true
	vsync_enabled = true
	max_fps = 60
	sonar_palette = "cyan"
	apply_audio_settings()
	apply_display_settings()
	save_settings()


func reset_progress() -> void:
	story_highest_unlocked = 1
	challenge_highest_unlocked = 1
	story_completed = false
	current_level = 0
	level_records.clear()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "highest_unlocked_level", 1)
	cfg.set_value("progress", "story_highest_unlocked", 1)
	cfg.set_value("progress", "challenge_highest_unlocked", 1)
	cfg.set_value("progress", "story_completed", false)
	cfg.save(PROGRESS_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	level_records.clear()
	if cfg.load(PROGRESS_PATH) != OK:
		story_highest_unlocked = 1
		challenge_highest_unlocked = 1
		story_completed = false
		return

	var legacy_highest: int = int(cfg.get_value("progress", "highest_unlocked_level", 1))
	story_highest_unlocked = clampi(
		int(cfg.get_value("progress", "story_highest_unlocked", legacy_highest)),
		1,
		STORY_LEVELS.size() + 1
	)
	challenge_highest_unlocked = clampi(
		int(cfg.get_value("progress", "challenge_highest_unlocked", 1)),
		1,
		CHALLENGE_LEVELS.size() + 1
	)
	story_completed = bool(cfg.get_value("progress", "story_completed", story_highest_unlocked > STORY_LEVELS.size()))

	var max_entries := maxi(STORY_LEVELS.size(), CHALLENGE_LEVELS.size()) + 2
	for i in range(1, max_entries + 1):
		var sec := "level_%02d" % i
		if cfg.has_section(sec):
			level_records[i] = {
				"survivor": bool(cfg.get_value(sec, "survivor", true)),
				"ghost": bool(cfg.get_value(sec, "ghost", false)),
				"swift": bool(cfg.get_value(sec, "swift", false)),
				"best_time": float(cfg.get_value(sec, "best_time", 999.0)),
				"best_pings": int(cfg.get_value(sec, "best_pings", 999)),
				"stars": int(cfg.get_value(sec, "stars", 1)),
			}


func get_level_par(lvl: int) -> Dictionary:
	if LEVEL_PARS.has(lvl):
		return LEVEL_PARS[lvl]
	return { "par_time": 45.0, "par_pings": 12 }


func get_level_stars(lvl: int) -> int:
	if level_records.has(lvl):
		return int(level_records[lvl].get("stars", 0))
	return 0


func get_level_best_time(lvl: int) -> float:
	if level_records.has(lvl):
		return float(level_records[lvl].get("best_time", 0.0))
	return 0.0


func is_level_ghost_cleared(lvl: int) -> bool:
	if level_records.has(lvl):
		return bool(level_records[lvl].get("ghost", false))
	return false


func record_level_clear(level_number: int, clear_time: float, pings: int, alerts: int) -> Dictionary:
	# Unlock next level in campaign
	complete_level(level_number)

	var par: Dictionary = get_level_par(level_number)
	var par_time: float = float(par.get("par_time", 45.0))
	var par_pings: int = int(par.get("par_pings", 12))

	var is_survivor := true
	var is_ghost := (alerts == 0)
	var is_swift := (clear_time <= par_time)

	var rec: Dictionary = level_records.get(level_number, {
		"survivor": false,
		"ghost": false,
		"swift": false,
		"best_time": 999.0,
		"best_pings": 999,
		"stars": 0
	})

	var prior_ghost: bool = bool(rec.get("ghost", false))
	var prior_swift: bool = bool(rec.get("swift", false))
	var prior_best_time: float = float(rec.get("best_time", 999.0))
	var prior_best_pings: int = int(rec.get("best_pings", 999))

	var new_ghost: bool = prior_ghost or is_ghost
	var new_swift: bool = prior_swift or is_swift
	var new_best_time: float = minf(prior_best_time, clear_time)
	var new_best_pings: int = mini(prior_best_pings, pings)

	var total_stars := 1 + (1 if new_ghost else 0) + (1 if new_swift else 0)
	var run_stars := 1 + (1 if is_ghost else 0) + (1 if is_swift else 0)

	rec["survivor"] = true
	rec["ghost"] = new_ghost
	rec["swift"] = new_swift
	rec["best_time"] = new_best_time
	rec["best_pings"] = new_best_pings
	rec["stars"] = total_stars
	level_records[level_number] = rec

	# Save records to progress config
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "highest_unlocked_level", highest_unlocked_level)
	var sec := "level_%02d" % level_number
	cfg.set_value(sec, "survivor", true)
	cfg.set_value(sec, "ghost", new_ghost)
	cfg.set_value(sec, "swift", new_swift)
	cfg.set_value(sec, "best_time", new_best_time)
	cfg.set_value(sec, "best_pings", new_best_pings)
	cfg.set_value(sec, "stars", total_stars)
	cfg.save(PROGRESS_PATH)

	return {
		"level_number": level_number,
		"clear_time": clear_time,
		"pings": pings,
		"alerts": alerts,
		"par_time": par_time,
		"par_pings": par_pings,
		"is_survivor": is_survivor,
		"is_ghost": is_ghost,
		"is_swift": is_swift,
		"run_stars": run_stars,
		"total_stars": total_stars,
		"is_new_best_time": (clear_time < prior_best_time)
	}


func complete_level(level_number: int) -> void:
	var active_levels := get_current_levels()
	if level_number < 1 or level_number > active_levels.size():
		return

	# Complete current level and unlock next level
	var next_unlocked := mini(level_number + 1, active_levels.size() + 1)

	if current_mode == GameMode.STORY:
		if next_unlocked > story_highest_unlocked:
			story_highest_unlocked = next_unlocked
		if level_number >= active_levels.size() or story_highest_unlocked > active_levels.size():
			story_completed = true
	else:
		if next_unlocked > challenge_highest_unlocked:
			challenge_highest_unlocked = next_unlocked

	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "highest_unlocked_level", story_highest_unlocked)
	cfg.set_value("progress", "story_highest_unlocked", story_highest_unlocked)
	cfg.set_value("progress", "challenge_highest_unlocked", challenge_highest_unlocked)
	cfg.set_value("progress", "story_completed", story_completed)
	var error := cfg.save(PROGRESS_PATH)

	if error != OK:
		push_error("Failed to save level progress: %s" % error)


func start_menu_bgm() -> void:
	if _bgm_pad_player == null:
		_setup_menu_bgm()
	_bgm_active = true
	if _bgm_pad_player != null and not _bgm_pad_player.playing:
		_bgm_pad_player.volume_db = -26.0
		_bgm_pad_player.play()
		var tw := create_tween()
		tw.tween_property(_bgm_pad_player, "volume_db", -7.5, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func stop_menu_bgm(fade_dur: float = 0.4) -> void:
	_bgm_active = false
	if _bgm_pad_player != null and _bgm_pad_player.playing:
		var tw := create_tween()
		tw.tween_property(_bgm_pad_player, "volume_db", -40.0, fade_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if not _bgm_active and _bgm_pad_player != null:
				_bgm_pad_player.stop()
		)


func _setup_menu_bgm() -> void:
	_wav_bgm_note = SfxManager.get_menu_bgm_note()
	_wav_bgm_droplet = SfxManager.get_menu_bgm_droplet()

	_bgm_pad_player = AudioStreamPlayer.new()
	_bgm_pad_player.name = "GlobalMenuBGM"
	_bgm_pad_player.stream = SfxManager.get_menu_bgm_pad()
	_bgm_pad_player.bus = &"BGM"
	_bgm_pad_player.volume_db = -26.0
	add_child(_bgm_pad_player)


func _process(delta: float) -> void:
	if not _bgm_active or _bgm_pad_player == null or not _bgm_pad_player.playing:
		return

	_bgm_pad_player.volume_db = lerpf(_bgm_pad_player.volume_db, -7.5, clampf(delta * 4.0, 0.0, 1.0))

	# Generative crystalline echo notes (A minor / Dorian motif)
	_bgm_note_timer -= delta
	if _bgm_note_timer <= 0.0:
		_bgm_note_timer = randf_range(2.8, 4.8)
		var motif_indices: Array[int] = [1, 4, 3, 1, 5, 3, 2, 0, 1, 6, 4, 3]
		var idx: int = motif_indices[_bgm_note_step % motif_indices.size()]
		_bgm_note_step += 1
		var pitch: float = BGM_SCALE[idx]
		_play_bgm_sfx(_wav_bgm_note, randf_range(-11.5, -8.5), pitch)

		if randf() < 0.45:
			var ans_pitch: float = BGM_SCALE[(idx + 2) % BGM_SCALE.size()]
			get_tree().create_timer(0.44).timeout.connect(func():
				if _bgm_active:
					_play_bgm_sfx(_wav_bgm_note, -13.5, ans_pitch)
			)

	# Subterranean cavern water droplets
	_bgm_drop_timer -= delta
	if _bgm_drop_timer <= 0.0:
		_bgm_drop_timer = randf_range(4.2, 7.8)
		_play_bgm_sfx(_wav_bgm_droplet, randf_range(-13.0, -9.5), randf_range(0.84, 1.26))


func _play_bgm_sfx(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if stream == null or not _bgm_active:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"BGM"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _sync_bgm_for_scene(target_path: String) -> void:
	if "headphone_warning" in target_path:
		stop_menu_bgm(0.1)
	elif target_path == MAIN_SCENE or target_path.begins_with("res://levels/"):
		stop_menu_bgm(0.35)
	else:
		start_menu_bgm()
