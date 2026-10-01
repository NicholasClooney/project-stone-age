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
const KeepRule = preload("res://scripts/keep_rule.gd")
const ReleaseLog = preload("res://server/release_log.gd")
const Progression = preload("res://server/progression.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
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
	"use_spirit":["use_spirit",["slot","target"]],
	"gm_grant_spirits":["gm_grant_spirits",[]],
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
	"set_player_elements":["set_player_elements",["elements"]],
	"learn_pet_skill":["learn_pet_skill",["index","skill_id"]],
	"set_character":["set_character",["id"]],
	"set_face":["set_face",["face"]],
	"set_free_spirits":["set_free_spirits",["on"]],
	"accept_quest":["accept_quest",[]],
	"claim_quest":["claim_quest",[]],
	"grant_starter_pets":["grant_starter_pets",[]],
	"claim_default_companions":["claim_default_companions",[]],
	"gm_raise_level":["gm_raise_level",["index","target"]],
	"gm_set_base_stat":["gm_set_base_stat",["index","stat","value","additive"]],
	"gm_grant_points":["gm_grant_points",["amount"]],
	"gm_heal":["gm_heal",["index"]],
	"gm_clear_modified":["gm_clear_modified",["index"]],
	"gm_grant_pet":["gm_grant_pet",["template","full_grade"]],
	"set_music_favorite":["set_music_favorite",["track","favorite"]],
	"create_music_playlist":["create_music_playlist",["name"]],
	"rename_music_playlist":["rename_music_playlist",["name","new_name"]],
	"delete_music_playlist":["delete_music_playlist",["name"]],
	"add_music_to_playlist":["add_music_to_playlist",["name","track"]],
	"remove_music_from_playlist":["remove_music_from_playlist",["name","position","track"]],
	"move_music_in_playlist":["move_music_in_playlist",["name","position","track","step"]],
}

## GM and developer commands (ADMIN_COMMANDS, every gm_*) are refused unless
## this is set. A lone server or the desktop game is always admin; a
## multi-profile server (server/profile_hub.gd) sets it from the accounts file.
var admin := true
## The account this backend plays on a multi-profile server, "" otherwise.
var account_name := ""
const ADMIN_COMMANDS := ["battle_escape_dev","start_battle_config","start_wild_battle_config","open_battle","begin_battle","set_fast_hunt_threads"]

var quest_catalog = preload("res://scripts/quest_catalog.gd").new()
var original_quests = preload("res://server/original_quests.gd").new()
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
## 放生记录 (server/release_log.gd): its own file next to the save,
## <save>.release-log.jsonl, never read when the save loads. Tests set
## release_log_path; without either the log stays in memory.
var release_log = preload("res://server/release_log.gd").new()
var release_log_path := ""
## 抓宠记录: the same kind of log in <save>.capture-log.jsonl (capture_log_path for tests).
var capture_log = preload("res://server/release_log.gd").new()
var capture_log_path := ""
## 停止记录: why the hunt or the find-pet cycle stopped, paused or skipped a
## hit, in <save>.stop-log.jsonl (stop_log_path for tests).
var stop_log = preload("res://server/release_log.gd").new()
var stop_log_path := ""
## Counts appends to the three logs (_record_releases).
var pet_log_revision := 0
## 重启后自动恢复: <save>.resume.json (resume_path for tests), read once at
## startup. The standalone server (keep_resume_current) keeps it current while
## a run goes on, since a killed or TERM-ed Godot never reaches _finalize:
## at once when the run moves on (phase, pet, 后台搜宠 queue, counts), else
## every RESUME_INTERVAL_MSEC, and removes it when the run stops. The save is
## written first each time, so the file never names pets the save lacks.
var resume_path := ""
var keep_resume_current := false
const RESUME_INTERVAL_MSEC := 10000
var resume_clock: Callable = Time.get_ticks_msec
## Writes of the resume file, for tests.
var resume_writes := 0
var _resume_key := ""
var _resume_written_msec := -1
static var _map_names: Dictionary = {}
var last_saved_payload := ""
var rev := 0
var _storage_json := ""
var automation = Automation.new(self)
## Events raised while a command or tick runs are delivered after it finishes,
## so a client reacting to one never re-enters a half-applied change.
var _depth := 0
## How long the last automation tick took, and a running average, for
## 开发者性能面板 (scripts/perf_monitor.gd reads them; nothing else does).
var tick_usec := 0
var tick_avg_usec := 0.0
var _queue: Array[Dictionary] = []

func _init() -> void:
	original_quests.catalog = quest_catalog
	encounter_rng.randomize()
	session.battle_pets_hook = _live_battle_pets

