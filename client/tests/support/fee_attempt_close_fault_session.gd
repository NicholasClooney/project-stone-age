extends "res://server/game_session.gd"

# Test-only W1/W2 result interleavings; every successful injected physical write
# calls the original _write_profile_candidate exactly once.
var mode: String = ""
var host_ref: WeakRef
var writer_calls: int = 0
var nested_result: Dictionary = {}
var reentry_handle: Dictionary = {}
var injected_tmp_directory: bool = false
var read_calls: int = 0
var mutate_after_read: int = 0
var successor_session: RefCounted

func bind_host(host: Node) -> void:
	host_ref = weakref(host)

func _read_fee_attempt_file(path: String, expected: PackedByteArray) -> Dictionary:
	var result: Dictionary = super._read_fee_attempt_file(path, expected)
	read_calls += 1
	if read_calls == mutate_after_read:
		var host = host_ref.get_ref() if host_ref != null else null
		if host != null:
			match mode:
				"read_replace_session":
					var replacement = get_script().new()
					replacement.bind_host(host)
					successor_session = replacement
					host.session = successor_session
				"read_replace_profile":
					host.session._profile = host.session._profile.duplicate(true)
				"read_change_owner":
					host.session._profile["profile_id"] = "read-successor-profile"
				"read_replace_path":
					host.save_path = "user://fee-close-read-successor-must-stay-absent.json"
				"read_change_serial":
					host.quest_save_serial += 1
				"read_change_cache":
					host.last_saved_payload = "read-successor-cache"
				"read_replace_identity":
					host.quest_auto.identity.run_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
				"read_claim_sidecar":
					var claim := RefCounted.new()
					host._fee_resume_sidecar_call = claim
					host._fee_resume_sidecar_frame = {"call": claim}
	return result

func _write_fee_close_candidate_once(candidate: Dictionary, path: String, expected_profile_ref: Dictionary, expected_profile_value: Dictionary, run_id: String, phase: String) -> Dictionary:
	var result: Dictionary = super._write_fee_close_candidate_once(candidate, path, expected_profile_ref, expected_profile_value, run_id, phase)
	if phase == "w1" and mode == "w1_readback_unknown":
		result.primary = {"ok": false, "exists": true, "error": ERR_FILE_CANT_READ, "matches": false, "bytes": PackedByteArray()}
	if phase == "w1" and mode == "w1_missing_writer_return":result.erase("writer_return")
	if phase == "w2" and mode == "w2_missing_writer_return":result.erase("writer_return")
	return result

func _write_profile_candidate(candidate: Dictionary, path: String) -> bool:
	writer_calls += 1
	var host = host_ref.get_ref() if host_ref != null else null
	var inject_open: bool = (mode == "w1_open_error" and writer_calls == 1) or (mode == "w2_open_error" and writer_calls == 2)
	if inject_open:
		var tmp_absolute: String = ProjectSettings.globalize_path(path + ".tmp")
		injected_tmp_directory = DirAccess.make_dir_absolute(tmp_absolute) == OK
	var result: bool = super._write_profile_candidate(candidate, path)
	if mode == "w1_claim_sidecar" and writer_calls == 1 and host != null:
		var claim := RefCounted.new()
		host._fee_resume_sidecar_call = claim
		host._fee_resume_sidecar_frame = {"call": claim}
	if mode == "w1_reenter_same_handle" and writer_calls == 1 and host != null:
		nested_result = host._persist_fee_attempt_close_pair(reentry_handle)
	if mode == "w1_replace_identity" and writer_calls == 1 and host != null:
		host.quest_auto.identity.run_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	if mode == "w1_replace_path" and writer_calls == 1 and host != null:
		host.save_path = "user://fee-close-successor-must-stay-absent.json"
	if mode == "w1_replace_profile_owner" and writer_calls == 1 and host != null:
		host.session._profile["profile_id"] = "successor-profile-must-not-be-written"
	if mode == "w1_wrapper_false_after_commit" and writer_calls == 1 and result:
		return false
	if mode == "w2_wrapper_false_after_commit" and writer_calls == 2 and result:
		return false
	return result
