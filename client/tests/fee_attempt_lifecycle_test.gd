extends SceneTree
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
const OWNER = "samgir-singleplayer-v1"
const CHARACTER = "100000"
const RUN_A = "0123456789abcdef0123456789abcdef"
const RUN_B = "fedcba9876543210fedcba9876543210"
const RUN_C = "00112233445566778899aabbccddeeff"
const ATTEMPT = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SOURCE = "locked-source-example"
const OFFER = "ticket-tier-example"
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func expected_record(run_id: String, run_status: String, purchase: Dictionary, unresolved: Dictionary = {}) -> Dictionary:
	return {
		"schema": 1,
		"owner": {"profile_id": OWNER, "character_id": CHARACTER},
		"current": {"run_id": run_id, "run_status": run_status, "purchase": purchase.duplicate(true)},
		"unresolved_attempt": unresolved.duplicate(true)
	}

func candidate_of(result: Dictionary) -> Dictionary:
	var value: Variant = result.get("candidate", {})
	return value if value is Dictionary else {}

func check_transition(result: Dictionary, expected: Dictionary, input_after: Dictionary, input_before: Dictionary, label: String) -> void:
	var candidate: Dictionary = candidate_of(result)
	check(result.get("ok", false) == true, "%s returns ok" % label)
	check(Journal.valid(candidate), "%s candidate passes valid" % label)
	check(candidate == expected, "%s candidate equals independent full expected record" % label)
	check(input_after == input_before, "%s leaves input unchanged" % label)