## The open battle's live participants (pet_id -> reason) beyond its start
## roster: the pet fighting now, any pet that has already defeated an enemy
## (its experience is still owed) and, in an automatic capture battle, the
## capture helpers it may switch to. GameSession.battle_pets() adds these.
func _live_battle_pets() -> Dictionary:
	var busy := {}
	if not battle_open or session._pending.is_empty():return busy
	var live: Dictionary = battle.snapshot()
	if str(live.get("battle_id",""))!=str(session._pending.get("battle_id","")):return busy
	var pets: Array = live.get("pets",[])
	var slots := [int(live.get("active_pet",-1))]
	for enemy in live.get("enemies",[]):slots.append(int(enemy.get("defeated_by_pet_index",-1)))
	for slot in slots:
		if slot>=0 and slot<pets.size():busy[str(pets[slot].get("pet_id",""))] = "出战中"
	if battle.capture_assist:busy.merge(automation.capture_helpers(),false)
	return busy

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_depth += 1
	automation.tick(delta)
	_depth -= 1
	_record_releases()
	_flush()
	if keep_resume_current:keep_resume_file()
	tick_usec = Time.get_ticks_usec()-started
	tick_avg_usec = lerpf(tick_avg_usec,float(tick_usec),0.1)

## Loads an existing save. Returns false for unreadable files; the caller then
## disables persistence so the original file is never replaced.
func load_profile(path: String) -> bool:
	original_quests.pending={}
	if not session.load_game(path):return false
	last_saved_payload = JSON.stringify(session.snapshot())
	_publish()
	return true

func handle(command: Dictionary) -> Dictionary:
	_depth += 1
	var reply := _handle(command)
	_depth -= 1
	_record_releases()
	_flush()
	return reply

## Appends the pets released or caught by the last command or tick to
## 放生记录 and 抓宠记录.
## Anything appended raises pet_log_revision and emits pet_log_changed, so an
## open 宠物记录 window fetches its page again.
func _record_releases() -> void:
	_release_log_file()
	var appended: bool = not session.release_events.is_empty() or not session.capture_events.is_empty() or not automation.stop_events.is_empty()
	if not session.release_events.is_empty():release_log.append(session.take_release_events())
	if not session.capture_events.is_empty():capture_log.append(session.take_capture_events().map(_capture_entry))
	if not automation.stop_events.is_empty():stop_log.append(automation.take_stop_events())
	if appended:
		pet_log_revision += 1
		_emit({"type":"pet_log_changed","revision":pet_log_revision})

## The logs' files follow the save: <save>.release-log.jsonl and
## <save>.capture-log.jsonl, or tests' paths.
func _release_log_file() -> void:
	release_log.path = release_log_path if not release_log_path.is_empty() else (save_path.get_basename()+".release-log.jsonl" if not save_path.is_empty() else "")
	capture_log.path = capture_log_path if not capture_log_path.is_empty() else (save_path.get_basename()+".capture-log.jsonl" if not save_path.is_empty() else "")
	stop_log.path = stop_log_path if not stop_log_path.is_empty() else (save_path.get_basename()+".stop-log.jsonl" if not save_path.is_empty() else "")

## The server is quitting: a running hunt or cycle is recorded in 停止记录,
## and with 重启后自动恢复 on what it needs to go on is written to the resume
## file (automation.gd record_shutdown). Call save() after this.
func record_shutdown() -> void:
	var wood := _wood_battle_resume()
	# A saved wood battle resumes in place rather than being abandoned by the
	# automation shutdown path (which would record its id as completed).
	if not wood.is_empty():battle_open = false
	var state: Dictionary = automation.record_shutdown()
	if not wood.is_empty():
		battle_open = true
		state.wood_battle = wood
	_record_releases()
	var path := _resume_file()
	if path.is_empty():return
	if state.is_empty():_remove_resume_file(path)
	else:_write_resume_file(path,state)

## A graceful stop (server_main.gd, on a shutdown request or a normal quit):
## nothing runs any more, the run is written down, the profile saved.
func shut_down() -> void:
	keep_resume_current = false
	set_process(false)
	var wood := _wood_battle_resume()
	record_shutdown()
	if not wood.is_empty():
		# The checkpoint contains the pending battle. Save its pre-settlement
		# profile normally; this process is stopping and will run no more turns.
		session._pending.clear()
		battle_open = false
	if not save():printerr("Could not save %s at shutdown: %s" % [save_path,session.last_error])

