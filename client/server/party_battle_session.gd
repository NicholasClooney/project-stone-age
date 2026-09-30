extends "res://server/squad_battle_session.gd"
## LAN phase 4a (docs/development/lan-profiles.md "Phase 4a"): one battle for
## a whole 组队 party, on the squad layout (五人镜像队: 5 players and 5 pets a
## side). Slot 0 is the leader, in the base session's player fields; slot k
## (1..4) is member k, SquadBattleSession's ally k-1 with ally pet k-1.
##
## The original (gmsv battle/battle.c):
## - BATTLE_PartyNewEntry puts every party member not already fighting on
##   the leader's side, each with their default pet.
## - BATTLE_CommandWait: the turn waits until every living player sent a
##   command. Ours waits for every living connected player, and the host
##   (server/party_battles.gd) resolves it anyway after TURN_SECONDS: a
##   player who has not commanded auto-attacks that turn (the original drops
##   them from the battle and the party after 120 s; we never drop anyone).
## - Escape takes only that player (and their pet) out; the others fight on.
## - A player who falls stays in the battle until it ends. Their side loses
##   only when no player is left standing.
## - BATTLE_AddExpItem: each defeated enemy's CHAR_EXP goes whole to every
##   actor credited with it, reduced when that actor is more than
##   EXPGET_MAXLEVEL levels above the enemy (x (20-gap)/15, at least 1); a
##   rider's mount gets 60 %. BATTLE_GetExpGold then pays only living
##   players and their living pets. `share_exp` (队伍共享经验, ours, on by
##   default) credits every living member and their pets with every enemy.
##
## This file holds no clock, sockets or profiles: commands come in per slot,
## and the host decides when a turn resolves. Refused in 4a: capture and pet
## switching (4b) and 镜子的精灵. Members' pets always obey (the loyalty
## check runs for the leader's pet only; 4b). The healing 精灵
## (server/spirits.gd) work for every player: each casts from its own 气力
## on anyone on the party's side (a teammate, a pet, the whole side), and
## 复活精灵 gets a fallen teammate back up.
const BattleAutoPolicy = preload("res://scripts/battle_auto_policy.gd")
const Riding = preload("res://scripts/riding.gd")
const EXPGET_MAXLEVEL := 5
const EXPGET_DIV := 15
const TURN_SECONDS := 45
const ACTIONS := ["attack","defend","item","escape"]
const PET_COMMANDS := ["attack","skill","defend","standby"]

## 队伍共享经验 for this battle (the party's switch when it started).
var share_exp := true
## Slot -> true: this slot's command comes from the automatic source instead
## of a device, and the turn does not wait for it: its player has no device
## online (the clone AI's attack), or turned on 组队自动战斗 (LAN phase 4c).
var auto_slots: Dictionary = {}
## Slot -> {hp, spirit}: a member's 组队自动战斗 preset (_auto_command). `hp`
## is the player's own 停机线 in percent: at or below it the slot heals
## (a 精灵 when `spirit` and 气力 allow, else a 回复药).
var auto_policies: Dictionary = {}
## Slot -> {name, id, character_id, weapon}.
var slot_info: Array = []
## Slot -> this turn's command {action, target}, cleared when the turn resolves.
var _commands: Dictionary = {}
## Slot -> the pet's standing order {command, skill, target} (kept between
## turns, like the base session's pet_command).
var _pet_orders: Dictionary = {}
## Slot -> the last action the slot took, and the pet command it ran.
var _last_actions: Dictionary = {}
var _last_pet: Dictionary = {}
## Slot -> true once that player escaped (it is out of the battle).
var _escaped: Dictionary = {}
var _escape_tries: Dictionary = {}
## Slot -> true once its fall was announced.
var _fallen: Dictionary = {}
## Members' pet rosters (slot -> pets at the start), kept outside the ally
## dictionaries so turn frames stay small.
var _rosters: Dictionary = {}
var _escaping_slot := -1

func start_battle(config: Dictionary = {}) -> Dictionary:
	if _state.active:return snapshot()
	var members: Array = config.get("party_members",[])
	var allies: Array = []
	var ally_pets: Array = []
	for i in range(mini(4,members.size())):
		var member: Dictionary = members[i]
		allies.append(member.ally)
		ally_pets.append(member.pet)
		_rosters[i+1] = member.pets.duplicate(true)
	var squad := config.duplicate(true)
	squad.allies = allies
	squad.ally_pets = ally_pets
	super.start_battle(squad)
	_state.can_capture = false
	_state.mirror_available = false
	# 恢复护符: each player heals its own pet with its own charm (the leader's
	# here; members' in their ally entry).
	_state.healing_available = bool(config.get("healing_available",false))
	_state.party = true
	slot_info = config.get("party_slots",[]).duplicate(true)
	share_exp = bool(config.get("share_exp",true))
	return snapshot()

func slot_count() -> int:
	return 1+_state.get("allies",[]).size()

## A slot still in the battle (not escaped; fallen players stay in).
func slot_in(slot: int) -> bool:
	return slot>=0 and slot<slot_count() and not _escaped.has(slot) and (slot==0 or not bool(_state.allies[slot-1].get("escaped",false)))

