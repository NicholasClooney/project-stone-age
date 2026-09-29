extends RefCounted
## 属性 (地水火风) and 属性相克 from gmsv, in the source's order and arithmetic.
## Values are the stored 0..100 points per element, ordered [地, 水, 火, 风]
## like CHAR_EARTHAT..CHAR_WINDAT. See docs/reverse-engineering/elements.md.
const Progression = preload("res://server/progression.gd")
const CaptureRules = preload("res://server/capture_rules.gd")

const NAMES := ["地","水","火","风"]
const NONE := [0,0,0,0]
## Starting 属性 while character creation is deferred: a legal creation
## choice (char.c:110-128), 地10 in the creation screen's points.
const PLAYER_DEFAULT := [100,0,0,0]

# battle_event.c:25-31.
const AJ_SAME := 1.0
const AJ_UP := 1.5
const AJ_DOWN := 0.6
const ATTR_MAX := 100
const D_ATTR := 1.0/(ATTR_MAX*ATTR_MAX)

## BATTLE_AttrCalc (battle_event.c:795-840) as a table: row = attacking
## element, column = defending element, both indexed 0地 1水 2火 3风 4无.
## 地克水, 水克火, 火克风, 风克地; every element beats 无 and 无 loses to all.
const TABLE := [
	[AJ_SAME,AJ_UP,AJ_SAME,AJ_DOWN,AJ_UP],
	[AJ_DOWN,AJ_SAME,AJ_UP,AJ_SAME,AJ_UP],
	[AJ_SAME,AJ_DOWN,AJ_SAME,AJ_UP,AJ_UP],
	[AJ_UP,AJ_SAME,AJ_DOWN,AJ_SAME,AJ_UP],
	[AJ_DOWN,AJ_DOWN,AJ_DOWN,AJ_DOWN,AJ_SAME],
]
# Each source row sums its terms in the order 无, 火, 水, 地, 风.
const TERM_ORDER := [4,2,1,0,3]

## The stored 属性 of a player, pet or enemy. Actors that predate the field
## (old saves, the tutorial species) fall back to their source template.
static func of(actor: Dictionary) -> Array:
	var value: Variant = actor.get("elements")
	if value is Array and value.size()==4:return value.map(func(v):return int(v))
	return template_elements(actor)

static func template_elements(actor: Dictionary) -> Array:
	var species := str(actor.get("species",""))
	if CaptureRules.TEMPLATE_IDS.has(species):species = "original_%d" % CaptureRules.TEMPLATE_IDS[species]
	elif actor.has("template_id") and not species.begins_with("original_"):species = "original_%d" % int(actor.template_id)
	var elements: Variant = Progression.species_definition(species).get("elements")
	if elements is Array and elements.size()==4:return elements.map(func(v):return int(v))
	return NONE.duplicate()

## CHAR_initcharWorkInt (char.c:2848-2853): every positive element writes its
## negative into the opposite one (地<->火, 水<->风), in index order.
static func work(elements: Array) -> Array:
	var result: Array = elements.map(func(v):return int(v))
	for i in range(4):
		if int(result[i])>0:result[(i+2)%4] = -int(result[i])
	return result

## BATTLE_GetAttr tail (battle_event.c:891-899): negatives count as 0 and
## 无属性 is whatever is left of 100.
static func power(work_values: Array) -> Array:
	var result := [0,0,0,0,0]
	var rest := ATTR_MAX
	for i in range(4):
		result[i] = maxi(0,int(work_values[i]))
		rest -= result[i]
	result[4] = maxi(0,rest)
	return result

## The five battle values [地,水,火,风,无] of one fighter. A mounted player
## carries its own precomputed attr_pow (see mounted_power).
static func battle_power(actor: Dictionary) -> Array:
	var value: Variant = actor.get("attr_pow")
	if value is Array and value.size()==5:return value
	return power(work(of(actor)))

## BATTLE_GetAttr with a ride pet (battle_event.c:862-880): without
## _BATTLE_NEWPOWER the rider and mount work values average with C integer
## division. The reference build enables _BATTLE_NEWPOWER (version.h:96),
## which skips the mount, so the "reference" combat profile uses the rider only.
static func mounted_power(rider: Array, mount: Array, profile: String = "classic") -> Array:
	var own := work(rider)
	if profile == "reference":return power(own)
	var ridden := work(mount)
	var average := []
	for i in range(4):average.append(int((int(own[i])+int(ridden[i]))/2))
	return power(average)

## BATTLE_AttrCalc + BATTLE_AttrAdjust (battle_event.c:795-1011) for the
## default field (BATTLE_ATTR_NONE, battle.c:741): each side's field power is
## AJ_BOTTOM, so the final damage *= At/Df factor is exactly 1.
static func adjust(attacker: Array, defender: Array, damage: int) -> int:
	var total := 0
	for my in range(5):
		# At_pow[i] *= damage, then each row is a double sum truncated to int.
		var mine := int(attacker[my])*damage
		var row := 0.0
		for vs in TERM_ORDER:row += float(mine*int(defender[vs]))*float(TABLE[my][vs])
		total += int(row)
	return int(float(total)*D_ATTR)

## The attacker-over-defender multiplier in percent for damage 100, the same
## probe the source makes with BATTLE_AttrAdjust(..., 100).
static func percent(attacker: Array, defender: Array) -> int:
	return adjust(attacker,defender,100)

## Creation rules (char.c:110-128) in stored points: 0..100 in steps of 10,
## a total of 100, at most two elements and never two opposite ones.
static func valid_player(elements: Variant) -> bool:
	if not elements is Array or elements.size()!=4:return false
	var total := 0
	var used := 0
	for value in elements:
		if not (value is int or value is float) or float(value)!=floor(float(value)):return false
		if int(value)<0 or int(value)>100 or int(value)%10!=0:return false
		total += int(value)
		if int(value)>0:used += 1
	if total!=100 or used>2:return false
	return not (int(elements[0])>0 and int(elements[2])>0) and not (int(elements[1])>0 and int(elements[3])>0)

## "地80 水20", or "无" for none.
static func text(elements: Array) -> String:
	var parts := PackedStringArray()
	for i in range(4):
		if int(elements[i])>0:parts.append("%s%d" % [NAMES[i],int(elements[i])])
	return " ".join(parts) if not parts.is_empty() else "无"

## One click of the creation screen's 属性 buttons (login.cpp:3480-3535),
## in creation points (0..10 each, 10 in total). "+" is refused while the
## opposite element has points; with none left it takes one from the first
## other element that has some.
static func creation_step(points: Array, index: int, plus: bool) -> Array:
	var result: Array = points.map(func(v):return int(v))
	var left := 10
	for value in result:left -= int(value)
	if not plus:
		if int(result[index])>0:result[index] -= 1
		return result
	if int(result[(index+2)%4])!=0:return result
	if left>0:
		result[index] += 1
		return result
	for i in range(4):
		if i!=index and int(result[i])>0:
			result[index] += 1
			result[i] -= 1
			break
	return result