## Keeps the resume file in step with the running automation (see resume_path).
## Called after every tick; cheap unless the run moved on or the interval passed.
func keep_resume_file() -> void:
	var path := _resume_file()
	if path.is_empty():return
	var now := int(resume_clock.call())
	var wood := _wood_battle_resume()
	var key: String = automation.resume_key()+str(wood.get("battle_id",""))+str(wood.get("turn",0))
	if key==_resume_key and _resume_written_msec>=0 and now-_resume_written_msec<RESUME_INTERVAL_MSEC:return
	_resume_key = key
	_resume_written_msec = now
	var state: Dictionary = automation.resume_state() if automation.resume_wanted() else {}
	if not wood.is_empty():state.wood_battle = wood
	if state.is_empty():
		_remove_resume_file(path)
		return
	# The profile first: a pet the file names (caught, in training) is in the
	# save. A pet settled after this write is found again on resume
	# (automation.gd _resume_capture / _resume_train reconcile it). With a
	# battle open the save waits; the battle is fought again after a restart.
	if session._pending.is_empty():
		session.set_location(int(state.map_id),int(state.cell[0]),int(state.cell[1]))
		if not save():
			printerr("Could not save %s; the resume file waits for the next save." % save_path)
			_resume_written_msec = -1
			return
	_write_resume_file(path,state)

## Written to a temporary file and renamed over the old one, so a kill leaves
## either the previous or the new file, never half of one.
func _write_resume_file(path: String, state: Dictionary) -> void:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:
		printerr("Could not write %s; the automation will not resume." % path)
		return
	# Native JSON keeps ints, int keys and nested types exactly, so queued
	# troops compare equal when replayed.
	file.store_string(JSON.stringify(JSON.from_native(state)))
	file.flush()
	var error := file.get_error()
	file.close()
	var absolute := ProjectSettings.globalize_path(path)
	if error!=OK or DirAccess.rename_absolute(absolute+".tmp",absolute)!=OK:
		printerr("Could not write %s; the automation will not resume." % path)
		return
	resume_writes += 1

func _remove_resume_file(path: String) -> void:
	if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## After load_profile: a run written down at the last shutdown goes on once
## the character stands where it ran (automation.gd try_resume). The file is
## used once.
func load_resume() -> void:
	var path := _resume_file()
	if path.is_empty() or not FileAccess.file_exists(path):return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var state = JSON.to_native(parsed) if parsed!=null else null
	if state is Dictionary:
		if state.get("wood_battle") is Dictionary:_restore_wood_battle(state.wood_battle)
		if state.has("kind"):automation.load_resume(state)

## 重启后自动恢复's file: <save>.resume.json, or tests' resume_path.
func _resume_file() -> String:
	if not resume_path.is_empty():return resume_path
	return save_path.get_basename()+".resume.json" if not save_path.is_empty() else ""

## Where a capture came from: the find-pet cycle (with its run), the hunt's
## automatic capture battle, or a battle the player fought; GM grants say so.
func _capture_entry(event: Dictionary) -> Dictionary:
	var pet: Dictionary = event.pet
	var source := str(event.get("source",""))
	if source.is_empty():
		if automation.flow_active():source = "找宠流程"
		elif automation.running and str(automation.settings.get("preset",""))=="capture":source = "自动抓宠"
		else:source = "手动捕获"
	var lv120: Dictionary = Progression.project_pet(pet,120) if int(pet.get("level",1))<120 else {}
	return ReleaseLog.capture_entry(pet,lv120,automation.position_map,map_name(automation.position_map),automation.position_cell,source,automation.flow_run_id if source=="找宠流程" else "")

## The map's name from the imported world catalog ("" when unknown).
static func map_name(map_id: int) -> String:
	if _map_names.is_empty() and FileAccess.file_exists("res://assets/legacy/world/manifest.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/world/manifest.json"))
		if parsed is Dictionary:
			for id in parsed.get("maps",{}):_map_names[int(id)] = str(parsed.maps[id].get("name",""))
	return str(_map_names.get(map_id,""))

## Battle commands that name the turn they answer. Several devices can drive
## one battle; a command for a turn that has already been resolved (another
## device acted first) is dropped instead of landing on the next turn.
const TURN_COMMANDS := ["battle_command","battle_pet_command","battle_pet_skill","battle_escape_dev"]

func _handle(command: Dictionary) -> Dictionary:
	var type := str(command.get("type",""))
	var before_position := [automation.position_map,automation.position_cell]
	var reply: Dictionary
	# Movement/activity invalidates the conversation even if another device
	# later walks back or stops before confirming the old window.
	if type in ["warp","auto","auto_start","flow_start","open_battle","begin_battle","start_battle_config","start_wild_battle_config","start_wild_battle"]:original_quests.pending={}
	if not admin and admin_only(type):reply = _reject("只有管理员角色可以使用 GM 和开发者功能。")
	elif type in TURN_COMMANDS and command.has("turn") and not _current_turn(command):reply = _stale("battle turn already resolved")
	elif PROFILE_COMMANDS.has(type):reply = _profile_command(type,command)
	elif has_method("_cmd_"+type):reply = call("_cmd_"+type,command)
	else:reply = _reject("unknown command "+type)
	if before_position!=[automation.position_map,automation.position_cell]:original_quests.pending={}
	reply.seq = command.get("seq",0)
	reply.type = "ack" if reply.get("ok",false) else "rejected"
	return reply

