extends SceneTree
## UNRUN private writer-candidate oracle. No Stop caller, RPC, source authority,
## ticket price, route, sidecar or user-facing behavior is exercised.
const Backend = preload("res://server/backend.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
const FaultSession = preload("res://tests/support/fee_attempt_close_fault_session.gd")
const RUN := "11111111111111111111111111111111"
const OTHER_RUN := "44444444444444444444444444444444"
const ATTEMPT := "22222222222222222222222222222222"
const SOURCE := "synthetic-stop-test-source"
const OFFER := "synthetic-stop-test-offer"
const ITEM := 799001
const AMOUNT := 37
var failures: int = 0
var case_index: int = 0
var kept_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func is_true(value:Variant)->bool:
	if not value is bool:return false
	var typed:bool=value
	return typed

func is_false(value:Variant)->bool:
	if not value is bool:return false
	var typed:bool=value
	return not typed

func is_unknown(value:Variant)->bool:
	return value is String and value=="unknown"

func raw(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"ok": false, "exists": true, "directory": true, "bytes": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error: int = FileAccess.get_open_error()
		return {"ok": open_error == ERR_FILE_NOT_FOUND, "exists": false, "error": open_error, "bytes": PackedByteArray()}
	var length: int = file.get_length()
	if length < 0 or length > 2147483647:
		file.close()
		return {"ok": false, "exists": true, "error": ERR_FILE_CANT_READ, "bytes": PackedByteArray()}
	var bytes: PackedByteArray = file.get_buffer(length)
	var error: int = file.get_error()
	file.close()
	return {"ok": error == OK and bytes.size() == length, "exists": true, "length": length, "error": error, "bytes": bytes}

func fail_setup(host: Node, message: String) -> Dictionary:
	check(false, message)
	host.free()
	quit(1)
	return {}

func setup_profile_validation_context(value: Variant, pure_journal_valid: bool) -> String:
	# Bounded scalar-only context for the original one-shot _valid_profile result.
	# Do not call validators, snapshot, save, or stringify the full profile here.
	if not value is Dictionary:return JSON.stringify({"stage":"after_original_save_migration","reason":"_valid_profile returned false; no first-failure API","profile_type":type_string(typeof(value)),"pure_journal_valid":pure_journal_valid})
	var profile:Dictionary=value
	var fields:Dictionary={}
	for key:String in ["version","profile_id","character_id","player","inventory","quest","location","pets","pet_storage","original_items","original_instances","original_equipment","next_original_uid","quest_loot"]:
		var field:Variant=profile.get(key,null)
		var scalar:String=""
		if field is String or field is int or field is float or field is bool:scalar=str(field)
		fields[key]={"type":type_string(typeof(field)),"scalar":scalar}
	var journal:Variant=profile.get("quest_auto_fee_lifecycle",null)
	var journal_context:Dictionary={"type":type_string(typeof(journal))}
	var owner_matches:bool=false
	if journal is Dictionary:
		journal_context["size"]=journal.size()
		var owner:Variant=journal.get("owner",null)
		var current:Variant=journal.get("current",null)
		if owner is Dictionary:
			journal_context["owner_profile_type"]=type_string(typeof(owner.get("profile_id",null)))
			journal_context["owner_character_type"]=type_string(typeof(owner.get("character_id",null)))
			owner_matches=owner.get("profile_id",null)==profile.get("profile_id",null) and owner.get("character_id",null)==profile.get("character_id",null)
		if current is Dictionary:
			journal_context["schema_type"]=type_string(typeof(journal.get("schema",null)))
			journal_context["run_id_type"]=type_string(typeof(current.get("run_id",null)))
			journal_context["run_status_type"]=type_string(typeof(current.get("run_status",null)))
			var purchase:Variant=current.get("purchase",null)
			journal_context["purchase_type"]=type_string(typeof(purchase))
			if purchase is Dictionary:journal_context["purchase_state"]=str(purchase.get("state","<missing>"))
	return JSON.stringify({"stage":"after_original_save_migration","reason":"_valid_profile returned false; no first-failure API","profile_fields":fields,"journal":journal_context,"owner_matches_profile":owner_matches,"pure_journal_valid":pure_journal_valid})

func expected_closed(prior: Dictionary, attempting: bool) -> Dictionary:
	var expected: Dictionary = prior.duplicate(true)
	expected.current.run_status = "closed"
	if attempting:
		expected.unresolved_attempt = {"origin_run_id": RUN, "attempt_id": ATTEMPT,
			"source_id": SOURCE, "offer_id": OFFER, "item_id": ITEM,
			"amount": AMOUNT, "balance_before": 100}
		expected.current.purchase = {"state": "manual_only"}
	return expected

func setup_case(tag: String, mode: String = "", attempting: bool = false, open_frame: bool = true) -> Dictionary:
	case_index += 1
	var host = Backend.new()
	host.set_process(false)
	host.save_path = "user://fee-close-%d-%02d-%s.json" % [Time.get_ticks_usec(), case_index, tag]
	var session = FaultSession.new()
	session.bind_host(host)
	host.session = session
	session.battle_pets_hook = host._live_battle_pets
	session.capture_entry_hook = host._capture_entry
	session.mode = ""
	var owner_record: Dictionary = Journal.empty_record(str(session._profile.profile_id), str(session._profile.character_id), RUN, true)
	var attached_journal_valid:bool=not owner_record.is_empty() and Journal.valid(owner_record)
	if not attached_journal_valid:return fail_setup(host, "literal fixture owner record is valid")
	if attempting:
		var begin: Dictionary = Journal.begin_attempt(owner_record, RUN, ATTEMPT, SOURCE, OFFER, ITEM, AMOUNT, 100)
		var attempting_record_valid:bool=begin.get("ok",false) and Journal.valid(begin.get("candidate",{}))
		if not attempting_record_valid:return fail_setup(host, "fixture attempting state is legal")
		owner_record = begin.candidate
		attached_journal_valid=attempting_record_valid
	session._profile["quest_auto_fee_lifecycle"] = owner_record.duplicate(true)
	var path: String = ProjectSettings.globalize_path(host.save_path)
	kept_paths.append(path)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix) or DirAccess.dir_exists_absolute(path + suffix):return fail_setup(host, "unique disk fixture path is unused")
	if not session.save_game(host.save_path):return fail_setup(host, "fixture primary is written through original save_game")
	var full_profile_valid:bool=session._valid_profile(session._profile)
	if not full_profile_valid:
		print("FEE CLOSE SETUP VALIDATION CONTEXT: "+setup_profile_validation_context(session._profile,attached_journal_valid))
		return fail_setup(host, "full profile with active fee journal validates")
	host.last_saved_payload = JSON.stringify(session._profile)
	host.quest_save_serial = 71
	session.writer_calls = 0
	var active_identity: Dictionary = {"run_id": RUN, "step_id": "close-writer-test", "revision": 8}
	host.quest_auto.running = true
	host.quest_auto.internal = true
	host.quest_auto.identity.run_id = RUN
	host.quest_auto.identity.step_id = str(active_identity.step_id)
	host.quest_auto.identity.revision = int(active_identity.revision)
	# Model the exact stop identity effect only; this is not a call to stop().
	host.quest_auto.identity.invalidate()
	host.quest_auto.running = false
	host.quest_auto.source_frame = null
	var profile_before: Dictionary = session._profile.duplicate(true)
	var old_journal: Dictionary = owner_record.duplicate(true)
	var expected_journal: Dictionary = expected_closed(old_journal, attempting)
	var pure: Dictionary = Journal.close_run(old_journal, RUN)
	if not pure.get("ok", false) or pure.get("already_closed", true) or pure.get("candidate", {}) != expected_journal or not Journal.valid(expected_journal):return fail_setup(host, "close_run equals independent literal and output validates")
	var candidate: Dictionary = session._profile.duplicate(true)
	candidate.quest_auto_fee_lifecycle = expected_journal.duplicate(true)
	var candidate_before: Dictionary = candidate.duplicate(true)
	var handle: Dictionary = {}
	if open_frame:
		handle = host._begin_fee_attempt_close_frame(active_identity, candidate)
		if handle.is_empty():return fail_setup(host, "exact stopped identity and close candidate seal private frame")
	if candidate != candidate_before:return fail_setup(host, "frame setup does not mutate candidate input")
	var p0: Dictionary = raw(host.save_path)
	var b0: Dictionary = raw(host.save_path + ".bak")
	var t0: Dictionary = raw(host.save_path + ".tmp")
	if not p0.ok or p0.bytes != host.last_saved_payload.to_utf8_buffer() or not b0.ok or b0.exists or not t0.ok or t0.exists:return fail_setup(host, "P0 primary/cache exact; backup/tmp absent")
	var expected_read_baseline:int=3 if open_frame else 0
	if session.writer_calls!=0 or session.read_calls!=expected_read_baseline:return fail_setup(host,"setup writer/read counters match pre-persist baseline")
	# Arm the requested fault only after the ordinary setup save and frame reads.
	session.mode=mode
	return {"host": host, "session": session, "mode":mode,"tag":tag,"handle": handle, "candidate": candidate,
		"writer_calls_before_persist":session.writer_calls,"read_calls_before_persist":session.read_calls,
		"profile_ref0": session._profile,"profile_id0":str(session._profile.profile_id),"save_path0":host.save_path,
		"prior_profile": profile_before,
		"cache0": host.last_saved_payload, "serial0": host.quest_save_serial,
		"primary0": p0, "backup0": b0, "active_identity": active_identity}

func cleanup_memory(data: Dictionary) -> void:
	if data.get("host") is Node and is_instance_valid(data.host):data.host.free()

func persist_case(data:Dictionary)->Dictionary:
	var session:Variant=data.get("session",null)
	if not session is FaultSession or not data.get("host") is Backend:return {"ok":false,"stage":"invalid_test_case"}
	if session.mode!=data.get("mode",null):
		check(false,"fault mode is armed only after setup: %s" % str(data.get("tag","unknown")))
		return {"ok":false,"stage":"fault_mode_not_armed"}
	if session.writer_calls!=data.get("writer_calls_before_persist",-1) or session.read_calls!=data.get("read_calls_before_persist",-1):
		check(false,"writer/read counters match setup baseline: %s" % str(data.get("tag","unknown")))
		return {"ok":false,"stage":"setup_counter_baseline_changed"}
	var expected_calls:Dictionary={
		"success":{"writers":2,"reads":15},"attempting":{"writers":2,"reads":15},
		"w1-open-failure":{"writers":1,"reads":9},"w1-wrapper-false":{"writers":1,"reads":9},
		"w2-open-failure":{"writers":2,"reads":15},"w2-wrapper-false":{"writers":2,"reads":15},
		"same-handle-reentry":{"writers":2,"reads":15},"sidecar-claim-during-w1":{"writers":1,"reads":9},
		"identity-before-w1":{"writers":0,"reads":3},"owner-before-w1":{"writers":0,"reads":3},
		"identity-during-w1":{"writers":1,"reads":9},"owner-during-w1":{"writers":1,"reads":9},
		"path-during-w1":{"writers":1,"reads":9},"readback-unknown":{"writers":1,"reads":9},
		"missing-w1-return":{"writers":1,"reads":9},"missing-w2-return":{"writers":2,"reads":15}}
	var tag:Variant=data.get("tag",null)
	if not tag is String or not expected_calls.has(tag):
		check(false,"persist case has an explicit writer/read oracle tag")
		return {"ok":false,"stage":"missing_counter_oracle"}
	var expected:Dictionary=expected_calls[tag]
	var result:Dictionary=data.host._persist_fee_attempt_close_pair(data.handle)
	check(session.writer_calls==expected.writers and session.read_calls==expected.reads,"actual writer/read totals match static call-path oracle: %s" % tag)
	return result

func run() -> void:
	# Success, no purchase: only run_status changes; all profile fields stay equal.
	var success: Dictionary = setup_case("success")
	if success.is_empty():return
	var expected_profile: Dictionary = success.candidate.duplicate(true)
	var result: Dictionary = persist_case(success)
	var p1: Dictionary = raw(success.host.save_path)
	var b1: Dictionary = raw(success.host.save_path + ".bak")
	var t1: Dictionary = raw(success.host.save_path + ".tmp")
	var close_bytes: PackedByteArray = JSON.stringify(expected_profile).to_utf8_buffer()
	check(is_true(result.get("ok",null)) and is_true(result.get("profile_pair_closed",null)) and result.w1_calls == 1 and result.w2_calls == 1, "W1/W2 close pair verifies")
	check(p1.ok and b1.ok and t1.ok and p1.bytes == close_bytes and b1.bytes == close_bytes and not t1.exists, "all three raw files match independent close candidate")
	check(success.host.session._profile == expected_profile and success.host.last_saved_payload == JSON.stringify(expected_profile), "W1 installs exact full profile/cache")
	check(success.host.quest_save_serial == success.serial0 + 1 and result.serial_after_w1 == success.serial0 + 1 and result.serial_after_w2 == success.serial0 + 1, "serial advances exactly once at W1 install")
	var replay: Dictionary = success.host._persist_fee_attempt_close_pair(success.handle)
	check(is_false(replay.get("ok",null)) and replay.stage == "invalid_handle" and success.session.writer_calls == 2, "same handle replay rejected after frame retirement")
	check(success.host._begin_fee_attempt_close_frame(success.active_identity, expected_profile).is_empty() and success.session.writer_calls == 2, "repeated close candidate rejected once profile record is already closed")
	cleanup_memory(success)

	# Attempting closes to an unresolved tombstone, never a new automatic attempt.
	var attempted: Dictionary = setup_case("attempting", "", true)
	if attempted.is_empty():return
	var attempt_result: Dictionary = persist_case(attempted)
	var attempt_journal: Dictionary = attempted.host.session._profile.quest_auto_fee_lifecycle
	check(is_true(attempt_result.get("ok",null)) and Journal.valid(attempt_journal) and attempt_journal.current.run_status == "closed", "attempting profile closes through legal pure transition")
	check(attempt_journal.current.purchase == {"state":"manual_only"} and attempt_journal.unresolved_attempt.origin_run_id == RUN and attempt_journal.unresolved_attempt.attempt_id == ATTEMPT, "unknown attempt becomes origin-bound manual-only tombstone")
	cleanup_memory(attempted)

	# Invalid full-profile delta and another run's otherwise-valid candidate refuse before writes.
	var invalid: Dictionary = setup_case("invalid-candidate", "", false, false)
	if invalid.is_empty():return
	var wrong: Dictionary = invalid.candidate.duplicate(true)
	wrong.player.gold = int(wrong.player.get("gold",0)) + 1
	check(invalid.host._begin_fee_attempt_close_frame(invalid.active_identity, wrong).is_empty() and invalid.session.writer_calls == 0, "unrelated profile mutation is rejected")
	var other: Dictionary = invalid.candidate.duplicate(true)
	var other_record: Dictionary = Journal.empty_record(str(other.profile_id), str(other.character_id), OTHER_RUN, true)
	other.quest_auto_fee_lifecycle = Journal.close_run(other_record, OTHER_RUN).candidate
	check(invalid.host._begin_fee_attempt_close_frame(invalid.active_identity, other).is_empty() and invalid.session.writer_calls == 0, "cross-run candidate rejected")
	var wrong_owner: Dictionary = invalid.candidate.duplicate(true)
	wrong_owner.quest_auto_fee_lifecycle.owner.profile_id = "other-profile"
	check(invalid.host._begin_fee_attempt_close_frame(invalid.active_identity, wrong_owner).is_empty(), "same-run record for a different profile owner is rejected")
	var second_frame: Dictionary = invalid.host._begin_fee_attempt_close_frame(invalid.active_identity, invalid.candidate)
	check(not second_frame.is_empty(), "valid frame can be sealed after invalid candidates")
	check(invalid.host._begin_fee_attempt_close_frame(invalid.active_identity, invalid.candidate).is_empty(), "single-flight blocks another close frame")
	cleanup_memory(invalid)

	# W1 true I/O failure: no closed primary/backup fact; tmp directory is retained.
	var w1fail: Dictionary = setup_case("w1-open-failure", "w1_open_error")
	if w1fail.is_empty():return
	var w1_result: Dictionary = persist_case(w1fail)
	var p_w1: Dictionary = raw(w1fail.host.save_path)
	var b_w1: Dictionary = raw(w1fail.host.save_path + ".bak")
	check(is_false(w1_result.get("ok",null)) and w1_result.w1_calls == 1 and w1_result.serial_after_w2 == w1fail.serial0, "W1 failure does not install profile or advance serial")
	check(p_w1.ok and p_w1.bytes == w1fail.primary0.bytes and b_w1.ok and not b_w1.exists and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(w1fail.host.save_path + ".tmp")) and w1_result.temporary == "unknown", "W1 failure retains primary/backup and reports unreadable tmp directory as unknown")
	check(w1fail.host.session._profile.quest_auto_fee_lifecycle.current.run_status == "active" and w1fail.host.last_saved_payload == w1fail.cache0, "W1 failure does not fake an in-memory close")
	cleanup_memory(w1fail)

	# W1 wrapper false after primary candidate readback: install and report partial; do not roll back.
	var w1false: Dictionary = setup_case("w1-wrapper-false", "w1_wrapper_false_after_commit")
	if w1false.is_empty():return
	var w1false_result: Dictionary = persist_case(w1false)
	var w1false_p: Dictionary = raw(w1false.host.save_path)
	var w1false_b: Dictionary = raw(w1false.host.save_path + ".bak")
	var w1false_t: Dictionary = raw(w1false.host.save_path + ".tmp")
	check(is_false(w1false_result.get("ok",null)) and is_true(w1false_result.get("primary_closed",null)) and is_false(w1false_result.get("backup_closed",null)) and is_false(w1false_result.get("w1_writer_return",null)), "false W1 wrapper is reported separately from landed primary")
	check(w1false_p.bytes == JSON.stringify(w1false.candidate).to_utf8_buffer() and w1false_b.bytes == w1false.primary0.bytes and w1false_t.ok and not w1false_t.exists and w1false.host.session._profile == w1false.candidate and w1false.host.quest_save_serial == w1false.serial0 + 1, "W1 partial remains installed, backup old, tmp absent, serial once")
	cleanup_memory(w1false)

	# W2 open failure preserves W1 primary and memory; backup remains original.
	var w2fail: Dictionary = setup_case("w2-open-failure", "w2_open_error")
	if w2fail.is_empty():return
	var w2_result: Dictionary = persist_case(w2fail)
	var w2_p: Dictionary = raw(w2fail.host.save_path)
	var w2_b: Dictionary = raw(w2fail.host.save_path + ".bak")
	check(is_false(w2_result.get("ok",null)) and is_true(w2_result.get("primary_closed",null)) and is_false(w2_result.get("backup_closed",null)) and w2_result.serial_after_w1 == w2fail.serial0 + 1, "W2 failure reports exact W1 partial fact")
	check(w2_p.bytes == JSON.stringify(w2fail.candidate).to_utf8_buffer() and w2_b.bytes == w2fail.primary0.bytes and w2fail.host.session._profile == w2fail.candidate, "W2 failure never rolls back W1 primary or memory")
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(w2fail.host.save_path + ".tmp")) and w2_result.temporary == "unknown", "W2 injected tmp directory remains and its read fact stays unknown")
	cleanup_memory(w2fail)

	# W2 wrapper false after two exact readbacks: facts say pair closed; operation flag remains false.
	var w2false: Dictionary = setup_case("w2-wrapper-false", "w2_wrapper_false_after_commit")
	if w2false.is_empty():return
	var w2false_result: Dictionary = persist_case(w2false)
	check(is_false(w2false_result.get("ok",null)) and is_true(w2false_result.get("profile_pair_closed",null)) and is_false(w2false_result.get("w2_writer_return",null)), "pair readback fact is not erased by wrapper false")
	var w2false_p: Dictionary = raw(w2false.host.save_path)
	var w2false_b: Dictionary = raw(w2false.host.save_path + ".bak")
	var w2false_t: Dictionary = raw(w2false.host.save_path + ".tmp")
	check(w2false_p.bytes == JSON.stringify(w2false.candidate).to_utf8_buffer() and w2false_b.bytes == w2false_p.bytes and w2false_t.ok and not w2false_t.exists and w2false.host.quest_save_serial == w2false.serial0 + 1, "W2 exact pair remains installed, tmp absent, one serial increment")
	cleanup_memory(w2false)

	# Same-handle nested call is rejected while the outer writer owns execution.
	var nested: Dictionary = setup_case("same-handle-reentry", "w1_reenter_same_handle")
	if nested.is_empty():return
	nested.session.reentry_handle = nested.handle
	var nested_outer: Dictionary = persist_case(nested)
	check(nested.session.nested_result.get("stage","") == "already_executing" and not nested.session.nested_result.get("ok",true), "nested same-handle call is refused")
	check(is_true(nested_outer.get("ok",null)) and nested.session.writer_calls == 2 and is_true(nested_outer.get("profile_pair_closed",null)), "outer call alone performs W1/W2")
	cleanup_memory(nested)

	# A sidecar claim that appears inside the virtual W1 writer prevents stale
	# memory installation and W2 at the next close-frame checkpoint.
	var late_claim:Dictionary=setup_case("sidecar-claim-during-w1","w1_claim_sidecar")
	if late_claim.is_empty():return
	var late_claim_result:Dictionary=persist_case(late_claim)
	var late_claim_primary:Dictionary=raw(late_claim.host.save_path)
	check(is_false(late_claim_result.get("ok",null)) and is_true(late_claim_result.get("primary_closed",null)) and late_claim.session.writer_calls==1,"late sidecar claim blocks install/W2 after W1")
	check(late_claim_primary.ok and late_claim_primary.bytes==JSON.stringify(late_claim.candidate).to_utf8_buffer() and late_claim.host.session._profile.quest_auto_fee_lifecycle.current.run_status=="active" and late_claim.host.quest_save_serial==late_claim.serial0,"late claim preserves old in-memory owner despite W1 disk fact")
	cleanup_memory(late_claim)

	# Owner identity changes before W1: fresh write admission fails and disk is unchanged.
	var stale: Dictionary = setup_case("identity-before-w1")
	if stale.is_empty():return
	stale.host.quest_auto.identity.run_id = OTHER_RUN
	var stale_result: Dictionary = persist_case(stale)
	var stale_p: Dictionary = raw(stale.host.save_path)
	check(is_false(stale_result.get("ok",null)) and stale.session.writer_calls == 0 and stale_p.bytes == stale.primary0.bytes, "old stop identity cannot write after successor mutation")
	cleanup_memory(stale)

	# Profile owner changes before W1: no old close candidate is written.
	var owner_before: Dictionary = setup_case("owner-before-w1")
	if owner_before.is_empty():return
	owner_before.host.session._profile.profile_id = "successor-profile"
	var owner_before_result: Dictionary = persist_case(owner_before)
	var owner_before_primary: Dictionary = raw(owner_before.host.save_path)
	check(is_false(owner_before_result.get("ok",null)) and owner_before.session.writer_calls == 0 and owner_before_primary.bytes == owner_before.primary0.bytes, "owner mutation before W1 prevents stale close write")
	cleanup_memory(owner_before)

	# Identity replacement inside W1 leaves only the old captured path's W1 fact;
	# no W2 and no install into the changed QuestAuto owner.
	var successor: Dictionary = setup_case("identity-during-w1", "w1_replace_identity")
	if successor.is_empty():return
	var successor_result: Dictionary = persist_case(successor)
	var successor_p: Dictionary = raw(successor.host.save_path)
	var successor_b: Dictionary = raw(successor.host.save_path + ".bak")
	check(is_false(successor_result.get("ok",null)) and is_true(successor_result.get("primary_closed",null)) and successor.session.writer_calls == 1, "identity successor stops stale frame after W1")
	check(successor_p.bytes == JSON.stringify(successor.candidate).to_utf8_buffer() and successor_b.bytes == successor.primary0.bytes and successor.host.session._profile.quest_auto_fee_lifecycle.current.run_status == "active", "old W1 disk fact not installed over successor memory")
	cleanup_memory(successor)

	# Profile owner replacement inside W1 leaves only the captured old-path fact.
	var owner_after: Dictionary = setup_case("owner-during-w1", "w1_replace_profile_owner")
	if owner_after.is_empty():return
	var owner_after_result: Dictionary = persist_case(owner_after)
	var owner_after_primary: Dictionary = raw(owner_after.host.save_path)
	var owner_after_backup: Dictionary = raw(owner_after.host.save_path + ".bak")
	check(is_false(owner_after_result.get("ok",null)) and is_true(owner_after_result.get("primary_closed",null)) and owner_after.session.writer_calls == 1, "owner replacement after W1 blocks stale install and W2")
	check(owner_after_primary.bytes == JSON.stringify(owner_after.candidate).to_utf8_buffer() and owner_after_backup.bytes == owner_after.primary0.bytes and owner_after.host.session._profile.profile_id == "successor-profile-must-not-be-written", "old disk fact is not installed over replacement profile")
	cleanup_memory(owner_after)

	# Path replacement inside W1 must not create or touch the successor path.
	var path_case: Dictionary = setup_case("path-during-w1", "w1_replace_path")
	if path_case.is_empty():return
	var original_path: String = path_case.host._fee_attempt_close_frame.path
	var path_result: Dictionary = persist_case(path_case)
	var new_path: String = ProjectSettings.globalize_path(path_case.host.save_path)
	var old_primary: Dictionary = raw(original_path)
	check(is_false(path_result.get("ok",null)) and is_true(path_result.get("primary_closed",null)) and path_case.session.writer_calls == 1, "path successor stops the old frame after its captured W1")
	check(old_primary.ok and old_primary.bytes == JSON.stringify(path_case.candidate).to_utf8_buffer() and not FileAccess.file_exists(new_path) and not FileAccess.file_exists(new_path + ".tmp"), "writer remains on captured path; successor path untouched")
	cleanup_memory(path_case)

	# The writer may land while the wrapper cannot provide a trustworthy readback.
	var readback_unknown:Dictionary=setup_case("readback-unknown","w1_readback_unknown")
	if readback_unknown.is_empty():return
	var readback_unknown_result:Dictionary=persist_case(readback_unknown)
	var readback_unknown_disk:Dictionary=raw(readback_unknown.host.save_path)
	check(is_false(readback_unknown_result.get("ok",null)) and is_unknown(readback_unknown_result.get("primary_closed",null)) and is_unknown(readback_unknown_result.get("profile_pair_closed",null)),"unreadable writer result remains unknown, never coerced to false")
	check(readback_unknown_disk.ok and readback_unknown_disk.bytes==JSON.stringify(readback_unknown.candidate).to_utf8_buffer() and readback_unknown.host.session._profile.quest_auto_fee_lifecycle.current.run_status=="active" and readback_unknown.host.quest_save_serial==readback_unknown.serial0,"unknown readback does not install or fake rollback a known disk fact")
	cleanup_memory(readback_unknown)

	# Missing writer_return is not a bool: W1 evidence installs once but refuses W2.
	var missing_w1:Dictionary=setup_case("missing-w1-return","w1_missing_writer_return")
	if missing_w1.is_empty():return
	var missing_w1_result:Dictionary=persist_case(missing_w1)
	check(is_false(missing_w1_result.get("ok",null)) and is_unknown(missing_w1_result.get("w1_writer_return",null)) and is_true(missing_w1_result.get("primary_closed",null)),"missing W1 return stays unknown despite primary readback")
	check(missing_w1.session.writer_calls==1 and missing_w1.host.quest_save_serial==missing_w1.serial0+1 and missing_w1.host.session._profile==missing_w1.candidate,"missing W1 return preserves landed candidate and blocks W2")
	cleanup_memory(missing_w1)

	# Missing W2 writer_return keeps complete disk facts separate from operation success.
	var missing_w2:Dictionary=setup_case("missing-w2-return","w2_missing_writer_return")
	if missing_w2.is_empty():return
	var missing_w2_result:Dictionary=persist_case(missing_w2)
	check(is_false(missing_w2_result.get("ok",null)) and is_unknown(missing_w2_result.get("w2_writer_return",null)) and is_true(missing_w2_result.get("profile_pair_closed",null)),"missing W2 return remains unknown while exact pair readback remains true")
	check(missing_w2.session.writer_calls==2 and missing_w2.host.quest_save_serial==missing_w2.serial0+1,"missing W2 return does not trigger a third write")
	cleanup_memory(missing_w2)

	# Read callbacks run after the candidate preflight snapshot. Each mutation must
	# prevent handle publication before any physical write or successor-path touch.
	var read_mutations:Dictionary={
		"read_replace_session":1,"read_change_serial":1,
		"read_replace_profile":2,"read_change_owner":2,"read_claim_sidecar":2,
		"read_replace_path":3,"read_replace_identity":3,"read_change_cache":3
	}
	for mutation_value in read_mutations.keys():
		var mutation:String=str(mutation_value)
		var expected_read_count:int=int(read_mutations[mutation])
		var row:Dictionary=setup_case("pre-read-"+mutation,"",false,false)
		if row.is_empty():return
		row.session.mode=mutation
		row.session.mutate_after_read=expected_read_count
		var read_original_path:String=row.host.save_path
		var pre_p:Dictionary=raw(read_original_path)
		var refused:Dictionary=row.host._begin_fee_attempt_close_frame(row.active_identity,row.candidate)
		var after_p:Dictionary=raw(read_original_path)
		var after_b:Dictionary=raw(read_original_path+".bak")
		var after_t:Dictionary=raw(read_original_path+".tmp")
		check(refused.is_empty() and row.session.read_calls==expected_read_count and row.session.writer_calls==0 and row.host._fee_attempt_close_call==null,"pre-read "+mutation+" refuses before handle/write")
		check(pre_p.ok and after_p.ok and pre_p.bytes==after_p.bytes and after_b.ok and not after_b.exists and after_t.ok and not after_t.exists,"pre-read "+mutation+" leaves original target/backup/tmp bytes unchanged")
		if mutation=="read_replace_path":
			var successor_path:String=ProjectSettings.globalize_path(row.host.save_path)
			check(successor_path!=ProjectSettings.globalize_path(read_original_path) and not FileAccess.file_exists(successor_path) and not FileAccess.file_exists(successor_path+".tmp"),"pre-read path mutation never creates successor target/tmp")
		if mutation=="read_replace_session":
			check(row.session.successor_session!=null and row.host.session==row.session.successor_session,"pre-read session replacement remains successor-owned")
		if mutation=="read_replace_profile":
			check(not is_same(row.session._profile,row.profile_ref0) and row.session._profile==row.prior_profile,"pre-read profile reference successor remains unchanged")
		if mutation=="read_change_owner":
			check(row.session._profile.profile_id=="read-successor-profile" and row.session._profile.profile_id!=row.profile_id0,"pre-read owner mutation remains successor-owned")
		if mutation=="read_replace_path":
			check(row.host.save_path!="" and row.host.save_path!=row.save_path0,"pre-read path successor remains selected")
		if mutation=="read_change_serial":
			check(row.host.quest_save_serial==row.serial0+1,"pre-read serial successor remains unchanged")
		if mutation=="read_change_cache":
			check(row.host.last_saved_payload=="read-successor-cache","pre-read cache successor remains unchanged")
		if mutation=="read_replace_identity":
			check(row.host.quest_auto.identity.run_id=="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","pre-read identity successor remains unchanged")
		if mutation=="read_claim_sidecar":
			check(row.host._fee_resume_sidecar_call!=null and not row.host._fee_resume_sidecar_frame.is_empty(),"pre-read old sidecar claim is not cleared")
		if row.session.successor_session!=null:row.session.successor_session=null
		cleanup_memory(row)

	# Existing independent attempt and sidecar claims each block close admission.
	var attempt_claim:Dictionary=setup_case("attempt-claim", "", false, false)
	if attempt_claim.is_empty():return
	attempt_claim.host._fee_attempt_writer_call=RefCounted.new()
	check(attempt_claim.host._begin_fee_attempt_close_frame(attempt_claim.active_identity,attempt_claim.candidate).is_empty() and attempt_claim.session.writer_calls==0,"existing attempt claim blocks close frame")
	cleanup_memory(attempt_claim)
	var sidecar_claim:Dictionary=setup_case("sidecar-claim", "", false, false)
	if sidecar_claim.is_empty():return
	sidecar_claim.host._fee_resume_sidecar_call=RefCounted.new()
	sidecar_claim.host._fee_resume_sidecar_frame={"call":sidecar_claim.host._fee_resume_sidecar_call}
	check(sidecar_claim.host._begin_fee_attempt_close_frame(sidecar_claim.active_identity,sidecar_claim.candidate).is_empty() and sidecar_claim.session.writer_calls==0,"existing sidecar claim blocks close frame")
	cleanup_memory(sidecar_claim)

	print("FEE ATTEMPT CLOSE PAIR CANDIDATE: %d failures; UNRUN" % failures)
	quit(1 if failures else 0)
