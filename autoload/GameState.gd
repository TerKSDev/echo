extends Node
## Global game state (Autoload as "GameState").
## Keeps the level list, current level, and persistent audio/microphone settings
## automatically saved to `user://settings.cfg`.

const MENU_SCENE := "res://ui/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL_SELECT_SCENE := "res://ui/level_select.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://level_progress.cfg"

const LEVELS: Array[String] = [
	"res://levels/level_test.tscn",
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
]

const SECTORS: Array[Dictionary] = [
	{"name": "ABYSS ORIGIN", "depth": "-2,680 M"},
	{"name": "VOID CAVITY", "depth": "-2,360 M"},
	{"name": "SUB-CRUST TRENCH", "depth": "-2,060 M"},
	{"name": "LURKING VAULT", "depth": "-1,780 M"},
	{"name": "OBSIDIAN LABYRINTH", "depth": "-1,520 M"},
	{"name": "ECHO CHAMBER", "depth": "-1,280 M"},
	{"name": "BASALT TUNNELS", "depth": "-1,060 M"},
	{"name": "SCREAMER NEST", "depth": "-850 M"},
	{"name": "THE SILENT POOL", "depth": "-660 M"},
	{"name": "CRYSTAL DRIFT", "depth": "-480 M"},
	{"name": "BONE HOLLOW", "depth": "-320 M"},
	{"name": "WHISPER CHASM", "depth": "-160 M"},
	{"name": "SURFACE BREACH", "depth": "-40 M"},
]

var current_level := 0
var highest_unlocked_level := 1

func get_level_name(lvl: int) -> String:
	var idx := lvl - 1
	if idx >= 0 and idx < SECTORS.size():
		return str(SECTORS[idx]["name"])
	return "TRAINING GROUNDS" if lvl == 0 else "CAVERN SECTOR %02d" % lvl

func get_level_depth_str(lvl: int) -> String:
	var idx := lvl - 1
	if idx >= 0 and idx < SECTORS.size():
		var raw: String = str(SECTORS[idx]["depth"])
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
const SETTINGS_SCENE := "res://ui/settings_scene.tscn"
var previous_scene_path: String = LEVEL_SELECT_SCENE


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
	return LEVELS[clampi(current_level, 0, LEVELS.size() - 1)]


func has_next_level() -> bool:
	return current_level + 1 < LEVELS.size()


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
		var fade_in := curtain.create_tween()
		fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_in.tween_interval(0.04)
		fade_in.tween_property(curtain, "color:a", 0.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(func():
			_is_transitioning = false
			curtain_layer.queue_free()
		)
	)


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


func reset_progress() -> void:
	highest_unlocked_level = 1
	current_level = 0
	level_records.clear()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "highest_unlocked_level", 1)
	cfg.save(PROGRESS_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	level_records.clear()
	if cfg.load(PROGRESS_PATH) != OK:
		highest_unlocked_level = 1
		return

	highest_unlocked_level = clampi(
		int(cfg.get_value("progress", "highest_unlocked_level", 1)),
		1,
		13
	)

	for i in range(1, 14):
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
	# 只接受正式关卡 1 到 13。
	if level_number < 1 or level_number > 13:
		return

	# 完成当前关卡后开放下一关。
	# 完成第 13 关时，仍然记录最高解锁关卡为 13。
	var next_unlocked := mini(level_number + 1, 13)

	if next_unlocked > highest_unlocked_level:
		highest_unlocked_level = next_unlocked

	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value(
		"progress",
		"highest_unlocked_level",
		highest_unlocked_level
	)
	var error := cfg.save(PROGRESS_PATH)

	if error != OK:
		push_error("Failed to save level progress: %s" % error)
