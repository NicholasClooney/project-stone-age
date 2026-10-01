extends RefCounted
## Real battle core and automation policy, advanced one turn at a time.
## It never settles a profile or claims drops. The first trial has precisely
## the seed the actual next battle will use; four following seeds test luck.
const Solo=preload("res://server/battle_session.gd")
const Squad=preload("res://server/squad_battle_session.gd")
const Party=preload("res://server/party_battle_session.gd")
const Policy=preload("res://scripts/battle_auto_policy.gd")
const TRIALS=5
const TURN_LIMIT=200
var config: Dictionary={}
var settings: Dictionary={}
var first_seed:=0
var ready:=false
var wins:=0
var trials:=0
var reason:=""
var _battle
var _turn:=0
var _party:=false
var _first_won:=false

func begin(source: Dictionary, run: Dictionary, seed_value: int) -> void:
	config=source.duplicate(true);settings=run.duplicate(true);first_seed=seed_value
	ready=false;wins=0;trials=0;reason="";_battle=null;_first_won=false;_party=config.has("party_members")

func _finish(won: bool, why: String) -> void:
	if trials==0:_first_won=won
	wins+=1 if won else 0;trials+=1
	if not won and reason.is_empty():reason=why
	_battle=null
	ready=trials>=TRIALS

func advance(budget_usec: int=1000) -> void:
	var deadline:=Time.get_ticks_usec()+maxi(1,budget_usec)
	while not ready and Time.get_ticks_usec()<deadline:
		if _battle==null:
			_battle=Party.new() if _party else Squad.new() if not config.get("allies",[]).is_empty() else Solo.new()
			_battle.rng_seed=first_seed+trials;_battle.start_battle(config);_battle.automated=true;_turn=0
			if _party:_battle.auto_policies=config.get("training_party_policies",{}).duplicate(true)
		var state: Dictionary=_battle.snapshot()
		if not bool(state.active):_finish(str(state.outcome) in ["win","captured"],str(state.outcome));continue
		if _turn>=TURN_LIMIT:_finish(false,"超过%d回合"%TURN_LIMIT);continue
		var line:=int(settings.get("hp",10))
		var action:="";var pet:="defend";var target:=-1
		if not _party and bool(state.get("healing_available",false)) and int(state.get("pet_hp",0))>0 and int(state.pet_hp)*100<=int(state.get("pet_max_hp",1))*maxi(50,line):action="heal_pet"
		if action.is_empty() and bool(settings.get("spirit",true)):
			var cast: Dictionary=Policy.spirit_choice(state,line,_party,int(settings.get("side_heal",50)))
			if not cast.is_empty():action=str(cast.action);target=int(cast.target)
		if action.is_empty():
			var watched:=state.duplicate()
			if bool(settings.get("protect",true)) and not _party:watched.active_pet=-1
			var low:=Policy.health_stop(watched,line,int(config.get("ride_pet_index",-1)))
			if not low.is_empty():
				if _party and int(state.player_hp)*100<=int(state.player_max_hp)*line and int(state.get("potions",0))>0:action="item"
				elif _party and int(state.get("pet_hp",0))>0 and bool(state.get("healing_available",false)):action="heal_pet"
				else:_finish(false,low);continue
		if action.is_empty():
			var decision: Dictionary=Policy.decide(state,settings,-1)
			if decision.has("stop"):_finish(false,str(decision.stop));continue
			action=str(decision.action);pet=str(decision.pet);target=int(decision.target)
		if _party:
			_battle.set_slot_pet(0,pet,0,target);_battle.submit_slot(0,action,target);_battle.resolve_turn()
		else:
			_battle.set_pet_command(pet);_battle.set_pet_target(target);_battle.submit_action(action,target)
		_turn+=1

func summary() -> Dictionary:
	return {"ready":ready,"ok":ready and _first_won and TRIALS-wins<=1,"wins":wins,"trials":trials,"reason":reason}
