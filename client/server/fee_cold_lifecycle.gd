extends RefCounted
## Dormant cold-load orchestration only. No Start, purchase, logout or switch.
const Exact = preload("res://server/fee_start_journal_writer.gd")
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
var _scope: Dictionary = {}
var _frame: Dictionary = {}
var _diagnostic: Dictionary = {}

func has_call() -> bool:return not _frame.is_empty()
func current_call() -> RefCounted:return _frame.get("call")
func owns_call(call: RefCounted) -> bool:return not _frame.is_empty() and is_same(call, _frame.call)
func revoke_call() -> void:_frame = {} # Existing disk protection is not a receipt.

func _run(b) -> String:
	var value: Variant = b.session._profile.get("quest_auto_fee_lifecycle")
	return value.current.run_id if Journal.valid(value) else ""

func _capture(b) -> Dictionary:
	return {"session": b.session, "path": b.save_path, "resume_path": b._resume_file(),
		"account": b.account_name, "owner": Exact.owner(b.session._profile), "run": _run(b),
		"has_fee": b.session._profile.has("quest_auto_fee_lifecycle")}

func _matches(b, scope: Dictionary) -> bool:
	if scope.is_empty() or not is_same(b.session, scope.session):return false
	return b.save_path == scope.path and b._resume_file() == scope.resume_path and b.account_name == scope.account \
		and Exact.same_value(Exact.owner(b.session._profile), scope.owner) and _run(b) == scope.run \
		and b.session._profile.has("quest_auto_fee_lifecycle") == scope.has_fee

func handles_current(b) -> bool:return _matches(b, _scope)
func protects_resume(b) -> bool:return handles_current(b) and _scope.protect
func diagnostic(b) -> Dictionary:
	return _diagnostic.duplicate(true) if handles_current(b) else {"profile": "unknown", "sidecar": "unknown", "pending": true}

func _read_state(b, scope: Dictionary) -> Dictionary:
	if not _matches(b, scope):return {"kind": "stale"}
	var row: Dictionary = b._fee_resume_io_read(scope.resume_path)
	if not _matches(b, scope):return {"kind": "stale"}
	if not Exact.row_complete(row):return {"kind": "unknown"}
	if not row.exists:return {"kind": "absent", "state": {}, "bytes": PackedByteArray()}
	var parser := JSON.new()
	if parser.parse(row.bytes.get_string_from_utf8()) != OK:return {"kind": "invalid"}
	var budget: Array = [0]
	if not b._fee_native_sidecar_dictionary_safe(parser.data, 0, budget):return {"kind": "invalid"}
	var state: Variant = JSON.to_native(parser.data, false)
	if not state is Dictionary:return {"kind": "invalid"}
	return {"kind": "present", "state": state, "bytes": row.bytes}

func _call_current(b) -> bool:
	return not _frame.is_empty() and is_same(_scope, _frame.scope) and handles_current(b)

## Same reverse exclusion as the baseline writer, allowing only this retire claim.
func _idle_for_retire(b) -> bool:
	if b.quest_auto.running or b.quest_auto.source_frame != null or b.battle_open or b.stationary.running:return false
	if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.automation.loot_scope.is_empty():return false
	if not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return false
	if not b.session._loot_failure_active.is_empty() or not b.session._loot_failure_write.is_empty() or b._loot_outer_resume_call != null or not b._loot_resume_envelope.is_empty():return false
	var t = b.quest_loot
	if t.consume_call != null or t.attempt_call != null or not t.attempt_frame.is_empty() or t.heartbeat_call != null:return false
	if t.anchor_ms >= 0 or not t.initial_failure.is_empty() or not t.followup.is_empty():return false
	if t.public_start_call != null or not t.initial_e2.is_empty() or not t.ready_frame.is_empty() or not t.open_obligation.is_empty() or not t.close_pending.is_empty() or not t.failed_initial_resume.is_empty() or not t.failed_followup_resume.is_empty():return false
	if b._quest_auto_stop_operation_call != null or b._quest_auto_stop_operation_owner != null:return false
	if b._fee_attempt_writer_call != null or not b._fee_attempt_writer_snapshot.is_empty() or b._fee_attempt_writer_executing:return false
	if b._fee_attempt_close_call != null or not b._fee_attempt_close_frame.is_empty() or b._fee_attempt_close_executing:return false
	if not b._fee_start_journal_writer._frame.is_empty() or b._fee_start_journal_writer._executing:return false
	if b._fee_resume_sidecar_call == null:return b._fee_resume_sidecar_frame.is_empty() and not b._fee_resume_sidecar_executing
	return _frame.has("sidecar_call") and is_same(b._fee_resume_sidecar_call, _frame.sidecar_call)