func run() -> void:
	var original: Dictionary = Journal.empty_record(OWNER, CHARACTER, RUN_A)
	var original_expected: Dictionary = expected_record(RUN_A, "active", {"state": "none"})
	check(original == original_expected and Journal.valid(original), "New record equals the independent full initial oracle")
	var original_before: Dictionary = original.duplicate(true)
	var same_sidecar: Dictionary = {"owner": {"profile_id": OWNER, "character_id": CHARACTER}, "run_id": RUN_A}
	var started: Dictionary = Journal.sidecar_decision(original, same_sidecar)
	check(started.ok and started.resume and started.attempt_slot_available, "Only same owner and run restores first-attempt eligibility")
	check(not Journal.sidecar_decision(original, {"owner": same_sidecar.owner, "run_id": RUN_B}).resume, "Old sidecar cannot attach to a later run")
	check(not Journal.sidecar_decision(original, {"owner": {"profile_id": "another-profile", "character_id": CHARACTER}, "run_id": RUN_A}).resume, "Sidecar from another stable profile cannot resume")
	var route_blocked: Dictionary = Journal.empty_record(OWNER, CHARACTER, RUN_B, false)
	check(Journal.valid(route_blocked) and route_blocked == expected_record(RUN_B, "active", {"state": "manual_only"}), "Denied route slot is a valid manual-only record")

	var attempted_result: Dictionary = Journal.begin_attempt(original, RUN_A, ATTEMPT, SOURCE, OFFER, 2755, 200, 1000)
	var attempting_purchase: Dictionary = {"state": "attempting", "attempt_id": ATTEMPT, "source_id": SOURCE, "offer_id": OFFER, "item_id": 2755, "amount": 200, "balance_before": 1000}
	var attempted_expected: Dictionary = expected_record(RUN_A, "active", attempting_purchase)
	check_transition(attempted_result, attempted_expected, original, original_before, "begin_attempt")
	var attempted: Dictionary = candidate_of(attempted_result)
	var attempting_sidecar: Dictionary = {"owner": original_before.owner, "run_id": RUN_A}
	var attempting_resume: Dictionary = Journal.sidecar_decision(attempted, attempting_sidecar)
	check(attempting_resume.ok and attempting_resume.resume and not attempting_resume.attempt_slot_available, "Attempting run resumes but cannot issue another automatic yes")
	check(not Journal.begin_attempt(attempted, RUN_A, ATTEMPT, SOURCE, OFFER, 2755, 200, 1000).ok, "Same run cannot begin a second attempt")
	check(not Journal.begin_attempt(attempted, RUN_B, ATTEMPT, SOURCE, OFFER, 2755, 200, 1000).ok, "Wrong run cannot write an attempt")

	var attempted_before_commit: Dictionary = attempted.duplicate(true)
	var committed_result: Dictionary = Journal.commit_ticket(attempted, RUN_A, ATTEMPT, 7, 800)
	var ticket_purchase: Dictionary = {"state": "ticket_committed", "attempt_id": ATTEMPT, "source_id": SOURCE, "offer_id": OFFER, "item_id": 2755, "amount": 200, "balance_before": 1000, "balance_after": 800, "ticket_uid": 7}
	var committed_expected: Dictionary = expected_record(RUN_A, "active", ticket_purchase)
	check_transition(committed_result, committed_expected, attempted, attempted_before_commit, "commit_ticket")
	var committed: Dictionary = candidate_of(committed_result)
	var committed_resume: Dictionary = Journal.sidecar_decision(committed, attempting_sidecar)
	check(committed_resume.ok and committed_resume.resume and not committed_resume.attempt_slot_available, "Ticket-committed active run resumes without another purchase slot")
	var fee_fact: Dictionary = Journal.committed_fee_fact(committed)
	check(fee_fact.transaction_id == ATTEMPT and fee_fact.origin_run_id == RUN_A and fee_fact.source_id == SOURCE and fee_fact.offer_id == OFFER, "Typed fee fact derives identity/source from committed candidate")
	check(fee_fact.currency == "stone" and fee_fact.amount == 200 and fee_fact.balance_before == 1000 and fee_fact.balance_after == 800 and fee_fact.ticket_uid == 7, "Typed fee fact carries exact financial fields and purchased UID")
	check(not fee_fact.has("durable"), "Pure candidate projection cannot certify persistence")
	check(Journal.committed_fee_fact(attempted).is_empty() and Journal.committed_fee_fact(original).is_empty(), "Pending and unattempted records produce no committed fact")
	check(not Journal.commit_ticket(attempted, RUN_A, ATTEMPT, true, 800).ok, "Boolean cannot impersonate an item UID")
	check(not Journal.commit_ticket(attempted, RUN_A, ATTEMPT, 7, 801).ok, "Fee fact must match before/after balance")
	check(attempted == attempted_before_commit, "Rejected ticket transitions leave the attempting input unchanged")

	var committed_before_entry: Dictionary = committed.duplicate(true)
	check(not Journal.commit_entry(committed, RUN_A, ATTEMPT, 8, 2755, 8).ok, "Entry cannot substitute a different purchased-ticket UID")
	check(not Journal.commit_entry(committed, RUN_A, ATTEMPT, 7, 2756, 8).ok, "Entry rejects a consumed item of the wrong type")
	var entered_result: Dictionary = Journal.commit_entry(committed, RUN_A, ATTEMPT, 7, 2755, 8)
	var entry_purchase: Dictionary = ticket_purchase.duplicate(true)
	entry_purchase.state = "entry_committed"
	entry_purchase.consumed_ticket_uid = 8
	var entered_expected: Dictionary = expected_record(RUN_A, "active", entry_purchase)
	check_transition(entered_result, entered_expected, committed, committed_before_entry, "commit_entry")
	var entered: Dictionary = candidate_of(entered_result)
	check(entered.current.purchase.ticket_uid == 7 and entered.current.purchase.consumed_ticket_uid == 8, "Purchase and actual consumption UIDs remain distinct")
	var entry_fact: Dictionary = Journal.committed_fee_fact(entered)
	check(entry_fact.ticket_uid == 7 and entry_fact.consumed_ticket_uid == 8, "Typed entry fact preserves both UID roles")
	var entered_resume: Dictionary = Journal.sidecar_decision(entered, attempting_sidecar)
	check(entered_resume.ok and entered_resume.resume and not entered_resume.attempt_slot_available, "Entry-committed active run resumes without another purchase slot")

	var entered_before_close: Dictionary = entered.duplicate(true)
	var close_result: Dictionary = Journal.close_run(entered, RUN_A)
	var closed_expected: Dictionary = expected_record(RUN_A, "closed", entry_purchase)
	check_transition(close_result, closed_expected, entered, entered_before_close, "close known committed run")
	var closed: Dictionary = candidate_of(close_result)
	var stale_resume: Dictionary = Journal.sidecar_decision(closed, same_sidecar)
	check(stale_resume.ok and not stale_resume.resume and not stale_resume.attempt_slot_available and stale_resume.reason == "profile_closed", "Closed profile rejects matching sidecar")
	var closed_before_repeat: Dictionary = closed.duplicate(true)
	var repeated_close: Dictionary = Journal.close_run(closed, RUN_A)
	check(repeated_close.ok and repeated_close.already_closed and candidate_of(repeated_close) == closed and Journal.valid(candidate_of(repeated_close)), "Repeated close of known transaction is idempotent")
	check(closed == closed_before_repeat, "Repeated close leaves known closed input unchanged")
	var closed_before_replace: Dictionary = closed.duplicate(true)
	var next_result: Dictionary = Journal.replace_closed_for_start(closed, OWNER, CHARACTER, RUN_B)
	var run_b_expected: Dictionary = expected_record(RUN_B, "active", {"state": "none"})
	check_transition(next_result, run_b_expected, closed, closed_before_replace, "replace known closed run")
	check(not Journal.replace_closed_for_start(closed, OWNER, CHARACTER, RUN_A).ok, "A new Start must use a fresh run identity")

	# A persisted attempting fence survives one-generation backup fallback.
	var attempt_backup: Dictionary = attempted.duplicate(true)
	var fallback_decision: Dictionary = Journal.sidecar_decision(attempt_backup, attempting_sidecar)
	check(fallback_decision.resume and not fallback_decision.attempt_slot_available, "Attempting backup fallback cannot repeat yes")
	var close_backup: Dictionary = closed.duplicate(true)
	check(not Journal.sidecar_decision(close_backup, same_sidecar).resume, "Closed backup also rejects old resume")

	# Unknown is bound to the original run while closed, then retained unchanged
	# under later active/closed runs; ticket presence is not modeled by this helper.
	var attempted_before_stop: Dictionary = attempted.duplicate(true)
	var unknown_close_result: Dictionary = Journal.close_run(attempted, RUN_A)
	var unknown: Dictionary = {"origin_run_id": RUN_A, "attempt_id": ATTEMPT, "source_id": SOURCE, "offer_id": OFFER, "item_id": 2755, "amount": 200, "balance_before": 1000}
	var unknown_closed_expected: Dictionary = expected_record(RUN_A, "closed", {"state": "manual_only"}, unknown)
	check_transition(unknown_close_result, unknown_closed_expected, attempted, attempted_before_stop, "close attempting run")
	var unknown_closed: Dictionary = candidate_of(unknown_close_result)
	var unknown_sidecar: Dictionary = {"owner": original_before.owner, "run_id": RUN_A}
	var closed_unknown_resume: Dictionary = Journal.sidecar_decision(unknown_closed, unknown_sidecar)
	check(closed_unknown_resume.ok and not closed_unknown_resume.resume, "Original closed tombstone rejects old sidecar")
	var unknown_closed_before_repeat: Dictionary = unknown_closed.duplicate(true)
	var repeat_unknown_result: Dictionary = Journal.close_run(unknown_closed, RUN_A)
	check(unknown_closed == unknown_closed_before_repeat, "Repeated close leaves its input unchanged")
	check(repeat_unknown_result.ok and repeat_unknown_result.already_closed and Journal.valid(candidate_of(repeat_unknown_result)), "Repeated close preserves a valid original-run tombstone")
	check(candidate_of(repeat_unknown_result) == unknown_closed_expected and unknown_closed == unknown_closed_expected, "Repeated close and original closed stage equal the full expected record")
	var unknown_closed_before_replace: Dictionary = unknown_closed.duplicate(true)
	var unknown_new_result: Dictionary = Journal.replace_closed_for_start(unknown_closed, OWNER, CHARACTER, RUN_B)
	var unknown_active_expected: Dictionary = expected_record(RUN_B, "active", {"state": "manual_only"}, unknown)
	check_transition(unknown_new_result, unknown_active_expected, unknown_closed, unknown_closed_before_replace, "replace with unresolved attempt")
	var unknown_new: Dictionary = candidate_of(unknown_new_result)
	var new_run_sidecar: Dictionary = {"owner": original_before.owner, "run_id": RUN_B}
	var active_unknown_resume: Dictionary = Journal.sidecar_decision(unknown_new, new_run_sidecar)
	check(active_unknown_resume.ok and active_unknown_resume.resume and not active_unknown_resume.attempt_slot_available, "New run may resume but unresolved prior attempt stays manual-only")
	var unknown_closed_before_route: Dictionary = unknown_closed.duplicate(true)
	var route_replacement_result: Dictionary = Journal.replace_closed_for_start(unknown_closed, OWNER, CHARACTER, RUN_B, true)
	check_transition(route_replacement_result, unknown_active_expected, unknown_closed, unknown_closed_before_route, "route availability cannot erase unknown attempt")
	check(not Journal.sidecar_decision(unknown_new, unknown_sidecar).resume, "Old attempt sidecar cannot attach to replacement run")
	check(not Journal.begin_attempt(unknown_new, RUN_B, RUN_B, SOURCE, OFFER, 2755, 200, 1000).ok, "Unresolved tombstone disables automatic yes in the new run")
	check(not Journal.replace_closed_for_start(unknown_closed, OWNER, CHARACTER, ATTEMPT).ok, "Replacement run cannot reuse the unresolved transaction identity")

	var unknown_new_before_close: Dictionary = unknown_new.duplicate(true)
	var close_new_result: Dictionary = Journal.close_run(unknown_new, RUN_B)
	var unknown_new_closed_expected: Dictionary = expected_record(RUN_B, "closed", {"state": "manual_only"}, unknown)
	check_transition(close_new_result, unknown_new_closed_expected, unknown_new, unknown_new_before_close, "close replacement run with inherited tombstone")
	var unknown_new_closed: Dictionary = candidate_of(close_new_result)
	check(not Journal.sidecar_decision(unknown_new_closed, new_run_sidecar).resume, "Closed replacement run rejects its sidecar")
	var unknown_new_closed_before_replace: Dictionary = unknown_new_closed.duplicate(true)
	var unknown_third_result: Dictionary = Journal.replace_closed_for_start(unknown_new_closed, OWNER, CHARACTER, RUN_C)
	var unknown_third_expected: Dictionary = expected_record(RUN_C, "active", {"state": "manual_only"}, unknown)
	check_transition(unknown_third_result, unknown_third_expected, unknown_new_closed, unknown_new_closed_before_replace, "replace second closed run while retaining old origin")
	var third_run_sidecar: Dictionary = {"owner": original_before.owner, "run_id": RUN_C}
	var third_unknown_resume: Dictionary = Journal.sidecar_decision(candidate_of(unknown_third_result), third_run_sidecar)
	check(third_unknown_resume.ok and third_unknown_resume.resume and not third_unknown_resume.attempt_slot_available, "Third run sidecar can resume while inherited tombstone blocks automatic purchase")

	for invalid in [true, 1.5, INF, "1"]:
		check(not Journal.strict_int(invalid), "Strict integer rejects %s" % str(invalid))
	var bad_amount: Dictionary = original.duplicate(true)
	bad_amount.current.purchase = {"state": "attempting", "attempt_id": ATTEMPT, "source_id": SOURCE, "offer_id": OFFER, "item_id": 2755, "amount": true, "balance_before": 1000}
	check(not Journal.valid(bad_amount), "Malformed fee amount is not treated as an empty record")
	for malformed_purchase in [null, "bad", [], {}, {"state": 1}, {"state": ["none"]}, {"state": "attempting", "source_id": SOURCE, "offer_id": OFFER, "item_id": 2755, "amount": 200, "balance_before": 1000}]:
		var bad_purchase: Dictionary = original.duplicate(true)
		bad_purchase.current.purchase = malformed_purchase
		check(not Journal.valid(bad_purchase), "Malformed purchase is rejected before unsafe field access: %s" % str(malformed_purchase))
	check(original == original_before, "Malformed-input cases do not mutate their source record")
	var reused_attempt_id: Dictionary = attempted.duplicate(true)
	reused_attempt_id.current.purchase.attempt_id = RUN_A
	check(not Journal.valid(reused_attempt_id), "Attempt identity cannot reuse its run identity")
	var bad_owner: Dictionary = original.duplicate(true)
	bad_owner.owner.transport_id = 1
	check(not Journal.valid(bad_owner), "Transport identity cannot enter persistent owner record")
	var bad_entry: Dictionary = entered.duplicate(true)
	bad_entry.current.purchase.consumed_ticket_uid = true
	check(not Journal.valid(bad_entry), "A non-integer consumed UID is rejected")
	var bad_unknown: Dictionary = unknown_new.duplicate(true)
	bad_unknown.unresolved_attempt.origin_run_id = RUN_B
	check(not Journal.valid(bad_unknown), "Unknown origin cannot equal the active replacement run")
	var reused_unknown: Dictionary = unknown_new.duplicate(true)
	reused_unknown.unresolved_attempt.origin_run_id = RUN_A
	reused_unknown.unresolved_attempt.attempt_id = RUN_B
	check(not Journal.valid(reused_unknown), "Tombstone attempt identity cannot equal its origin or current run")
	var unknown_attempt_equals_origin: Dictionary = unknown_new.duplicate(true)
	unknown_attempt_equals_origin.unresolved_attempt.attempt_id = RUN_A
	check(not Journal.valid(unknown_attempt_equals_origin), "Tombstone attempt identity cannot equal its origin")
	check(not Journal.valid(expected_record(RUN_A, "active", {"state": "manual_only"}, unknown)), "Same-origin tombstone is not accepted on an active run")
	check(not Journal.valid(expected_record(RUN_A, "closed", {"state": "none"}, unknown)), "Closed same-origin tombstone still requires manual_only")

	if failures > 0:
		print("FEE ATTEMPT LIFECYCLE: %d failures; pure candidates only" % failures)
		quit(1)
		return
	print("FEE ATTEMPT LIFECYCLE: all oracle assertions passed; pure candidates only")
	quit(0)
