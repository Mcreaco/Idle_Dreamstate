extends Node

@onready var sfx_dive: AudioStreamPlayer = $SFX_Dive
@onready var sfx_overclock: AudioStreamPlayer = $SFX_Overclock
@onready var sfx_wake: AudioStreamPlayer = $SFX_Wake
@onready var sfx_fail: AudioStreamPlayer = $SFX_Fail
@onready var sfx_corruption: AudioStreamPlayer = $SFX_Corruption

# Procedural Piano Synthesis
var _sample_hz: float = 44100.0

# Internal Nodes/Playback
var music_player: AudioStreamPlayer
var sfx_hit_player: AudioStreamPlayer
var _sfx_playback: AudioStreamGeneratorPlayback

var enabled: bool = true
var master_volume: float = 1.0 # 0..1

func _ready() -> void:
	_setup_procedural_nodes()
	_apply_volume()

func _setup_procedural_nodes() -> void:
	# Music Player - NOW USING REAL FILE
	music_player = AudioStreamPlayer.new()
	var music_stream = load("res://assets/music/Dreamsmusic.mp3")
	if music_stream:
		music_stream.loop = true
		music_player.stream = music_stream
	music_player.bus = "Master"
	add_child(music_player)
	music_player.play()

	# SFX Generator (Shared for combat)
	sfx_hit_player = AudioStreamPlayer.new()
	var gen_sfx = AudioStreamGenerator.new()
	gen_sfx.mix_rate = _sample_hz
	gen_sfx.buffer_length = 0.1
	sfx_hit_player.stream = gen_sfx
	add_child(sfx_hit_player)
	sfx_hit_player.play()
	_sfx_playback = sfx_hit_player.get_stream_playback()

func _process(delta: float) -> void:
	# No procedural music process needed for MP3
	pass

func _play_chord_note() -> void:
	pass

func _fill_music_buffer() -> void:
	pass

func play_combat_hit() -> void:
	if not enabled or not _sfx_playback: return
	# More rhythmic / soft "thud" hit
	var frames = int(_sample_hz * 0.07)
	for i in range(frames):
		var p = float(i) / float(frames)
		# Low frequency impact + soft noise
		var impact = sin(p * TAU * 110.0 * (1.0 - p)) * exp(-p * 12.0)
		var noise = (randf() * 2.0 - 1.0) * 0.03 * exp(-p * 25.0)
		var s = (impact * 0.4 + noise) * 0.12
		_sfx_playback.push_frame(Vector2(s, s))

func play_combat_kill() -> void:
	if not enabled or not _sfx_playback: return
	# Resonant gong-like death sound
	var frames = int(_sample_hz * 0.5)
	for i in range(frames):
		var p = float(i) / _sample_hz
		# Deeper 52Hz (E) root with resonance
		var s = sin(p * TAU * 52.0) * exp(-p * 3.5) 
		s += sin(p * TAU * 104.0) * exp(-p * 5.0) * 0.5
		s *= 0.18
		_sfx_playback.push_frame(Vector2(s, s))

func set_enabled(on: bool) -> void:
	enabled = on
	_apply_volume()
	if on: music_player.play()
	else: music_player.stop()

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_volume()

func _apply_volume() -> void:
	var lin: float = master_volume if enabled else 0.0
	var vol_db: float = linear_to_db(lin)

	if is_instance_valid(sfx_dive): sfx_dive.volume_db = vol_db
	if is_instance_valid(sfx_overclock): sfx_overclock.volume_db = vol_db
	if is_instance_valid(sfx_wake): sfx_wake.volume_db = vol_db
	if is_instance_valid(sfx_fail): sfx_fail.volume_db = vol_db
	if is_instance_valid(sfx_corruption): sfx_corruption.volume_db = vol_db
	if is_instance_valid(music_player): music_player.volume_db = vol_db + 2.0 # Music slightly louder

func play_dive() -> void:
	if enabled and is_instance_valid(sfx_dive):
		sfx_dive.play()

func play_overclock() -> void:
	if enabled and is_instance_valid(sfx_overclock):
		sfx_overclock.play()

func play_wake() -> void:
	if enabled and is_instance_valid(sfx_wake):
		sfx_wake.play()

func play_fail() -> void:
	if enabled and is_instance_valid(sfx_fail):
		sfx_fail.play()

func play_corruption() -> void:
	if enabled and is_instance_valid(sfx_corruption):
		if not sfx_corruption.playing:
			sfx_corruption.play()
