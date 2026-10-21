extends PointLight2D
## 声波光源:玩家发出声音时,在声源位置扩散一圈光环。
## 光环被 LightOccluder2D(墙)挡住,从而照出墙的轮廓。

@export var player_path: NodePath = ^"../../Player"
## 响度 -> 半径(像素)。步行 0.05≈80px,大喊 0.25≈400px。
@export var radius_per_loudness := 1600.0
@export var min_radius := 48.0
@export var duration := 0.9
@export var peak_energy := 1.6

const TEXTURE_RADIUS := 256.0 # 纹理 512px 的一半

var _tween: Tween


func _ready() -> void:
	enabled = false
	shadow_enabled = true
	var player := get_node_or_null(player_path)
	if player and player.has_signal("sound_emitted"):
		player.sound_emitted.connect(_on_sound_emitted)
	else:
		push_warning("SoundWave: 找不到玩家或 sound_emitted 信号 (%s)" % player_path)


func _on_sound_emitted(pos: Vector2, loudness: float, _is_voice: bool) -> void:
	emit_wave(pos, maxf(loudness * radius_per_loudness, min_radius))


func emit_wave(pos: Vector2, radius: float) -> void:
	if _tween:
		_tween.kill()
	global_position = pos
	texture_scale = 0.05
	energy = peak_energy
	enabled = true

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "texture_scale", radius / TEXTURE_RADIUS, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "energy", 0.0, duration).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void: enabled = false)
