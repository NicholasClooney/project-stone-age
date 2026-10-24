extends SceneTree
const Clock=preload("res://scripts/clock.gd")

# UNRUN test candidate. Private frame setup is a test fixture, not a public
# command, authenticated purchase, route proof, or original price assertion.
const Backend = preload("res://server/backend.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
const FaultSession = preload("res://tests/support/fee_attempt_writer_fault_session.gd")
const RUN := "11111111111111111111111111111111"
const ATTEMPT := "22222222222222222222222222222222"
const ALT_ATTEMPT := "33333333333333333333333333333333"
const SOURCE := "synthetic-test-source"
const OFFER := "synthetic-test-offer"
const ITEM := 799001 # synthetic schema-valid journal value; not a game ticket claim
const AMOUNT := 37 # synthetic oracle value; not a 44/200/300 product price
const RUN_B := "44444444444444444444444444444444"
const DISK_SUFFIXES: Array[String] = ["", ".bak", ".tmp"]
var failures := 0
var case_index := 0
var fixture_paths: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func read_exact(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		return {"ok": error == ERR_FILE_NOT_FOUND, "exists": false, "error": error, "bytes": PackedByteArray()}
	var length := file.get_length()
	var length_error := file.get_error()
	if length_error != OK or length < 0 or length > 2147483647:
		file.close()
		return {"ok": false, "exists": true, "error": length_error, "bytes": PackedByteArray()}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	return {"ok": error == OK and bytes.size() == length, "exists": true, "error": error, "bytes": bytes}

func abort_setup(host: Node, label: String) -> Dictionary:
	check(false, label)
	host.free()
	quit(1)
	return {}

func setup_case(tag: String, mode: String = "", attempt_id: String = ATTEMPT, amount: int = AMOUNT) -> Dictionary:
	case_index += 1
	var host = Backend.new()
	host.set_process(false)
	host.save_path = "user://fee-attempt-writer-%d-%02d-%s.json" % [Clock.ticks_usec(), case_index, tag]
	var session = FaultSession.new()
	session.bind_host(host)
	host.session = session
	session.battle_pets_hook = host._live_battle_pets
	session.capture_entry_hook = host._capture_entry
	session._profile["quest_auto_fee_lifecycle"] = Journal.empty_record(
		str(session._profile.profile_id), str(session._profile.character_id), RUN, true)
	if session._profile.quest_auto_fee_lifecycle.is_empty() or not Journal.valid(session._profile.quest_auto_fee_lifecycle):
		return abort_setup(host, "fixture journal created and validates")
	var base: String = ProjectSettings.globalize_path(host.save_path)
	fixture_paths.append(base)
	for suffix in DISK_SUFFIXES:
		var file_path: String = base + suffix
		if FileAccess.file_exists(file_path) or DirAccess.dir_exists_absolute(file_path):
			return abort_setup(host, "Unique isolated fixture path is unused")
	host.quest_auto.running = true
	host.quest_auto.internal = true
	host.quest_auto.identity.run_id = RUN
	host.quest_auto.identity.step_id = "fee_attempt_test"
	host.quest_auto.identity.revision = 1
	if not session.save_game(host.save_path):
		return abort_setup(host, "baseline uses original save_game")
	host.last_saved_payload = JSON.stringify(session._profile)
	host.quest_save_serial = 50
	session.writer_calls = 0
	session.read_calls = 0
	session.mode = mode
	var prior: Dictionary = session._profile.quest_auto_fee_lifecycle.duplicate(true)
	# Independent literal oracle; production begin_attempt must derive this exact
	# transition, but does not construct the expected profile used below.
	var expected_journal: Dictionary = prior.duplicate(true)
	expected_journal.current.purchase = {"state": "attempting", "attempt_id": attempt_id,
		"source_id": SOURCE, "offer_id": OFFER, "item_id": ITEM,
		"amount": amount, "balance_before": 100}
	var attempt: Dictionary = Journal.begin_attempt(prior, RUN, attempt_id, SOURCE, OFFER, ITEM, amount, 100)
	if not attempt.get("ok", false) or attempt.get("candidate", {}) != expected_journal or not Journal.valid(expected_journal):
		return abort_setup(host, "pure begin_attempt equals independent literal legal transition")
	var candidate: Dictionary = session._profile.duplicate(true)
	candidate.quest_auto_fee_lifecycle = expected_journal
	host._depth = 1 # internal synchronous command-depth fixture only
	var wrong_run_prior: Dictionary = Journal.empty_record(str(session._profile.profile_id), str(session._profile.character_id), RUN_B, true)
	var wrong_run_attempt: Dictionary = Journal.begin_attempt(wrong_run_prior, RUN_B, ALT_ATTEMPT, SOURCE, OFFER, ITEM, amount, 100)
	if not wrong_run_attempt.get("ok", false) or not Journal.valid(wrong_run_attempt.get("candidate", {})):
		return abort_setup(host, "wrong-run negative is independently pure-valid")
	var wrong_run_profile: Dictionary = session._profile.duplicate(true)
	wrong_run_profile.quest_auto_fee_lifecycle = wrong_run_attempt.candidate
	if not host._begin_fee_attempt_writer_frame(wrong_run_profile).is_empty():
		return abort_setup(host, "pure-valid journal for another live run is rejected")
	var handle: Dictionary = host._begin_fee_attempt_writer_frame(candidate)
	if handle.is_empty():
		return abort_setup(host, "backend seals legal same-run journal transition")
	session.reentry_handle = handle
	session.read_calls = 0 # begin-frame file reads are outside the injected W1/W2 phase ordinal
	var primary0: Dictionary = read_exact(host.save_path)
	var backup0: Dictionary = read_exact(host.save_path + ".bak")
	var temporary0: Dictionary = read_exact(host.save_path + ".tmp")
	if not primary0.ok or primary0.bytes != host.last_saved_payload.to_utf8_buffer():
		return abort_setup(host, "P0 primary bytes equal independently captured cache")
	if not backup0.ok or backup0.exists or not temporary0.ok or temporary0.exists:
		return abort_setup(host, "P0 backup/tmp are explicitly absent")
	return {"host": host, "session": session, "handle": handle, "candidate": candidate,
		"p0": session._profile.duplicate(true), "cache0": host.last_saved_payload,
		"serial0": host.quest_save_serial, "primary0": primary0, "backup0": backup0}

func profile_is(host, expected: Dictionary) -> bool:
	return host.session._profile == expected

func finish_case(data: Dictionary) -> void:
	data.host.free()

func run() -> void:
	# Successful W1 + W2: two physical writes, one in-memory serial install.
	var ok_case := setup_case("success")
	if ok_case.is_empty(): return
	var success: Dictionary = ok_case.host._persist_fee_attempt_fence(ok_case.handle)
	var success_p := read_exact(ok_case.host.save_path)
	var success_b := read_exact(ok_case.host.save_path + ".bak")
	var success_t := read_exact(ok_case.host.save_path + ".tmp")
	check(success.ok and success.persisted == true and success.w1_calls == 1 and success.w2_calls == 1, "two real writer calls complete")
	check(ok_case.session.writer_calls == 2 and success_p.ok and success_b.ok and success_t.ok and not success_t.exists, "P1 primary/backup read back and tmp absent")
	check(success_p.bytes == JSON.stringify(ok_case.candidate).to_utf8_buffer() and success_b.bytes == success_p.bytes, "independent full candidate bytes in both copies")
	check(profile_is(ok_case.host, ok_case.candidate) and ok_case.host.last_saved_payload == JSON.stringify(ok_case.candidate), "live profile and cache install exact candidate")
	check(ok_case.host.quest_save_serial == ok_case.serial0 + 1 and success.serial_after_w2 == ok_case.serial0 + 1, "serial counts one W1 install, not two physical writes")
	var replay: Dictionary = ok_case.host._persist_fee_attempt_fence(ok_case.handle)
	check(not replay.ok and ok_case.session.writer_calls == 2, "retired handle replay cannot write")
	finish_case(ok_case)

	# An independently prepared legal same-run attempt with different facts is
	# accepted; attempt-id variation alone is not an authorization failure.
	var alternate_case := setup_case("alternate-legal", "", ALT_ATTEMPT, 41)
	if alternate_case.is_empty(): return
	var alternate_success: Dictionary = alternate_case.host._persist_fee_attempt_fence(alternate_case.handle)
	var alternate_primary: Dictionary = read_exact(alternate_case.host.save_path)
	var alternate_backup: Dictionary = read_exact(alternate_case.host.save_path + ".bak")
	check(alternate_success.ok and alternate_success.persisted == true and alternate_case.session.writer_calls == 2, "different legitimate same-run attempt reaches both original writer calls")
	check(alternate_primary.ok and alternate_backup.ok and alternate_primary.bytes == JSON.stringify(alternate_case.candidate).to_utf8_buffer() and alternate_backup.bytes == alternate_primary.bytes, "independent alternate candidate is exact in both copies")
	check(profile_is(alternate_case.host, alternate_case.candidate) and alternate_case.host.quest_save_serial == alternate_case.serial0 + 1, "alternate legitimate attempt installs exact state once")
	finish_case(alternate_case)

	# Forged handle cannot consume or retire the legitimate sealed capability.
	var fake_case := setup_case("forged")
	if fake_case.is_empty(): return
	var fake_result: Dictionary = fake_case.host._persist_fee_attempt_fence({"call": RefCounted.new()})
	var malformed_result: Dictionary = fake_case.host._persist_fee_attempt_fence({"call": fake_case.handle.call, "extra": true})
	check(not fake_result.ok and not malformed_result.ok and fake_case.session.writer_calls == 0, "forged and malformed copied-token handles rejected without I/O")
	var fake_success: Dictionary = fake_case.host._persist_fee_attempt_fence(fake_case.handle)
	check(fake_success.ok and fake_case.session.writer_calls == 2, "forged handle did not retire genuine frame")
	finish_case(fake_case)

	# Actual FileAccess.open failure: test double places a directory at tmp just
	# before super invokes the real writer. This is distinct from wrapper false.
	var w1_io := setup_case("w1-open", "w1_open_error")
	if w1_io.is_empty(): return
	var w1_error: Dictionary = w1_io.host._persist_fee_attempt_fence(w1_io.handle)
	var w1_disk := read_exact(w1_io.host.save_path)
	check(w1_io.session.injected_io_error and w1_io.session.writer_calls == 1 and not w1_error.ok and w1_error.persisted == false, "W1 underlying open error observed; no candidate in canonical files")
	var w1_backup := read_exact(w1_io.host.save_path + ".bak")
	check(w1_disk.ok and w1_disk.bytes == w1_io.primary0.bytes and w1_backup.ok and not w1_backup.exists and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(w1_io.host.save_path + ".tmp")), "W1 failure has exact P0/backup-absent/tmp-directory state")
	check(profile_is(w1_io.host, w1_io.p0) and w1_io.host.last_saved_payload == w1_io.cache0 and w1_io.host.quest_save_serial == w1_io.serial0, "W1 failure retains complete memory/cache/serial P0")
	finish_case(w1_io)

	# Wrapper false after super successfully committed W1 is not an I/O failure.
	var w1_false := setup_case("w1-wrapper-false", "w1_wrapper_false_after_commit")
	if w1_false.is_empty(): return
	var false_result: Dictionary = w1_false.host._persist_fee_attempt_fence(w1_false.handle)
	var false_primary := read_exact(w1_false.host.save_path)
	var false_backup := read_exact(w1_false.host.save_path + ".bak")
	check(not false_result.ok and false_result.persisted == true and false_result.stage == "w1_wrapper_false_after_primary_readback", "wrapper false distinguished from underlying writer error")
	var false_tmp := read_exact(w1_false.host.save_path + ".tmp")
	check(w1_false.session.writer_calls == 1 and false_primary.bytes == JSON.stringify(w1_false.candidate).to_utf8_buffer() and false_backup.bytes == w1_false.primary0.bytes and false_tmp.ok and not false_tmp.exists, "W1 landed P1/P0 backup/tmp absent; W2 not attempted")
	check(profile_is(w1_false.host, w1_false.candidate) and w1_false.host.last_saved_payload == JSON.stringify(w1_false.candidate) and w1_false.host.quest_save_serial == w1_false.serial0 + 1, "W1 landed profile/cache/serial not rolled back")
	finish_case(w1_false)

	# Actual W2 FileAccess.open error after a verified W1.
	var w2_io := setup_case("w2-open", "w2_open_error")
	if w2_io.is_empty(): return
	var w2_error: Dictionary = w2_io.host._persist_fee_attempt_fence(w2_io.handle)
	var w2_primary := read_exact(w2_io.host.save_path)
	var w2_backup := read_exact(w2_io.host.save_path + ".bak")
	check(w2_io.session.injected_io_error and w2_io.session.writer_calls == 2 and not w2_error.ok and w2_error.persisted == true, "W2 underlying open error preserves W1 persisted fact")
	check(w2_primary.bytes == JSON.stringify(w2_io.candidate).to_utf8_buffer() and w2_backup.bytes == w2_io.primary0.bytes and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(w2_io.host.save_path + ".tmp")), "W2 error leaves actual P1/P0/tmp-directory state")
	check(profile_is(w2_io.host, w2_io.candidate) and w2_io.host.last_saved_payload == JSON.stringify(w2_io.candidate) and w2_io.host.quest_save_serial == w2_io.serial0 + 1, "W2 failure never rolls back W1 memory/cache")
	finish_case(w2_io)

	# Serial-only change before W1 must reject without a physical write.
	var serial_before := setup_case("serial-before-w1")
	if serial_before.is_empty(): return
	serial_before.host.quest_save_serial += 1
	var before_serial_result: Dictionary = serial_before.host._persist_fee_attempt_fence(serial_before.handle)
	var serial_before_p := read_exact(serial_before.host.save_path)
	var serial_before_b := read_exact(serial_before.host.save_path + ".bak")
	var serial_before_t := read_exact(serial_before.host.save_path + ".tmp")
	check(not before_serial_result.ok and before_serial_result.stage == "owner_or_cas_rejected_before_w1" and serial_before.session.writer_calls == 0, "S0 mismatch rejects before W1")
	check(serial_before_p.bytes == serial_before.primary0.bytes and serial_before_b.ok and not serial_before_b.exists and serial_before_t.ok and not serial_before_t.exists, "pre-W1 serial mismatch preserves full P0/P0-backup-absent/tmp-absent disk")
	check(profile_is(serial_before.host, serial_before.p0) and serial_before.host.last_saved_payload == serial_before.cache0 and serial_before.host.quest_save_serial == serial_before.serial0 + 1, "pre-W1 serial-only change leaves profile/cache unchanged")
	finish_case(serial_before)

	# Test double increments only serial after the post-W1 disk check and after
	# the P1 in-memory install; the frozen S0+1 W2 expectation must reject it.
	var serial_case := setup_case("serial-before-w2", "serial_w2_interference")
	if serial_case.is_empty(): return
	var serial_result: Dictionary = serial_case.host._persist_fee_attempt_fence(serial_case.handle)
	var serial_disk := read_exact(serial_case.host.save_path)
	check(not serial_result.ok and serial_result.persisted == true and serial_result.stage == "serial_or_owner_changed_before_w2", "W2 fence compares frozen S0+1, not current serial to itself")
	var serial_backup := read_exact(serial_case.host.save_path + ".bak")
	var serial_tmp := read_exact(serial_case.host.save_path + ".tmp")
	check(serial_case.session.writer_calls == 1 and serial_disk.bytes == JSON.stringify(serial_case.candidate).to_utf8_buffer() and serial_backup.bytes == serial_case.primary0.bytes and serial_tmp.ok and not serial_tmp.exists, "serial-only W2 interleaving preserves P1/P0/tmp-absent and stops before W2")
	check(profile_is(serial_case.host, serial_case.candidate) and serial_case.host.last_saved_payload == JSON.stringify(serial_case.candidate) and serial_case.host.quest_save_serial == serial_case.serial0 + 2, "preserve W1 install plus injected serial-only advance")
	finish_case(serial_case)

	# Re-entry with the same handle observes a single-use executing claim.
	var reentry := setup_case("same-handle-reentry", "w1_reenter_same_handle")
	if reentry.is_empty(): return
	var reentry_result: Dictionary = reentry.host._persist_fee_attempt_fence(reentry.handle)
	check(reentry.session.nested_result.get("stage", "") == "already_executing" and not reentry.session.nested_result.get("ok", true), "nested same handle rejected without retiring outer frame")
	var reentry_primary := read_exact(reentry.host.save_path)
	var reentry_backup := read_exact(reentry.host.save_path + ".bak")
	var reentry_tmp := read_exact(reentry.host.save_path + ".tmp")
	check(reentry_result.ok and reentry.session.writer_calls == 2 and reentry_primary.bytes == JSON.stringify(reentry.candidate).to_utf8_buffer() and reentry_backup.bytes == reentry_primary.bytes and reentry_tmp.ok and not reentry_tmp.exists, "outer invocation completes exactly W1/W2 and exact primary/backup")
	check(profile_is(reentry.host, reentry.candidate) and reentry.host.last_saved_payload == JSON.stringify(reentry.candidate) and reentry.host.quest_save_serial == reentry.serial0 + 1, "nested attempt leaves exact profile/cache and one-install serial")
	finish_case(reentry)

	# Owner replacement after W1 leaves known disk P1 but cannot install it into
	# the replaced in-memory quest owner or invoke W2.
	var owner_case := setup_case("owner-replacement", "w1_replace_owner")
	if owner_case.is_empty(): return
	var owner_result: Dictionary = owner_case.host._persist_fee_attempt_fence(owner_case.handle)
	var owner_primary := read_exact(owner_case.host.save_path)
	check(not owner_result.ok and owner_result.persisted == true and owner_result.stage == "w1_landed_but_frame_changed_before_install", "old frame refuses owner replacement")
	var owner_backup := read_exact(owner_case.host.save_path + ".bak")
	var owner_tmp := read_exact(owner_case.host.save_path + ".tmp")
	check(owner_case.session.writer_calls == 1 and owner_primary.bytes == JSON.stringify(owner_case.candidate).to_utf8_buffer() and owner_backup.bytes == owner_case.primary0.bytes and owner_tmp.ok and not owner_tmp.exists, "owner replacement preserves exact P1/P0/tmp-absent and does not write W2")
	check(profile_is(owner_case.host, owner_case.p0) and owner_case.host.last_saved_payload == owner_case.cache0 and owner_case.host.quest_save_serial == owner_case.serial0, "old candidate not installed into changed owner")
	finish_case(owner_case)

	# Replacing the captured settlement dictionary after W1 must be fenced too.
	var settlement_case := setup_case("settlement-replacement", "w1_replace_settlement")
	if settlement_case.is_empty(): return
	var settlement_result: Dictionary = settlement_case.host._persist_fee_attempt_fence(settlement_case.handle)
	var settlement_primary := read_exact(settlement_case.host.save_path)
	var settlement_backup := read_exact(settlement_case.host.save_path + ".bak")
	check(not settlement_result.ok and settlement_result.persisted == true and settlement_result.stage == "w1_landed_but_frame_changed_before_install", "changed loot settlement invalidates the old writer frame")
	check(settlement_case.session.writer_calls == 1 and settlement_primary.bytes == JSON.stringify(settlement_case.candidate).to_utf8_buffer() and settlement_backup.bytes == settlement_case.primary0.bytes, "settlement change preserves W1 disk fact and prevents W2")
	check(profile_is(settlement_case.host, settlement_case.p0) and settlement_case.host.last_saved_payload == settlement_case.cache0 and settlement_case.host.quest_save_serial == settlement_case.serial0, "settlement change prevents stale in-memory installation")
	finish_case(settlement_case)

	if failures == 0:
		for base in fixture_paths:
			for suffix in DISK_SUFFIXES:
				var path: String = base + suffix
				if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
	print("FEE ATTEMPT WRITER FENCE: %d failures; static candidate only" % failures)
	quit(1 if failures else 0)
