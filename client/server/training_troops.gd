extends RefCounted
## Non-original training convenience. Read-only expected rewards of the actual
## local catalog; no samples, encounter RNG or invented high-level enemy pool.
const Art = preload("res://server/troop_art.gd")
const PartyXP = preload("res://server/party_battle_session.gd")
const Riding = preload("res://scripts/riding.gd")
var key := ""
var ready := false
var rows: Array = []
var allowed: Array = []
var best_expected := 0.0
var threshold := 0.0
var participant: Dictionary = {}
var _tasks: Array = []
var _task: Dictionary = {}
var _states: Dictionary = {}
var _next: Dictionary = {}
var _keys: Array = []
var _cursor := 0
var _attempt := 0
var _success := 0.0
var _totals: Array = []
var _stride := 1
var _maximum := 0
static var _roster_cache: Dictionary = {}

## Same level*30 advancement as GameSession._gain_xp. Target may be below 120.
static func remaining_xp(actor: Dictionary, target_level: int = 120) -> int:
	var level := clampi(int(actor.get("level",1)),1,120)
	var target := clampi(target_level,1,120)
	if level>=target:return 0
	return maxi(0,15*(target*(target-1)-level*(level-1))-int(actor.get("xp",0)))

static func context(profile: Dictionary, settings: Dictionary, clones: bool, best_others: bool = false, party: Dictionary = {}) -> Dictionary:
	var pets: Array=profile.get("pets",[])
	var active:=int(profile.get("active_pet",-1))
	var ride:=int(profile.get("ride_pet",-1))
	var eligible:=active>=0 and active<pets.size() and active!=ride and (int(pets[active].get("hp",0))>0 or (bool(settings.get("protect",true)) and not bool(party.get("party",false))))
	var alive:=active>=0 and active<pets.size() and active!=ride and int(pets[active].get("hp",0))>0
	var pet_count:=1 if alive else 0
	if clones:
		if best_others:
			var other_count:=0
			for pet in pets+profile.get("pet_storage",[]):
				if (active<0 or str(pet.get("pet_id",""))!=str(pets[active].get("pet_id",""))) and (ride<0 or str(pet.get("pet_id",""))!=str(pets[ride].get("pet_id",""))) and int(pet.get("hp",0))>0:other_count+=1
			pet_count+=mini(4,other_count)
		else:pet_count+=4 if alive else 0
	var kind:="pet" if eligible else "player"
	var index:=active if eligible else -1
	if not eligible and ride>=0 and ride<pets.size() and int(pets[ride].get("hp",0))>0 and (pet_count==0 or (bool(party.get("party",false)) and bool(party.get("share_exp",true)))):
		kind="mount";index=ride
	var actor: Dictionary=pets[index] if index>=0 else profile.get("player",{})
	var multiplier:=int(settings.get("xp",1))
	if not multiplier in [1,2,10,100]:multiplier=1
	var result: Dictionary={"kind":kind,"index":index,"level":int(actor.get("level",1)),
		"remaining_xp":remaining_xp(actor,int(settings.get("target_level",120))),"players":5 if clones else 1,"active_pets":pet_count,
		"multiplier":multiplier,"ride_level":int(pets[ride].level) if ride>=0 and ride<pets.size() else -1}
	result.merge(party,true)
	return result

func prepare(catalog, map_id: int, cell: Vector2i, profile: Dictionary, settings: Dictionary, clones: bool, best_others: bool = false, party: Dictionary = {}) -> void:
	var area: Dictionary=catalog.area_at(map_id,cell)
	var current:=context(profile,settings,clones,best_others,party)
	# HP and XP progress do not change group rewards; level/mode does, and
	# every group's source/art shape below is also part of the cache key.
	var signature:=JSON.stringify([catalog.get_instance_id(),map_id,cell.x,cell.y,area,profile.get("original_items",[]),current.kind,current.level,current.multiplier,current.ride_level,current.players,current.active_pets,current.get("party",false),current.get("share_exp",true)])
	if signature==key:
		participant=current
		return
	key=signature;ready=false;rows=[];allowed=[];best_expected=0.0;threshold=0.0;participant=current
	_tasks=[];_task={};_states={};_next={};_keys=[];_cursor=0
	if bool(current.get("party",false)) and not bool(current.get("share_exp",true)):
		participant.unavailable="队伍未共享经验时按击杀归属分经验，暂不能预计宠物经验；请打开队伍共享经验或关闭练级挑敌群。"
		_finish();return
	if area.is_empty() or int(area.get("probability_max",0))<=0 or bool(area.get("invalid_weights",false)) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:
		_finish();return
	var held: Array=profile.get("original_items",[])
	var seen:=[]
	for choice in area.get("groups",[]):
		var id:=int(choice.id)
		if int(choice.get("weight",0))<=0 or id in seen:continue
		seen.append(id)
		var group: Dictionary=catalog.data.get("groups",{}).get(str(id),{})
		if group.is_empty() or bool(group.get("invalid_weights",false)):continue
		var requires:=int(group.get("requires_item",-1));var excludes:=int(group.get("excludes_item",-1))
		if (requires>=0 and not requires in held) or (excludes>=0 and excludes in held):continue
		_tasks.append({"catalog":catalog,"area":area,"group":group,"id":id})
	if _tasks.is_empty():_finish()

