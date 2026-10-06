extends RefCounted
## Pure, bounded run/attempt journal shape and transition candidates.
## No IO, clock, transport authority or publication; callers supply verified facts.
const SCHEMA := 1
const MAX_INT := 2147483647
const ROOT_KEYS := ["schema", "owner", "current", "unresolved_attempt"]
const OWNER_KEYS := ["profile_id", "character_id"]
const CURRENT_KEYS := ["run_id", "run_status", "purchase"]
const ATTEMPT_KEYS := ["state", "attempt_id", "source_id", "offer_id", "item_id", "amount", "balance_before"]
const TICKET_KEYS := ["state", "attempt_id", "source_id", "offer_id", "item_id", "amount", "balance_before", "balance_after", "ticket_uid"]
const ENTRY_KEYS := ["state", "attempt_id", "source_id", "offer_id", "item_id", "amount", "balance_before", "balance_after", "ticket_uid", "consumed_ticket_uid"]
const UNKNOWN_KEYS := ["origin_run_id", "attempt_id", "source_id", "offer_id", "item_id", "amount", "balance_before"]

static func opaque(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func strict_int(value: Variant, low: int = 0, high: int = MAX_INT) -> bool:
	return value is int and value >= low and value <= high

static func nonempty(value: Variant, max_length: int = 128) -> bool:
	return value is String and not value.is_empty() and value.length() <= max_length

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key): return value.has(key))

## attempt_slot_available must come from server-side route/feature checks, never a client field.
static func empty_record(profile_id: String, character_id: String, run_id: String, attempt_slot_available: bool = true) -> Dictionary:
	if not nonempty(profile_id) or not nonempty(character_id) or not opaque(run_id):
		return {}
	return {
		"schema": SCHEMA,
		"owner": {"profile_id": profile_id, "character_id": character_id},
		"current": {"run_id": run_id, "run_status": "active", "purchase": {"state": "none" if attempt_slot_available else "manual_only"}},
		"unresolved_attempt": {}
	}

