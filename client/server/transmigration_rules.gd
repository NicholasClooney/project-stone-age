extends RefCounted
## Pure, inactive stage-three rules. No profile schema, IO, or authority mutation.
## npc_transmigration.c:804–923; exact source and C oracle in
## tools/transmigration_rules_sources.json and audit_transmigration_rules.py.
const STATS := ["vitality", "strength", "toughness", "dexterity"]
const MAX_COUNT := 5
# The existing actor validator bounds each fixed-point base stat at this value.
const MAX_BASE := 100000000

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=low and value<=high

## A missing/unknown positive-count history must not be reconstructed from level.
static func valid_history(count: Variant, equation: Variant) -> bool:
	if not integer(count,0,MAX_COUNT) or not integer(equation,0,2147483647):return false
	var n := int(count)
	var q := (int(equation)>>16)&0xffff
	var level_sum := int(equation)&0xffff
	return q<=20*n and level_sum>=80*n and level_sum<=130*n

## C's float operations round to binary32 at each arithmetic/store boundary.
## In Rounding(tmp,1), +0.5 is double, followed by a float return, then float *100.
static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func inherit(base_fixed: Variant, old_equation: Variant, old_level: Variant, new_count: Variant, completed_quests: Variant) -> Dictionary:
	if not integer(new_count,1,MAX_COUNT):return {"ok":false,"reason":"invalid_count"}
	if not valid_history(int(new_count)-1,old_equation):return {"ok":false,"reason":"invalid_history"}
	if not integer(old_level,80,2147483647):return {"ok":false,"reason":"invalid_level"}
	if not integer(completed_quests,0,20):return {"ok":false,"reason":"invalid_quest_count"}
	if not base_fixed is Dictionary or base_fixed.size()!=4:return {"ok":false,"reason":"invalid_base"}
	var total := 0
	for key in STATS:
		if not integer(base_fixed.get(key),0,MAX_BASE):return {"ok":false,"reason":"invalid_base"}
		total+=int(base_fixed[key])
	if total==0:return {"ok":false,"reason":"zero_total"}
	var n := int(new_count)
	var q := ((int(old_equation)>>16)&0xffff)+int(completed_quests)
	var level_sum := (int(old_equation)&0xffff)+mini(int(old_level),130)
	var p := _f32(_f32(float(total))/100.0)
	var quest_term := _f32(float(q)/4.0)
	var level_term := _f32(_f32(float(level_sum)-_f32(float(n)*85.0))/4.0)
	var answer := int(_f32(_f32(_f32(p/12.0)+quest_term)+level_term))
	var inherited := {}
	for key in STATS:
		var ratio := _f32(_f32(float(base_fixed[key]))/_f32(float(total)))
		var tmp := _f32(ratio*_f32(float(answer)))
		inherited[key]=maxi(0,int(_f32(_f32(tmp+0.5)*100.0)))
	return {"ok":true,"new_count":n,"equation":(q<<16)+level_sum,"base_stats":inherited,"stat_points":n*10,"ans":answer}

const QUESTS := [1,2,4,5,8,12,14,15,16,17,19,22,27,30,31,34,35,38,44,45]
const KEEP_END := [69,70,71,72,109,118,122,131,127,158,159]
const KEEP_NOW := [69,70,71,72]
const PRESENTS := [[1377,1380,1379,1378,1381],[1380,1379,1378,1377,1381],[1379,1378,1377,1380,1381],[1378,1377,1380,1379,1381]]
const PRESENT_TEMPLATES := {1377:6,1378:232,1379:244,1380:272,1381:304}
const HOMES := [[1006,15,22],[2006,20,16],[3006,21,16],[4006,14,20]]

static func _events_valid(events: Variant) -> bool:
	if not events is Dictionary:return false
	for key in ["now","ended"]:
		if not events.get(key) is Array or events[key].size()!=6:return false
		for word in events[key]:
			if not integer(word,0,4294967295):return false
	return true

static func _flag(words: Array, event: int) -> bool:
	return (int(words[event/32])&(1<<(event%32)))!=0

static func _set_flag(words: Array, event: int) -> void:
	words[event/32]=int(words[event/32])|(1<<(event%32))

static func quest_count(events: Variant) -> int:
	if not _events_valid(events):return -1
	var result := 0
	for event in QUESTS:
		if _flag(events.ended,event):result+=1
	return result

static func flags_after(events: Variant, new_count: Variant) -> Dictionary:
	if not _events_valid(events):return {"ok":false,"reason":"invalid_events"}
	if not integer(new_count,1,5):return {"ok":false,"reason":"invalid_count"}
	var result := {"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]}
	for event in KEEP_END:
		if _flag(events.ended,event):_set_flag(result.ended,event)
	for event in KEEP_NOW:
		if _flag(events.now,event):_set_flag(result.now,event)
	for event in range(48,48+int(new_count)):_set_flag(result.ended,event)
	return {"ok":true,"events":result}

static func sacrifice_templates(new_count: Variant) -> Array[int]:
	if not integer(new_count,1,5):return []
	if int(new_count)==5:return [693,694,695,696]
	return [692+int(new_count)]

## pets is the full carried array; Session validates its current capacity.
## Species is the existing canonical template identity.
## Explicit UID choice is a project supplement; empty choice keeps C slot order.
static func select_sacrifices(pets: Variant, new_count: Variant, selected_ids: Variant = []) -> Dictionary:
	var required := sacrifice_templates(new_count)
	if required.is_empty():return {"ok":false,"reason":"invalid_count"}
	if not pets is Array or not selected_ids is Array:return {"ok":false,"reason":"invalid_pets"}
	var seen := {}
	for pet in pets:
		if not pet is Dictionary or not pet.get("pet_id") is String or pet.pet_id.is_empty() or seen.has(pet.pet_id):return {"ok":false,"reason":"invalid_pet_uid"}
		seen[pet.pet_id]=true
	var chosen := {}
	for uid in selected_ids:
		if not uid is String or chosen.has(uid) or not seen.has(uid):return {"ok":false,"reason":"invalid_selection"}
		chosen[uid]=true
	if not selected_ids.is_empty() and selected_ids.size()!=required.size():return {"ok":false,"reason":"invalid_selection"}
	var ids := []
	var indices := []
	for template in required:
		var found := -1
		for index in range(pets.size()):
			var pet: Dictionary=pets[index]
			if pet.get("species","")!="original_%d"%template:continue
			if not chosen.is_empty() and not chosen.has(pet.pet_id):continue
			found=index
			break
		if found<0:return {"ok":false,"reason":"missing_sacrifice"}
		indices.append(found)
		ids.append(pets[found].pet_id)
	return {"ok":true,"pet_ids":ids,"indices":indices}

static func reward_for(savepoint_bits: Variant, new_count: Variant) -> Dictionary:
	if not integer(new_count,1,5):return {"ok":false,"reason":"invalid_count"}
	if not integer(savepoint_bits,0,2147483647):return {"ok":false,"reason":"invalid_savepoint"}
	for village in range(4):
		if (int(savepoint_bits)&(1<<village))==0:continue
		var enemy: int=PRESENTS[village][int(new_count)-1]
		var home: Array=HOMES[village]
		return {"ok":true,"enemy_id":enemy,"template_id":PRESENT_TEMPLATES[enemy],"location":{"map_id":home[0],"x":home[1],"y":home[2]},"village_index":village}
	return {"ok":false,"reason":"missing_savepoint"}
