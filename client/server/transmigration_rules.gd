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
