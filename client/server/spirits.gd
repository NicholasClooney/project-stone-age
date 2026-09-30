extends RefCounted
## 精灵 (magic) and 气力 (MP), ported from the pinned gmsv
## (docs/reverse-engineering/magic-and-mp.md). A 精灵 is not an item of its
## own: an equipment item names one (itemset.txt magicid, "mid") and what it
## costs to cast (magicusemp, "mu"); magic.txt gives the spell. Only the
## healing spirits and 镜子的精灵 are built; the rest of magic.txt is not.

## char.c:275 CHAR_MAXMP = CHAR_MP = 100 at creation; nothing in the pinned
## server raises it (only equipment ITEM_MODIFYMP, which no item here has).
const MAX_MP := 100

## magic_base.h MAGIC_FIELDTYPE: where a spell can be cast.
const FIELD_ALL := 0
const FIELD_BATTLE := 1
const FIELD_MAP := 2
## magic_base.h MAGIC_TARGETTYPE (the ones these spells use).
const TARGET_MYSELF := 0
const TARGET_OTHER := 1
const TARGET_WHOLEOTHERSIDE := 8

## Battle target codes (the original's toNo, as the caster's own screen
## shows the battle): 0 the caster, 1 its pet, 2+2i ally i, 3+2i ally i's
## pet, SIDE the caster's whole side (the original's 20/21, TARGET_SIDE).
const SELF := 0
const OWN_PET := 1
const SIDE := 20

## battle_magic.h: MAGIC_EFFECT_USER on the caster; the healed or revived
## side shows SPR_heal / heal2 / heal3 or SPR_fukkatu1..3 (anim_tbl.h).
const EFFECT_USER := 100600
const EFFECT_HEAL := [100601,100602,100603]
const EFFECT_REVIVE := [100607,100608,100609]

