extends SceneTree
## Unrun B1 candidate: private Start journal I/O only. No public Start,
## purchase, sidecar, cold recovery, Hub caller or durable ACK is exercised.
const Backend = preload("res://server/backend.gd")
const FaultSession = preload("res://tests/support/fee_start_journal_fault_session.gd")
const Writer = preload("res://server/fee_start_journal_writer.gd")
const OLD := "11111111111111111111111111111111"
const NEW := "22222222222222222222222222222222"
const ORIGIN := "33333333333333333333333333333333"
const ATTEMPT := "44444444444444444444444444444444"
var failures := 0
var checks := 0
var index := 0
var paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func truth(value: Variant) -> bool:
	if not value is bool:return false
	var typed: bool = value
	return typed

func text_is(value: Variant, expected: String) -> bool:
	if not value is String:return false
	return value == expected

func raw(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {"exists": false, "bytes": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:return {"exists": true, "bytes": PackedByteArray(), "error": true}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return {"exists": true, "bytes": bytes}

func literal(owner: Dictionary, run: String, status: String, unknown: bool = false, slot: bool = true) -> Dictionary:
	return {"schema": 1, "owner": owner.duplicate(true),
		"current": {"run_id": run, "run_status": status, "purchase": {"state": "none" if slot and not unknown else "manual_only"}},
		"unresolved_attempt": {"origin_run_id": ORIGIN, "attempt_id": ATTEMPT, "source_id": "test-source", "offer_id": "test-offer", "item_id": 799001, "amount": 37, "balance_before": 100} if unknown else {}}

func setup(tag: String, kind: String = "absent", seal: bool = true) -> Dictionary:
	index += 1
	var b = Backend.new()
	b.set_process(false)
	var s = FaultSession.new()
	b.session = s
	s.host = weakref(b)
	s.battle_pets_hook = b._live_battle_pets
	s.capture_entry_hook = b._capture_entry
	b.save_path = "user://fee-start-%d-%03d-%s.json" % [Time.get_ticks_usec(), index, tag]
	paths.append(ProjectSettings.globalize_path(b.save_path))
	var owner: Dictionary = {"profile_id": s._profile.profile_id, "character_id": s._profile.character_id}
	if kind != "absent":s._profile.quest_auto_fee_lifecycle = literal(owner, OLD, "active" if kind == "active" else "closed", kind == "unknown")
	if not s.save_game(b.save_path):
		check(false, "fixture original save: " + tag)
		b.free()
		quit(1)
		return {}
	if kind == "backup":check(s.save_game(b.save_path), "fixture backup save")
	b.last_saved_payload = JSON.stringify(s._profile)
	b.quest_save_serial = 41
	s.writer_calls = 0
	s.read_calls = 0
	var before: Dictionary = s._profile.duplicate(true)
	var expected: Dictionary = before.duplicate(true)
	expected["quest_auto_fee_lifecycle"] = literal(owner, NEW, "active", kind == "unknown", kind != "manual")
	var disk: Array = [raw(b.save_path), raw(b.save_path + ".bak"), raw(b.save_path + ".tmp")]
	check(disk[0].bytes == b.last_saved_payload.to_utf8_buffer() and disk[1].exists == (kind == "backup") and not disk[2].exists, "fixture raw baseline: " + tag)
	var h: Dictionary = b._begin_fee_start_journal_frame(expected) if seal else {}
	if seal:check(not h.is_empty() and s.read_calls == 3 and s.writer_calls == 0, "sealed frame exact counters: " + tag)
	s.handle = h
	return {"b": b, "s": s, "path": b.save_path, "before": before, "expected": expected, "disk": disk, "handle": h, "cache": b.last_saved_payload, "ref": s._profile, "tag": tag}

func disk_check(c: Dictionary, primary: Dictionary, backup: Dictionary, backup_exists: bool, label: String) -> void:
	var p: Dictionary = raw(c.path)
	var k: Dictionary = raw(c.path + ".bak")
	check(p.exists and p.bytes == JSON.stringify(primary).to_utf8_buffer(), label + ": full primary bytes")
	check(k.exists == backup_exists and (not backup_exists or k.bytes == JSON.stringify(backup).to_utf8_buffer()), label + ": full backup bytes")
	check(not raw(c.path + ".tmp").exists, label + ": tmp absent")

func finish(c: Dictionary) -> void:
	c.b.free() # Deliberately retain every success/failure disk fixture.

func good(kind: String) -> void:
	var c: Dictionary = setup("good-" + kind, kind)
	var r: Dictionary = c.b._persist_fee_start_journal_pair(c.handle)
	check(truth(r.get("ok")) and truth(r.get("pair_verified")) and truth(r.get("installed")), "success flags: " + kind)
	check(c.s.writer_calls == 2 and c.s.read_calls == 15, "success full I/O oracle: " + kind)
	check(c.s._profile == c.expected and c.b.last_saved_payload == JSON.stringify(c.expected) and c.b.quest_save_serial == 42, "success full memory/cache/serial: " + kind)
	disk_check(c, c.expected, c.expected, true, kind)
	check(c.b._fee_attempt_writer_call == null, "claim released: " + kind)
	check(text_is(c.b._persist_fee_start_journal_pair(c.handle).get("stage"), "invalid_handle"), "replay cannot rewrite")
	finish(c)

func faults() -> void:
	for mode: String in ["w1_fail", "w2_fail", "w1_false", "w2_false", "read_unknown", "read_bad_ok", "read_bad_exists", "read_bad_bytes", "bad_return", "bad_row", "owner_after", "serial_after", "path_after", "identity_after", "claim_after", "nested"]:
		var c: Dictionary = setup(mode)
		c.s.mode = mode
		if mode.begins_with("read_"):c.s.read_fault_at = 7 # begin 3 + preflight 3 + W1 primary read.
		var r: Dictionary = c.b._persist_fee_start_journal_pair(c.handle)
		var two: bool = mode in ["w2_fail", "w2_false", "nested"]
		check(c.s.writer_calls == (2 if two else 1) and c.s.read_calls == (15 if two else 9), mode + ": exact all reads/writes")
		check(truth(r.get("ok")) == (mode == "nested"), mode + ": operation result")
		var installed: bool = mode in ["w2_fail", "w1_false", "w2_false", "bad_return", "nested"]
		check(truth(r.get("installed")) == installed, mode + ": installation fact")
		if mode == "owner_after":
			var expected_owner: Dictionary = c.before.duplicate(true)
			expected_owner.profile_id = "successor-profile"
			check(is_same(c.s._profile, c.s.successor) and c.s._profile == expected_owner, "complete independent owner successor retained")
		else:check(c.s._profile == (c.expected if installed else c.before), mode + ": full live profile")
		check(c.b.last_saved_payload == (JSON.stringify(c.expected) if installed else c.cache), mode + ": cache oracle")
		check(c.b.quest_save_serial == (51 if mode == "serial_after" else (42 if installed else 41)), mode + ": serial oracle")
		if mode == "w1_fail":disk_check(c, c.before, {}, false, mode)
		elif mode in ["w2_false", "nested"]:disk_check(c, c.expected, c.expected, true, mode)
		else:disk_check(c, c.expected, c.before, true, mode)
		if mode == "claim_after":check(is_same(c.b._fee_attempt_writer_call, c.s.injected_claim), "successor claim not cleared")
		else:check(c.b._fee_attempt_writer_call == null, mode + ": claim cleared")
		if mode == "nested":check(text_is(c.s.nested.get("stage"), "already_executing") and c.s.nested_frame.is_empty(), "nested same handle/end/begin preserves outer frame")
		if mode.begins_with("read_") or mode == "bad_row":check(text_is(r.get("primary"), "unknown"), mode + ": unreadable is unknown")
		if mode == "w2_false":check(truth(r.get("pair_verified")) and not truth(r.get("ok")), "pair facts survive false W2 wrapper")
		finish(c)

func rejects() -> void:
	for kind: String in ["active", "closed", "unknown", "absent"]:
		var c: Dictionary = setup("reject-" + kind, kind, false)
		var rejected: Dictionary = c.expected.duplicate(true)
		if kind == "closed":rejected.quest_auto_fee_lifecycle.current.run_id = OLD
		elif kind == "unknown":rejected.quest_auto_fee_lifecycle.unresolved_attempt.origin_run_id = OLD
		elif kind == "absent":rejected.player.gold += 1
		check(c.b._begin_fee_start_journal_frame(rejected).is_empty(), kind + ": reject illegal transition/full profile delta")
		check(c.s.read_calls == 0 and c.s.writer_calls == 0 and c.s._profile == c.before, kind + ": rejected before I/O, input unchanged")
		disk_check(c, c.before, {}, false, kind)
		finish(c)
	var typed: Dictionary = setup("typed", "closed", false)
	for side: String in ["before", "candidate"]:
		for key: String in ["profile_id", "character_id"]:
			for bad: Variant in [null, true, 1, [], "", "x".repeat(129)]:
				var before: Dictionary = typed.before.duplicate(true)
				var after: Dictionary = typed.expected.duplicate(true)
				if side == "before":before[key] = bad
				else:after[key] = bad
				check(not Writer.transition(before, after), "strict typed outer owner " + side + key)
			var missing_before: Dictionary = typed.before.duplicate(true)
			var missing_after: Dictionary = typed.expected.duplicate(true)
			if side == "before":missing_before.erase(key)
			else:missing_after.erase(key)
			check(not Writer.transition(missing_before, missing_after), "missing outer owner " + side + key)
		for field: String in ["owner", "current", "schema", "unresolved_attempt"]:
			for bad: Variant in [null, true, 2, [], "bad"]:
				var before: Dictionary = typed.before.duplicate(true)
				var after: Dictionary = typed.expected.duplicate(true)
				if side == "before":before.quest_auto_fee_lifecycle[field] = bad
				else:after.quest_auto_fee_lifecycle[field] = bad
				check(not Writer.transition(before, after), "strict journal field " + side + field)
		for key: String in ["profile_id", "character_id"]:
			for bad: Variant in [null, false, 7, [], "foreign"]:
				var before: Dictionary = typed.before.duplicate(true)
				var after: Dictionary = typed.expected.duplicate(true)
				if side == "before":before.quest_auto_fee_lifecycle.owner[key] = bad
				else:after.quest_auto_fee_lifecycle.owner[key] = bad
				check(not Writer.transition(before, after), "strict inner owner " + side + key)
	for side: String in ["before", "candidate"]:
		for key: String in ["profile_id", "character_id"]:
			var before: Dictionary = typed.before.duplicate(true)
			var after: Dictionary = typed.expected.duplicate(true)
			if side == "before":before.quest_auto_fee_lifecycle.owner.erase(key)
			else:after.quest_auto_fee_lifecycle.owner.erase(key)
			check(not Writer.transition(before, after), "missing inner owner " + side + key)
	for field: String in ["run_id", "run_status", "purchase"]:
		for bad: Variant in [null, false, 1, [], {}]:
			var after: Dictionary = typed.expected.duplicate(true)
			after.quest_auto_fee_lifecycle.current[field] = bad
			check(not Writer.transition(typed.before, after), "bad current field " + field)
	var float_changed: Dictionary = typed.expected.duplicate(true)
	float_changed.player.gold = float(float_changed.player.gold)
	check(not Writer.transition(typed.before, float_changed), "unrelated numeric type change rejected")
	check(typed.s.writer_calls == 0 and typed.s.read_calls == 0, "pure bad types do no I/O")
	finish(typed)

func handles_and_cas() -> void:
	var c: Dictionary = setup("handles")
	for bad: Variant in [null, [], 1, {}, {"start_call": RefCounted.new()}, {"start_call": c.handle.start_call, "extra": true}, {"call": c.handle.start_call}]:
		check(text_is(c.b._persist_fee_start_journal_pair(bad).get("stage"), "invalid_handle"), "wrong handle rejected")
		c.b._end_fee_start_journal_frame(bad)
	var old_shape: Dictionary = {"call": c.handle.start_call}
	check(not truth(c.b._persist_fee_attempt_fence(old_shape).get("ok")), "Start token cannot enter old attempt seam")
	c.b._end_fee_attempt_writer_frame(old_shape)
	check(c.b._begin_quest_auto_stop_operation(c.b.quest_auto).is_empty(), "Start reservation blocks live Stop claim")
	check(c.b._begin_fee_start_journal_frame(c.expected).is_empty(), "nested prepare rejected")
	check(truth(c.b._persist_fee_start_journal_pair(c.handle).get("ok")), "wrong handle did not consume real frame")
	check(c.s.writer_calls == 2 and c.s.read_calls == 15, "handle I/O exact")
	finish(c)
	for mode: String in ["owner", "serial", "path", "ref", "cache", "identity"]:
		var d: Dictionary = setup("pre-" + mode)
		match mode:
			"owner": d.s._profile.profile_id = "new-owner"
			"serial": d.b.quest_save_serial += 1
			"path": d.b.save_path += ".next"
			"ref": d.s._profile = d.s._profile.duplicate(true)
			"cache": d.b.last_saved_payload += " "
			"identity": d.b.quest_auto.identity = preload("res://server/quest_auto_state.gd").new()
		var value: Dictionary = d.s._profile.duplicate(true)
		var ref: Dictionary = d.s._profile
		check(not truth(d.b._persist_fee_start_journal_pair(d.handle).get("ok")), mode + ": stale before write")
		check(d.s.writer_calls == 0 and d.s.read_calls == 3 and is_same(d.s._profile, ref) and d.s._profile == value, mode + ": preserve successor, no I/O")
		disk_check(d, d.before, {}, false, mode)
		finish(d)

func physical_and_read_boundaries() -> void:
	for mode: String in ["w1_tmp_directory", "w2_tmp_directory"]:
		var c: Dictionary = setup(mode)
		c.s.mode = mode
		var r: Dictionary = c.b._persist_fee_start_journal_pair(c.handle)
		var w2: bool = mode == "w2_tmp_directory"
		check(not truth(r.get("ok")) and truth(r.get("installed")) == w2, mode + ": actual tmp-open failure")
		check(c.s.writer_calls == (2 if w2 else 1) and c.s.read_calls == (15 if w2 else 9), mode + ": physical failure exact counters")
		check(raw(c.path).bytes == JSON.stringify(c.expected if w2 else c.before).to_utf8_buffer(), mode + ": full primary")
		check(raw(c.path + ".bak").exists == w2, mode + ": backup existence")
		if w2:check(raw(c.path + ".bak").bytes == JSON.stringify(c.before).to_utf8_buffer(), mode + ": full backup")
		check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(c.path + ".tmp")), mode + ": failure directory retained")
		check(c.s._profile == (c.expected if w2 else c.before) and c.b.quest_save_serial == (42 if w2 else 41), mode + ": no false rollback/install")
		finish(c)
	for ordinal: int in [1, 2, 3]:
		var opening: Dictionary = setup("begin-read-%d" % ordinal, "absent", false)
		opening.s.mode = "read_owner"
		opening.s.read_fault_at = ordinal
		check(opening.b._begin_fee_start_journal_frame(opening.expected).is_empty(), "begin read owner CAS %d" % ordinal)
		check(opening.s.writer_calls == 0 and opening.s.read_calls == ordinal, "begin stops at exact changed read %d" % ordinal)
		check(text_is(opening.s._profile.profile_id, "read-successor"), "begin preserves successor")
		disk_check(opening, opening.before, {}, false, "begin CAS")
		finish(opening)
	for ordinal: int in [4, 5, 6, 10, 11, 12]:
		var c: Dictionary = setup("read-cas-%d" % ordinal)
		c.s.mode = "read_owner"
		c.s.read_fault_at = ordinal
		var r: Dictionary = c.b._persist_fee_start_journal_pair(c.handle)
		var landed: bool = ordinal >= 10
		check(not truth(r.get("ok")) and c.s.read_calls == ordinal and c.s.writer_calls == (1 if landed else 0), "read CAS exact stop %d" % ordinal)
		var expected_successor: Dictionary = (c.expected if landed else c.before).duplicate(true)
		expected_successor.profile_id = "read-successor"
		check(c.s._profile == expected_successor and c.b.quest_save_serial == (42 if landed else 41), "read CAS complete successor %d" % ordinal)
		disk_check(c, c.expected if landed else c.before, c.before, landed, "read CAS")
		finish(c)
	for suffix: String in ["", ".bak", ".tmp"]:
		var c: Dictionary = setup("disk-drift-" + ("primary" if suffix.is_empty() else suffix.substr(1)))
		var file := FileAccess.open(c.path + suffix, FileAccess.WRITE)
		if file == null:
			check(false, "disk drift fixture can open")
			finish(c)
			continue
		file.store_string("independent successor bytes")
		file.close()
		var r: Dictionary = c.b._persist_fee_start_journal_pair(c.handle)
		check(not truth(r.get("ok")) and c.s.writer_calls == 0 and c.s.read_calls == 6, "disk drift exact preflight " + suffix)
		check(c.s._profile == c.before and c.b.quest_save_serial == 41 and raw(c.path + suffix).bytes == "independent successor bytes".to_utf8_buffer(), "disk drift preserves full memory and foreign bytes " + suffix)
		finish(c)
	for claim: String in ["writer", "close", "sidecar", "stop"]:
		var c: Dictionary = setup("busy-" + claim, "absent", false)
		var token := RefCounted.new()
		match claim:
			"writer": c.b._fee_attempt_writer_call = token
			"close": c.b._fee_attempt_close_call = token
			"sidecar": c.b._fee_resume_sidecar_call = token
			"stop": c.b._quest_auto_stop_operation_call = token
		check(c.b._begin_fee_start_journal_frame(c.expected).is_empty(), "busy seam " + claim)
		check(c.s.writer_calls == 0 and c.s.read_calls == 0, "busy seam no I/O " + claim)
		finish(c)

