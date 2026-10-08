extends CanvasLayer

@onready var player = get_node("../Player")

func _ready():
    $SoundBtn.button_down.connect(player.start_charge)
    $SoundBtn.button_up.connect(player.release_charge)
    $SneakBtn.pressed.connect(player.toggle_sneak)