## gmsv data/magic.txt, one row per spell built here: name, comment, the
## function (kind), MAGIC_OPTION (power), MAGIC_FIELD, MAGIC_TARGET and
## MAGIC_TARGET_DEADFLG.
const MAGIC := {
	0:{"name":"治愈的精灵 Lv1","comment":"耐久力回复 80 (自己)","kind":"recovery","power":80,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	1:{"name":"治愈的精灵 Lv2","comment":"耐久力回复 160 (自己)","kind":"recovery","power":160,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	2:{"name":"治愈的精灵 Lv3","comment":"耐久力回复 320 (自己)","kind":"recovery","power":320,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	3:{"name":"治愈的精灵 Lv4","comment":"耐久力回复 480 (自己)","kind":"recovery","power":480,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	4:{"name":"治愈的精灵 Lv5","comment":"耐久力回复 800 (自己)","kind":"recovery","power":800,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	5:{"name":"治愈的精灵 Lv6","comment":"耐久力回复 1160 (自己)","kind":"recovery","power":1160,"field":FIELD_ALL,"target":TARGET_MYSELF,"dead":false},
	10:{"name":"滋润的精灵 Lv1","comment":"耐久力回复 65 (单人)","kind":"recovery","power":65,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	11:{"name":"滋润的精灵 Lv2","comment":"耐久力回复 130 (单人)","kind":"recovery","power":130,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	12:{"name":"滋润的精灵 Lv3","comment":"耐久力回复 260 (单人)","kind":"recovery","power":260,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	13:{"name":"滋润的精灵 Lv4","comment":"耐久力回复 390 (单人)","kind":"recovery","power":390,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	14:{"name":"滋润的精灵 Lv5","comment":"耐久力回复 650 (单人)","kind":"recovery","power":650,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	15:{"name":"滋润的精灵 Lv6","comment":"耐久力回复 880 (单人)","kind":"recovery","power":880,"field":FIELD_ALL,"target":TARGET_OTHER,"dead":false},
	20:{"name":"恩惠的精灵 Lv1","comment":"耐久力回复 50 (一方全体)","kind":"recovery","power":50,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	21:{"name":"恩惠的精灵 Lv2","comment":"耐久力回复 100 (一方全体)","kind":"recovery","power":100,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	22:{"name":"恩惠的精灵 Lv3","comment":"耐久力回复 200 (一方全体)","kind":"recovery","power":200,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	23:{"name":"恩惠的精灵 Lv4","comment":"耐久力回复 300 (一方全体)","kind":"recovery","power":300,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	24:{"name":"恩惠的精灵 Lv5","comment":"耐久力回复 500 (一方全体)","kind":"recovery","power":500,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	25:{"name":"恩惠的精灵 Lv6","comment":"耐久力回复 600 (一方全体)","kind":"recovery","power":600,"field":FIELD_BATTLE,"target":TARGET_WHOLEOTHERSIDE,"dead":false},
	50:{"name":"复活精灵 Lv1","comment":"气绝状态回复 100 (单人)","kind":"ressurect","power":100,"field":FIELD_BATTLE,"target":TARGET_OTHER,"dead":true},
	51:{"name":"复活精灵 Lv2","comment":"气绝状态回复 300 (单人)","kind":"ressurect","power":300,"field":FIELD_BATTLE,"target":TARGET_OTHER,"dead":true},
	52:{"name":"复活精灵 Lv3","comment":"气绝状态回复 500 (单人)","kind":"ressurect","power":500,"field":FIELD_BATTLE,"target":TARGET_OTHER,"dead":true},
	53:{"name":"复活精灵 Lv4","comment":"气绝状态回复 700 (单人)","kind":"ressurect","power":700,"field":FIELD_BATTLE,"target":TARGET_OTHER,"dead":true},
	260:{"name":"镜子的精灵","comment":"攻击反射1次 (单人)","kind":"magic_def","power":0,"field":FIELD_BATTLE,"target":TARGET_OTHER,"dead":false},
}

## gmsv data/itemset.txt rows for the equipment that carries a spirit here:
## item id, graphic, cost, type, level (ITEM_LEVEL, char_item.c:345 refuses
## equipping above the player's level), the stat modifiers, magicid and
## magicusemp. slot: "body" (CHAR_BODY, ITEM_ARMOUR) or "amulet"
## (CHAR_DECORATION, ITEM_AMULET: two amulets are never worn together,
## char_item.c:379). shop: where the pinned server sells it.
const ITEMS := {
	"haru_armor":{"name":"哈鲁Lv1铠2","item_id":1011,"graphic":21027,"price":400,"slot":"body","level":10,"defence":6,"speed":-2,"charm":0,"magic":0,"mp":5,"memo":"防 +6 敏 -2  治愈的精灵 Lv1","shop":"萨姆吉尔的防具店（1001，17,15）"},
	"freya_robe":{"name":"芙雷雅Lv1服2","item_id":1112,"graphic":21009,"price":484,"slot":"body","level":10,"defence":3,"speed":0,"charm":0,"magic":10,"mp":8,"memo":"防 +3  滋润的精灵 Lv1","shop":"卡鲁它那的防具店（4001，18,17）"},
	"teo_robe":{"name":"提欧Lv1服2","item_id":1113,"graphic":21009,"price":528,"slot":"body","level":10,"defence":3,"speed":0,"charm":0,"magic":20,"mp":20,"memo":"防 +3  恩惠的精灵 Lv1","shop":"萨姆吉尔的防具店（1001，17,15）"},
	"koyala_charm":{"name":"柯雅拉Lv1护身符","item_id":1450,"graphic":22017,"price":1000,"slot":"amulet","level":0,"defence":0,"speed":0,"charm":3,"magic":50,"mp":20,"memo":"魅 +3  复活精灵 Lv1","shop":"原版商店不卖 Lv1（Lv2 在 10920，Lv3 在道场的商人 1008）"},
	"mirror_charm":{"name":"美丽尼亚护身符1","item_id":1460,"graphic":22018,"price":4800,"slot":"amulet","level":10,"defence":0,"speed":0,"charm":1,"magic":260,"mp":5,"memo":"魅 +1  镜的精灵","shop":"原版商店不卖"},
}
## The body armour and amulets this build adds (the mirror predates them).
const SPIRIT_ITEMS := ["haru_armor","freya_robe","teo_robe","koyala_charm"]

## char_item.c LACKOFCLASS / CANNOTEQUIP2.
const TOO_WEAK := "能力不足无法装备。"
const SAME_KIND := "无法同时装备两项同种类的物品。"
## Not the original's words: its client only plays the refusal sound
## (se 220) and draws the entry red when 气力 is short (battlemenu.cpp:755).
const NO_MP := "气力不足。"

static func magic_of(item: String) -> Dictionary:
	var entry: Dictionary = ITEMS.get(item,{})
	return MAGIC.get(int(entry.get("magic",-1)),{})

## The spirit an item gives in battle, as battle configs carry it.
static func spirit_entry(item: String) -> Dictionary:
	var entry: Dictionary = ITEMS.get(item,{})
	var magic := magic_of(item)
	if magic.is_empty():return {}
	return {"item":item,"item_name":str(entry.name),"magic":int(entry.magic),"name":str(magic.name),"comment":str(magic.comment),"mp":int(entry.mp),"kind":str(magic.kind),"target":int(magic.target),"field":int(magic.field),"dead":bool(magic.dead),"power":int(magic.power)}

## util.h RAND(x,y): ((x-1)+1+(int)((double)(y-(x-1))*rand()/(RAND_MAX+1.0))),
## evaluated in double as gcc does for the float arguments these callers pass.
## `fraction` is rand()/(RAND_MAX+1.0), in [0, 1).
static func c_rand(x: float, y: float, fraction: float) -> float:
	return (x-1.0)+1.0+float(int((y-(x-1.0))*fraction))

## rand()/(RAND_MAX+1.0) from a seeded generator (glibc RAND_MAX 2^31-1).
static func fraction(rng: RandomNumberGenerator) -> float:
	return float(rng.randi() & 0x7fffffff)/2147483648.0

## battle_magic.c BATTLE_MultiRecovery (BD_KIND_HP, _MAGIC_REHPAI on in the
## pinned version.h, so no GetRecoveryRate and no percent): the heal one
## target gets, before it is split with a mount.
static func battle_heal(power: int, rng: RandomNumberGenerator) -> int:
	return int(c_rand(power*0.9,power*1.1,fraction(rng)))

## Magic_RideGetHP (flg 1): the rider's share in percent, by what each of
## rider and mount is missing.
static func rider_share(hp: int, max_hp: int, pet_hp: int, pet_max_hp: int) -> int:
	var own := max_hp-hp
	var pet := pet_max_hp-pet_hp
	var both := own+pet
	if both<=0:both = 1
	return int((own*100)/both)

## BATTLE_MultiRecovery with a mount: [rider's part, mount's part].
static func split_heal(amount: int, hp: int, max_hp: int, pet_hp: int, pet_max_hp: int) -> Array:
	var own := int((amount*rider_share(hp,max_hp,pet_hp,pet_max_hp))/100)
	return [own,amount-own]

## BATTLE_MultiRessurect: power 0 is full, else RAND(0.9, 1.1) of it, at least 1.
static func revive_hp(power: int, max_hp: int, rng: RandomNumberGenerator) -> int:
	var amount := max_hp if power==0 else int(c_rand(power*0.9,power*1.1,fraction(rng)))
	return mini(maxi(1,amount),max_hp)

## magic_field.c MAGIC_Recovery_Field / MAGIC_OtherRecovery_Field: the float
## power RAND(0.9, 1.1) of the option, truncated when added.
static func field_heal(power: int, rng: RandomNumberGenerator) -> int:
	return int(c_rand(power*0.9,power*1.1,fraction(rng)))

## MAGIC_Recovery_Battle / MAGIC_Ressurect_Battle: the effect the healed
## side shows for this power.
static func target_effect(kind: String, power: int) -> int:
	if kind=="ressurect":
		if power<=0:return EFFECT_REVIVE[2]
		return EFFECT_REVIVE[0] if power<=100 else EFFECT_REVIVE[1] if power<=300 else EFFECT_REVIVE[2]
	return EFFECT_HEAL[0] if power<=100 else EFFECT_HEAL[1] if power<=300 else EFFECT_HEAL[2]

## Whether a target code suits the spirit (MAGIC_isTargetValid plus the
## client's choice: MYSELF only the caster, OTHER one member, the whole side
## only for WHOLEOTHERSIDE; the caster's own side only).
static func target_fits(spirit: Dictionary, code: int) -> bool:
	match int(spirit.get("target",-1)):
		TARGET_MYSELF:return code==SELF
		TARGET_OTHER:return code>=0 and code<=9
		TARGET_WHOLEOTHERSIDE:return code==SIDE
	return false
