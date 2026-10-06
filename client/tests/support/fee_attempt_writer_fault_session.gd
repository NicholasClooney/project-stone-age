extends "res://server/game_session.gd"

# Test-only disk/return interleavings. This does not replace the original writer:
# every armed write still calls super exactly once.
var mode := ""
var host_ref: WeakRef
var writer_calls := 0
var read_calls := 0
var nested_result: Dictionary = {}
var reentry_handle: Dictionary = {}
var injected_io_error := false

func bind_host(host: Node) -> void:
	host_ref = weakref(host)

func _read_fee_attempt_file(path: String, expected: PackedByteArray) -> Dictionary:
	read_calls += 1
	var result: Dictionary = super._read_fee_attempt_file(path, expected)
	# The first Backend read of P1 after W1 installation is read #7 in this
	# fixed call order. Mutate only serial there, before the W2 CAS.
	if mode == "serial_w2_interference" and read_calls == 7:
		var host = host_ref.get_ref() if host_ref != null else null
		if host != null:
			host.quest_save_serial += 1
	return result

func _write_profile_candidate(candidate: Dictionary, path: String) -> bool:
	writer_calls += 1
	var host = host_ref.get_ref() if host_ref != null else null
	if (mode == "w1_open_error" and writer_calls == 1) or (mode == "w2_open_error" and writer_calls == 2):
		var temp_absolute := ProjectSettings.globalize_path(path + ".tmp")
		injected_io_error = DirAccess.make_dir_absolute(temp_absolute) == OK
	var result: bool = super._write_profile_candidate(candidate, path)
	if mode == "w1_wrapper_false_after_commit" and writer_calls == 1 and result:
		return false
	if mode == "w1_reenter_same_handle" and writer_calls == 1 and host != null:
		nested_result = host._persist_fee_attempt_fence(reentry_handle)
	if mode == "w1_replace_owner" and writer_calls == 1 and host != null:
		host.quest_auto.identity.run_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	if mode == "w1_replace_settlement" and writer_calls == 1:
		_loot_settlement = {"test_interference": true}
	return result
