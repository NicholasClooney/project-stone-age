extends RefCounted
## Reviewed project safeguards. These are not additional original event flags.
## Other audited chains are added separately; staged rebirth bosses stay closed.
static func scope(map_id: int) -> String:
	if map_id in [41,42]:return "dream"
	for entry in [[20101,20105,"herb"],[20401,20406,"goya"],[20501,20508,"wood"],[11001,11006,"doctor"],[10701,10705,"saton"],[31801,31806,"miner"]]:
		if map_id>=int(entry[0]) and map_id<=int(entry[1]):return str(entry[2])
	if map_id>=31701 and map_id<=31706:return "brothers"
	if map_id>=20601 and map_id<=20608:return "jan"
	if map_id>=20801 and map_id<=20807:return "dragon"
	if map_id==10204:return "adult"
	if (map_id>=21201 and map_id<=21215) or (map_id>=21301 and map_id<=21315):return "water"
	if map_id in [31301,31302]:return "water_blue"
	if map_id>=21001 and map_id<=21016:return "earth"
	if map_id>=20301 and map_id<=20309:return "phoenix"
	if map_id>=30001 and map_id<=30016:return "fire"
	if map_id>=11101 and map_id<=11107:return "munde"
	if map_id>=11201 and map_id<=11215:return "wind"
	return ""

static func portal_root(from_map: int, to_map: int) -> bool:
	if [from_map,to_map] in [[300,31701],[200,20601],[200,20801],[200,20101],[200,20401],[200,20501],[100,11001],[100,10701],[300,31801]]:return true
	return (from_map==400 and to_map in [41,42]) or (from_map==10202 and to_map==10204) or (from_map==200 and to_map==20301) or (from_map==5000 and to_map==31301)

static func script_root(source_id: String, to_map: int) -> bool:
	if source_id=="genout/wpm_200_73_696" and to_map==21201:return true
	if source_id=="genout/wpm_200_316_711" and to_map==21301:return true
	if source_id=="genout/wpm_40_13_1" and to_map==31301:return true
	if source_id in ["genout/wpm_200_359_671","genout/wpm_200_358_671"] and to_map==21001:return true
	return (source_id=="genout/wpm_100_443_127" and to_map==11101) or (source_id=="genout/wpm_100_278_325" and to_map==11201) or (source_id=="genout/wpm_30502_45_41" and to_map==30001) or (source_id=="genout/wpm_30503_26_5" and to_map==30015)

static func action_marks(npc: Dictionary, _branch: Dictionary) -> Array:
	if source(npc) in ["giiru/event/ev28_ed1","giiru/event/ev28_ed2","giiru/event/ev28_ed3","giiru/event/ev28_ed4","giiru/event/ev28_ed5"]:return ["brothers_final"]
	if source(npc) in ["jaruga/event/event20_4","jaruga/event/event20_6"]:return ["jan_final"]
	if source(npc) in ["jaruga/event/event17_1","jaruga/event/event17_2","jaruga/event/event17_3"]:return ["dragon_gate"]
	if source(npc)=="jaruga/event/hekisei03":return ["water_material"]
	if source(npc) in ["jaruga/event/ruri01","jaruga/event/ruri05","jaruga/event/ruri06"]:return ["earth_final"]
	if source(npc) in ["giiru/event/sink/sink02","giiru/event/sink/sink06"]:return ["fire_final"]
	if source(npc)=="seimu/event/event01_2":return ["dream_final"]
	# Same actual event12 NPC serves legacy Munde and wind branches 2/3.
	# Both routes reach it through the original Munde keyword and final guard.
	if source(npc)=="sainasu/event/event12":return ["munde_final"]
	if source(npc) in ["sainasu/event/genou_1","sainasu/event/genou_2"]:return ["wind_final"]
	return []

static func action_mark(source_id: String) -> String:
	if source_id=="genout/wpm_20807_11_37":return "dragon_gate"
	if source_id=="genout/wpm_21308_20_10":return "water_material"
	return ""

static func battle_mark(source_id: String) -> String:
	if source_id in ["300/sb_5b1.arg","300/sb_5b2.arg","300/sb_5b3.arg","300/sb_5b4.arg","300/sb_5b5.arg"]:return "brothers_final"
	if source_id in ["200/sb_jan1.arg","200/sb_jan2.arg","200/sb_jan3.arg"]:return "jan_final"
	if source_id=="200/sb_dbt.arg":return "earth_final"
	if source_id=="300/sb_hpa.arg":return "fire_final"
	if source_id in ["400/sb_muge1.arg","400/sb_muge2.arg"]:return "dream_final"
	if source_id in ["100/sb_go.arg","100/sb_dan.arg"]:return "munde_final"
	if source_id=="100/sb_kgi.arg":return "wind_final"
	return ""

static func mark_regions(mark: String) -> Array:
	if mark=="brothers_final":return [[31706,45,16],[31706,5,17],[31706,35,17],[31706,25,16],[31706,15,16],[31706,14,5]]
	if mark=="jan_final":return [[20607,36,31],[20608,0,7]]
	if mark=="dragon_gate":return [[20807,13,35]]
	if mark=="water_material":return [[21308,20,7]]
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
