# AdService.gd  (MOCK, AUTOLOAD)
extends Node

# -------------------------------------------------
# AD IDS (LOCKED)
# -------------------------------------------------
const AD_WAKE_BONUS := "WAKE_BONUS"
const AD_OFFLINE_DOUBLE := "OFFLINE_DOUBLE"
const AD_TIMED_BOOST := "TIMED_BOOST"
const AD_FAIL_SAVE := "FAIL_SAVE"

# -------------------------------------------------
# SIGNALS (ONLY OUTPUTS)
# -------------------------------------------------
signal reward_wake_bonus(multiplier: float)
signal reward_offline_double
signal reward_timed_boost(seconds: float)
signal reward_fail_save

# -------------------------------------------------
# CONFIG
# -------------------------------------------------
const TIMED_BOOST_SECONDS := 600.0   # 10 min
const COOLDOWN_TIMED_BOOST := 30 * 60
const COOLDOWN_FAIL_SAVE := 60 * 60

# -------------------------------------------------
# SESSION FLAGS
# -------------------------------------------------
var _offline_used_this_session: bool = false
var _wake_used_this_run: bool = false

# -------------------------------------------------
# OPTIONAL IAP FLAGS (wire later)
# -------------------------------------------------
var starter_pack_owned: bool = false

# -------------------------------------------------
# PUBLIC API
# -------------------------------------------------
func can_show(ad_id: String) -> bool:
	if starter_pack_owned:
		return true

	match ad_id:
		AD_WAKE_BONUS:
			return not _wake_used_this_run
		AD_OFFLINE_DOUBLE:
			return not _offline_used_this_session
		AD_TIMED_BOOST:
			return _cooldown_ready("ad_cd_timed_boost")
		AD_FAIL_SAVE:
			return _cooldown_ready("ad_cd_fail_save")
		_:
			return false

func show_rewarded(ad_id: String) -> void:
	if not can_show(ad_id):
		return
	# MOCK: instant success
	_on_ad_completed(ad_id)

# -------------------------------------------------
# INTERNAL
# -------------------------------------------------
func _on_ad_completed(ad_id: String) -> void:
	var now := Time.get_unix_time_from_system()

	match ad_id:
		AD_WAKE_BONUS:
			_wake_used_this_run = true
			reward_wake_bonus.emit(_wake_multiplier())

		AD_OFFLINE_DOUBLE:
			_offline_used_this_session = true
			reward_offline_double.emit()

		AD_TIMED_BOOST:
			_set_cd("ad_cd_timed_boost", now + COOLDOWN_TIMED_BOOST)
			reward_timed_boost.emit(TIMED_BOOST_SECONDS)

		AD_FAIL_SAVE:
			_set_cd("ad_cd_fail_save", now + COOLDOWN_FAIL_SAVE)
			reward_fail_save.emit()

func reset_for_new_run() -> void:
	_wake_used_this_run = false

func _wake_multiplier() -> float:
	return 1.0  # +100% Memories

func _cooldown_ready(key: String) -> bool:
	var data: Dictionary = SaveSystem.load_game()
	var t := float(data.get(key, 0.0))
	return Time.get_unix_time_from_system() >= t

func _set_cd(key: String, time: float) -> void:
	var data: Dictionary = SaveSystem.load_game()
	data[key] = time
	SaveSystem.save_game(data)
