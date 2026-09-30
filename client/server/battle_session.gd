extends RefCounted
## Local authority for classic physical combat. Capture follows the pinned reference; escape chance remains an approximation.
const PLAYER_MAX_HP := 48
const ENEMY_MAX_HP := 32
var capture_assist := false
func set_capture_assist(enabled: bool) -> void:
	capture_assist=enabled
## Set by the backend's automation runner (自动练级, 带宠升级, 后台搜宠): a
## disobeying pet then only loses its action, so a run is never ended by a
## pet attacking its owner or leaving (docs/reverse-engineering/charm-and-loyalty.md).
var automated := false

var rng_seed := 42
var _rng := RandomNumberGenerator.new()
var _state: Dictionary = {"active": false, "outcome": "", "player_hp":48,"player_max_hp":48,"enemy_hp":32,"enemy_max_hp":32,"turn":0,"events":[]}
var _config: Dictionary = {}
var _escape_attempts := 0
var _skill_used := false
const CaptureRules = preload("res://server/capture_rules.gd")
const CombatRules = preload("res://server/classic_combat_rules.gd")
const Loyalty = preload("res://server/loyalty.gd")
const Spirits = preload("res://server/spirits.gd")
## 镜子的精灵's 气力 (itemset.txt item 1460 magicusemp).
const MIRROR_MP := 5
var _acting_enemy := 0
var _target := 0
var _pet_choice := -2
var _pet_target := -1
var _last_outcome := ""
var _last_damage := 0
var _pending_counter: Dictionary = {}
var _chosen_skill := 0
var _player_guard := false
var _player_command := "attack"
var _pet_guard := false
var _last_ride_damage := 0
## The pet's loyalty check this action ("" when it obeyed), for the frame.
var _pet_disobey := ""
## The player's 精灵 target code this turn (server/spirits.gd), and what the
## last spirit cast did, for its frame.
var _spirit_target := 0
var _last_spirit: Dictionary = {}

# Optional authority extensions. Defaults retain the original solo scheduler.
func _extend_actors(_actors: Array[Dictionary], _action: String) -> void:
	pass

func _actor_precedes(a: Dictionary, b: Dictionary) -> bool:
	return a.speed > b.speed or (a.speed == b.speed and a.tie < b.tie)

func _extra_actor_alive(_actor: Dictionary) -> bool:
	return true

func _before_actor(_actor: Dictionary) -> void:
	pass

func _extra_action(_actor: Dictionary, _action: String) -> void:
	pass

func start_battle(config: Dictionary = {}) -> Dictionary:
	if _state.active:
		return snapshot()
	capture_assist=false
	_config = config.duplicate(true)
	_rng.seed = rng_seed
	_escape_attempts = 0
	_chosen_skill = 0
	_pet_target = -1
	_skill_used = false
	var pet: Dictionary = config.get("pet", {}).duplicate(true)
	_state = {"active":true,"outcome":"","battle_id":config.get("battle_id", ""),"player_hp":config.get("player_hp",48),"player_max_hp":config.get("player_max_hp",48),"enemy_hp":config.get("enemy_max_hp",32),"enemy_max_hp":config.get("enemy_max_hp",32),"enemy_name":config.get("enemy_name","乌力"),"enemy_species":config.get("enemy_species","wooli"),"enemy_sprite":config.get("enemy_sprite",100250),"pet_sprite":pet.get("sprite",100250),"pet_name":pet.get("name",""),"skill_unlocked":pet.get("skill_unlocked",false),"boss":config.get("boss",false),"turn":0,"events":["遭遇野生石器伙伴！"],"pet":pet,"pet_command":"attack","pet_hp":pet.get("hp",0),"pet_max_hp":pet.get("max_hp",0),"potions":config.get("potions",0),"captured_species":"","xp":0,"gold":0,"skill_used":false}
	var initial_order: Array[String] = []
	_state["healing_available"]=bool(config.get("healing_available",false))
	_state["mirror_available"]=bool(config.get("mirror_available",false))
	_state["mirror_self"]=0
	_state["mirror_pets"]={}
	# 气力 and the 精灵 the worn equipment gives (GameSession.spirits()).
	_state["player_mp"]=clampi(int(config.get("player_mp",Spirits.MAX_MP)),0,Spirits.MAX_MP)
	_state["mirror_mp"]=int(config.get("mirror_mp",MIRROR_MP))
	_state["spirits"]=config.get("spirits",{}).duplicate(true)
	_state["turn_order"] = initial_order
	_state["turn_frames"] = []
	_state["player_level"] = int(config.get("player_level",1))
	_state["player_elements"] = config.get("player_elements",[0,0,0,0]).duplicate()
	_state["last_pet_command"] = "attack"
	_state["enemy_target"] = ""
	_state["can_capture"] = bool(config.get("can_capture",true)) and not bool(config.get("boss",false))
	var enemies: Array = config.get("enemies", []).duplicate(true)
	if enemies.is_empty():
		enemies.append({"name":_state.enemy_name,"species":_state.enemy_species,"sprite":_state.enemy_sprite,"max_hp":_state.enemy_max_hp,"attack":config.get("enemy_attack",7),"defence":config.get("enemy_defence",0),"speed":config.get("enemy_speed",7),"reward_xp":config.get("reward_xp",20),"reward_gold":config.get("reward_gold",10)})
	for enemy in enemies:
		enemy["hp"] = enemy.get("hp",enemy.get("max_hp",32))
		enemy["max_hp"] = enemy.get("max_hp",32)
		enemy["captured"] = false
	_state["enemies"] = enemies.slice(0,10)
	_state["pets"] = config.get("pets", [pet] if not pet.is_empty() else []).duplicate(true)
	_state["active_pet"] = int(config.get("active_pet",0 if not _state.pets.is_empty() else -1))
	_state["ride_pet"] = int(config.get("ride_pet_index",-1))
	_state["mounted_sprite"] = int(config.get("mounted_sprite",-1))
	if int(_state.ride_pet) == int(_state.active_pet): _state.active_pet = -1
	_state["selected_target"] = 0
	_state["captured_species_list"] = []
	_state["capture_success"] = false
	_state["pet_escapes"] = 0
	_sync_pet()
	_sync_enemy(0)
	return snapshot()

