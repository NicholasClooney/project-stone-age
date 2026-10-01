extends RefCounted
## LAN phase 4a (docs/development/lan-profiles.md "Phase 4a"): the profile
## hub's running party battles. When a party leader's backend opens a battle,
## open() puts every member not already fighting into the same battle
## (server/party_battle_session.gd), each with a pending record in their own
## GameSession. Every participant's backend then holds a SlotView as its
## `battle`: the battle as that player's devices see it, and the way their
## commands reach their own slot.
##
## The turn resolves when every standing player with a device online has
## sent a command, or when the turn timer (45 s) fires: the missing ones
## auto-attack. A player whose devices are all gone is auto-played at once,
## every turn, until the battle ends; it leaves the party only then.
## Each player is settled on their own save when they leave the battle
## (escape) or when it ends.
##
## The clock is the hub's `battle_clock` (tests fake it); nothing here
## sleeps or ticks on its own: the hub calls tick() each frame.
const PartyBattleSession = preload("res://server/party_battle_session.gd")
const TURN_MSEC := PartyBattleSession.TURN_SECONDS*1000

var hub
## battle id -> {id, session, ids: [profile id per slot], own: [each
## profile's pending battle id], deadline (msec), settled: {slot: true}}.
var battles: Dictionary = {}
## Profile id -> its battle entry, while that profile is in a running party
## battle and not yet settled.
var fighting: Dictionary = {}
## Profiles that lost every device during their battle: they leave the party
## once it ends (hub._party_gone).
var gone: Dictionary = {}
var _serial := 0

func _init(owner) -> void:
	hub = owner

func now() -> int:
	return int(hub.battle_clock.call())

func in_battle(id: String) -> bool:
	return fighting.has(id)

## The party led by `leader_id` has a battle running (the leader may have
## escaped from it already).
func party_busy(leader_id: String) -> bool:
	for entry in battles.values():
		if str(entry.ids[0])==leader_id and bool(entry.session.snapshot().active):return true
	return false

## Backend.party_battle_hook: `leader_id`'s backend opens a battle with
## `config` (its pending record). Returns the leader's SlotView, or null
## when this is no party battle (not a leader, or nobody free to join).
func open(config: Dictionary, rng_seed: int, leader_id: String):
	if not hub.party.is_leader(leader_id) or fighting.has(leader_id):return null
	var leader = hub.backends.get(leader_id)
	if leader==null:return null
	var member_ids: Array = []
	for id in hub.party.members(leader_id).slice(1):
		var backend = hub.backends.get(id)
		# A member still looking at the last battle's result (or whose device
		# plays 快速战斗 and has not closed it yet) is taken into this one:
		# the leader's 自动练级 meets the next troop at once (LAN phase 4c).
		if backend!=null and backend.battle_open and backend.party_battle() and not fighting.has(id) and not bool(backend.battle.entry.session._state.active) and backend.session._pending.is_empty():
			backend.close_battle()
		if backend==null or backend.battle_open or not backend.session._pending.is_empty() or fighting.has(id):continue
		member_ids.append(id)
	if member_ids.is_empty():return null
	_serial += 1
	var battle_id := "party-%d-%s" % [_serial,str(config.get("battle_id",""))]
	var ids: Array = [leader_id]
	var own: Array = [str(config.get("battle_id",""))]
	var slots: Array = [_slot_info(leader_id,leader,config)]
	var members: Array = []
	leader.session.start_party_config(battle_id)
	for id in member_ids:
		var backend = hub.backends[id]
		var member: Dictionary = backend.session.start_party_config(battle_id,config.get("enemies",[]),config.has("battle_gold"))
		if member.is_empty():continue
		ids.append(id)
		own.append(str(member.battle_id))
		slots.append(_slot_info(id,backend,member))
		members.append(_member_entry(slots.back(),member))
	var start: Dictionary = config.duplicate(true)
	start.battle_id = battle_id
	start.allies = []
	start.ally_pets = []
	start.can_capture = false
	start.party_members = members
	start.party_slots = slots
	start.share_exp = hub.party.shares_exp(leader_id)
	var session = PartyBattleSession.new()
	session.rng_seed = rng_seed
	session.start_battle(start)
	var entry := {"id":battle_id,"session":session,"ids":ids,"own":own,"deadline":now()+TURN_MSEC,"settled":{}}
	battles[battle_id] = entry
	for id in ids:fighting[id] = entry
	_update_auto(entry)
	print("[%s] 组队战斗开始：%s。" % [hub._name(leader_id),"、".join(ids.map(func(id):return hub._name(id)))])
	for slot in range(1,ids.size()):hub.backends[ids[slot]].open_party_battle(SlotView.new(self,entry,slot))
	entry.opened = true
	return SlotView.new(self,entry,0)

