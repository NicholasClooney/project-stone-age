extends RefCounted
## Private journal-only seam. No command caller, source admission, purchase,
## sidecar, running-state installation or fresh-Start capability is provided.
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
var _frame: Dictionary = {}
var _executing := false

static func owner(profile: Variant) -> Dictionary:
	if not profile is Dictionary:return {}
	var p: Variant = profile.get("profile_id")
	var c: Variant = profile.get("character_id")
	if not Journal.nonempty(p) or not Journal.nonempty(c):return {}
	return {"profile_id": p, "character_id": c}

## Dictionary equality alone can equate integral floats with integers. The
## journal seam must not alter unrelated profile field types either.
static func same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):return false
	if left is Dictionary:
		if left.size() != right.size():return false
		for key: Variant in left:
			if not right.has(key) or not same_value(left[key], right[key]):return false
		return true
	if left is Array:
		if left.size() != right.size():return false
		for i: int in range(left.size()):
			if not same_value(left[i], right[i]):return false
		return true
	return left == right

## Validate each side independently before comparing fields. Full-profile
## validity is checked by Session after this narrow typed journal boundary.
static func transition(before: Variant, candidate: Variant) -> bool:
	var old_owner: Dictionary = owner(before)
	var new_owner: Dictionary = owner(candidate)
	if old_owner.is_empty() or new_owner.is_empty() or old_owner != new_owner:return false
	var next: Variant = candidate.get("quest_auto_fee_lifecycle")
	if not Journal.valid(next) or next.owner != new_owner:return false
	if next.current.run_status != "active" or next.current.purchase.state not in ["none", "manual_only"]:return false
	var slot: bool = next.current.purchase.state == "none"
	var expected_journal: Dictionary
	if before.has("quest_auto_fee_lifecycle"):
		var previous: Variant = before.quest_auto_fee_lifecycle
		if not Journal.valid(previous) or previous.owner != old_owner:return false
		var replaced: Dictionary = Journal.replace_closed_for_start(previous, old_owner.profile_id, old_owner.character_id, next.current.run_id, slot)
		if not replaced.get("ok", false):return false
		expected_journal = replaced.candidate
	else:
		expected_journal = Journal.empty_record(old_owner.profile_id, old_owner.character_id, next.current.run_id, slot)
	if expected_journal != next:return false
	var expected: Dictionary = before.duplicate(true)
	expected["quest_auto_fee_lifecycle"] = expected_journal
	return same_value(candidate, expected)

static func row_state(row: Variant, exists: bool, bytes: PackedByteArray) -> String:
	if not row is Dictionary:return "unknown"
	var ok_value: Variant = row.get("ok")
	var exists_value: Variant = row.get("exists")
	if not ok_value is bool or not exists_value is bool:return "unknown"
	var read_ok: bool = ok_value
	var found: bool = exists_value
	if not read_ok:return "unknown"
	if found != exists:return "differs"
	if not found:return "matches"
	var raw: Variant = row.get("bytes")
	if not raw is PackedByteArray:return "unknown"
	return "matches" if raw == bytes else "differs"

static func row_complete(row: Variant) -> bool:
	if not row is Dictionary:return false
	var ok_value: Variant = row.get("ok")
	var exists_value: Variant = row.get("exists")
	if not ok_value is bool or not exists_value is bool:return false
	var read_ok: bool = ok_value
	var found: bool = exists_value
	return read_ok and (not found or row.get("bytes") is PackedByteArray)

static func strict_true(value: Variant) -> bool:
	if not value is bool:return false
	var typed: bool = value
	return typed

static func writer_state(value: Variant) -> String:
	if not value is bool:return "unknown"
	var typed: bool = value
	return "true" if typed else "false"

func _idle(b) -> bool:
	return b._quest_auto_stop_operation_call == null \
		and b._fee_attempt_close_call == null and b._fee_attempt_close_frame.is_empty() and not b._fee_attempt_close_executing \
		and b._fee_resume_sidecar_call == null and b._fee_resume_sidecar_frame.is_empty() and not b._fee_resume_sidecar_executing \
		and b._fee_attempt_writer_snapshot.is_empty() and not b._fee_attempt_writer_executing