func slot_hp(slot: int) -> int:
	return int(_state.player_hp) if slot==0 else int(_state.allies[slot-1].hp)

## In the battle and standing: it commands this turn.
func slot_standing(slot: int) -> bool:
	return slot_in(slot) and slot_hp(slot)>0

func slot_escaped(slot: int) -> bool:
	return _escaped.has(slot)

func has_command(slot: int) -> bool:
	return _commands.has(slot)

## Standing players whose command the turn still waits for.
func waiting_slots() -> Array:
	var result: Array = []
	if not bool(_state.active):return result
	for slot in range(slot_count()):
		if slot_standing(slot) and not auto_slots.has(slot) and not _commands.has(slot):result.append(slot)
	return result

## One player's command for this turn. "" when accepted, else why not.
func submit_slot(slot: int, action: String, target: int = -1) -> String:
	if not bool(_state.active):return "战斗已经结束。"
	if not slot_in(slot):return "你已经离开这场战斗。"
	if slot_hp(slot)<=0:return "你已倒下，等待队友结束战斗。"
	if action in ["capture","switch"]:return "组队战斗暂不能捕捉或换宠（下一阶段开放）。"
	if action in ["mirror_self","mirror_pet"]:return "组队战斗暂不能使用镜子的精灵。"
	if action.begins_with("spirit:"):
		var why := spirit_refusal(_caster(slot),action.trim_prefix("spirit:"),target,slot)
		if not why.is_empty():return why
		_commands[slot] = {"action":action,"target":target,"ref":_target_ref(target,slot)}
		return ""
	if action=="heal_pet":
		var pet := _slot_pet(slot)
		if not slot_healing(slot):return "没有恢复护符。"
		if pet.is_empty() or int(pet.get("hp",0))<=0 or int(pet.get("hp",0))>=int(pet.get("max_hp",0)):return "出战宠物已倒下或体力已满。"
		_commands[slot] = {"action":action,"target":target}
		return ""
	if not action in ACTIONS:return "未知指令。"
	if action=="item":
		var potions := int(_state.potions) if slot==0 else int(_state.allies[slot-1].get("potions",0))
		var full := slot_hp(slot)>=(int(_state.player_max_hp) if slot==0 else int(_state.allies[slot-1].max_hp))
		if potions<=0 or full:return "没有回复药，或体力已满。"
	_commands[slot] = {"action":action,"target":target}
	return ""

## The pet's standing order for a slot. False when refused.
func set_slot_pet(slot: int, command: String, skill_id: int = 0, target: int = -2) -> bool:
	if not bool(_state.active) or not slot_in(slot) or not command in PET_COMMANDS:return false
	var pet := _slot_pet(slot)
	if pet.is_empty():return false
	if command=="skill" and (skill_id not in [3,10,50] or skill_id not in pet.get("learned_skills",[])):return false
	var order: Dictionary = _pet_orders.get(slot,{"command":"attack","skill":0,"target":-1})
	order.command = command
	if command=="skill":order.skill = skill_id
	if target>-2:order.target = target
	_pet_orders[slot] = order
	return true

func set_slot_pet_target(slot: int, target: int) -> void:
	var order: Dictionary = _pet_orders.get(slot,{"command":"attack","skill":0,"target":-1})
	order.target = target
	_pet_orders[slot] = order

func _slot_pet(slot: int) -> Dictionary:
	return _state.pet if slot==0 else _state.ally_pets[slot-1]

## Another slot's command this turn already casts a whole-side heal (恩惠).
func _side_heal_taken(slot: int) -> bool:
	for other in _commands:
		if int(other)==slot:continue
		var command: Dictionary = _commands[other]
		if not str(command.get("action","")).begins_with("spirit:") or str(command.get("ref",{}).get("kind",""))!="side":continue
		var spirit: Dictionary = _caster_spirits(_caster(int(other))).get(str(command.action).trim_prefix("spirit:"),{})
		if str(spirit.get("kind",""))=="recovery":return true
	return false

## The slot's player as a 精灵 caster ref.
func _caster(slot: int) -> Dictionary:
	return {"kind":"player","index":-1} if slot==0 else {"kind":"ally","index":slot-1}

## A target code as member `viewer` sees the battle (view_for): 0 itself,
## 1 its pet, 2+2p / 3+2p the p-th ally on its screen (the leader first,
## then the other members in order) and that ally's pet, SIDE the party.
func _target_ref(code: int, viewer: int = 0) -> Dictionary:
	if viewer<=0 or code==Spirits.SIDE:return super._target_ref(code,viewer)
	if code==Spirits.SELF:return {"kind":"ally","index":viewer-1}
	if code==Spirits.OWN_PET:return {"kind":"ally_pet","index":viewer-1}
	if code<2 or code>9:return {}
	var position := int((code-2)/2)
	var pet := code%2==1
	if position==0:return {"kind":"pet" if pet else "player","index":-1}
	for member in range(_state.get("allies",[]).size()):
		if member!=viewer-1 and _ally_position(viewer,member)==position:return {"kind":"ally_pet" if pet else "ally","index":member}
	return {}

