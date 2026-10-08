extends "res://server/game_session.gd"
## UNRUN. Faults are armed after ordinary load/fixture I/O unless testing loader.
var host: WeakRef
var mode := ""
var writes := 0
var reads := 0
var at_read := 0
var handle: Dictionary = {}
var nested: Dictionary = {}
var successor: Dictionary = {}
var claim: RefCounted

func _write_profile_candidate(candidate: Dictionary, path: String) -> bool:
	writes += 1
	if mode == "no_write":return false
	if mode == "tmp_directory":DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	if mode == "nested":
		var b = host.get_ref()
		nested = b._persist_fee_loaded_baseline(handle)
		b._end_fee_loaded_baseline(handle)
	var result: bool = super._write_profile_candidate(candidate, path)
	if mode == "after_false":return false
	if mode in ["owner", "path", "serial", "timer", "claim"]:
		var b = host.get_ref()
		match mode:
			"owner":
				successor = _profile.duplicate(true)
				successor.profile_id = "successor"
				_profile = successor
			"path":b.save_path += ".next"
			"serial":b.quest_save_serial += 10
			"timer":b.quest_loot = preload("res://server/quest_auto_loot.gd").new()
			"claim":
				claim = RefCounted.new()
				b._fee_attempt_close_call = claim
	return result

func _read_fee_attempt_file(path: String, expected: PackedByteArray) -> Dictionary:
	reads += 1
	var r: Dictionary = super._read_fee_attempt_file(path, expected)
	if reads == at_read:
		match mode:
			"unknown":return {"ok": false, "exists": true}
			"bad_type":return {"ok": 1, "exists": true, "bytes": r.get("bytes")}
			"read_owner":_profile = _profile.duplicate(true);_profile.profile_id = "read-successor"
	return r

func load_game(path: String) -> bool:
	if mode == "fake_load":return true
	var loaded: bool = super.load_game(path)
	return false if mode == "load_after_false" else loaded
