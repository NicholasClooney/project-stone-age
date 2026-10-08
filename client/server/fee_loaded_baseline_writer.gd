extends RefCounted
## UNRUN B2a candidate. A real successful load may bind a private receipt;
## no production caller executes this baseline. No close, resume, or purchase.
const Exact = preload("res://server/fee_start_journal_writer.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
var _bound: Dictionary = {}
var _frame: Dictionary = {}
var _executing := false
var _close_continuation: Dictionary = {}

func bind_loaded(b, loaded_session, path: String, previous_receipt: Dictionary) -> RefCounted:
	var r: Dictionary = loaded_session._fee_loaded_receipt
	if is_same(r, previous_receipt) or not loaded_session._fee_loaded_receipt_current(r):return null
	if not is_same(b.session, loaded_session) or r.path != path:return null
	var token := RefCounted.new()
	_bound = {"token": token, "receipt": r, "session": loaded_session, "path": path,
		"path_at_bind": b.save_path, "timer": b.quest_loot, "timer_lifetime": b.quest_loot.lifetime,
		"profile_ref": loaded_session._profile, "profile": loaded_session._profile.duplicate(true),
		"cache": b.last_saved_payload, "serial": b.quest_save_serial, "account": b.account_name,
		"runner": b.quest_auto, "identity_ref": b.quest_auto.identity, "identity": b.quest_auto.identity.checkpoint(),
		"automation": b.automation, "auto_token": b.automation.start_lifetime,
		"stationary": b.stationary, "battle": b.battle, "original": b.original_quests}
	return token

func finish_load_publication(b, token: RefCounted) -> void:
	if token == null or _bound.is_empty() or not is_same(_bound.token, token):return
	if not _owner_current(b, false) or b.save_path != _bound.path_at_bind:_bound = {}

func _owner_current(b, require_path: bool = true) -> bool:
	if _bound.is_empty():return false
	var c: Dictionary = _bound
	if not is_same(b.session, c.session) or not c.session._fee_loaded_receipt_current(c.receipt):return false
	if not is_same(b.session._profile, c.profile_ref) or not Exact.same_value(b.session._profile, c.profile):return false
	if require_path and b.save_path != c.path:return false
	if b.last_saved_payload != c.cache or b.quest_save_serial != c.serial or b.account_name != c.account:return false
	if not is_same(b.quest_loot, c.timer) or not is_same(b.quest_loot.lifetime, c.timer_lifetime):return false
	if not is_same(b.quest_auto, c.runner) or not is_same(b.quest_auto.identity, c.identity_ref) or b.quest_auto.identity.checkpoint() != c.identity:return false
	if not is_same(b.automation, c.automation) or not is_same(b.automation.start_lifetime, c.auto_token):return false
	return is_same(b.stationary, c.stationary) and is_same(b.battle, c.battle) and is_same(b.original_quests, c.original)

func _idle(b) -> bool:
	if b.quest_auto.running or b.quest_auto.source_frame != null or b.battle_open or b.stationary.running:return false
	if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.automation.loot_scope.is_empty():return false
	if not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return false
	if not b.session._loot_failure_active.is_empty() or not b.session._loot_failure_write.is_empty() or b._loot_outer_resume_call != null or not b._loot_resume_envelope.is_empty():return false
	var t = b.quest_loot
	if t.consume_call != null or t.attempt_call != null or not t.attempt_frame.is_empty() or t.heartbeat_call != null:return false
	if t.anchor_ms >= 0 or not t.initial_failure.is_empty() or not t.followup.is_empty():return false
	if t.public_start_call != null or not t.initial_e2.is_empty() or not t.ready_frame.is_empty() or not t.open_obligation.is_empty() or not t.close_pending.is_empty() or not t.failed_initial_resume.is_empty() or not t.failed_followup_resume.is_empty():return false
	return b._quest_auto_stop_operation_call == null and b._quest_auto_stop_operation_owner == null \
		and b._fee_attempt_writer_call == null and b._fee_attempt_writer_snapshot.is_empty() and not b._fee_attempt_writer_executing \
		and b._fee_attempt_close_frame.is_empty() and not b._fee_attempt_close_executing \
		and b._fee_resume_sidecar_call == null and b._fee_resume_sidecar_frame.is_empty() and not b._fee_resume_sidecar_executing \
		and b._fee_start_journal_writer._frame.is_empty() and not b._fee_start_journal_writer._executing

func _current(b) -> bool:
	if _frame.is_empty() or not _owner_current(b) or not _idle(b):return false
	var f: Dictionary = _frame
	if not is_same(_bound, f.bound) or not is_same(b._fee_attempt_close_call, f.claim):return false
	if not is_same(b.session._pending, f.pending) or not is_same(b.session._loot_settlement, f.loot) or not is_same(b.original_quests.pending, f.page):return false
	return b._depth == f.depth and b._dispatch_boundary_depth == f.dispatch_depth and b._observer_depth == f.observer_depth \
		and b._flush_depth == f.flush_depth and b._dispatch_epoch == f.epoch

func _read_three(b) -> Array:
	var result: Array = []
	var c: Dictionary = _frame.bound
	for suffix: String in ["", ".bak", ".tmp"]:
		if not _current(b):return result
		result.append(c.session._read_fee_attempt_file(c.path + suffix, PackedByteArray()))
		if not _current(b):return result
	return result

func _decode(s, row: Dictionary) -> Dictionary:
	if not Exact.row_complete(row) or not row.exists:return {}
	var parsed: Variant = s._parse_save(row.bytes.get_string_from_utf8())
	if not parsed is Dictionary or Exact.owner(parsed).is_empty():return {}
	var boundary: Dictionary = s._canonical_fee_attempt_profile(parsed)
	if not Exact.strict_true(boundary.get("ok")) or not s._valid_profile(parsed):return {}
	var normalized: Dictionary = s._normalize_numbers(parsed)
	if boundary.present:normalized.quest_auto_fee_lifecycle = boundary.record.duplicate(true)
	return normalized

## Only an independently proven B1 transition may explain different run IDs.
func _compatible(source: Dictionary, other: Dictionary) -> bool:
	var a: Dictionary = Exact.owner(source)
	var z: Dictionary = Exact.owner(other)
	if a.is_empty() or z.is_empty() or a != z:return false
	var current: Variant = source.get("quest_auto_fee_lifecycle")
	var older: Variant = other.get("quest_auto_fee_lifecycle")
	if not Journal.valid(current) or not Journal.valid(older):return false
	if current.owner != a or older.owner != z:return false
	if current.current.run_id == older.current.run_id:return true
	return Exact.transition(other, source)

func _disk_allowed(b, rows: Array) -> bool:
	if rows.size() != 3 or not _current(b):return false
	if not Exact.row_complete(rows[0]) or not Exact.row_complete(rows[1]) or Exact.row_state(rows[2], false, PackedByteArray()) != "matches":return false
	var c: Dictionary = _bound
	var r: Dictionary = c.receipt
	# No capture from a caller-provided candidate: source was recorded by load_game.
	var source: Dictionary = _decode(c.session, {"ok": true, "exists": true, "bytes": r.source_bytes})
	if not _current(b) or source.is_empty():return false
	var primary: Dictionary = _decode(c.session, rows[0])
	if not _current(b):return false
	var backup: Dictionary = _decode(c.session, rows[1])
	if not _current(b):return false
	if r.loader_wrote:
		if Exact.row_state(rows[0], true, r.loader_profile_bytes) != "matches" or Exact.row_state(rows[1], true, r.source_bytes) != "matches":return false
	elif r.source == "primary":
		if Exact.row_state(rows[0], true, r.source_bytes) != "matches":return false
	else:
		if Exact.row_state(rows[1], true, r.source_bytes) != "matches" or not primary.is_empty():return false
	if rows[1].exists and backup.is_empty():return false # Bad/foreign backup is retained, never guessed away.
	if not backup.is_empty() and not _compatible(source, backup):return false
	_frame.primary_was_valid = not primary.is_empty()
	return _current(b)

func begin(b) -> Dictionary:
	if _executing or not _frame.is_empty() or not _owner_current(b) or not _idle(b) or b._fee_attempt_close_call != null:return {}
	_frame = {"call": RefCounted.new(), "claim": RefCounted.new(), "bound": _bound,
		"pending": b.session._pending, "loot": b.session._loot_settlement, "page": b.original_quests.pending,
		"depth": b._depth, "dispatch_depth": b._dispatch_boundary_depth, "observer_depth": b._observer_depth,
		"flush_depth": b._flush_depth, "epoch": b._dispatch_epoch}
	b._fee_attempt_close_call = _frame.claim
	var h: Dictionary = {"load_call": _frame.call}
	_executing = true
	var rows: Array = _read_three(b)
	var allowed: bool = _disk_allowed(b, rows)
	_executing = false
	if not allowed:
		end(b, h)
		return {}
	_frame.before = rows.duplicate(true)
	return h

func _handle(h: Variant) -> bool:
	return h is Dictionary and h.size() == 1 and h.has("load_call") and not _frame.is_empty() and is_same(h.load_call, _frame.call)

func end(b, h: Variant) -> void:
	if _executing or not _handle(h):return
	if is_same(b._fee_attempt_close_call, _frame.claim):b._fee_attempt_close_call = null
	_frame = {}

func _finish(b, h: Dictionary, result: Dictionary) -> Dictionary:
	_executing = false
	end(b, h)
	return result

func _same_rows(rows: Array, prior: Array) -> bool:
	if rows.size() != 3:return false
	for i: int in range(3):
		var exists: bool = prior[i].exists
		if Exact.row_state(rows[i], exists, prior[i].bytes if exists else PackedByteArray()) != "matches":return false
	return true

func persist(b, h: Variant) -> Dictionary:
	if not _handle(h):return {"ok": false, "stage": "invalid_handle"}
	if _executing:return {"ok": false, "stage": "already_executing"}
	_executing = true
	if not _current(b):return _finish(b, h, {"ok": false, "stage": "owner_or_claim_changed"})
	var rows: Array = _read_three(b)
	if not _current(b) or not _same_rows(rows, _frame.before):return _finish(b, h, {"ok": false, "stage": "disk_or_owner_changed"})
	var c: Dictionary = _bound
	var r: Dictionary = c.receipt
	var serial: int = c.serial
	if Exact.row_state(rows[0], true, r.loaded_bytes) == "matches":
		r.used = true # One receipt, no file write, no artificial save serial.
		_frame.verified_rows = rows.duplicate(true)
		_mint_close_continuation(b)
		return _finish(b, h, {"ok": true, "stage": "already_matches", "writer_return": "not_called", "primary": "matches", "backup": "unchanged", "temporary": "matches", "installed": false, "serial_before": serial, "serial_after": serial})
	# Session consumes the receipt before raw I/O; nested commit/end cannot reuse it.
	var result: Dictionary = c.session._write_fee_loaded_baseline_once(r, c.path, c.profile_ref, c.profile, self, b)
	var p: String = Exact.row_state(result.get("primary"), true, r.loaded_bytes)
	var expected_backup: Dictionary = rows[0] if _frame.primary_was_valid else rows[1]
	var k: String = Exact.row_state(result.get("backup"), expected_backup.exists, expected_backup.bytes if expected_backup.exists else PackedByteArray())
	var t: String = Exact.row_state(result.get("temporary"), false, PackedByteArray())
	# Consumed receipt is still the same object; only this continuation may check it.
	var current: bool = _after_write_current(b, r)
	var installed: bool = false
	if p == "matches" and current:
		b.last_saved_payload = JSON.stringify(c.profile)
		b.quest_save_serial = serial + 1
		installed = true # Profile was the exact load product already; never swap a successor.
	var succeeded: bool = installed and k == "matches" and t == "matches" and Exact.strict_true(result.get("writer_return"))
	if succeeded:
		_frame.verified_rows = [result.primary.duplicate(true), result.backup.duplicate(true), result.temporary.duplicate(true)]
		_mint_close_continuation(b)
	return _finish(b, h, {"ok": succeeded, "stage": "baseline_verified" if succeeded else "partial_or_unknown",
		"writer_return": Exact.writer_state(result.get("writer_return")), "primary": p, "backup": k, "temporary": t,
		"installed": installed, "serial_before": serial, "serial_after": b.quest_save_serial})

func authorizes_session_write(b, r: Dictionary) -> bool:
	return _executing and _current(b) and is_same(_bound.receipt, r) and is_same(b._fee_loaded_baseline_writer, self)

func _after_write_current(b, r: Dictionary) -> bool:
	# Never temporarily un-consume r to pass a guard: a callback could see it.
	if _frame.is_empty() or not is_same(_bound, _frame.bound) or not is_same(b.session, _bound.session):return false
	if not is_same(b.session._fee_loaded_receipt, r) or not Exact.strict_true(r.get("used")):return false
	return _owner_after_consumption(b) and _idle(b) and is_same(b._fee_attempt_close_call, _frame.claim) \
		and is_same(b.session._pending, _frame.pending) and is_same(b.session._loot_settlement, _frame.loot) and is_same(b.original_quests.pending, _frame.page) \
		and b._depth == _frame.depth and b._dispatch_boundary_depth == _frame.dispatch_depth and b._observer_depth == _frame.observer_depth and b._flush_depth == _frame.flush_depth and b._dispatch_epoch == _frame.epoch

func _owner_after_consumption(b) -> bool:
	var c: Dictionary = _bound
	return b.save_path == c.path and b.account_name == c.account and b.last_saved_payload == c.cache and b.quest_save_serial == c.serial \
		and is_same(b.session._profile, c.profile_ref) and Exact.same_value(b.session._profile, c.profile) \
		and is_same(b.quest_loot, c.timer) and is_same(b.quest_loot.lifetime, c.timer_lifetime) \
		and is_same(b.quest_auto, c.runner) and is_same(b.quest_auto.identity, c.identity_ref) and b.quest_auto.identity.checkpoint() == c.identity \
		and is_same(b.automation, c.automation) and is_same(b.automation.start_lifetime, c.auto_token) \
		and is_same(b.stationary, c.stationary) and is_same(b.battle, c.battle) and is_same(b.original_quests, c.original)

## Memory-only revocation at every Backend load entry, including failed loads.
## Never steals an executing frame or another writer's claim.
func revoke_loaded_authority() -> void:
	_bound = {}
	_close_continuation = {}

## Only persist's two internally verified success branches reach this method.
## Diagnostics are not an input and the envelope never leaves the private writer pair.
func _mint_close_continuation(b) -> void:
	if not _executing or _frame.is_empty() or not _frame.has("verified_rows"):return
	if not is_same(_bound, _frame.bound) or not is_same(b._fee_loaded_baseline_writer, self):return
	_close_continuation = {"token": RefCounted.new(), "state": "ready", "bound": _bound,
		"receipt_token": _bound.receipt.token, "receipt_profile_ref": _bound.receipt.profile_ref, "receipt_value": _receipt_value(_bound.receipt),
		"profile_ref": b.session._profile, "profile": b.session._profile.duplicate(true),
		"cache": b.last_saved_payload, "serial": b.quest_save_serial,
		"rows": _frame.verified_rows.duplicate(true), "pending": _frame.pending, "loot": _frame.loot,
		"page": _frame.page, "depth": _frame.depth, "dispatch_depth": _frame.dispatch_depth,
		"observer_depth": _frame.observer_depth, "flush_depth": _frame.flush_depth, "epoch": _frame.epoch}

func _receipt_value(r: Dictionary) -> Dictionary:
	var value: Dictionary = r.duplicate(false)
	value.erase("token")
	value.erase("profile_ref")
	return value.duplicate(true)

func _continuation_owner_current(b, c: Dictionary) -> bool:
	if c.is_empty() or not is_same(_bound, c.bound) or _bound.is_empty():return false
	var a: Dictionary = c.bound
	if not is_same(b.session, a.session) or not is_same(b.session._fee_loaded_receipt, a.receipt) or not Exact.strict_true(a.receipt.get("used")):return false
	if not is_same(a.receipt.get("token"), c.receipt_token) or not is_same(a.receipt.get("profile_ref"), c.receipt_profile_ref) or not Exact.same_value(_receipt_value(a.receipt), c.receipt_value):return false
	return b.save_path == a.path and b.account_name == a.account \
		and is_same(b.quest_loot, a.timer) and is_same(b.quest_loot.lifetime, a.timer_lifetime) \
		and is_same(b.quest_auto, a.runner) and is_same(b.quest_auto.identity, a.identity_ref) and b.quest_auto.identity.checkpoint() == a.identity \
		and is_same(b.automation, a.automation) and is_same(b.automation.start_lifetime, a.auto_token) \
		and is_same(b.stationary, a.stationary) and is_same(b.battle, a.battle) and is_same(b.original_quests, a.original) \
		and is_same(b.session._pending, c.pending) and is_same(b.session._loot_settlement, c.loot) and is_same(b.original_quests.pending, c.page) \
		and b._depth == c.depth and b._dispatch_boundary_depth == c.dispatch_depth and b._observer_depth == c.observer_depth \
		and b._flush_depth == c.flush_depth and b._dispatch_epoch == c.epoch

func take_close_continuation(b, consumer, claim: RefCounted) -> Dictionary:
	if _close_continuation.is_empty() or _close_continuation.state != "ready":return {}
	if not is_same(consumer, b._fee_recovered_close_writer) or claim == null or not is_same(b._fee_attempt_close_call, claim):return {}
	if not consumer.owns_claim(claim):return {}
	var c: Dictionary = _close_continuation
	if _executing or not _frame.is_empty() or not _continuation_owner_current(b, c) or not _idle(b) \
		or not is_same(b.session._profile, c.profile_ref) or not Exact.same_value(b.session._profile, c.profile) \
		or b.last_saved_payload != c.cache or b.quest_save_serial != c.serial:
		_close_continuation = {}
		return {}
	c.state = "taken"
	c.consumer = weakref(consumer)
	c.claim = claim
	return c

## Profile/cache/serial CAS belongs to the consumer after take: W1 changes them.
func close_continuation_current(b, consumer, c: Dictionary) -> bool:
	return not c.is_empty() and is_same(c, _close_continuation) and c.state == "taken" \
		and is_same(consumer, b._fee_recovered_close_writer) and is_same(c.consumer.get_ref(), consumer) \
		and is_same(b._fee_attempt_close_call, c.claim) and _continuation_owner_current(b, c)

func end_close_continuation(consumer, c: Dictionary) -> void:
	if c.is_empty() or not is_same(c, _close_continuation) or c.state != "taken":return
	if is_same(c.consumer.get_ref(), consumer):_close_continuation = {}

func discard_ready_continuation() -> void:
	if not _close_continuation.is_empty() and _close_continuation.state == "ready":_close_continuation = {}
