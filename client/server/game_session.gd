extends RefCounted
var world_catalog = preload("res://scripts/world_catalog.gd").new()
## Single-player authority. Prototype rules; original art/data do not imply formula parity.
## 4: 气力 (player.mp) and the 精灵 equipment (equipment, spirit items).
const SAVE_VERSION := 7
const TransmigrationState=preload("res://server/transmigration_state.gd")
const ItemStorage=preload("res://server/item_storage.gd")
const OriginalRevival = preload("res://server/original_revival.gd")
const OriginalEquipment = preload("res://server/original_equipment.gd")
const PET_CAPACITY := 30
const MAX_LEVEL := 120
## Project change: one gold cap for all rewards, including future rebirth.
const MAX_GOLD := 1000000000
const ClassicLuck = preload("res://server/classic_luck.gd")
const Loyalty = preload("res://server/loyalty.gd")
const Progression = preload("res://server/progression.gd")
const Elements = preload("res://server/elements.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
static var _drop_sources: Dictionary = {}
static var _drop_sources_loaded := false
const TroopArt = preload("res://server/troop_art.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const KeepRule = preload("res://scripts/keep_rule.gd")
const ReleaseLog = preload("res://server/release_log.gd")
const Spirits = preload("res://server/spirits.gd")
## 放生记录 entries for pets released since the backend last took them
## (take_release_events); the backend appends them to the log file.
var release_events: Array = []
## 抓宠记录 events for pets that joined since the backend last took them
## ({pet, source}; source is "" for a battle capture, whose source the backend
## knows, or GM发放).
var capture_events: Array = []
## Called synchronously before the new pet joins carried/storage inventory.
var capture_entry_hook: Callable

const MusicLibrary = preload("res://scripts/music_library.gd")
## The spirit equipment sells at its itemset.txt cost (docs/reverse-engineering/magic-and-mp.md).
const ITEM_PRICES := {"potion":10,"club":30,"mirror_charm":4800,"haru_armor":400,"freya_robe":484,"teo_robe":528,"koyala_charm":1000}
const SPECIES := {
	"blue_dragon":{"name":"扬奇洛斯","alias":"蓝人龙","category":"人龙","sprite":100288,"speed":20},
	"golden_tiger":{"name":"金格萨贝鲁","alias":"金虎","category":"老虎","sprite":100330,"speed":29},
	"red_rex":{"name":"巴朵兰恩","alias":"红暴龙","category":"暴龙","sprite":100373,"speed":25},
	"wooli":{"name":"乌力","sprite":100250,"hp":32,"attack":7,"defence":0,"speed":8},
	"wooli_wooli":{"name":"乌力乌力","sprite":100251,"hp":40,"attack":8,"defence":1,"speed":6},
	"woolistan":{"name":"乌力斯坦","sprite":100252,"hp":48,"attack":9,"defence":2,"speed":4},
}
var _profile: Dictionary
var _pending: Dictionary = {}
var _training_preview
## Pets the open battle's live state adds to battle_pets() (pet_id -> reason):
## one switched in, one that already has kill credit, the capture helpers.
## The backend sets it; without it only the battle's start roster counts.
var battle_pets_hook: Callable
var last_error := ""
# Injectable login clock/randomness; unrelated to combat and encounter RNG.
var login_clock: Callable
var login_rng: RandomNumberGenerator
# Temporary solo-training companions; never duplicate persistent rewards or pets.
var clone_squad_enabled := false
## 展示模式 training (server/automation.gd): the four clones bring the player's
## best other pets instead of copies of the active one. Off everywhere else.
var clone_best_others := false
# Optional single-player assist; each battle snapshots this before any rewards.
var experience_multiplier: int = 1:
	set(value):
		experience_multiplier = value if value in [1,2,10,100] else 1

var recovery_rng := RandomNumberGenerator.new()
var original_item_catalog = preload("res://scripts/quest_catalog.gd").new()

func _init(clock: Callable = Callable(), luck_random: RandomNumberGenerator = null) -> void:
	recovery_rng.randomize()
	login_clock=clock
	login_rng=luck_random if luck_random!=null else RandomNumberGenerator.new()
	if luck_random==null:login_rng.randomize()
	_profile = {"version":SAVE_VERSION,"character_id":"100000","profile_id":"samgir-singleplayer-v1","player":{"hp":48,"max_hp":48,"level":1,"xp":0,"gold":20,"attack":10,"defence":0,"speed":10,"stat_points":0,"allocated_stats":{"vitality":0,"strength":0,"toughness":0,"dexterity":0},"elements":Elements.PLAYER_DEFAULT.duplicate()},"inventory":{"potion":2,"club":0,"mirror_charm":0,"haru_armor":0,"freya_robe":0,"teo_robe":0,"koyala_charm":0},"equipped_mirror":false,"equipment":{"body":"","amulet":""},"equipped":false,"travel_pass":false,"pets":[],"pet_storage":[],"next_pet_id":1,"active_pet":-1,"ride_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1,"no_random_encounters":false,"automation_settings":{},"music":MusicLibrary.empty()}
	_profile.merge(ORIGINAL_DEFAULT.duplicate(true),true)

	_profile.player.base_stats = Progression.START.duplicate()
	Progression.refresh(_profile.player)
	_profile.player.hp = _profile.player.max_hp
	_profile.player.mp = Spirits.MAX_MP
	# A new character starts at charm 60 under the charm rules (loyalty.gd).
	_profile.player.charm = Loyalty.CHARM_START
	_profile.player.charm_rules = 1
	TransmigrationState.migrate(_profile)
	_refresh_login_luck()

func _refresh_login_luck() -> void:
	var now:=int(login_clock.call()) if login_clock.is_valid() else int(Time.get_unix_time_from_system())
	ClassicLuck.login(_profile.player,now,login_rng)

# Original item 2422: reusable undersea passage permit, sold for 200 stone.
func buy_travel_pass() -> bool:
	if not _pending.is_empty() or _profile.get("travel_pass",false) or _profile.player.gold < 200:
		return false
	_profile.player.gold -= 200
	_profile.travel_pass = true
	return true

func has_travel_pass() -> bool:
	return _profile.get("travel_pass",false)

const ORIGINAL_DEFAULT := {"original_events":{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]},"original_items":[],"origin":{"village_id":1000,"savepoint_bit":0,"provenance":"prototype_default"},"original_savepoint_bits":1}

static func _original_integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and float(value)==floor(float(value)) and value>=low and value<=high

static func original_state_valid(value: Dictionary) -> bool:
	if not value.get("original_events") is Dictionary:return false
	for kind in ["now","ended"]:
		var words = value.original_events.get(kind)
		if not words is Array or words.size()!=6:return false
		for word in words:
			if not (word is int or word is float) or float(word)!=floor(float(word)) or word<0 or word>4294967295:return false
	var original_limit:=15
	if int(value.get("version",5))>=6:
		original_limit=18
		if value.get("original_equipment") is Dictionary:
			original_limit+=int(value.original_equipment.has("head"))+int(value.original_equipment.has("body"))
	if not value.get("original_items") is Array or value.original_items.size()>original_limit:return false
	for item in value.original_items:
		if not (item is int or item is float) or float(item)!=floor(float(item)) or item<=0 or item>2147483647:return false
	var origin = value.get("origin")
	if not origin is Dictionary or not _original_integer(origin.get("village_id"),1000,4000) or int(origin.village_id) not in [1000,2000,3000,4000] or not _original_integer(origin.get("savepoint_bit"),0,3) or origin.get("provenance") not in ["prototype_default","original_hometown"]:return false
	if int(origin.village_id)!=1000*(int(origin.savepoint_bit)+1):return false
	var bits = value.get("original_savepoint_bits")
	return (bits is int or bits is float) and float(bits)==floor(float(bits)) and bits>=0 and bits<=15

static func bag_slots(profile: Dictionary) -> int:
	var total: int = profile.get("original_items",[]).size()
	for uid in profile.get("original_equipment",{}).values():
		if int(uid)>0:total-=1
	var worn: Array = profile.get("equipment",{}).values()
	if profile.get("equipped",false):worn.append("club")
	if profile.get("equipped_mirror",false):worn.append("mirror_charm")
	for key in profile.get("inventory",{}):
		if int(profile.inventory[key])>(1 if key in worn else 0):total+=1
	return total

func snapshot() -> Dictionary:
	ItemStorage.migrate(_profile)
	OriginalEquipment.migrate(_profile)
	_ensure_pet_ids()
	_sync_stat_points()
	_refresh_loyalty()
	return _profile.duplicate(true)

## Which pets the player has (carried and warehouse) and their levels, without
## copying the profile: changes whenever a pet is caught, stored, withdrawn,
## released or levelled. The find-pet cycle's 最高 − x thresholds follow it.
func pet_signature() -> String:
	var parts: PackedStringArray = []
	for pet in _profile.get("pets",[])+_profile.get("pet_storage",[]):
		parts.append("%s:%d:%d" % [str(pet.get("pet_id","")),int(pet.get("level",0)),int(pet.get("template_id",-1))])
	return ",".join(parts)

func start_battle_config(species: String = "wooli", boss: bool = false, enemy_count: int = 1) -> Dictionary:
	if not SPECIES.has(species) or not _pending.is_empty() or (boss and not can_fight_boss()):
		return {}
	_ensure_pet_ids()
	_refresh_loyalty()
	var enemy: Dictionary = SPECIES[species].duplicate()
	var native := Progression.species_actor(species,3 if boss else 1,int(_profile.next_battle)*7919)
	for key in native:enemy[key] = native[key]
	var player: Dictionary = _profile.player
	var pet: Dictionary = {}
	if _profile.active_pet >= 0:
		pet = _profile.pets[_profile.active_pet].duplicate(true)
	OriginalEquipment.migrate(_profile)
	var armour := equipment_mods()
	var config := {"battle_id":"battle-%d" % _profile.next_battle,"player_hp":player.hp,"player_max_hp":player.max_hp,"player_attack":maxi(1,int(player.attack)+int(armour.attack)),"player_defence":maxi(0,int(player.defence)+int(armour.defence)),"player_speed":maxi(1,int(player.speed)+int(armour.speed)),"enemy_species":species,"enemy_name":("强壮的" if boss else "") + enemy.name,"enemy_sprite":enemy.sprite,"enemy_max_hp":enemy.max_hp,"enemy_attack":enemy.attack,"enemy_defence":enemy.defence,"enemy_speed":enemy.speed,"boss":boss,"pet":pet,"potions":_profile.inventory.potion,"can_capture":_profile.pets.size() < PET_CAPACITY,"reward_xp":60 if boss else 20,"reward_gold":30 if boss else 10}
	config.healing_available=int(_profile.inventory.get("healing_charm",0))>0
	config.mirror_available=bool(_profile.get("equipped_mirror",false))
	# 气力 and the 精灵 of the worn equipment (server/spirits.gd).
	config.player_mp = player_mp()
	config.spirits = spirits()
	config.mirror_mp = 0 if free_spirits() else preload("res://server/battle_session.gd").MIRROR_MP
	config.experience_multiplier = experience_multiplier
	config.ride_pet_index = int(_profile.get("ride_pet",-1))
	config.ride_pet = _profile.pets[config.ride_pet_index].duplicate(true) if config.ride_pet_index>=0 else {}
	config.mounted_sprite = preload("res://scripts/riding.gd").composite(str(_profile.character_id),int(config.ride_pet.get("sprite",0))) if not config.ride_pet.is_empty() else -1
	config.player_level = player.level
	# Reference effective charm/luck; login owns the native-day luck refresh.
	config.player_charm = clampi(int(player.get("charm",60))+int(armour.charm),0,100)
	config.original_revival_items = OriginalRevival.inventory(_profile)
	config.original_revival_budget = config.original_revival_items.size()
	config.original_equipment_items = OriginalEquipment.battle_items(_profile)
	config.player_resistances = OriginalEquipment.resistances(_profile)
	config.equipment_base = {}
	var original_mods:=OriginalEquipment.mods(_profile)
	for stat in OriginalEquipment.STATS:config.equipment_base[stat]=int(player.get(stat,60 if stat=="charm" else 0))+int(armour[stat])-int(original_mods[stat])
	config.equipment_occupied = [int(_profile.original_equipment.head)>0,(not str(_equipment().body).is_empty() or int(_profile.original_equipment.body)>0),bool(_profile.equipped) or int(_profile.original_equipment.arm)>0,bool(_profile.get("equipped_mirror",false)) or not str(_equipment().amulet).is_empty() or int(_profile.original_equipment.amulet)>0,int(_profile.original_equipment.bracelet)>0]
	config.player_luck = int(player.get("luck",0))
	config.player_vital = int(player.base_stats.vitality)/100.0
	config.player_weapon = "axe" if int(_profile.original_equipment.arm)>0 else "club" if _profile.equipped else ""
	config.player_elements = player_elements()
	config.allies = []
	config.ally_pets = []
	if clone_squad_enabled:
		for i in range(4):
			config.allies.append({"name":"分身 %d" % (i+1),"character_id":str(_profile.character_id),"kind":"player","weapon":config.player_weapon,"hp":player.hp,"max_hp":player.max_hp,"attack":config.player_attack,"defence":config.player_defence,"speed":config.player_speed,"level":player.level,"vital":config.player_vital,"luck":0,"elements":config.player_elements.duplicate()})
			var mirror: Dictionary = config.allies.back()
			mirror.mount = config.ride_pet.duplicate(true)
			mirror.mounted_sprite = config.mounted_sprite
			mirror.base_stats = {"attack":mirror.attack,"defence":mirror.defence,"speed":mirror.speed}
			config.ally_pets.append(pet.duplicate(true) if int(_profile.active_pet)!=int(config.ride_pet_index) else {})
		if clone_best_others:
			var others := best_other_pets(4)
			for i in range(4):config.ally_pets[i] = others[i] if i < others.size() else {}
	config.capture_slots = PET_CAPACITY-_profile.pets.size()
	config.pets = _profile.pets.duplicate(true)
	config.active_pet = _profile.active_pet
	config.enemies = []
	for i in range(clampi(enemy_count,1,3)):
		var actor := Progression.species_actor(species,3 if boss else 1,int(_profile.next_battle)*7919+i*97)
		actor.merge({"name":config.enemy_name,"species":species,"sprite":enemy.sprite,"level":3 if boss else 1,"reward_xp":config.reward_xp,"reward_gold":config.reward_gold})
		config.enemies.append(actor)
	_profile.next_battle += 1
	config.protect_pets = protect_pets
	_pending = config.duplicate(true)
	return config

## Virtual copies of the strongest pets besides the active and ridden ones, from
## the party and the warehouse: level, then 三围合, then attack, then the older
## pet. Copies carry a clone id so no reward or change reaches the real pet.
func best_other_pets(count: int) -> Array:
	_ensure_pet_ids()
	var skip := {}
	for index in [int(_profile.active_pet),int(_profile.get("ride_pet",-1))]:
		if index>=0 and index<_profile.pets.size():skip[str(_profile.pets[index].get("pet_id",""))] = true
	var pool: Array = []
	for pet in _profile.pets+_profile.get("pet_storage",[]):
		if not skip.has(str(pet.get("pet_id",""))) and int(pet.get("hp",0))>0:pool.append(pet)
	pool.sort_custom(func(a, b):
		if int(a.level)!=int(b.level):return int(a.level)>int(b.level)
		var sa := int(a.attack)+int(a.defence)+int(a.speed)
		var sb := int(b.attack)+int(b.defence)+int(b.speed)
		if sa!=sb:return sa>sb
		if int(a.attack)!=int(b.attack):return int(a.attack)>int(b.attack)
		return str(a.pet_id).naturalnocasecmp_to(str(b.pet_id))<0)
	var result: Array = []
	for pet in pool.slice(0,count):
		var copy: Dictionary = pet.duplicate(true)
		copy.pet_id = "clone-of-"+str(pet.pet_id)
		result.append(copy)
	return result

## Forgets a battle config that was built but never opened (the hunt's
## battle forecast refused a mixed troop: server/battle_forecast.gd).
func cancel_pending_battle(battle_id: String) -> void:
	if str(_pending.get("battle_id",""))==battle_id:_pending.clear()

## Independent authority-only random stream. Decimal strings preserve all
## 64 bits through JSON. Optional in existing v6 saves; no SaveVersion bump.
func training_borrow_rng() -> Dictionary:
	return _profile.get("training_borrow_rng",{}).duplicate(true)

func set_training_borrow_rng(value: Dictionary) -> bool:
	if not preload("res://server/training_borrow.gd").valid_rng(value):return false
	_profile.training_borrow_rng=value.duplicate(true)
	return true

## Pure forecast config: actual authority rules and roster, no pending record,
## battle id allocation, loyalty mutation or reward in the live session.
func preview_wild_battle_config(troop: Dictionary) -> Dictionary:
	if _training_preview==null:_training_preview=get_script().new()
	var preview=_training_preview
	preview._pending.clear()
	preview.world_catalog=world_catalog
	preview._profile=_profile.duplicate(true)
	preview.clone_squad_enabled=clone_squad_enabled
	preview.clone_best_others=clone_best_others
	preview.experience_multiplier=experience_multiplier
	preview.protect_pets=protect_pets
	return preview.start_wild_battle_config(troop)

func start_wild_battle_config(troop: Dictionary, clear_target: int = -1, capture_only: bool = false) -> Dictionary:
	if not _pending.is_empty() or not troop.get("enemies") is Array:return {}
	if capture_only and _profile.pets.size()>=PET_CAPACITY and not storage_capture_room(1):return {}
	var enemies: Array = troop.enemies.duplicate(true)
	if enemies.is_empty() or enemies.size()>10:return {}
	for enemy in enemies:
		if not enemy is Dictionary:return {}
		enemy.xp = 0
		var definition: Dictionary = Progression.species_definition(str(enemy.get("species","")))
		if definition.is_empty() or not _wild_actor_valid(enemy):return {}
		if int(enemy.get("sprite",-1))!=int(definition.get("sprite",-2)):return {}
		if not enemy.get("can_capture") is bool:return {}
		if not _integer(enemy.get("reward_xp"),0,1000000000) or not _integer(enemy.get("reward_gold"),0,1000000000):return {}
		if not enemy.get("name") is String or enemy.name.is_empty():return {}
		if not _generated_drops_valid(enemy):return {}
		if not enemy.has("growth_weights") or not enemy.has("base_stats"):return {}
	var previous_clone := clone_squad_enabled
	if clear_target>=0:clone_squad_enabled = true
	var config := start_battle_config()
	clone_squad_enabled = previous_clone
	if config.is_empty():return {}
	if clear_target>=0:
		if clear_target>=enemies.size() or int(enemies[clear_target].level)!=1:
			cancel_pending_battle(str(config.battle_id));return {}
		config.clear_capture_target = clear_target
		config.active_pet = -1
		config.pet = {}
		config.ally_pets = [{},{},{},{}]
	var first: Dictionary = enemies[0]
	config.enemies = enemies
	config.enemy_species = first.species
	config.enemy_name = first.name
	config.enemy_sprite = first.sprite
	for field in ["max_hp","attack","defence","speed"]:config["enemy_"+field] = first[field]
	config.reward_xp = first.reward_xp
	config.reward_gold = first.reward_gold
	config.source_encounter = true
	if capture_only:
		config.capture_only = true
		config.capture_destination = "storage" if _profile.pets.size()>=PET_CAPACITY else "carried"
		config.can_capture = true
		config.capture_slots = 1
	# Pinned gmsv setup.cf BATTLEGOLD=10; battle.c BATTLE_GetExp pays
	# once for the player before level-up, not once per defeated enemy.
	config.battle_gold = int(_profile.player.level)*10
	config.area_id = int(troop.get("area_id",-1))
	config.group_id = int(troop.get("group_id",-1))
	if troop.has("training_borrow"):config.training_borrow=troop.training_borrow.duplicate(true)
	config.protect_pets = protect_pets
	_pending = config.duplicate(true)
	return config

## LAN phase 4a (server/party_battle_session.gd): the open battle is a party
## battle. `enemies` are the shared troop; without them (the leader) the
## pending battle's own troop stays. A member gets its own pending record
## (its own battle id, so its completed_battles never collide with another
## player's), built from its own profile like a solo battle, so shops,
## stores and saves are refused until its settlement. Captures are refused in
## 4a. Returns the config ({} when a battle is already pending for a member).
func start_party_config(party_battle_id: String, enemies: Array = [], battle_gold: bool = false) -> Dictionary:
	var config: Dictionary
	if enemies.is_empty():
		if _pending.is_empty():return {}
		config = _pending.duplicate(true)
	else:
		if not _pending.is_empty():return {}
		config = start_battle_config()
		if config.is_empty():return {}
		config.enemies = enemies.duplicate(true)
		var first: Dictionary = enemies[0]
		config.enemy_species = str(first.get("species",config.enemy_species))
		config.enemy_name = str(first.get("name",config.enemy_name))
		config.enemy_sprite = int(first.get("sprite",config.enemy_sprite))
		config.source_encounter = true
		if battle_gold:config.battle_gold = int(_profile.player.level)*10
	config.allies = []
	config.ally_pets = []
	config.can_capture = false
	config.capture_slots = 0
	config.erase("capture_only")
	config.party = true
	config.party_battle_id = party_battle_id
	config.protect_pets = protect_pets
	_pending = config.duplicate(true)
	return config

func apply_battle_result(result: Dictionary, party_drop_claims: Array = []) -> bool:
	if _pending.is_empty() or result.get("active",true) or result.get("battle_id","") != _pending.battle_id:
		return false
	var outcome: String = result.get("outcome","")
	if outcome not in ["win","captured","escaped","defeat"]:
		return false
	var id: String = _pending.battle_id
	if id in _profile.completed_battles:
		return false
	var revival_result = result.get("original_revival_items",[] if _pending.get("original_revival_items",[]).is_empty() else null)
	if not OriginalRevival.result_valid(_pending.get("original_revival_items",[]),revival_result):return false
	var equipment_result = result.get("original_equipment_items",[] if _pending.get("original_equipment_items",[]).is_empty() else null)
	if not OriginalEquipment.result_valid(_pending.get("original_equipment_items",[]),equipment_result):return false
	var hp := int(result.get("player_hp",-1))
	var potions := int(result.get("potions",-1))
	if hp < 0 or hp > _profile.player.max_hp or potions < 0 or potions > _pending.potions:
		return false
	# 气力 is only spent in a battle (nothing there restores it).
	var mp_start := int(_pending.get("player_mp",player_mp()))
	var mp := int(result.get("player_mp",mp_start))
	if mp < 0 or mp > mp_start:return false
	var captures: Array = result.get("captured_species_list",[])
	var enemies: Array = result.get("enemies",[])
	var capture_only := bool(_pending.get("capture_only",false)) and not bool(_pending.get("party",false))
	# Missing destination belongs to a legacy frozen direct-storage battle.
	var direct_storage := capture_only and str(_pending.get("capture_destination","storage"))=="storage"
	if enemies.size() != _pending.enemies.size():return false
	if direct_storage:
		if captures.size()>int(_pending.get("capture_slots",0)) or not storage_capture_room(captures.size()):return false
	else:
		if _profile.pets.size()+captures.size()>PET_CAPACITY:
			if capture_only:last_error = "随身已满，只抓不练已停：请腾出位置后继续"
			return false
		if capture_only and captures.size()>int(_pending.get("capture_slots",0)):return false
	# The result's pet indices are slots of the battle's start roster. Pets that
	# are not in the battle can be stored, withdrawn or released meanwhile, so
	# each slot is matched to the party by pet id (-1: no longer carried).
	var roster: Array = _pending.get("pets",_profile.pets)
	var slots := _battle_slots()
	var verified_captures := []
	var captured_actors := []
	var earned_xp := 0
	var multiplier := int(_pending.get("experience_multiplier",1))
	# A party battle's experience comes worked out per member (party_xp:
	# 队伍共享经验 or the original's kill credit, level gap and multiplier
	# already applied); the enemies still pay their gold as in a solo battle.
	var party := bool(_pending.get("party",false))
	var earned_gold := 0
	var remaining := 0
	var pet_rewards: Array = []
	pet_rewards.resize(roster.size())
	pet_rewards.fill(0)
	for i in range(enemies.size()):
		var foe: Dictionary = enemies[i]
		var original: Dictionary = _pending.enemies[i]
		if not _integer(foe.get("hp"),0,original.max_hp) or foe.get("species") != original.species:return false
		if foe.get("captured",false):
			if _pending.boss or not _pending.can_capture or not original.get("can_capture",true) or foe.hp != 0:return false
			verified_captures.append(original.species)
			if capture_only and int(original.get("level",0))!=1:return false
			captured_actors.append(original.duplicate(true))
		elif foe.hp == 0:
			var enemy_xp := 0 if party else int(original.reward_xp)*multiplier
			earned_xp += enemy_xp
			earned_gold += int(original.reward_gold)
			var recipient = foe.get("defeated_by_pet_index",-1)
			if not _integer(recipient,-1,roster.size()-1):return false
			if int(recipient)>=0:pet_rewards[int(recipient)] += enemy_xp
			var ridden = foe.get("defeated_with_ride_index",-1)
			if not _integer(ridden,-1,roster.size()-1):return false
			if int(ridden)>=0:
				if int(ridden) != int(_pending.get("ride_pet_index",-1)):return false
				if not party:pet_rewards[int(ridden)] += preload("res://scripts/riding.gd").experience(enemy_xp,int(roster[int(ridden)].level),int(original.get("level",1)))
		else:remaining += 1
	if party:
		var shares: Dictionary = result.get("party_xp",{})
		if not _integer(shares.get("player",0),0,1000000000):return false
		earned_xp = int(shares.get("player",0))
		var pet_shares: Array = shares.get("pets",[])
		if pet_shares.size()!=roster.size():return false
		for i in range(pet_shares.size()):
			if not _integer(pet_shares[i],0,1000000000):return false
			pet_rewards[i] = int(pet_shares[i])
	var sorted_captures := captures.duplicate()
	sorted_captures.sort()
	verified_captures.sort()
	if sorted_captures != verified_captures:return false
	if outcome in ["win","captured"] and remaining != 0:return false
	if outcome == "captured" and captures.is_empty():return false
	if (outcome == "defeat" and hp != 0) or (outcome != "defeat" and hp == 0):return false
	var battle_pets: Array = result.get("pets",[])
	if battle_pets.size() != roster.size():return false
	var revival_count:=0
	var revival_budget:int=int(_pending.get("original_revival_budget",_pending.get("original_revival_items",[]).size()))
	for i in range(battle_pets.size()):
		if not _integer(battle_pets[i].get("hp"),0,roster[i].max_hp):return false
		if not _integer(battle_pets[i].get("original_revival_count",0),0,revival_budget):return false
		revival_count+=int(battle_pets[i].get("original_revival_count",0))
	if revival_count>revival_budget:return false
	if not _integer(result.get("active_pet",-1),-1,roster.size()-1):return false
	if not _integer(result.get("pet_escapes",0),0,10):return false
	var start_ride := int(_pending.get("ride_pet_index",_profile.get("ride_pet",-1)))
	var ride_index = result.get("ride_pet",start_ride)
	if not _integer(ride_index,-1,roster.size()-1):return false
	if int(ride_index) not in [-1,start_ride]:return false
	if int(ride_index)>=0 and (int(result.get("active_pet",-1)) == int(ride_index) or int(battle_pets[int(ride_index)].hp)<=0):return false
	# The host supplies party claims separately from the result. Item ids always
	# come from the trusted start record, never result.enemies/generated_drops.
	var claims: Array = party_drop_claims.duplicate(true) if party else _pending.get("loot_claims",[]).duplicate(true)
	if not party and not _pending.has("loot_claims"):
		for i in range(enemies.size()):
			if int(enemies[i].hp)==0 and not bool(enemies[i].get("captured",false)):
				for j in range(_pending.enemies[i].get("generated_drops",[]).size()):claims.append({"enemy":i,"item":j})
	var seen_claims := {}
	var items := []
	for claim in claims:
		if not claim is Dictionary or not _integer(claim.get("enemy"),0,enemies.size()-1):return false
		var index := int(claim.enemy)
		var generated: Array = _pending.enemies[index].get("generated_drops",[])
		if not _integer(claim.get("item"),0,generated.size()-1):return false
		var key := "%d:%d"%[index,int(claim.item)]
		if seen_claims.has(key) or int(enemies[index].hp)!=0 or bool(enemies[index].get("captured",false)):return false
		seen_claims[key] = true
		items.append(int(generated[int(claim.item)]))
	OriginalRevival.settle(_profile,_pending.get("original_revival_items",[]),revival_result)
	OriginalEquipment.settle(_profile,equipment_result)
	_profile.ride_pet = int(slots[int(ride_index)]) if int(ride_index)>=0 else -1
	_profile.player.hp = hp
	_profile.player.mp = mp
	_profile.inventory.potion = potions
	for i in range(battle_pets.size()):
		if int(slots[i])>=0:
			_profile.pets[int(slots[i])].hp = int(battle_pets[i].hp)
			Loyalty.add_variable(_profile.pets[int(slots[i])],int(battle_pets[i].get("original_revival_count",0))*OriginalRevival.PET_AI_GAIN)
	_profile.active_pet = int(slots[int(result.active_pet)]) if int(result.get("active_pet",-1))>=0 else -1
	# The owner a pet caught this battle judged its loyalty by (battle_event.c:3435).
	var owner_level := int(_profile.player.level)
	var owner_charm := clampi(int(_profile.player.get("charm",Loyalty.CHARM_START))+int(equipment_mods().charm),0,100)
	_battle_loyalty(result,enemies,battle_pets,outcome,roster,slots)
	# Rewards per party slot from here on (the result summary reads them so).
	var party_rewards: Array = []
	party_rewards.resize(_profile.pets.size())
	party_rewards.fill(0)
	for i in range(roster.size()):
		if int(slots[i])>=0:party_rewards[int(slots[i])] += int(pet_rewards[i])
	pet_rewards = party_rewards
	if outcome in ["win","captured"]:
		earned_gold += int(_pending.get("battle_gold",0))
		earned_gold = mini(earned_gold,MAX_GOLD-int(_profile.player.gold))
		_profile.player.gold += earned_gold
		var level_before := int(_profile.player.level)
		_gain_xp(_profile.player,earned_xp)
		# battle.c:3175: +2 charm once for a battle that levels the player up.
		if int(_profile.player.level)>level_before:Loyalty.add_charm(_profile.player,Loyalty.CHARM_PLAYER_LEVEL_UP)
		for i in range(_profile.pets.size()):
			if _profile.pets[i].hp>0 or protect_pets:_gain_xp(_profile.pets[i],int(pet_rewards[i]))
			else:pet_rewards[i] = 0
		if outcome == "win" and _profile.quest.accepted and not _profile.quest.claimed:
			if _pending.boss:
				_profile.quest.boss_defeated = true
			else:
				_profile.quest.wins += 1
	if outcome not in ["win","captured"]:
		earned_xp = 0
		earned_gold = 0
		pet_rewards.fill(0)
	result.drop_summary = []
	# Minimum wood path: normal surviving victory. Multi-enemy escape profits
	# remain outside this implementation (original BATTLE_Stop is different).
	if outcome=="win" and hp>0:
		for item in items:
			var received := bag_slots(_profile)<15
			if received:OriginalEquipment.add(_profile,item)
			result.drop_summary.append({"item_id":item,"received":received})
	result.experience_multiplier = multiplier
	result.xp = earned_xp
	result.gold = earned_gold
	result.pet_reward_xp = pet_rewards
	for original in captured_actors:
		var captured: Dictionary
		if _pending.get("source_encounter",false):
			# Capture keeps the actual wild animal, including caught level and rolls.
			captured = original.duplicate(true)
			for field in ["reward_xp","reward_gold","captured","defeated_by_pet_index","defeated_with_ride_index","generated_drops","generated_drop_slots","source_wait_only"]:captured.erase(field)
			captured.hp = captured.max_hp
			captured.xp = 0
			captured.skill_unlocked = false
			captured.learned_skills = []
		else:
			var species: String = original.species
			var base: Dictionary = SPECIES[species]
			captured = {"species":species,"name":base.name,"sprite":base.sprite,"level":1,"xp":0,"skill_unlocked":false}
			var native := Progression.species_actor(species,1,int(_profile.next_battle)*7919+_profile.pets.size()*97)
			captured.merge(native)
		captured.original_end_event = 0
		_assign_pet_id(captured)
		Loyalty.stamp_modai(captured)
		captured.variable_ai = Loyalty.capture_variable(owner_level,owner_charm,int(captured.level),Loyalty.modai_for(captured))
		if capture_only:
			captured.capture_only = true
			captured.capture_only_untrained = true
			captured.capture_destination = "storage" if direct_storage else "carried"
			captured.capture_destination_reason = "full_auto_store" if direct_storage and _pending.has("capture_destination") else ("legacy_storage" if direct_storage else "carried_room")
		_record_capture(captured,"")
		if direct_storage:_profile.pet_storage.append(captured)
		else:
			_profile.pets.append(captured)
			if _profile.pets.size() == 1:_profile.active_pet = 0
	if outcome == "defeat" and party and bool(result.get("party_stay",false)):
		# The party won without this fallen member: as battle.c BATTLE_Exit,
		# it gets up with 1 HP where it stands (so do its fallen pets), keeps
		# its place in the party, and earns nothing (BATTLE_GetExpGold).
		_profile.player.hp = 1
		for pet in _profile.pets:
			if int(pet.hp)<=0:pet.hp = 1
	elif outcome == "defeat":
		_recover()
		_profile.location = {"map_id":1000,"x":80,"y":90}
	if result.get("gm_escape",false):_profile.gm_modified=true
	_profile.completed_battles.append(id)
	# Monotonic IDs plus a bounded replay log keep save size bounded.
	if _profile.completed_battles.size() > 128:
		_profile.completed_battles.pop_front()
	_pending.clear()
	_refresh_loyalty()
	return true

## Charm and loyalty the battle changed, before experience and level-ups
## (docs/reverse-engineering/charm-and-loyalty.md): every kill while a pet is
## out (+0.01, +0.2 for a higher-level enemy, battle.c:4795), a pet that fell
## (-5, battle.c:4405), the owner falling (charm -2 and the out pet -1,
## battle.c:4379) and a pet that left in disobedience (charm -1,
## battle_event.c:4729). Death penalties halve at owner level 10 or less.
## Roster indices are battle slots; slots maps them to the party (-1: gone).
func _battle_loyalty(result: Dictionary, enemies: Array, battle_pets: Array, outcome: String, roster: Array, slots: Array) -> void:
	var player: Dictionary = _profile.player
	var level := int(player.level)
	for i in range(enemies.size()):
		var foe: Dictionary = enemies[i]
		if foe.get("captured",false) or int(foe.hp)!=0:continue
		var index := int(foe.get("defeated_by_pet_index",-1))
		if index<0 or int(slots[index])<0:continue
		var pet: Dictionary = _profile.pets[int(slots[index])]
		Loyalty.add_variable(pet,Loyalty.AI_PET_GOLD_WIN if int(_pending.enemies[i].get("level",1))>int(pet.level) else Loyalty.AI_PET_WIN)
	for i in range(mini(battle_pets.size(),roster.size())):
		# A mount is not a battle entry: its fall is no pet death (battle.c:4389).
		if i==int(_pending.get("ride_pet_index",-1)) or int(slots[i])<0:continue
		if int(roster[i].get("hp",0))>0 and int(battle_pets[i].hp)==0 and not protect_pets:
			Loyalty.add_variable(_profile.pets[int(slots[i])],Loyalty.death_penalty(Loyalty.AI_PET_DEAD,level))
	if outcome=="defeat":
		Loyalty.add_charm(player,Loyalty.death_penalty(Loyalty.CHARM_PLAYER_DEAD,level))
		if int(_profile.active_pet)>=0:
			Loyalty.add_variable(_profile.pets[int(_profile.active_pet)],Loyalty.death_penalty(Loyalty.AI_PLAYER_DEAD,level))
	Loyalty.add_charm(player,Loyalty.CHARM_PET_ESCAPE*int(result.get("pet_escapes",0)))

## Every pet's loyalty follows its owner's current level and charm
## (char.c:2918). Pets without variable_ai predate the rules and are migrated
## when the save loads; until then they keep obeying as before.
func _refresh_loyalty() -> void:
	var owner: Dictionary=_profile.player.duplicate()
	owner.charm=clampi(int(owner.get("charm",60))+int(equipment_mods().charm),0,100)
	for pet in _profile.pets+_profile.get("pet_storage",[]):
		if pet.has("variable_ai"):Loyalty.refresh(pet,owner)

func _gain_xp(actor: Dictionary, amount: int) -> void:
	if amount>0 and actor.get("capture_only_untrained",false):actor.capture_only_untrained = false
	actor.xp += amount
	while actor.level < MAX_LEVEL and actor.xp >= actor.level * 30:
		actor.xp -= actor.level * 30
		actor.level += 1
		if actor.has("skill_unlocked"):
			Progression.migrate_pet(actor,int(actor.sprite))
			Progression.grow_pet(actor,int(actor.level))
			actor.skill_unlocked = not actor.get("learned_skills",[]).is_empty()
			# battle.c:3224 AI_FIX_PETLEVELUP: +5 loyalty per level.
			if actor.has("variable_ai"):Loyalty.add_variable(actor,Loyalty.AI_PET_LEVEL_UP)
		else:
			# battle.c:3173 defaults to 3 skill-up points per level.
			actor.stat_points += 3
		actor.hp = actor.max_hp
	# Excess assisted XP cannot grow past the supported level or overflow saves.
	if actor.level >= MAX_LEVEL:actor.xp = 0

func buy_item(item: String) -> bool:
	if not _pending.is_empty() or not ITEM_PRICES.has(item) or _profile.player.gold < ITEM_PRICES[item] or int(_profile.inventory.get(item,0)) >= 99:
		return false
	var candidate := _profile.duplicate(true)
	candidate.inventory[item]=int(candidate.inventory.get(item,0))+1
	if bag_slots(candidate)>15:return false
	_profile.player.gold -= ITEM_PRICES[item]
	_profile.inventory[item] = int(_profile.inventory.get(item,0))+1
	return true

func sell_item(item: String) -> bool:
	if not _pending.is_empty() or not ITEM_PRICES.has(item) or int(_profile.inventory.get(item,0)) <= 0 or ((item == "club" and _profile.equipped and _profile.inventory.club == 1) or (item=="mirror_charm" and _profile.get("equipped_mirror",false) and _profile.inventory.mirror_charm==1)):
		return false
	# The worn copy of a piece of spirit equipment cannot be sold.
	if item in Spirits.SPIRIT_ITEMS and item in worn_items() and int(_profile.inventory.get(item,0))==1:return false
	_profile.inventory[item] -= 1
	_profile.player.gold += int(ITEM_PRICES[item] / 2)
	return true

func use_item(item: Variant = "potion", pet_id: Variant = "") -> bool:
	last_error=""
	last_note=""
	if not item is String or not pet_id is String:last_error="无效道具或目标。";return false
	if not _pending.is_empty():last_error="野外道具不能在战斗中使用；复活秘药请从战斗道具菜单选择。";return false
	if item=="original_2450":last_error="萨顿家的秘药只能在战斗道具菜单使用。";return false
	if item=="original_2401":return _use_original_herb(str(pet_id))
	if item!="potion" or not str(pet_id).is_empty() or _profile.inventory.potion<=0 or _profile.player.hp>=_profile.player.max_hp:return false
	_profile.inventory.potion-=1
	_profile.player.hp=mini(_profile.player.max_hp,_profile.player.hp+30)
	return true

func _use_original_herb(pet_id: String) -> bool:
	var item: Dictionary=original_item_catalog.items.get("2401",{})
	var use: Dictionary=item.get("use",{})
	if str(use.get("kind",""))!="hp_recovery" or not use.get("field_supported",false):last_error="原香草使用资料尚未导入。";return false
	if int(_profile.player.hp)<=0:last_error="施药者已经死亡，不能使用道具。";return false
	if not 2401 in _profile.original_items:last_error="没有哈罗的香草。";return false
	var target: Dictionary=_profile.player
	if not pet_id.is_empty():
		target={}
		for pet in _profile.pets:
			if str(pet.pet_id)==pet_id:target=pet;break
		if target.is_empty():last_error="目标宠物不在随身队伍。";return false
	# ITEM_useRecovery_Field: a nominal 体100 rolls 90..110; even a
	# full or zero-HP target is accepted. The dead owner cannot use it.
	var power := recovery_rng.randi_range(int(use.roll_min),int(use.roll_max))
	var before := int(target.hp)
	target.hp=clampi(before+power,1,int(target.max_hp))
	OriginalEquipment.remove(_profile,2401)
	last_note="%s耐久力回复%d，消耗一份哈罗的香草。"%["自己" if pet_id.is_empty() else str(target.name),int(target.hp)-before]
	return true

func equip_item(item: String = "club") -> bool:
	var before := _profile.duplicate(true)
	if not _equip_item(item):return false
	if bag_slots(_profile)>15 and bag_slots(_profile)>bag_slots(before):
		_profile=before
		last_error="道具栏已满。"
		return false
	return true

func _equip_item(item: String) -> bool:
	last_error = ""
	OriginalEquipment.migrate(_profile)
	if item.begins_with("original:"):return _toggle_original_item(item.trim_prefix("original:"))
	if not _pending.is_empty() or item not in ["club","mirror_charm"]+Spirits.SPIRIT_ITEMS or int(_profile.inventory.get(item,0))<=0:
		return false
	if item in Spirits.SPIRIT_ITEMS:return _toggle_spirit_item(item)
	if item=="mirror_charm":
		# Both are ITEM_AMULET: char_item.c:379 never wears two together.
		if not bool(_profile.get("equipped_mirror",false)) and (not str(_equipment().amulet).is_empty() or int(_profile.original_equipment.amulet)>0):
			last_error = Spirits.SAME_KIND
			return false
		_profile.equipped_mirror=not bool(_profile.get("equipped_mirror",false))
	else:
		if not _profile.equipped:_profile.original_equipment.arm=0
		_profile.equipped = not _profile.equipped
	return true

## The command addresses one owned instance, never an item-id copy.
func _toggle_original_item(raw_uid: String) -> bool:
	if not _pending.is_empty() or not raw_uid.is_valid_int():return false
	var uid:=int(raw_uid)
	for entry in _profile.original_instances:
		if int(entry.uid)!=uid:continue
		var id:=int(entry.item_id)
		if not OriginalEquipment.ITEMS.has(id):return false
		var data: Dictionary=OriginalEquipment.ITEMS[id]
		var slot:=str(data.slot)
		if int(_profile.original_equipment[slot])==uid:
			_profile.original_equipment[slot]=0
			return true
		if int(_profile.player.level)<int(data.level):
			last_error=Spirits.TOO_WEAK
			return false
		if (slot=="bracelet" and int(_profile.original_equipment.bracelet)>0) or (slot=="amulet" and (int(_profile.original_equipment.amulet)>0 or bool(_profile.get("equipped_mirror",false)) or not str(_equipment().amulet).is_empty())):
			last_error=Spirits.SAME_KIND
			return false
		_profile.original_equipment[slot]=uid
		if slot=="arm":_profile.equipped=false
		if slot=="body":_equipment().body=""
		return true
	return false

# ---- 气力 and 精灵 (server/spirits.gd) --------------------------------------

## {"body": item or "", "amulet": item or ""}: the worn spirit equipment.
func _equipment() -> Dictionary:
	if not _profile.get("equipment") is Dictionary:_profile.equipment = {"body":"","amulet":""}
	for slot in ["body","amulet"]:
		if not _profile.equipment.has(slot):_profile.equipment[slot] = ""
	return _profile.equipment

## The spirit items worn now (body armour, the amulet).
func worn_items() -> Array:
	var result: Array = []
	for slot in ["body","amulet"]:
		var item := str(_equipment()[slot])
		if not item.is_empty():result.append(item)
	return result

## Wearing a worn item again takes it off; another body armour replaces the
## worn one. char_item.c: ITEM_LEVEL above the player's level is refused
## (能力不足无法装备), and so is a second amulet (the mirror).
func _toggle_spirit_item(item: String) -> bool:
	var data: Dictionary = Spirits.ITEMS[item]
	var slot := str(data.slot)
	var worn := _equipment()
	if str(worn[slot])==item:
		worn[slot] = ""
		return true
	if int(data.level)>int(_profile.player.level):
		last_error = Spirits.TOO_WEAK
		return false
	if slot=="amulet" and (bool(_profile.get("equipped_mirror",false)) or int(_profile.get("original_equipment",{}).get("amulet",0))>0):
		last_error = Spirits.SAME_KIND
		return false
	worn[slot] = item
	if slot=="body":_profile.original_equipment.body=0
	return true

## All reviewed itemset attack/defence/speed/charm modifiers.
func equipment_mods() -> Dictionary:
	var result := OriginalEquipment.mods(_profile)
	result.attack+=4 if _profile.equipped else 0
	for item in worn_items():
		result.defence += int(Spirits.ITEMS[item].defence)
		result.speed += int(Spirits.ITEMS[item].speed)
	return result

## 精灵不耗气力 (设置 → 角色; on unless the player turns it off): a
## convenience some private servers made, not the original. Every 精灵 and
## the 镜子的精灵 then cost 0 气力; 气力 itself is kept as it is.
func free_spirits() -> bool:
	return bool(_profile.get("free_spirits",true))

func set_free_spirits(on: bool) -> bool:
	if not _pending.is_empty():return false
	_profile.free_spirits = on
	return true

func player_mp() -> int:
	return clampi(int(_profile.player.get("mp",Spirits.MAX_MP)),0,Spirits.MAX_MP)

## The spirits the worn equipment gives, by slot (battle configs carry these;
## the original's battle 精灵 menu lists the equipment slots' magic).
func spirits() -> Dictionary:
	var result := {}
	for slot in ["body","amulet"]:
		var item := str(_equipment()[slot])
		if item.is_empty():continue
		var entry := Spirits.spirit_entry(item)
		if entry.is_empty():continue
		if free_spirits():entry.mp = 0
		result[slot] = entry
	return result

## A healing spirit cast outside battle (lssproto_MU_recv -> MAGIC_Use):
## target 0 the player, k the k-th carried pet (Callfromcli_Util_
## getTargetCharaindex; party members are not built). Only FIELD_ALL spells
## (治愈, 滋润); MYSELF heals the caster whatever the target. last_note says
## what happened (magic_field.c's line: 耐久力回复N / X的耐久力回复N).
var last_note := ""
var field_rng := RandomNumberGenerator.new()
func use_spirit(slot: String, target: int = 0) -> bool:
	last_error = ""
	last_note = ""
	if not _pending.is_empty():
		last_error = "战斗中请用战斗里的「精灵」指令。"
		return false
	var spirit: Dictionary = spirits().get(slot,{})
	if spirit.is_empty():
		last_error = "这个位置没有装备精灵。"
		return false
	if str(spirit.kind)!="recovery" or int(spirit.field)==Spirits.FIELD_BATTLE:
		last_error = "%s只能在战斗中使用。" % str(spirit.name)
		return false
	if int(spirit.target)==Spirits.TARGET_OTHER and (target<0 or target>_profile.pets.size()):
		last_error = "请选择自己或随身宠物。"
		return false
	if player_mp()<int(spirit.mp):
		last_error = Spirits.NO_MP
		return false
	_profile.player.mp = player_mp()-int(spirit.mp)
	var on_player: bool = int(spirit.target)==Spirits.TARGET_MYSELF or target==0
	var actor: Dictionary = _profile.player if on_player else _profile.pets[target-1]
	var before := int(actor.hp)
	actor.hp = mini(int(actor.max_hp),before+Spirits.field_heal(int(spirit.power),field_rng))
	var gained := int(actor.hp)-before
	last_note = "耐久力回复%d" % gained if on_player else "%s的耐久力回复%d" % [str(actor.get("name","宠物")),gained]
	return true

## 用精灵补血 between battles (自动练级, a party leader's run for every
## member): FIELD_ALL healing 精灵 on the player, then on the carried pets
## in `pet_indices` (the battle pet, the mount), while one is at or below
## `line` percent and the 气力 lasts. Returns whether anything was cast.
func spirit_heal_to_line(line: int, pet_indices: Array = []) -> bool:
	var cast := false
	for _guard in range(200):
		var done := false
		var own := _field_spirit([Spirits.TARGET_MYSELF,Spirits.TARGET_OTHER])
		if _below_line(_profile.player,line) and not own.is_empty():
			done = use_spirit(own,0)
		else:
			var other := _field_spirit([Spirits.TARGET_OTHER])
			for index in pet_indices:
				if other.is_empty() or done:break
				if int(index)>=0 and int(index)<_profile.pets.size() and _below_line(_profile.pets[int(index)],line):done = use_spirit(other,int(index)+1)
		if not done:break
		cast = true
	return cast

## The slot of a worn FIELD_ALL healing spirit with one of `targets` whose
## 气力 the player has ("" when none).
func _field_spirit(targets: Array) -> String:
	var worn := spirits()
	for target in targets:
		for slot in worn:
			var spirit: Dictionary = worn[slot]
			if str(spirit.kind)=="recovery" and int(spirit.field)!=Spirits.FIELD_BATTLE and int(spirit.target)==int(target) and int(spirit.mp)<=player_mp():return str(slot)
	return ""

static func _below_line(actor: Dictionary, line: int) -> bool:
	return int(actor.hp)>0 and int(actor.hp)<int(actor.max_hp) and int(actor.hp)*100<=int(actor.max_hp)*line

## Developer grant: one of each piece of spirit equipment and full 气力.
func gm_grant_spirits() -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能发放装备。")
	for item in Spirits.SPIRIT_ITEMS:_profile.inventory[item] = maxi(1,int(_profile.inventory.get(item,0)))
	_profile.player.mp = Spirits.MAX_MP
	_gm_mark(_profile.player)
	return true

# Single-player convenience grant, once per profile; loaded game writes normally.
func grant_pet_care_items() -> bool:
	if not _pending.is_empty() or _profile.get("pet_care_granted",false):return false
	_profile.inventory.healing_charm=maxi(1,int(_profile.inventory.get("healing_charm",0)))
	_profile.inventory.mirror_charm=maxi(1,int(_profile.inventory.get("mirror_charm",0)))
	OriginalEquipment.migrate(_profile)
	if int(_profile.original_equipment.amulet)==0 and str(_equipment().amulet).is_empty():_profile.equipped_mirror=true
	_profile.pet_care_granted=true
	return true

func heal_carried_pets() -> bool:
	if not _pending.is_empty() or int(_profile.inventory.get("healing_charm",0))<=0:return false
	var changed:=false
	for pet in _profile.pets:
		if int(pet.hp)>0 and int(pet.hp)<int(pet.max_hp):
			pet.hp=pet.max_hp
			changed=true
	return changed

## 练级保护 (training.protect, not original), set by the automation runner for
## the battles it fights: a carried pet that falls loses no loyalty and still
## earns its experience, and restore_carried_pets brings every carried pet
## back to full HP between battles.
var protect_pets := false

func restore_carried_pets() -> bool:
	if not _pending.is_empty():return false
	var changed:=false
	for pet in _profile.pets:
		if int(pet.hp)<int(pet.max_hp):
			pet.hp=pet.max_hp
			changed=true
	return changed

## Brings a fallen carried pet back to full HP between battles (后台搜宠's
## training; not an original rule). False while a battle is pending.
func revive_carried_pet(pet_id: String) -> bool:
	if not _pending.is_empty():return false
	for pet in _profile.pets:
		if str(pet.get("pet_id",""))==pet_id and int(pet.hp)<=0:
			pet.hp=pet.max_hp
			return true
	return false

## 休息 at the villager: NPC_HealerAllHeal (npc_healer.c) restores 耐久力
## and 气力, and the pets. A defeat (_recover alone) leaves 气力 as it was.
func heal() -> bool:
	if not _pending.is_empty():
		return false
	_recover()
	_profile.player.mp = Spirits.MAX_MP
	return true

func _recover() -> void:
	_profile.player.hp = _profile.player.max_hp
	for pet in _profile.pets:
		pet.hp = pet.max_hp


# Stable identity distinguishes same-name pets across carried and warehouse lists.
static func original_pet_event(pet: Dictionary) -> int:
	if pet.has("original_end_event"):return int(pet.original_end_event)
	return 0 if int(pet.get("source_enemy_id",-1))>0 and str(pet.get("species","")).begins_with("original_") else 1

func _assign_pet_id(pet: Dictionary) -> void:
	if not pet.has("favorite"):pet.favorite=false
	pet.pet_id="pet-%d"%int(_profile.get("next_pet_id",1))
	_profile.next_pet_id=int(_profile.get("next_pet_id",1))+1

func _ensure_pet_ids() -> void:
	if not _profile.has("pet_storage"):_profile.pet_storage=[]
	var next:=int(_profile.get("next_pet_id",1))
	for pet in _profile.pets+_profile.pet_storage:
		if pet.has("pet_id"):next=maxi(next,int(str(pet.pet_id).trim_prefix("pet-"))+1)
	_profile.next_pet_id=next
	for pet in _profile.pets+_profile.pet_storage:
		if not pet.has("original_end_event"):pet.original_end_event=original_pet_event(pet)
		if not pet.has("pet_id"):_assign_pet_id(pet)
		if not pet.has("favorite"):pet.favorite=false

func _valid_pet_ids(profile: Dictionary) -> bool:
	var modern:=int(profile.version)>=3
	if modern and (not profile.has("pet_storage") or not profile.has("next_pet_id")):return false
	var seen:={}
	var largest:=0
	for pet in profile.pets+profile.get("pet_storage",[]):
		if not pet is Dictionary:return false
		if pet.has("favorite") and not pet.favorite is bool:return false
		for flag in ["auto_reject","auto_hunt","auto_qualified"]:
			if pet.has(flag) and not pet[flag] is bool:return false
		if not pet.has("pet_id"):
			if modern:return false
			continue
		if not pet.pet_id is String or not pet.pet_id.begins_with("pet-"):return false
		var suffix:String=pet.pet_id.trim_prefix("pet-")
		if not suffix.is_valid_int() or str(int(suffix))!=suffix or int(suffix)<1 or int(suffix)>=9007199254740991:return false
		if seen.has(pet.pet_id):return false
		seen[pet.pet_id]=true;largest=maxi(largest,int(suffix))
	return not profile.has("next_pet_id") or _integer(profile.next_pet_id,largest+1,9007199254740991)

## Pets taking part in the open battle, pet_id -> reason: the start roster's
## active pet (出战中) and mount (骑乘中), plus what battle_pets_hook adds.
## Empty when no battle is pending. Every other pet can be released, stored or
## withdrawn during the battle (clone squads are copies and never count).
func battle_pets() -> Dictionary:
	if _pending.is_empty():return {}
	var busy := {}
	var roster: Array = _pending.get("pets",[])
	for pair in [[int(_pending.get("active_pet",-1)),"出战中"],[int(_pending.get("ride_pet_index",-1)),"骑乘中"]]:
		if int(pair[0])>=0 and int(pair[0])<roster.size():busy[str(roster[int(pair[0])].get("pet_id",""))] = pair[1]
	if battle_pets_hook.is_valid():busy.merge(battle_pets_hook.call(),false)
	busy.erase("")
	return busy

## Why this pet cannot be changed now ("" when it can): it takes part in the
## open battle. what: the refused action, e.g. 放生 or 存入仓库.
func battle_refusal(pet_id: String, what: String) -> String:
	var reason := str(battle_pets().get(pet_id,""))
	return "" if reason.is_empty() else "这只宠物正在战斗中（%s），战斗结束后才能%s。" % [reason,what]

## Party slots the open battle may still fill with captures (0 without one).
func _capture_room() -> int:
	if bool(_pending.get("capture_only",false)) and str(_pending.get("capture_destination","storage"))=="storage":return 0
	if _pending.is_empty() or bool(_pending.get("boss",false)) or not bool(_pending.get("can_capture",true)):return 0
	return mini(int(_pending.get("capture_slots",0)),_pending.get("enemies",[]).size())

## The party index of each slot of the battle's start roster (-1 when that pet
## was stored or released during the battle).
func _battle_slots() -> Array:
	var slots: Array = []
	if not _pending.has("pets"):
		for i in range(_profile.pets.size()):slots.append(i)
		return slots
	var where := {}
	for i in range(_profile.pets.size()):where[str(_profile.pets[i].get("pet_id",""))] = i
	for pet in _pending.pets:slots.append(int(where.get(str(pet.get("pet_id","")),-1)))
	return slots

## Capacity checks are shared by preflight and settlement, before any mutation.
func storage_capture_room(count: int) -> bool:
	last_error = ""
	var capacity := preload("res://server/server_settings.gd").pet_storage_capacity()
	if capacity>0 and _profile.get("pet_storage",[]).size()+count>capacity:
		last_error = "仓库已满；只抓不练已暂停，请先腾出仓库位置。"
		return false
	return true

static func capture_only_protected(pet: Dictionary) -> bool:
	return bool(pet.get("capture_only",false)) and bool(pet.get("capture_only_untrained",false))

## auto_hunt marks a stored reject the rolling keep may prune; qualified marks
## a qualifying pet (shown as 达标; cleared on retrieval).
func store_pet(index: int, auto_hunt: bool=false, qualified: bool=false) -> bool:
	last_error=""
	if index<0 or index>=_profile.pets.size():last_error="请选择随身宠物。";return false
	last_error=battle_refusal(str(_profile.pets[index].get("pet_id","")),"存入仓库")
	if not last_error.is_empty():return false
	if index==int(_profile.get("ride_pet",-1)):
		last_error="请先取消这只宠物的骑乘状态。";return false
	_ensure_pet_ids()
	if not storage_capture_room(1):return false
	if auto_hunt:_profile.pets[index].auto_hunt=true
	if qualified:_profile.pets[index].auto_qualified=true
	_profile.pet_storage.append(_profile.pets[index])
	if index==int(_profile.active_pet):_profile.active_pet=-1
	_profile.pets.remove_at(index)
	if int(_profile.active_pet)>index:_profile.active_pet-=1
	if int(_profile.get("ride_pet",-1))>index:_profile.ride_pet-=1
	return true

func retrieve_pet(index: int) -> bool:
	last_error=""
	if index<0 or index>=_profile.get("pet_storage",[]).size():last_error="请选择仓库宠物。";return false
	if _profile.pets.size()>=PET_CAPACITY:last_error="随身宠物栏已满，请先存入其他宠物。";return false
	# The open battle may still catch pets into the party: keep room for them.
	if _profile.pets.size()+1+_capture_room()>PET_CAPACITY:last_error="战斗中要为捕捉留出宠物栏空位，战斗结束后再取出。";return false
	_ensure_pet_ids()
	# A retrieved pet belongs to the player again and is never auto-pruned.
	for flag in ["auto_reject","auto_hunt","auto_qualified"]:_profile.pet_storage[index].erase(flag)
	_profile.pets.append(_profile.pet_storage[index])
	_profile.pet_storage.remove_at(index)
	return true

# Rolling keep for pets the auto-hunt stored (flag auto_hunt): per metric in
# order, keep the top N not already kept (e.g. 15 by sum, then 5 by attack) and
# delete the rest. Only pets listed in ids (this run's rejects) are candidates;
# earlier warehouse pets, player-stored and favorite pets are never touched. All-zero keeps prune nothing.
func prune_hunt_pets(template_id: int, keep: Dictionary, ids: Array) -> int:
	last_error=""
	if not _pending.is_empty():last_error="请先结束战斗。";return 0
	var total_keep:=0
	for metric in keep:total_keep+=maxi(0,int(keep[metric]))
	if total_keep<=0:return 0
	var allowed:={}
	for id in ids:allowed[str(id)]=true
	var candidates:=[]
	for pet in _profile.get("pet_storage",[]):
		if not capture_only_protected(pet) and allowed.has(str(pet.get("pet_id",""))) and (pet.get("auto_hunt",false) or pet.get("auto_reject",false)) and not pet.get("favorite",false) and int(pet.get("template_id",-1))==template_id:candidates.append(pet)
	if candidates.size()<=total_keep:return 0
	var kept:={}
	for metric in ["sum","attack","defence","speed"]:
		var quota:=maxi(0,int(keep.get(metric,0)))
		if quota==0:continue
		var ranked:=candidates.filter(func(pet):return not kept.has(str(pet.pet_id)))
		ranked.sort_custom(func(a,b):
			var va:=_hunt_metric(a,metric);var vb:=_hunt_metric(b,metric)
			if va!=vb:return va>vb
			var sa:=_hunt_metric(a,"sum");var sb:=_hunt_metric(b,"sum")
			if sa!=sb:return sa>sb
			if int(a.attack)!=int(b.attack):return int(a.attack)>int(b.attack)
			return str(a.pet_id)<str(b.pet_id))
		for pet in ranked.slice(0,quota):kept[str(pet.pet_id)]=true
	var doomed:={}
	for pet in candidates:
		if not kept.has(str(pet.pet_id)):doomed[str(pet.pet_id)]=true
	# 放生记录: which quotas it missed, beaten by the last pet each quota kept.
	var names:={"sum":"三围合","attack":"攻击","defence":"防御","speed":"敏捷"}
	var missed:=[];var holders:=[]
	for metric in ["sum","attack","defence","speed"]:
		var quota:=maxi(0,int(keep.get(metric,0)))
		if quota==0:continue
		missed.append("%s未进前%d"%[names[metric],quota])
		var last:Dictionary={}
		for pet in candidates:
			if kept.has(str(pet.pet_id)) and (last.is_empty() or _hunt_metric(pet,metric)<_hunt_metric(last,metric)):last=pet
		if not last.is_empty() and not holders.any(func(item):return item.pet_id==str(last.pet_id)):holders.append(ReleaseLog.beater(last))
	for pet in candidates:
		if doomed.has(str(pet.pet_id)):release_events.append(ReleaseLog.entry(pet,"仓库","未达标整理","未达标，"+"、".join(missed),holders))
	_profile.pet_storage=_profile.pet_storage.filter(func(pet):return not doomed.has(str(pet.get("pet_id",""))))
	return doomed.size()

# 保留规则 (scripts/keep_rule.gd), the find-pet cycle's optional tidy: releases
# the pets of this species, carried or stored, that the rule does not keep.
# Favourites, the active pet, the mount and `protected` (pet_id -> reason, e.g.
# the capture helper) always stay. Returns the released pet ids.
func apply_keep_rule(template_id: int, rule: Dictionary, protected: Dictionary = {}, source: String = "自动整理") -> Array:
	last_error=""
	_ensure_pet_ids()
	var kept:=KeepRule.always_kept(_profile)
	kept.merge(protected,true)
	# During a battle its participants stay as well.
	kept.merge(battle_pets(),false)
	var pets:=KeepRule.species_pets(_profile,template_id)
	if source=="自动整理":
		for pet in pets:
			if capture_only_protected(pet):kept[str(pet.pet_id)] = "只抓不练，尚未手动练级"
	var verdict:=KeepRule.evaluate(pets,rule,kept)
	if verdict.release.is_empty():return []
	var summary:=release_pets(verdict.release,source,keep_rule_notes(pets,verdict))
	var skipped:={}
	for entry in summary.get("skipped",[]):skipped[str(entry.id)]=true
	return verdict.release.filter(func(id):return not skipped.has(str(id)))

## 放生记录 notes for a KeepRule verdict: pet_id -> {reason, beaten_by, judged}.
static func keep_rule_notes(pets: Array, verdict: Dictionary) -> Dictionary:
	var by_id:={}
	for pet in pets:by_id[str(pet.get("pet_id",""))]=pet
	var notes:={}
	for id in verdict.release:
		var why:Dictionary=verdict.why.get(id,{})
		var beaten:=[]
		for other in why.get("beaten_by",[]):
			if by_id.has(other):beaten.append(ReleaseLog.beater(by_id[other],verdict.stats[other]))
		notes[id]={"reason":str(why.get("reason","按保留规则放生")),"beaten_by":beaten,"judged":verdict.stats[id]}
	return notes

## The 放生记录 entries collected since the last call.
func take_release_events() -> Array:
	var result:=release_events
	release_events=[]
	return result

## The 抓宠记录 events collected since the last call.

func _record_capture(pet: Dictionary, source: String) -> void:
	var event := {"pet":pet.duplicate(true),"source":source}
	if capture_entry_hook.is_valid():event["entry"] = capture_entry_hook.call(event).duplicate(true)
	capture_events.append(event)

func take_capture_events() -> Array:
	var result:=capture_events
	capture_events=[]
	return result

static func _hunt_metric(pet: Dictionary, metric: String) -> int:
	if metric=="sum":return int(pet.attack)+int(pet.defence)+int(pet.speed)
	return int(pet.get(metric,0))

func set_pet_favorite(pet_id: String, favorite: bool) -> bool:
	last_error=""
	# A battle never reads or writes favourites, so this works during one too.
	for pet in _profile.pets+_profile.get("pet_storage",[]):
		if str(pet.get("pet_id",""))==pet_id:
			pet.favorite=favorite;return true
	last_error="找不到这只宠物。";return false

# Permanently removes pets by stable ID from the party and warehouse. Favorites,
# the active pet and the mount are skipped; carried indices are re-pointed.
# Each released pet gets a 放生记录 entry: source (手动, 保留规则, 自动整理) and
# notes (pet_id -> {reason, beaten_by, judged}; without one the reason is 手动放生).
func release_pets(ids: Array, source: String = "手动", notes: Dictionary = {}) -> Dictionary:
	last_error=""
	var result:={"released":0,"skipped":[]}
	# During a battle only its participants are kept back (skipped as 战斗中).
	var busy:=battle_pets()
	var wanted:={}
	for id in ids:wanted[str(id)]=true
	var active_id:=""
	var ride_id:=""
	if int(_profile.active_pet)>=0 and int(_profile.active_pet)<_profile.pets.size():active_id=str(_profile.pets[int(_profile.active_pet)].get("pet_id",""))
	if int(_profile.get("ride_pet",-1))>=0 and int(_profile.ride_pet)<_profile.pets.size():ride_id=str(_profile.pets[int(_profile.ride_pet)].get("pet_id",""))
	var found:={}
	var doomed:={}
	for pet in _profile.pets+_profile.get("pet_storage",[]):
		var identifier:=str(pet.get("pet_id",""))
		if not wanted.has(identifier):continue
		found[identifier]=true
		if source in ["自动整理","未达标整理"] and capture_only_protected(pet):result.skipped.append({"id":identifier,"reason":"只抓不练，尚未手动练级"})
		elif pet.get("favorite",false):result.skipped.append({"id":identifier,"reason":"收藏"})
		elif busy.has(identifier):result.skipped.append({"id":identifier,"reason":"战斗中"})
		elif identifier==ride_id:result.skipped.append({"id":identifier,"reason":"骑乘中"})
		elif identifier==active_id:result.skipped.append({"id":identifier,"reason":"出战中"})
		else:doomed[identifier]=true
	for identifier in wanted:
		if not found.has(identifier):result.skipped.append({"id":identifier,"reason":"找不到"})
	if doomed.is_empty():return result
	for location in ["pets","pet_storage"]:
		for pet in _profile.get(location,[]):
			var identifier:=str(pet.get("pet_id",""))
			if not doomed.has(identifier):continue
			var note:Dictionary=notes.get(identifier,{})
			release_events.append(ReleaseLog.entry(pet,"随身" if location=="pets" else "仓库",source,str(note.get("reason","手动放生")),note.get("beaten_by",[]),note.get("judged",{})))
	_profile.pets=_profile.pets.filter(func(pet):return not doomed.has(str(pet.get("pet_id",""))))
	_profile.pet_storage=_profile.get("pet_storage",[]).filter(func(pet):return not doomed.has(str(pet.get("pet_id",""))))
	_profile.active_pet=-1
	if _profile.has("ride_pet"):_profile.ride_pet=-1
	for i in range(_profile.pets.size()):
		var identifier:=str(_profile.pets[i].get("pet_id",""))
		if not active_id.is_empty() and identifier==active_id:_profile.active_pet=i
		if not ride_id.is_empty() and identifier==ride_id:_profile.ride_pet=i
	result.released=doomed.size()
	return result

func retrieve_pet_by_id(pet_id: String) -> bool:
	for index in range(_profile.get("pet_storage",[]).size()):
		if str(_profile.pet_storage[index].get("pet_id",""))==pet_id:return retrieve_pet(index)
	last_error="这只宠物已不在仓库。";return false

func select_pet(index: int) -> bool:
	last_error = ""
	if not _pending.is_empty():
		last_error = "战斗中不能更换出战宠物，请用战斗里的「宠物」指令。"
		return false
	if index < -1 or index >= _profile.pets.size():
		return false
	if index >= 0 and index == int(_profile.get("ride_pet",-1)):return false
	_profile.active_pet = index
	return true

func rename_pet(index: int, pet_name: String) -> bool:
	pet_name = pet_name.strip_edges()
	if not _pending.is_empty() or index < 0 or index >= _profile.pets.size() or pet_name.is_empty() or pet_name.length() > 16 or "\n" in pet_name:
		return false
	_profile.pets[index].name = pet_name
	return true

func accept_quest() -> bool:
	if not _pending.is_empty() or _profile.quest.accepted:
		return false
	_profile.quest.accepted = true
	return true

func can_fight_boss() -> bool:
	return _profile.quest.accepted and _profile.quest.wins >= 3 and not _profile.pets.is_empty() and not _profile.quest.boss_defeated

func claim_quest() -> bool:
	if int(_profile.inventory.potion)==0 and bag_slots(_profile)>=15:return false
	if not _pending.is_empty() or not _profile.quest.boss_defeated or _profile.quest.claimed:
		return false
	_profile.quest.claimed = true
	_profile.player.gold += 100
	_profile.inventory.potion = mini(99,_profile.inventory.potion + 3)
	_gain_xp(_profile.player,60)
	return true

## The player's automation overrides (defaults are applied by AutomationSettings).
func automation_settings() -> Dictionary:
	return _profile.get("automation_settings",{}).duplicate(true)

## Deep-merges a validated partial update; null resets a value or section.
func set_automation_settings(patch: Variant) -> bool:
	var reply: Dictionary = AutomationSettings.apply_patch(_profile.get("automation_settings",{}),patch)
	if not reply.ok:
		last_error = str(reply.reason)
		return false
	_profile.automation_settings = reply.overrides
	return true

# ---- radio library (scripts/music_library.gd) ------------------------------
# Allowed during battles: the radio keeps playing through them.

func _music() -> Dictionary:
	if not _profile.get("music") is Dictionary:_profile.music = MusicLibrary.empty()
	return _profile.music

func set_music_favorite(track: String, favorite: bool) -> bool:
	last_error=""
	if not MusicLibrary.valid_track(track):last_error="没有这首曲子。";return false
	var favorites: Array = _music().favorites
	if favorite and not favorites.has(track):
		if favorites.size() >= MusicLibrary.MAX_TRACKS:last_error="收藏已满。";return false
		favorites.append(track)
	elif not favorite:favorites.erase(track)
	return true

func create_music_playlist(name: String) -> bool:
	last_error=""
	var clean := MusicLibrary.clean_name(name)
	if clean.is_empty():last_error="请输入歌单名称。";return false
	if MusicLibrary.find(_music(),clean) >= 0:last_error="已有同名歌单。";return false
	if _music().playlists.size() >= MusicLibrary.MAX_PLAYLISTS:last_error="歌单数量已满。";return false
	_music().playlists.append({"name":clean,"tracks":[]})
	return true

func rename_music_playlist(name: String, new_name: String) -> bool:
	last_error=""
	var index := MusicLibrary.find(_music(),name)
	var clean := MusicLibrary.clean_name(new_name)
	if index < 0:last_error="找不到这个歌单。";return false
	if clean.is_empty():last_error="请输入歌单名称。";return false
	if clean!=name and MusicLibrary.find(_music(),clean) >= 0:last_error="已有同名歌单。";return false
	_music().playlists[index].name = clean
	return true

func delete_music_playlist(name: String) -> bool:
	last_error=""
	var index := MusicLibrary.find(_music(),name)
	if index < 0:last_error="找不到这个歌单。";return false
	_music().playlists.remove_at(index)
	return true

## Appends a track (a playlist may hold a track more than once).
func add_music_to_playlist(name: String, track: String) -> bool:
	last_error=""
	var index := MusicLibrary.find(_music(),name)
	if index < 0:last_error="找不到这个歌单。";return false
	if not MusicLibrary.valid_track(track):last_error="没有这首曲子。";return false
	var tracks: Array = _music().playlists[index].tracks
	if tracks.size() >= MusicLibrary.MAX_TRACKS:last_error="歌单已满。";return false
	tracks.append(track)
	return true

## Removes the entry at position, which must still hold track (so a device
## showing an older list cannot remove a different entry).
func remove_music_from_playlist(name: String, position: int, track: String) -> bool:
	last_error=""
	var index := MusicLibrary.find(_music(),name)
	if index < 0:last_error="找不到这个歌单。";return false
	var tracks: Array = _music().playlists[index].tracks
	if position < 0 or position >= tracks.size() or tracks[position]!=track:last_error="歌单已在别处改动，请再试一次。";return false
	tracks.remove_at(position)
	return true

## Moves the entry at position one step up (-1) or down (+1).
func move_music_in_playlist(name: String, position: int, track: String, step: int) -> bool:
	last_error=""
	var index := MusicLibrary.find(_music(),name)
	if index < 0:last_error="找不到这个歌单。";return false
	var tracks: Array = _music().playlists[index].tracks
	var target := position+signi(step)
	if position < 0 or position >= tracks.size() or tracks[position]!=track:last_error="歌单已在别处改动，请再试一次。";return false
	if target < 0 or target >= tracks.size():return true
	tracks[position] = tracks[target]
	tracks[target] = track
	return true

func set_location(map_id: int, x: int, y: int) -> bool:
	if not _pending.is_empty() or not _location_valid({"map_id":map_id,"x":x,"y":y}):
		return false
	_profile.location = {"map_id":map_id,"x":x,"y":y}
	return true

func save_game(path: String) -> bool:
	OriginalEquipment.migrate(_profile)
	_ensure_pet_ids()
	_sync_stat_points()
	_refresh_loyalty()
	last_error = ""
	if not _pending.is_empty():
		last_error = "Finish the battle before saving."
		return false
	return _write_profile(path)

## Candidate is already normalized/validated; do not run equipment migration here.
func commit_transmigration_candidate(candidate:Dictionary,path:String)->bool:
	if not _pending.is_empty() or path.is_empty() or not TransmigrationState.continuation_error(_profile).is_empty():return false
	if not _valid_profile(candidate) or candidate.rebirth.history!="natural" or int(candidate.player.transmigration)!=int(_profile.player.transmigration)+1:return false
	if str(candidate.rebirth.last_transaction)==str(_profile.rebirth.get("last_transaction","")):return false
	var before:Dictionary=_profile
	_profile=candidate.duplicate(true)
	if _write_profile(path):return true
	_profile=before
	return false

func _write_profile(path:String)->bool:
	var file := FileAccess.open(path + ".tmp",FileAccess.WRITE)
	if file == null:
		last_error = "Cannot create save."
		return false
	file.store_string(JSON.stringify(_profile))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and _valid_profile(_parse_save(FileAccess.get_file_as_string(path))):
		if DirAccess.copy_absolute(absolute,absolute + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(absolute + ".tmp",absolute) == OK

func load_game(path: String) -> bool:
	if not _pending.is_empty():
		return false
	for candidate in [path,path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed = _parse_save(FileAccess.get_file_as_string(candidate))
		if _valid_profile(parsed):
			_profile = _normalize_numbers(parsed)
			if int(_profile.version)<6:
				for key in ["original_instances","original_equipment","next_original_uid"]:_profile.erase(key)
			_refresh_login_luck()
			_ensure_pet_ids()
			if not _profile.inventory.has("mirror_charm"):_profile.inventory.mirror_charm=0
			if not _profile.has("equipped_mirror"):_profile.equipped_mirror=false
			# Saves before 气力 (version 3 and older) start with it full, and
			# with no spirit equipment.
			if not _profile.player.has("mp"):_profile.player.mp = Spirits.MAX_MP
			for item in Spirits.SPIRIT_ITEMS:
				if not _profile.inventory.has(item):_profile.inventory[item] = 0
			_equipment()
			if not _profile.has("ride_pet"):_profile.ride_pet = -1
			if not _profile.has("character_id"):_profile.character_id = "100000"
			if not _profile.has("travel_pass"):
				_profile.travel_pass = false
			# Saves before automation settings get the defaults; invalid parts are dropped.
			if not _profile.has("no_random_encounters"):_profile.no_random_encounters=false
			_profile.automation_settings = AutomationSettings.sanitize(_profile.get("automation_settings",{}))
			# Saves before the radio get an empty library; malformed parts are dropped.
			_profile.music = MusicLibrary.sanitize(_profile.get("music"))
			# Earlier prototype saves predate speed; migrate only this optional field.
			if not _profile.player.has("speed"):
				_profile.player.speed = 10 + _profile.player.level - 1
			for pet in _profile.pets+_profile.pet_storage:
				if not pet.has("speed"):
					pet.speed = int(SPECIES.get(pet.species,{}).get("speed",1)) + pet.level - 1
			if not _profile.player.has("allocated_stats"):
				# Preserve existing prototype gains, credit missed allocation once.
				_profile.player.allocated_stats = {"vitality":0,"strength":0,"toughness":0,"dexterity":0}
			Progression.migrate_player(_profile.player)
			# Saves before 属性 (or with an illegal choice) get the default.
			if not Elements.valid_player(_profile.player.get("elements")):_profile.player.elements = Elements.PLAYER_DEFAULT.duplicate()
			else:_profile.player.elements = _profile.player.elements.map(func(v):return int(v))
			var all_pets: Array=_profile.pets+_profile.pet_storage
			for i in range(all_pets.size()):
				var pet: Dictionary=all_pets[i]
				if not pet.has("original_end_event"):pet.original_end_event = original_pet_event(pet)
				Progression.migrate_pet(pet,int(pet.sprite)+i*7919)
				if not pet.has("learned_skills"):pet.learned_skills = []
				pet.skill_unlocked = not pet.learned_skills.is_empty()
			Progression.refresh(_profile.player)
			for pet in _profile.pets+_profile.pet_storage:Progression.refresh(pet)
			# Saves before charm and loyalty rules (loyalty.gd migrate_*).
			Loyalty.migrate_charm(_profile.player)
			for pet in _profile.pets+_profile.pet_storage:Loyalty.migrate_pet(pet,_profile.player)
			_refresh_loyalty()
			if int(_profile.version)<5:_profile.merge(ORIGINAL_DEFAULT.duplicate(true),true)
			OriginalEquipment.migrate(_profile)
			# itemset dropatlogout (column78), char.c CHAR_dropItemAtLogout:
			# only the audited answer papers and wisdom crystal (2507..2517).
			for item in range(2507,2518):
				while item in _profile.original_items:OriginalEquipment.remove(_profile,item)
			TransmigrationState.migrate(_profile)
			_profile.version = SAVE_VERSION
			_sync_stat_points()
			return true
	last_error = "No valid save or backup."
	return false

func _valid_profile(value: Variant) -> bool:
	if value is Dictionary and value.has("training_borrow_rng") and not preload("res://server/training_borrow.gd").valid_rng(value.training_borrow_rng):return false
	if value is Dictionary and value.has("no_random_encounters") and not value.no_random_encounters is bool:return false
	if value is Dictionary and value.has("default_companions_claimed") and not value.default_companions_claimed is bool:return false
	if value is Dictionary and value.has("gm_modified") and not value.gm_modified is bool:return false
	if value is Dictionary and value.has("gm_bonus_points") and not _integer(value.gm_bonus_points,0,100000):return false
	if value is Dictionary and value.has("character_id") and not _valid_character(value.character_id):return false
	if value is Dictionary and value.has("face") and not _integer(value.face,0,24):return false
	if value is Dictionary and value.has("travel_pass") and not value.travel_pass is bool:
		return false
	if not value is Dictionary or not _integer(value.get("version",0),1,SAVE_VERSION) or value.get("profile_id", "") != "samgir-singleplayer-v1":
		return false
	if not TransmigrationState.valid(value):return false
	if int(value.version)>=5 and not original_state_valid(value):return false
	if not ItemStorage.valid(value):return false
	if int(value.version)>=6 and (not OriginalEquipment.valid(value) or bag_slots(value)>15):return false
	for key in ["player","inventory","quest","location"]:
		if not value.get(key) is Dictionary:
			return false
	if not value.get("pets") is Array or value.pets.size() > PET_CAPACITY or not value.get("completed_battles") is Array:
		return false
	if value.has("ride_pet") and (not _integer(value.ride_pet,-1,value.pets.size()-1) or (value.ride_pet >= 0 and value.ride_pet == value.get("active_pet"))):return false
	if not _integer(value.get("active_pet"),-1,value.pets.size()-1) or not _integer(value.get("next_battle"),1,1000000000) or not value.get("equipped") is bool:
		return false
	if value.player is Dictionary and value.player.has("transmigration") and not _integer(value.player.transmigration,0,2147483647):return false
	if not _actor_valid(value.player) or not _integer(value.player.get("gold"),0,MAX_GOLD):
		return false
	for field in ["charm","luck","last_luck_time"]:
		if value.player.has(field) and not _integer(value.player[field],1 if field=="luck" else 0,4102444800 if field=="last_luck_time" else (100 if field=="charm" else 5)):return false
	if value.player.has("charm_rules") and not _integer(value.player.charm_rules,1,1):return false
	if value.player.has("stat_points") and not _integer(value.player.stat_points,0,1000000000):
		return false
	if value.player.has("allocated_stats"):
		if not value.player.get("allocated_stats") is Dictionary:
			return false
		var assigned := 0
		for stat in ["vitality","strength","toughness","dexterity"]:
			if not _integer(value.player.allocated_stats.get(stat),0,TransmigrationState.point_budget(value)):
				return false
			assigned += int(value.player.allocated_stats[stat])
		if assigned > TransmigrationState.point_budget(value):
			return false
	if not _integer(value.inventory.get("healing_charm",0),0,99):return false
	if value.has("pet_care_granted") and not value.pet_care_granted is bool:return false
	if value.has("equipped_mirror") and not value.equipped_mirror is bool:return false
	if value.get("equipped_mirror",false) and int(value.inventory.get("mirror_charm",0))<1:return false
	for item in ITEM_PRICES:
		if not _integer(value.inventory.get(item,0 if item=="mirror_charm" or item in Spirits.SPIRIT_ITEMS else null),0,99):
			return false
	if value.player.has("mp") and not _integer(value.player.mp,0,Spirits.MAX_MP):return false
	if value.has("equipment"):
		if not value.equipment is Dictionary:return false
		for slot in value.equipment:
			var worn = value.equipment[slot]
			if not slot in ["body","amulet"] or not worn is String:return false
			if worn.is_empty():continue
			if not worn in Spirits.SPIRIT_ITEMS or str(Spirits.ITEMS[worn].slot)!=slot or int(value.inventory.get(worn,0))<1:return false
		if not str(value.equipment.get("amulet","")).is_empty() and bool(value.get("equipped_mirror",false)):return false
	if value.equipped and value.inventory.club < 1:
		return false
	for key in ["accepted","boss_defeated","claimed"]:
		if not value.quest.get(key) is bool:
			return false
	if not _integer(value.quest.get("wins"),0,1000000000):
		return false
	if (value.quest.claimed and not value.quest.boss_defeated) or (value.quest.boss_defeated and not value.quest.accepted):
		return false
	if value.completed_battles.size() > 128:
		return false
	for battle_id in value.completed_battles:
		if not battle_id is String or not battle_id.begins_with("battle-") or battle_id.length() > 32:
			return false
	if not _location_valid(value.location):
		return false
	if not value.get("pet_storage",[]) is Array:return false
	if not _valid_pet_ids(value):return false
	for pet in value.pets+value.get("pet_storage",[]):
		if not pet is Dictionary or not _actor_valid(pet) or Progression.species_definition(str(pet.get("species",""))).is_empty() or not pet.get("name") is String or pet.name.is_empty() or pet.name.length() > 16 or not pet.get("skill_unlocked") is bool:
			return false
		if str(pet.species).begins_with("original_") and (not pet.has("base_stats") or not pet.has("growth_weights")):return false
		if pet.has("base_stats") and not pet.has("growth_weights"):return false
		var definition: Dictionary = SPECIES.get(pet.species,Progression.species_definition(pet.species))
		if pet.get("sprite") != definition.get("sprite",-1):
			return false
		if pet.has("original_end_event") and not _integer(pet.original_end_event,0,1):return false
		for flag in ["capture_only","capture_only_untrained"]:
			if pet.has(flag) and not pet[flag] is bool:return false
		if pet.has("variable_ai") and not _integer(pet.variable_ai,Loyalty.VARIABLE_MIN,Loyalty.VARIABLE_MAX):return false
		if pet.has("modai") and not _integer(pet.modai,0,1000000000):return false
		if pet.has("loyalty") and not _integer(pet.loyalty,0,100):return false
	return true

func _wild_actor_valid(actor: Dictionary) -> bool:
	if _actor_valid(actor):return true
	var shape:Dictionary=preload("res://server/original_ore_actor.gd").validation_shape(actor)
	return not shape.is_empty() and _actor_valid(shape)

func _actor_valid(actor: Dictionary) -> bool:
	if actor.has("gm_modified") and not actor.gm_modified is bool:return false
	if actor.has("base_stats"):
		if not actor.base_stats is Dictionary:return false
		for key in Progression.STATS:
			if not _integer(actor.base_stats.get(key),0,100000000):return false
	if actor.has("legacy_stat_offset"):
		if not actor.legacy_stat_offset is Dictionary:return false
		for key in Progression.DERIVED:
			if not _integer(actor.legacy_stat_offset.get(key),-1000000,1000000):return false
	if actor.has("growth_weights"):
		if not actor.growth_weights is Array or actor.growth_weights.size() != 4:return false
		for weight in actor.growth_weights:
			if not _integer(weight,0,255):return false
		if not _integer(actor.get("growth_rank"),0,5) or not _integer(actor.get("growth_seed"),0,100000000000000):return false
	if actor.has("learned_skills"):
		if not actor.learned_skills is Array or actor.learned_skills.size() > 3:return false
		var seen := []
		for skill in actor.learned_skills:
			if not _integer(skill,0,1000) or int(skill) not in [3,10,50] or int(skill) in seen:return false
			seen.append(int(skill))
	if actor.has("speed") and not _integer(actor.speed,1,1000000):
		return false
	for key in ["max_hp","level","attack"]:
		if not _integer(actor.get(key),1,1000000):
			return false
	return _integer(actor.get("hp"),0,actor.max_hp) and _integer(actor.get("xp"),0,1000000000) and _integer(actor.get("defence"),0,1000000)

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

func _normalize_numbers(value: Variant) -> Variant:
	if value is float:
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _normalize_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize_numbers(item))
		return result
	return value

func _location_valid(location: Dictionary) -> bool:
	if not _integer(location.get("map_id"),0,65535):
		return false
	var map_id := int(location.map_id)
	var info: Dictionary = world_catalog.info(map_id)
	if not info.is_empty():
		return _integer(location.get("x"),0,int(info.width)-1) and _integer(location.get("y"),0,int(info.height)-1)
	if map_id not in [1000,100,1002]:
		return false
	var bound := 800 if map_id == 100 else (160 if map_id == 1000 else 30)
	return _integer(location.get("x"),0,bound-1) and _integer(location.get("y"),0,bound-1)

func _parse_save(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data

func allocate_stat(stat: String, amount: int = 1) -> bool:
	_sync_stat_points()
	var p: Dictionary = _profile.player
	if not _pending.is_empty() or not p.allocated_stats.has(stat) or p.stat_points <= 0 or amount <= 0:return false
	amount = mini(amount,int(p.stat_points))
	Progression.migrate_player(p)
	var old_max := int(p.max_hp)
	p.allocated_stats[stat] += amount
	p.base_stats[stat] += 100*amount
	Progression.refresh(p)
	p.hp += int(p.max_hp)-old_max
	_sync_stat_points()
	return true

func distribute_stats(stats: Array) -> bool:
	_sync_stat_points()
	if not _pending.is_empty() or stats.is_empty() or _profile.player.stat_points<=0:return false
	var unique: Array=[]
	for stat in stats:
		if not stat is String or not _profile.player.allocated_stats.has(stat) or stat in unique:return false
		unique.append(stat)
	var points:=int(_profile.player.stat_points)
	var each:=int(points/unique.size())
	var remainder:=points%unique.size()
	for i in range(unique.size()):
		var amount:=each+(1 if i<remainder else 0)
		if amount>0:allocate_stat(unique[i],amount)
	return true

## The player's 属性 [地,水,火,风] in stored points.
func player_elements() -> Array:
	var value: Variant = _profile.player.get("elements")
	return value.map(func(v):return int(v)) if Elements.valid_player(value) else Elements.PLAYER_DEFAULT.duplicate()

## The creation-screen 属性 choice (char.c:110-128). Character creation is
## deferred, so the choice stays open outside battle.
func set_player_elements(elements: Variant) -> bool:
	if not _pending.is_empty() or not Elements.valid_player(elements):return false
	_profile.player.elements = elements.map(func(v):return int(v))
	return true

func effective_player_stats() -> Dictionary:
	var result := {}
	for key in Progression.DERIVED:result[key] = _profile.player[key]
	var armour := equipment_mods()
	result.attack = maxi(1,int(result.attack)+int(armour.attack))
	result.charm = clampi(int(_profile.player.get("charm",60))+int(armour.charm),0,100)
	result.defence = maxi(0,int(result.defence)+int(armour.defence))
	result.speed = maxi(1,int(result.speed)+int(armour.speed))
	var riding := int(_profile.get("ride_pet",-1))
	if riding>=0:
		result = preload("res://scripts/riding.gd").adjusted_stats(result,_profile.pets[riding])
	return result

func _sync_stat_points() -> void:
	var assigned := 0
	for count in _profile.player.allocated_stats.values():
		assigned += int(count)
	_profile.player.stat_points = maxi(0,TransmigrationState.point_budget(_profile)-assigned)

func learn_pet_skill(index: int, skill_id: int) -> bool:
	var catalog = preload("res://scripts/pet_skills.gd")
	if not _pending.is_empty() or index < 0 or index >= _profile.pets.size() or not catalog.SKILLS.has(skill_id):return false
	var location: Dictionary = _profile.location
	if not catalog.TRAINERS.has(location.map_id):return false
	var trainer: Dictionary = catalog.TRAINERS[location.map_id]
	if skill_id not in trainer.skills or Vector2(location.x,location.y).distance_to(Vector2(trainer.cell[0],trainer.cell[1])) > 2.0:return false
	var pet: Dictionary = _profile.pets[index]
	var learned: Array = pet.get("learned_skills",[])
	var cost := int(catalog.SKILLS[skill_id].cost)
	if skill_id in learned or learned.size() >= 3 or _profile.player.gold < cost:return false
	_profile.player.gold -= cost
	learned.append(skill_id)
	pet.learned_skills = learned
	pet.skill_unlocked = true
	return true

func _valid_character(id: Variant) -> bool:
	if not id is String or not id.is_valid_int():return false
	var number := int(id)
	if str(number) != id or number < 100000 or number > 100235 or (number-100000)%5 != 0:return false
	var catalog: Dictionary = preload("res://scripts/character_art.gd").index()
	return catalog.is_empty() or catalog.get("characters",{}).has(id)

## 人物面部: which of the appearance's 25 original faces (eye * 5 + mouth,
## client login.cpp:3401) the status window shows. It keeps its eye and mouth
## when the appearance changes.
func set_face(face: int) -> bool:
	if not _pending.is_empty() or face < 0 or face > 24:return false
	_profile.face = face
	return true

func set_character(id: String) -> bool:
	if not _pending.is_empty() or not _valid_character(id):return false
	_profile.character_id = id
	var index := int(_profile.get("ride_pet",-1))
	if index>=0 and not preload("res://scripts/riding.gd").can_mount(_profile,index).is_empty():_profile.ride_pet = -1
	return true

# Explicit developer starter pack: idempotent; preserves existing companions.
func grant_starter_pets() -> bool:
	if not _pending.is_empty():return false
	_ensure_pet_ids()
	var missing: Array[String] = []
	for species in ["blue_dragon","golden_tiger","red_rex"]:
		var found := false
		for pet in _profile.pets+_profile.get("pet_storage",[]):
			if pet.species == species:found = true
		if not found:missing.append(species)
	if _profile.pets.size()+missing.size()>PET_CAPACITY:return false
	for species in missing:
		var data: Dictionary = SPECIES[species]
		var pet := Progression.species_actor(species,1,int(data.sprite))
		# A developer grant, like the GM petmake (chatmagic.c:1487): loyalty 100.
		pet.merge({"species":species,"name":data.name,"sprite":data.sprite,"level":1,"xp":0,"skill_unlocked":false,"loyalty":100,"variable_ai":Loyalty.AI_GM_PET})
		Loyalty.stamp_modai(pet)
		_assign_pet_id(pet)
		_profile.pets.append(pet)
	return true

## One mutation; the backend owns persistence and rollback.
func mount_pet_as(pet_id: String, character_id: String) -> bool:
	last_error = ""
	if not _valid_character(character_id):
		last_error = "无效的角色造型。"
		return false
	var index := -1
	for i in range(_profile.pets.size()):
		if str(_profile.pets[i].get("pet_id","")) == pet_id and not pet_id.is_empty():index = i;break
	if index < 0:
		last_error = "这只伙伴已不在随身栏，请重新选择。"
		return false
	if not preload("res://scripts/riding.gd").compatible_characters(int(_profile.pets[index].get("sprite",0))).has(character_id):
		last_error = "此造型没有这只伙伴的原版骑乘动画。"
		return false
	var before := _profile.duplicate(true)
	_profile.character_id = character_id
	if not mount_pet(index):
		_profile = before
		return false
	return true

func mount_pet(index: int) -> bool:
	last_error = ""
	if not _pending.is_empty():
		# family.c FAMILY_RidePet: 战斗中不可骑宠！
		last_error = "战斗中不能骑乘或下骑。"
		return false
	if index == -1:
		_profile.ride_pet = -1
		return true
	last_error = preload("res://scripts/riding.gd").can_mount(_profile,index)
	if not last_error.is_empty():return false
	_profile.ride_pet = index
	return true

# Explicit developer-only mutations. The UI labels all values and checkpoints
# successful changes; ordinary progression never invokes these methods.
func _gm_actor(index: int) -> Dictionary:
	if index == -1:return _profile.player
	if index >= 0 and index < _profile.pets.size():return _profile.pets[index]
	return {}

func _gm_error(message: String) -> bool:
	last_error=message
	return false

func _gm_mark(actor: Dictionary) -> void:
	_profile.gm_modified=true
	actor.gm_modified=true

func gm_clear_modified(index: int = -2) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能清除 GM 标记。")
	if index==-2:
		_profile.player.erase("gm_modified")
		for pet in _profile.pets:pet.erase("gm_modified")
	else:
		var actor:=_gm_actor(index)
		if actor.is_empty():return _gm_error("请选择有效角色或宠物。")
		actor.erase("gm_modified")
	_profile.gm_modified=bool(_profile.player.get("gm_modified",false))
	for pet in _profile.pets:
		_profile.gm_modified=bool(_profile.gm_modified) or bool(pet.get("gm_modified",false))
	return true

# Workflow shortcut: spends exactly the XP each level needs through the normal
# _gain_xp loop, so every level's seeded growth runs once and final stats match
# battle training. Not a GM edit, so no GM mark.
func level_pet_to(pet_id: String, target: int) -> bool:
	last_error=""
	if not _pending.is_empty():last_error="请先结束战斗。";return false
	for pet in _profile.pets:
		if str(pet.get("pet_id",""))!=pet_id:continue
		var goal:=clampi(target,1,MAX_LEVEL)
		while int(pet.level)<goal:_gain_xp(pet,int(pet.level)*30-int(pet.xp))
		return true
	last_error="目标宠物不在随身队伍。";return false

func gm_raise_level(index: int, target: Variant) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能修改等级。")
	var actor:=_gm_actor(index)
	if actor.is_empty() or not _integer(target,1,120):return _gm_error("请选择角色或宠物，等级须为1至120的整数。")
	if int(target)<int(actor.level):return _gm_error("只允许升至指定等级，不能降级。")
	if int(target)==int(actor.level):return true
	while int(actor.level)<int(target):_gain_xp(actor,int(actor.level)*30-int(actor.xp))
	_gm_mark(actor)
	_sync_stat_points()
	return true

func gm_set_base_stat(index: int, stat: String, value: Variant, additive: bool = false) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能修改能力。")
	var actor:=_gm_actor(index)
	if actor.is_empty() or stat not in Progression.STATS or not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>10000:
		return _gm_error("基础值必须是有限数字，范围0至10000；增加值可为负数。")
	var planned:=actor.duplicate(true)
	if index==-1:Progression.migrate_player(planned)
	else:Progression.migrate_pet(planned,int(planned.sprite))
	var fixed:=roundi(float(value)*100.0)
	if additive:fixed+=int(planned.base_stats[stat])
	if fixed<0 or fixed>1000000:return _gm_error("结果超出基础值0至10000的范围。")
	planned.base_stats[stat]=fixed
	Progression.refresh(planned)
	actor.merge(planned,true)
	if index==-1:TransmigrationState.record_developer_base(_profile)
	_gm_mark(actor)
	return true

## Developer convenience: a Lv1 pet of any original template whose battle art
## is imported (special pets no imported map spawns, see
## docs/reverse-engineering/special-pets.md). Born by the same rules as a
## caught Lv1 pet; full_grade fixes all four birth grades at +2 (满档). Goes to
## the party, or the warehouse when the party is full. Not marked
## gm_modified: the pet is an ordinary birth, not an edited one.
func gm_grant_pet(template: Variant, full_grade: bool = false) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能发放宠物。")
	if not _integer(template,1,99999):return _gm_error("原表编号须为1至99999的整数。")
	var species := "original_%d" % int(template)
	var data: Dictionary = Progression.species_definition(species)
	if data.is_empty():return _gm_error("没有原表 %d。" % int(template))
	# Later pets from the album (tools/import_encounters.py) have art but no stats to be born with.
	if not bool(data.get("stats_known",true)):return _gm_error("%s（%d）是 %s 新宠，没有原版数值，不能发放。" % [data.name,int(template),str(data.get("source",""))])
	if not TroopArt.can_render([{"sprite":int(data.sprite)}]):return _gm_error("原表 %d（%s）的战斗图未导入，不能发放。" % [int(template),data.name])
	_ensure_pet_ids()
	var pet := Progression.species_actor(species,1,randi(),[2,2,2,2] if full_grade else [])
	pet.merge({"species":species,"template_id":int(template),"name":str(data.name),"sprite":int(data.sprite),"level":1,"xp":0,"skill_unlocked":false,"elements":data.get("elements",[0,0,0,0]).duplicate(),"size":int(data.get("size",1))})
	# GM petmake (chatmagic.c:1487) gives the pet CHAR_VARIABLEAI 10000: loyalty 100.
	pet.original_end_event = 0
	pet.variable_ai = Loyalty.AI_GM_PET
	Loyalty.stamp_modai(pet)
	_assign_pet_id(pet)
	_record_capture(pet,"GM发放")
	if _profile.pets.size() < PET_CAPACITY:
		_profile.pets.append(pet)
		if _profile.pets.size()==1:_profile.active_pet = 0
	else:_profile.pet_storage.append(pet)
	return true

func gm_grant_points(amount: Variant) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能增加分配点。")
	if not _integer(amount,1,100000) or int(_profile.get("gm_bonus_points",0))+int(amount)>100000:return _gm_error("增加点数须为正整数，GM赠点累计上限100000。")
	_profile.gm_bonus_points=int(_profile.get("gm_bonus_points",0))+int(amount)
	_gm_mark(_profile.player)
	_sync_stat_points()
	return true

func gm_heal(index: int = -2) -> bool:
	last_error=""
	if not _pending.is_empty():return _gm_error("战斗中不能直接恢复；可使用立即脱战。")
	var actors: Array=[]
	if index==-2:
		actors.append(_profile.player)
		actors.append_array(_profile.pets)
	else:
		var actor:=_gm_actor(index)
		if actor.is_empty():return _gm_error("请选择有效角色或宠物。")
		actors.append(actor)
	for actor in actors:
		actor.hp=actor.max_hp
		_gm_mark(actor)
	if index in [-2,-1]:_profile.player.mp = Spirits.MAX_MP
	return true

func claim_default_companions() -> bool:
	if bool(_profile.get("default_companions_claimed",false)):return false
	if not grant_starter_pets():return false
	_profile.default_companions_claimed = true
	return true

static func _generated_drops_valid(enemy: Dictionary) -> bool:
	var drops = enemy.get("generated_drops",[])
	if not drops is Array or drops.size()>10:return false
	for item in drops:
		if not _original_integer(item,1,2147483647):return false
	if enemy.has("source_wait_only") and not enemy.source_wait_only is bool:return false
	if drops.is_empty() and not bool(enemy.get("source_wait_only",false)):return true
	if not _drop_sources_loaded:
		_drop_sources_loaded = true
		var path := "res://assets/legacy/encounters/catalog.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:_drop_sources = parsed.get("enemies",{})
	var id := int(enemy.get("source_enemy_id",-1))
	var source: Dictionary = _drop_sources.get(str(id),{})
	if source.is_empty() or str(enemy.get("species",""))!="original_%d"%int(source.template_id):return false
	if bool(enemy.get("source_wait_only",false)) and not bool(source.get("wait_only",false)):return false
	if not drops.is_empty() and not EncounterCatalog.drop_enemy_allowed(id):return false
	var allowed := []
	for drop in source.get("drops",[]):
		if int(drop.get("probability",0))>0:allowed.append(int(drop.item_id))
	for item in drops:
		var index := allowed.find(int(item))
		if index<0:return false
		allowed.remove_at(index)
	return true