func set_pet_target(index: int) -> bool:
	if not _state.active or not _enemy_alive(index):
		return false
	_pet_target = index
	return true

func set_pet_skill(skill_id: int) -> bool:
	if not _state.active or _state.pet.is_empty() or skill_id not in [3,10,50] or skill_id not in _state.pet.get("learned_skills",[]):
		return false
	_chosen_skill = skill_id
	_state["selected_skill"] = skill_id
	_state.pet_command = "skill"
	return true

func set_pet_command(command: String) -> bool:
	if not _state.active or _state.pet.is_empty() or command not in ["attack","skill","defend","standby"]:
		return false
	if command == "skill" and _chosen_skill not in _state.pet.get("learned_skills",[]):
		return false
	_state.pet_command = command
	return true

func submit_action(action: String, target: int = -1, pet_index: int = -2) -> Dictionary:
	if not _state.active or (action not in ["attack","defend","escape","capture","item","switch","mirror_self","mirror_pet","heal_pet"] and not action.begins_with("spirit:")):
		return snapshot()
	if action.begins_with("spirit:"):
		if not spirit_refusal({"kind":"player","index":-1},action.trim_prefix("spirit:"),target).is_empty():return snapshot()
		_spirit_target = target
		target = -1
	if action=="heal_pet" and (not _state.healing_available or _state.active_pet<0 or _state.pet_hp<=0 or _state.pet_hp>=_state.pet_max_hp):return snapshot()
	if action.begins_with("mirror_"):
		if not _state.mirror_available or int(_state.get("player_mp",0))<int(_state.get("mirror_mp",MIRROR_MP)):return snapshot()
		if action=="mirror_pet" and (_state.active_pet<0 or _state.pet_hp<=0):return snapshot()
	if action == "item" and (_state.potions <= 0 or _state.player_hp >= _state.player_max_hp):
		return snapshot()
	if action == "capture" and (_state.boss or not _config.get("can_capture",true) or _state.captured_species_list.size() >= int(_config.get("capture_slots",5)) ):
		return snapshot()
	if action == "switch" and (pet_index < -1 or pet_index >= _state.pets.size() or pet_index == _state.active_pet or pet_index == int(_state.get("ride_pet",-1)) and pet_index >= 0):
		return snapshot()
	if action == "switch" and pet_index >= 0 and int(_state.pets[pet_index].get("hp",0)) <= 0:
		return snapshot()
	_target = target if target >= 0 else int(_state.selected_target)
	if _target >= _state.enemies.size() or _target < 0 or not _enemy_alive(_target):
		_target = _first_enemy()
	if action == "capture" and not _state.enemies[_target].get("can_capture",true):return snapshot()
	_state.selected_target = _target
	_sync_enemy(_target)
	_pet_choice = pet_index
	_state.capture_success = false
	_state.turn += 1
	_state.events = []
	_state.enemy_target = ""
	# Defence is selected for the whole round, even before a slower actor acts.
	var pet_command: String = _state.pet_command
	_state.last_pet_command = pet_command
	_player_guard = action == "defend"
	_player_command = action
	# Every device presents the turn from this, not from its own last choice:
	# an automated capture or another device's command plays its animation too.
	_state.last_player_command = action
	_pet_guard = pet_command == "defend"
	var actors: Array[Dictionary] = [
		{"actor":"player","speed":int(_player_stats().speed),"tie":0},

	]
	for index in range(_state.enemies.size()):
		if _enemy_alive(index):
			actors.append({"actor":"enemy","enemy_index":index,"speed":int(_state.enemies[index].get("speed",7)),"tie":2 + index})
	if action != "switch" and not _state.pet.is_empty() and _state.pet_hp > 0:
		actors.append({"actor":"pet","speed":int(_state.pet.get("speed",8)),"tie":1})
	_extend_actors(actors,action)
	actors.sort_custom(_actor_precedes)
	var resolved_order: Array[String] = []
	_state["turn_order"] = resolved_order
	_state["turn_frames"] = []
	for actor in actors:
		if not _state.active:
			break
		if actor.actor == "pet" and _state.pet_hp <= 0:
			continue
		if actor.actor == "enemy" and not _enemy_alive(int(actor.enemy_index)):
			continue
		if not _extra_actor_alive(actor):continue
		_before_actor(actor)
		_acting_enemy = int(actor.get("enemy_index",-1))
		_last_outcome = action if actor.actor == "player" else pet_command if actor.actor == "pet" else "attack"
		_last_damage = 0
		_last_ride_damage = 0
		_pet_disobey = ""
		_last_spirit = {}
		_pending_counter = {}
		_state.turn_order.append(actor.actor)
		match actor.actor:
			"player":
				_player_action(action)
			"pet":
				_pet_action(pet_command)
			"enemy":
				_enemy_action(action == "defend",pet_command == "defend")
			_:
				_extra_action(actor,action)
		if _state.active_pet >= 0:
			_state.pets[_state.active_pet] = _state.pet.duplicate(true)
		_record_frame(str(actor.actor))
		for counter_step in range(5):
			if not _state.active or _pending_counter.is_empty(): break
			_resolve_counter()

	_state.pet_command = pet_command if pet_command != "standby" else "attack"
	return snapshot()

