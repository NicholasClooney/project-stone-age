extends RefCounted
## 人物魅力 and 宠物忠诚度, pinned to gmsv. Pure rules; GameSession and
## BattleSession apply them. docs/reverse-engineering/charm-and-loyalty.md.
##
## A pet's loyalty (CHAR_WORKFIXAI) is recomputed from the owner, never stored
## as the truth (char.c:2918-2943 CHAR_complianceParameter):
##   base = min(100, int(owner_level × charm × 1.10 / (pet_level × modai) × 100))
##   loyalty = clamp(int(base + variable_ai × 0.01), 0, 100)
## modai is the species' 忠诚难度 (enemybase column 13, E_T_MODAI; 0 means 100);
## variable_ai is the pet's own earned part in hundredths (CHAR_VARIABLEAI,
## -10000..10000), moved by the events below.
const Progression = preload("res://server/progression.gd")
const CaptureRules = preload("res://server/capture_rules.gd")

const CHARM_START := 60              # char.c:274
const CHARM_MAX := 100               # char.c:5244 CHAR_AddCharm
const CAPTURE_MAX := 60              # char_base.h:43 CHAR_DEFAULTMAXAI
const VARIABLE_MIN := -10000         # char_base.h:45
const VARIABLE_MAX := 10000          # char_base.h:44
const OBEDIENT := 80                 # battle.c:5758, no check at 80 or more
# battle.h:441-457
const CHARM_PLAYER_LEVEL_UP := 2
const CHARM_PLAYER_DEAD := -2
const CHARM_PET_ESCAPE := -1
const AI_PET_LEVEL_UP := 500
const AI_PET_WIN := 1
const AI_PET_GOLD_WIN := 20
const AI_PLAYER_DEAD := -100
const AI_PET_DEAD := -500
## chatmagic.c:1487 (GM petmake) sets CHAR_VARIABLEAI to 10000.
const AI_GM_PET := 10000

## The loyalty an owner of this level and charm sees on this pet.
static func value(owner_level: int, charm: int, pet_level: int, modai: int, variable_ai: int) -> int:
	if modai <= 0: modai = 100
	var ai := int(float(owner_level*charm)*1.10/float(maxi(1,pet_level)*modai)*100.0)
	if ai > 100: ai = 100
	ai = int(float(ai)+float(variable_ai)*0.01)
	return clampi(ai,0,100)

## battle_event.c:3436-3443: a caught pet starts at 0 and, when the owner's
## formula gives more than 60, owes the excess so it starts at 60.
static func capture_variable(owner_level: int, charm: int, pet_level: int, modai: int) -> int:
	var ai := value(owner_level,charm,pet_level,modai,0)
	return (CAPTURE_MAX-ai)*100 if ai > CAPTURE_MAX else 0

static func add_variable(pet: Dictionary, amount: int) -> void:
	pet.variable_ai = clampi(int(pet.get("variable_ai",0))+amount,VARIABLE_MIN,VARIABLE_MAX)

static func add_charm(player: Dictionary, amount: int) -> void:
	player.charm = clampi(int(player.get("charm",CHARM_START))+amount,0,CHARM_MAX)

## Death penalties are halved (integer division) for owners at level 10 or
## less (battle.c:4376 levelflg).
static func death_penalty(amount: int, owner_level: int) -> int:
	return amount/2 if owner_level <= 10 else amount

## The species' modai: stored on the pet at capture, else the imported
## template's (enemybase column 13), else 0 (the formula then uses 100).
static func modai_for(pet: Dictionary) -> int:
	if pet.has("modai"): return int(pet.modai)
	var species := str(pet.get("species",""))
	if CaptureRules.TEMPLATE_IDS.has(species): species = "original_%d" % int(CaptureRules.TEMPLATE_IDS[species])
	elif pet.has("template_id"): species = "original_%d" % int(pet.template_id)
	return int(Progression.species_definition(species).get("modai",0))

## Records the template's modai on a new pet when the catalog has it.
static func stamp_modai(pet: Dictionary) -> void:
	var modai := modai_for(pet)
	if modai > 0: pet.modai = modai

## Recomputes pet.loyalty (the shown and used value) for this owner.
static func refresh(pet: Dictionary, player: Dictionary) -> void:
	pet.loyalty = value(int(player.get("level",1)),int(player.get("charm",CHARM_START)),int(pet.get("level",1)),modai_for(pet),int(pet.get("variable_ai",0)))

## Pets from before these rules get the variable a pet caught at Lv1 by this
## owner and levelled to its current level would have; the developer starter
## pack (which carried loyalty 100) keeps 100 like a GM pet.
static func migrate_pet(pet: Dictionary, player: Dictionary) -> void:
	if pet.has("variable_ai"): return
	if int(pet.get("loyalty",0)) >= 100:
		pet.variable_ai = AI_GM_PET
		return
	var start := capture_variable(int(player.get("level",1)),int(player.get("charm",CHARM_START)),1,modai_for(pet))
	pet.variable_ai = clampi(start+AI_PET_LEVEL_UP*(int(pet.get("level",1))-1),VARIABLE_MIN,VARIABLE_MAX)

## Saves from before charm changed kept a flat 60: credit +2 for every level
## already gained (capped at 100). Deaths before then are not reconstructed.
static func migrate_charm(player: Dictionary) -> void:
	if player.has("charm_rules"): return
	player.charm_rules = 1
	add_charm(player,CHARM_PLAYER_LEVEL_UP*(int(player.get("level",1))-1))

## battle.c:5734 BATTLE_PetLoyalCheck with Rand = RAND(1,100): what a pet of
## this loyalty does with its command.
##   normal         obeys
##   random_target  same command at a random enemy (a guard does nothing)
##   random_action  a random one of its skill slots at a random enemy
##   attack_owner   attacks its owner
##   attack_enemy   attacks a random enemy
##   escape         leaves the battle (and the owner loses 1 charm)
static func check(loyalty: int, roll: int) -> String:
	if loyalty >= 80: return "normal"
	if loyalty >= 70: return "random_target" if roll < 10 else "normal"
	if loyalty >= 60: return "random_target" if roll < 20 else "normal"
	if loyalty >= 50: return "random_target" if roll < 35 else "normal"
	if loyalty >= 40: return "random_target" if roll < 50 else "normal"
	if loyalty >= 20: return "random_action" if roll < 70 else "normal"
	if loyalty >= 10: return "attack_owner" if roll < 80 else "attack_enemy"
	return "attack_owner" if roll < 60 else "escape"
