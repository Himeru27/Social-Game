extends Node
## Autoload "AudioManager": Music/SFX buses, volume control, UI sounds, music playback.
## Drop an .ogg at res://assets/audio/music/menu_theme.ogg and it plays automatically.
## Your own files (.ogg / .mp3 / .wav, any of them) override the generated sounds:
##   assets/audio/sfx/footstep, button_hover, button_click, pause_menu
##   assets/audio/music/menu_theme (title screen), lobby_theme (lobby)

## Music level (dB, before the player's Music slider) for real music files, by track: tuned to sit under footsteps and chat.
const MUSIC_DB := {"menu": -6.0, "lobby": -10.0}
const _AUDIO_EXTS := ["ogg", "mp3", "wav"]

var _music: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _click: AudioStream
var _hover: AudioStream
var _pause: AudioStream
var _sit: AudioStreamWAV
var _ambient: AudioStreamPlayer
var _steps: Array[AudioStream] = []
var _emote_sfx: Dictionary = {}       ## emote id -> AudioStreamWAV
var _music_cache: Dictionary = {}     ## "menu" / "lobby" -> looping AudioStreamWAV
var _current_music := ""


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_click = _tone(660.0, 0.08)
	_hover = _tone(880.0, 0.04)
	_sit = _tone(150.0, 0.2)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "SFX"
	_ambient.volume_db = -26.0
	add_child(_ambient)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3:
		_steps.append(_noise_burst(0.11, 900.0 + i * 220.0, rng))
	var custom_step := _find_audio("res://assets/audio/sfx/footstep")
	if custom_step != "":
		_steps.clear()
		_steps.append(load(custom_step))
	var custom_click := _find_audio("res://assets/audio/sfx/button_click")
	if custom_click != "":
		_click = load(custom_click)
	var custom_hover := _find_audio("res://assets/audio/sfx/button_hover")
	if custom_hover != "":
		_hover = load(custom_hover)
	var custom_pause := _find_audio("res://assets/audio/sfx/pause_menu")
	if custom_pause != "":
		_pause = load(custom_pause)
	GameSettings.settings_changed.connect(apply_volumes)
	apply_volumes()


func apply_volumes() -> void:
	_set_bus("Master", float(GameSettings.get_value("master_volume")))
	_set_bus("Music", float(GameSettings.get_value("music_volume")))
	_set_bus("SFX", float(GameSettings.get_value("sfx_volume")))


func play_click() -> void:
	_sfx.stream = _click
	_sfx.volume_db = -4.0
	_sfx.play()


## Plays when the pause menu opens (only if assets/audio/sfx/pause_menu.* exists).
func play_pause() -> void:
	if _pause == null:
		return
	_sfx.stream = _pause
	_sfx.volume_db = -4.0
	_sfx.play()


func play_sit() -> void:
	_sfx.stream = _sit
	_sfx.volume_db = -4.0
	_sfx.play()


func play_hover() -> void:
	if _sfx.playing:
		return
	_sfx.stream = _hover
	_sfx.volume_db = -8.0
	_sfx.play()


## Plays res://...ogg if the file exists (drop your own music in assets/audio/music/); otherwise falls back to the
## built-in generated loop named by `fallback` ("menu" or "lobby"). Re-calling with the same track does not restart it.
func play_music(path: String, fallback := "") -> void:
	var stream: AudioStream = null
	var key := path
	var found := _find_audio(path)
	if found != "":
		key = found
		stream = load(found)
		if "loop" in stream:
			stream.loop = true
	elif fallback != "":
		key = "builtin:" + fallback
		if not _music_cache.has(fallback):
			_music_cache[fallback] = _make_music(fallback)
		stream = _music_cache[fallback]
	else:
		return
	if _current_music == key and _music.playing:
		return
	_current_music = key
	_music.stream = stream
	if key.begins_with("builtin:"):
		_music.volume_db = -10.0
	else:
		_music.volume_db = float(MUSIC_DB.get(fallback, 0.0))
	_music.play()


## Returns the first existing file for `path` with any of the supported extensions ("" if none).
func _find_audio(path: String) -> String:
	var base := path.get_basename()
	for ext in _AUDIO_EXTS:
		var candidate: String = "%s.%s" % [base, ext]
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func stop_music() -> void:
	_music.stop()
	_current_music = ""


func get_footstep() -> AudioStream:
	return _steps[randi() % _steps.size()]


func get_sit_sound() -> AudioStreamWAV:
	return _sit