func _capture(b, candidate: Dictionary) -> Dictionary:
	# Reference-bearing dictionaries must never be deep-copied.
	return {
		"session": b.session, "profile_ref": b.session._profile, "profile": b.session._profile.duplicate(true),
		"pending_ref": b.session._pending, "loot_ref": b.session._loot_settlement,
		"quest_auto": b.quest_auto, "identity_ref": b.quest_auto.identity, "identity": b.quest_auto.identity.checkpoint(),
		"auto_client": b.quest_auto.client, "auto_connection": b.quest_auto.connection, "auto_internal": b.quest_auto.internal,
		"auto_detached": b.quest_auto.detached, "auto_phase": b.quest_auto.phase,
		"automation": b.automation, "auto_token": b.automation.start_lifetime, "compact": b.automation.compact_active,
		"stationary": b.stationary, "original_quests": b.original_quests, "page_ref": b.original_quests.pending,
		"battle": b.battle, "path": b.save_path, "account_name": b.account_name,
		"cache": b.last_saved_payload, "serial": b.quest_save_serial, "serial_before": b.quest_save_serial,
		"depth": b._depth, "dispatch_boundary_depth": b._dispatch_boundary_depth,
		"observer_depth": b._observer_depth, "flush_depth": b._flush_depth, "dispatch_epoch": b._dispatch_epoch,
		"candidate": candidate.duplicate(true), "candidate_bytes": JSON.stringify(candidate).to_utf8_buffer(),
		"w1_calls": 0, "w2_calls": 0, "w1_writer_return": "unknown", "w2_writer_return": "unknown", "installed": false
	}

func _current(b) -> bool:
	if _frame.is_empty() or not _idle(b):return false
	var f: Dictionary = _frame
	if not is_same(b._fee_attempt_writer_call, f.claim):return false
	if not is_same(b.session, f.session) or not is_same(b.session._profile, f.profile_ref) or not same_value(b.session._profile, f.profile):return false
	if JSON.stringify(b.session._profile) != f.cache:return false
	if not is_same(b.session._pending, f.pending_ref) or not b.session._pending.is_empty():return false
	if not is_same(b.session._loot_settlement, f.loot_ref) or not b.session._loot_settlement.is_empty():return false
	if not is_same(b.quest_auto, f.quest_auto) or not is_same(b.quest_auto.identity, f.identity_ref):return false
	if b.quest_auto.running or b.quest_auto.source_frame != null or b.quest_auto.identity.checkpoint() != f.identity:return false
	if b.quest_auto.client != f.auto_client or b.quest_auto.connection != f.auto_connection or b.quest_auto.internal != f.auto_internal or b.quest_auto.detached != f.auto_detached or b.quest_auto.phase != f.auto_phase:return false
	if not is_same(b.automation, f.automation) or not is_same(b.automation.start_lifetime, f.auto_token) or b.automation.compact_active != f.compact:return false
	if b.automation.running or b.automation.hunt_running or b.automation.flow_active():return false
	if not is_same(b.stationary, f.stationary) or b.stationary.running:return false
	if not is_same(b.original_quests, f.original_quests) or not is_same(b.original_quests.pending, f.page_ref) or not b.original_quests.pending.is_empty():return false
	if not is_same(b.battle, f.battle) or b.battle_open:return false
	if b.save_path != f.path or b.account_name != f.account_name or b.last_saved_payload != f.cache or b.quest_save_serial != f.serial:return false
	return b._depth == f.depth and b._dispatch_boundary_depth == f.dispatch_boundary_depth and b._observer_depth == f.observer_depth and b._flush_depth == f.flush_depth and b._dispatch_epoch == f.dispatch_epoch

func begin(b, candidate: Variant) -> Dictionary:
	if not _frame.is_empty() or _executing or not _idle(b) or b._fee_attempt_writer_call != null:return {}
	if b.save_path.is_empty() or not transition(b.session._profile, candidate):return {}
	if not b.session._valid_profile(b.session._profile) or not b.session._valid_profile(candidate):return {}
	if JSON.stringify(b.session._profile) != b.last_saved_payload:return {}
	_frame = _capture(b, candidate)
	_frame.call = RefCounted.new()
	_frame.claim = RefCounted.new() # Separate reservation: old seam handles cannot consume this Start handle.
	b._fee_attempt_writer_call = _frame.claim
	var handle: Dictionary = {"start_call": _frame.call}
	if not _current(b):
		end(b, handle)
		return {}
	var rows: Array = _read_three(b)
	if not _current(b) or rows.size() != 3:
		end(b, handle)
		return {}
	if row_state(rows[0], true, _frame.cache.to_utf8_buffer()) != "matches" or not row_complete(rows[1]) or row_state(rows[2], false, PackedByteArray()) != "matches":
		end(b, handle)
		return {}
	_frame.before_rows = rows.duplicate(true)
	return handle

func _valid_handle(handle: Variant) -> bool:
	return handle is Dictionary and handle.size() == 1 and handle.has("start_call") and not _frame.is_empty() and is_same(handle.start_call, _frame.call)