## GM tools, battle fixtures, 立即脱战 and the server's 线程数.
static func admin_only(type: String) -> bool:
	return type.begins_with("gm_") or type in ADMIN_COMMANDS

func _current_turn(command: Dictionary) -> bool:
	var live: Dictionary = battle.snapshot()
	# A party battle's command names its slot too (LAN phase 4a).
	if command.has("slot") and int(command.slot)!=int(live.get("party_slot",0)):return false
	return battle_open and bool(live.get("active",false)) and str(live.get("battle_id",""))==str(command.get("battle_id","")) and int(live.get("turn",-1))==int(command.turn)

## The open battle is a party battle (server/party_battles.gd SlotView).
func party_battle() -> bool:
	return battle.has_method("party_view")

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
	session.last_note = ""
	var ok: bool = session.callv(spec[0],arguments)
	if not ok:return _reject(session.last_error)
	save()
	_publish()
	# What a field 精灵 did (耐久力回复N), for the device that cast it.
	return {"ok":true,"note":session.last_note} if not session.last_note.is_empty() else {"ok":true}

## Partial update of the profile's automation settings (see
## scripts/automation_settings.gd): deep-merged and validated; null resets a
## value or section to its default. Every client gets the profile event.
## 本机极速模式 线程数 for this server (0 = auto, up to the core count). It
## belongs to the computer, not the character: kept in server_settings.gd,
## never the profile. Every client sees it in the automation status.
func _cmd_set_fast_hunt_threads(command: Dictionary) -> Dictionary:
	if not command.has("threads"):return _reject("missing threads")
	var error: String = automation.set_fast_threads(command.threads)
	return _reject(error) if not error.is_empty() else {"ok":true}

func _cmd_set_automation_settings(command: Dictionary) -> Dictionary:
	if not command.has("settings"):return _reject("missing settings")
	session.last_error = ""
	if not session.set_automation_settings(command.settings):return _reject(session.last_error)
	save()
	automation.profile_settings_changed()
	_publish()
	return {"ok":true}

## One page of 放生记录 (see _cmd_pet_log).
func _cmd_release_log(command: Dictionary) -> Dictionary:
	var asked := command.duplicate()
	asked.kind = "released"
	return _cmd_pet_log(asked)

## One page of a pet log, newest first. kind: caught (抓宠记录), released
## (放生记录) or stops (停止记录: automation.gd _record_stop); page (from 0), page_size (1..100, default 20), template_id (-1
## for every species), run ("" for all, "latest" for the current or most
## recent find-pet run, or a run id; caught only). Entries are cross-linked:
## a caught pet later released carries `released` {time, reason, source}, a
## released pet whose capture is logged carries `caught` {time, map_name,
## cell, source, run}. The reply's latest_run names the run "latest" means.
func _cmd_pet_log(command: Dictionary) -> Dictionary:
	_record_releases()
	if str(command.get("kind",""))=="stops":
		var stops: Dictionary = stop_log.page(int(command.get("page",0)),int(command.get("page_size",20)),-1,str(command.get("run","")))
		stops.kind = "stops"
		stops.latest_run = automation.flow_run_id
		return {"ok":true,"log":stops}
	var caught := str(command.get("kind","released"))=="caught"
	var log = capture_log if caught else release_log
	var run := str(command.get("run","")) if caught else ""
	# "latest": the running cycle's run, else the newest run in the log.
	var latest: String = automation.flow_run_id
	if latest.is_empty():
		for item in capture_log.page(0,1).get("runs",[]).slice(0,1):latest = str(item.run)
	if run=="latest":run = latest if not latest.is_empty() else "none"
	var page: Dictionary = log.page(int(command.get("page",0)),int(command.get("page_size",20)),int(command.get("template_id",-1)),run)
	var other: Array = release_log.entries() if caught else capture_log.entries()
	var by_id := {}
	for item in other:by_id[str(item.get("pet_id",""))] = item
	for item in page.entries:
		var match_item: Dictionary = by_id.get(str(item.get("pet_id","")),{})
		if match_item.is_empty():continue
		if caught:item.released = {"time":int(match_item.get("time",0)),"reason":str(match_item.get("reason","")),"source":str(match_item.get("source",""))}
		else:item.caught = {"time":int(match_item.get("time",0)),"map_name":str(match_item.get("map_name","")),"cell":match_item.get("cell",[]),"source":str(match_item.get("source","")),"run":str(match_item.get("run",""))}
	page.latest_run = latest
	page.kind = "caught" if caught else "released"
	return {"ok":true,"log":page}

