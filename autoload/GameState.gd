extends Node
## Global game state (Autoload as "GameState").
## Keeps the level list, current level, and persistent audio/microphone settings
## automatically saved to `user://settings.cfg`.

const MENU_SCENE := "res://ui/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const SETTINGS_PATH := "user://settings.cfg"

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

var current_level := 0
var master_volume := 1.0
var mic_enabled := true
var mic_sensitivity := 0.5        # 0.0 (low/strict) .. 1.0 (high/sensitive)
var mic_noise_floor_db := -48.0   # Calibrated ambient floor in dB
var mic_calibrated := false


func _ready() -> void:
	load_settings()


# Effective dB threshold required to trigger a voice echo
func get_mic_trigger_db() -> float:
	var margin: float = lerpf(24.0, 7.0, clampf(mic_sensitivity, 0.0, 1.0))
	return clampf(mic_noise_floor_db + margin, -44.0, -14.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("mic", "enabled", mic_enabled)
	cfg.set_value("mic", "sensitivity", mic_sensitivity)
	cfg.set_value("mic", "noise_floor_db", mic_noise_floor_db)
	cfg.set_value("mic", "calibrated", mic_calibrated)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	mic_enabled = bool(cfg.get_value("mic", "enabled", true))
	mic_sensitivity = clampf(float(cfg.get_value("mic", "sensitivity", 0.5)), 0.0, 1.0)
	mic_noise_floor_db = clampf(float(cfg.get_value("mic", "noise_floor_db", -48.0)), -54.0, -34.0)
	mic_calibrated = bool(cfg.get_value("mic", "calibrated", false))

	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(master_volume, 0.0001)))


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(master_volume, 0.0001)))
	save_settings()


func current_level_path() -> String:
	return LEVELS[clampi(current_level, 0, LEVELS.size() - 1)]


func has_next_level() -> bool:
	return current_level + 1 < LEVELS.size()


func start_game(level_index: int = 0) -> void:
	get_tree().paused = false
	current_level = level_index
	get_tree().change_scene_to_file(MAIN_SCENE)


func next_level() -> void:
	if has_next_level():
		start_game(current_level + 1)
	else:
		go_to_menu()


func restart_level() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
