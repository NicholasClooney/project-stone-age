extends RefCounted
## D0 independent projection. Same A field structure; automatic_required origin.
## Not a capability. No run/step/UID fields; no change to manual validator.
const MAX_GOLD := 1000000000
const SHOPS := ["genout/ss_1100_86_107", "genout/ss_4000_99_85"]
const GATE := "genout/wpm_40_13_1@40:13:1"
const COMMON := ["schema", "scope", "origin", "owner", "transaction_id", "fee_kind", "phase", "source_id", "currency", "amount", "balance_before", "balance_after", "status", "durability", "save_serial", "candidate_sha256"]

static func exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high

static func hex_id(value: Variant, length: int = 32) -> bool:
	if not value is String or value.length() != length:return false
	for character in value:
		if not character in "0123456789abcdef":return false
	return true

static func owner_valid(value: Variant) -> bool:
	if not exact(value, ["profile_id", "character_id"]):return false
	for key in ["profile_id", "character_id"]:
		if not value[key] is String or value[key].is_empty() or value[key].length() > 128:return false
	return true

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("fee_kind") is String:return false
	var permit: bool = value.fee_kind == "undersea_permit200"
	if not permit and value.fee_kind != "seimu300":return false
	if not exact(value, COMMON + (["entitlement"] if permit else ["destination"])):return false
	if not integer(value.schema, 1, 1) or not owner_valid(value.owner) or not hex_id(value.transaction_id):return false
	for key in ["scope", "origin", "phase", "source_id", "currency", "status", "durability"]:
		if not value[key] is String:return false
	if value.scope != "profile" or value.origin != "automatic_required" or value.currency != "stone" or value.status != "committed":return false
	if value.durability not in ["disk", "memory"] or not integer(value.save_serial, 0, 9223372036854775807) or not hex_id(value.candidate_sha256, 64):return false
	if not integer(value.amount, 200 if permit else 300, 200 if permit else 300):return false
	if not integer(value.balance_before, value.amount, MAX_GOLD) or not integer(value.balance_after, 0, MAX_GOLD) or value.balance_before - value.amount != value.balance_after:return false
	if permit:
		return value.phase == "permit_purchase" and value.source_id in SHOPS and value.entitlement is String and value.entitlement == "travel_pass"
	if value.phase != "gate_crossing" or value.source_id != GATE or not exact(value.destination, ["map_id", "cell"]):return false
	var target: Dictionary = value.destination
	return integer(target.map_id, 31301, 31301) and target.cell is Array and target.cell.size() == 2 and integer(target.cell[0], 10, 10) and integer(target.cell[1], 104, 104)

## The stable display dedupe tuple is (owner, transaction_id, phase). It is not
## a durable replay journal and must never authorize another charge. Future
## ticket purchase/entry facts require separate tags and transaction identities.
static func from_committed(frame: Dictionary) -> Dictionary:
	if not frame.get("marked") is bool or not frame.marked or not frame.get("durable") is bool:return {}
	if not frame.get("path") is String or frame.durable != (not frame.path.is_empty()):return {}
	if not frame.get("before") is Dictionary or not frame.get("committed") is Dictionary:return {}
	var before: Dictionary = frame.before
	var committed: Dictionary = frame.committed
	var owner: Dictionary = {"profile_id": committed.get("profile_id"), "character_id": committed.get("character_id")}
	var before_owner: Dictionary = {"profile_id": before.get("profile_id"), "character_id": before.get("character_id")}
	if not owner_valid(owner) or not owner_valid(before_owner):return {}
	if before_owner != owner:return {}
	if not before.get("player") is Dictionary or not committed.get("player") is Dictionary:return {}
	if not frame.get("kind") is String or frame.kind not in ["permit", "seimu"]:return {}
	var permit: bool = frame.kind == "permit"
	var amount: int = 200 if permit else 300
	if not integer(before.player.get("gold"), amount, MAX_GOLD) or not integer(committed.player.get("gold"), 0, MAX_GOLD):return {}
	# Check the complete candidate delta, not just a coincidental balance change.
	var expected: Dictionary = before.duplicate(true)
	expected.player.gold -= amount
	if permit:
		if not before.get("travel_pass") is bool or before.travel_pass:return {}
		if not committed.get("travel_pass") is bool or not committed.travel_pass:return {}
		expected.travel_pass = true
	else:
		expected.location = {"map_id": 31301, "x": 10, "y": 104}
	if committed != expected or not frame.get("payload") is String or JSON.stringify(committed) != frame.payload:return {}
	var fact: Dictionary = {
		"schema": 1, "scope": "profile", "origin": "automatic_required", "owner": owner,
		"transaction_id": frame.get("transaction_id"),
		"fee_kind": "undersea_permit200" if permit else "seimu300",
		"phase": "permit_purchase" if permit else "gate_crossing",
		"source_id": frame.get("source"), "currency": "stone", "amount": amount,
		"balance_before": before.player.gold, "balance_after": committed.player.gold,
		"status": "committed", "durability": "disk" if frame.durable else "memory",
		"save_serial": frame.get("committed_serial"), "candidate_sha256": frame.payload.sha256_text()
	}
	if permit:fact.entitlement = "travel_pass"
	else:fact.destination = {"map_id": 31301, "cell": [10, 104]}
	return fact if valid(fact) else {}
