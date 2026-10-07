extends "res://server/game_session.gd"
## Faults are armed only after ordinary fixture saves and frame preparation.
var host: WeakRef
var mode := ""
var writer_calls := 0
var read_calls := 0
var active_phase := ""
var handle: Dictionary = {}
var nested: Dictionary = {}
var nested_frame: Dictionary = {}
var successor: Dictionary = {}
var injected_claim: RefCounted
var read_fault_at := 0

func _write_profile_candidate(candidate: Dictionary, path: String) -> bool:
	writer_calls += 1
	if (mode == "w1_fail" and writer_calls == 1) or (mode == "w2_fail" and writer_calls == 2):return false
	if (mode == "w1_tmp_directory" and writer_calls == 1) or (mode == "w2_tmp_directory" and writer_calls == 2):
		DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	if mode == "nested" and writer_calls == 1:
		var b = host.get_ref()
		nested = b._persist_fee_start_journal_pair(handle)
		b._end_fee_start_journal_frame(handle)
		nested_frame = b._begin_fee_start_journal_frame(candidate)
	var written: bool = super._write_profile_candidate(candidate, path)
	if writer_calls == 1 and mode in ["owner_after", "serial_after", "path_after", "identity_after", "claim_after"]:
		var b = host.get_ref()
		match mode:
			"owner_after":
				successor = _profile.duplicate(true)
				successor.profile_id = "successor-profile"
				_profile = successor
			"serial_after": b.quest_save_serial += 10
			"path_after": b.save_path += ".successor"
			"identity_after": b.quest_auto.identity = preload("res://server/quest_auto_state.gd").new()
			"claim_after":
				injected_claim = RefCounted.new()
				b._fee_attempt_writer_call = injected_claim
	if (mode == "w1_false" and writer_calls == 1) or (mode == "w2_false" and writer_calls == 2):return false
	return written

func _read_fee_attempt_file(path: String, candidate_bytes: PackedByteArray) -> Dictionary:
	read_calls += 1
	var actual: Dictionary = super._read_fee_attempt_file(path, candidate_bytes)
	if read_fault_at > 0 and read_calls == read_fault_at:
		match mode:
			"read_unknown":return {"ok": false, "exists": true}
			"read_bad_ok":return {"ok": 1, "exists": true, "bytes": actual.get("bytes")}
			"read_bad_exists":return {"ok": true, "exists": [], "bytes": actual.get("bytes")}
			"read_bad_bytes":return {"ok": true, "exists": true, "bytes": false}
			"read_owner":
				_profile = _profile.duplicate(true)
				_profile.profile_id = "read-successor"
	return actual

func _write_fee_start_candidate_once(candidate: Variant, path: String, expected_profile_ref: Dictionary, expected_profile_value: Dictionary, phase: String) -> Dictionary:
	active_phase = phase
	var result: Dictionary = super._write_fee_start_candidate_once(candidate, path, expected_profile_ref, expected_profile_value, phase)
	if mode == "bad_return" and phase == "w1":result.writer_return = []
	if mode == "bad_row" and phase == "w1":result.primary = null
	return result
