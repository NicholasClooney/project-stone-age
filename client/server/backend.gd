extends Node
## Gameplay authority host. Clients send JSON-safe commands to handle() and
## present the events it emits; nothing here touches scene nodes, textures or
## audio. See docs/technical/backend-interface.md for the message contract.
signal event(message: Dictionary)

const PROTOCOL := 1
const GameSession = preload("res://server/game_session.gd")
const BattleSession = preload("res://server/battle_session.gd")
const SquadBattleSession = preload("res://server/squad_battle_session.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const TroopArt = preload("res://server/troop_art.gd")
const Automation = preload("res://server/automation.gd")
const VILLAGE := {"map_id":1000,"x":80,"y":90}
const DEBUG_SPECIES := ["wooli","wooli_wooli","woolistan"]

# Profile mutations forwarded to GameSession: type -> [method, argument fields].
# Fields are positional; a missing trailing field uses the method default.
const PROFILE_COMMANDS := {
	"buy_item":["buy_item",["item"]],
	"sell_item":["sell_item",["item"]],
	"use_item":["use_item",["item"]],
	"equip_item":["equip_item",["item"]],
	"buy_travel_pass":["buy_travel_pass",[]],
	"heal":["heal",[]],
	"heal_carried_pets":["heal_carried_pets",[]],
	"grant_pet_care_items":["grant_pet_care_items",[]],
	"level_pet_to":["level_pet_to",["pet_id","target"]],
	"store_pet":["store_pet",["index","auto_hunt"]],
	"retrieve_pet":["retrieve_pet",["index"]],
	"retrieve_pet_by_id":["retrieve_pet_by_id",["pet_id"]],
	"select_pet":["select_pet",["index"]],
	"mount_pet":["mount_pet",["index"]],
	"rename_pet":["rename_pet",["index","name"]],
	"set_pet_favorite":["set_pet_favorite",["pet_id","favorite"]],
	"allocate_stat":["allocate_stat",["stat","amount"]],
	"distribute_stats":["distribute_stats",["stats"]],
	"learn_pet_skill":["learn_pet_skill",["index","skill_id"]],
	"set_character":["set_character",["id"]],
	"accept_quest":["accept_quest",[]],
	"claim_quest":["claim_quest",[]],
	"grant_starter_pets":["grant_starter_pets",[]],
	"claim_default_companions":["claim_default_companions",[]],
	"gm_raise_level":["gm_raise_level",["index","target"]],
	"gm_set_base_stat":["gm_set_base_stat",["index","stat","value","additive"]],
	"gm_grant_points":["gm_grant_points",["amount"]],
	"gm_heal":["gm_heal",["index"]],
	"gm_clear_modified":["gm_clear_modified",["index"]],
}

var session = GameSession.new()
var battle = BattleSession.new()
## Augmented copy of the latest battle state (settlement summary included).
var battle_state: Dictionary = {}
## A battle stays open from start until a client or runner closes it.
var battle_open := false
var encounter_catalog = EncounterCatalog.new()
var encounter_rng := RandomNumberGenerator.new()
var encounter_serial := 0
var save_path := ""
var last_saved_payload := ""
var rev := 0
var _storage_json := ""
var automation = Automation.new(self)
## Events raised while a command or tick runs are delivered after it finishes,
## so a client reacting to one never re-enters a half-applied change.
var _depth := 0
var _queue: Array[Dictionary] = []

func _init() -> void:
	encounter_rng.randomize()

func _process(delta: float) -> void:
	_depth += 1
	automation.tick(delta)
	_depth -= 1
	_flush()

## Loads an existing save. Returns false for unreadable files; the caller then
## disables persistence so the original file is never replaced.
func load_profile(path: String) -> bool:
	if not session.load_game(path):return false
	last_saved_payload = JSON.stringify(session.snapshot())
	_publish()
	return true

func handle(command: Dictionary) -> Dictionary:
	_depth += 1
	var reply := _handle(command)
	_depth -= 1
	_flush()
	return reply

## Battle commands that name the turn they answer. Several devices can drive
## one battle; a command for a turn that has already been resolved (another
## device acted first) is dropped instead of landing on the next turn.
const TURN_COMMANDS := ["battle_command","battle_pet_command","battle_pet_skill","battle_escape_dev"]

func _handle(command: Dictionary) -> Dictionary:
	var type := str(command.get("type",""))
	var reply: Dictionary
	if type in TURN_COMMANDS and command.has("turn") and not _current_turn(command):reply = _stale("battle turn already resolved")
	elif PROFILE_COMMANDS.has(type):reply = _profile_command(type,command)
	elif has_method("_cmd_"+type):reply = call("_cmd_"+type,command)
	else:reply = _reject("unknown command "+type)
	reply.seq = command.get("seq",0)
	reply.type = "ack" if reply.get("ok",false) else "rejected"
	return reply

func _current_turn(command: Dictionary) -> bool:
	var live: Dictionary = battle.snapshot()
	return battle_open and bool(live.get("active",false)) and str(live.get("battle_id",""))==str(command.get("battle_id","")) and int(live.get("turn",-1))==int(command.turn)

func full_snapshot() -> Dictionary:
	var profile: Dictionary = session.snapshot()
	# The receiver now holds this storage; later changes are relative to it.
	_storage_json = JSON.stringify(profile.get("pet_storage",[]))
	return {"type":"snapshot","v":PROTOCOL,"rev":rev,"profile":profile,"derived":_derived(),"options":_options(),"battle":_live_battle_state(),"battle_open":battle_open,"automation":automation.status()}

# ---- session ---------------------------------------------------------------

func _cmd_hello(command: Dictionary) -> Dictionary:
	if int(command.get("protocol",PROTOCOL))!=PROTOCOL:return _reject("protocol %d required" % PROTOCOL)
	return {"ok":true,"snapshot":full_snapshot()}

## Heartbeat: lets a client notice a connection that died without closing.
func _cmd_ping(_command: Dictionary) -> Dictionary:
	return {"ok":true}

func _cmd_snapshot(_command: Dictionary) -> Dictionary:
	return {"ok":true,"snapshot":full_snapshot()}

func _cmd_set_options(command: Dictionary) -> Dictionary:
	if command.has("clone_squad"):session.clone_squad_enabled = bool(command.clone_squad)
	if command.has("experience_multiplier"):session.experience_multiplier = int(command.experience_multiplier)
	_publish()
	return {"ok":true}

func _cmd_checkpoint(command: Dictionary) -> Dictionary:
	if battle.snapshot().active:return _stale("battle active")
	if battle_open and str(battle.snapshot().outcome)=="defeat":
		session.set_location(VILLAGE.map_id,VILLAGE.x,VILLAGE.y)
	elif command.has("map_id"):
		session.set_location(int(command.map_id),int(command.x),int(command.y))
	var saved := save()
	_publish()
	if not saved:return _reject("save_failed")
	return {"ok":true}

func _required_arguments(method: String) -> int:
	for info in session.get_script().get_script_method_list():
		if info.name==method:return info.args.size()-info.default_args.size()
	return 0

func _profile_command(type: String, command: Dictionary) -> Dictionary:
	var spec: Array = PROFILE_COMMANDS[type]
	var arguments := []
	for field in spec[1]:
		if not command.has(field):break
		arguments.append(command[field])
	# A remote command missing a required field is refused, not a script error.
	if arguments.size() < _required_arguments(spec[0]):return _reject("missing %s" % spec[1][arguments.size()])
	session.last_error = ""
	var ok: bool = session.callv(spec[0],arguments)
	if not ok:return _reject(session.last_error)
	save()
	_publish()
	return {"ok":true}

## Partial update of the profile's automation settings (see
## scripts/automation_settings.gd): deep-merged and validated; null resets a
## value or section to its default. Every client gets the profile event.
func _cmd_set_automation_settings(command: Dictionary) -> Dictionary:
	if not command.has("settings"):return _reject("missing settings")
	session.last_error = ""
	if not session.set_automation_settings(command.settings):return _reject(session.last_error)
	save()
	automation.profile_settings_changed()
	_publish()
	return {"ok":true}

## Drops the listed hunt-stored pets beyond the per-metric keep counts; replies with how many.
func _cmd_prune_hunt_pets(command: Dictionary) -> Dictionary:
	var pruned: int = session.prune_hunt_pets(int(command.get("template_id",-1)),command.get("keep",{}),command.get("ids",[]))
	if pruned > 0:
		save()
		_publish()
	return {"ok":true,"pruned":pruned}

## Permanently releases pets by stable ID; replies with GameSession's summary.
func _cmd_release_pets(command: Dictionary) -> Dictionary:
	session.last_error = ""
	var result: Dictionary = session.release_pets(command.get("ids",[]))
	if int(result.get("released",0)) > 0:
		save()
		_publish()
	return {"ok":true,"result":result,"error":session.last_error}

# ---- battles ---------------------------------------------------------------

## Test and developer fixture: issue a battle config that open_battle accepts.
func _cmd_start_battle_config(command: Dictionary) -> Dictionary:
	var config: Dictionary = session.start_battle_config(str(command.get("species","wooli")),bool(command.get("boss",false)),int(command.get("enemy_count",1)))
	_publish()
	return {"ok":not config.is_empty(),"config":config}

func _cmd_start_wild_battle_config(command: Dictionary) -> Dictionary:
	var config: Dictionary = session.start_wild_battle_config(command.get("troop",{}))
	_publish()
	return {"ok":not config.is_empty(),"config":config}

## Opens a battle for a config this authority issued; the settlement later
## validates the result against the same pending record.
func _cmd_open_battle(command: Dictionary) -> Dictionary:
	var config: Dictionary = command.get("config",{})
	if config.is_empty() or battle.snapshot().active:return _reject("battle unavailable")
	if str(config.get("battle_id",""))!=str(session._pending.get("battle_id","-")):return _reject("stale battle config")
	return {"ok":true,"state":open_battle(config)}

func _cmd_begin_battle(command: Dictionary) -> Dictionary:
	if battle.snapshot().active:return _stale("battle active")
	var boss := bool(command.get("boss",false))
	var enemy_count := int(command.get("enemy_count",0))
	var config: Dictionary = session.start_battle_config("woolistan" if boss else DEBUG_SPECIES[encounter_serial%3],boss,1 if boss else (enemy_count if enemy_count > 0 else 1 + encounter_serial % 3))
	if config.is_empty():return _reject("battle unavailable")
	return {"ok":true,"state":open_battle(config)}

## One step on a field cell. With encounter, a hit also opens the wild battle.
func _cmd_field_step(command: Dictionary) -> Dictionary:
	var hit: bool = encounter_catalog.step(int(command.map_id),_cell(command),encounter_rng)
	if not hit or not bool(command.get("encounter",false)):return {"ok":true,"hit":hit,"battle":false}
	var opened := wild_encounter(int(command.map_id),_cell(command))
	opened.hit = true
	opened.battle = bool(opened.ok)
	opened.ok = true
	return opened

func _cmd_wild_encounter(command: Dictionary) -> Dictionary:
	var result := wild_encounter(int(command.map_id),_cell(command))
	return result

func wild_encounter(map_id: int, cell: Vector2i) -> Dictionary:
	if battle.snapshot().active:return _stale("battle active")
	var troop: Dictionary = encounter_catalog.roll(map_id,cell,encounter_rng)
	if troop.is_empty():
		var reply := _reject(encounter_catalog.last_error)
		reply.skipped = "data"
		return reply
	if not TroopArt.can_render(troop.enemies):
		var reply := _reject("art")
		reply.skipped = "art"
		return reply
	var config: Dictionary = session.start_wild_battle_config(troop)
	if config.is_empty():return _reject("battle validation failed")
	var state := open_battle(config)
	encounter_catalog.pressure = int(encounter_catalog.area_at(map_id,cell).get("probability_min",0))
	return {"ok":true,"state":state,"troop":troop}

func open_battle(config: Dictionary) -> Dictionary:
	encounter_serial += 1
	battle = SquadBattleSession.new() if not config.get("allies",[]).is_empty() else BattleSession.new()
	battle.rng_seed = 42+encounter_serial
	battle_state = battle.start_battle(config)
	battle_open = true
	battle_state.capture_assist = battle.capture_assist
	_publish()
	_emit({"type":"battle_started","state":battle_state.duplicate(true)})
	return battle_state.duplicate(true)

func _cmd_battle_pet_command(command: Dictionary) -> Dictionary:
	if not battle.set_pet_command(str(command.get("command",""))):return _reject("pet command refused")
	_refresh_battle_state()
	return {"ok":true}

func _cmd_battle_pet_skill(command: Dictionary) -> Dictionary:
	if not battle.set_pet_skill(int(command.get("skill_id",0))):return _reject("pet skill refused")
	_refresh_battle_state()
	return {"ok":true}

func _cmd_battle_capture_assist(command: Dictionary) -> Dictionary:
	set_capture_assist(bool(command.get("enabled",false)))
	return {"ok":true}

func set_capture_assist(enabled: bool) -> void:
	if battle.capture_assist==enabled:return
	battle.set_capture_assist(enabled)
	if not battle_state.is_empty():_refresh_battle_state()

func _cmd_battle_command(command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	return {"ok":true,"state":battle_command(command)}

func battle_command(command: Dictionary) -> Dictionary:
	if command.has("pet_target"):battle.set_pet_target(int(command.pet_target))
	var skill_id := int(command.get("pet_skill",0))
	if skill_id > 0 and battle.snapshot().pet_command == "skill":battle.set_pet_skill(skill_id)
	var state: Dictionary = battle.submit_action(str(command.get("action","")),int(command.get("target",-1)),int(command.get("switch_pet",-2)))
	return _after_turn(state)

func _cmd_battle_escape_dev(_command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	return {"ok":true,"state":_after_turn(battle.developer_escape())}

## Settles a finished battle exactly once and appends the reward summary that
## clients display; the summary compares the profile before and after.
func _after_turn(state: Dictionary) -> Dictionary:
	if not bool(state.active) and bool(battle_state.get("settled",false)) and str(battle_state.get("battle_id",""))==str(state.get("battle_id","")):
		return battle_state.duplicate(true)
	var before: Dictionary = session.snapshot()
	if not bool(state.active) and session.apply_battle_result(state):
		state.settled = true
		if state.outcome in ["win","captured"] and int(state.get("xp",0)) > 0:
			state.events.append("获得经验 %d，石币 %d。" % [int(state.get("xp",0)),int(state.get("gold",0))])
			var after: Dictionary = session.snapshot()
			state.result_summary = [{"name":"你","xp":int(state.get("xp",0)),"level_up":int(after.player.level)>int(before.player.level)}]
			var pet_rewards: Array = state.get("pet_reward_xp",[])
			for pet_index in range(mini(before.pets.size(),pet_rewards.size())):
				if int(pet_rewards[pet_index])<=0: continue
				state.result_summary.append({"name":str(after.pets[pet_index].name),"xp":int(pet_rewards[pet_index]),"level_up":int(after.pets[pet_index].level)>int(before.pets[pet_index].level)})
			if int(after.player.level)>int(before.player.level):
				state.events.append("升级！%d 级，体力恢复。状态窗口可分配 %d 点。" % [int(after.player.level),int(after.player.get("stat_points",0))])
			if int(after.active_pet)>=0 and int(after.active_pet) < before.pets.size():
				var index: int = after.active_pet
				if int(after.pets[index].level)>int(before.pets[index].level):
					state.events.append("%s 成长到 %d 级！" % [after.pets[index].name,after.pets[index].level])
					if int(after.pets[index].level) == 2:
						state.events.append("可以向饲育员学习伙伴技能。")
		elif state.outcome=="captured":
			state.events.append("伙伴已加入宠物栏，可为它取名并选择出战。")
		save()
		_publish()
	state.capture_assist = battle.capture_assist
	battle_state = state
	_emit({"type":"battle_turn","state":state.duplicate(true)})
	return state.duplicate(true)

func _cmd_battle_close(_command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	if battle.snapshot().active:return _reject("battle not finished")
	return {"ok":true,"outcome":close_battle()}

func close_battle() -> String:
	var outcome := str(battle.snapshot().outcome)
	if outcome=="defeat":session.set_location(VILLAGE.map_id,VILLAGE.x,VILLAGE.y)
	battle_open = false
	save()
	_emit({"type":"battle_closed","battle_id":str(battle_state.get("battle_id","")),"outcome":outcome})
	return outcome

func _refresh_battle_state() -> void:
	battle_state = _live_battle_state()
	_emit({"type":"battle_state","state":battle_state.duplicate(true)})

## Current authority state plus the settlement fields only this host adds.
func _live_battle_state() -> Dictionary:
	if battle_state.is_empty():return {}
	var live: Dictionary = battle.snapshot()
	for key in ["settled","result_summary","xp","gold","pet_reward_xp","experience_multiplier"]:
		if battle_state.has(key) and not live.get("active",false):live[key] = battle_state[key]
	if not live.get("active",false) and battle_state.has("events") and str(battle_state.get("outcome",""))==str(live.get("outcome","")):live.events = battle_state.events
	live.capture_assist = battle.capture_assist
	return live.duplicate(true)

# ---- automation ------------------------------------------------------------

func _cmd_auto_start(command: Dictionary) -> Dictionary:
	return automation.start(command)

func _cmd_auto_update(command: Dictionary) -> Dictionary:
	return automation.update(command)

func _cmd_auto_stop(command: Dictionary) -> Dictionary:
	return automation.stop_request(str(command.get("reason","已手动停止")))

func _cmd_auto_step(_command: Dictionary) -> Dictionary:
	automation.step()
	return {"ok":true}

func _cmd_auto(command: Dictionary) -> Dictionary:
	return automation.command(str(command.get("name","")),command)

func _cmd_presented(command: Dictionary) -> Dictionary:
	automation.presented(str(command.get("battle_id","")),int(command.get("turn",-1)))
	return {"ok":true}

## Positions are reported by whichever client walks; every other client
## follows the broadcast (the reporter recognises its own client id).
func _cmd_report_position(command: Dictionary) -> Dictionary:
	var cell := _cell(command)
	var moved: bool = int(command.map_id)!=automation.position_map or cell!=automation.position_cell
	var paused: String = automation.position_changed(int(command.map_id),cell,bool(command.get("map_changed",false)))
	if moved:_emit({"type":"position","map_id":int(command.map_id),"cell":[cell.x,cell.y],"client":str(command.get("client",""))})
	return {"ok":true,"paused":paused}

# ---- persistence and events ------------------------------------------------

func save() -> bool:
	if save_path.is_empty():return true
	var payload := JSON.stringify(session.snapshot())
	if payload==last_saved_payload:return true
	if not session.save_game(save_path):return false
	last_saved_payload = payload
	return true

func publish() -> void:
	_publish()

func _publish() -> void:
	rev += 1
	var profile: Dictionary = session.snapshot()
	var storage: Array = profile.get("pet_storage",[])
	profile.erase("pet_storage")
	var storage_json := JSON.stringify(storage)
	if storage_json!=_storage_json:
		_storage_json = storage_json
		_emit({"type":"pet_storage","rev":rev,"pet_storage":storage})
	_emit({"type":"profile","rev":rev,"profile":profile,"derived":_derived(),"options":_options()})

func emit_event(message: Dictionary) -> void:
	_emit(message)

func _emit(message: Dictionary) -> void:
	message.v = PROTOCOL
	if _depth > 0:
		_queue.append(message)
		return
	event.emit(message)

func _flush() -> void:
	if _depth > 0:return
	while not _queue.is_empty():
		event.emit(_queue.pop_front())

func _derived() -> Dictionary:
	return {"has_travel_pass":session.has_travel_pass(),"can_fight_boss":session.can_fight_boss(),"effective_stats":session.effective_player_stats(),"gm_pending":not session._pending.is_empty(),"pet_capacity":GameSession.PET_CAPACITY,"max_level":GameSession.MAX_LEVEL}

func _options() -> Dictionary:
	return {"clone_squad":session.clone_squad_enabled,"experience_multiplier":session.experience_multiplier}

func _cell(command: Dictionary) -> Vector2i:
	var cell: Array = command.get("cell",[0,0])
	return Vector2i(int(cell[0]),int(cell[1]))

func _reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

## A command overtaken by another device's: rejected, but not an error to show.
func _stale(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"stale":true}
