extends RefCounted
## Pinned itemset.txt; only reviewed wood/herb/adult equipment is wearable here.
## HEAD is independent of legacy BODY. Legacy ownership fields stay intact.
## arm / bracelet are
## CHAR_ARM / CHAR_DECORATION2, with amulets (legacy or original) in CHAR_DECORATION1.
const ITEMS := {
	2418:{"name":"仪之兜","type":6,"slot":"head","level":30,"attack":0,"defence":15,"speed":-3,"charm":0,"durability":2500000,"resistances":[3,3,3,3,3,3]},
	2427:{"name":"老爷爷的护身符","type":15,"slot":"amulet","level":10,"attack":0,"defence":0,"speed":0,"charm":-1,"durability":2500000,"resistances":[2,2,2,2,2,2]},
	2465:{"name":"哈恩的斧头","type":1,"slot":"arm","level":25,"attack":35,"defence":-15,"speed":-15,"charm":0,"durability":0},
	2485:{"name":"哈恩改造的斧头","type":1,"slot":"arm","level":25,"attack":33,"defence":-10,"speed":-10,"charm":0,"durability":300000},
	2481:{"name":"杉的手环","type":8,"slot":"bracelet","level":30,"attack":8,"defence":5,"speed":-5,"charm":-5,"durability":2500000},
}
const STAGES := ["完好","受损","毁坏","不堪使用"]
const STATS := ["attack","defence","speed","charm"]

static func instance(id: int, uid: int) -> Dictionary:
	return {"uid":uid,"item_id":id,"durability":int(ITEMS.get(id,{}).get("durability",0))}

static func migrate(profile: Dictionary) -> void:
	if profile.has("original_instances"):
		# Version 6 used no HEAD field: 2418 was an unworn story instance
		# with zero durability. Initialize that newly supported item only once.
		if not profile.original_equipment.has("head"):
			profile.original_equipment.head=0
			for entry in profile.original_instances:
				if int(entry.item_id)==2418 and int(entry.durability)==0:entry.durability=2500000
		# original_items remains the canonical compatibility projection. Old
		# authority tools may append it directly; retain existing copies in order
		# and initialize only newly acquired entries, never re-roll durability.
		if profile.original_instances.size()==profile.get("original_items",[]).size():
			var aligned:=true
			for i in range(profile.original_instances.size()):
				if int(profile.original_instances[i].item_id)!=int(profile.original_items[i]):aligned=false;break
			if aligned:return
		var existing: Array=profile.original_instances.duplicate()
		var rebuilt: Array=[]
		for id in profile.get("original_items",[]):
			var index: int=-1
			for i in range(existing.size()):
				if int(existing[i].item_id)==int(id):index=i;break
			if index>=0:rebuilt.append(existing.pop_at(index))
			else:
				rebuilt.append(instance(int(id),int(profile.next_original_uid)))
				profile.next_original_uid+=1
		profile.original_instances=rebuilt
		var uids: Array=rebuilt.map(func(entry):return int(entry.uid))
		for slot in profile.original_equipment:
			if int(profile.original_equipment[slot]) not in uids:profile.original_equipment[slot]=0
		return
	profile.original_instances=[]
	profile.original_equipment={"arm":0,"bracelet":0,"amulet":0,"head":0}
	profile.next_original_uid=1
	for id in profile.get("original_items",[]):
		profile.original_instances.append(instance(int(id),int(profile.next_original_uid)))
		profile.next_original_uid+=1

static func add(profile: Dictionary, id: int) -> void:
	migrate(profile)
	profile.original_items.append(id)
	profile.original_instances.append(instance(id,int(profile.next_original_uid)))
	profile.next_original_uid+=1

static func remove_at(profile: Dictionary, index: int) -> void:
	migrate(profile)
	if index<0 or index>=profile.original_items.size():return
	var uid: int=int(profile.original_instances[index].uid)
	for slot in profile.original_equipment:
		if int(profile.original_equipment[slot])==uid:profile.original_equipment[slot]=0
	profile.original_instances.remove_at(index)
	profile.original_items.remove_at(index)

static func remove(profile: Dictionary, id: int) -> void:
	migrate(profile)
	# Original NPC scans start at equipped positions before the bag. A script that
	# consumes one copy therefore consumes the worn copy first, if present.
	for i in range(profile.original_instances.size()):
		var entry: Dictionary=profile.original_instances[i]
		if int(entry.item_id)==id and worn(profile,int(entry.uid)):
			remove_at(profile,i)
			return
	remove_at(profile,profile.original_items.find(id))

static func worn(profile: Dictionary, uid: int) -> bool:
	return uid>0 and uid in profile.get("original_equipment",{}).values()