func _player_action(action: String) -> void:
	match action:
		"heal_pet":
			if _state.pet_hp<=0:return # A slower healer cannot revive a fallen pet.
			_state.pet_hp=_state.pet_max_hp
			_state.pet.hp=_state.pet_hp
			_state.pets[_state.active_pet].hp=_state.pet_hp
			_last_outcome="heal_pet"
			_state.events.append("恢复护符：你为%s恢复体力，不消耗气力。"%str(_state.pet_name))
		"mirror_self","mirror_pet":
			# MAGIC_MagicDef: without the 气力 the spell does nothing.
			if int(_state.get("player_mp",0))<int(_state.get("mirror_mp",MIRROR_MP)):
				_last_outcome="spirit_fail"
				_state.events.append("气力不足，镜子的精灵没有回应。")
				return
			_state.player_mp=int(_state.player_mp)-int(_state.get("mirror_mp",MIRROR_MP))
			if action=="mirror_self":_state.mirror_self=1
			else:_state.mirror_pets[_state.active_pet]=1
			_last_outcome="mirror_cast"
			_state.events.append("镜子的精灵：%s获得一次直接攻击反射。" % ("你" if action=="mirror_self" else str(_state.pet_name)))
		"switch":
			_state.active_pet = _pet_choice
			_sync_pet()
			_chosen_skill = 0
			_state["selected_skill"] = 0
			_state.events.append("收回伙伴。" if _pet_choice == -1 else "出战：" + str(_state.pet_name))
		"attack":
			_attack_enemy(_player_stats(),"你")
		"defend":
			_state.events.append("你做好防御。")
		"escape":
			_escape_attempts += 1
			if _rng.randi_range(1,100) <= mini(100,40 + 20 * _escape_attempts):
				_finish("escaped","成功逃离战斗。")
			else:
				_state.events.append("逃跑失败！下次机会增加了。")
		"capture":
			var capture_player := {"level":_config.get("player_level",1),"speed":_config.get("player_speed",10),"charm":_config.get("player_charm",60),"luck":_config.get("player_luck",0),"capture_bonus":_config.get("capture_bonus",0)}
			var evaluation := CaptureRules.evaluate(capture_player,_state.enemies[_target])
			_config["capture_bonus"]=0 # Consumed after every attempt, including failures.
			_state["capture_evaluation"]=evaluation
			var captured := false
			if evaluation.eligible:
				var roll := _rng.randi_range(1,100)
				_state.capture_evaluation["roll"]=roll
				captured=CaptureRules.succeeds(evaluation,roll)
			if captured:
				_state.captured_species = _state.enemy_species
				_state.captured_species_list.append(_state.enemy_species)
				_state.capture_success = true
				_state.can_capture = _state.captured_species_list.size() < int(_config.get("capture_slots",5))
				_state.enemies[_target].captured = true
				_state.enemies[_target].hp = 0
				_state.enemy_hp = 0
				_last_outcome = "captured"
				if _first_enemy() < 0:
					_finish("captured","捕获成功！新的伙伴加入了。")
				else:
					_state.events.append("捕获成功！战斗继续。")
			else:
				_state.events.append("捕获失败，可继续尝试或降低目标体力。" if evaluation.eligible else str(evaluation.reason))
		"item":
			_state.potions -= 1
			_state.player_hp = mini(_state.player_max_hp,_state.player_hp + 30)
			_state.events.append("使用药草，恢复体力。")
		_:
			if action.begins_with("spirit:"):_cast_spirit({"kind":"player","index":-1},action.trim_prefix("spirit:"),_target_ref(_spirit_target))


func _pet_action(command: String) -> void:
	if command == "standby":
		# petskill.txt ID0 / PETSKILL_None: remain in place, consume the action.
		return
	# battle.c:6099: every other command first passes the loyalty check. The
	# roll is drawn only below 80, where it can matter.
	var loyalty := int(_state.pet.get("loyalty",100))
	if loyalty < Loyalty.OBEDIENT and _disobeys(command,Loyalty.check(loyalty,_rng.randi_range(1,100))):return
	if command == "defend":
		return
	_pet_perform(command,_chosen_skill,_pet_target)

