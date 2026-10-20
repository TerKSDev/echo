extends Node
## Global game state (Autoload as "GameState").
## Keeps the level list and which level is currently being played.
##
## Teammates: add your finished level scenes to LEVELS (in play order).
## A level scene is a plain Node2D that holds walls, enemies, and optionally
## a Marker2D named "PlayerStart" (where the player spawns).

const MENU_SCENE := "res://ui/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

const LEVELS: Array[String] = [
	"res://levels/level_test.tscn",
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
]

var current_level := 0
var mic_enabled := true


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