## A canonical ref as member `slot` sees it (the inverse of _target_ref).
func _view_ref(ref: Dictionary, slot: int) -> Dictionary:
	var kind := str(ref.get("kind",""))
	var index := int(ref.get("index",-1))
	match kind:
		"player":return {"kind":"ally","index":0}
		"pet":return {"kind":"ally_pet","index":0}
		"ally","ally_pet":
			var pet := kind=="ally_pet"
			if index==slot-1:return {"kind":"pet" if pet else "player","index":-1}
			return {"kind":kind,"index":_ally_position(slot,index)}
	return ref.duplicate()

## The leader and its pet are out once the leader escaped.
func _ref_present(ref: Dictionary) -> bool:
	if str(ref.get("kind","")) in ["player","pet"] and not slot_in(0):return false
	return super._ref_present(ref)

## The slot's player carries a 恢复护符 (it is never used up).
func slot_healing(slot: int) -> bool:
	if slot==0:return bool(_state.get("healing_available",false))
	return slot>0 and slot<slot_count() and bool(_state.allies[slot-1].get("healing",false))

## The automatic command source. Without a preset the clone AI attacks
## (squad allies attack the selected enemy). A member's 组队自动战斗 preset
## (LAN phase 4c) plays as 自动练级's 普通攻击 does (battle_auto_policy.gd):
## the first standing enemy, the pet attacking with it; and at or below the
## player's own 停机线, with a 回复药 left, it drinks one instead.
func _auto_command(slot: int) -> Dictionary:
	if not auto_policies.has(slot):return {"action":"attack","target":-1}
	# A healing 精灵 before a 回复药 (LAN phase 4c presets, 用精灵补血): the
	# player at its line, a teammate at that line, a fallen teammate.
	if bool(auto_policies[slot].get("spirit",true)):
		# 全体补血: one 恩惠 a turn is enough. The leader's command comes in
		# first, then the automatic slots in slot order; a slot skips 恩惠 when
		# an earlier command this turn already casts it.
		var cast: Dictionary = BattleAutoPolicy.spirit_choice(view_for(slot),int(auto_policies[slot].get("hp",10)),true,int(auto_policies[slot].get("side",0)),_side_heal_taken(slot))
		if not cast.is_empty():
			return {"action":str(cast.action),"target":int(cast.target),"ref":_target_ref(int(cast.target),slot),"auto":true}
	# As battle_auto_policy.gd: a pet at half its hp or less gets the 恢复护符.
	var own_pet := _slot_pet(slot)
	if slot_healing(slot) and not own_pet.is_empty() and int(own_pet.get("hp",0))>0 and int(own_pet.get("hp",0))*2<=int(own_pet.get("max_hp",0)):
		var guard: Dictionary = _pet_orders.get(slot,{"command":"attack","skill":0,"target":-1})
		guard.command = "defend"
		_pet_orders[slot] = guard
		return {"action":"heal_pet","target":-1,"auto":true}
	var hp := slot_hp(slot)
	var max_hp := int(_state.player_max_hp) if slot==0 else int(_state.allies[slot-1].max_hp)
	var potions := int(_state.potions) if slot==0 else int(_state.allies[slot-1].get("potions",0))
	if potions>0 and hp<max_hp and hp*100<=max_hp*int(auto_policies[slot].get("hp",10)):return {"action":"item","target":-1,"auto":true}
	var target := _first_enemy()
	if not _slot_pet(slot).is_empty():
		var order: Dictionary = _pet_orders.get(slot,{"command":"attack","skill":0,"target":-1})
		order.command = "attack"
		order.target = target
		_pet_orders[slot] = order
	return {"action":"attack","target":target,"auto":true}

## Resolves the turn: every standing player without a command gets the
## automatic one (the 45 s timer, a disconnected player). `timed_out`: the
## names of players the timer ran out on, for the turn's events.
func resolve_turn(timed_out: Array = []) -> Dictionary:
	if not bool(_state.active):return snapshot()
	for slot in range(slot_count()):
		if slot_standing(slot) and not _commands.has(slot):_commands[slot] = _auto_command(slot)
	for slot in _commands:_last_actions[slot] = str(_commands[slot].action)
	for slot in range(slot_count()):
		var order: Dictionary = _pet_orders.get(slot,{})
		_last_pet[slot] = str(order.get("command","attack"))
	# The leader's pet order goes through the base session's own checks.
	var lead: Dictionary = _pet_orders.get(0,{})
	if not _state.pet.is_empty():
		if str(lead.get("command","attack"))=="skill":set_pet_skill(int(lead.get("skill",0)))
		else:set_pet_command(str(lead.get("command","attack")))
		if int(lead.get("target",-1))>=0:set_pet_target(int(lead.target))
	var own: Dictionary = _commands.get(0,{"action":"defend","target":-1})
	submit_action(str(own.action),int(own.target),-2)
	for name in timed_out:_state.events.push_front("%s超时未下指令，自动攻击。" % str(name))
	_commands.clear()
	_check_end()
	return snapshot()

