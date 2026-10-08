extends "res://tests/support/fee_loaded_baseline_fault_session.gd"
var close_mode := ""
var close_calls := 0
var fault_write := 0
var fault_read := 0
var close_handle: Dictionary = {}
var inner: Dictionary = {}
var close_claim: RefCounted
var inside_close := false

func _write_fee_close_candidate_once(candidate: Dictionary, path: String, expected_profile_ref: Dictionary, expected_profile_value: Dictionary, run_id: String, phase: String) -> Dictionary:
	close_calls += 1
	inside_close = true
	var result: Dictionary = super._write_fee_close_candidate_once(candidate, path, expected_profile_ref, expected_profile_value, run_id, phase)
	inside_close = false
	if close_calls == fault_write and close_mode == "raw_type":result.writer_return = 1;result.ok = true
	return result

func _write_profile_candidate(candidate: Dictionary, path: String) -> bool:
	if not inside_close:return super._write_profile_candidate(candidate, path)
	writes += 1
	var armed: bool = close_calls == fault_write
	if armed and close_mode == "no_write":return false
	if armed and close_mode == "nested":
		var b = host.get_ref()
		inner = b._persist_fee_recovered_close(close_handle)
		b._end_fee_recovered_close(close_handle)
		check_nested_begin(b)
	# Call grandparent through inherited fault writer while its faults are disabled.
	writes -= 1
	var result: bool = super._write_profile_candidate(candidate, path)
	if armed:
		if close_mode == "after_false":return false
		if close_mode in ["owner", "serial", "path", "claim", "timer"]:mutate_owner(close_mode)
	return result

func check_nested_begin(b) -> void:
	inner.begin = b._begin_fee_recovered_close()

func mutate_owner(which: String) -> void:
	var b = host.get_ref()
	match which:
		"owner":_profile = _profile.duplicate(true);_profile.profile_id = "read-successor"
		"serial":b.quest_save_serial += 10
		"path":b.save_path += ".next"
		"claim":close_claim = RefCounted.new();b._fee_attempt_close_call = close_claim
		"timer":b.quest_loot = preload("res://server/quest_auto_loot.gd").new()

func _read_fee_attempt_file(path: String, expected: PackedByteArray) -> Dictionary:
	var result: Dictionary = super._read_fee_attempt_file(path, expected)
	if reads == fault_read:
		if close_mode == "unknown":return {"ok": false, "exists": true}
		if close_mode == "read_owner":mutate_owner("owner")
	return result