## Drops the listed hunt-stored pets beyond the per-metric keep counts; replies with how many.
func _cmd_prune_hunt_pets(command: Dictionary) -> Dictionary:
	var pruned: int = session.prune_hunt_pets(int(command.get("template_id",-1)),command.get("keep",{}),command.get("ids",[]))
	if pruned > 0:
		save()
		_publish()
	return {"ok":true,"pruned":pruned}

## Permanently releases pets by stable ID; replies with GameSession's summary.
## `source` 保留规则 with `template_id` (the selection came from 同种比较's
## 按保留规则选中): the backend re-evaluates the rule so 放生记录 shows why each
## went and who beat it; other pets in the selection are logged as 手动放生.
func _cmd_release_pets(command: Dictionary) -> Dictionary:
	session.last_error = ""
	var source := str(command.get("source","手动"))
	var notes := {}
	if source=="保留规则" and int(command.get("template_id",-1))>=0:
		var template := int(command.template_id)
		var profile: Dictionary = session.snapshot()
		var protected: Dictionary = KeepRule.always_kept(profile)
		protected.merge(automation.capture_helpers(),true)
		protected.merge(session.battle_pets(),false)
		var rule: Dictionary = AutomationSettings.stat_filter(session.automation_settings(),template).get("keep_rule",{})
		var pets: Array = KeepRule.species_pets(profile,template)
		notes = session.keep_rule_notes(pets,KeepRule.evaluate(pets,rule,protected))
	var result: Dictionary = session.release_pets(command.get("ids",[]),source if source in ["手动","保留规则"] else "手动",notes)
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
	var troop: Dictionary = command.get("troop",{}).duplicate(true)
	# Even the admin fixture cannot supply pre-rolled profit through a command.
	for enemy in troop.get("enemies",[]):
		if enemy is Dictionary:enemy.erase("generated_drops")
	var config: Dictionary = session.start_wild_battle_config(troop)
	_publish()
	return {"ok":not config.is_empty(),"config":config}

## Opens a battle for a config this authority issued; the settlement later
## validates the result against the same pending record.
func _cmd_open_battle(command: Dictionary) -> Dictionary:
	var config: Dictionary = command.get("config",{})
	if config.is_empty() or battle.snapshot().active:return _reject("battle unavailable")
	if str(config.get("battle_id",""))!=str(session._pending.get("battle_id","-")):return _reject("stale battle config")
	# Freeze source loot metadata from the config issued by this authority.
	config = config.duplicate(true)
	if config.get("enemies",[]).size()!=session._pending.get("enemies",[]).size():return _reject("stale battle troop")
	for i in range(config.get("enemies",[]).size()):
		for key in ["generated_drops","source_enemy_id","source_wait_only"]:
			config.enemies[i].erase(key)
			if session._pending.enemies[i].has(key):config.enemies[i][key] = session._pending.enemies[i][key]
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
	var troop: Dictionary = encounter_catalog.roll(map_id,cell,encounter_rng,session.snapshot().get("original_items",[]))
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
	session.battle_pets_hook = _live_battle_pets
	encounter_serial += 1
	# A multi-profile server's party leader: the whole party fights it (LAN
	# phase 4a, server/party_battles.gd), or the hook declines with null.
	if party_battle_hook.is_valid():
		var view = party_battle_hook.call(config,42+encounter_serial)
		if view!=null:return open_party_battle(view)
	battle = SquadBattleSession.new() if not config.get("allies",[]).is_empty() else BattleSession.new()
	battle.rng_seed = 42+encounter_serial
	battle_state = battle.start_battle(config)
	battle_open = true
	battle_state.capture_assist = battle.capture_assist
	_publish()
	_emit({"type":"battle_started","state":battle_state.duplicate(true)})
	return battle_state.duplicate(true)

## LAN phase 4a: set by the profile hub; (config, rng seed) -> the leader's
## party battle view, or null for an ordinary battle.
var party_battle_hook: Callable
## LAN phase 4c: set by the profile hub; () -> "" or why a party leader's
## 自动练级 stops before meeting the next troop (a member at its 停机线).
var party_guard: Callable

## This profile joins a party battle (its pending record is already set):
## `view` is its window on it (server/party_battles.gd SlotView).
func open_party_battle(view) -> Dictionary:
	session.battle_pets_hook = _live_battle_pets
	battle = view
	battle_state = battle.snapshot()
	battle_open = true
	battle_state.capture_assist = false
	_publish()
	_emit({"type":"battle_started","state":battle_state.duplicate(true)})
	return battle_state.duplicate(true)