# ---- actors and actions -----------------------------------------------------

func _ally_alive(index: int, kind: String = "ally") -> bool:
	return super._ally_alive(index,kind) and not bool(_state.allies[index].get("escaped",false))

func _extend_actors(actors: Array[Dictionary], _action: String) -> void:
	# The leader acts only while standing; its pet leaves when it escaped.
	for i in range(actors.size()-1,-1,-1):
		var who := str(actors[i].actor)
		if (who=="player" and not slot_standing(0)) or (who=="pet" and not slot_in(0)):actors.remove_at(i)
	for index in range(_state.allies.size()):
		var slot := index+1
		var command: Dictionary = _commands.get(slot,{})
		_state.allies[index].defending = str(command.get("action",""))=="defend"
		_state.ally_pets[index].defending = str(_pet_orders.get(slot,{}).get("command",""))=="defend"
		if _ally_alive(index):
			actors.append({"actor":"ally","ally_index":index,"speed":int(_stats(index,"ally").get("speed",10)),"tie":12+index})
		if _ally_alive(index,"ally_pet"):
			actors.append({"actor":"ally_pet","ally_index":index,"speed":int(_stats(index,"ally_pet").get("speed",10)),"tie":16+index})

func _extra_actor_alive(actor: Dictionary) -> bool:
	match str(actor.actor):
		"player":return slot_standing(0)
		"pet":return slot_in(0)
	return super._extra_actor_alive(actor)

func _player_action(action: String) -> void:
	_escaping_slot = 0 if action=="escape" else -1
	super._player_action(action)
	_escaping_slot = -1

func _extra_action(actor: Dictionary, _action: String) -> void:
	var index := int(actor.ally_index)
	var slot := index+1
	var member: Dictionary = _state.allies[index]
	var name := str(member.name)
	if actor.actor=="ally_pet":
		_member_pet_action(index)
		return
	var command: Dictionary = _commands.get(slot,_auto_command(slot))
	_last_outcome = str(command.action)
	if str(command.action).begins_with("spirit:"):
		_cast_spirit(_caster(slot),str(command.action).trim_prefix("spirit:"),command.get("ref",_target_ref(int(command.target),slot)))
		return
	match str(command.action):
		"attack":
			_target = int(command.target) if _enemy_alive(int(command.target)) else int(_state.selected_target)
			_attack_enemy(_stats(index,"ally"),name)
		"defend":
			_state.events.append("%s做好防御。" % name)
		"item":
			member.potions = int(member.get("potions",0))-1
			var before := int(member.hp)
			member.hp = mini(int(member.max_hp),int(member.hp)+30)
			_last_damage = int(member.hp)-before
			_state.events.append("%s使用药草，恢复体力。" % name)
		"heal_pet":
			# 恢复护符: the member's own pet back to full (a fallen one stays down).
			var pet: Dictionary = _state.ally_pets[index]
			if pet.is_empty() or int(pet.get("hp",0))<=0:return
			var before := int(pet.hp)
			pet.hp = int(pet.max_hp)
			_last_damage = int(pet.hp)-before
			_state.events.append("恢复护符：%s为%s恢复体力，不消耗气力。" % [name,str(pet.get("name","宠物"))])
		"escape":
			_escape_tries[slot] = int(_escape_tries.get(slot,0))+1
			if _rng.randi_range(1,100)<=mini(100,40+20*int(_escape_tries[slot])):
				member.escaped = true
				_escaped[slot] = true
				_state.events.append("%s成功逃离战斗。" % name)
			else:
				_state.events.append("%s逃跑失败！" % name)

## A member's pet: its standing order (attack, skill 3/10/50, defend, standby).
func _member_pet_action(index: int) -> void:
	var slot := index+1
	var order: Dictionary = _pet_orders.get(slot,{"command":"attack","skill":0,"target":-1})
	var command := str(order.get("command","attack"))
	var pet: Dictionary = _state.ally_pets[index]
	_last_outcome = command
	if command in ["standby","defend"]:return
	var stats := _stats(index,"ally_pet")
	var skill := int(order.get("skill",0)) if command=="skill" else 0
	if skill==50:stats.attack = int(stats.get("attack",4))+int(int(stats.get("attack",4))*0.25)
	if skill==3:stats.guard_break = true
	if skill==10:stats.damage_divisor = 2
	_target = int(order.get("target",-1)) if _enemy_alive(int(order.get("target",-1))) else int(_state.selected_target)
	_attack_enemy(stats,str(pet.get("name","宠物")))
	if skill==10 and _state.active and _enemy_alive(_target):
		_record_frame("ally_pet")
		_state.turn_order.append("ally_pet")
		_attack_enemy(stats,str(pet.get("name","宠物")))

func _attack_enemy(stats: Dictionary, actor_name: String) -> void:
	super._attack_enemy(stats,actor_name)
	# The squad credits allies' kills to the leader's pets and mount; in a
	# party each kill is credited to its own slot (_credit_kills, which marks
	# the enemy once this action's frame is recorded).
	if _acting_ally>=0 and _target>=0 and int(_state.enemies[_target].hp)==0 and not _state.enemies[_target].has("killer"):
		_state.enemies[_target].defeated_by_pet_index = -1
		_state.enemies[_target].defeated_with_ride_index = -1

