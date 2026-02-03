extends Node

@onready var sfx_dive: AudioStreamPlayer = $SFX_Dive
@onready var sfx_overclock: AudioStreamPlayer = $SFX_Overclock
@onready var sfx_wake: AudioStreamPlayer = $SFX_Wake
@onready var sfx_fail: AudioStreamPlayer = $SFX_Fail
@onready var sfx_corruption: AudioStreamPlayer = $SFX_Corruption

var enabled: bool = true
var master_volume: float = 1.0 # 0..1

func _ready() -> void:
	_apply_volume()

func set_enabled(on: bool) -> void:
	enabled = on
	_apply_volume()

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
