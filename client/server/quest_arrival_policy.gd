extends RefCounted
## Reviewed project safeguards. These are not additional original event flags.
## Other audited chains are added separately; staged rebirth bosses stay closed.
static func scope(map_id: int) -> String:
	if map_id==10204:return "adult"
	if (map_id>=21201 and map_id<=21215) or (map_id>=21301 and map_id<=21315):return "water"
	if map_id in [31301,31302]:return "water_blue"
	if map_id>=30301 and map_id<=30307:return "water_stone"
	if map_id in [41,42]:return "dream"
	if map_id>=11101 and map_id<=11107:return "munde"
	if map_id>=11201 and map_id<=11215:return "wind"
	return ""

static func portal_root(from_map: int, to_map: int) -> bool:
	return (from_map==400 and to_map in [41,42]) or (from_map==5000 and to_map==31301) or (from_map==10202 and to_map==10204)

static func script_root(source_id: String, to_map: int) -> bool:
	if source_id=="genout/wpm_300_247_222" and to_map==30301:return true
	if source_id=="genout/wpm_300_182_162" and to_map==30307:return true
	if source_id=="genout/wpm_200_73_696" and to_map==21201:return true
	if source_id=="genout/wpm_200_316_711" and to_map==21301:return true
	if source_id=="genout/wpm_40_13_1" and to_map==31301:return true
	return (source_id=="genout/wpm_100_443_127" and to_map==11101) or (source_id=="genout/wpm_100_278_325" and to_map==11201)

static func action_marks(npc: Dictionary, _branch: Dictionary) -> Array:
	if source(npc)=="jaruga/event/hekisei03":return ["water_material"]
	if source(npc)=="seimu/event/event01_2":return ["dream_final"]
	# Same actual event12 NPC serves legacy Munde and wind branches 2/3.
	# Both routes reach it through the original Munde keyword and final guard.
	if source(npc)=="sainasu/event/event12":return ["munde_final"]
	if source(npc) in ["sainasu/event/genou_1","sainasu/event/genou_2"]:return ["wind_final"]
	return []

static func action_mark(source_id: String) -> String:
	if source_id=="genout/wpm_21308_20_10":return "water_material"
	return ""

static func battle_mark(source_id: String) -> String:
	if source_id in ["400/sb_muge1.arg","400/sb_muge2.arg"]:return "dream_final"
	if source_id in ["100/sb_go.arg","100/sb_dan.arg"]:return "munde_final"
	if source_id=="100/sb_kgi.arg":return "wind_final"
	return ""

static func mark_regions(mark: String) -> Array:
	if mark=="water_material":return [[21308,20,7]]
	if mark=="dream_final":return [[41,34,39],[42,34,39]]
	if mark=="munde_final":return [[11107,23,35]]
	if mark=="wind_final":return [[11215,9,16]]
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