func _slot_info(id: String, backend, config: Dictionary) -> Dictionary:
	return {"id":id,"name":hub._name(id),"character_id":str(backend.session._profile.get("character_id","100000")),"weapon":str(config.get("player_weapon","")),"multiplier":int(config.get("experience_multiplier",1))}

## A member's ally, ally pet and roster for PartyBattleSession, from its own
## pending config (the same fields a solo battle of that profile uses).
func _member_entry(info: Dictionary, config: Dictionary) -> Dictionary:
	var ride := int(config.get("ride_pet_index",-1))
	var active := int(config.get("active_pet",-1))
	if active==ride:active = -1
	var pets: Array = config.get("pets",[])
	var ally := {"name":str(info.name),"character_id":str(info.character_id),"kind":"player","weapon":str(config.get("player_weapon","")),"hp":int(config.player_hp),"max_hp":int(config.player_max_hp),"attack":int(config.player_attack),"defence":int(config.player_defence),"speed":int(config.player_speed),"level":int(config.get("player_level",1)),"vital":float(config.get("player_vital",0)),"luck":int(config.get("player_luck",0)),"elements":config.get("player_elements",[0,0,0,0]).duplicate(),"potions":int(config.get("potions",0)),"active_pet":active,"ride_pet":ride,"mount":config.get("ride_pet",{}).duplicate(true),"mounted_sprite":int(config.get("mounted_sprite",-1))}
	ally.base_stats = {"attack":ally.attack,"defence":ally.defence,"speed":ally.speed}
	# The member's own 恢复护符 (PartyBattleSession.slot_healing).
	ally.healing = bool(config.get("healing_available",false))
	# The member's own 气力 and worn 精灵 (server/spirits.gd).
	ally.mp = int(config.get("player_mp",0))
	ally.spirits = config.get("spirits",{}).duplicate(true)

	var pet: Dictionary = pets[active].duplicate(true) if active>=0 and active<pets.size() else {}
	return {"ally":ally,"pet":pet,"pets":pets.duplicate(true)}

## Every frame (hub._process) and after connection changes: auto-play
## players with no device, resolve turns nobody waits for any more, and turns
## whose timer ran out.
func tick() -> void:
	for entry in battles.values().duplicate():
		if not bool(entry.session.snapshot().active):continue
		_update_auto(entry)
		if entry.session.waiting_slots().is_empty():_resolve(entry,[])
		elif now()>=int(entry.deadline):_resolve(entry,entry.session.waiting_slots())

## Who the turn does not wait for: players with no device (the clone AI's
## attack), and members with 组队自动战斗 on (their own preset, LAN phase 4c:
## hub.party_auto). The leader's slot is its own: its 自动练级 run commands it.
func _update_auto(entry: Dictionary) -> void:
	var auto := {}
	var policies := {}
	for slot in range(entry.ids.size()):
		var id := str(entry.ids[slot])
		if hub.connections_of(id).is_empty():auto[slot] = true
		var preset: Dictionary = hub.party_auto(id) if slot>0 else {}
		if not preset.is_empty():
			auto[slot] = true
			policies[slot] = preset
	var changed: bool = auto!=entry.session.auto_slots
	entry.session.auto_slots = auto
	entry.session.auto_policies = policies
	# A player switched 自动战斗 (or lost or regained its devices): every
	# screen shows who the turn waits for now.
	if changed and bool(entry.get("opened",false)):_status(entry)

## A player's command for this turn, from their backend. "" or why refused.
func submit(entry: Dictionary, slot: int, action: String, target: int) -> String:
	if not bool(entry.session.snapshot().active):return "战斗已经结束。"
	var reason: String = entry.session.submit_slot(slot,action,target)
	if not reason.is_empty():return reason
	_update_auto(entry)
	if entry.session.waiting_slots().is_empty():_resolve(entry,[])
	else:_status(entry)
	return ""

func set_pet(entry: Dictionary, slot: int, command: String, skill_id: int) -> bool:
	var ok: bool = entry.session.set_slot_pet(slot,command,skill_id)
	return ok

func set_pet_target(entry: Dictionary, slot: int, target: int) -> void:
	entry.session.set_slot_pet_target(slot,target)

## Ends the whole battle without rewards (立即脱战, or a runner giving up).
func end_all(entry: Dictionary, developer: bool) -> void:
	if not bool(entry.session.snapshot().active):return
	if developer:entry.session.developer_escape()
	else:entry.session.abandon()
	_push(entry)

func _resolve(entry: Dictionary, timed_out: Array) -> void:
	entry.session.resolve_turn(timed_out.map(func(slot):return entry.session._slot_name(int(slot))))
	entry.deadline = now()+TURN_MSEC
	_push(entry)