## Enemies pick any standing player or living pet still in the battle.
func _enemy_action(guarding: bool, pet_guarding: bool) -> void:
	var targets: Array = []
	if slot_standing(0):targets.append(["player",-1])
	if slot_in(0) and not _state.pet.is_empty() and int(_state.pet_hp)>0:targets.append(["pet",-1])
	for i in range(_state.allies.size()):
		if _ally_alive(i):targets.append(["ally",i])
		if _ally_alive(i,"ally_pet"):targets.append(["ally_pet",i])
	var enemy: Dictionary = _state.enemies[_acting_enemy]
	if targets.is_empty() or str(enemy.get("command","attack"))=="defend":
		_last_outcome = "defend"
		return
	var pick: Array = targets[_rng.randi_range(0,targets.size()-1)]
	if int(pick[1])<0:
		_enemy_hits_leader(str(pick[0])=="pet",guarding,pet_guarding)
		return
	var kind := str(pick[0])
	var index := int(pick[1])
	_state.enemy_target = kind
	_state.ally_index = index
	var ally: Dictionary = _member(index,kind)
	var result: Dictionary = CombatRules.resolve(enemy,_stats(index,kind,true),_rng,bool(ally.get("defending",false)),str(_config.get("combat_profile","classic")))
	_last_outcome = result.outcome
	_apply_member_damage(index,kind,int(result.damage))
	_state.events.append("对手攻击%s：%s %d。" % [str(ally.name),_last_outcome,_last_damage])
	if _ally_alive(index,kind) and not ally.get("defending",false) and _rng.randi_range(1,10000)<int(CombatRules.odds(ally,enemy,"counter")*100):
		_pending_counter = {"actor":kind,"enemy_index":_acting_enemy,"target":"enemy","ally_index":index}

## The base session's enemy attack on the leader or its pet, target chosen.
func _enemy_hits_leader(target_pet: bool, guarding: bool, pet_guarding: bool) -> void:
	_state.enemy_target = "pet" if target_pet else "player"
	var defender: Dictionary = _state.pet.duplicate(true) if target_pet else _player_stats(true)
	defender["kind"] = "pet" if target_pet else "player"
	if target_pet and _state.last_pet_command == "skill" and _chosen_skill == 50:
		defender.defence = int(defender.get("defence",0)) + int(int(defender.get("defence",0)) * -0.35)
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
	if _state.player_hp == 0:_finish("defeat","")

## The base session ends the battle when the leader falls or escapes; in a
## party that only takes the leader out, until nobody is left standing.
func _finish(outcome: String, message: String) -> void:
	if bool(_state.active) and outcome=="defeat":
		_check_end()
		return
	if bool(_state.active) and outcome=="escaped" and _escaping_slot==0:
		_escaped[0] = true
		_state.events.append("%s成功逃离战斗。" % _slot_name(0))
		_check_end()
		return
	super._finish(outcome,message)

## Falls are announced once; with no player standing the battle is over:
## lost if anyone fell, else everyone escaped.
func _check_end() -> void:
	if not bool(_state.active):return
	# The leader falling to the counter that took the last enemy: still a win.
	if _first_enemy()<0:
		super._finish("win","战斗胜利！")
		return
	var anyone := false
	var fell := false
	for slot in range(slot_count()):
		if not slot_in(slot):continue
		if slot_hp(slot)>0:
			anyone = true
			# 复活精灵 got it up: a later fall is announced again.
			_fallen.erase(slot)
		else:
			fell = true
			if not _fallen.has(slot):
				_fallen[slot] = true
				_state.events.append("%s倒下了。" % _slot_name(slot))
	if anyone:return
	if fell:super._finish("defeat","全队倒下，回村恢复体力。")
	else:super._finish("escaped","全员逃离战斗。")

func _slot_name(slot: int) -> String:
	if slot<slot_info.size():return str(slot_info[slot].get("name","队友"))
	return "队长" if slot==0 else str(_state.allies[slot-1].get("name","队友"))

func _record_frame(actor: String) -> void:
	super._record_frame(actor)
	_credit_kills(actor)
	var frame: Dictionary = _state.turn_frames.back()
	frame.escaped = _escaped.keys()
	_check_end()

## Who defeated each enemy (BATTLE_AddExpItem's attacker list): the slot, the
## player or its pet, the pet's roster index, and the rider's mount.
func _credit_kills(actor: String) -> void:
	for enemy in _state.enemies:
		if int(enemy.hp)!=0 or bool(enemy.get("captured",false)) or enemy.has("killer"):continue
		var slot := 0
		var kind := "player"
		var pet := -1
		var ride := -1
		match actor:
			"player":ride = int(_state.get("ride_pet",-1))
			"pet":
				kind = "pet"
				pet = int(_state.active_pet)
			"ally","ally_pet":
				slot = _acting_ally+1
				var member: Dictionary = _state.allies[_acting_ally]
				if actor=="ally_pet":
					kind = "pet"
					pet = int(member.get("active_pet",-1))
				elif int(member.get("mount",{}).get("hp",0))>0:ride = int(member.get("ride_pet",-1))
			_:continue
		enemy.killer = {"slot":slot,"kind":kind,"pet":pet,"ride":ride}

