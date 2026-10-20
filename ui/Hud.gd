extends CanvasLayer

@onready var player = get_node_or_null("../Player")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player != null:
		$SoundBtn.button_down.connect(player.start_charge)
		$SoundBtn.button_up.connect(player.release_charge)
		$SneakBtn.pressed.connect(player.toggle_sneak)
		if player.has_node("MicInput"):
			var mic = player.get_node("MicInput")
			if mic != null and mic.has_signal("voice_detected"):
				mic.voice_detected.connect(_on_voice_detected)

	if has_node("PauseBtn") and has_node("SettingsModal"):
		$PauseBtn.pressed.connect($SettingsModal.open)

func _on_voice_detected(_loudness: float) -> void:
	if has_node("MicIndicator"):
		$MicIndicator.pulse_flash()