## Called by every existing exact-retire snapshot CAS only during this cold call.
func retire_guard_current(b) -> bool:
	if _frame.has("departure"):return _departure_retire_current(b)
	return _call_current(b) and _frame.has("retire") and b._fee_recovered_close_writer.retire_current(b, self, _frame.retire) and _idle_for_retire(b)

## Existing exact writer invokes this only at its internal verified success exit.
func mark_retired_from_writer(b, frame: Dictionary) -> void:
	if not retire_guard_current(b) or not b._fee_resume_sidecar_executing:return
	if not is_same(frame, b._fee_resume_sidecar_frame) or not is_same(frame.get("call"), _frame.get("sidecar_call")):return
	_frame.retire_verified = true
	_frame.residual = not frame.candidate.is_empty()

func _finish(b, call: RefCounted) -> void:
	if not owns_call(call):return
	if _frame.has("retire"):b._fee_recovered_close_writer.end_retire(self, _frame.retire)
	_frame = {}

## True only routes away from legacy save/load_resume; it is not write authority.
func open(b) -> bool:
	if not b._fee_cold_lifecycle_enabled():return false
	if has_call():return true
	var scope: Dictionary = _capture(b)
	var initial: Dictionary = _read_state(b, scope)
	var fee_marker: bool = initial.get("state", {}).has("fee_attempt_binding")
	if not scope.has_fee and not fee_marker:return false # Legacy and loot-only keep original behavior.
	_scope = scope
	_scope.protect = true
	var facts: Dictionary = {"profile": "unknown", "sidecar": "not_evaluated", "pending": true, "anchor": "existing_journal_not_failure_log"}
	_diagnostic = facts
	if not _matches(b, scope):return true
	var call := RefCounted.new()
	_frame = {"call": call, "scope": _scope}
	if not scope.has_fee:
		facts.sidecar = "fee_marker_without_profile_preserved"
		_finish(b, call)
		return true
	var baseline: Dictionary = b._begin_fee_loaded_baseline()
	if baseline.is_empty():
		facts.profile = "baseline_unavailable"
		_finish(b, call)
		return true
	facts.baseline = b._persist_fee_loaded_baseline(baseline)
	b._end_fee_loaded_baseline(baseline)
	if not _call_current(b):
		_finish(b, call)
		return true
	var close: Dictionary = b._begin_fee_recovered_close() # Only private baseline success can enter.
	if close.is_empty():
		facts.profile = "close_unavailable_or_nonidempotent_closed"
		_finish(b, call)
		return true
	facts.close = b._persist_fee_recovered_close(close)
	b._end_fee_recovered_close(close)
	if not _call_current(b):
		_finish(b, call)
		return true
	var permission: Dictionary = b._fee_recovered_close_writer.take_retire(b, self, call)
	if permission.is_empty():
		facts.profile = "close_not_verified"
		_finish(b, call)
		return true
	_frame.retire = permission
	facts.profile = "closed_pair_verified"
	var readback: Dictionary = _read_state(b, scope)
	if not retire_guard_current(b):
		_finish(b, call)
		return true
	if readback.kind not in ["present", "absent"]:
		facts.sidecar = "unknown_or_invalid_preserved"
		_finish(b, call)
		return true
	var state: Dictionary = readback.state
	if b.quest_loot.State.resume_is_loot(state.get("quest_auto")):
		facts.sidecar = "mixed_loot_marker_preserved"
		_finish(b, call)
		return true
	var prepared: Dictionary = b._begin_fee_resume_closed_retire_frame()
	# The real private frame/call, not a diagnostic ok, grants the old writer entry.
	var prepared_call: Variant = prepared.get("call")
	if not prepared_call is RefCounted or not is_same(prepared_call, b._fee_resume_sidecar_call) or b._fee_resume_sidecar_frame.get("action") != "retire_closed":
		facts.sidecar = prepared.get("stage", "retire_unavailable")
		_finish(b, call)
		return true
	_frame.sidecar_call = prepared_call
	if b._fee_resume_sidecar_frame.target_exists != (readback.kind == "present") or b._fee_resume_sidecar_frame.target_bytes != readback.bytes:
		facts.sidecar = "marker_changed_before_claim"
		b._end_fee_resume_sidecar_frame({"call": prepared_call})
		_finish(b, call)
		return true
	if not retire_guard_current(b):
		b._end_fee_resume_sidecar_frame({"call": prepared_call})
		_finish(b, call)
		return true
	var result: Dictionary = b._commit_fee_resume_closed_retire_frame({"call": prepared_call})
	b._end_fee_resume_sidecar_frame({"call": prepared_call})
	facts.retire = result
	# Only the internal writer completion mark can release generic-file protection.
	if retire_guard_current(b) and _frame.get("retire_verified", false):
		facts.sidecar = "retired"
		_scope.protect = _frame.residual
		facts.pending = _scope.protect
		if _scope.protect:facts.sidecar = "retired_residual_preserved"
	else:facts.sidecar = "retire_partial_or_unknown"
	_finish(b, call)
	return true