# ---- rewards and settlement -------------------------------------------------

## battle.c BATTLE_AddExpItem's level gap: whole below EXPGET_MAXLEVEL levels
## above the enemy, then x (20-gap)/15, at least 1.
static func gap_exp(exp: int, level: int, enemy_level: int) -> int:
	var gap := level-enemy_level
	if gap<=EXPGET_MAXLEVEL:return exp
	var share := mini(EXPGET_MAXLEVEL+EXPGET_DIV-gap,EXPGET_DIV)
	if share<=0:return 1
	return maxi(1,exp*share/EXPGET_DIV)

## The slot's roster at the start, its battle pet and its mount indices, its
## level and experience multiplier.
func _slot_roster(slot: int) -> Array:
	return _state.pets if slot==0 else _rosters.get(slot,[])

func _slot_level(slot: int) -> int:
	return int(_state.get("player_level",1)) if slot==0 else int(_state.allies[slot-1].get("level",1))

func _slot_active_pet(slot: int) -> int:
	if slot==0:return int(_state.active_pet)
	var member: Dictionary = _state.allies[slot-1]
	return int(member.get("active_pet",-1)) if not _state.ally_pets[slot-1].is_empty() else -1

func _slot_ride(slot: int) -> int:
	if slot==0:return int(_state.get("ride_pet",-1))
	var member: Dictionary = _state.allies[slot-1]
	return int(member.get("ride_pet",-1)) if int(member.get("mount",{}).get("hp",0))>0 else -1

func _slot_multiplier(slot: int) -> int:
	if slot<slot_info.size():return maxi(1,int(slot_info[slot].get("multiplier",1)))
	return 1

## Experience for one slot: {player, pets: [per roster index]}. Only a win
## pays, only standing players (BATTLE_GetExpGold); dead pets are dropped at
## settlement (GameSession.apply_battle_result).
func rewards_for(slot: int) -> Dictionary:
	var roster: Array = _slot_roster(slot)
	var pets: Array = []
	pets.resize(roster.size())
	pets.fill(0)
	var result := {"player":0,"pets":pets}
	if str(_state.outcome)!="win" or not slot_standing(slot):return result
	var level := _slot_level(slot)
	var active := _slot_active_pet(slot)
	var ride := _slot_ride(slot)
	var multiplier := _slot_multiplier(slot)
	for enemy in _state.enemies:
		if bool(enemy.get("captured",false)) or int(enemy.hp)!=0:continue
		var exp := int(enemy.get("reward_xp",0))*multiplier
		var enemy_level := int(enemy.get("level",1))
		var killer: Dictionary = enemy.get("killer",{})
		if share_exp:
			result.player += gap_exp(exp,level,enemy_level)
			if active>=0 and active<roster.size():pets[active] += gap_exp(exp,int(roster[active].get("level",1)),enemy_level)
			if ride>=0 and ride<roster.size():pets[ride] += Riding.experience(exp,int(roster[ride].get("level",1)),enemy_level)
		elif int(killer.get("slot",-1))==slot:
			if str(killer.kind)=="player":
				result.player += gap_exp(exp,level,enemy_level)
				var mount := int(killer.get("ride",-1))
				if mount>=0 and mount<roster.size():pets[mount] += Riding.experience(exp,int(roster[mount].get("level",1)),enemy_level)
			else:
				var pet := int(killer.get("pet",-1))
				if pet>=0 and pet<roster.size():pets[pet] += gap_exp(exp,int(roster[pet].get("level",1)),enemy_level)
	return result

## The slot's own outcome: escaped, win, or defeat. A player who fell in a
## battle the party won is "defeat" with party_stay (1 HP where it stands).
func slot_outcome(slot: int) -> Dictionary:
	if slot_escaped(slot) or (slot>0 and bool(_state.allies[slot-1].get("escaped",false))):return {"outcome":"escaped","stay":false}
	var ended := str(_state.outcome)
	var down := slot_hp(slot)<=0
	if ended=="defeat":return {"outcome":"defeat","stay":false}
	if down:return {"outcome":"defeat","stay":true}
	return {"outcome":"win" if ended in ["win","captured"] else "escaped","stay":false}

## The slot's current pet roster (hp as now in the battle).
func _slot_pets(slot: int, source: Dictionary = {}) -> Array:
	if slot==0:return (source.get("pets",_state.pets) if not source.is_empty() else _state.pets).duplicate(true)
	var roster: Array = _slot_roster(slot).duplicate(true)
	var allies: Array = source.get("allies",_state.allies) if not source.is_empty() else _state.allies
	var ally_pets: Array = source.get("ally_pets",_state.ally_pets) if not source.is_empty() else _state.ally_pets
	var member: Dictionary = allies[slot-1]
	var active := int(member.get("active_pet",-1))
	if active>=0 and active<roster.size() and not ally_pets[slot-1].is_empty():roster[active].hp = int(ally_pets[slot-1].get("hp",0))
	var ride := int(member.get("ride_pet",-1))
	if ride>=0 and ride<roster.size() and not member.get("mount",{}).is_empty():roster[ride].hp = int(member.mount.get("hp",0))
	return roster