static func valid_unknown(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not exact_keys(value, UNKNOWN_KEYS):
		return false
	return opaque(value.origin_run_id) and opaque(value.attempt_id) \
		and nonempty(value.source_id) and nonempty(value.offer_id) \
		and strict_int(value.item_id, 1) and strict_int(value.amount, 1) and strict_int(value.balance_before) \
		and value.balance_before >= value.amount

static func valid_purchase(value: Variant, has_unknown: bool) -> bool:
	if not value is Dictionary or not value.has("state") or not value.state is String:
		return false
	match value.state:
		"none":
			return exact_keys(value, ["state"]) and not has_unknown
		"manual_only":
			return exact_keys(value, ["state"])
		"attempting":
			return exact_keys(value, ATTEMPT_KEYS) and opaque(value.attempt_id) \
				and nonempty(value.source_id) and nonempty(value.offer_id) \
				and strict_int(value.item_id, 1) and strict_int(value.amount, 1) \
				and strict_int(value.balance_before) and value.balance_before >= value.amount and not has_unknown
		"ticket_committed":
			return exact_keys(value, TICKET_KEYS) and opaque(value.attempt_id) \
				and nonempty(value.source_id) and nonempty(value.offer_id) \
				and strict_int(value.item_id, 1) and strict_int(value.amount, 1) and strict_int(value.balance_before) \
				and strict_int(value.balance_after) and value.balance_before - value.amount == value.balance_after \
				and strict_int(value.ticket_uid, 1) and not has_unknown
		"entry_committed":
			return exact_keys(value, ENTRY_KEYS) and opaque(value.attempt_id) \
				and nonempty(value.source_id) and nonempty(value.offer_id) \
				and strict_int(value.item_id, 1) and strict_int(value.amount, 1) and strict_int(value.balance_before) \
				and strict_int(value.balance_after) and value.balance_before - value.amount == value.balance_after \
				and strict_int(value.ticket_uid, 1) and strict_int(value.consumed_ticket_uid, 1) and not has_unknown
	return false

static func valid(record: Variant) -> bool:
	if not record is Dictionary or not exact_keys(record, ROOT_KEYS):
		return false
	if not strict_int(record.schema, SCHEMA, SCHEMA):
		return false
	if not record.owner is Dictionary or not exact_keys(record.owner, OWNER_KEYS):
		return false
	if not nonempty(record.owner.profile_id) or not nonempty(record.owner.character_id):
		return false
	if not record.current is Dictionary or not exact_keys(record.current, CURRENT_KEYS):
		return false
	var current: Dictionary = record.current
	if not opaque(current.run_id) or not current.run_status is String \
		or current.run_status not in ["active", "closed"]:
		return false
	if not valid_unknown(record.unresolved_attempt):
		return false
	var has_unknown: bool = not record.unresolved_attempt.is_empty()
	var purchase_value: Variant = current.get("purchase", null)
	if not valid_purchase(purchase_value, has_unknown):
		return false
	var purchase: Dictionary = purchase_value
	if purchase.state in ["attempting", "ticket_committed", "entry_committed"] and purchase.attempt_id == current.run_id:
		return false
	if has_unknown:
		var unknown: Dictionary = record.unresolved_attempt
		if unknown.attempt_id == unknown.origin_run_id or unknown.attempt_id == current.run_id:
			return false
		if purchase.state != "manual_only":
			return false
		# The original closed run may hold its own tombstone. Once replaced,
		# the tombstone must keep its origin while every newer run stays distinct.
		if unknown.origin_run_id == current.run_id and current.run_status != "closed":
			return false
	return true

static func sidecar_decision(record: Variant, sidecar: Variant) -> Dictionary:
	if not valid(record):
		return {"ok": false, "resume": false, "attempt_slot_available": false, "reason": "invalid_profile_record"}
	if record.current.run_status != "active":
		return {"ok": true, "resume": false, "attempt_slot_available": false, "reason": "profile_closed"}
	if not sidecar is Dictionary or not sidecar.has("owner") or not sidecar.owner is Dictionary:
		return {"ok": true, "resume": false, "attempt_slot_available": false, "reason": "missing_or_invalid_sidecar"}
	var same_owner: bool = sidecar.owner.get("profile_id", null) == record.owner.profile_id \
		and sidecar.owner.get("character_id", null) == record.owner.character_id
	var same_run: bool = sidecar.get("run_id", null) == record.current.run_id
	if not same_owner or not same_run:
		return {"ok": true, "resume": false, "attempt_slot_available": false, "reason": "sidecar_owner_or_run_mismatch"}
	var purchase_state: String = str(record.current.purchase.state)
	var slot_available: bool = purchase_state == "none" and record.unresolved_attempt.is_empty()
	return {"ok": true, "resume": true, "attempt_slot_available": slot_available, "reason": "matched_active_run"}

static func begin_attempt(record: Variant, run_id: String, attempt_id: String, source_id: String, offer_id: String, item_id: Variant, amount: Variant, balance_before: Variant) -> Dictionary:
	if not valid(record) or record.current.run_status != "active" or record.current.run_id != run_id:
		return {"ok": false, "reason": "stale_or_closed_run"}
	if not record.unresolved_attempt.is_empty() or record.current.purchase.state != "none":
		return {"ok": false, "reason": "purchase_not_eligible"}
	if not opaque(attempt_id) or attempt_id == run_id or not nonempty(source_id) or not nonempty(offer_id) \
		or not strict_int(item_id, 1) or not strict_int(amount, 1) or not strict_int(balance_before) or balance_before < amount:
		return {"ok": false, "reason": "invalid_attempt_facts"}
	var candidate: Dictionary = record.duplicate(true)
	candidate.current.purchase = {"state": "attempting", "attempt_id": attempt_id, "source_id": source_id, "offer_id": offer_id, "item_id": item_id, "amount": amount, "balance_before": balance_before}
	return {"ok": true, "candidate": candidate}

static func commit_ticket(record: Variant, run_id: String, attempt_id: String, ticket_uid: Variant, balance_after: Variant) -> Dictionary:
	if not valid(record) or record.current.run_status != "active" or record.current.run_id != run_id:
		return {"ok": false, "reason": "stale_or_closed_run"}
	var purchase: Dictionary = record.current.purchase
	if purchase.state != "attempting" or purchase.attempt_id != attempt_id or not strict_int(ticket_uid, 1) \
		or not strict_int(balance_after) or purchase.balance_before - purchase.amount != balance_after:
		return {"ok": false, "reason": "attempt_or_uid_mismatch"}
	var candidate: Dictionary = record.duplicate(true)
	candidate.current.purchase = purchase.duplicate(true)
	candidate.current.purchase.state = "ticket_committed"
	candidate.current.purchase.ticket_uid = ticket_uid
	candidate.current.purchase.balance_after = balance_after
	return {"ok": true, "candidate": candidate}

static func commit_entry(record: Variant, run_id: String, attempt_id: String, ticket_uid: Variant, consumed_item_id: Variant, consumed_ticket_uid: Variant) -> Dictionary:
	if not valid(record) or record.current.run_status != "active" or record.current.run_id != run_id:
		return {"ok": false, "reason": "stale_or_closed_run"}
	var purchase: Dictionary = record.current.purchase
	if purchase.state != "ticket_committed" or purchase.attempt_id != attempt_id \
		or not strict_int(ticket_uid, 1) or ticket_uid != purchase.ticket_uid \
		or not strict_int(consumed_item_id, 1) or consumed_item_id != purchase.item_id \
		or not strict_int(consumed_ticket_uid, 1):
		return {"ok": false, "reason": "ticket_consumption_mismatch"}
	var candidate: Dictionary = record.duplicate(true)
	candidate.current.purchase = purchase.duplicate(true)
	candidate.current.purchase.state = "entry_committed"
	candidate.current.purchase.consumed_ticket_uid = consumed_ticket_uid
	return {"ok": true, "candidate": candidate}

## Pure financial projection from an already committed candidate. This is not
## proof of disk durability; the writer boundary must add that fact only after
## its own successful write/readback checks.
static func committed_fee_fact(record: Variant) -> Dictionary:
	if not valid(record) or record.current.run_status != "active":
		return {}
	var purchase: Dictionary = record.current.purchase
	if purchase.state not in ["ticket_committed", "entry_committed"]:
		return {}
	var fact: Dictionary = {
		"schema": 1,
		"transaction_id": purchase.attempt_id,
		"origin_run_id": record.current.run_id,
		"attempt_id": purchase.attempt_id,
		"source_id": purchase.source_id,
		"offer_id": purchase.offer_id,
		"item_id": purchase.item_id,
		"currency": "stone",
		"amount": purchase.amount,
		"balance_before": purchase.balance_before,
		"balance_after": purchase.balance_after,
		"ticket_uid": purchase.ticket_uid,
		"state": purchase.state
	}
	if purchase.state == "entry_committed":
		fact.consumed_ticket_uid = purchase.consumed_ticket_uid
	return fact

static func close_run(record: Variant, run_id: String) -> Dictionary:
	if not valid(record) or record.current.run_id != run_id:
		return {"ok": false, "reason": "stale_run"}
	var candidate: Dictionary = record.duplicate(true)
	candidate.current.run_status = "closed"
	var unresolved: Dictionary = _unknown_from(record)
	if not unresolved.is_empty():
		candidate.unresolved_attempt = unresolved
		candidate.current.purchase = {"state": "manual_only"}
	return {"ok": true, "candidate": candidate, "already_closed": record.current.run_status == "closed"}

static func _unknown_from(record: Dictionary) -> Dictionary:
	if not record.unresolved_attempt.is_empty():
		return record.unresolved_attempt.duplicate(true)
	var purchase: Dictionary = record.current.purchase
	if purchase.state != "attempting":
		return {}
	return {
		"origin_run_id": record.current.run_id,
		"attempt_id": purchase.attempt_id,
		"source_id": purchase.source_id,
		"offer_id": purchase.offer_id,
		"item_id": purchase.item_id,
		"amount": purchase.amount,
		"balance_before": purchase.balance_before
	}

static func replace_closed_for_start(previous: Variant, profile_id: String, character_id: String, new_run_id: String, attempt_slot_available: bool = true) -> Dictionary:
	if not valid(previous) or previous.current.run_status != "closed":
		return {"ok": false, "reason": "previous_run_not_closed"}
	if previous.owner.profile_id != profile_id or previous.owner.character_id != character_id:
		return {"ok": false, "reason": "profile_owner_mismatch"}
	var unknown: Dictionary = _unknown_from(previous)
	if new_run_id == previous.current.run_id:
		return {"ok": false, "reason": "new_run_must_be_distinct"}
	var candidate: Dictionary = empty_record(profile_id, character_id, new_run_id, attempt_slot_available)
	if candidate.is_empty():
		return {"ok": false, "reason": "invalid_new_run"}
	if not unknown.is_empty():
		if new_run_id == unknown.origin_run_id or new_run_id == unknown.attempt_id:
			return {"ok": false, "reason": "new_run_must_not_reuse_unknown_origin"}
		candidate.unresolved_attempt = unknown
		candidate.current.purchase = {"state": "manual_only"}
	return {"ok": true, "candidate": candidate}
