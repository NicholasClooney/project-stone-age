extends RefCounted
## Private, single-use loaded-baseline continuation. No execution caller.
## JSON profile boundary; neither sidecar execution nor cross-file atomicity.
const Exact = preload("res://server/fee_start_journal_writer.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
var _frame: Dictionary = {}
var _executing := false

func owns_claim(claim: RefCounted) -> bool:
	return not _frame.is_empty() and is_same(_frame.claim, claim)

func _handle(h: Variant) -> bool:
	return h is Dictionary and h.size() == 1 and h.has("recovered_close_call") and not _frame.is_empty() and is_same(h.recovered_close_call, _frame.call)

func _current(b) -> bool:
	if _frame.is_empty():return false
	var f: Dictionary = _frame
	if not f.has("continuation") or not b._fee_loaded_baseline_writer.close_continuation_current(b, self, f.continuation):return false
	return Exact.same_value(f.candidate, f.candidate_value) and b._fee_loaded_baseline_writer._idle(b) and is_same(b.session._profile, f.profile_ref) \
		and Exact.same_value(b.session._profile, f.profile) and b.last_saved_payload == f.cache and b.quest_save_serial == f.serial

func _read_three(b) -> Array:
	var rows: Array = []
	for suffix: String in ["", ".bak", ".tmp"]:
		if not _current(b):return rows
		rows.append(_frame.continuation.bound.session._read_fee_attempt_file(_frame.path + suffix, PackedByteArray()))
		if not _current(b):return rows
	return rows

func begin(b) -> Dictionary:
	if _executing or not _frame.is_empty():return {}
	if b._fee_attempt_close_call != null or not b._fee_loaded_baseline_writer._idle(b):
		b._fee_loaded_baseline_writer.discard_ready_continuation()
		return {}
	_frame = {"call": RefCounted.new(), "claim": RefCounted.new()}
	b._fee_attempt_close_call = _frame.claim
	var h: Dictionary = {"recovered_close_call": _frame.call}
	var c: Dictionary = b._fee_loaded_baseline_writer.take_close_continuation(b, self, _frame.claim)
	if c.is_empty():
		end(b, h)
		return {}
	_frame.merge({"continuation": c, "profile_ref": c.profile_ref, "profile": c.profile.duplicate(true),
		"cache": c.cache, "serial": c.serial, "serial_before": c.serial, "path": c.bound.path, "installed": false})
	var before: Dictionary = _frame.profile
	var owner: Dictionary = Exact.owner(before)
	var record: Variant = before.get("quest_auto_fee_lifecycle")
	if owner.is_empty() or not Journal.valid(record) or not Exact.same_value(owner, record.owner):
		end(b, h)
		return {}
	var transition: Dictionary = Journal.close_run(record, record.current.run_id)
	if not Exact.strict_true(transition.get("ok")) or not Journal.valid(transition.get("candidate")):
		end(b, h)
		return {}
	# Session's unchanged w2 admits only an idempotent closed record.
	var repairing: bool = record.current.run_status == "closed"
	if repairing and not Exact.same_value(record, transition.candidate):
		end(b, h)
		return {}
	var candidate: Dictionary = before.duplicate(true)
	candidate.quest_auto_fee_lifecycle = transition.candidate.duplicate(true)
	_frame.merge({"candidate": candidate, "candidate_value": candidate.duplicate(true), "bytes": JSON.stringify(candidate).to_utf8_buffer(),
		"run_id": record.current.run_id, "repairing": repairing})
	_executing = true
	var rows: Array = _read_three(b)
	var accepted: bool = _current(b) and b._fee_loaded_baseline_writer._same_rows(rows, c.rows)
	_executing = false
	if not accepted:
		end(b, h)
		return {}
	_frame.before = rows.duplicate(true)
	return h

func end(b, h: Variant) -> void:
	if _executing or not _handle(h):return
	if _frame.has("continuation"):b._fee_loaded_baseline_writer.end_close_continuation(self, _frame.continuation)
	if is_same(b._fee_attempt_close_call, _frame.claim):b._fee_attempt_close_call = null
	_frame = {}

func _result(b, stage: String, rows: Array, first: Variant, second: Variant, ok: bool = false) -> Dictionary:
	var p := "unknown"
	var k := "unknown"
	var t := "unknown"
	if rows.size() == 3:
		p = Exact.row_state(rows[0], true, _frame.bytes)
		k = Exact.row_state(rows[1], true, _frame.bytes)
		t = Exact.row_state(rows[2], false, PackedByteArray())
	return {"ok": ok, "stage": stage, "writer_first": Exact.writer_state(first), "writer_second": Exact.writer_state(second),
		"first_journal_phase": "w2" if _frame.repairing else "w1", "second_journal_phase": "w2",
		"primary_closed": p, "backup_closed": k, "temporary": t, "installed": _frame.installed,
		"serial_before": _frame.serial_before, "serial_after": b.quest_save_serial, "owner_current": _current(b), "sidecar": "not_evaluated"}

func _finish(b, h: Dictionary, result: Dictionary) -> Dictionary:
	_executing = false
	end(b, h)
	return result

func _rows(raw: Dictionary) -> Array:
	return [raw.get("primary"), raw.get("backup"), raw.get("temporary")]

func persist(b, h: Variant) -> Dictionary:
	if not _handle(h):return {"ok": false, "stage": "invalid_handle"}
	if _executing:return {"ok": false, "stage": "already_executing"}
	_executing = true
	var rows: Array = _read_three(b)
	if not _current(b) or not b._fee_loaded_baseline_writer._same_rows(rows, _frame.before):
		return _finish(b, h, _result(b, "disk_or_owner_before_w1", rows, null, null))
	var f: Dictionary = _frame
	var s = f.continuation.bound.session
	var first: Dictionary = s._write_fee_close_candidate_once(f.candidate, f.path, f.profile_ref, f.profile, f.run_id, "w2" if f.repairing else "w1")
	var w1: Variant = first.get("writer_return")
	rows = _rows(first)
	if Exact.row_state(rows[0], true, f.bytes) != "matches" or not _current(b):
		return _finish(b, h, _result(b, "w1_uninstalled", rows, w1, null))
	# Physical primary proof precedes installation even when the raw wrapper is false.
	s._profile = f.candidate.duplicate(true)
	b.last_saved_payload = JSON.stringify(s._profile)
	b.quest_save_serial = f.serial_before + 1
	f.profile_ref = s._profile
	f.profile = s._profile.duplicate(true)
	f.cache = b.last_saved_payload
	f.serial = b.quest_save_serial
	f.installed = true
	var expected: Array = [{"ok": true, "exists": true, "bytes": f.bytes}, f.before[0], {"ok": true, "exists": false, "bytes": PackedByteArray()}]
	if not Exact.strict_true(w1) or not b._fee_loaded_baseline_writer._same_rows(rows, expected) or not _current(b):
		return _finish(b, h, _result(b, "w1_partial_or_false", rows, w1, null))
	rows = _read_three(b)
	if not _current(b) or not b._fee_loaded_baseline_writer._same_rows(rows, expected):
		return _finish(b, h, _result(b, "w2_preflight_changed", rows, w1, null))
	var second: Dictionary = s._write_fee_close_candidate_once(f.candidate, f.path, f.profile_ref, f.profile, f.run_id, "w2")
	rows = _rows(second)
	var w2: Variant = second.get("writer_return")
	var succeeded: bool = _current(b) and Exact.strict_true(w2) and Exact.row_state(rows[0], true, f.bytes) == "matches" \
		and Exact.row_state(rows[1], true, f.bytes) == "matches" and Exact.row_state(rows[2], false, PackedByteArray()) == "matches"
	return _finish(b, h, _result(b, "pair_verified" if succeeded else "w2_partial_or_unknown", rows, w1, w2, succeeded))