## Enemies as one slot's settlement reads them: kill credit for its own pet
## and mount only (loyalty), everything else as the battle has it.
func _slot_enemies(slot: int, enemies: Array) -> Array:
	var result: Array = enemies.duplicate(true)
	for enemy in result:
		var killer: Dictionary = enemy.get("killer",{})
		var own := int(killer.get("slot",-1))==slot
		enemy.defeated_by_pet_index = int(killer.get("pet",-1)) if own and str(killer.get("kind",""))=="pet" else -1
		enemy.defeated_with_ride_index = int(killer.get("ride",-1)) if own and str(killer.get("kind",""))=="player" else -1
	return result

## What GameSession.apply_battle_result of this slot's profile takes, once
## the slot is out (escaped) or the battle is over. `battle_id` is that
## profile's own pending battle id.
func slice_for(slot: int, battle_id: String) -> Dictionary:
	var ending := slot_outcome(slot)
	var result := {"active":false,"battle_id":battle_id,"outcome":ending.outcome,"party_stay":ending.stay,"captured_species_list":[],"enemies":_slot_enemies(slot,_state.enemies),"pets":_slot_pets(slot),"party_xp":rewards_for(slot) if ending.outcome=="win" else {"player":0,"pets":_zeros(_slot_roster(slot).size())}}
	if slot==0:
		result.player_hp = int(_state.player_hp)
		result.player_mp = int(_state.get("player_mp",0))
		result.potions = int(_state.potions)
		result.active_pet = int(_state.active_pet)
		result.ride_pet = int(_state.get("ride_pet",-1))
		result.pet_escapes = int(_state.get("pet_escapes",0))
	else:
		var member: Dictionary = _state.allies[slot-1]
		result.player_hp = int(member.hp)
		result.player_mp = int(member.get("mp",0))
		result.potions = int(member.get("potions",0))
		result.active_pet = int(member.get("active_pet",-1))
		result.ride_pet = _slot_ride(slot)
		result.pet_escapes = 0
	return result

static func _zeros(count: int) -> Array:
	var result: Array = []
	result.resize(count)
	result.fill(0)
	return result

# ---- each device's view -----------------------------------------------------

## The battle as slot `slot`'s devices see it: their own character in the
## player's place (its hp, potions, pets, commands), the other players as
## allies. The client's battle view then works as in a solo battle.
func view_for(slot: int) -> Dictionary:
	var canonical := snapshot()
	var view: Dictionary = canonical if slot==0 else _remap(canonical,slot)
	view.enemies = _slot_enemies(slot,canonical.enemies)
	view.party_slot = slot
	view.can_capture = false
	view.mirror_available = false
	view.healing_available = slot_healing(slot)
	var order: Dictionary = _pet_orders.get(slot,{})
	view.pet_command = str(order.get("command","attack"))
	view.selected_skill = int(order.get("skill",0))
	view.last_pet_command = str(_last_pet.get(slot,"attack"))
	view.last_player_command = str(_last_actions.get(slot,"attack"))
	var out := not slot_in(slot)
	if out:
		# This player escaped: its battle is over, whatever the others do.
		view.active = false
		view.outcome = "escaped"
	elif not bool(view.active) and str(view.outcome)!="defeat" and slot_hp(slot)<=0 and not out:
		# The party won or escaped; this fallen player gets up where it is.
		view.party_fallen = true
	for i in range(view.turn_frames.size()):
		view.turn_frames[i].enemies = _slot_enemies(slot,view.turn_frames[i].get("enemies",[]))
	return view

## Canonical order: leader, members 0..n-1. In member k's view the leader is
## ally 0 and the other members follow in order.
func _ally_position(slot: int, member_index: int) -> int:
	return member_index+1 if member_index<slot-1 else member_index

func _remap(canonical: Dictionary, slot: int) -> Dictionary:
	var view: Dictionary = canonical.duplicate(true)
	_remap_fields(view,canonical,slot)
	var frames: Array = []
	for frame in canonical.get("turn_frames",[]):
		var copy: Dictionary = frame.duplicate(true)
		_remap_fields(copy,frame,slot)
		frames.append(copy)
	view.turn_frames = frames
	var order: Array = []
	for who in canonical.get("turn_order",[]):order.append({"player":"ally","pet":"ally_pet"}.get(str(who),str(who)))
	view.turn_order = order
	var me := str(slot_info[slot].get("name","")) if slot<slot_info.size() else ""
	var leader := _slot_name(0)
	var events: Array = []
	for line in canonical.get("events",[]):
		var text := str(line).replace("你",leader)
		if not me.is_empty():text = text.replace(me,"你")
		events.append(text)
	view.events = events
	return view