## A party battle turn resolved (or this player left it): present it, and
## settle `slice` (PartyBattleSession.slice_for) when this player is out.
func party_turn(state: Dictionary, slice: Dictionary, drop_claims: Array = []) -> void:
	_depth += 1
	_after_turn(state,slice,drop_claims)
	_depth -= 1
	_flush()

## A party member sent a command; the turn still waits for others.
func party_status() -> void:
	_depth += 1
	_refresh_battle_state()
	_depth -= 1
	_flush()

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
	if party_battle():
		# The turn resolves once every player has sent theirs (or on the
		# timer); the host then presents it to every participant.
		if command.has("pet_target"):battle.set_pet_target(int(command.pet_target))
		var reason: String = battle.submit(str(command.get("action","")),int(command.get("target",-1)))
		if not reason.is_empty():return _reject(reason)
		return {"ok":true,"state":battle.snapshot()}
	# A pet stored or released during this battle can no longer be sent in.
	if str(command.get("action",""))=="switch" and int(command.get("switch_pet",-2))>=0:
		var roster: Array = battle.snapshot().get("pets",[])
		var slot := int(command.switch_pet)
		var carried: Array = session.snapshot().pets.map(func(pet):return str(pet.get("pet_id","")))
		var ident: String = str(roster[slot].get("pet_id","")) if slot<roster.size() else ""
		if not ident.is_empty() and not ident in carried:return _reject("这只宠物已存入仓库或放生，不能换上场。")
	return {"ok":true,"state":battle_command(command)}

func battle_command(command: Dictionary) -> Dictionary:
	if party_battle():
		# The leader's 自动练级 in a party battle (LAN phase 4c): its command
		# goes to its own slot; the host presents and settles the turn when
		# it resolves (party_turn), which may be now or after the others.
		if command.has("pet_target"):battle.set_pet_target(int(command.pet_target))
		battle.submit(str(command.get("action","")),int(command.get("target",-1)))
		return battle_state.duplicate(true) if bool(battle_state.get("settled",false)) else battle.snapshot()
	if command.has("pet_target"):battle.set_pet_target(int(command.pet_target))
	var skill_id := int(command.get("pet_skill",0))
	if skill_id > 0 and battle.snapshot().pet_command == "skill":battle.set_pet_skill(skill_id)
	var state: Dictionary = battle.submit_action(str(command.get("action","")),int(command.get("target",-1)),int(command.get("switch_pet",-2)))
	return _after_turn(state)

## Ends the open battle with no rewards and closes it: the find-pet cycle
## giving up a capture battle (BattleSession.abandon, no GM mark).
func abandon_battle() -> void:
	if not battle_open:return
	if bool(battle.snapshot().get("active",false)):_after_turn(battle.abandon())
	close_battle()

