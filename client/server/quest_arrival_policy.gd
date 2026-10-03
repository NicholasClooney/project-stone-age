extends RefCounted
## Reviewed project safeguards. These are not additional original event flags.
## Other audited chains are added separately; staged rebirth bosses stay closed.
static func scope(map_id: int) -> String:
	if map_id in [41,42]:return "dream"
	if map_id==10204:return "adult"
	if map_id>=21001 and map_id<=21016:return "earth"
	if map_id>=20301 and map_id<=20309:return "phoenix"
	if map_id>=30001 and map_id<=30016:return "fire"
	if map_id>=11101 and map_id<=11107:return "munde"
	if map_id>=11201 and map_id<=11215:return "wind"
	return ""

static func portal_root(from_map: int, to_map: int) -> bool:
	return (from_map==400 and to_map in [41,42]) or (from_map==10202 and to_map==10204) or (from_map==200 and to_map==20301)

static func script_root(source_id: String, to_map: int) -> bool:
	if source_id in ["genout/wpm_200_359_671","genout/wpm_200_358_671"] and to_map==21001:return true
	return (source_id=="genout/wpm_100_443_127" and to_map==11101) or (source_id=="genout/wpm_100_278_325" and to_map==11201) or (source_id=="genout/wpm_30502_45_41" and to_map==30001) or (source_id=="genout/wpm_30503_26_5" and to_map==30015)

static func action_marks(npc: Dictionary, _branch: Dictionary) -> Array:
	if source(npc) in ["jaruga/event/ruri01","jaruga/event/ruri05","jaruga/event/ruri06"]:return ["earth_final"]
	if source(npc) in ["giiru/event/sink/sink02","giiru/event/sink/sink06"]:return ["fire_final"]
	if source(npc)=="seimu/event/event01_2":return ["dream_final"]
	# Same actual event12 NPC serves legacy Munde and wind branches 2/3.
	# Both routes reach it through the original Munde keyword and final guard.
	if source(npc)=="sainasu/event/event12":return ["munde_final"]
	if source(npc) in ["sainasu/event/genou_1","sainasu/event/genou_2"]:return ["wind_final"]
	return []

static func battle_mark(source_id: String) -> String:
	if source_id=="200/sb_dbt.arg":return "earth_final"
	if source_id=="300/sb_hpa.arg":return "fire_final"
	if source_id in ["400/sb_muge1.arg","400/sb_muge2.arg"]:return "dream_final"
	if source_id in ["100/sb_go.arg","100/sb_dan.arg"]:return "munde_final"
	if source_id=="100/sb_kgi.arg":return "wind_final"
	return ""

static func mark_regions(mark: String) -> Array:
	if mark=="earth_final":return [[21015,9,17]]
	if mark=="fire_final":return [[30016,26,63]]
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