## One state or frame from the leader's side to member `slot`'s side.
func _remap_fields(target: Dictionary, source: Dictionary, slot: int) -> void:
	var index := slot-1
	var allies: Array = source.get("allies",[])
	var ally_pets: Array = source.get("ally_pets",[])
	if index>=allies.size():return
	var me: Dictionary = allies[index]
	var pet: Dictionary = ally_pets[index] if index<ally_pets.size() else {}
	target.player_hp = int(me.hp)
	target.player_max_hp = int(me.max_hp)
	target.pet_hp = int(pet.get("hp",0))
	target.pet_max_hp = int(pet.get("max_hp",0))
	target.pets = _slot_pets(slot,source)
	if source.has("player_mp"):target.player_mp = int(me.get("mp",0))
	# A 精灵 cast's caster, target and healed, from this member's side.
	if source.has("spirit"):
		var spirit: Dictionary = source.spirit.duplicate(true)
		spirit.caster = _view_ref(spirit.caster,slot)
		spirit.target = _view_ref(spirit.target,slot)
		for heal in spirit.heals:
			var seen := _view_ref(heal,slot)
			heal.kind = seen.kind
			heal.index = seen.index
		target.spirit = spirit

	target.pet_index = int(me.get("active_pet",-1)) if not pet.is_empty() else -1
	target.ride_pet = int(me.get("ride_pet",-1)) if int(me.get("mount",{}).get("hp",0))>0 else -1
	target.mounted_sprite = int(me.get("mounted_sprite",-1))
	if source.has("potions") or source.has("player_level"):
		target.potions = int(me.get("potions",0))
		target.player_mp = int(me.get("mp",0))
		target.spirits = me.get("spirits",{}).duplicate(true)
		target.player_level = int(me.get("level",1))
		target.player_elements = me.get("elements",[0,0,0,0]).duplicate()
		target.pet = pet.duplicate(true)
		target.pet_name = str(pet.get("name",""))
		target.pet_sprite = int(pet.get("sprite",100250))
		target.skill_unlocked = not pet.get("learned_skills",[]).is_empty()
		target.active_pet = target.pet_index
	var others: Array = [_leader_as_ally(source)]
	var other_pets: Array = [_leader_pet_as_ally(source)]
	for j in range(allies.size()):
		if j==index:continue
		others.append(allies[j])
		other_pets.append(ally_pets[j] if j<ally_pets.size() else {})
	target.allies = others
	target.ally_pets = other_pets
	# Who acted and who was hit, from this member's side.
	var who := str(source.get("actor",""))
	var ally_index := int(source.get("ally_index",-1))
	if source.has("actor"):
		match who:
			"player":
				target.actor = "ally"
				target.ally_index = 0
			"pet":
				target.actor = "ally_pet"
				target.ally_index = 0
			"ally","ally_pet":
				if ally_index==index:target.actor = "player" if who=="ally" else "pet"
				else:target.ally_index = _ally_position(slot,ally_index)
			"enemy":pass
		target.disobey = ""
		target.skill_id = 0
	# enemy_target is only meaningful on an enemy's frame (it lingers on
	# later frames of the turn) and on the state itself.
	var hit := str(source.get("enemy_target","")) if who in ["","enemy"] else ""
	match hit:
		"player":
			target.enemy_target = "ally"
			target.ally_index = 0
		"pet":
			target.enemy_target = "ally_pet"
			target.ally_index = 0
		"ally","ally_pet":
			if ally_index==index:target.enemy_target = "player" if hit=="ally" else "pet"
			else:target.ally_index = _ally_position(slot,ally_index)

## The leader drawn as an ally on a member's screen.
func _leader_as_ally(source: Dictionary) -> Dictionary:
	var info: Dictionary = slot_info[0] if not slot_info.is_empty() else {}
	var pets: Array = source.get("pets",_state.pets)
	var ride := int(source.get("ride_pet",_state.get("ride_pet",-1)))
	var mount: Dictionary = pets[ride].duplicate(true) if ride>=0 and ride<pets.size() else {}
	return {"name":str(info.get("name","队长")),"character_id":str(info.get("character_id","100000")),"weapon":str(info.get("weapon","")),"kind":"player","hp":int(source.get("player_hp",_state.player_hp)),"max_hp":int(_state.player_max_hp),"level":int(_state.get("player_level",1)),"elements":_state.get("player_elements",[0,0,0,0]).duplicate(),"mount":mount,"mounted_sprite":int(source.get("mounted_sprite",_state.get("mounted_sprite",-1))),"defending":str(_commands.get(0,{}).get("action",_last_actions.get(0,"")))=="defend","escaped":_escaped.has(0)}

func _leader_pet_as_ally(source: Dictionary) -> Dictionary:
	if _escaped.has(0):return {}
	var index := int(source.get("pet_index",source.get("active_pet",_state.active_pet)))
	var pets: Array = source.get("pets",_state.pets)
	if index<0 or index>=pets.size():return {}
	var pet: Dictionary = pets[index].duplicate(true)
	pet.hp = int(source.get("pet_hp",pet.get("hp",0)))
	pet.defending = str(_last_pet.get(0,""))=="defend"
	return pet
