extends RefCounted
## Reviewed project safeguards. These are not additional original event flags.
## Other audited chains are added separately; staged rebirth bosses stay closed.
static func scope(map_id: int) -> String:
	return "dream" if map_id in [41,42] else ""

static func portal_root(from_map: int, to_map: int) -> bool:
	return from_map==400 and to_map in [41,42]

static func script_root(_source: String, _to_map: int) -> bool:
	return false

static func action_marks(npc: Dictionary, _branch: Dictionary) -> Array:
	if source(npc)=="seimu/event/event01_2":return ["dream_final"]
	return []

static func battle_mark(source_id: String) -> String:
	if source_id in ["400/sb_muge1.arg","400/sb_muge2.arg"]:return "dream_final"
	return ""

static func mark_regions(mark: String) -> Array:
	if mark=="dream_final":return [[41,34,39],[42,34,39]]
	return []

static func blocked_guard_items(pending_guard: Dictionary) -> Array:
	match str(pending_guard.get("npc_id","")).split("@")[0]:
		"100/sb_nusu1.arg":return [2428]
		"100/sb_nusu2.arg":return [2429]
		"100/sb_nusu3.arg":return [2430]
		"300/sb_bac.arg":return [2533]
	return []

static func source(npc: Dictionary) -> String:
	return str(npc.get("source_script",str(npc.get("id","")).split("@")[0]))
