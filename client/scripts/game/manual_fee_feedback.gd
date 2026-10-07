extends RefCounted
## Presentation only. Frozen manual contract from required_fee_fact; never an
## ACK interpreter, profile writer, payment retry or transport routing rule.
const MAX_GOLD := 1000000000
const MAX_SEEN := 256
const COMMON := ["schema", "scope", "origin", "owner", "transaction_id", "fee_kind", "phase", "source_id", "currency", "amount", "balance_before", "balance_after", "status", "durability", "save_serial", "candidate_sha256"]
var seen: Array = []
var displayed_owner: Dictionary = {}
var displayed_text := ""

static func exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func integer(value: Variant, low: int, high: int, json_numbers: bool) -> bool:
	if value is int:return value >= low and value <= high
	# JSON.parse_string delivers numbers as doubles. Validate before converting;
	# native delivery must still reject floats, including integral ones.
	if not json_numbers or not value is float:return false
	if not is_finite(value) or floor(value) != value:return false
	# INT64_MAX rounds UP to 2^63 as a double: never cast that boundary.
	if value < 0.0 or value >= 9223372036854775808.0:return false
	return int(value) >= low and int(value) <= high

static func hex_id(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:return false
	for character in value:
		if not character in "0123456789abcdef":return false
	return true

static func owner_valid(value: Variant) -> bool:
	if not exact(value, ["profile_id", "character_id"]):return false
	for key in ["profile_id", "character_id"]:
		if not value[key] is String or value[key].is_empty() or value[key].length() > 128:return false
	return true

static func valid(value: Variant, json_numbers: bool) -> bool:
	if not value is Dictionary or not value.get("fee_kind") is String:return false
	var permit: bool = value.fee_kind == "undersea_permit200"
	if not permit and value.fee_kind != "seimu300":return false
	if not exact(value, COMMON + (["entitlement"] if permit else ["destination"])):return false
	if not integer(value.schema, 1, 1, json_numbers) or not owner_valid(value.owner) or not hex_id(value.transaction_id, 32):return false
	for key in ["scope", "origin", "phase", "source_id", "currency", "status", "durability"]:
		if not value[key] is String:return false
	if value.scope != "profile" or value.origin != "manual" or value.currency != "stone" or value.status != "committed":return false
	if value.durability not in ["disk", "memory"] or not integer(value.save_serial, 0, 9223372036854775807, json_numbers) or not hex_id(value.candidate_sha256, 64):return false
	var amount: int = 200 if permit else 300
	if not integer(value.amount, amount, amount, json_numbers):return false
	if not integer(value.balance_before, amount, MAX_GOLD, json_numbers) or not integer(value.balance_after, 0, MAX_GOLD, json_numbers):return false
	if int(value.balance_before) - amount != int(value.balance_after):return false
	if permit:
		return value.phase == "permit_purchase" and value.source_id in ["genout/ss_1100_86_107", "genout/ss_4000_99_85"] and value.entitlement is String and value.entitlement == "travel_pass"
	if value.phase != "gate_crossing" or value.source_id != "genout/wpm_40_13_1@40:13:1" or not exact(value.destination, ["map_id", "cell"]):return false
	var target: Dictionary = value.destination
	return integer(target.map_id, 31301, 31301, json_numbers) and target.cell is Array and target.cell.size() == 2 and integer(target.cell[0], 10, 10, json_numbers) and integer(target.cell[1], 104, 104, json_numbers)

## Retire only our own last fee presentation on an authoritative owner change.
## Keep dedupe history: switching away and back is not another transaction.
func stale_text(profile: Dictionary) -> String:
	var owner: Dictionary = {"profile_id": profile.get("profile_id"), "character_id": profile.get("character_id")}
	if displayed_owner.is_empty() or displayed_owner == owner:return ""
	var previous := displayed_text
	displayed_owner = {}
	displayed_text = ""
	return previous

## Empty result means leave the current presentation untouched. Cache belongs
## to one scene/device, survives owner switches, and keeps the last 256 tuples.
## Eviction/restart may allow an old hint again; this is not exactly-once storage.
func consume(event: Dictionary, profile: Dictionary, json_numbers: bool) -> Dictionary:
	var original := str(event.get("text", ""))
	if not valid(event.get("fee_fact"), json_numbers):return {"text": original}
	var fact: Dictionary = event.fee_fact
	var owner: Dictionary = {"profile_id": profile.get("profile_id"), "character_id": profile.get("character_id")}
	# A late fact is still owned by its original character, never by the current
	# snapshot. Do not show its old success text under a newly selected character.
	if not owner_valid(owner) or fact.owner != owner:return {}
	var key := [fact.owner.profile_id, fact.owner.character_id, fact.transaction_id, fact.phase]
	if seen.has(key):return {}
	seen.append(key)
	if seen.size() > MAX_SEEN:seen.pop_front()
	var description: String = "原售证：永久海底通行资格已生效" if fact.fee_kind == "undersea_permit200" else "赛姆原通行费"
	var committed := "%s，扣除%d石币，提交后余额%d。" % [description, int(fact.amount), int(fact.balance_after)]
	# Existing production text already contains the amount: do not repeat it.
	var text := original
	if not text.contains(committed):text += ("\n" if not text.is_empty() else "") + committed
	text += "\n仅在内存中提交，尚未保存到磁盘。" if fact.durability == "memory" else "\n本次提交已写入存档。"
	displayed_owner = fact.owner.duplicate(true)
	displayed_text = text
	return {"text": text}
