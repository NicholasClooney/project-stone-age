extends RefCounted
## Single-player authority. Prototype rules; original art/data do not imply formula parity.
const SAVE_VERSION := 1
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
	_profile = {"version":SAVE_VERSION,"profile_id":"samgir-singleplayer-v1","player":{"hp":48,"max_hp":48,"level":1,"xp":0,"gold":20,"attack":10,"defence":0,"speed":10,"stat_points":0,"allocated_stats":{"vitality":0,"strength":0,"toughness":0,"dexterity":0}},"inventory":{"potion":2,"club":0},"equipped":false,"pets":[],"active_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1}

func snapshot() -> Dictionary:
	return _profile.duplicate(true)

func start_battle_config(species: String = "wooli", boss: bool = false) -> Dictionary:
	if not SPECIES.has(species) or not _pending.is_empty() or (boss and not can_fight_boss()):
		return {}
	var enemy: Dictionary = SPECIES[species]
	var player: Dictionary = _profile.player
	var pet: Dictionary = {}
	if _profile.active_pet >= 0:
		pet = _profile.pets[_profile.active_pet].duplicate(true)
	var config := {"battle_id":"battle-%d" % _profile.next_battle,"player_hp":player.hp,"player_max_hp":player.max_hp,"player_attack":player.attack + (4 if _profile.equipped else 0),"player_defence":player.defence,"player_speed":player.speed,"enemy_species":species,"enemy_name":("强壮的" if boss else "") + enemy.name,"enemy_sprite":enemy.sprite,"enemy_max_hp":enemy.hp * (2 if boss else 1),"enemy_attack":enemy.attack + (3 if boss else 0),"enemy_defence":enemy.defence,"enemy_speed":enemy.speed,"boss":boss,"pet":pet,"potions":_profile.inventory.potion,"can_capture":_profile.pets.size() < 5,"reward_xp":60 if boss else 20,"reward_gold":30 if boss else 10}
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
	var enemy_hp := int(result.get("enemy_hp",-1))
	if enemy_hp < 0 or enemy_hp > _pending.enemy_max_hp or (outcome == "win" and enemy_hp != 0) or (outcome == "defeat" and hp != 0) or (outcome != "defeat" and hp == 0):
		return false
	if outcome == "captured" and (enemy_hp <= 0 or enemy_hp * 100 > _pending.enemy_max_hp * 60):
		return false
	if outcome == "captured" and (_pending.boss or not _pending.can_capture or result.get("captured_species","") != _pending.enemy_species):
		return false
	_profile.player.hp = hp
	_profile.inventory.potion = potions
	if _profile.active_pet >= 0:
		var pet: Dictionary = _profile.pets[_profile.active_pet]
		pet.hp = clampi(int(result.get("pet_hp",pet.hp)),0,pet.max_hp)
	if outcome == "win":
		_profile.player.gold += _pending.reward_gold
		_gain_xp(_profile.player,_pending.reward_xp)
		if _profile.active_pet >= 0:
			_gain_xp(_profile.pets[_profile.active_pet],_pending.reward_xp)
		if _profile.quest.accepted and not _profile.quest.claimed:
			if _pending.boss:
				_profile.quest.boss_defeated = true
			else:
				_profile.quest.wins += 1
	elif outcome == "captured":
		var species: String = _pending.enemy_species
		var base: Dictionary = SPECIES[species]
		_profile.pets.append({"species":species,"name":base.name,"sprite":base.sprite,"hp":base.hp,"max_hp":base.hp,"attack":4 + base.defence,"defence":base.defence,"speed":base.speed,"level":1,"xp":0,"skill_unlocked":false})
		if _profile.pets.size() == 1:
			_profile.active_pet = 0
	elif outcome == "defeat":
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
			actor.max_hp += 8
			actor.attack += 2
			actor.speed = int(actor.get("speed",10)) + 1
			actor.skill_unlocked = actor.level >= 2
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
			# Earlier prototype saves predate speed; migrate only this optional field.
			if not _profile.player.has("speed"):
				_profile.player.speed = 10 + _profile.player.level - 1
			for pet in _profile.pets:
				if not pet.has("speed"):
					pet.speed = SPECIES[pet.species].speed + pet.level - 1
			if not _profile.player.has("allocated_stats"):
				# Preserve existing prototype gains, credit missed allocation once.
				_profile.player.allocated_stats = {"vitality":0,"strength":0,"toughness":0,"dexterity":0}
				_profile.player.stat_points = (_profile.player.level-1)*3
			return true
	last_error = "No valid save or backup."
	return false

func _valid_profile(value: Variant) -> bool:
	if not value is Dictionary or value.get("version",0) != SAVE_VERSION or value.get("profile_id", "") != "samgir-singleplayer-v1":
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
	if value.player.has("allocated_stats") or value.player.has("stat_points"):
		if not value.player.get("allocated_stats") is Dictionary or not _integer(value.player.get("stat_points"),0,(value.player.level-1)*3):
			return false
		var assigned := 0
		for stat in ["vitality","strength","toughness","dexterity"]:
			if not _integer(value.player.allocated_stats.get(stat),0,(value.player.level-1)*3):
				return false
			assigned += int(value.player.allocated_stats[stat])
		if assigned + int(value.player.stat_points) != (int(value.player.level)-1)*3:
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
		if pet.get("sprite") != SPECIES[pet.species].sprite:
			return false
	return true

func _actor_valid(actor: Dictionary) -> bool:
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
	if not _integer(location.get("map_id"),0,10000):
		return false
	var map_id := int(location.map_id)
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
	# char.c CHAR_SkillUp uses four base stats and consumes exactly one point.
	# MVP uses primary effects only; fractional cross-stat formulas are deferred.
	var p: Dictionary = _profile.player
	if not _pending.is_empty() or not p.allocated_stats.has(stat) or p.stat_points <= 0:
		return false
	p.stat_points -= 1
	p.allocated_stats[stat] += 1
	match stat:
		"vitality":
			p.max_hp += 4
			p.hp += 4
		"strength":p.attack += 1
		"toughness":p.defence += 1
		"dexterity":p.speed += 1
	return true
