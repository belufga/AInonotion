extends Node
## Procedural sound effects (autoload "Sfx").
##
## Every sound is synthesised at startup from filtered noise and a decaying sine thump, so the
## project needs no audio assets. Playback goes through a ring of positional players.

const RATE := 22050
const PLAYERS := 16

var _streams: Dictionary[StringName, AudioStreamWAV] = {}
var _players: Array[AudioStreamPlayer3D] = []
var _head := 0


func _ready() -> void:
	# duration, decay, low-pass, thump Hz, thump gain
	_streams[&"pistol"] = _burst(0.25, 28.0, 0.55, 190.0, 0.5)
	_streams[&"rifle"] = _burst(0.32, 20.0, 0.7, 150.0, 0.6)
	_streams[&"shotgun"] = _burst(0.5, 12.0, 0.4, 95.0, 0.9)
	_streams[&"explosion"] = _burst(1.5, 4.0, 0.12, 48.0, 1.0)
	_streams[&"impact"] = _burst(0.08, 60.0, 0.6, 320.0, 0.3)
	_streams[&"flesh"] = _burst(0.14, 32.0, 0.14, 110.0, 0.6)
	_streams[&"glass"] = _burst(0.4, 11.0, 0.95, 2600.0, 0.25)
	_streams[&"click"] = _burst(0.04, 120.0, 0.9, 1400.0, 0.3)
	_streams[&"pump"] = _burst(0.13, 34.0, 0.35, 420.0, 0.4)
	_streams[&"tool"] = _burst(0.12, 26.0, 0.25, 760.0, 0.7)
	for i in PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 14.0
		player.max_distance = 250.0
		add_child(player)
		_players.append(player)


func play(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(id):
		return
	var player := _players[_head]
	_head = (_head + 1) % PLAYERS
	player.stream = _streams[id]
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	player.play()


func _burst(duration: float, decay: float, lowpass: float, thump_hz: float, thump_gain: float) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		filtered += (randf() * 2.0 - 1.0 - filtered) * lowpass
		var sample := filtered * exp(-t * decay) + sin(TAU * thump_hz * t) * exp(-t * decay * 0.6) * thump_gain
		data.encode_s16(i * 2, int(clampf(sample * 0.8, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