func _recipient_xp(xp: int, enemy_level: int) -> int:
	if str(participant.kind)=="mount":return Riding.experience(xp,int(participant.level),enemy_level)
	return PartyXP.gap_exp(xp,int(participant.level),enemy_level) if bool(participant.get("party",false)) else xp

func _group(catalog, area: Dictionary, group: Dictionary, id: int) -> Dictionary:
	var types:=[];var ids:=[];var maximum:=0;var total_weight:=0
	for choice in group.get("enemies",[]):
		var enemy: Dictionary=catalog.data.get("enemies",{}).get(str(int(choice.id)),{})
		var template: Dictionary=catalog.data.get("templates",{}).get(str(int(enemy.get("template_id",-1))),{})
		if enemy.is_empty() or template.is_empty():return {}
		var cap:=int(enemy.get("max_count",0))
		var lo:=int(enemy.get("level_min",0));var hi:=int(enemy.get("level_max",0))
		if cap<0 or lo<1 or hi<lo or hi>1000000:return {}
		maximum+=cap
		var weight:=maxi(0,int(choice.get("weight",0)))
		total_weight+=weight
		var at:=ids.find(int(choice.id))
		if at>=0:
			types[at].cap+=cap;types[at].weight+=weight
			continue
		ids.append(int(choice.id))
		var rank:=5;var nominal:=0
		for value in template.get("weights",[]):nominal+=int(value)
		for i in range(6):
			if nominal>=[100,95,90,85,80,0][i]:rank=i;break
		var reward:=0.0;var mount:=0.0
		# Only the table and level-gap portion varies. Beyond it a fixed
		# source reward (or zero outside the table) is constant, even if a
		# legal original enemy range reaches above the player's Lv120 cap.
		var varied:=maxi(int(participant.level)-6,int(participant.ride_level)-6)
		if int(enemy.get("experience",-1))==-1:varied=maxi(varied,catalog.data.get("experience_table",[]).size())
		var end:=mini(hi,maxi(lo-1,varied))
		for level in range(lo,end+1):
			var xp: int=catalog.experience(enemy,template,level,rank)*int(participant.multiplier)
			reward+=_recipient_xp(xp,level)
			if int(participant.ride_level)>=0:mount+=Riding.experience(xp,int(participant.ride_level),level)
		if end<hi:
			var xp: int=catalog.experience(enemy,template,end+1,rank)*int(participant.multiplier)
			reward+=_recipient_xp(xp,end+1)*(hi-end)
			if int(participant.ride_level)>=0:mount+=Riding.experience(xp,int(participant.ride_level),end+1)*(hi-end)

		types.append({"id":int(choice.id),"cap":cap,"weight":weight,"big":int(template.get("size",0))==1,
			"art":Art.can_render([{"sprite":int(template.get("sprite",-1))}]),"xp":reward/(hi-lo+1),"mount_xp":mount/(hi-lo+1)})
	maximum=mini(clampi(int(area.get("max_enemies",1)),1,10),maximum)
	if maximum<=0 or total_weight<=0:return {}
	var shape:=[]
	for t in types:shape.append([t.id,t.cap,t.weight,t.big,t.art])
	return {"id":id,"types":types,"maximum":maximum,"total":total_weight,"roster_key":JSON.stringify([maximum,shape])}