## Protection only. Never a load receipt or a close/retire permission.
func hold_departure(b) -> void:
	if handles_current(b):
		_scope.protect=true
		return
	_scope=_capture(b)
	_scope.protect=true
	_diagnostic={"profile":"departure_unverified","sidecar":"preserved","pending":true,"anchor":"existing_journal_not_failure_log"}

## Extra guard on a REAL live Stop claim through the existing exact-retire hooks.
## This is not a cold permission and cannot authorize a no-Stop recovered writer.
func begin_departure(b,f:Dictionary)->bool:
	if has_call() or not b._fee_departure_current(f):return false
	hold_departure(b)
	_frame={"call":RefCounted.new(),"scope":_scope,"departure":f,"stop":{}}
	return true
func bind_departure_stop(b,f:Dictionary)->void:
	if not _frame.has("departure") or not is_same(_frame.departure,f) or not b._fee_departure_current(f):return
	var stop:Dictionary={"call":b._quest_auto_stop_operation_call,"owner":f.runner}
	if b._quest_auto_stop_operation_current(stop):_frame.stop=stop
func end_departure(f:Dictionary)->void:
	if _frame.has("departure") and is_same(_frame.departure,f):_frame={}
func _departure_retire_current(b)->bool:
	if not _frame.has("departure") or not b._fee_departure_current(_frame.departure):return false
	if not handles_current(b) or not b._quest_auto_stop_operation_current(_frame.stop):return false
	var candidate:Dictionary=b._fee_resume_sidecar_frame
	if candidate.is_empty():return true # Preflight only; actual frame is checked before I/O.
	if not is_same(candidate.get("cold_call"),_frame.call) or not is_same(candidate.get("stop_call"),_frame.stop.call):return false
	if not candidate.get("target_exists",false):return true
	var parser:=JSON.new()
	if parser.parse(candidate.target_bytes.get_string_from_utf8())!=OK:return false
	var budget:Array=[0]
	if not b._fee_native_sidecar_dictionary_safe(parser.data,0,budget):return false
	var state:Variant=JSON.to_native(parser.data,false)
	return state is Dictionary and not b.quest_loot.State.resume_is_loot(state.get("quest_auto"))

## Only the real guarded five-file observation calls this at its absent exit.
func finish_departure_absent(b,f:Dictionary)->void:
	if not _frame.has("departure") or not is_same(_frame.departure,f) or not b._fee_departure_current(f) or not handles_current(b):return
	_scope.protect=false