## Emote audio from assets/audio/emotes/: [file name, loops while the emote lasts, loop restart point in seconds].
## The looping files are prepared so the end crossfades into the restart point; Player fades them out when the emote ends.
const EMOTE_AUDIO := {
	NetProtocol.EMOTE_BRAZILIAN: ["brazilian_taka_la_dentro", true, 1.5],
	NetProtocol.EMOTE_COFFEE: ["coffee", false, 0.0],
	NetProtocol.EMOTE_STRANGER: ["stranger_things_dance", true, 0.75],
	NetProtocol.EMOTE_HI: ["hi", false, 0.0],
	NetProtocol.EMOTE_AURA: ["aura_farm", true, 0.75],
}


func get_emote_sound(id: int) -> AudioStream:
	if not _emote_sfx.has(id):
		_emote_sfx[id] = _load_emote_sound(id)
	return _emote_sfx[id]


func _load_emote_sound(id: int) -> AudioStream:
	if not EMOTE_AUDIO.has(id):
		return null
	var e: Array = EMOTE_AUDIO[id]
	var path := _find_audio("res://assets/audio/emotes/" + str(e[0]))
	if path == "":
		return null
	var stream: AudioStream = load(path)
	if bool(e[1]) and "loop" in stream:
		stream.loop = true
		stream.loop_offset = float(e[2])
	return stream


func start_ambient() -> void:
	if _ambient.stream == null:
		_ambient.stream = _room_tone()
	if not _ambient.playing:
		_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Generates a short decaying sine blip so the UI has sound without any asset files.
func _tone(freq: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(TAU * freq * t) * exp(-t * 35.0) * 0.5
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


# ---------------------------------------------------------------- generated sounds (no asset files needed)

func _wav(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Footstep: low-passed noise with a fast decay.
func _noise_burst(duration: float, cutoff: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := clampf(TAU * cutoff / rate, 0.0, 1.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] = lp * exp(-t * 38.0) * 2.6
	return _wav(out, rate)


func _sweep(f0: float, f1: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / rate
		out[i] = sin(phase) * sin(PI * k) * 0.3
	return _wav(out, rate)


func _notes(freqs: Array, each: float) -> AudioStreamWAV:
	var rate := 22050
	var per := int(rate * each)
	var out := PackedFloat32Array()
	out.resize(per * freqs.size())
	for j in freqs.size():
		for i in per:
			var t := float(i) / rate
			out[j * per + i] = sin(TAU * float(freqs[j]) * t) * exp(-t * 14.0) * 0.4
	return _wav(out, rate)


## Three short falling "ha" pulses with a little vibrato.
func _laugh() -> AudioStreamWAV:
	var rate := 22050
	var pulse := int(rate * 0.13)
	var gap := int(rate * 0.07)
	var out := PackedFloat32Array()
	out.resize((pulse + gap) * 3)
	for j in 3:
		var base := 330.0 - j * 35.0
		for i in pulse:
			var t := float(i) / rate
			var f := base + sin(TAU * 28.0 * t) * 12.0
			out[j * (pulse + gap) + i] = sin(TAU * f * t) * sin(PI * float(i) / pulse) * 0.32
	return _wav(out, rate)


## Soft low room tone: filtered noise with a crossfaded seam so the loop is click-free.
func _room_tone() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 4
	var xf := rate / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var raw := PackedFloat32Array()
	raw.resize(n + xf)
	var lp := 0.0
	for i in n + xf:
		lp += 0.04 * (rng.randf_range(-1.0, 1.0) - lp)
		raw[i] = lp
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i] * 2.2
	for i in xf:
		var k := float(i) / xf
		out[i] = lerpf(raw[n + i], raw[i], k) * 2.2
	return _wav(out, rate, true)


## Slow ambient pad. Each chord fades in/out to silence, so the loop point is seamless.
func _make_music(kind: String) -> AudioStreamWAV:
	var rate := 11025
	var chords: Array
	var chord_len := 4.0
	if kind == "menu":
		chords = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 246.94, 293.66], [164.81, 196.0, 246.94]]
	else:
		chords = [[261.63, 329.63, 392.0], [220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 246.94, 293.66]]
		chord_len = 5.0
	var per := int(rate * chord_len)
	var out := PackedFloat32Array()
	out.resize(per * chords.size())
	for c in chords.size():
		var notes: Array = chords[c]
		for i in per:
			var t := float(i) / rate
			var env := pow(sin(PI * float(i) / per), 2.0)
			var v := 0.0
			for f in notes:
				v += sin(TAU * float(f) * t) + 0.35 * sin(TAU * float(f) * 2.0 * t + 1.0)
			v += 0.5 * sin(TAU * float(notes[0]) * 0.5 * t)        # soft bass
			out[c * per + i] = v * env * 0.1
	return _wav(out, rate, true)
