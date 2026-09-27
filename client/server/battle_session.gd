extends RefCounted
## Local authority. Balance and capture threshold are explicit MVP approximations.
const PLAYER_MAX_HP := 48
const ENEMY_MAX_HP := 32
var rng_seed := 42
var _rng := RandomNumberGenerator.new()
var _state: Dictionary = {"active": false, "outcome": "", "player_hp":48,"player_max_hp":48,"enemy_hp":32,"enemy_max_hp":32,"turn":0,"events":[]}
var _config: Dictionary = {}
var _escape_attempts := 0
var _skill_used := false

func start_battle(config: Dictionary = {}) -> Dictionary:
	if _state.active:
		return snapshot()
	_config = config.duplicate(true)
	_rng.seed = rng_seed
	_escape_attempts = 0
	_skill_used = false
	var pet: Dictionary = config.get("pet", {}).duplicate(true)
	_state = {"active":true,"outcome":"","battle_id":config.get("battle_id", ""),"player_hp":config.get("player_hp",48),"player_max_hp":config.get("player_max_hp",48),"enemy_hp":config.get("enemy_max_hp",32),"enemy_max_hp":config.get("enemy_max_hp",32),"enemy_name":config.get("enemy_name","乌力"),"enemy_species":config.get("enemy_species","wooli"),"enemy_sprite":config.get("enemy_sprite",100250),"pet_sprite":pet.get("sprite",100250),"pet_name":pet.get("name",""),"skill_unlocked":pet.get("skill_unlocked",false),"boss":config.get("boss",false),"turn":0,"events":["遭遇野生石器伙伴！"],"pet":pet,"pet_command":"attack","pet_hp":pet.get("hp",0),"pet_max_hp":pet.get("max_hp",0),"potions":config.get("potions",0),"captured_species":"","xp":0,"gold":0,"skill_used":false}
	var initial_order: Array[String] = []
	_state["turn_order"] = initial_order
	_state["last_pet_command"] = "attack"
	_state["can_capture"] = bool(config.get("can_capture",true)) and not bool(config.get("boss",false))
	return snapshot()

func set_pet_command(command: String) -> bool:
	if not _state.active or _state.pet.is_empty() or command not in ["attack","skill","defend"]:
		return false
	if command == "skill" and (_skill_used or int(_state.pet.get("level",1)) < 2):
		return false
	_state.pet_command = command
	return true

func submit_action(action: String) -> Dictionary:
	if not _state.active or action not in ["attack","defend","escape","capture","item"]:
		return snapshot()
	if action == "item" and (_state.potions <= 0 or _state.player_hp >= _state.player_max_hp):
		return snapshot()
	if action == "capture" and (_state.boss or not _config.get("can_capture",true)):
		return snapshot()
	_state.turn += 1
	_state.events = []
	# Defence is selected for the whole round, even before a slower actor acts.
	var pet_command: String = _state.pet_command
	_state.last_pet_command = pet_command
	var actors: Array[Dictionary] = [
		{"actor":"player","speed":int(_config.get("player_speed",10)),"tie":0},
		{"actor":"enemy","speed":int(_config.get("enemy_speed",7)),"tie":2},
	]
	if not _state.pet.is_empty() and _state.pet_hp > 0:
		actors.append({"actor":"pet","speed":int(_state.pet.get("speed",8)),"tie":1})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.speed > b.speed or (a.speed == b.speed and a.tie < b.tie))
	var resolved_order: Array[String] = []
	_state["turn_order"] = resolved_order
	for actor in actors:
		if not _state.active:
			break
		if actor.actor == "pet" and _state.pet_hp <= 0:
			continue
		_state.turn_order.append(actor.actor)
		match actor.actor:
			"player":
				_player_action(action)
			"pet":
				_pet_action(pet_command)
			"enemy":
				_enemy_action(action == "defend",pet_command == "defend")
	_state.pet_command = "attack"
	return snapshot()

func _player_action(action: String) -> void:
	match action:
		"attack":
			var damage := maxi(1, int(_config.get("player_attack",10)) + _rng.randi_range(-2,2) - int(_config.get("enemy_defence",0)))
			_hit_enemy(damage,"你")
		"defend":
			_state.events.append("你做好防御。")
		"escape":
			_escape_attempts += 1
			if _rng.randi_range(1,100) <= mini(100,40 + 20 * _escape_attempts):
				_finish("escaped","成功逃离战斗。")
			else:
				_state.events.append("逃跑失败！下次机会增加了。")
		"capture":
			if _state.enemy_hp * 100 <= _state.enemy_max_hp * 60:
				_state.captured_species = _state.enemy_species
				_finish("captured","捕获成功！新的伙伴加入了。")
			else:
				_state.events.append("捕获失败，先削弱对手的体力！")
		"item":
			_state.potions -= 1
			_state.player_hp = mini(_state.player_max_hp,_state.player_hp + 30)
			_state.events.append("使用药草，恢复体力。")

func _pet_action(command: String) -> void:
	if command == "defend":
		return
	var damage := int(_state.pet.get("attack",4))
	if command == "skill" and not _skill_used and int(_state.pet.get("level",1)) >= 2:
		damage *= 2
		_skill_used = true
		_state.skill_used = true
	_hit_enemy(damage,str(_state.pet.get("name","伙伴")))

func _enemy_action(guarding: bool, pet_guarding: bool) -> void:
	var damage := maxi(1,int(_config.get("enemy_attack",7)) + _rng.randi_range(-2,2) - int(_config.get("player_defence",0)))
	if guarding:
		damage = maxi(1,int(damage / 2.0))
	if not _state.pet.is_empty() and _state.pet_hp > 0 and pet_guarding:
		_state.pet_hp = maxi(0,_state.pet_hp - maxi(1,int(damage / 2.0)))
		_state.pet.hp = _state.pet_hp
		_state.events.append("伙伴挡下了攻击。")
	else:
		_state.player_hp = maxi(0,_state.player_hp - damage)
		_state.events.append("对手攻击，造成 %d 点伤害。" % damage)
	if _state.player_hp == 0:
		_finish("defeat","你暂时落败，回村恢复体力。")

func _hit_enemy(damage: int, actor: String) -> void:
	damage = mini(damage,_state.enemy_hp)
	_state.enemy_hp -= damage
	_state.events.append("%s攻击，造成 %d 点伤害。" % [actor,damage])
	if _state.enemy_hp == 0:
		_finish("win","战斗胜利！")

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func _finish(outcome: String, message: String) -> void:
	_state.active = false
	_state.outcome = outcome
	if outcome == "win":
		_state.xp = int(_config.get("reward_xp",20))
		_state.gold = int(_config.get("reward_gold",10))
	_state.events.append(message)