## Bounded continuation: a single state at a time; no synchronous 100-roll
## sampling or unbounded rejection loop while preparing a local ranking.
func advance(budget_usec: int = 1000) -> void:
	var deadline:=Time.get_ticks_usec()+maxi(1,budget_usec)
	while not ready and Time.get_ticks_usec()<deadline:
		if _task.is_empty():
			if _tasks.is_empty():_finish();return
			var pending: Dictionary=_tasks.pop_front()
			_task=_group(pending.catalog,pending.area,pending.group,int(pending.id))
			if _task.is_empty():continue
			if _roster_cache.has(_task.roster_key):
				_add_row(_task,_roster_cache[_task.roster_key]);_task={};continue
			_begin()
		if _keys.is_empty():
			_end_group();continue
		if _cursor>=_keys.size():
			_states=_next;_next={};_keys=_states.keys();_cursor=0;_attempt+=1
			if _attempt>=100:
				for state in _states.values():_terminal(state)
				_end_group()
			continue
		var state: Dictionary=_states[_keys[_cursor]];_cursor+=1
		if int(state.count)>=int(state.target):_terminal(state);continue
		for i in range(_task.types.size()):
			var t: Dictionary=_task.types[i]
			if int(t.weight)<=0:continue
			var probability:=float(state.p)*float(t.weight)/int(_task.total)
			var code:=int(state.code);var target:=int(state.target);var count:=int(state.count);var big:=int(state.big)
			var counts: Array=state.counts
			if int(counts[i])<int(t.cap):
				if bool(t.big) and big>=5:target-=1
				else:
					counts=counts.duplicate();counts[i]+=1;count+=1;big+=1 if bool(t.big) else 0
					code+=int(pow(11,i))
			var ident:=code+target*_stride
			if _next.has(ident):_next[ident].p+=probability
			else:_next[ident]={"p":probability,"code":code,"target":target,"count":count,"big":big,"counts":counts}

func _begin() -> void:
	_stride=int(pow(11,_task.types.size()));_maximum=int(_task.maximum)
	_success=0.0;_totals=[];_totals.resize(_task.types.size());_totals.fill(0.0)
	_states={};_next={};_cursor=0;_attempt=0
	var zero:=[];zero.resize(_task.types.size());zero.fill(0)
	for target in range(1,_maximum+1):_states[target*_stride]={"p":1.0/_maximum,"code":0,"target":target,"count":0,"big":0,"counts":zero}
	_keys=_states.keys()

func _terminal(state: Dictionary) -> void:
	if int(state.count)<=0:return
	for i in range(_task.types.size()):
		if int(state.counts[i])>0 and not bool(_task.types[i].art):return
	_success+=float(state.p)
	for i in range(_totals.size()):_totals[i]+=float(state.p)*int(state.counts[i])

func _end_group() -> void:
	var measured: Dictionary={"probability":_success,"counts":_totals.duplicate()}
	_roster_cache[_task.roster_key]=measured
	_add_row(_task,measured)
	_task={};_states={};_next={};_keys=[]

func _add_row(task: Dictionary, measured: Dictionary) -> void:
	var probability:=float(measured.probability)
	if probability<=0:return
	var expected:=0.0;var count:=0.0;var mount:=0.0;var enemy_counts:={}
	for i in range(task.types.size()):
		var copies:=float(measured.counts[i])/probability
		expected+=copies*float(task.types[i].xp);count+=copies;mount+=copies*float(task.types[i].mount_xp)
		enemy_counts[int(task.types[i].id)]=copies
	rows.append({"group_id":int(task.id),"expected_xp":expected,"expected_enemies":count,"entry_probability":probability,"enemy_counts":enemy_counts,
		"recipient":str(participant.kind),"recipient_level":int(participant.level),"mount_xp_if_player_credit":mount})

static func same_score(a: float, b: float) -> bool:
	return absf(a-b)<=maxf(0.000000001,maxf(absf(a),absf(b))*0.000000000001)

func _finish() -> void:
	rows.sort_custom(func(a,b):return float(a.expected_xp)>float(b.expected_xp) if not same_score(float(a.expected_xp),float(b.expected_xp)) else int(a.group_id)<int(b.group_id))
	ready=true
	if rows.is_empty():return
	best_expected=float(rows[0].expected_xp)
	if best_expected<=0:return
	threshold=float(rows[ceili(rows.size()*0.3)-1].expected_xp)
	for row in rows:
		if float(row.expected_xp)>threshold or same_score(float(row.expected_xp),threshold):allowed.append(int(row.group_id))

func local_best_expected() -> float:return best_expected
func summary() -> Dictionary:
	return {"ready":ready,"groups":rows.duplicate(true),"allowed":allowed.duplicate(),"threshold":threshold,"best_expected":best_expected,"participant":participant.duplicate(true)}
