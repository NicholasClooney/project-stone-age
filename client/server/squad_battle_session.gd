extends "res://server/battle_session.gd"
## Optional solo training companions; reward settlement stays with the real player.
var _acting_ally := -1
var _acting_kind := "ally"

func start_battle(config: Dictionary = {}) -> Dictionary:
	if _state.active:return snapshot()
	super.start_battle(config)
	_state.allies=config.get("allies",[]).slice(0,4).duplicate(true)
	_state.ally_pets=config.get("ally_pets",[]).slice(0,4).duplicate(true)
	while _state.ally_pets.size()<_state.allies.size():_state.ally_pets.append({})
	for i in range(_state.allies.size()):_refresh_mount(i)
	_state.ally_index=-1
	return snapshot()

func _member(index: int, kind: String = "ally") -> Dictionary:
	return _state.ally_pets[index] if kind=="ally_pet" else _state.allies[index]

func _ally_alive(index: int, kind: String = "ally") -> bool:
	return index>=0 and index<_state.get("allies",[]).size() and int(_member(index,kind).get("hp",0))>0

func _refresh_mount(index: int, defending: bool = false) -> Dictionary:
	var ally: Dictionary=_state.allies[index]
	var base: Dictionary=ally.get("base_stats",{"attack":ally.attack,"defence":ally.defence,"speed":ally.speed})
	var stats:=ally.duplicate(true)
	stats.merge(base,true)
	stats.dex=base.speed
	if int(ally.get("mount",{}).get("hp",0))>0:
		stats=preload("res://scripts/riding.gd").adjusted_stats(stats,ally.mount,str(_config.get("combat_profile","classic")),defending)
	for key in ["attack","defence","speed"]:ally[key]=stats[key]
	return stats

func _stats(index: int, kind: String, defending: bool = false) -> Dictionary:
	if kind=="ally":return _refresh_mount(index,defending)
	var pet:=_member(index,kind).duplicate(true)
	pet.kind="pet"
	return pet

func _extend_actors(actors: Array[Dictionary], action: String) -> void:
	for index in range(_state.allies.size()):
		for kind in ["ally","ally_pet"]:
			if not _ally_alive(index,kind):continue
			_member(index,kind)["defending"]=capture_assist or action in ["capture","escape"]
			actors.append({"actor":kind,"ally_index":index,"speed":int(_stats(index,kind).get("speed",10)),"tie":12+index+(4 if kind=="ally_pet" else 0)})

func _actor_precedes(a: Dictionary, b: Dictionary) -> bool:
	if a.actor=="player" or b.actor=="player":return a.actor=="player"
	return super._actor_precedes(a,b)

func _extra_actor_alive(actor: Dictionary) -> bool:
	return actor.actor not in ["ally","ally_pet"] or _ally_alive(int(actor.ally_index),str(actor.actor))

func _before_actor(actor: Dictionary) -> void:
	_acting_ally=int(actor.get("ally_index",-1))
	_acting_kind=str(actor.actor)
	_state.ally_index=-1

func _extra_action(actor: Dictionary, action: String) -> void:
	if actor.actor not in ["ally","ally_pet"]:return
	if capture_assist or action in ["capture","escape"]:
		_last_outcome="defend"
		return
	_target=int(_state.selected_target)
	_attack_enemy(_stats(_acting_ally,_acting_kind),str(_member(_acting_ally,_acting_kind).name))

func _record_frame(actor: String) -> void:
	super._record_frame(actor)
	var frame: Dictionary = _state.turn_frames.back()
	frame.allies=_state.get("allies",[]).duplicate(true)
	frame.ally_pets=_state.get("ally_pets",[]).duplicate(true)
	frame.ally_index=_acting_ally if actor in ["ally","ally_pet"] else int(_state.get("ally_index",-1))

func _attack_enemy(stats: Dictionary, actor_name: String) -> void:
	super._attack_enemy(stats,actor_name)
	if _acting_ally>=0 and _target>=0 and int(_state.enemies[_target].hp)==0:
		_state.enemies[_target].defeated_with_ride_index=int(_state.get("ride_pet",-1))
	# The existing kill attribution pays only the main player's actual pets.
	if _acting_ally>=0 and not _pending_counter.is_empty():
		_pending_counter.target=_acting_kind
		_pending_counter.ally_index=_acting_ally

