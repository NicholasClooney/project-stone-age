extends SceneTree
## Static candidate only: complete-profile load and actual Backend.load_resume dispatch.
## Not registered or executed in this review batch.
const Session = preload("res://server/game_session.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
const FIELD := "quest_auto_fee_lifecycle"
const RUN_A := "11111111111111111111111111111111"
const RUN_B := "33333333333333333333333333333333"
const ATTEMPT := "22222222222222222222222222222222"
const OTHER_ATTEMPT := "44444444444444444444444444444444"
const FIXED_NOW := 1800000000
const SOURCE_SEED := 8317
const TARGET_SEED := 9137
const MAX_EVIDENCE_FILE_BYTES := 16777216
var assertions := 0
var failures := 0
var run_tag := ""

class ResumeSpy extends "res://server/quest_auto.gd":
	var load_calls := 0
	var loaded_state: Dictionary = {}
	func load_resume(b, state: Dictionary) -> void:
		load_calls += 1
		loaded_state = state.duplicate(true)

class ResumeProbeBackend extends "res://server/backend.gd":
	var position_restore_calls := 0
	func _restore_quest_saved_position() -> bool:
		position_restore_calls += 1
		return true

func _initialize() -> void:
	run_tag = Crypto.new().generate_random_bytes(8).hex_encode()
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func _fixed_clock() -> int:
	return FIXED_NOW

func _new_session(seed_value: int):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Session.new(Callable(self, "_fixed_clock"), rng)

func _profile(record: Dictionary = {}, include_record: bool = true) -> Dictionary:
	var source = _new_session(SOURCE_SEED)
	var value: Dictionary = source.snapshot()
	value.version = Session.SAVE_VERSION
	if include_record:
		value[FIELD] = record.duplicate(true)
	return value

func _configure_session_clock(session) -> void:
	session.login_clock = Callable(self, "_fixed_clock")
	var rng := RandomNumberGenerator.new()
	rng.seed = SOURCE_SEED
	session.login_rng = rng

func _owner() -> Dictionary:
	return {"profile_id": "samgir-singleplayer-v1", "character_id": "100000"}

func _none_record(run_id: String = RUN_A) -> Dictionary:
	return {
		"schema": 1, "owner": _owner(),
		"current": {"run_id": run_id, "run_status": "active", "purchase": {"state": "none"}},
		"unresolved_attempt": {}
	}

func _manual_record(run_id: String = RUN_A) -> Dictionary:
	return {
		"schema": 1, "owner": _owner(),
		"current": {"run_id": run_id, "run_status": "active", "purchase": {"state": "manual_only"}},
		"unresolved_attempt": {}
	}

func _attempting_record(run_id: String = RUN_A) -> Dictionary:
	return {
		"schema": 1, "owner": _owner(),
		"current": {"run_id": run_id, "run_status": "active", "purchase": {
			"state": "attempting", "attempt_id": ATTEMPT, "source_id": "synthetic-source",
			"offer_id": "synthetic-offer", "item_id": 900001, "amount": 17, "balance_before": 90
		}},
		"unresolved_attempt": {}
	}

func _ticket_record(run_id: String = RUN_A) -> Dictionary:
	var value := _attempting_record(run_id)
	value.current.purchase.merge({"state": "ticket_committed", "balance_after": 73, "ticket_uid": 7}, true)
	return value

func _entry_record(run_id: String = RUN_A) -> Dictionary:
	var value := _ticket_record(run_id)
	value.current.purchase.state = "entry_committed"
	value.current.purchase.consumed_ticket_uid = 8
	return value

func _unknown_active_record() -> Dictionary:
	return {
		"schema": 1, "owner": _owner(),
		"current": {"run_id": RUN_B, "run_status": "active", "purchase": {"state": "manual_only"}},
		"unresolved_attempt": {
			"origin_run_id": RUN_A, "attempt_id": OTHER_ATTEMPT, "source_id": "synthetic-source",
			"offer_id": "synthetic-offer", "item_id": 900001, "amount": 17, "balance_before": 90
		}
	}

func _closed_record(with_unknown: bool) -> Dictionary:
	var value := {
		"schema": 1, "owner": _owner(),
		"current": {"run_id": RUN_A, "run_status": "closed", "purchase": {"state": "manual_only"}},
		"unresolved_attempt": {}
	}
	if with_unknown:
		value.unresolved_attempt = {
			"origin_run_id": RUN_A, "attempt_id": OTHER_ATTEMPT, "source_id": "synthetic-source",
			"offer_id": "synthetic-offer", "item_id": 900001, "amount": 17, "balance_before": 90
		}
	return value

func _float_record(record: Dictionary) -> Dictionary:
	var value: Dictionary = record.duplicate(true)
	value.schema = float(value.schema)
	var purchase: Dictionary = value.current.purchase
	if purchase.state in ["attempting", "ticket_committed", "entry_committed"]:
		for key: String in ["item_id", "amount", "balance_before"]: purchase[key] = float(purchase[key])
	if purchase.state in ["ticket_committed", "entry_committed"]:
		for key: String in ["balance_after", "ticket_uid"]: purchase[key] = float(purchase[key])
	if purchase.state == "entry_committed": purchase.consumed_ticket_uid = float(purchase.consumed_ticket_uid)
	if not value.unresolved_attempt.is_empty():
		for key: String in ["item_id", "amount", "balance_before"]: value.unresolved_attempt[key] = float(value.unresolved_attempt[key])
	return value

func _path(label: String) -> String:
	return "user://fee-load-v3-%s-%s.json" % [run_tag, label]

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

func _write_profile(path: String, profile: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(profile))

func _read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return {"ok": open_error == ERR_FILE_NOT_FOUND, "exists": false, "error": open_error, "length": -1, "bytes": PackedByteArray()}
	var length := file.get_length()
	if length < 0 or length > MAX_EVIDENCE_FILE_BYTES:
		file.close()
		return {"ok": false, "exists": true, "error": ERR_FILE_CANT_READ, "length": length, "bytes": PackedByteArray()}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	return {"ok": error == OK and bytes.size() == length, "exists": true, "error": error, "length": length, "bytes": bytes}

func _same_file_image(left: Dictionary, right: Dictionary) -> bool:
	return left.get("ok", false) and right.get("ok", false) \
		and left.get("exists", false) == right.get("exists", false) \
		and left.get("length", -2) == right.get("length", -3) \
		and left.get("bytes", PackedByteArray()) == right.get("bytes", PackedByteArray())

func _write_record_case(label: String, expected_record: Dictionary) -> void:
	var path := _path(label)
	var raw_profile := _profile(_float_record(expected_record))
	var raw_bytes := JSON.stringify(raw_profile).to_utf8_buffer()
	if not check(_write_profile(path, raw_profile), "Fixture write succeeds: " + label):return
	var primary_before := _read_file(path)
	var backup_before := _read_file(path + ".bak")
	var temporary_before := _read_file(path + ".tmp")
	if not check(primary_before.get("ok", false) and primary_before.get("exists", false) and primary_before.get("length", -1) == raw_bytes.size() and primary_before.get("bytes", PackedByteArray()) == raw_bytes, "Primary pre-image is completely read before load: " + label):return
	if not check(backup_before.get("ok", false) and not backup_before.get("exists", true), "Backup is truly absent before primary load: " + label):return
	if not check(temporary_before.get("ok", false) and not temporary_before.get("exists", true), "Temporary is truly absent before primary load: " + label):return
	var target = _new_session(TARGET_SEED)
	var before_rng: int = target.login_rng.state
	var before_recovery_rng: int = target.recovery_rng.state
	if not check(target.load_game(path), "Full JSON lifecycle profile loads: " + label):return
	var expected_profile: Dictionary = _profile(expected_record)
	if not check(target._profile == expected_profile, "Complete normalized profile equals independently constructed expected profile: " + label):return
	if not check(target.login_rng.state == before_rng and target.recovery_rng.state == before_recovery_rng, "Fixed-clock load does not consume/change either Session RNG: " + label):return
	if not check(target.last_load_source == "primary", "Primary source provenance is exact: " + label):return
	var primary_after := _read_file(path)
	var backup_after := _read_file(path + ".bak")
	var temporary_after := _read_file(path + ".tmp")
	if not check(primary_after.get("ok", false) and backup_after.get("ok", false) and temporary_after.get("ok", false), "All post-load disk reads are complete: " + label):return
	if not check(_same_file_image(primary_after, primary_before), "Primary existence/declared length/full bytes stay exact: " + label):return
	if not check(_same_file_image(backup_after, backup_before), "Backup existence/declared length/full bytes stay exact: " + label):return
	if not check(_same_file_image(temporary_after, temporary_before), "Temporary existence/declared length/full bytes stay exact: " + label):return
	print("FEE LOAD RETAINED case=", label, "path=", path, "primary_bytes=", raw_bytes.size())

func _resume_state(run_id: String, owner: Dictionary, include_binding: bool = true) -> Dictionary:
	var state := {"quest_auto": {"version": 3, "quest_id": 2, "clean_authorized": false,
		"strict_walk": true, "identity": {"run_id": run_id, "step_id": "test-step", "revision": 4}, "phase": "travel"}}
	if include_binding:
		state.fee_attempt_binding = {"owner": owner.duplicate(true), "run_id": run_id}
	return state

func _resume_dispatch_case(label: String, record: Dictionary, state: Dictionary, expected_dispatch: bool) -> void:
	var profile_path := _path("resume-profile-" + label)
	var has_record := not record.is_empty()
	var profile := _profile(record, has_record)
	if not check(_write_profile(profile_path, profile), "Resume profile fixture write succeeds: " + label):return
	var backend = ResumeProbeBackend.new()
	var spy = ResumeSpy.new()
	backend.quest_auto = spy
	backend.save_path = profile_path
	backend.resume_path = _path("resume-sidecar-" + label)
	_configure_session_clock(backend.session)
	var expected_profile: Dictionary = _profile(record, has_record)
	var expected_profile_bytes := JSON.stringify(profile).to_utf8_buffer()
	var profile_primary_before := _read_file(profile_path)
	var profile_backup_before := _read_file(profile_path + ".bak")
	var profile_tmp_before := _read_file(profile_path + ".tmp")
	if not check(profile_primary_before.get("ok", false) and profile_primary_before.get("exists", false) and profile_primary_before.get("length", -1) == expected_profile_bytes.size() and profile_primary_before.bytes == expected_profile_bytes and profile_backup_before.get("ok", false) and not profile_backup_before.get("exists", true) and profile_tmp_before.get("ok", false) and not profile_tmp_before.get("exists", true), "Resume profile primary/backup/tmp exact pre-images are complete: " + label):
		backend.free()
		return
	var login_rng_preload: int = backend.session.login_rng.state
	var recovery_rng_preload: int = backend.session.recovery_rng.state
	if not check(backend.session.load_game(profile_path), "Actual profile loader accepts resume fixture: " + label):
		backend.free()
		return
	if not check(backend.session._profile == expected_profile and backend.session.last_load_source == "primary", "Resume profile full load matches independent expected state: " + label):
		backend.free()
		return
	if not check(backend.automation.resume_wanted() and not backend.battle_open and backend.session._pending.is_empty(), "Actual quest-intent/position gate prerequisites are live for this case: " + label):
		backend.free()
		return
	if not check(backend.session.login_rng.state == login_rng_preload and backend.session.recovery_rng.state == recovery_rng_preload, "Profile load preserves both configured Session RNG states: " + label):
		backend.free()
		return
	var resume_writes_before: int = backend.resume_writes
	backend._write_resume_file(backend.resume_path, state)
	var sidecar_tmp_before := _read_file(backend.resume_path + ".tmp")
	if not check(sidecar_tmp_before.get("ok", false) and not sidecar_tmp_before.get("exists", true), "Sidecar writer starts with no stale tmp file: " + label):
		backend.free()
		return
	var before := _read_file(backend.resume_path)
	var expected_sidecar_bytes := JSON.stringify(JSON.from_native(state)).to_utf8_buffer()
	if not check(backend.resume_writes == resume_writes_before + 1 and before.get("ok", false) and before.get("exists", false) and before.get("length", -1) == expected_sidecar_bytes.size() and before.get("bytes", PackedByteArray()) == expected_sidecar_bytes, "Actual resume sidecar writer committed the exact readable file: " + label):
		backend.free()
		return
	var parsed_sidecar = JSON.parse_string(before.bytes.get_string_from_utf8())
	var native_sidecar = JSON.to_native(parsed_sidecar) if parsed_sidecar != null else null
	if not check(native_sidecar is Dictionary and native_sidecar == state, "Written sidecar round-trips to the exact expected state: " + label):
		backend.free()
		return
	var profile_before: Dictionary = backend.session._profile.duplicate(true)
	var profile_path_before := _read_file(profile_path)
	if not check(profile_path_before.get("ok", false) and profile_path_before.get("exists", false), "Loaded profile disk is fully readable: " + label):
		backend.free()
		return
	backend.load_resume()
	if not check(spy.load_calls == (1 if expected_dispatch else 0), "Actual Backend.load_resume dispatch result: " + label):
		backend.free()
		return
	if expected_dispatch and not check(spy.loaded_state == state.get("quest_auto", {}), "QuestAuto receives the exact persisted intent after allowed dispatch: " + label):
		backend.free()
		return
	if not check(backend.position_restore_calls == (1 if expected_dispatch else 0), "Actual quest saved-position restore gate result: " + label):
		backend.free()
		return
	if not check(backend.session._profile == profile_before, "Resume dispatch leaves loaded profile unchanged: " + label):
		backend.free()
		return
	var profile_path_after := _read_file(profile_path)
	if not check(profile_path_after.get("ok", false) and profile_path_after.get("exists", false), "Profile remains readable after resume dispatch: " + label):
		backend.free()
		return
	var profile_backup_after := _read_file(profile_path + ".bak")
	var profile_tmp_after := _read_file(profile_path + ".tmp")
	if not check(profile_backup_after.get("ok", false) and profile_tmp_after.get("ok", false), "Profile backup/tmp remain readable after resume: " + label):
		backend.free()
		return
	if not check(_same_file_image(profile_path_after, profile_primary_before) and _same_file_image(profile_backup_after, profile_backup_before) and _same_file_image(profile_tmp_after, profile_tmp_before), "Resume dispatch leaves all profile disk existence/length/bytes exact: " + label):
		backend.free()
		return
	var after := _read_file(backend.resume_path)
	var sidecar_tmp_after := _read_file(backend.resume_path + ".tmp")
	if not check(after.get("ok", false) and sidecar_tmp_after.get("ok", false) and not after.get("exists", true) and not sidecar_tmp_after.get("exists", true), "One-shot sidecar and writer tmp are absent after consumption: " + label):
		backend.free()
		return
	print("FEE RESUME OBSERVED case=", label, "dispatch=", spy.load_calls, "position_restore=", backend.position_restore_calls, "pre_bytes=", before.bytes.size())
	backend.free()

func _malformed_cases(native: Dictionary) -> void:
	var rows: Array = []
	var row: Dictionary
	row = native.duplicate(true); row.schema = true; rows.append(["bool", row, true])
	row = native.duplicate(true); row.current.purchase.amount = 17.5; rows.append(["fraction", row, true])
	row = native.duplicate(true); row.current.purchase.amount = INF; rows.append(["nonfinite-direct", row, false])
	row = native.duplicate(true); row.current.purchase.amount = 2147483648; rows.append(["out-of-range", row, true])
	row = native.duplicate(true); row.current.purchase.erase("attempt_id"); rows.append(["missing-attempt-id", row, true])
	row = native.duplicate(true); row.erase("unresolved_attempt"); rows.append(["missing-key", row, true])
	row = native.duplicate(true); row.extra = "unexpected"; rows.append(["extra-key", row, true])
	row = native.duplicate(true); row.owner.character_id = "other-profile"; rows.append(["wrong-owner", row, true])
	row = native.duplicate(true); row.current.purchase = null; rows.append(["null-purchase", row, true])
	for case: Array in rows:
		var label: String = str(case[0])
		var raw_record: Dictionary = case[1]
		var profile := _profile(raw_record)
		var target = _new_session(TARGET_SEED)
		var canonical: Dictionary = target._canonical_fee_attempt_profile(profile)
		if not check(not canonical.get("ok", true), "Raw validator rejects without property error: " + label):return
		if not case[2]:
			print("FEE LOAD INVALID direct-only=", label, " reason=JSON cannot faithfully encode non-finite number")
			continue
		var path := _path("invalid-" + label)
		if not check(_write_profile(path, profile), "Malformed JSON fixture write succeeds: " + label):return
		var primary_before := _read_file(path)
		var backup_before := _read_file(path + ".bak")
		var temp_before := _read_file(path + ".tmp")
		if not check(primary_before.get("ok", false) and primary_before.get("exists", false) and backup_before.get("ok", false) and not backup_before.get("exists", true) and temp_before.get("ok", false) and not temp_before.get("exists", true), "Malformed fixture disk state is fully captured: " + label):return
		var live_before: Dictionary = target._profile.duplicate(true)
		var rng_before: int = target.login_rng.state
		var recovery_rng_before: int = target.recovery_rng.state
		if not check(not target.load_game(path), "Actual load_game rejects malformed lifecycle: " + label):return
		if not check(target._profile == live_before and target.login_rng.state == rng_before and target.recovery_rng.state == recovery_rng_before, "Rejected load preserves full live profile/RNG: " + label):return
		if not check(target.last_load_source.is_empty(), "Rejected load records no source: " + label):return
		var primary_after := _read_file(path)
		var backup_after := _read_file(path + ".bak")
		var temp_after := _read_file(path + ".tmp")
		if not check(primary_after.get("ok", false) and backup_after.get("ok", false) and temp_after.get("ok", false), "Malformed post-load disk reads succeed: " + label):return
		if not check(_same_file_image(primary_after, primary_before) and _same_file_image(backup_after, backup_before) and _same_file_image(temp_after, temp_before), "Rejected load preserves primary/backup/tmp existence, length and bytes: " + label):return

func run() -> void:
	var none := _none_record()
	var manual := _manual_record()
	var attempting := _attempting_record()
	var ticket := _ticket_record()
	var entry := _entry_record()
	var unknown_active := _unknown_active_record()
	var closed_plain := _closed_record(false)
	var closed_unknown := _closed_record(true)

	# JSON.stringify -> parser -> raw validator -> native strict journal -> load migration.
	var roundtrip_cases: Array = [
		["none", none], ["manual-only", manual], ["attempting", attempting],
		["ticket-committed", ticket], ["entry-committed", entry],
		["unknown-active", unknown_active], ["closed", closed_plain], ["closed-unknown", closed_unknown]
	]
	for case: Array in roundtrip_cases:
		var failure_mark: int = failures
		var raw_profile := _profile(_float_record(case[1]))
		var parser_session = Session.new()
		var raw = parser_session._parse_save(JSON.stringify(raw_profile))
		if not check(raw is Dictionary, "JSON parse returns profile for " + str(case[0])):return
		var canonical: Dictionary = parser_session._canonical_fee_attempt_profile(raw)
		if not check(canonical.get("ok", false), "Raw shape/numeric boundary accepts valid state " + str(case[0])):return
		if not check(canonical.get("record", {}) == case[1], "Canonical state equals independent literal oracle " + str(case[0])):return
		if not check(Journal.valid(canonical.record), "Native strict helper accepts canonical state " + str(case[0])):return
		parser_session = null
		_write_record_case(str(case[0]), case[1])
		if failures != failure_mark:return

	# Invalid primary + valid backup follows existing loot recovery contract.
	var fallback_path := _path("invalid-primary-valid-backup")
	var invalid_primary := _profile(_float_record(ticket))
	invalid_primary[FIELD].current.purchase.amount = true
	var backup_profile := _profile(ticket)
	if not check(_write_profile(fallback_path, invalid_primary), "Invalid primary fixture write succeeds"):return
	if not check(_write_profile(fallback_path + ".bak", backup_profile), "Valid backup fixture write succeeds"):return
	var primary_before := _read_file(fallback_path)
	var backup_before := _read_file(fallback_path + ".bak")
	var fallback_tmp_before := _read_file(fallback_path + ".tmp")
	var expected_invalid_primary := JSON.stringify(invalid_primary).to_utf8_buffer()
	var expected_backup := JSON.stringify(backup_profile).to_utf8_buffer()
	if not check(primary_before.get("ok", false) and primary_before.get("exists", false) and primary_before.bytes == expected_invalid_primary and backup_before.get("ok", false) and backup_before.get("exists", false) and backup_before.bytes == expected_backup and fallback_tmp_before.get("ok", false) and not fallback_tmp_before.get("exists", true), "Fallback primary/backup/tmp exact pre-images are complete"):return
	var fallback = _new_session(TARGET_SEED)
	var fallback_rng_before: int = fallback.login_rng.state
	var fallback_recovery_rng_before: int = fallback.recovery_rng.state
	if not check(fallback.load_game(fallback_path), "Valid backup loads after invalid primary"):return
	var fallback_expected: Dictionary = backup_profile.duplicate(true)
	fallback_expected.quest_loot.recovery_blocked = true # actual LootState.recovered(..., from_backup=true)
	if not check(fallback.last_load_source == "backup", "Fallback reports actual read source"):return
	if not check(fallback._profile == fallback_expected, "Fallback result equals complete independently prepared recovered profile"):return
	if not check(fallback.login_rng.state == fallback_rng_before and fallback.recovery_rng.state == fallback_recovery_rng_before, "Fixed-clock fallback preserves both Session RNGs"):return
	var primary_after := _read_file(fallback_path)
	var backup_after := _read_file(fallback_path + ".bak")
	var temp_after := _read_file(fallback_path + ".tmp")
	var expected_primary := JSON.stringify(fallback_expected).to_utf8_buffer()
	var fallback_tmp_after := temp_after
	if not check(primary_after.get("ok", false) and backup_after.get("ok", false) and temp_after.get("ok", false), "Fallback post-images are fully readable"):return
	if not check(primary_before.bytes != primary_after.bytes, "Expected loot backup recovery rewrites invalid primary"):return
	if not check(primary_after.length == expected_primary.size() and primary_after.bytes == expected_primary, "Recovery primary length/bytes equal complete expected profile"):return
	if not check(_same_file_image(backup_after, backup_before), "Source backup existence/length/bytes remain exact"):return
	if not check(_same_file_image(fallback_tmp_after, fallback_tmp_before), "Recovery tmp existence/length/bytes follow exact expected absence"):return
	print("FEE LOAD RETAINED case=fallback path=", fallback_path, "primary_before=", primary_before.bytes.size(), "primary_after=", primary_after.bytes.size(), "backup_bytes=", backup_after.bytes.size())

	# Legacy record absence remains untouched by the loader.
	var legacy_path := _path("legacy-no-fee-field")
	var legacy_profile := _profile({}, false)
	if not check(_write_profile(legacy_path, legacy_profile), "Legacy profile write succeeds"):return
	var legacy = _new_session(TARGET_SEED)
	var legacy_rng_before: int = legacy.login_rng.state
	var legacy_recovery_rng_before: int = legacy.recovery_rng.state
	var legacy_bytes_before := _read_file(legacy_path)
	var legacy_backup_before := _read_file(legacy_path + ".bak")
	var legacy_tmp_before := _read_file(legacy_path + ".tmp")
	if not check(legacy_bytes_before.get("ok", false) and legacy_bytes_before.get("exists", false) and legacy_backup_before.get("ok", false) and not legacy_backup_before.get("exists", true) and legacy_tmp_before.get("ok", false) and not legacy_tmp_before.get("exists", true), "Legacy primary/backup/tmp pre-images are complete"):return
	if not check(legacy.load_game(legacy_path), "Legacy no-field profile still loads"):return
	if not check(not legacy._profile.has(FIELD) and legacy.last_load_source == "primary", "Legacy load does not synthesize fee data"):return
	if not check(legacy._profile == legacy_profile, "Legacy full profile equals independent expected"):return
	if not check(legacy.login_rng.state == legacy_rng_before and legacy.recovery_rng.state == legacy_recovery_rng_before, "Legacy fixed-clock load preserves both Session RNGs"):return
	var legacy_bytes_after := _read_file(legacy_path)
	var legacy_backup_after := _read_file(legacy_path + ".bak")
	var legacy_tmp_after := _read_file(legacy_path + ".tmp")
	if not check(legacy_bytes_after.get("ok", false) and legacy_backup_after.get("ok", false) and legacy_tmp_after.get("ok", false), "Legacy post-images are fully readable"):return
	if not check(_same_file_image(legacy_bytes_after, legacy_bytes_before), "Legacy primary existence/length/bytes stay exact"):return
	if not check(_same_file_image(legacy_backup_after, legacy_backup_before), "Legacy backup existence/length/bytes stay exact"):return
	if not check(_same_file_image(legacy_tmp_after, legacy_tmp_before), "Legacy tmp existence/length/bytes stay exact"):return

	var malformed_failure_mark: int = failures
	_malformed_cases(ticket)
	if failures != malformed_failure_mark:return

	# Exercise actual writer -> actual one-shot Backend.load_resume -> observed QuestAuto entry.
	var matching_profile_path := _path("resume-profile-matching-producer")
	if not check(_write_profile(matching_profile_path, _profile(none)), "Matching producer profile fixture write succeeds"):return
	var matching_backend = ResumeProbeBackend.new()
	var matching_spy = ResumeSpy.new()
	matching_backend.quest_auto = matching_spy
	matching_backend.save_path = matching_profile_path
	_configure_session_clock(matching_backend.session)
	if not check(matching_backend.session.load_game(matching_profile_path), "Matching producer profile uses actual loader"):
		matching_backend.free()
		return
	matching_spy.running = true
	matching_spy.identity.run_id = RUN_A
	matching_spy.identity.step_id = "test-step"
	matching_spy.identity.revision = 4
	var generated: Dictionary = matching_backend._quest_resume_state({})
	if not check(generated.get("fee_attempt_binding", {}) == {"owner": _owner(), "run_id": RUN_A}, "Server constructs binding from actual QuestAuto identity and live profile journal"):
		matching_backend.free()
		return
	matching_backend.free()
	_resume_dispatch_case("matching-active", none, generated, true)
	_resume_dispatch_case("legacy-no-fee-data", {}, _resume_state(RUN_A, _owner(), false), true)
	_resume_dispatch_case("closed-run", closed_plain, _resume_state(RUN_A, _owner()), false)
	_resume_dispatch_case("attempting-unknown-outcome", attempting, _resume_state(RUN_A, _owner()), false)
	_resume_dispatch_case("record-without-binding", none, _resume_state(RUN_A, _owner(), false), false)
	_resume_dispatch_case("binding-without-record", {}, _resume_state(RUN_A, _owner()), false)
	_resume_dispatch_case("wrong-owner", none, _resume_state(RUN_A, {"profile_id": "samgir-singleplayer-v1", "character_id": "other"}), false)
	_resume_dispatch_case("wrong-run", none, _resume_state(RUN_B, _owner()), false)
	var bad_identity := _resume_state(RUN_A, _owner())
	bad_identity.quest_auto.identity.revision = true
	_resume_dispatch_case("bad-identity-bool-revision", none, bad_identity, false)
	var out_of_range_identity := _resume_state(RUN_A, _owner())
	out_of_range_identity.quest_auto.identity.revision = 2147483647
	_resume_dispatch_case("bad-identity-revision-bound", none, out_of_range_identity, false)
	var long_step_identity := _resume_state(RUN_A, _owner())
	long_step_identity.quest_auto.identity.step_id = "s".repeat(257)
	_resume_dispatch_case("bad-identity-step-length", none, long_step_identity, false)

	print("FEE LIFECYCLE LOAD/RESUME assertions=", assertions, " failures=", failures, " evidence_tag=", run_tag)
	quit(0 if failures == 0 else 1)