## battle.c:5734 BATTLE_PetLoyalCheck: the original shows "No!" (BX,
## CG_ICON_NO) over the pet, then runs the changed command. Returns whether
## the pet's action is used up.
func _disobeys(command: String, mode: String) -> bool:
	if mode == "normal": return false
	_pet_disobey = mode
	var pet_name := str(_state.pet_name)
	if automated:
		_state.events.append("%s不听指挥，这回合没有行动。" % pet_name)
		_last_outcome = "standby"
		return true
	match mode:
		"random_target":
			# A guard (or a command at itself) becomes nothing (type 1).
			if command == "defend":
				_state.events.append("%s不听指挥，没有防御。" % pet_name)
				_last_outcome = "standby"
			else:
				_state.events.append("%s不听指挥，攻击了别的目标。" % pet_name)
				_pet_perform(command,_chosen_skill,_random_enemy())
		"random_action":
			# BATTLE_PetRandomSkill: a random one of the seven skill slots
			# (待机, 攻击, 防御, then learned skills) at a random enemy.
			var slots: Array = ["standby","attack","defend"]
			for skill in _state.pet.get("learned_skills",[]):slots.append(int(skill))
			var slot := _rng.randi_range(0,6)
			var chosen: Variant = slots[slot] if slot < slots.size() else "standby"
			_state.events.append("%s不听指挥，胡乱行动。" % pet_name)
			if chosen is int:_pet_perform("skill",int(chosen),_random_enemy())
			elif chosen == "attack":_pet_perform("attack",0,_random_enemy())
			else:_last_outcome = "standby"
		"attack_owner":
			_pet_attack_owner()
		"attack_enemy":
			_state.events.append("%s不听指挥，自己冲向敌人。" % pet_name)
			_pet_perform("attack",0,_random_enemy())
		"escape":
			_pet_escape()
	return true

func _random_enemy() -> int:
	var alive: Array[int] = []
	for index in range(_state.enemies.size()):
		if _enemy_alive(index):alive.append(index)
	return alive[_rng.randi_range(0,alive.size()-1)] if not alive.is_empty() else -1

## PETAI_MODE_OWNERATTACK: an ordinary attack on its owner.
func _pet_attack_owner() -> void:
	var stats: Dictionary = _state.pet.duplicate(true)
	stats["kind"] = "pet"
	var owner := _player_stats(true)
	owner["kind"] = "player"
	var result: Dictionary = CombatRules.resolve(stats,owner,_rng,_player_guard,str(_config.get("combat_profile","classic")))
	_last_outcome = result.outcome
	_state.enemy_target = "player"
	_apply_player_damage(int(result.damage))
	_state.events.append("%s不听指挥，攻击了主人：%s %d。" % [str(_state.pet_name),_last_outcome,_last_damage])
	if _state.player_hp == 0:
		_finish("defeat","你被自己的宠物打倒了，回村恢复体力。")

## PETAI_MODE_ESCAPE / BATTLE_LostEscape (battle_event.c:4703): the pet
## leaves the battle and is no longer the battle pet; the owner loses 1 charm
## when the battle settles (pet_escapes). The pet itself stays owned.
func _pet_escape() -> void:
	var index := int(_state.active_pet)
	_state.pets[index] = _state.pet.duplicate(true)
	_state.events.append("%s不听指挥，离开了战斗。" % str(_state.pet_name))
	_state.active_pet = -1
	_sync_pet()
	_state.pet_escapes = int(_state.get("pet_escapes",0))+1
	_last_outcome = "switch"

func _pet_perform(command: String, skill_id: int, target: int) -> void:
	if _enemy_alive(target): _target = target
	var stats: Dictionary = _state.pet.duplicate(true)
	stats["kind"] = "pet"
	if command == "skill" and skill_id in [3,10,50]:
		if skill_id == 50:
			stats.attack = int(stats.get("attack",4)) + int(int(stats.get("attack",4))*0.25)
		if skill_id == 3: stats["guard_break"] = true
		if skill_id == 10: stats["damage_divisor"] = 2
		_attack_enemy(stats,str(stats.get("name","伙伴")))
		if skill_id == 10 and _state.active and _enemy_alive(_target):
			_record_frame("pet")
			_state.turn_order.append("pet")
			_attack_enemy(stats,str(stats.get("name","伙伴")))
		return
	_attack_enemy(stats,str(stats.get("name","伙伴")))

func _player_stats(defending: bool = false) -> Dictionary:
	var stats := {"kind":"player","attack":_config.get("player_attack",10),"defence":_config.get("player_defence",0),"speed":_config.get("player_speed",10),"level":_config.get("player_level",1),"vital":_config.get("player_vital",0),"luck":_config.get("player_luck",0),"weapon":_config.get("player_weapon",""),"elements":_config.get("player_elements",[0,0,0,0])}

	stats["dex"] = float(_config.get("player_speed",10))
	var index := int(_state.get("ride_pet",-1))
	if index >= 0 and index < _state.pets.size() and int(_state.pets[index].hp) > 0:
		return preload("res://scripts/riding.gd").adjusted_stats(stats,_state.pets[index],str(_config.get("combat_profile","classic")),defending)
	return stats