static func mods(profile: Dictionary) -> Dictionary:
	var result: Dictionary={"attack":0,"defence":0,"speed":0,"charm":0}
	for entry in profile.get("original_instances",[]):
		if not worn(profile,int(entry.uid)):continue
		for stat in STATS:result[stat]+=int(ITEMS[int(entry.item_id)][stat])
	return result

## itemset six resistance modifiers: poison, paralysis, sleep, stone,
## drunk, confusion. Metadata only until the battle status system exists.
static func resistances(profile: Dictionary) -> Array:
	var result: Array=[0,0,0,0,0,0]
	for entry in profile.get("original_instances",[]):
		if not worn(profile,int(entry.uid)):continue
		var values: Array=ITEMS[int(entry.item_id)].get("resistances",[0,0,0,0,0,0])
		for i in range(6):result[i]+=int(values[i])
	return result

static func battle_items(profile: Dictionary) -> Array:
	var result: Array=[]
	for entry in profile.get("original_instances",[]):
		if worn(profile,int(entry.uid)):result.append(entry.duplicate(true))
	return result

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and float(value)==floor(float(value)) and value>=low and value<=high

static func valid(profile: Dictionary) -> bool:
	if profile.has("equipment") and not profile.equipment is Dictionary:return false
	if not profile.get("original_instances") is Array or profile.original_instances.size()!=profile.original_items.size():return false
	if not profile.get("original_equipment") is Dictionary:return false
	var has_head: bool=profile.original_equipment.has("head")
	if profile.original_equipment.size()!=(4 if has_head else 3):return false
	if not integer(profile.get("next_original_uid"),1,2147483647):return false
	var seen: Array=[]
	for i in range(profile.original_instances.size()):
		var entry=profile.original_instances[i]
		if not entry is Dictionary or entry.size()!=3 or not integer(entry.get("uid"),1,int(profile.next_original_uid)-1) or entry.uid in seen:return false
		if not integer(entry.get("item_id"),1,2147483647) or int(entry.item_id)!=int(profile.original_items[i]):return false
		if not integer(entry.get("durability"),0,int(ITEMS.get(int(entry.item_id),{}).get("durability",0))):return false
		var legacy_helmet: bool=int(entry.item_id)==2418 and not has_head
		if legacy_helmet and int(entry.durability)!=0:return false
		if not legacy_helmet and ITEMS.has(int(entry.item_id)) and int(ITEMS[int(entry.item_id)].durability)>0 and int(entry.durability)==0:return false
		seen.append(entry.uid)
	for slot in (["arm","bracelet","amulet","head"] if has_head else ["arm","bracelet","amulet"]):
		var uid=profile.original_equipment.get(slot)
		if not integer(uid,0,int(profile.next_original_uid)-1):return false
		if int(uid)==0:continue
		var matches: Array=profile.original_instances.filter(func(entry):return int(entry.uid)==int(uid))
		if matches.size()!=1 or not ITEMS.has(int(matches[0].item_id)) or str(ITEMS[int(matches[0].item_id)].slot)!=slot:return false
	if int(profile.original_equipment.arm)>0 and bool(profile.get("equipped",false)):return false
	if int(profile.original_equipment.amulet)>0 and (bool(profile.get("equipped_mirror",false)) or not str(profile.get("equipment",{}).get("amulet","")).is_empty()):return false
	return true

## Validate a settlement against the equipment at admission, before mutation.
static func result_valid(initial: Array, final: Variant) -> bool:
	if not final is Array or initial.size()!=final.size():return false
	for i in range(initial.size()):
		var entry=final[i]
		if not entry is Dictionary or entry.size()!=3:return false
		if entry.get("uid")!=initial[i].uid or entry.get("item_id")!=initial[i].item_id or not integer(entry.get("durability"),0,int(initial[i].durability)):return false
	return true

static func settle(profile: Dictionary, final: Array) -> void:
	for entry in final:
		for index in range(profile.original_instances.size()):
			if int(profile.original_instances[index].uid)!=int(entry.uid):continue
			if int(entry.durability)==0 and int(ITEMS[int(entry.item_id)].durability)>0:remove_at(profile,index)
			else:profile.original_instances[index].durability=int(entry.durability)
			break

## BATTLE_ItemCrush: preserve C integer truncation and its overwritten >=200
## assignment. RAND is the original inclusive floating upper-bound macro.
static func wear_amount(damage: int, arm: bool, rng: RandomNumberGenerator) -> int:
	var low:=int((damage-50)/40) if arm else int((200-damage)/20)
	if (arm and low<=0) or (not arm and low<0):low=1
	return low+int((float(low)*1.4-float(low)+1.0)*float(rng.randi() & 0x7fffffff)/2147483648.0)

static func stage(entry: Dictionary) -> int:
	var maximum:=int(ITEMS[int(entry.item_id)].durability)
	if maximum<1:return 0
	var percent:=int(int(entry.durability)*100/maximum)
	return 0 if percent>=70 else 1 if percent>=50 else 2 if percent>=30 else 3