func session_boundary() -> void:
	var c: Dictionary = setup("session-boundary", "closed", false)
	for phase: String in ["", "w2", "w3"]:
		var r: Dictionary = c.s._write_fee_start_candidate_once(c.expected, c.path, c.s._profile, c.before, phase)
		check(not r.has("writer_return"), "raw rejects illegal phase/candidate " + phase)
	var changed: Dictionary = c.expected.duplicate(true)
	changed.player.gold += 1
	check(not c.s._write_fee_start_candidate_once(changed, c.path, c.s._profile, c.before, "w1").has("writer_return"), "raw rejects unrelated full-profile delta")
	for side: String in ["before", "candidate"]:
		for bad: Variant in [null, true, 1, []]:
			var old: Dictionary = c.before.duplicate(true)
			var after: Dictionary = c.expected.duplicate(true)
			if side == "before":old.profile_id = bad
			else:after.character_id = bad
			c.s._profile = old
			check(not c.s._write_fee_start_candidate_once(after, c.path, old, old.duplicate(true), "w1").has("writer_return"), "raw independently typed owner " + side)
	c.s._profile = c.before.duplicate(true)
	check(c.s.writer_calls == 0 and c.s.read_calls == 0, "raw boundary no I/O")
	disk_check(c, c.before, {}, false, "raw")
	finish(c)

func run() -> void:
	good("absent")
	good("closed")
	good("unknown")
	good("manual")
	good("backup")
	faults()
	rejects()
	handles_and_cas()
	session_boundary()
	physical_and_read_boundaries()
	print("FEE START JOURNAL SUMMARY checks=%d failures=%d retained_fixtures=%d" % [checks, failures, paths.size()])
	for path: String in paths:print("FEE START JOURNAL RETAINED " + path)
	quit(1 if failures else 0)