func _attack_enemy(stats: Dictionary, actor_name: String) -> void:
	_pending_counter = {}
	if not _enemy_alive(_target):
		_target = _first_enemy()
	if _target < 0:
		return
	_sync_enemy(_target)
	var enemy: Dictionary = _state.enemies[_target]
	var result: Dictionary = CombatRules.resolve(stats,enemy,_rng,str(enemy.get("command","attack")) == "defend" and not stats.get("guard_break",false),str(_config.get("combat_profile","classic")))
	_last_outcome = result.outcome
	_last_damage = mini(int(int(result.damage)/int(stats.get("damage_divisor",1))),int(enemy.hp))
	enemy.hp -= _last_damage
	if int(enemy.hp) == 0:
		enemy["defeated_by_pet_index"] = _state.active_pet if _state.pet_hp > 0 else -1
		enemy["defeated_with_ride_index"] = int(_state.get("ride_pet",-1)) if stats.kind == "player" else -1
	_sync_enemy(_target)
	_state.events.append("%s攻击%s：%s %d。" % [actor_name,str(enemy.get("name","对手")),_last_outcome,_last_damage])
	if int(enemy.hp) > 0 and str(enemy.get("command","attack")) == "attack" and _rng.randi_range(1,10000) < int(CombatRules.odds(enemy,stats,"counter")*100):
		_pending_counter = {"actor":"enemy","enemy_index":_target,"target":"player" if stats.kind == "player" else "pet"}
	if _first_enemy() < 0:
		_finish("win","战斗胜利！")

func _enemy_action(guarding: bool, pet_guarding: bool) -> void:
	var pet_alive: bool = not _state.pet.is_empty() and _state.pet_hp > 0
	var target_pet: bool = pet_alive and _rng.randi_range(0,1) == 1
	_state.enemy_target = "pet" if target_pet else "player"
	var defender: Dictionary = _state.pet.duplicate(true) if target_pet else _player_stats(true)
	defender["kind"] = "pet" if target_pet else "player"
	if target_pet and _state.last_pet_command == "skill" and _chosen_skill == 50:
		defender.defence = int(defender.get("defence",0)) + int(int(defender.get("defence",0)) * -0.35)
	if str(_state.enemies[_acting_enemy].get("command","attack")) == "defend":
		_last_outcome = "defend"
		return
	var result: Dictionary = CombatRules.resolve(_state.enemies[_acting_enemy],defender,_rng,pet_guarding if target_pet else guarding,str(_config.get("combat_profile","classic")))
	_last_outcome = result.outcome
	if _reflect_incoming(int(result.damage),target_pet):return
	_last_damage = mini(int(result.damage),int(_state.pet_hp if target_pet else _state.player_hp))
	if target_pet:
		_state.pet_hp -= _last_damage
		_state.pet.hp = _state.pet_hp
	else:
		_apply_player_damage(int(result.damage))
	_state.events.append("对手攻击%s：%s %d。" % [str(_state.pet_name) if target_pet else "你",_last_outcome,_last_damage])
	var can_counter: bool = _state.pet_hp > 0 and _state.last_pet_command == "attack" if target_pet else _state.player_hp > 0 and _player_command == "attack"
	if can_counter and _rng.randi_range(1,10000) < int(CombatRules.odds(defender,_state.enemies[_acting_enemy],"counter")*100):
		_pending_counter = {"actor":"pet" if target_pet else "player","enemy_index":_acting_enemy,"target":"enemy"}
	if _state.player_hp == 0:
		_finish("defeat","你暂时落败，回村恢复体力。")

func _reflect_incoming(damage: int, target_pet: bool) -> bool:
	# battle_event.c BATTLE_DamageSub: positive direct damage reflects once,
	# before rider/pet splitting; reflection itself never generates a counter.
	var charges:=int(_state.mirror_pets.get(_state.active_pet,0)) if target_pet else int(_state.mirror_self)
	if damage<=0 or charges<=0:return false
	if target_pet:_state.mirror_pets[_state.active_pet]=0
	else:_state.mirror_self=0
	_pending_counter={}
	_last_outcome="reflect"
	var enemy:Dictionary=_state.enemies[_acting_enemy]
	_last_damage=mini(damage,int(enemy.hp))
	enemy.hp-=_last_damage
	if int(enemy.hp)==0:
		enemy.defeated_by_pet_index=_state.active_pet if _state.pet_hp>0 else -1
		enemy.defeated_with_ride_index=int(_state.get("ride_pet",-1)) if not target_pet else -1
	_sync_enemy(_acting_enemy)
	_state.events.append("镜子的精灵反射攻击！对手受到 %d 伤害。"%_last_damage)
	if _first_enemy()<0:_finish("win","战斗胜利！")
	return true

func _enemy_alive(index: int) -> bool:
	return index >= 0 and index < _state.enemies.size() and int(_state.enemies[index].hp) > 0

func _first_enemy() -> int:
	for index in range(_state.enemies.size()):
		if _enemy_alive(index):
			return index
	return -1

func _sync_enemy(index: int) -> void:
	if index < 0 or index >= _state.enemies.size():
		return
	var enemy: Dictionary = _state.enemies[index]
	for key in ["hp","max_hp","name","species","sprite"]:
		_state["enemy_" + key] = enemy.get(key,_state.get("enemy_" + key))

func _sync_pet() -> void:
	var index: int = _state.active_pet
	_state.pet = _state.pets[index].duplicate(true) if index >= 0 and index < _state.pets.size() else {}
	_state.pet_hp = _state.pet.get("hp",0)
	_state.pet_max_hp = _state.pet.get("max_hp",0)
	_state.pet_name = _state.pet.get("name","")
	_state.pet_sprite = _state.pet.get("sprite",100250)
	_state.skill_unlocked = not _state.pet.get("learned_skills",[]).is_empty()

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func _finish(outcome: String, message: String) -> void:
	_state.active = false
	_state.outcome = outcome
	if outcome in ["win","captured"]:
		for enemy in _state.enemies:
			if not enemy.captured:
				_state.xp += int(enemy.get("reward_xp",20))
				_state.gold += int(enemy.get("reward_gold",10))
	_state.events.append(message)