func _enemy_action(guarding: bool, pet_guarding: bool) -> void:
	# Negative entries delegate to the unchanged player/pet target selection.
	var targets: Array[int]=[-1]
	if not _state.pet.is_empty() and _state.pet_hp>0:targets.append(-1)
	for i in range(_state.allies.size()):
		if _ally_alive(i):targets.append(i)
		if _ally_alive(i,"ally_pet"):targets.append(i+4)
	var index: int=targets[_rng.randi_range(0,targets.size()-1)]
	if index<0:
		super._enemy_action(guarding,pet_guarding)
		return
	var kind: String="ally_pet" if index>=4 else "ally"
	index=index%4
	_state.enemy_target=kind
	_state.ally_index=index
	var ally: Dictionary=_member(index,kind)
	var enemy: Dictionary=_state.enemies[_acting_enemy]
	if str(enemy.get("command","attack"))=="defend":
		_last_outcome="defend"
		return
	var result: Dictionary=CombatRules.resolve(enemy,_stats(index,kind,true),_rng,bool(ally.get("defending",false)),str(_config.get("combat_profile","classic")))
	_last_outcome=result.outcome
	_apply_member_damage(index,kind,int(result.damage))
	_state.events.append("对手攻击%s：%s %d。" % [str(ally.name),_last_outcome,_last_damage])
	if _ally_alive(index,kind) and not ally.get("defending",false) and _rng.randi_range(1,10000)<int(CombatRules.odds(ally,enemy,"counter")*100):
		_pending_counter={"actor":kind,"enemy_index":_acting_enemy,"target":"enemy","ally_index":index}

func _resolve_counter() -> void:
	if not _pending_counter.has("ally_index"):
		_acting_ally=-1
		super._resolve_counter()
		return
	var counter: Dictionary=_pending_counter
	_pending_counter={}
	var index:=int(counter.ally_index)
	_acting_enemy=int(counter.enemy_index)
	_target=_acting_enemy
	var kind: String=str(counter.actor) if counter.actor!="enemy" else str(counter.target)
	if not _ally_alive(index,kind) or not _enemy_alive(_acting_enemy):return
	var ally: Dictionary=_member(index,kind)
	var enemy: Dictionary=_state.enemies[_acting_enemy]
	var from_ally: bool=counter.actor!="enemy"
	var attacker: Dictionary=_stats(index,kind) if from_ally else enemy
	var defender: Dictionary=enemy if from_ally else _stats(index,kind,true)
	var result: Dictionary=CombatRules.resolve(attacker,defender,_rng,false,str(_config.get("combat_profile","classic")))
	var damage:=maxi(1,int(int(result.damage)*0.75)) if int(result.damage)>0 else 0
	_last_damage=mini(damage,int(defender.hp))
	_last_ride_damage=0
	_last_outcome="counter_miss" if result.outcome=="miss" else "counter_critical" if result.outcome=="critical" else "counter"
	if from_ally:enemy.hp-=_last_damage
	else:_apply_member_damage(index,kind,damage)
	_acting_ally=index if from_ally else -1
	_acting_kind=kind
	_state.enemy_target="" if from_ally else kind
	_state.ally_index=index
	if from_ally and int(enemy.hp)==0:
		enemy.defeated_by_pet_index=_state.active_pet if _state.pet_hp>0 else -1
		enemy.defeated_with_ride_index=int(_state.get("ride_pet",-1))
	_sync_enemy(_target)
	_state.events.append("反击！%d" % _last_damage)
	_state.turn_order.append(str(counter.actor))
	_record_frame(str(counter.actor))
	if _first_enemy()<0:_finish("win","战斗胜利！")
	elif _ally_alive(index,kind) and _enemy_alive(_acting_enemy):
		var allowed: bool=str(enemy.get("command","attack"))=="attack" if from_ally else not bool(ally.get("defending",false))
		if allowed and _rng.randi_range(1,10000)<int(CombatRules.odds(defender,attacker,"counter")*100):
			_pending_counter={"actor":"enemy" if from_ally else kind,"enemy_index":_acting_enemy,"target":kind if from_ally else "enemy","ally_index":index}

func _apply_member_damage(index: int, kind: String, damage: int) -> void:
	var member:=_member(index,kind)
	var own_damage:=damage
	_last_ride_damage=0
	if kind=="ally" and damage>0 and int(member.get("mount",{}).get("hp",0))>0:
		var own_def:=maxi(1,int(member.base_stats.defence))
		var pet_def:=maxi(1,int(member.mount.get("defence",0)))
		own_damage=int(float(damage*pet_def)/float(own_def+pet_def))+1
		_last_ride_damage=mini(damage-own_damage+1,int(member.mount.hp))
		member.mount.hp-=_last_ride_damage
		if int(member.mount.hp)<=0:
			member.mounted_sprite=-1
			_refresh_mount(index)
	_last_damage=mini(own_damage,int(member.hp))
	member.hp-=_last_damage
