extends Control

@onready var start_button: Button = $Content/VBoxContainer/StartButton
@onready var settings_button: Button = $Content/VBoxContainer/SettingsButton
@onready var how_to_play_button: Button = $Content/VBoxContainer/HowToPlayButton
@onready var credits_button: Button = $Content/VBoxContainer/CreditsButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	credits_button.pressed.connect(_on_credits_pressed)


func _on_start_pressed() -> void:
	GameState.start_game()


func _on_settings_pressed() -> void:
	show_message(
		"Settings",
		"Volume and sound effect settings will be available here."
	)


func _on_how_to_play_pressed() -> void:
	show_message(
		"How to Play",
		"Click the screen to emit a sound wave.\n\n"
		+ "Sound waves reveal the surrounding cave.\n"
		+ "Louder sounds travel farther,\n"
		+ "but may attract enemies in the darkness.\n\n"
		+ "Use sound to find your way out.\n"
		+ "Stay quiet. Stay alive."
	)


func _on_credits_pressed() -> void:
	show_message(
		"Credits",
		"ECHO: Sound in the Darkness\n\n"
		+ "Game Design: Team Members\n"
		+ "Programming: Team Members\n"
		+ "Art Design: Team Members\n"
		+ "Sound Design: Team Members"
	)


func show_message(title_text: String, body_text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title_text
	dialog.dialog_text = body_text

	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

	add_child(dialog)
	dialog.popup_centered()