func _record_frame(actor: String) -> void:
	_state.turn_frames.append({"actor":actor,"player_hp":_state.player_hp,"enemy_hp":_state.enemy_hp,"pet_hp":_state.pet_hp,"enemy_target":_state.enemy_target,"enemy_index":_acting_enemy,"target_index":_target,"pet_index":_state.active_pet,"outcome":_last_outcome,"damage":_last_damage,"enemies":_state.enemies.duplicate(true),"pets":_state.pets.duplicate(true),"capture_success":_state.capture_success,"ride_pet":int(_state.get("ride_pet",-1)),"mounted_sprite":int(_state.get("mounted_sprite",-1)),"ride_damage":_last_ride_damage,"skill_id":_chosen_skill if actor == "pet" and _state.last_pet_command == "skill" and _pet_disobey.is_empty() and not _last_outcome.begins_with("counter") else 0,"disobey":_pet_disobey if actor == "pet" else ""})
	# A 精灵 cast: who cast what on whom, and each heal (the original's BJ/BD).
	if not _last_spirit.is_empty():_state.turn_frames.back().spirit = _last_spirit.duplicate(true)
	_state.turn_frames.back().player_mp = int(_state.get("player_mp",0))


func _resolve_counter() -> void:
	_last_ride_damage = 0
	var counter: Dictionary = _pending_counter
	_pending_counter = {}
	var actor := str(counter.actor)
	_acting_enemy = int(counter.enemy_index)
	_target = _acting_enemy
	var attacker: Dictionary = _state.enemies[_acting_enemy] if actor == "enemy" else _player_stats() if actor == "player" else _state.pet.duplicate(true)
	attacker["kind"] = actor
	var defender: Dictionary = (_state.enemies[_acting_enemy] if actor != "enemy" else _player_stats(true) if counter.target == "player" else _state.pet).duplicate(true)
	defender["kind"] = "enemy" if actor != "enemy" else str(counter.target)
	var result: Dictionary = CombatRules.resolve(attacker,defender,_rng,false,str(_config.get("combat_profile","classic")))
	var damage := int(int(result.damage)*0.75)
	if int(result.damage) > 0: damage = maxi(1,damage)
	_last_outcome = "counter_miss" if result.outcome == "miss" else "counter_critical" if result.outcome == "critical" else "counter"
	if actor != "enemy":
		_last_damage = mini(damage,int(_state.enemies[_target].hp))
		_state.enemies[_target].hp -= _last_damage
		if int(_state.enemies[_target].hp) == 0:
			_state.enemies[_target]["defeated_by_pet_index"] = _state.active_pet if _state.pet_hp > 0 else -1
			_state.enemies[_target]["defeated_with_ride_index"] = int(_state.get("ride_pet",-1)) if actor == "player" else -1
		_sync_enemy(_target)
	else:
		_state.enemy_target = counter.target
		if _reflect_incoming(damage,counter.target=="pet"):
			_state.turn_order.append(actor)
			_record_frame(actor)
			return
		if counter.target == "player":
			_apply_player_damage(damage)
		else:
			_last_damage = mini(damage,int(_state.pet_hp))
			_state.pet_hp -= _last_damage
			_state.pet.hp = _state.pet_hp
			_state.pets[_state.active_pet] = _state.pet.duplicate(true)
	_state.events.append("反击！%d" % _last_damage)
	_state.turn_order.append(actor)
	_record_frame(actor)
	if _state.player_hp <= 0: _finish("defeat","你暂时落败，回村恢复体力。")
	elif _first_enemy() < 0: _finish("win","战斗胜利！")
	if _state.active:
		var next_actor := str(counter.target) if actor == "enemy" else "enemy"
		var allowed: bool = _player_command == "attack" if next_actor == "player" else _state.last_pet_command == "attack" if next_actor == "pet" else str(_state.enemies[_acting_enemy].get("command","attack")) == "attack"
		var alive: bool = _state.player_hp > 0 if next_actor == "player" else _state.pet_hp > 0 if next_actor == "pet" else _enemy_alive(_acting_enemy)
		if allowed and alive and _rng.randi_range(1,10000) < int(CombatRules.odds(defender,attacker,"counter")*100):
			_pending_counter = {"actor":next_actor,"enemy_index":_acting_enemy,"target":actor}

func _apply_player_damage(damage: int) -> void:
	var player_damage := damage
	var index := int(_state.get("ride_pet",-1))
	if damage > 0 and index >= 0 and index < _state.pets.size() and int(_state.pets[index].hp) > 0:
		# battle_event.c:1738: native rider/mount damage split, including +1.
		var own_def := maxi(1,int(_config.get("player_defence",0)))
		var pet_def := maxi(1,int(_state.pets[index].get("defence",0)))
		player_damage = int(float(damage*pet_def)/float(own_def+pet_def))+1
		_last_ride_damage = mini(damage-player_damage+1,int(_state.pets[index].hp))
		_state.pets[index].hp -= _last_ride_damage
		if int(_state.pets[index].hp) <= 0:
			_state.ride_pet = -1
			_state.mounted_sprite = -1
			_state.events.append("骑乘伙伴倒下了，下骑。")
	_last_damage = mini(player_damage,int(_state.player_hp))
	_state.player_hp -= _last_damage