func end(b, handle: Variant) -> void:
	if not _valid_handle(handle) or _executing:return
	if is_same(b._fee_attempt_writer_call, _frame.claim):b._fee_attempt_writer_call = null
	_frame = {}

func _read_three(b) -> Array:
	var rows: Array = []
	var f: Dictionary = _frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if not _current(b):return rows
		rows.append(f.session._read_fee_attempt_file(f.path + suffix, f.candidate_bytes))
		if not _current(b):return rows
	return rows

func _same_rows(rows: Array, expected: Array) -> bool:
	if rows.size() != 3 or expected.size() != 3:return false
	for i: int in range(3):
		if not row_complete(expected[i]):return false
		var found: bool = expected[i].exists
		var bytes: PackedByteArray = expected[i].bytes if found else PackedByteArray()
		if row_state(rows[i], found, bytes) != "matches":return false
	return true

func _result(b, stage: String, rows: Array, ok: bool = false) -> Dictionary:
	var states: Array[String] = ["unknown", "unknown", "unknown"]
	for i: int in range(mini(rows.size(), 3)):
		states[i] = row_state(rows[i], i != 2, _frame.candidate_bytes if i != 2 else PackedByteArray())
	return {"ok": ok, "stage": stage, "primary": states[0], "backup": states[1], "temporary": states[2],
		"pair_verified": states[0] == "matches" and states[1] == "matches" and states[2] == "matches",
		"installed": _frame.installed, "state_current": _current(b),
		"serial_before": _frame.serial_before, "serial_after": b.quest_save_serial,
		"w1_calls": _frame.w1_calls, "w2_calls": _frame.w2_calls,
		"w1_writer_return": _frame.w1_writer_return, "w2_writer_return": _frame.w2_writer_return}

func _finish(b, handle: Dictionary, result: Dictionary) -> Dictionary:
	_executing = false
	end(b, handle)
	return result

func persist(b, handle: Variant) -> Dictionary:
	if not _valid_handle(handle):return {"ok": false, "stage": "invalid_handle"}
	if _executing:return {"ok": false, "stage": "already_executing"}
	_executing = true
	if not _current(b):return _finish(b, handle, _result(b, "owner_or_claim_before_w1", []))
	var pre: Array = _read_three(b)
	if not _current(b) or not _same_rows(pre, _frame.before_rows):return _finish(b, handle, _result(b, "preflight_changed", pre))
	var f: Dictionary = _frame
	var first: Dictionary = f.session._write_fee_start_candidate_once(f.candidate, f.path, f.profile_ref, f.profile, "w1")
	f.w1_calls = 1
	f.w1_writer_return = writer_state(first.get("writer_return"))
	var rows1: Array = [first.get("primary"), first.get("backup"), first.get("temporary")]
	if row_state(rows1[0], true, f.candidate_bytes) != "matches":return _finish(b, handle, _result(b, "w1_not_verified", rows1))
	if not _current(b):return _finish(b, handle, _result(b, "w1_landed_owner_changed", rows1))
	# The actual candidate survives a false wrapper or a later W2 failure.
	b.session._profile = f.candidate.duplicate(true)
	b.last_saved_payload = JSON.stringify(f.candidate)
	b.quest_save_serial = f.serial_before + 1
	f.profile_ref = b.session._profile
	f.profile = b.session._profile.duplicate(true)
	f.cache = b.last_saved_payload
	f.serial = b.quest_save_serial
	f.installed = true
	if not strict_true(first.get("writer_return")) or row_state(rows1[1], true, f.before_rows[0].bytes) != "matches" or row_state(rows1[2], false, PackedByteArray()) != "matches":return _finish(b, handle, _result(b, "w1_partial_or_wrapper_false", rows1))
	var pre2: Array = _read_three(b)
	if not _current(b) or not _same_rows(pre2, rows1):return _finish(b, handle, _result(b, "before_w2_changed", pre2))
	var second: Dictionary = f.session._write_fee_start_candidate_once(f.candidate, f.path, f.profile_ref, f.profile, "w2")
	f.w2_calls = 1
	f.w2_writer_return = writer_state(second.get("writer_return"))
	var rows2: Array = [second.get("primary"), second.get("backup"), second.get("temporary")]
	var pair: bool = row_state(rows2[0], true, f.candidate_bytes) == "matches" and row_state(rows2[1], true, f.candidate_bytes) == "matches" and row_state(rows2[2], false, PackedByteArray()) == "matches"
	var success: bool = pair and strict_true(second.get("writer_return")) and _current(b)
	return _finish(b, handle, _result(b, "pair_verified" if success else "w2_partial_or_owner_changed", rows2, success))
