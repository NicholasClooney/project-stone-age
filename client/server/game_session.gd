extends RefCounted
var world_catalog = preload("res://scripts/world_catalog.gd").new()
## Single-player authority. Prototype rules; original art/data do not imply formula parity.
const SAVE_VERSION := 2
const PET_CAPACITY := 30
const Progression = preload("res://server/progression.gd")
const ITEM_PRICES := {"potion":10,"club":30}
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
var last_error := ""

func _init() -> void:
	_profile = {"version":SAVE_VERSION,"character_id":"100000","profile_id":"samgir-singleplayer-v1","player":{"hp":48,"max_hp":48,"level":1,"xp":0,"gold":20,"attack":10,"defence":0,"speed":10,"stat_points":0,"allocated_stats":{"vitality":0,"strength":0,"toughness":0,"dexterity":0}},"inventory":{"potion":2,"club":0},"equipped":false,"travel_pass":false,"pets":[],"active_pet":-1,"ride_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1}

	_profile.player.base_stats = Progression.START.duplicate()
	Progression.refresh(_profile.player)
	_profile.player.hp = _profile.player.max_hp

# Original item 2422: reusable undersea passage permit, sold for 200 stone.
func buy_travel_pass() -> bool:
	if not _pending.is_empty() or _profile.get("travel_pass",false) or _profile.player.gold < 200:
		return false
	_profile.player.gold -= 200
	_profile.travel_pass = true
	return true

func has_travel_pass() -> bool:
	return _profile.get("travel_pass",false)

func snapshot() -> Dictionary:
	_sync_stat_points()
	return _profile.duplicate(true)

func start_battle_config(species: String = "wooli", boss: bool = false, enemy_count: int = 1) -> Dictionary:
	if not SPECIES.has(species) or not _pending.is_empty() or (boss and not can_fight_boss()):
		return {}
	var enemy: Dictionary = SPECIES[species].duplicate()
	var native := Progression.species_actor(species,3 if boss else 1,int(_profile.next_battle)*7919)
	for key in native:enemy[key] = native[key]
	var player: Dictionary = _profile.player
	var pet: Dictionary = {}
	if _profile.active_pet >= 0:
		pet = _profile.pets[_profile.active_pet].duplicate(true)
	var config := {"battle_id":"battle-%d" % _profile.next_battle,"player_hp":player.hp,"player_max_hp":player.max_hp,"player_attack":player.attack+(4 if _profile.equipped else 0),"player_defence":player.defence,"player_speed":player.speed,"enemy_species":species,"enemy_name":("强壮的" if boss else "") + enemy.name,"enemy_sprite":enemy.sprite,"enemy_max_hp":enemy.max_hp,"enemy_attack":enemy.attack,"enemy_defence":enemy.defence,"enemy_speed":enemy.speed,"boss":boss,"pet":pet,"potions":_profile.inventory.potion,"can_capture":_profile.pets.size() < PET_CAPACITY,"reward_xp":60 if boss else 20,"reward_gold":30 if boss else 10}
	config.ride_pet_index = int(_profile.get("ride_pet",-1))
	config.ride_pet = _profile.pets[config.ride_pet_index].duplicate(true) if config.ride_pet_index>=0 else {}
	config.mounted_sprite = preload("res://scripts/riding.gd").composite(str(_profile.character_id),int(config.ride_pet.get("sprite",0))) if not config.ride_pet.is_empty() else -1
	config.player_level = player.level
	config.player_vital = int(player.base_stats.vitality)/100.0
	config.player_weapon = "club" if _profile.equipped else ""
	config.capture_slots = PET_CAPACITY-_profile.pets.size()
	config.pets = _profile.pets.duplicate(true)
	config.active_pet = _profile.active_pet
	config.enemies = []
	for i in range(clampi(enemy_count,1,3)):
		var actor := Progression.species_actor(species,3 if boss else 1,int(_profile.next_battle)*7919+i*97)
		actor.merge({"name":config.enemy_name,"species":species,"sprite":enemy.sprite,"level":3 if boss else 1,"reward_xp":config.reward_xp,"reward_gold":config.reward_gold})
		config.enemies.append(actor)
	_profile.next_battle += 1
	_pending = config.duplicate(true)
	return config

func apply_battle_result(result: Dictionary) -> bool:
	if _pending.is_empty() or result.get("active",true) or result.get("battle_id","") != _pending.battle_id:
		return false
	var outcome: String = result.get("outcome","")
	if outcome not in ["win","captured","escaped","defeat"]:
		return false
	var id: String = _pending.battle_id
	if id in _profile.completed_battles:
		return false
	var hp := int(result.get("player_hp",-1))
	var potions := int(result.get("potions",-1))
	if hp < 0 or hp > _profile.player.max_hp or potions < 0 or potions > _pending.potions:
		return false
	var captures: Array = result.get("captured_species_list",[])
	var enemies: Array = result.get("enemies",[])
	if enemies.size() != _pending.enemies.size() or _profile.pets.size()+captures.size()>PET_CAPACITY:return false
	var verified_captures := []
	var earned_xp := 0
	var earned_gold := 0
	var remaining := 0
	var pet_rewards: Array = []
	pet_rewards.resize(_profile.pets.size())
	pet_rewards.fill(0)
	for i in range(enemies.size()):
		var foe: Dictionary = enemies[i]
		var original: Dictionary = _pending.enemies[i]
		if not _integer(foe.get("hp"),0,original.max_hp) or foe.get("species") != original.species:return false
		if foe.get("captured",false):
			if _pending.boss or not _pending.can_capture or foe.hp != 0:return false
			verified_captures.append(original.species)
		elif foe.hp == 0:
			earned_xp += int(original.reward_xp)
			earned_gold += int(original.reward_gold)
			var recipient = foe.get("defeated_by_pet_index",-1)
			if not _integer(recipient,-1,_profile.pets.size()-1):return false
			if int(recipient)>=0:pet_rewards[int(recipient)] += int(original.reward_xp)
			var ridden = foe.get("defeated_with_ride_index",-1)
			if not _integer(ridden,-1,_profile.pets.size()-1):return false
			if int(ridden)>=0:
				if int(ridden) != int(_pending.get("ride_pet_index",-1)):return false
				pet_rewards[int(ridden)] += preload("res://scripts/riding.gd").experience(int(original.reward_xp),int(_profile.pets[int(ridden)].level),int(original.get("level",1)))
		else:remaining += 1
	var sorted_captures := captures.duplicate()
	sorted_captures.sort()
	verified_captures.sort()
	if sorted_captures != verified_captures:return false
	if outcome in ["win","captured"] and remaining != 0:return false
	if outcome == "captured" and captures.is_empty():return false
	if (outcome == "defeat" and hp != 0) or (outcome != "defeat" and hp == 0):return false
	var battle_pets: Array = result.get("pets",[])
	if battle_pets.size() != _profile.pets.size():return false
	for i in range(battle_pets.size()):
		if not _integer(battle_pets[i].get("hp"),0,_profile.pets[i].max_hp):return false
	if not _integer(result.get("active_pet",-1),-1,_profile.pets.size()-1):return false
	var ride_index = result.get("ride_pet",int(_profile.get("ride_pet",-1)))
	if not _integer(ride_index,-1,_profile.pets.size()-1):return false
	if int(ride_index) not in [-1,int(_profile.get("ride_pet",-1))]:return false
	if int(ride_index)>=0 and (int(result.get("active_pet",-1)) == int(ride_index) or int(battle_pets[int(ride_index)].hp)<=0):return false
	_profile.ride_pet = int(ride_index)
	_profile.player.hp = hp
	_profile.inventory.potion = potions
	for i in range(battle_pets.size()):_profile.pets[i].hp = int(battle_pets[i].hp)
	_profile.active_pet = int(result.get("active_pet",-1))
	if outcome in ["win","captured"]:
		_profile.player.gold += earned_gold
		_gain_xp(_profile.player,earned_xp)
		for i in range(_profile.pets.size()):
			if _profile.pets[i].hp>0:_gain_xp(_profile.pets[i],int(pet_rewards[i]))
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
	result.xp = earned_xp
	result.gold = earned_gold
	result.pet_reward_xp = pet_rewards
	for species in captures:
		var base: Dictionary = SPECIES[species]
		var captured := {"species":species,"name":base.name,"sprite":base.sprite,"level":1,"xp":0,"skill_unlocked":false}
		var native := Progression.species_actor(species,1,int(_profile.next_battle)*7919+_profile.pets.size()*97)
		captured.merge(native)
		_profile.pets.append(captured)
		if _profile.pets.size() == 1:_profile.active_pet = 0
	if outcome == "defeat":
		_recover()
		_profile.location = {"map_id":1000,"x":80,"y":90}
	if result.get("gm_escape",false):_profile.gm_modified=true
	_profile.completed_battles.append(id)
	# Monotonic IDs plus a bounded replay log keep save size bounded.
	if _profile.completed_battles.size() > 128:
		_profile.completed_battles.pop_front()
	_pending.clear()
	return true

func _gain_xp(actor: Dictionary, amount: int) -> void:
	actor.xp += amount
	while actor.xp >= actor.level * 30:
		actor.xp -= actor.level * 30
		actor.level += 1
		if actor.has("skill_unlocked"):
			Progression.migrate_pet(actor,int(actor.sprite))
			Progression.grow_pet(actor,int(actor.level))
			actor.skill_unlocked = not actor.get("learned_skills",[]).is_empty()
		else:
			# battle.c:3173 defaults to 3 skill-up points per level.
			actor.stat_points += 3
		actor.hp = actor.max_hp

func buy_item(item: String) -> bool:
	if not _pending.is_empty() or not ITEM_PRICES.has(item) or _profile.player.gold < ITEM_PRICES[item] or _profile.inventory[item] >= 99:
		return false
	_profile.player.gold -= ITEM_PRICES[item]
	_profile.inventory[item] += 1
	return true

func sell_item(item: String) -> bool:
	if not _pending.is_empty() or not ITEM_PRICES.has(item) or _profile.inventory[item] <= 0 or (item == "club" and _profile.equipped and _profile.inventory.club == 1):
		return false
	_profile.inventory[item] -= 1
	_profile.player.gold += int(ITEM_PRICES[item] / 2)
	return true

func use_item(item: String = "potion") -> bool:
	if not _pending.is_empty() or item != "potion" or _profile.inventory.potion <= 0 or _profile.player.hp >= _profile.player.max_hp:
		return false
	_profile.inventory.potion -= 1
	_profile.player.hp = mini(_profile.player.max_hp,_profile.player.hp + 30)
	return true

func equip_item(item: String = "club") -> bool:
	if not _pending.is_empty() or item != "club" or _profile.inventory.club <= 0:
		return false
	_profile.equipped = not _profile.equipped
	return true

func heal() -> bool:
	if not _pending.is_empty():
		return false
	_recover()
	return true

func _recover() -> void:
	_profile.player.hp = _profile.player.max_hp
	for pet in _profile.pets:
		pet.hp = pet.max_hp

func select_pet(index: int) -> bool:
	if not _pending.is_empty() or index < -1 or index >= _profile.pets.size():
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
	if not _pending.is_empty() or not _profile.quest.boss_defeated or _profile.quest.claimed:
		return false
	_profile.quest.claimed = true
	_profile.player.gold += 100
	_profile.inventory.potion = mini(99,_profile.inventory.potion + 3)
	_gain_xp(_profile.player,60)
	return true

func set_location(map_id: int, x: int, y: int) -> bool:
	if not _pending.is_empty() or not _location_valid({"map_id":map_id,"x":x,"y":y}):
		return false
	_profile.location = {"map_id":map_id,"x":x,"y":y}
	return true

func save_game(path: String) -> bool:
	_sync_stat_points()
	last_error = ""
	if not _pending.is_empty():
		last_error = "Finish the battle before saving."
		return false
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
			if not _profile.has("ride_pet"):_profile.ride_pet = -1
			if not _profile.has("character_id"):_profile.character_id = "100000"
			if not _profile.has("travel_pass"):
				_profile.travel_pass = false
			# Earlier prototype saves predate speed; migrate only this optional field.
			if not _profile.player.has("speed"):
				_profile.player.speed = 10 + _profile.player.level - 1
			for pet in _profile.pets:
				if not pet.has("speed"):
					pet.speed = SPECIES[pet.species].speed + pet.level - 1
			if not _profile.player.has("allocated_stats"):
				# Preserve existing prototype gains, credit missed allocation once.
				_profile.player.allocated_stats = {"vitality":0,"strength":0,"toughness":0,"dexterity":0}
			Progression.migrate_player(_profile.player)
			for i in range(_profile.pets.size()):
				Progression.migrate_pet(_profile.pets[i],int(_profile.pets[i].sprite)+i*7919)
				if not _profile.pets[i].has("learned_skills"):_profile.pets[i].learned_skills = []
				_profile.pets[i].skill_unlocked = not _profile.pets[i].learned_skills.is_empty()
			Progression.refresh(_profile.player)
			for pet in _profile.pets:Progression.refresh(pet)
			_profile.version = SAVE_VERSION
			_sync_stat_points()
			return true
	last_error = "No valid save or backup."
	return false

func _valid_profile(value: Variant) -> bool:
	if value is Dictionary and value.has("default_companions_claimed") and not value.default_companions_claimed is bool:return false
	if value is Dictionary and value.has("gm_modified") and not value.gm_modified is bool:return false
	if value is Dictionary and value.has("gm_bonus_points") and not _integer(value.gm_bonus_points,0,100000):return false
	if value is Dictionary and value.has("character_id") and not _valid_character(value.character_id):return false
	if value is Dictionary and value.has("travel_pass") and not value.travel_pass is bool:
		return false
	if not value is Dictionary or not _integer(value.get("version",0),1,SAVE_VERSION) or value.get("profile_id", "") != "samgir-singleplayer-v1":
		return false
	for key in ["player","inventory","quest","location"]:
		if not value.get(key) is Dictionary:
			return false
	if not value.get("pets") is Array or value.pets.size() > PET_CAPACITY or not value.get("completed_battles") is Array:
		return false
	if value.has("ride_pet") and (not _integer(value.ride_pet,-1,value.pets.size()-1) or (value.ride_pet >= 0 and value.ride_pet == value.get("active_pet"))):return false
	if not _integer(value.get("active_pet"),-1,value.pets.size()-1) or not _integer(value.get("next_battle"),1,1000000000) or not value.get("equipped") is bool:
		return false
	if not _actor_valid(value.player) or not _integer(value.player.get("gold"),0,1000000000):
		return false
	if value.player.has("stat_points") and not _integer(value.player.stat_points,0,1000000000):
		return false
	if value.player.has("allocated_stats"):
		if not value.player.get("allocated_stats") is Dictionary:
			return false
		var assigned := 0
		for stat in ["vitality","strength","toughness","dexterity"]:
			if not _integer(value.player.allocated_stats.get(stat),0,(value.player.level-1)*3+int(value.get("gm_bonus_points",0))):
				return false
			assigned += int(value.player.allocated_stats[stat])
		if assigned > (int(value.player.level)-1)*3+int(value.get("gm_bonus_points",0)):
			return false
	for item in ITEM_PRICES:
		if not _integer(value.inventory.get(item),0,99):
			return false
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
	for pet in value.pets:
		if not pet is Dictionary or not _actor_valid(pet) or not SPECIES.has(pet.get("species","")) or not pet.get("name") is String or pet.name.is_empty() or pet.name.length() > 16 or not pet.get("skill_unlocked") is bool:
			return false
		if pet.has("base_stats") and not pet.has("growth_weights"):return false
		if pet.get("sprite") != SPECIES[pet.species].sprite:
			return false
	return true

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

func allocate_stat(stat: String) -> bool:
	_sync_stat_points()
	var p: Dictionary = _profile.player
	if not _pending.is_empty() or not p.allocated_stats.has(stat) or p.stat_points <= 0:return false
	Progression.migrate_player(p)
	var old_max := int(p.max_hp)
	p.allocated_stats[stat] += 1
	p.base_stats[stat] += 100
	Progression.refresh(p)
	p.hp += int(p.max_hp)-old_max
	_sync_stat_points()
	return true

func effective_player_stats() -> Dictionary:
	var result := {}
	for key in Progression.DERIVED:result[key] = _profile.player[key]
	result.attack += 4 if _profile.equipped else 0
	var riding := int(_profile.get("ride_pet",-1))
	if riding>=0:
		result = preload("res://scripts/riding.gd").adjusted_stats(result,_profile.pets[riding])
	return result

func _sync_stat_points() -> void:
	var assigned := 0
	for count in _profile.player.allocated_stats.values():
		assigned += int(count)
	_profile.player.stat_points = maxi(0,(int(_profile.player.level)-1)*3+int(_profile.get("gm_bonus_points",0))-assigned)

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
	var path := "res://assets/legacy/characters/catalog.json"
	if FileAccess.file_exists(path):
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		return catalog.get("characters",{}).has(id)
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
	var missing: Array[String] = []
	for species in ["blue_dragon","golden_tiger","red_rex"]:
		var found := false
		for pet in _profile.pets:
			if pet.species == species:found = true
		if not found:missing.append(species)
	if _profile.pets.size()+missing.size()>PET_CAPACITY:return false
	for species in missing:
		var data: Dictionary = SPECIES[species]
		var pet := Progression.species_actor(species,1,int(data.sprite))
		pet.merge({"species":species,"name":data.name,"sprite":data.sprite,"level":1,"xp":0,"skill_unlocked":false,"loyalty":100})
		_profile.pets.append(pet)
	return true

func mount_pet(index: int) -> bool:
	last_error = ""
	if not _pending.is_empty():return false
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
	_gm_mark(actor)
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
	return true

func claim_default_companions() -> bool:
	if bool(_profile.get("default_companions_claimed",false)):return false
	if not grant_starter_pets():return false
	_profile.default_companions_claimed = true
	return true
