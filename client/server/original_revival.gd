extends RefCounted
## itemset.txt:2033; ITEM_useRessurect -> BATTLE_MultiRessurect.
## 101 = OTHER + deadTargetFlag, not 'dead targets only'. Both sides and
## living actors can be selected; a living target still consumes the item.
const Equipment = preload("res://server/original_equipment.gd")
const PET_AI_GAIN := 300 # battle.h AI_FIX_PETRESSURECT
const USER_EFFECT := 100612 # anim_tbl.h SPR_item3
const ITEMS := {2450:{"name":"萨顿家的秘药","power":500,"field":1,"target":101,"level":0}}
static func inventory(profile: Dictionary) -> Array:
	return profile.get("original_instances",[]).filter(func(entry):return ITEMS.has(int(entry.item_id))).duplicate(true)
static func uid(action: String) -> int:
	var raw := action.trim_prefix("revival:")
	return int(raw) if action.begins_with("revival:") and raw.is_valid_int() and int(raw)>0 else -1
static func result_valid(initial: Array, final: Variant) -> bool:
	if not final is Array:return false
	var seen: Array=[]
	for entry in final:
		if not entry is Dictionary or entry not in initial or entry in seen:return false
		seen.append(entry)
	return true
static func settle(profile: Dictionary, initial: Array, final: Array) -> void:
	for entry in initial:
		if entry in final:continue
		for i in range(profile.original_instances.size()):
			if int(profile.original_instances[i].uid)==int(entry.uid):
				Equipment.remove_at(profile,i)
				break
static func hp(power: int, maximum: int, rng: RandomNumberGenerator) -> int:
	return mini(maximum,maxi(1,rng.randi_range(int(power*0.9),int(power*1.1))))

static func can_revive(hp: int, player: bool, pvp: bool) -> bool:
	# battle_magic.c:1600: P_vs_P excludes human actors, not pets.
	return hp<=0 and not (player and pvp)