func _cmd_battle_escape_dev(_command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	return {"ok":true,"state":_after_turn(battle.developer_escape())}

## Settles a finished battle exactly once and appends the reward summary that
## clients display; the summary compares the profile before and after.
func _after_turn(state: Dictionary, settle: Dictionary = {}, drop_claims: Array = []) -> Dictionary:
	if not bool(state.active) and bool(battle_state.get("settled",false)) and str(battle_state.get("battle_id",""))==str(state.get("battle_id","")):
		return battle_state.duplicate(true)
	if settle.is_empty() and battle_open and not party_battle():session._pending.loot_claims = battle.drop_claims_for()
	var before: Dictionary = session.snapshot()
	# A party battle settles this player's own slice (its own battle id and
	# rewards); the state its devices see stays the shared battle.
	var result: Dictionary = settle if not settle.is_empty() else state
	if not bool(state.active) and session.apply_battle_result(result,drop_claims):
		if not settle.is_empty():
			for key in ["xp","gold","pet_reward_xp","experience_multiplier","drop_summary"]:state[key] = result.get(key,0)
		state.settled = true
		for drop in state.get("drop_summary",[]):
			var item_name := str(quest_catalog.items.get(str(int(drop.item_id)),{}).get("name","原版物品 #%d"%int(drop.item_id)))
			drop.name = item_name
			state.events.append("获得%s。"%item_name if drop.received else "背包已满，%s已销毁。"%item_name)
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
	_publish_battle_pets()
	battle_state = state
	_emit({"type":"battle_turn","state":state.duplicate(true)})
	return state.duplicate(true)

func _cmd_battle_close(command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	# Naming the battle: one already closed and replaced (a party leader's
	# 自动练级 met the next troop, LAN phase 4c) is not an error.
	if command.has("battle_id") and str(command.battle_id)!=str(battle.snapshot().get("battle_id","")):return _stale("battle already closed")
	if battle.snapshot().active:return _reject("battle not finished")
	return {"ok":true,"outcome":close_battle()}

func close_battle() -> String:
	var outcome := str(battle.snapshot().outcome)
	if outcome=="defeat":session.set_location(VILLAGE.map_id,VILLAGE.x,VILLAGE.y)
	battle_open = false
	save()
	_publish_battle_pets()
	_emit({"type":"battle_closed","battle_id":str(battle_state.get("battle_id","")),"outcome":outcome})
	return outcome

func _refresh_battle_state() -> void:
	battle_state = _live_battle_state()
	_publish_battle_pets()
	_emit({"type":"battle_state","state":battle_state.duplicate(true)})

## Clients grey out the battle's participants from the profile's derived
## battle_pets; a turn or a capture-assist change can alter them.
var _published_battle_pets: Dictionary = {}
func _publish_battle_pets() -> void:
	if session.battle_pets()!=_published_battle_pets:_publish()

## Current authority state plus the settlement fields only this host adds.
func _live_battle_state() -> Dictionary:
	if battle_state.is_empty():return {}
	var live: Dictionary = battle.snapshot()
	for key in ["settled","result_summary","xp","gold","pet_reward_xp","experience_multiplier","drop_summary"]:
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

## Authorize the guarded sea portal using this backend's current map and permit.
func _cmd_check_passage(command: Dictionary) -> Dictionary:
	if int(command.get("from_map",-1))!=automation.position_map:return _reject("位置已经改变。")
	if preload("res://scripts/passage_rules.gd").requires_permit(automation.position_map,int(command.get("to_map",-1))) and not session.has_travel_pass():
		return _reject("穿过海底关卡需要通行证。")
	return {"ok":true}

## Positions are reported by whichever client walks; every other client
## follows the broadcast (the reporter recognises its own client id).
func _cmd_report_position(command: Dictionary) -> Dictionary:
	var origin: int = automation.position_map
	if preload("res://scripts/passage_rules.gd").requires_permit(origin,int(command.map_id)) and not session.has_travel_pass():
		return _reject("穿过海底关卡需要通行证。")
	var cell := _cell(command)
	var moved: bool = int(command.map_id)!=automation.position_map or cell!=automation.position_cell
	var paused: String = automation.position_changed(int(command.map_id),cell,bool(command.get("map_changed",false)))
	if moved:_emit({"type":"position","map_id":int(command.map_id),"cell":[cell.x,cell.y],"client":str(command.get("client",""))})
	return {"ok":true,"paused":paused}

## What other players on the map see of this character (LAN phase 2,
## server/presence.gd): appearance, level, mount, and whether it is fighting
## (a battle is open, or compact 自动练级 runs between its battles). Reads
## the profile in place; nothing is copied. `auto` (any automation running)
## is for 组队 (server/party.gd), not sent to other players.
func presence_state() -> Dictionary:
	var profile: Dictionary = session._profile
	var ride := -1
	var ride_name := ""
	var index := int(profile.get("ride_pet",-1))
	var pets: Array = profile.get("pets",[])
	if index>=0 and index<pets.size():
		ride = int(pets[index].get("sprite",-1))
		ride_name = str(pets[index].get("name",""))
	return {"name":account_name,"level":int(profile.get("player",{}).get("level",1)),"look":{"c":str(profile.get("character_id","100000")),"face":int(profile.get("face",0)),"ride":ride,"rn":ride_name},"map":automation.position_map,"cell":automation.position_cell,"battle":battle_open or (automation.running and automation.compact_active),"auto":automation.running or automation.hunt_running or automation.flow_active()}

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
	# battle_pets: pet_id -> reason for the open battle's participants, which
	# release, store, deploy and ride refuse until it ends.
	_published_battle_pets = session.battle_pets()
	return {"has_travel_pass":session.has_travel_pass(),"can_fight_boss":session.can_fight_boss(),"effective_stats":session.effective_player_stats(),"gm_pending":not session._pending.is_empty(),"battle_pets":_published_battle_pets.duplicate(),"pet_capacity":GameSession.PET_CAPACITY,"max_level":GameSession.MAX_LEVEL}

func _options() -> Dictionary:
	var options := {"clone_squad":session.clone_squad_enabled,"experience_multiplier":session.experience_multiplier,"admin":admin}
	if not account_name.is_empty():options.account = account_name
	return options

func _cell(command: Dictionary) -> Vector2i:
	var cell: Array = command.get("cell",[0,0])
	return Vector2i(int(cell[0]),int(cell[1]))

func _reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

## A command overtaken by another device's: rejected, but not an error to show.
func _stale(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"stale":true}

func _cmd_quest_talk(command: Dictionary) -> Dictionary:
	return original_quests.talk(self,str(command.get("npc_id","")))

func _cmd_quest_choose(command: Dictionary) -> Dictionary:
	return original_quests.choose(self,str(command.get("token","")),str(command.get("choice","")))

func _cmd_quest_close(command: Dictionary) -> Dictionary:
	if original_quests.pending.is_empty() or str(command.get("token",""))!=str(original_quests.pending.token):return _reject("对话已过期。")
	original_quests.pending={}
	return {"ok":true,"closed":true}

func _cmd_quest_discard(command: Dictionary) -> Dictionary:
	if battle_open or automation.running or automation.hunt_running or automation.flow_active():return _reject("当前正忙。")
	var before: Dictionary=session.snapshot()
	var item = command.get("item_id")
	if not item is int and not item is float:return _reject("无效物品。")
	if float(item)!=floor(float(item)) or not int(item) in before.original_items:return _reject("没有这个物品。")
	session._profile.original_items.erase(int(item))
	if not save():session._profile=before;return _reject("save_failed")
	_publish()
	return {"ok":true}

## Minimal restart support for the original single-enemy wood encounter.
## The profile and already-created loot travel together; restarting never rolls.
## Party topology and clone battles are not restored by this solo checkpoint.
func _wood_battle_resume() -> Dictionary:
	if not automation.resume_wanted() or not battle_open or party_battle() or session._pending.is_empty():return {}
	var pending: Dictionary = session._pending
	if pending.get("enemies",[]).size()!=1 or int(pending.enemies[0].get("source_enemy_id",-1))!=563 or not pending.get("allies",[]).is_empty():return {}
	var live: Dictionary = battle.snapshot()
	if not bool(live.get("active",false)):return {}
	return {"battle_id":str(pending.battle_id),"turn":int(live.turn),"profile":session.snapshot(),"pending":pending.duplicate(true),"state":live,"rng_state":battle._rng.state,"rng_seed":battle.rng_seed,"escape_attempts":battle._escape_attempts,"skill_used":battle._skill_used,"chosen_skill":battle._chosen_skill,"pet_target":battle._pet_target}

func _restore_wood_battle(saved: Dictionary) -> bool:
	if battle_open or not session._pending.is_empty():return false
	var profile = saved.get("profile")
	var config = saved.get("pending")
	var live = saved.get("state")
	if not profile is Dictionary or not session._valid_profile(profile) or not config is Dictionary or not live is Dictionary:return false
	var current: Dictionary = session.snapshot()
	if str(profile.profile_id)!=str(current.profile_id) or int(profile.next_battle)<int(current.next_battle):return false
	var id := str(saved.get("battle_id",""))
	if id.is_empty() or id in current.completed_battles or id in profile.completed_battles or id!=str(config.get("battle_id","")) or id!=str(live.get("battle_id","")):return false
	if config.get("party",false) or not config.get("allies",[]).is_empty() or config.get("enemies",[]).size()!=1 or live.get("enemies",[]).size()!=1 or not bool(live.get("active",false)):return false
	var enemy: Dictionary = config.enemies[0]
	if int(enemy.get("source_enemy_id",-1))!=563 or not session._actor_valid(enemy) or not GameSession._generated_drops_valid(enemy):return false
	var source: Dictionary = encounter_catalog.data.get("enemies",{}).get("563",{})
	if source.is_empty() or not bool(source.get("wait_only",false)) or not bool(enemy.get("source_wait_only",false)):return false
	var allowed := []
	for drop in source.get("drops",[]):allowed.append(int(drop.item_id))
	for item in enemy.get("generated_drops",[]):
		if int(item) not in allowed:return false
	if not GameSession._original_integer(live.enemies[0].get("hp"),0,int(enemy.max_hp)) or live.enemies[0].get("species")!=enemy.species:return false
	session._profile = profile.duplicate(true)
	session._pending = config.duplicate(true)
	battle = BattleSession.new()
	battle.rng_seed = int(saved.get("rng_seed",42))
	battle.start_battle(config)
	battle._state = live.duplicate(true)
	battle._rng.state = int(saved.get("rng_state",battle._rng.state))
	battle._escape_attempts = int(saved.get("escape_attempts",0))
	battle._skill_used = bool(saved.get("skill_used",false))
	battle._chosen_skill = int(saved.get("chosen_skill",0))
	battle._pet_target = int(saved.get("pet_target",-1))
	battle_state = battle.snapshot()
	battle_open = true
	_publish()
	return true