func developer_escape() -> Dictionary:
	return _end_without_rewards(true,"DEV：立即脱战，不获得经验、石币或捕获奖励。")

## The find-pet cycle gives up a capture battle it cannot finish (the target
## went down or can no longer be caught): the battle ends like an escape, with
## no experience, coins or capture, and without developer_escape's GM mark.
func abandon() -> Dictionary:
	return _end_without_rewards(false,"放弃这场捕捉战斗，不获得经验、石币或捕获奖励。")

func _end_without_rewards(developer: bool, note: String) -> Dictionary:
	if not bool(_state.get("active",false)):return snapshot()
	_state.turn+=1
	_state.events=[]
	_state.turn_order=["player"]
	_state.turn_frames=[]
	_state.capture_success=false
	_state.captured_species=""
	_state.captured_species_list=[]
	for enemy in _state.enemies:enemy.captured=false
	_state.xp=0
	_state.gold=0
	if developer:_state.gm_escape=true
	_last_outcome="escape"
	_last_damage=0
	_last_ride_damage=0
	_acting_enemy=-1
	_target=maxi(0,int(_state.get("selected_target",0)))
	_finish("escaped",note)
	_record_frame("player")
	return snapshot()

# ---- 精灵 (server/spirits.gd, docs/reverse-engineering/magic-and-mp.md) ------
# A member of the player's side is a ref {kind, index}: player, pet (the
# player's battle pet), ally i and ally_pet i (squads and party battles), or
# side (the whole side, for 恩惠). Target codes are the caster's own view.

## The ref a target code names, seen from the player (party battles map
## their members' views, party_battle_session.gd).
func _target_ref(code: int, _viewer: int = 0) -> Dictionary:
	if code==Spirits.SIDE:return {"kind":"side","index":-1}
	if code==Spirits.SELF:return {"kind":"player","index":-1}
	if code==Spirits.OWN_PET:return {"kind":"pet","index":-1}
	if code>=2 and code<=9:return {"kind":"ally" if code%2==0 else "ally_pet","index":int((code-2)/2)}
	return {}

## The ref is in the battle (not escaped; a fallen one is still in it).
func _ref_present(ref: Dictionary) -> bool:
	match str(ref.get("kind","")):
		"player":return true
		"pet":return not _state.pet.is_empty()
		"ally","ally_pet":
			var i := int(ref.index)
			var allies: Array = _state.get("allies",[])
			if i<0 or i>=allies.size() or bool(allies[i].get("escaped",false)):return false
			return ref.kind=="ally" or (i<_state.get("ally_pets",[]).size() and not _state.ally_pets[i].is_empty())
	return false

func _ref_actor(ref: Dictionary) -> Dictionary:
	match str(ref.kind):
		"player":return {"hp":_state.player_hp,"max_hp":_state.player_max_hp,"name":"你"}
		"pet":return _state.pet
		"ally":return _state.allies[int(ref.index)]
		"ally_pet":return _state.ally_pets[int(ref.index)]
	return {}

func _ref_hp(ref: Dictionary) -> int:
	return int(_state.player_hp) if ref.kind=="player" else int(_state.pet_hp) if ref.kind=="pet" else int(_ref_actor(ref).get("hp",0))

func _ref_max(ref: Dictionary) -> int:
	return int(_state.player_max_hp) if ref.kind=="player" else int(_state.pet_max_hp) if ref.kind=="pet" else int(_ref_actor(ref).get("max_hp",1))

func _ref_set_hp(ref: Dictionary, hp: int) -> void:
	match str(ref.kind):
		"player":_state.player_hp = hp
		"pet":
			_state.pet_hp = hp
			_state.pet.hp = hp
			if int(_state.active_pet)>=0 and int(_state.active_pet)<_state.pets.size():_state.pets[_state.active_pet].hp = hp
		_:_ref_actor(ref).hp = hp

func _ref_name(ref: Dictionary) -> String:
	if ref.kind=="player":return "你"
	return str(_ref_actor(ref).get("name","宠物" if str(ref.kind).ends_with("pet") else "队友"))

## The rider's living mount as a dictionary to change in place, or {}.
func _ref_mount(ref: Dictionary) -> Dictionary:
	if ref.kind=="player":
		var index := int(_state.get("ride_pet",-1))
		if index>=0 and index<_state.pets.size() and int(_state.pets[index].hp)>0:return _state.pets[index]
	elif ref.kind=="ally":
		var mount: Dictionary = _ref_actor(ref).get("mount",{})
		if int(mount.get("hp",0))>0:return mount
	return {}

## Every present member of the player's side (BATTLE_MultiList's side).
func _side_refs() -> Array:
	var result: Array = [{"kind":"player","index":-1},{"kind":"pet","index":-1}]
	for i in range(_state.get("allies",[]).size()):
		result.append({"kind":"ally","index":i})
		result.append({"kind":"ally_pet","index":i})
	return result.filter(_ref_present)

func _living_side() -> Array:
	return _side_refs().filter(func(ref):return _ref_hp(ref)>0)

