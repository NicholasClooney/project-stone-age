extends "res://server/battle_session.gd"
## Optional solo training companions; reward settlement stays with the real player.
var _acting_ally := -1

func start_battle(config: Dictionary = {}) -> Dictionary:
	if _state.active:return snapshot()
	super.start_battle(config)
	_state.allies=config.get("allies",[]).slice(0,4).duplicate(true)
	_state.ally_index=-1
	return snapshot()

func _ally_alive(index: int) -> bool:
	return index>=0 and index<_state.get("allies",[]).size() and int(_state.allies[index].hp)>0

func _extend_actors(actors: Array[Dictionary], action: String) -> void:
	for index in range(_state.allies.size()):
		_state.allies[index]["defending"]=action in ["capture","escape"]
		if _ally_alive(index):
			actors.append({"actor":"ally","ally_index":index,"speed":int(_state.allies[index].get("speed",10)),"tie":12+index})

func _actor_precedes(a: Dictionary, b: Dictionary) -> bool:
	if a.actor=="player" or b.actor=="player":return a.actor=="player"
	return super._actor_precedes(a,b)

func _extra_actor_alive(actor: Dictionary) -> bool:
	return actor.actor!="ally" or _ally_alive(int(actor.ally_index))

func _before_actor(actor: Dictionary) -> void:
	_acting_ally=int(actor.get("ally_index",-1))
	_state.ally_index=-1

func _extra_action(actor: Dictionary, action: String) -> void:
	if actor.actor!="ally":return
	if action in ["capture","escape"]:
		_last_outcome="defend"
		return
	_target=int(_state.selected_target)
	_attack_enemy(_state.allies[_acting_ally],str(_state.allies[_acting_ally].name))

func _record_frame(actor: String) -> void:
	super._record_frame(actor)
	var frame: Dictionary = _state.turn_frames.back()
	frame.allies=_state.get("allies",[]).duplicate(true)
	frame.ally_index=_acting_ally if actor=="ally" else int(_state.get("ally_index",-1))

func _attack_enemy(stats: Dictionary, actor_name: String) -> void:
	super._attack_enemy(stats,actor_name)
	# The existing kill attribution pays only the main player's actual pets.
	if _acting_ally>=0 and not _pending_counter.is_empty():
		_pending_counter.target="ally"
		_pending_counter.ally_index=_acting_ally

func _enemy_action(guarding: bool, pet_guarding: bool) -> void:
	# Negative entries delegate to the unchanged player/pet target selection.
	var targets: Array[int]=[-1]
	if not _state.pet.is_empty() and _state.pet_hp>0:targets.append(-1)
	for i in range(_state.allies.size()):
		if _ally_alive(i):targets.append(i)
	var index: int=targets[_rng.randi_range(0,targets.size()-1)]
	if index<0:
		super._enemy_action(guarding,pet_guarding)
		return
	_state.enemy_target="ally"
	_state.ally_index=index
	var ally: Dictionary=_state.allies[index]
	var enemy: Dictionary=_state.enemies[_acting_enemy]
	if str(enemy.get("command","attack"))=="defend":
		_last_outcome="defend"
		return
	var result: Dictionary=CombatRules.resolve(enemy,ally,_rng,bool(ally.get("defending",false)),str(_config.get("combat_profile","classic")))
	_last_outcome=result.outcome
	_last_damage=mini(int(result.damage),int(ally.hp))
	ally.hp-=_last_damage
	_state.events.append("对手攻击%s：%s %d。" % [str(ally.name),_last_outcome,_last_damage])
	if _ally_alive(index) and not ally.get("defending",false) and _rng.randi_range(1,10000)<int(CombatRules.odds(ally,enemy,"counter")*100):
		_pending_counter={"actor":"ally","enemy_index":_acting_enemy,"target":"enemy","ally_index":index}

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
	if not _ally_alive(index) or not _enemy_alive(_acting_enemy):return
	var ally: Dictionary=_state.allies[index]
	var enemy: Dictionary=_state.enemies[_acting_enemy]
	var from_ally: bool=counter.actor=="ally"
	var attacker: Dictionary=ally if from_ally else enemy
	var defender: Dictionary=enemy if from_ally else ally
	var result: Dictionary=CombatRules.resolve(attacker,defender,_rng,false,str(_config.get("combat_profile","classic")))
	var damage:=maxi(1,int(int(result.damage)*0.75)) if int(result.damage)>0 else 0
	_last_damage=mini(damage,int(defender.hp))
	_last_ride_damage=0
	_last_outcome="counter_miss" if result.outcome=="miss" else "counter_critical" if result.outcome=="critical" else "counter"
	defender.hp-=_last_damage
	_acting_ally=index if from_ally else -1
	_state.enemy_target="" if from_ally else "ally"
	_state.ally_index=index
	if from_ally and int(enemy.hp)==0:
		enemy.defeated_by_pet_index=_state.active_pet if _state.pet_hp>0 else -1
		enemy.defeated_with_ride_index=int(_state.get("ride_pet",-1))
	_sync_enemy(_target)
	_state.events.append("反击！%d" % _last_damage)
	_state.turn_order.append(str(counter.actor))
	_record_frame(str(counter.actor))
	if _first_enemy()<0:_finish("win","战斗胜利！")
	elif _ally_alive(index) and _enemy_alive(_acting_enemy):
		var allowed: bool=str(enemy.get("command","attack"))=="attack" if from_ally else not bool(ally.get("defending",false))
		if allowed and _rng.randi_range(1,10000)<int(CombatRules.odds(defender,attacker,"counter")*100):
			_pending_counter={"actor":"enemy" if from_ally else "ally","enemy_index":_acting_enemy,"target":"ally" if from_ally else "enemy","ally_index":index}
