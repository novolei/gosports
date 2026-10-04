extends Node
## Sound effects + music (autoload "Sfx"). Streams are loaded lazily from res://assets/audio.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_name := ""
var _crowd: AudioStreamPlayer
var _tween: Tween
var _loop_flags := ["crowd_loop"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	_music_b.bus = "Music"
	add_child(_music_a)
	add_child(_music_b)
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = "SFX"
	_crowd.volume_db = -14.0
	add_child(_crowd)
	apply_volumes()


func _ensure_bus(n: String) -> void:
	if AudioServer.get_bus_index(n) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, n)
		AudioServer.set_bus_send(idx, "Master")


func apply_volumes() -> void:
	var m := AudioServer.get_bus_index("Music")
	var s := AudioServer.get_bus_index("SFX")
	if m >= 0:
		AudioServer.set_bus_volume_db(m, linear_to_db(maxf(Game.settings["music"], 0.0001)))
		AudioServer.set_bus_mute(m, Game.settings["music"] <= 0.001)
	if s >= 0:
		AudioServer.set_bus_volume_db(s, linear_to_db(maxf(Game.settings["sfx"], 0.0001)))
		AudioServer.set_bus_mute(s, Game.settings["sfx"] <= 0.001)


func get_stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := SFX_DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		path = MUSIC_DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		_cache[name] = null
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV and name in _loop_flags:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
	_cache[name] = s
	return s


## play a one-shot effect. returns the player (or null)
func play(name: String, vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.0) -> AudioStreamPlayer:
	var s := get_stream(name)
	if s == null:
		return null
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool[0]
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return p


func play_step() -> void:
	play("step%d" % (1 + randi() % 3), -12.0, 1.0, 0.1)


func music(name: String, fade := 0.8) -> void:
	if name == _music_name:
		return
	_music_name = name
	var s := get_stream(name)
	if s == null:
		return
	if s is AudioStreamOggVorbis and name.begins_with("bgm"):
		(s as AudioStreamOggVorbis).loop = true
	var next := _music_b if _music_active == _music_a else _music_a
	var prev := _music_active
	next.stream = s
	next.pitch_scale = 1.0
	_tension = false
	next.volume_db = -40.0
	next.play()
	_music_active = next
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(next, "volume_db", -3.0, fade)
	if prev and prev.playing:
		_tween.tween_property(prev, "volume_db", -40.0, fade)
		_tween.chain().tween_callback(prev.stop)


var _tension := false


## match point: the music speeds up a touch (back to normal when another track starts)
func music_tension(on: bool) -> void:
	if on == _tension or _music_active == null:
		return
	_tension = on
	create_tween().tween_property(_music_active, "pitch_scale", 1.07 if on else 1.0, 0.9)


func stop_music(fade := 0.6) -> void:
	_music_name = ""
	if _music_active and _music_active.playing:
		var p := _music_active
		var t := create_tween()
		t.tween_property(p, "volume_db", -40.0, fade)
		t.tween_callback(p.stop)


func jingle(name: String) -> void:
	# one-shot music sting: duck the bgm briefly
	stop_music(0.3)
	var s := get_stream(name)
	if s == null:
		return
	_music_name = name
	_music_b.stream = s
	_music_b.pitch_scale = 1.0
	_tension = false
	_music_b.volume_db = -3.0
	_music_b.play()
	_music_active = _music_b


func crowd(on: bool) -> void:
	if on:
		if not _crowd.playing:
			_crowd.stream = get_stream("crowd_loop")
			_crowd.play()
	else:
		_crowd.stop()
