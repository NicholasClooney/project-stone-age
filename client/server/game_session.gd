extends RefCounted
var world_catalog = preload("res://scripts/world_catalog.gd").new()
## Single-player authority. Prototype rules; original art/data do not imply formula parity.
const SAVE_VERSION := 2
const Progression = preload("res://server/progression.gd")
const ITEM_PRICES := {"potion":10,"club":30}
const SPECIES := {
	"wooli":{"name":"乌力","sprite":100250,"hp":32,"attack":7,"defence":0,"speed":8},
	"wooli_wooli":{"name":"乌力乌力","sprite":100251,"hp":40,"attack":8,"defence":1,"speed":6},
	"woolistan":{"name":"乌力斯坦","sprite":100252,"hp":48,"attack":9,"defence":2,"speed":4},
}
var _profile: Dictionary
var _pending: Dictionary = {}
var last_error := ""

func _init() -> void:
	_profile = {"version":SAVE_VERSION,"profile_id":"samgir-singleplayer-v1","player":{"hp":48,"max_hp":48,"level":1,"xp":0,"gold":20,"attack":10,"defence":0,"speed":10,"stat_points":0,"allocated_stats":{"vitality":0,"strength":0,"toughness":0,"dexterity":0}},"inventory":{"potion":2,"club":0},"equipped":false,"travel_pass":false,"pets":[],"active_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1}

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
	var config := {"battle_id":"battle-%d" % _profile.next_battle,"player_hp":player.hp,"player_max_hp":player.max_hp,"player_attack":effective_player_stats().attack,"player_defence":player.defence,"player_speed":player.speed,"enemy_species":species,"enemy_name":("强壮的" if boss else "") + enemy.name,"enemy_sprite":enemy.sprite,"enemy_max_hp":enemy.max_hp,"enemy_attack":enemy.attack,"enemy_defence":enemy.defence,"enemy_speed":enemy.speed,"boss":boss,"pet":pet,"potions":_profile.inventory.potion,"can_capture":_profile.pets.size() < 5,"reward_xp":60 if boss else 20,"reward_gold":30 if boss else 10}
	config.player_level = player.level
	config.player_vital = int(player.base_stats.vitality)/100.0
	config.player_weapon = "club" if _profile.equipped else ""
	config.capture_slots = 5-_profile.pets.size()
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
	if enemies.size() != _pending.enemies.size() or _profile.pets.size()+captures.size()>5:return false
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
	if value is Dictionary and value.has("travel_pass") and not value.travel_pass is bool:
		return false
	if not value is Dictionary or not _integer(value.get("version",0),1,SAVE_VERSION) or value.get("profile_id", "") != "samgir-singleplayer-v1":
		return false
	for key in ["player","inventory","quest","location"]:
		if not value.get(key) is Dictionary:
			return false
	if not value.get("pets") is Array or value.pets.size() > 5 or not value.get("completed_battles") is Array:
		return false
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
			if not _integer(value.player.allocated_stats.get(stat),0,(value.player.level-1)*3):
				return false
			assigned += int(value.player.allocated_stats[stat])
		if assigned > (int(value.player.level)-1)*3:
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
	return result

func _sync_stat_points() -> void:
	var assigned := 0
	for count in _profile.player.allocated_stats.values():
		assigned += int(count)
	_profile.player.stat_points = maxi(0,(int(_profile.player.level)-1)*3-assigned)

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