## Every participant still in the battle sees the new turn; the ones now
## out of it (escaped, or the battle is over) are settled on their saves.
func _push(entry: Dictionary) -> void:
	var session = entry.session
	for slot in range(entry.ids.size()):
		if entry.settled.has(slot):continue
		var id := str(entry.ids[slot])
		var backend = hub.backends.get(id)
		if backend==null:continue
		var state := view(entry,slot)
		var slice := {}
		if not bool(state.active):
			slice = session.slice_for(slot,str(entry.own[slot]))
			entry.settled[slot] = true
			fighting.erase(id)
		backend.party_turn(state,slice,session.drop_claims_for(slot) if not slice.is_empty() else [])
		# The party fell: the server has everyone in the village now, so a
		# player with no device is there too and nobody is walked back.
		if not slice.is_empty() and str(slice.outcome)=="defeat" and not bool(slice.get("party_stay",false)):
			# The leader's 自动练级 ends with the party (LAN phase 4c).
			if backend.automation.running:backend.automation.stop("全队倒下，自动练级已停止。")
			var village: Dictionary = preload("res://server/backend.gd").VILLAGE
			backend.handle({"type":"report_position","map_id":int(village.map_id),"cell":[int(village.x),int(village.y)],"map_changed":true,"client":"party"})
	if not bool(session.snapshot().active):
		battles.erase(entry.id)
		print("[%s] 组队战斗结束：%s。" % [hub._name(str(entry.ids[0])),str(session.snapshot().outcome)])
		for id in entry.ids:
			if gone.has(id):
				gone.erase(id)
				hub._party_gone(str(id))
		hub.party_tick()

## A command came in but the turn still waits: everyone's devices see who.
func _status(entry: Dictionary) -> void:
	for slot in range(entry.ids.size()):
		if entry.settled.has(slot):continue
		var backend = hub.backends.get(str(entry.ids[slot]))
		if backend!=null:backend.party_status()

## The battle as slot `slot`'s devices see it, with the party's waiting
## state: party {slot, share_exp, seconds (left on the turn timer), sent
## (this slot's command is in), members [{slot, name, sent, down, out,
## auto}]}.
func view(entry: Dictionary, slot: int) -> Dictionary:
	var session = entry.session
	var state: Dictionary = session.view_for(slot)
	var members: Array = []
	for other in range(entry.ids.size()):
		members.append({"slot":other,"name":session._slot_name(other),"sent":session.has_command(other),"down":session.slot_hp(other)<=0,"out":not session.slot_in(other),"auto":session.auto_slots.has(other)})
	var active := bool(state.active)
	state.party = {"slot":slot,"share_exp":session.share_exp,"seconds":maxi(0,ceili((int(entry.deadline)-now())/1000.0)) if active else 0,"sent":session.has_command(slot),"members":members}
	return state

## A profile lost its last device. In a battle it is auto-played and leaves
## the party when the battle ends; returns whether that is the case.
func lost_devices(id: String) -> bool:
	if not fighting.has(id) and not _leads_running(id):return false
	gone[id] = true
	var entry: Dictionary = fighting.get(id,{})
	if not entry.is_empty():
		_update_auto(entry)
		if bool(entry.session.snapshot().active) and entry.session.waiting_slots().is_empty():_resolve(entry,[])
	return true

func _leads_running(id: String) -> bool:
	return hub.party.is_leader(id) and party_busy(id)

## One participant's window on the battle: what its backend holds as `battle`.
class SlotView extends RefCounted:
	var host
	var entry: Dictionary
	var slot := 0
	var capture_assist := false
	var automated := false
	var rng_seed := 0
	var last_error := ""

	func _init(owner, battle: Dictionary, index: int) -> void:
		host = owner
		entry = battle
		slot = index

	func party_view() -> bool:
		return true

	## The battle runs and this slot has nothing to send this turn: its
	## command is in, or its player is down or out. A 自动练级 run waits
	## then, spending no frame budget (LAN phase 4c).
	func waiting_for_others() -> bool:
		var session = entry.session
		return bool(session._state.active) and (session.has_command(slot) or not session.slot_standing(slot))

	func snapshot() -> Dictionary:
		return host.view(entry,slot)

	## Answers why a command was refused ("" when taken).
	func submit(action: String, target: int = -1) -> String:
		last_error = host.submit(entry,slot,action,target)
		return last_error

	func submit_action(action: String, target: int = -1, _pet_index: int = -2) -> Dictionary:
		submit(action,target)
		return snapshot()

	func set_pet_command(command: String) -> bool:
		return host.set_pet(entry,slot,command,0)

	func set_pet_skill(skill_id: int) -> bool:
		return host.set_pet(entry,slot,"skill",skill_id)

	func set_pet_target(index: int) -> bool:
		host.set_pet_target(entry,slot,index)
		return true

	func set_capture_assist(_enabled: bool) -> void:
		pass

	func developer_escape() -> Dictionary:
		host.end_all(entry,true)
		return snapshot()

	func abandon() -> Dictionary:
		host.end_all(entry,false)
		return snapshot()