## The caster's 气力 and spirits: the player's, or ally i's (party battles).
func _caster_mp(caster: Dictionary) -> int:
	return int(_state.get("player_mp",0)) if caster.kind=="player" else int(_state.allies[int(caster.index)].get("mp",0))

func _set_caster_mp(caster: Dictionary, mp: int) -> void:
	if caster.kind=="player":_state.player_mp = mp
	else:_state.allies[int(caster.index)].mp = mp

func _caster_spirits(caster: Dictionary) -> Dictionary:
	return _state.get("spirits",{}) if caster.kind=="player" else _state.allies[int(caster.index)].get("spirits",{})

## Why this 精灵 command cannot be given ("" when it can): the battle 精灵
## menu's rules (battlemenu.cpp:755: a map-only spell or too little 气力 is
## refused; the target is one the spell's MAGIC_TARGET allows).
func spirit_refusal(caster: Dictionary, slot: String, code: int, viewer: int = 0) -> String:
	var spirit: Dictionary = _caster_spirits(caster).get(slot,{})
	if spirit.is_empty():return "没有装备这个精灵。"
	if str(spirit.get("kind","")) not in ["recovery","ressurect"]:return "这个精灵在战斗菜单里还不能用。"
	if int(spirit.field)==Spirits.FIELD_MAP:return "%s只能在战斗外使用。" % str(spirit.name)
	if not Spirits.target_fits(spirit,code):return "这个精灵不能对这个目标使用。"
	if _caster_mp(caster)<int(spirit.mp):return Spirits.NO_MP
	if code!=Spirits.SIDE:
		var ref := _target_ref(code,viewer)
		if ref.is_empty() or not _ref_present(ref):return "目标不在战斗中。"
		# The client offers only standing targets unless the spell revives.
		if not bool(spirit.dead) and _ref_hp(ref)<=0:return "目标已经倒下。"
	return ""

## MAGIC_DirectUse -> MAGIC_Recovery / MAGIC_OtherRecovery / MAGIC_Ressurect:
## 气力 first (too little and nothing happens), then BATTLE_MultiRecovery or
## BATTLE_MultiRessurect. A single heal on a target that fell meanwhile goes
## to a random standing member of the side (BATTLE_MultiList).
func _cast_spirit(caster: Dictionary, slot: String, target: Dictionary) -> void:
	var spirit: Dictionary = _caster_spirits(caster).get(slot,{})
	var who := _ref_name(caster)
	_last_outcome = "spirit_fail"
	if spirit.is_empty() or target.is_empty():return
	var mp := _caster_mp(caster)
	if mp<int(spirit.mp):
		_state.events.append("%s的气力不足，%s没有回应。" % [who,str(spirit.name)])
		return
	_set_caster_mp(caster,mp-int(spirit.mp))
	_last_outcome = "spirit"
	var power := int(spirit.power)
	var heals: Array = []
	if str(spirit.kind)=="ressurect":
		# BATTLE_MultiListDead: only a fallen member; else nothing, 气力 spent.
		if target.kind!="side" and _ref_present(target) and _ref_hp(target)<=0:
			var gained := Spirits.revive_hp(power,_ref_max(target),_rng)
			_ref_set_hp(target,gained)
			heals.append({"kind":target.kind,"index":int(target.get("index",-1)),"amount":gained,"mount_amount":0,"revived":true})
			_state.events.append("%s使用%s，%s恢复意识（体力 %d）。" % [who,str(spirit.name),_ref_name(target),gained])
		else:
			_state.events.append("%s使用%s，但没有倒下的目标。" % [who,str(spirit.name)])
	else:
		var refs: Array = []
		if int(spirit.target)==Spirits.TARGET_MYSELF:refs = [caster]
		elif target.kind=="side":refs = _living_side()
		elif _ref_present(target) and _ref_hp(target)>0:refs = [target]
		else:
			var standing := _living_side()
			if not standing.is_empty():refs = [standing[_rng.randi_range(0,standing.size()-1)]]
		var parts: PackedStringArray = []
		for ref in refs:
			var amount := Spirits.battle_heal(power,_rng)
			var own := amount
			var mount_part := 0
			var mount := _ref_mount(ref)
			var hp := _ref_hp(ref)
			if not mount.is_empty():
				var split: Array = Spirits.split_heal(amount,hp,_ref_max(ref),int(mount.hp),int(mount.max_hp))
				own = int(split[0])
				mount_part = int(split[1])
				mount.hp = mini(int(mount.max_hp),int(mount.hp)+mount_part)
			_ref_set_hp(ref,mini(_ref_max(ref),hp+own))
			heals.append({"kind":ref.kind,"index":int(ref.get("index",-1)),"amount":own,"mount_amount":mount_part,"revived":false})
			parts.append("%s耐久力回复%d" % [_ref_name(ref),own]+("（骑宠 %d）" % mount_part if mount_part>0 else ""))
		_state.events.append("%s使用%s：%s。" % [who,str(spirit.name),"，".join(parts) if not parts.is_empty() else "没有目标"])
	_last_spirit = {"slot":slot,"item":str(spirit.get("item","")),"magic":int(spirit.magic),"name":str(spirit.name),"kind":str(spirit.kind),"caster":caster.duplicate(),"target":target.duplicate(),"user_effect":Spirits.EFFECT_USER,"effect":Spirits.target_effect(str(spirit.kind),power),"heals":heals}
