extends Node
## Gameplay authority host. Clients send JSON-safe commands to handle() and
## present the events it emits; nothing here touches scene nodes, textures or
## audio. See docs/technical/backend-interface.md for the message contract.
signal event(message: Dictionary)

const PROTOCOL := 1
## Public loot controls remain closed until the complete server entry and
## client integration have passed their acceptance windows. This is also the
## authority source for the display-only capability; clients cannot set it.
const QUEST_LOOT_PUBLIC_ENABLED := false
const GameSession = preload("res://server/game_session.gd")
const FeeAttemptJournal=preload("res://server/fee_attempt_lifecycle.gd")
const FeeStartJournalWriter=preload("res://server/fee_start_journal_writer.gd")
var _fee_start_journal_writer = FeeStartJournalWriter.new()
const BattleSession = preload("res://server/battle_session.gd")
const SquadBattleSession = preload("res://server/squad_battle_session.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const WildLoot = preload("res://server/quest_wild_loot.gd")
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
	"use_item":["use_item",["item","pet_id"]],
	"equip_item":["equip_item",["item"]],
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
## Pure travel refusal hook supplied by a multi-profile host (party lock).
var quest_visit_guard: Callable
var _following_party:=false
var _project_position:=false
var _party_move_evidence:Dictionary={}
var quest_arrival = preload("res://server/quest_legitimate_arrival.gd").new()
const TimePassage=preload("res://server/original_time_passage.gd")
const DreamPassage=preload("res://server/original_dream_passage.gd")
var quest_helper = preload("res://server/quest_helper.gd").new()
const AdultCheckpoint=preload("res://server/adult_battle_checkpoint.gd")
var stationary = preload("res://server/stationary_encounters.gd").new()
var stationary_party_member: Callable
var quest_auto = preload("res://server/quest_auto.gd").new()
var quest_loot = preload("res://server/quest_auto_loot.gd").new()
var transmigration = preload("res://server/transmigration_service.gd").new()
var original_quests = preload("res://server/original_quests.gd").new()
var _npc_state_published_version := 0
var session = GameSession.new()
var battle = BattleSession.new()
## Augmented copy of the latest battle state (settlement summary included).
var battle_state: Dictionary = {}
## A battle stays open from start until a client or runner closes it.
var battle_open := false
var encounter_catalog = EncounterCatalog.new()
var reviewed_hunt_travel = preload("res://server/reviewed_hunt_travel.gd").new()
var encounter_rng := RandomNumberGenerator.new()
var training_pool_rng := RandomNumberGenerator.new()
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
var _pet_log_pending := false
var _pet_log_sent_msec := -1000
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
## Private verified fee-resume sidecar transaction. No command/RPC caller.
var _fee_resume_sidecar_call: RefCounted
var _fee_resume_sidecar_frame: Dictionary = {}
var _fee_resume_sidecar_executing := false
## Successful persistence boundaries for synchronous quest transactions.
var quest_save_serial:=0
## Short-lived server-only capability for a two-copy fee-attempt fence.
var _fee_attempt_writer_call:RefCounted
var _fee_attempt_writer_snapshot:Dictionary={}
var _fee_attempt_writer_executing:=false
## Private closed-journal pair writer candidate; deliberately has no caller.
var _fee_attempt_close_call:RefCounted
var _fee_attempt_close_frame:Dictionary={}
var _fee_attempt_close_executing:=false
## Reentrant-operation fence held from QuestAuto identity invalidation through close/retire.
var _quest_auto_stop_operation_call:RefCounted
var _quest_auto_stop_operation_owner:Variant
# Server-only dynamic scope. Never accepted from commands or serialized.
var _quest_source_call:Dictionary={}
var _resume_key := ""
var _resume_written_msec := -1
static var _map_names: Dictionary = {}
var last_saved_payload := ""
var rev := 0
var _storage_json := ""
var automation = Automation.new(self)
## Events raised while a command or tick runs are delivered after it finishes,
## so a client reacting to one never re-enters a half-applied change.
# Stack-completion evidence; existing event order is unchanged.
var _dispatch_boundary_depth:=0
var _observer_depth:=0
var _flush_depth:=0
var _process_depth:=0
var _dispatch_dirty:=false
var _dispatch_epoch:=0
var _normal_process_generation:=0
var _normal_process_entry_epoch:=0
var _depth := 0
## How long the last automation tick took, and a running average, for
## 开发者性能面板 (scripts/perf_monitor.gd reads them; nothing else does).
var tick_usec := 0
var tick_avg_usec := 0.0
var _queue: Array[Dictionary] = []

func _init() -> void:
	original_quests.catalog = quest_catalog
	encounter_rng.randomize()
	training_pool_rng.randomize()
	session.battle_pets_hook = _live_battle_pets
	session.capture_entry_hook = _capture_entry

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
	if battle.capture_assist or int(live.get("clear_capture_target",-1))>=0:busy.merge(automation.capture_helpers(),false)
	return busy

func _process(delta: float) -> void:
	var normal:bool=_dispatch_boundary_depth==0 and _process_depth==0 and _observer_depth==0 and _flush_depth==0 and _depth==0
	_dispatch_boundary_depth+=1
	_process_depth+=1
	if normal:
		_normal_process_generation+=1
		_normal_process_entry_epoch=_dispatch_epoch
	var started := Time.get_ticks_usec()
	_depth += 1
	automation.tick(delta)
	# Passive P3 sample at the original outer-process boundary. This follows
	# the complete automation tick and precedes quest-auto consumption; nested
	# dispatches do not own a heartbeat generation.
	if normal and _process_depth==1 and _dispatch_boundary_depth==1 and _observer_depth==0 and _flush_depth==0 and _depth==1 and _normal_process_generation>0 and _normal_process_entry_epoch==_dispatch_epoch:
		quest_loot.heartbeat_normal_process(self,_normal_process_generation,_normal_process_entry_epoch)
	quest_auto.tick(self,delta)
	stationary.tick(self,delta)
	original_quests.refresh_npc_state()
	if original_quests.npc_state.version!=_npc_state_published_version:_publish()
	_depth -= 1
	_record_releases()
	_flush()
	if keep_resume_current:keep_resume_file()
	tick_usec = Time.get_ticks_usec()-started
	tick_avg_usec = lerpf(tick_avg_usec,float(tick_usec),0.1)
	_process_depth-=1
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()

## Loads an existing save. Returns false for unreadable files; the caller then
## disables persistence so the original file is never replaced.
func load_profile(path: String) -> bool:
	stationary.stop(self,"载入存档停止了原地遇敌。")
	var stop_result:Dictionary=quest_auto.stop(self,"载入存档停止了自动任务。")
	if not stop_result.get("ok",false):return false
	original_quests.pending={}
	if not session.load_game(path):return false
	quest_arrival.reset()
	transmigration.reset()
	last_saved_payload = JSON.stringify(session.snapshot())
	_publish()
	return true

func handle(command: Dictionary) -> Dictionary:
	var fee_refusal:Dictionary=_permit_entry_refusal(command)
	if not fee_refusal.is_empty():return fee_refusal
	_dispatch_boundary_depth+=1
	var source_scope:Dictionary=_quest_source_call
	var source_internal:bool=quest_auto.internal
	if not source_scope.is_empty():quest_auto.internal=false
	_quest_source_call={}
	_depth += 1
	stationary.diagnostic_command = command
	var reply := _handle(command)
	if str(command.get("type","")).begins_with("stationary_") and not bool(reply.get("ok",false)):
		stationary.audit(self,"reject",str(reply.get("reason","")),command)
	stationary.diagnostic_command = {}
	_depth -= 1
	_record_releases()
	_flush()
	_quest_source_call=source_scope
	if not source_scope.is_empty():quest_auto.internal=source_internal
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()
	return reply

## Appends the pets released or caught by the last command or tick to
## 放生记录 and 抓宠记录.
## Anything appended raises pet_log_revision and emits pet_log_changed, so an
## open 宠物记录 window fetches its page again.
func _record_releases() -> void:
	_release_log_file()
	var appended: bool = not session.release_events.is_empty() or not session.capture_events.is_empty() or not automation.stop_events.is_empty()
	# Persist every uncaught record, merging only its refresh notifications.
	# Captures, actual releases and stops must still be visible immediately.
	var queue_only: bool = session.capture_events.is_empty() and automation.stop_events.is_empty() and session.release_events.all(func(entry):return bool(entry.get("uncaught",false)))
	if not session.release_events.is_empty():release_log.append(session.take_release_events())
	if not session.capture_events.is_empty():capture_log.append(session.take_capture_events().map(_capture_entry))
	if not automation.stop_events.is_empty():stop_log.append(automation.take_stop_events())
	if appended:
		pet_log_revision += 1
		_pet_log_pending = true
	if _pet_log_pending and ((appended and not queue_only) or Time.get_ticks_msec()-_pet_log_sent_msec>=1000):
		_pet_log_pending = false
		_pet_log_sent_msec = Time.get_ticks_msec()
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
	var adult := AdultCheckpoint.snapshot(self)
	var wood := _wood_battle_resume()
	# A saved wood battle resumes in place rather than being abandoned by the
	# automation shutdown path (which would record its id as completed).
	if not wood.is_empty() or not adult.is_empty():battle_open = false
	var state: Dictionary = automation.record_shutdown()
	state = _quest_resume_state(state)
	if not wood.is_empty():
		battle_open = true
		state.wood_battle = wood
	if not adult.is_empty():
		battle_open=true
		state.adult_battle=adult
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
	var adult := AdultCheckpoint.snapshot(self)
	var wood := _wood_battle_resume()
	record_shutdown()
	quest_auto.stop(self,"服务器已停止。",false)
	if not wood.is_empty() or not adult.is_empty():
		# The checkpoint contains the pending battle. Save its pre-settlement
		# profile normally; this process is stopping and will run no more turns.
		session._pending.clear()
		battle_open = false
	if not save():printerr("Could not save %s at shutdown: %s" % [save_path,session.last_error])

## Keeps the resume file in step with the running automation (see resume_path).
## Called after every tick; cheap unless the run moved on or the interval passed.
func keep_resume_file() -> void:
	_dispatch_boundary_depth+=1
	_keep_resume_file()
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()

func _keep_resume_file() -> void:
	var path := _resume_file()
	if path.is_empty():return
	var now := int(resume_clock.call())
	var adult := AdultCheckpoint.snapshot(self)
	var wood := _wood_battle_resume()
	var key: String = automation.resume_key()+str(wood.get("battle_id",""))+str(wood.get("turn",0))+str(quest_auto.resume_state())+str(adult.get("battle_id",""))+str(adult.get("turn",0))
	if key==_resume_key and _resume_written_msec>=0 and now-_resume_written_msec<RESUME_INTERVAL_MSEC:return
	_resume_key = key
	_resume_written_msec = now
	var state: Dictionary = automation.resume_state() if automation.resume_wanted() else {}
	if not wood.is_empty():state.wood_battle = wood
	if not adult.is_empty():state.adult_battle = adult
	state = _quest_resume_state(state)
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

## Quest checkpoints contain intent only; original transactions already save flags/items.
func _quest_resume_state(state: Dictionary) -> Dictionary:
	if automation.resume_wanted() and not quest_auto.resume_state().is_empty():
		var quest_state:Dictionary=quest_auto.resume_state()
		state.quest_auto=quest_state
		var identity:Variant=quest_state.get("identity",null)
		var boundary:Dictionary=session._canonical_fee_attempt_profile(session._profile)
		if boundary.get("ok",false) and boundary.get("present",false) and identity is Dictionary:
			var lifecycle:Dictionary=boundary.record
			if lifecycle.current.run_status=="active" and identity.get("run_id",null)==lifecycle.current.run_id:
				# Server-derived sidecar binding; transport identity is not persisted.
				state.fee_attempt_binding={"owner":lifecycle.owner.duplicate(true),"run_id":lifecycle.current.run_id}
		state.map_id = automation.position_map
		state.cell = [automation.position_cell.x,automation.position_cell.y]
	return state

func _fee_attempt_resume_allowed(profile:Variant,state:Variant)->bool:
	if not profile is Dictionary or not state is Dictionary:return false
	var has_record:bool=profile.has("quest_auto_fee_lifecycle")
	var has_binding:bool=state.has("fee_attempt_binding")
	if not has_record and not has_binding:return true
	if not has_record or not has_binding:return false
	var boundary:Dictionary=session._canonical_fee_attempt_profile(profile)
	if not boundary.get("ok",false) or not boundary.get("present",false):return false
	var record:Dictionary=boundary.record
	var binding:Variant=state.get("fee_attempt_binding",null)
	if not binding is Dictionary or not FeeAttemptJournal.exact_keys(binding,["owner","run_id"]):return false
	if not binding.get("owner") is Dictionary or not FeeAttemptJournal.exact_keys(binding.owner,["profile_id","character_id"]):return false
	if not binding.owner.get("profile_id") is String or not binding.owner.get("character_id") is String:return false
	if not FeeAttemptJournal.opaque(binding.get("run_id")):return false
	var quest_state:Variant=state.get("quest_auto",null)
	if not quest_state is Dictionary:return false
	var identity:Variant=quest_state.get("identity",null)
	if not identity is Dictionary or not FeeAttemptJournal.exact_keys(identity,["run_id","step_id","revision"]):return false
	if not FeeAttemptJournal.opaque(identity.get("run_id")) or not identity.get("step_id") is String or identity.step_id.length()>256:return false
	var revision:Variant=identity.get("revision",null)
	# Match QuestAutoState.restore's bound; reject before its partial restore path.
	if not session._fee_raw_integer(revision,0,2147483646):return false
	var decision:Dictionary=FeeAttemptJournal.sidecar_decision(record,binding)
	if not decision.get("ok",false) or not decision.get("resume",false):return false
	if identity.run_id!=binding.run_id:return false
	# An in-flight fee call has an unknown commit result; never replay its yes.
	return record.current.purchase.state!="attempting"

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

func _fee_resume_io_read(path:String)->Dictionary:
	var base:String=_resume_file()
	if base.is_empty() or path not in [base,base+".tmp"]:return {"ok":false,"exists":false,"error":ERR_INVALID_PARAMETER,"bytes":PackedByteArray()}
	var absolute:String=ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):return {"ok":false,"exists":true,"error":ERR_FILE_CANT_READ,"bytes":PackedByteArray()}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:
		var open_error:int=FileAccess.get_open_error()
		return {"ok":open_error==ERR_FILE_NOT_FOUND,"exists":false,"missing":open_error==ERR_FILE_NOT_FOUND,"error":open_error,"bytes":PackedByteArray()}
	var declared:int=file.get_length()
	if declared<0 or declared>16777216:
		file.close()
		return {"ok":false,"exists":true,"error":ERR_FILE_CANT_READ,"bytes":PackedByteArray()}
	var bytes:PackedByteArray=file.get_buffer(declared)
	var error:int=file.get_error()
	file.close()
	if error!=OK or bytes.size()!=declared:return {"ok":false,"exists":true,"error":error,"length":declared,"bytes":bytes}
	return {"ok":true,"exists":true,"error":OK,"length":declared,"bytes":bytes}

func _fee_resume_io_write_tmp(payload:PackedByteArray)->Dictionary:
	var path:String=_resume_file()+".tmp"
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"ok":false,"stage":"temporary_already_exists","error":ERR_ALREADY_EXISTS}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return {"ok":false,"stage":"open_tmp","error":FileAccess.get_open_error()}
	file.store_buffer(payload)
	file.flush()
	var error:int=file.get_error()
	file.close()
	return {"ok":error==OK,"stage":"flush_tmp" if error!=OK else "tmp_written","error":error}

func _fee_resume_io_rename()->int:
	var absolute:String=ProjectSettings.globalize_path(_resume_file())
	return DirAccess.rename_absolute(absolute+".tmp",absolute)

func _fee_resume_io_remove()->int:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_resume_file()))

func _begin_fee_resume_sidecar_frame(action:String,candidate:Dictionary={})->Dictionary:
	if _quest_auto_stop_operation_call!=null:return _fee_resume_unknown_result("stop_operation_busy")
	if action not in ["write_fence","remove_fence"]:return _fee_resume_unknown_result("invalid_action")
	if _fee_resume_sidecar_call!=null or _fee_resume_sidecar_executing:return _fee_resume_unknown_result("busy")
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return _fee_resume_unknown_result("attempt_writer_claim_busy")
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return _fee_resume_unknown_result("close_claim_busy")
	var path:String=_resume_file()
	if path.is_empty() or save_path.is_empty():return _fee_resume_unknown_result("no_bound_resume_path")
	if JSON.stringify(session._profile)!=last_saved_payload:return _fee_resume_unknown_result("profile_cache_mismatch")
	var boundary:Dictionary=session._canonical_fee_attempt_profile(session._profile)
	if not boundary.get("ok",false) or not boundary.get("present",false):return _fee_resume_unknown_result("invalid_fee_profile")
	var record:Dictionary=boundary.record
	var expected_status:String="active" if action=="write_fence" else "closed"
	if record.current.run_status!=expected_status:return _fee_resume_unknown_result("wrong_run_status")
	var owner:Dictionary={"profile_id":str(session._profile.profile_id),"character_id":str(session._profile.character_id)}
	if record.owner!=owner:return _fee_resume_unknown_result("owner_mismatch")
	var target:Dictionary=_fee_resume_io_read(path)
	var temporary:Dictionary=_fee_resume_io_read(path+".tmp")
	var target_exists_value:Variant=target.get("exists",null)
	var temporary_exists_value:Variant=temporary.get("exists",null)
	if not _fee_resume_bool_field_is(target,"ok",true) or not _fee_resume_bool_field_is(temporary,"ok",true) or not (target_exists_value is bool) or not (temporary_exists_value is bool):return _fee_resume_unknown_result("sidecar_preflight_read")
	var target_exists:bool=target_exists_value
	var temporary_exists:bool=temporary_exists_value
	if temporary_exists:return _fee_resume_unknown_result("temporary_already_exists")
	var old_state:Dictionary={}
	if target_exists:
		var parser:=JSON.new()
		var parse_error:int=parser.parse(target.bytes.get_string_from_utf8())
		if parse_error!=OK:return _fee_resume_unknown_result("existing_sidecar_invalid_json")
		var parsed:Variant=parser.data
		# The legacy writer stores JSON.from_native(state), not a plain JSON
		# Dictionary. Validate a bounded, default-deny subset before to_native:
		# untyped Array, Dictionary envelopes, primitive tokens, and the exact
		# built-in Array[String] envelope emitted by Godot 4.6. Other typed,
		# custom, Object and script envelopes remain refused.
		var node_budget:Array=[0]
		if not _fee_native_sidecar_dictionary_safe(parsed,0,node_budget):return _fee_resume_unknown_result("existing_sidecar_invalid_native_envelope")
		var native:Variant=JSON.to_native(parsed,false)
		if not native is Dictionary:return _fee_resume_unknown_result("existing_sidecar_not_dictionary")
		old_state=native
	var binding:Dictionary={"owner":owner.duplicate(true),"run_id":record.current.run_id}
	var payload:=PackedByteArray()
	if action=="write_fence":
		var expected:Dictionary=old_state.duplicate(true)
		expected.erase("quest_auto")
		expected["fee_attempt_binding"]=binding
		if candidate!=expected:return _fee_resume_unknown_result("candidate_not_exact_fence")
		payload=JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer()
		if payload.size()>16777216:return _fee_resume_unknown_result("candidate_too_large")
	else:
		if candidate.size()!=0:return _fee_resume_unknown_result("delete_candidate_supplied")
		if target.get("exists",false):
			if old_state.has("quest_auto") or old_state.get("fee_attempt_binding",null)!=binding:return _fee_resume_unknown_result("existing_sidecar_not_this_fence")
			# Refuse hunt/battle/other recovery keys; deletion is only for the standalone fee marker.
			if not FeeAttemptJournal.exact_keys(old_state,["fee_attempt_binding"]):return _fee_resume_unknown_result("fence_not_standalone")
	var call:=RefCounted.new()
	_fee_resume_sidecar_call=call
	var frame:Dictionary={
		"call":call,"action":action,"session":session,"profile_ref":session._profile,
		"profile":session._profile.duplicate(true),"owner":owner.duplicate(true),"record":record.duplicate(true),
		"save_path":save_path,"resume_path":path,"cache":last_saved_payload,"serial":quest_save_serial,
		"target_exists":target_exists,"target_bytes":target.get("bytes",PackedByteArray()),
		"temporary_exists":temporary_exists,"temporary_bytes":temporary.get("bytes",PackedByteArray()),
		"candidate":candidate.duplicate(true),"payload":payload
	}
	_fee_resume_sidecar_frame=frame
	var prepared_fact:Dictionary=_fee_resume_sidecar_fact(frame)
	prepared_fact.merge({"ok":true,"call":call,"stage":"prepared","operation_attempted":false,"operation_completed":false},true)
	return prepared_fact

func _fee_native_sidecar_dictionary_safe(value:Variant,depth:int,node_budget:Array)->bool:
	if depth>64 or node_budget.is_empty():return false
	var visited:int=int(node_budget[0])+1
	if visited>100000:return false
	node_budget[0]=visited
	if not value is Dictionary:return false
	var envelope:Dictionary=value
	if envelope.size()!=2 or not envelope.has("type") or not envelope.has("args"):return false
	var type_value:Variant=envelope.get("type",null)
	var args_value:Variant=envelope.get("args",null)
	if not (type_value is String) or type_value!="Dictionary" or not (args_value is Array):return false
	var args:Array=args_value
	if args.size()%2!=0:return false
	var seen_keys:Dictionary={}
	var seen_string_like_keys:Dictionary={}
	for index in range(0,args.size(),2):
		var key_value:Variant=args[index]
		if not key_value is String:return false
		var key:String=key_value
		if not _fee_native_dictionary_key_safe(key) or seen_keys.has(key):return false
		seen_keys[key]=true
		var string_like_name:String=""
		if key.begins_with("s:"):string_like_name=key.substr(2)
		elif key.begins_with("sn:"):string_like_name=key.substr(3)
		if key.begins_with("s:") or key.begins_with("sn:"):
			# Godot Dictionary compares equal-content String and StringName keys
			# as the same key. Reject that alias before JSON.to_native can overwrite it.
			if seen_string_like_keys.has(string_like_name):return false
			seen_string_like_keys[string_like_name]=true
		if not _fee_native_sidecar_value_safe(args[index+1],depth+1,node_budget):return false
	return true

func _fee_native_typed_string_array_safe(value:Variant,depth:int,node_budget:Array)->bool:
	if depth>64 or node_budget.is_empty() or not value is Dictionary:return false
	var visited:int=int(node_budget[0])+1
	if visited>100000:return false
	node_budget[0]=visited
	var envelope:Dictionary=value
	if envelope.size()!=3 or not envelope.has("type") or not envelope.has("elem_type") or not envelope.has("args"):return false
	var type_value:Variant=envelope.get("type",null)
	var element_type:Variant=envelope.get("elem_type",null)
	var args_value:Variant=envelope.get("args",null)
	if not (type_value is String) or type_value!="Array":return false
	if not (element_type is String) or element_type!="String":return false
	if not (args_value is Array):return false
	var args:Array=args_value
	for child:Variant in args:
		var element_visit:int=int(node_budget[0])+1
		if element_visit>100000:return false
		node_budget[0]=element_visit
		if not (child is String):return false
		var token:String=child
		if not token.begins_with("s:"):return false
	return true

func _fee_native_sidecar_value_safe(value:Variant,depth:int,node_budget:Array)->bool:
	if depth>64 or node_budget.is_empty():return false
	var visited:int=int(node_budget[0])+1
	if visited>100000:return false
	node_budget[0]=visited
	var kind:int=typeof(value)
	if kind==TYPE_NIL or kind==TYPE_BOOL:return true
	if kind==TYPE_STRING:
		var token:String=value
		if token.begins_with("i:"):
			var integer_text:String=token.substr(2)
			return integer_text.is_valid_int() and str(integer_text.to_int())==integer_text
		if token.begins_with("f:"):
			var float_text:String=token.substr(2)
			if not float_text.is_valid_float():return false
			var number:float=float_text.to_float()
			return is_finite(number)
		return token.begins_with("s:") or token.begins_with("sn:") or token.begins_with("np:")
	if kind==TYPE_ARRAY:
		var array_value:Array=value
		for child:Variant in array_value:
			if not _fee_native_sidecar_value_safe(child,depth+1,node_budget):return false
		return true
	if kind==TYPE_DICTIONARY:
		var dictionary_value:Dictionary=value
		var type_value:Variant=dictionary_value.get("type",null)
		if dictionary_value.has("elem_type") or (type_value is String and type_value=="Array"):
			return _fee_native_typed_string_array_safe(dictionary_value,depth,node_budget)
		return _fee_native_sidecar_dictionary_safe(dictionary_value,depth,node_budget)
	# JSON parser numbers and all other Variant types are not emitted directly
	# by JSON.from_native for this sidecar subset.
	return false

func _fee_native_dictionary_key_safe(token:String)->bool:
	if token.begins_with("s:") or token.begins_with("sn:"):return true
	if not token.begins_with("i:"):return false
	var integer_text:String=token.substr(2)
	return integer_text.is_valid_int() and str(integer_text.to_int())==integer_text

## Closed-run sidecar retirement candidate. Internal-only; deliberately no caller.
## It shares the ordinary sidecar claim. Until the separate action-isolation
## prerequisite is applied, the old generic commit can misinterpret this action.
func _begin_fee_resume_closed_retire_frame(stop_handle:Dictionary={})->Dictionary:
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current(stop_handle):return _fee_resume_retire_unknown_result("stop_operation_busy")
	if _quest_auto_stop_operation_call==null and not stop_handle.is_empty():return _fee_resume_retire_unknown_result("stop_operation_missing")
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return _fee_resume_retire_unknown_result("busy")
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return _fee_resume_retire_unknown_result("close_claim_busy")
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return _fee_resume_retire_unknown_result("attempt_claim_busy")
	if session==null:return _fee_resume_retire_unknown_result("no_session")
	var path:String=_resume_file()
	if path.is_empty() or save_path.is_empty():return _fee_resume_retire_unknown_result("no_bound_profile_or_resume_path")
	if JSON.stringify(session._profile)!=last_saved_payload:return _fee_resume_retire_unknown_result("profile_cache_mismatch")
	var boundary:Dictionary=session._canonical_fee_attempt_profile(session._profile)
	if not boundary.get("ok",false) or not boundary.get("present",false):return _fee_resume_retire_unknown_result("invalid_fee_profile")
	var record:Dictionary=boundary.record
	if record.current.run_status!="closed":return _fee_resume_retire_unknown_result("profile_run_not_closed")
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	if record.owner!=owner:return _fee_resume_retire_unknown_result("owner_mismatch")
	var profile_bytes:PackedByteArray=JSON.stringify(session._profile).to_utf8_buffer()
	var snapshot:Dictionary={"session":session,"profile_ref":session._profile,"profile":session._profile.duplicate(true),"owner":owner.duplicate(true),"record":record.duplicate(true),"save_path":save_path,"resume_path":path,"profile_bytes":profile_bytes.duplicate(),"cache":last_saved_payload,"serial":quest_save_serial,"stop_call":stop_handle.get("call",null),"stop_owner":stop_handle.get("owner",null)}
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("snapshot_stale_before_reads")
	var profile_facts:Dictionary=_fee_resume_retire_profile_pair_facts(snapshot)
	if not _fee_resume_retire_profile_state_is(profile_facts,"matches"):return _fee_resume_retire_unknown_result("closed_profile_pair_not_verified",false,false,OK,profile_facts.get("profile_pair_state","unknown"))
	var target:Dictionary=_fee_resume_io_read(path)
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("owner_changed_after_target_read")
	var temporary:Dictionary=_fee_resume_io_read(path+".tmp")
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("owner_changed_after_tmp_read")
	# Sidecar readers are overridable. Re-read the closed profile pair after
	# those callbacks so a callback that changed the profile files cannot leave
	# an old pair observation attached to a newly published frame.
	var profile_after_sidecar_reads:Dictionary=_fee_resume_retire_profile_pair_facts(snapshot)
	if not _fee_resume_retire_profile_state_is(profile_after_sidecar_reads,"matches"):return _fee_resume_retire_unknown_result("closed_profile_pair_changed_during_sidecar_reads",false,false,OK,profile_after_sidecar_reads.get("profile_pair_state","unknown"))
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("owner_changed_after_profile_recheck")
	var target_recheck:Dictionary=_fee_resume_io_read(path)
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("owner_changed_after_target_recheck")
	var temporary_recheck:Dictionary=_fee_resume_io_read(path+".tmp")
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("owner_changed_after_tmp_recheck")
	if not _fee_resume_bool_field_is(target,"ok",true) or not _fee_resume_bool_field_is(temporary,"ok",true):return _fee_resume_retire_unknown_result("sidecar_preflight_read")
	var target_exists_value:Variant=target.get("exists",null)
	var temporary_exists_value:Variant=temporary.get("exists",null)
	if not target_exists_value is bool or not temporary_exists_value is bool:return _fee_resume_retire_unknown_result("sidecar_preflight_unknown")
	if not _fee_resume_bool_field_is(target_recheck,"ok",true) or not _fee_resume_bool_field_is(temporary_recheck,"ok",true):return _fee_resume_retire_unknown_result("sidecar_recheck_read")
	var target_recheck_exists:Variant=target_recheck.get("exists",null)
	var temporary_recheck_exists:Variant=temporary_recheck.get("exists",null)
	if not target_recheck_exists is bool or not temporary_recheck_exists is bool:return _fee_resume_retire_unknown_result("sidecar_recheck_unknown")
	if target_recheck_exists!=target_exists_value or temporary_recheck_exists!=temporary_exists_value:return _fee_resume_retire_unknown_result("sidecar_changed_during_profile_recheck")
	var target_exists:bool=target_exists_value
	var temporary_exists:bool=temporary_exists_value
	var target_recheck_exists_bool:bool=target_recheck_exists
	var temporary_recheck_exists_bool:bool=temporary_recheck_exists
	if not _fee_resume_retire_bytes_match(target,target_exists) or not _fee_resume_retire_bytes_match(target_recheck,target_recheck_exists_bool):return _fee_resume_retire_unknown_result("sidecar_target_bytes_invalid")
	if not _fee_resume_retire_bytes_match(temporary,temporary_exists) or not _fee_resume_retire_bytes_match(temporary_recheck,temporary_recheck_exists_bool):return _fee_resume_retire_unknown_result("sidecar_tmp_bytes_invalid")
	if target_exists and target.bytes!=target_recheck.bytes:return _fee_resume_retire_unknown_result("sidecar_target_changed_during_profile_recheck")
	if temporary_exists and temporary.bytes!=temporary_recheck.bytes:return _fee_resume_retire_unknown_result("sidecar_tmp_changed_during_profile_recheck")
	if temporary_exists:return _fee_resume_retire_unknown_result("temporary_already_exists")
	var old_state:Dictionary={}
	if target_exists:
		var parser:=JSON.new()
		if parser.parse(target.bytes.get_string_from_utf8())!=OK:return _fee_resume_retire_unknown_result("sidecar_invalid_json")
		var parsed:Variant=parser.data
		var budget:Array=[0]
		if not _fee_native_sidecar_dictionary_safe(parsed,0,budget):return _fee_resume_retire_unknown_result("sidecar_invalid_native_envelope")
		var decoded:Variant=JSON.to_native(parsed,false)
		if not decoded is Dictionary:return _fee_resume_retire_unknown_result("sidecar_not_dictionary")
		old_state=decoded
		var has_quest:bool=old_state.has("quest_auto")
		var has_binding:bool=old_state.has("fee_attempt_binding")
		if not has_quest and not has_binding:return _fee_resume_retire_unknown_result("present_sidecar_unattributed")
		if has_quest:
			var quest_value:Variant=old_state.get("quest_auto",null)
			if not quest_value is Dictionary:return _fee_resume_retire_unknown_result("quest_marker_invalid")
			var identity_value:Variant=quest_value.get("identity",null)
			if not identity_value is Dictionary:return _fee_resume_retire_unknown_result("quest_identity_invalid")
			var quest_run:Variant=identity_value.get("run_id",null)
			if not quest_run is String or not FeeAttemptJournal.opaque(quest_run):return _fee_resume_retire_unknown_result("quest_run_invalid")
			if quest_run!=record.current.run_id:return _fee_resume_retire_unknown_result("quest_marker_foreign")
		if has_binding:
			var binding_value:Variant=old_state.get("fee_attempt_binding",null)
			if not binding_value is Dictionary or not FeeAttemptJournal.exact_keys(binding_value,["owner","run_id"]):return _fee_resume_retire_unknown_result("binding_invalid")
			var binding_owner:Variant=binding_value.get("owner",null)
			var binding_run:Variant=binding_value.get("run_id",null)
			if not binding_owner is Dictionary or not FeeAttemptJournal.exact_keys(binding_owner,["profile_id","character_id"]):return _fee_resume_retire_unknown_result("binding_owner_invalid")
			if not binding_run is String or not FeeAttemptJournal.opaque(binding_run):return _fee_resume_retire_unknown_result("binding_run_invalid")
			if binding_owner!=owner:return _fee_resume_retire_unknown_result("binding_foreign_owner")
			if binding_run!=record.current.run_id:return _fee_resume_retire_unknown_result("binding_foreign_run")
	var expected_state:Dictionary=old_state.duplicate(true)
	expected_state.erase("quest_auto")
	expected_state.erase("fee_attempt_binding")
	var payload:=PackedByteArray()
	var remove_target:bool=expected_state.is_empty()
	if not remove_target:
		payload=JSON.stringify(JSON.from_native(expected_state)).to_utf8_buffer()
		if payload.size()>16777216:return _fee_resume_retire_unknown_result("candidate_too_large")
	if not _fee_resume_retire_snapshot_current(snapshot):return _fee_resume_retire_unknown_result("snapshot_stale_before_claim")
	if not target.has("bytes") or not target.get("bytes",null) is PackedByteArray:return _fee_resume_retire_unknown_result("target_bytes_missing_or_invalid")
	if not temporary.has("bytes") or not temporary.get("bytes",null) is PackedByteArray:return _fee_resume_retire_unknown_result("tmp_bytes_missing_or_invalid")
	var target_bytes_value:Variant=target.get("bytes",null)
	var temporary_bytes_value:Variant=temporary.get("bytes",null)
	var target_bytes:PackedByteArray=target_bytes_value
	var temporary_bytes:PackedByteArray=temporary_bytes_value
	var call:=RefCounted.new()
	var frame:Dictionary=snapshot.duplicate(true)
	# Deep-copy frozen values, then restore identity-bearing references. Dictionary
	# duplicate(true) recursively copies nested Dictionaries, so profile_ref must
	# remain the exact live Session profile object used by the owner fence.
	frame["session"]=snapshot.get("session")
	frame["profile_ref"]=snapshot.get("profile_ref")
	frame.merge({"call":call,"action":"retire_closed","stop_call":snapshot.get("stop_call",null),"stop_owner":snapshot.get("stop_owner",null),"target_exists":target_exists,"target_bytes":target_bytes.duplicate(),"temporary_exists":temporary_exists,"temporary_bytes":temporary_bytes.duplicate(),"candidate":expected_state.duplicate(true),"payload":payload,"remove_target":remove_target},true)
	_fee_resume_sidecar_call=call
	_fee_resume_sidecar_frame=frame
	return {"ok":true,"stage":"prepared","call":call,"operation_attempted":false,"operation_completed":false,"profile_pair_state":"matches"}

func _fee_resume_retire_snapshot_current(snapshot:Dictionary,allow_own_sidecar_claim:bool=false)->bool:
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current({"call":snapshot.get("stop_call"),"owner":snapshot.get("stop_owner")}):return false
	if _quest_auto_stop_operation_call==null and snapshot.get("stop_call",null)!=null:return false
	if snapshot.is_empty() or not is_same(session,snapshot.get("session")):return false
	if allow_own_sidecar_claim:
		if not is_same(_fee_resume_sidecar_call,snapshot.get("call")) or _fee_resume_sidecar_frame.is_empty():return false
	else:
		if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return false
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return false
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return false
	if not is_same(session._profile,snapshot.get("profile_ref")) or session._profile!=snapshot.get("profile",{}):return false
	if save_path!=snapshot.get("save_path") or _resume_file()!=snapshot.get("resume_path"):return false
	if last_saved_payload!=snapshot.get("cache") or quest_save_serial!=snapshot.get("serial"):return false
	var boundary:Dictionary=session._canonical_fee_attempt_profile(session._profile)
	return boundary.get("ok",false) and boundary.get("present",false) and boundary.get("record",{})==snapshot.get("record",{}) and boundary.record.owner==snapshot.get("owner",{}) and boundary.record.current.run_status=="closed"

func _fee_resume_retire_profile_pair_facts(snapshot:Dictionary,allow_own_sidecar_claim:bool=false)->Dictionary:
	if not _fee_resume_retire_snapshot_current(snapshot,allow_own_sidecar_claim):return {"profile_pair_state":"unknown"}
	var owner_session:Variant=snapshot.get("session",null)
	var profile_path:String=str(snapshot.get("save_path",""))
	var profile_bytes:PackedByteArray=snapshot.get("profile_bytes",PackedByteArray())
	var primary:Dictionary=owner_session._read_fee_attempt_file(profile_path,profile_bytes)
	if not _fee_resume_retire_snapshot_current(snapshot,allow_own_sidecar_claim):return {"profile_pair_state":"unknown","primary":primary}
	var backup:Dictionary=owner_session._read_fee_attempt_file(profile_path+".bak",profile_bytes)
	if not _fee_resume_retire_snapshot_current(snapshot,allow_own_sidecar_claim):return {"profile_pair_state":"unknown","primary":primary,"backup":backup}
	var temporary:Dictionary=owner_session._read_fee_attempt_file(profile_path+".tmp",PackedByteArray())
	if not _fee_resume_retire_snapshot_current(snapshot,allow_own_sidecar_claim):return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	for row:Dictionary in [primary,backup]:
		for key:String in ["ok","exists","matches"]:
			if not row.has(key) or not row.get(key) is bool:return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	if not temporary.has("ok") or not temporary.get("ok") is bool or not temporary.has("exists") or not temporary.get("exists") is bool:
		return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	if not _fee_resume_bool_field_is(primary,"ok",true) or not _fee_resume_bool_field_is(backup,"ok",true) or not _fee_resume_bool_field_is(temporary,"ok",true):
		return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	for row:Dictionary in [primary,backup,temporary]:
		if not row.has("bytes") or not row.get("bytes",null) is PackedByteArray:
			return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	var expected_profile_value:Variant=snapshot.get("profile_bytes",null)
	if not expected_profile_value is PackedByteArray:return {"profile_pair_state":"unknown","primary":primary,"backup":backup,"temporary":temporary}
	var expected_profile_bytes:PackedByteArray=expected_profile_value
	var primary_bytes_value:Variant=primary.get("bytes",null)
	var backup_bytes_value:Variant=backup.get("bytes",null)
	var temporary_bytes_value:Variant=temporary.get("bytes",null)
	var primary_bytes:PackedByteArray=primary_bytes_value
	var backup_bytes:PackedByteArray=backup_bytes_value
	var temporary_bytes:PackedByteArray=temporary_bytes_value
	var primary_matches:bool=_fee_resume_bool_field_is(primary,"exists",true) and _fee_resume_bool_field_is(primary,"matches",true) and primary_bytes==expected_profile_bytes
	var backup_matches:bool=_fee_resume_bool_field_is(backup,"exists",true) and _fee_resume_bool_field_is(backup,"matches",true) and backup_bytes==expected_profile_bytes
	var temporary_clear:bool=_fee_resume_bool_field_is(temporary,"exists",false) and temporary_bytes.is_empty()
	var matches:bool=primary_matches and backup_matches and temporary_clear
	return {"profile_pair_state":"matches" if matches else "differs","primary":primary,"backup":backup,"temporary":temporary}

func _fee_resume_retire_unknown_result(stage:String,attempted:bool=false,completed:bool=false,error:int=OK,profile_pair_state:Variant="unknown")->Dictionary:
	var result:Dictionary=_fee_resume_unknown_result(stage,attempted,completed,error)
	var pair_state:String="unknown"
	if profile_pair_state is String and (profile_pair_state=="matches" or profile_pair_state=="differs"):pair_state=profile_pair_state
	result["profile_pair_state"]=pair_state
	result["temporary_clear"]="unknown"
	return result

func _fee_resume_retire_profile_state_is(row:Dictionary,expected:String)->bool:
	var state:Variant=row.get("profile_pair_state",null)
	return state is String and state==expected

func _fee_resume_retire_tmp_clear_fact(row:Dictionary)->Variant:
	var ok_value:Variant=row.get("ok",null)
	var exists_value:Variant=row.get("exists",null)
	if not ok_value is bool or not exists_value is bool or not ok_value:return "unknown"
	var exists:bool=exists_value
	if not _fee_resume_retire_bytes_match(row,exists):return "unknown"
	return not exists

func _fee_resume_retire_bytes_match(row:Dictionary,expected_exists:bool)->bool:
	# Successful observations always include a typed byte field, even for absence.
	if not row.has("bytes"):return false
	var bytes_value:Variant=row.get("bytes",null)
	if not bytes_value is PackedByteArray:return false
	var bytes:PackedByteArray=bytes_value
	if not expected_exists:return bytes.is_empty()
	return true

func _fee_resume_retire_fact_from_read(frame:Dictionary,target:Dictionary)->Dictionary:
	var read_ok:Variant=target.get("ok",null)
	var exists:Variant=target.get("exists",null)
	if not read_ok is bool or not exists is bool or not read_ok:return {"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":"unknown"}
	if not _fee_resume_retire_bytes_match(target,exists):return {"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":"unknown"}
	var matches:bool=false
	if frame.get("remove_target",false):matches=not exists
	else:
		var target_bytes:PackedByteArray=target.bytes
		var payload_value:Variant=frame.get("payload",null)
		if not payload_value is PackedByteArray:return {"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":exists}
		var expected_payload:PackedByteArray=payload_value
		matches=exists and target_bytes==expected_payload
	return {"sidecar_persisted":matches,"target_state":"matches" if matches else "differs","sidecar_exists":exists}

func _fee_resume_closed_retire_frame_current(frame:Dictionary)->bool:
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current({"call":frame.get("stop_call"),"owner":frame.get("stop_owner")}):return false
	if _quest_auto_stop_operation_call==null and frame.get("stop_call",null)!=null:return false
	if frame.is_empty() or frame.get("action","")!="retire_closed" or not _fee_resume_sidecar_frame_current(frame):return false
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return false
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return false
	return frame.get("record",{}).current.run_status=="closed" and frame.get("record",{}).owner==frame.get("owner",{})

func _commit_fee_resume_closed_retire_frame(handle:Variant)->Dictionary:
	if not handle is Dictionary or handle.size()!=1 or not handle.has("call") or not is_same(_fee_resume_sidecar_call,handle.get("call")):return _fee_resume_retire_unknown_result("invalid_handle")
	if _fee_resume_sidecar_executing:return _fee_resume_retire_unknown_result("already_executing",false,false)
	var frame:Dictionary=_fee_resume_sidecar_frame
	if frame.is_empty() or not is_same(frame.get("call"),handle.get("call")):return _fee_resume_retire_unknown_result("stale_frame")
	if frame.get("action","")!="retire_closed":return _fee_resume_retire_unknown_result("wrong_commit_action")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_before_io_after_claim",false,false)
	_fee_resume_sidecar_executing=true
	# Every overridable read is followed by a current-frame check before another
	# path is touched. The pair is sampled again after sidecar callbacks, then
	# sidecar facts are sampled again; this is sequential evidence, not an atomic
	# snapshot across profile and resume files.
	var profile_before:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_initial_profile_pair",false,false)
	var target_before:Dictionary=_fee_resume_io_read(frame.resume_path)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_target_preflight",false,false)
	var tmp_before:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_preflight",false,false)
	var profile_after_sidecar:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_profile_recheck",false,false)
	var target_recheck:Dictionary=_fee_resume_io_read(frame.resume_path)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_target_recheck",false,false)
	var tmp_recheck:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_recheck",false,false)
	var profile_state:Variant=profile_after_sidecar.get("profile_pair_state","unknown")
	var sidecar_unchanged:bool=_fee_resume_retire_read_matches_frame(frame,target_before,false) and _fee_resume_retire_read_matches_frame(frame,tmp_before,true) and _fee_resume_retire_read_matches_frame(frame,target_recheck,false) and _fee_resume_retire_read_matches_frame(frame,tmp_recheck,true)
	if not _fee_resume_retire_profile_state_is(profile_before,"matches") or not _fee_resume_retire_profile_state_is(profile_after_sidecar,"matches") or not sidecar_unchanged:
		var blocked:Dictionary=_fee_resume_retire_unknown_result("pre_io_fence_changed",false,false,OK,profile_state)
		_end_fee_resume_sidecar_frame(handle)
		return blocked
	var attempted:bool=false
	var completed:bool=false
	var io_error:int=OK
	var io_stage:String="verified_absence"
	if frame.remove_target:
		if frame.target_exists:
			# Last check group before delete. A later external filesystem mutation
			# is outside this in-process fence and is not claimed to be atomic.
			var profile_before_remove:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_pair",false,false)
			var target_before_remove:Dictionary=_fee_resume_io_read(frame.resume_path)
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_target",false,false)
			var tmp_before_remove:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_tmp",false,false)
			if not _fee_resume_retire_read_matches_frame(frame,tmp_before_remove,true):return _fee_resume_retire_abort(handle,"remove_tmp_preflight_invalid",false,false)
			var profile_final_remove:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_pair_recheck",false,false)
			var target_final_remove:Dictionary=_fee_resume_io_read(frame.resume_path)
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_target_final",false,false)
			var tmp_final_remove:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove_tmp_final",false,false)
			if not _fee_resume_retire_read_matches_frame(frame,tmp_final_remove,true):return _fee_resume_retire_abort(handle,"remove_tmp_final_invalid",false,false)
			var remove_target_ok:bool=_fee_resume_retire_read_matches_frame(frame,target_before_remove,false) and _fee_resume_retire_read_matches_frame(frame,target_final_remove,false)
			var remove_tmp_ok:bool=_fee_resume_retire_read_matches_frame(frame,tmp_before_remove,true) and _fee_resume_retire_read_matches_frame(frame,tmp_final_remove,true)
			if not _fee_resume_retire_profile_state_is(profile_before_remove,"matches") or not _fee_resume_retire_profile_state_is(profile_final_remove,"matches") or not remove_target_ok or not remove_tmp_ok:
				var remove_blocked:Dictionary=_fee_resume_retire_unknown_result("pre_remove_fence_changed",false,false,OK,profile_final_remove.get("profile_pair_state","unknown"))
				_end_fee_resume_sidecar_frame(handle)
				return remove_blocked
			attempted=true
			io_error=_fee_resume_io_remove()
			completed=io_error==OK
			io_stage="remove"
			if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_remove",attempted,completed,io_error)
		else:
			completed=true
	else:
		attempted=true
		var write_result:Dictionary=_fee_resume_io_write_tmp(frame.payload)
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_write",true,false,int(write_result.get("error",OK)))
		var tmp_written:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_write_read",true,false,int(write_result.get("error",OK)))
		var profile_after_tmp:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_profile_pair",true,false,int(write_result.get("error",OK)))
		var tmp_written_bytes:Variant=tmp_written.get("bytes",null)
		var tmp_written_ok:bool=_fee_resume_bool_field_is(write_result,"ok",true) and _fee_resume_bool_field_is(tmp_written,"ok",true) and _fee_resume_bool_field_is(tmp_written,"exists",true) and tmp_written.has("bytes") and tmp_written_bytes is PackedByteArray and tmp_written_bytes==frame.payload
		if not tmp_written_ok or not _fee_resume_retire_profile_state_is(profile_after_tmp,"matches"):
			return _fee_resume_retire_observation_result(handle,frame,"tmp_write_or_profile_recheck_failed",true,false,int(write_result.get("error",OK)))
		var target_pre:Dictionary=_fee_resume_io_read(frame.resume_path)
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename_target_read",true,false)
		var tmp_pre:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename_tmp_read",true,false)
		var profile_before_rename:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename_profile_pair",true,false)
		var target_final_pre:Dictionary=_fee_resume_io_read(frame.resume_path)
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename_target_final",true,false)
		var tmp_final_pre:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename_tmp_final",true,false)
		var target_pre_ok:bool=_fee_resume_retire_read_matches_frame(frame,target_pre,false) and _fee_resume_retire_read_matches_frame(frame,target_final_pre,false)
		var tmp_pre_bytes:Variant=tmp_pre.get("bytes",null)
		var tmp_final_pre_bytes:Variant=tmp_final_pre.get("bytes",null)
		var tmp_pre_ok:bool=_fee_resume_bool_field_is(tmp_pre,"ok",true) and _fee_resume_bool_field_is(tmp_pre,"exists",true) and tmp_pre.has("bytes") and tmp_pre_bytes is PackedByteArray and tmp_pre_bytes==frame.payload and _fee_resume_bool_field_is(tmp_final_pre,"ok",true) and _fee_resume_bool_field_is(tmp_final_pre,"exists",true) and tmp_final_pre.has("bytes") and tmp_final_pre_bytes is PackedByteArray and tmp_final_pre_bytes==frame.payload
		if not target_pre_ok or not tmp_pre_ok or not _fee_resume_retire_profile_state_is(profile_before_rename,"matches"):
			return _fee_resume_retire_observation_result(handle,frame,"pre_rename_fence_changed",true,false,OK)
		io_error=_fee_resume_io_rename()
		completed=io_error==OK
		io_stage="rename"
		if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_rename",true,completed,io_error)
	# Post-operation facts are read only while the frozen owner/path remains
	# current. A stale result never follows the successor to another path.
	var target_after:Dictionary=_fee_resume_io_read(frame.resume_path)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_target_readback",attempted,completed,io_error)
	var tmp_after:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_tmp_readback",attempted,completed,io_error)
	var profile_after:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_post_operation_profile_pair",attempted,completed,io_error)
	var target_final:Dictionary=_fee_resume_io_read(frame.resume_path)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_final_target_readback",attempted,completed,io_error)
	var tmp_final:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_after_final_tmp_readback",attempted,completed,io_error)
	var target_fact:Dictionary=_fee_resume_retire_fact_from_read(frame,target_final)
	var persisted:Variant=target_fact.get("sidecar_persisted","unknown")
	var persisted_true:bool=false
	if persisted is bool:
		var persisted_bool:bool=persisted
		persisted_true=persisted_bool
	var tmp_clear:Variant=_fee_resume_retire_tmp_clear_fact(tmp_final)
	var tmp_clear_true:bool=false
	if tmp_clear is bool:
		var tmp_clear_bool:bool=tmp_clear
		tmp_clear_true=tmp_clear_bool
	var final_profile_state:Variant=profile_after.get("profile_pair_state","unknown")
	var frame_current:bool=_fee_resume_closed_retire_frame_current(frame)
	var ok:bool=completed and persisted_true and tmp_clear_true and _fee_resume_retire_profile_state_is(profile_after,"matches") and frame_current
	var result:Dictionary=target_fact.duplicate(true)
	result.merge({"ok":ok,"stage":io_stage if ok else "post_io_partial_or_unknown","operation_attempted":attempted,"operation_completed":completed,"temporary_clear":tmp_clear,"profile_pair_state":final_profile_state,"operation_error":io_error},true)
	_end_fee_resume_sidecar_frame(handle)
	return result

func _fee_resume_retire_abort(handle:Dictionary,stage:String,attempted:bool,completed:bool,error:int=OK)->Dictionary:
	# The path may now belong to a successor; do not perform another read.
	var result:Dictionary=_fee_resume_retire_unknown_result(stage,attempted,completed,error)
	_end_fee_resume_sidecar_frame(handle)
	return result

func _fee_resume_retire_observation_result(handle:Dictionary,frame:Dictionary,stage:String,attempted:bool,completed:bool,error:int)->Dictionary:
	# Safe only while the frozen owner/path still matches. Facts are read after a
	# pre-mutation error so operation failure is not confused with target state.
	var target:Dictionary=_fee_resume_io_read(frame.resume_path)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_during_error_observation_target",attempted,completed,error)
	var temporary:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_during_error_observation_tmp",attempted,completed,error)
	var pair:Dictionary=_fee_resume_retire_profile_pair_facts(frame,true)
	if not _fee_resume_closed_retire_frame_current(frame):return _fee_resume_retire_abort(handle,"stale_during_error_observation_profile_pair",attempted,completed,error)
	var fact:Dictionary=_fee_resume_retire_fact_from_read(frame,target)
	var temporary_clear:Variant=_fee_resume_retire_tmp_clear_fact(temporary)
	var pair_state:Variant=pair.get("profile_pair_state","unknown")
	var result:Dictionary=fact.duplicate(true)
	result.merge({"ok":false,"stage":stage,"operation_attempted":attempted,"operation_completed":completed,"operation_error":error,"temporary_clear":temporary_clear,"profile_pair_state":pair_state},true)
	_end_fee_resume_sidecar_frame(handle)
	return result

func _fee_resume_retire_read_matches_frame(frame:Dictionary,row:Dictionary,is_tmp:bool)->bool:
	if not _fee_resume_bool_field_is(row,"ok",true):return false
	var expected_exists:bool=frame.temporary_exists if is_tmp else frame.target_exists
	if not _fee_resume_bool_field_is(row,"exists",expected_exists):return false
	if not row.has("bytes"):return false
	var bytes_value:Variant=row.get("bytes",null)
	if not bytes_value is PackedByteArray:return false
	var bytes:PackedByteArray=bytes_value
	var expected_bytes:PackedByteArray=frame.temporary_bytes if is_tmp else frame.target_bytes
	if not expected_exists:return bytes.is_empty() and expected_bytes.is_empty()
	return bytes==expected_bytes

func _fee_resume_sidecar_frame_current(frame:Dictionary)->bool:
	if _quest_auto_stop_operation_call!=null and not (frame.get("action","")=="retire_closed" and is_same(_quest_auto_stop_operation_call,frame.get("stop_call"))):return false
	if frame.is_empty() or frame.get("action","") not in ["write_fence","remove_fence","retire_closed"]:return false
	if not is_same(_fee_resume_sidecar_call,frame.get("call")):return false
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return false
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return false
	if not is_same(session,frame.get("session")) or not is_same(session._profile,frame.get("profile_ref")) or session._profile!=frame.get("profile"):return false
	if save_path!=frame.get("save_path") or _resume_file()!=frame.get("resume_path"):return false
	if last_saved_payload!=frame.get("cache") or quest_save_serial!=frame.get("serial"):return false
	var boundary:Dictionary=session._canonical_fee_attempt_profile(session._profile)
	return boundary.get("ok",false) and boundary.get("present",false) and boundary.get("record",{})==frame.get("record",{}) and boundary.record.owner==frame.get("owner",{})

func _end_fee_resume_sidecar_frame(handle:Dictionary)->void:
	if handle.size()!=1 or not handle.has("call") or not is_same(_fee_resume_sidecar_call,handle.call):return
	_fee_resume_sidecar_call=null
	_fee_resume_sidecar_frame={}
	_fee_resume_sidecar_executing=false

func _fee_resume_unknown_result(stage:String,attempted:bool=false,completed:bool=false,error:int=OK)->Dictionary:
	return {"ok":false,"operation_attempted":attempted,"operation_completed":completed,"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":"unknown","stage":stage,"operation_error":error}

func _fee_resume_bool_field_is(row:Dictionary,key:String,expected:bool)->bool:
	var value:Variant=row.get(key,null)
	if not (value is bool):return false
	var typed:bool=value
	return typed==expected

func _fee_resume_sidecar_fact_from_read(frame:Dictionary,target:Dictionary)->Dictionary:
	var read_ok_value:Variant=target.get("ok",null)
	var exists_value:Variant=target.get("exists",null)
	if not (read_ok_value is bool) or not (exists_value is bool):return {"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":"unknown"}
	var read_ok:bool=read_ok_value
	var exists:bool=exists_value
	if not read_ok:return {"sidecar_persisted":"unknown","target_state":"unknown","sidecar_exists":"unknown"}
	var matches:bool=false
	if frame.get("action","")=="write_fence":
		matches=exists and target.get("bytes",PackedByteArray())==frame.get("payload",PackedByteArray())
	else:
		matches=not exists
	return {"sidecar_persisted":matches,"target_state":"matches" if matches else "differs","sidecar_exists":exists}

func _fee_resume_sidecar_fact(frame:Dictionary)->Dictionary:
	return _fee_resume_sidecar_fact_from_read(frame,_fee_resume_io_read(str(frame.get("resume_path",""))))

func _fee_resume_sidecar_result(frame:Dictionary,success:bool,stage:String,attempted:bool,completed:bool,error:int=OK)->Dictionary:
	var result:Dictionary=_fee_resume_sidecar_fact(frame)
	var tmp:Dictionary=_fee_resume_io_read(str(frame.get("resume_path",""))+".tmp")
	var tmp_clear:bool=_fee_resume_bool_field_is(tmp,"ok",true) and _fee_resume_bool_field_is(tmp,"exists",false)
	result.merge({"ok":success,"operation_attempted":attempted,"operation_completed":completed,"stage":stage,"operation_error":error,"temporary_clear":tmp_clear,"temporary_exists":tmp.get("exists","unknown")},true)
	return result

func _commit_fee_resume_sidecar_frame(handle:Variant)->Dictionary:
	if not handle is Dictionary:return _fee_resume_unknown_result("invalid_handle")
	if _fee_resume_sidecar_call==null or handle.size()!=1 or not handle.has("call") or not is_same(_fee_resume_sidecar_call,handle.get("call")):
		return _fee_resume_unknown_result("invalid_handle")
	if _fee_resume_sidecar_executing:return _fee_resume_unknown_result("already_executing",false,false)
	if _fee_resume_sidecar_frame.is_empty() or not is_same(handle.get("call"),_fee_resume_sidecar_frame.get("call")):
		return _fee_resume_unknown_result("frame_mismatch")
	var frame:Dictionary=_fee_resume_sidecar_frame
	# Ordinary commit must never reinterpret the closed-retire action.
	if frame.get("action","") not in ["write_fence","remove_fence"]:return _fee_resume_unknown_result("wrong_commit_action")
	_fee_resume_sidecar_executing=true
	if not _fee_resume_sidecar_frame_current(frame):
		var cas_result:Dictionary=_fee_resume_sidecar_result(frame,false,"owner_or_cas_before_io",false,false)
		_end_fee_resume_sidecar_frame(handle)
		return cas_result
	var before:Dictionary=_fee_resume_io_read(frame.resume_path)
	var tmp_before:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	if not _fee_resume_bool_field_is(before,"ok",true) or not _fee_resume_bool_field_is(before,"exists",frame.target_exists) or (frame.target_exists and before.get("bytes",PackedByteArray())!=frame.target_bytes) or not _fee_resume_bool_field_is(tmp_before,"ok",true) or not _fee_resume_bool_field_is(tmp_before,"exists",frame.temporary_exists) or (frame.temporary_exists and tmp_before.get("bytes",PackedByteArray())!=frame.temporary_bytes):
		var disk_result:Dictionary=_fee_resume_sidecar_result(frame,false,"disk_changed_before_io",false,false)
		_end_fee_resume_sidecar_frame(handle)
		return disk_result
	# Both preflight reads are overridable seams. Recheck after their callbacks and
	# exact byte comparison so a stale frame cannot write/remove a successor path.
	if not _fee_resume_sidecar_frame_current(frame):
		var stale_preflight_result:Dictionary=_fee_resume_sidecar_result(frame,false,"owner_or_cas_after_preflight_reads_before_io",false,false)
		_end_fee_resume_sidecar_frame(handle)
		return stale_preflight_result
	var operation_attempted:bool=false
	var operation_completed:bool=false
	var operation_error:int=OK
	if frame.action=="write_fence":
		operation_attempted=true
		var write_result:Dictionary=_fee_resume_io_write_tmp(frame.payload)
		var tmp_written:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
		if not _fee_resume_bool_field_is(write_result,"ok",true) or not _fee_resume_bool_field_is(tmp_written,"ok",true) or not _fee_resume_bool_field_is(tmp_written,"exists",true) or tmp_written.get("bytes",PackedByteArray())!=frame.payload:
			operation_error=int(write_result.get("error",OK))
			var tmp_fail_result:Dictionary=_fee_resume_sidecar_result(frame,false,"tmp_write_or_readback_failed",true,false,operation_error)
			tmp_fail_result["io_stage"]=write_result.get("stage","")
			tmp_fail_result["temporary_read_error"]=tmp_written.get("error",OK)
			_end_fee_resume_sidecar_frame(handle)
			return tmp_fail_result
		if not _fee_resume_sidecar_frame_current(frame):
			var stale_tmp_result:Dictionary=_fee_resume_sidecar_result(frame,false,"owner_or_cas_after_tmp_before_rename",true,false)
			_end_fee_resume_sidecar_frame(handle)
			return stale_tmp_result
		var target_pre:Dictionary=_fee_resume_io_read(frame.resume_path)
		var tmp_pre:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
		# Both reads are overridable seams. Re-check after the final read so a
		# callback changing owner/path/serial cannot pass into rename.
		if not _fee_resume_sidecar_frame_current(frame):
			var stale_read_result:Dictionary=_fee_resume_sidecar_result(frame,false,"owner_or_cas_after_target_reads_before_rename",true,false)
			_end_fee_resume_sidecar_frame(handle)
			return stale_read_result
		if not _fee_resume_bool_field_is(target_pre,"ok",true) or not _fee_resume_bool_field_is(target_pre,"exists",frame.target_exists) or (frame.target_exists and target_pre.get("bytes",PackedByteArray())!=frame.target_bytes) or not _fee_resume_bool_field_is(tmp_pre,"ok",true) or not _fee_resume_bool_field_is(tmp_pre,"exists",true) or tmp_pre.get("bytes",PackedByteArray())!=frame.payload:
			var target_result:Dictionary=_fee_resume_sidecar_result(frame,false,"target_or_tmp_changed_before_rename",true,false)
			target_result["target_pre_error"]=target_pre.get("error",OK)
			target_result["temporary_pre_error"]=tmp_pre.get("error",OK)
			_end_fee_resume_sidecar_frame(handle)
			return target_result
		operation_error=_fee_resume_io_rename()
		operation_completed=operation_error==OK
	else:
		if not _fee_resume_sidecar_frame_current(frame):
			var stale_remove_result:Dictionary=_fee_resume_sidecar_result(frame,false,"owner_or_cas_before_remove",false,false)
			_end_fee_resume_sidecar_frame(handle)
			return stale_remove_result
		if frame.target_exists:
			operation_attempted=true
			operation_error=_fee_resume_io_remove()
			operation_completed=operation_error==OK
		else:
			operation_completed=true # Verified absence; no mutation was attempted.
	var after:Dictionary=_fee_resume_io_read(frame.resume_path)
	var tmp_after:Dictionary=_fee_resume_io_read(frame.resume_path+".tmp")
	var fact:Dictionary=_fee_resume_sidecar_fact_from_read(frame,after)
	var persisted:Variant=fact.get("sidecar_persisted","unknown")
	var persisted_matches:bool=false
	if persisted is bool:
		persisted_matches=persisted
	var current:bool=_fee_resume_sidecar_frame_current(frame)
	var tmp_clear:bool=_fee_resume_bool_field_is(tmp_after,"ok",true) and _fee_resume_bool_field_is(tmp_after,"exists",false)
	var success:bool=operation_completed and persisted_matches and current and tmp_clear
	var stage:String="verified"
	if not current and persisted_matches:stage="owner_changed_after_io"
	elif not _fee_resume_bool_field_is(after,"ok",true) or not _fee_resume_bool_field_is(tmp_after,"ok",true):stage="readback_unknown"
	elif not operation_completed:stage="io_return_failed"
	elif not persisted_matches:stage="target_state_not_verified"
	elif not tmp_clear:stage="temporary_not_cleared"
	var final_result:Dictionary=fact.duplicate(true)
	final_result.merge({"ok":success,"operation_attempted":operation_attempted,"operation_completed":operation_completed,"stage":stage,"operation_error":operation_error,"temporary_clear":tmp_clear,"temporary_exists":tmp_after.get("exists","unknown")},true)
	_end_fee_resume_sidecar_frame(handle)
	return final_result

## After load_profile: a run written down at the last shutdown goes on once
## the character stands where it ran (automation.gd try_resume). The file is
## used once.
func load_resume() -> void:
	var path := _resume_file()
	if path.is_empty() or not FileAccess.file_exists(path):return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var state = JSON.to_native(parsed) if parsed!=null else null
	var allow_fee_quest_resume:bool=_fee_attempt_resume_allowed(session._profile,state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if state is Dictionary:
		if state.get("adult_battle") is Dictionary:
			if not AdultCheckpoint.restore(self,state.adult_battle) and str(state.adult_battle.get("battle_id","")) not in session._profile.completed_battles:return
		if state.get("wood_battle") is Dictionary:_restore_wood_battle(state.wood_battle)
		var quest_intent:bool=state.get("quest_auto") is Dictionary and automation.resume_wanted()
		# A real restored battle owns its exact authority position. Ordinary quest
		# intent has no coordinate authority: use only the validated saved profile.
		if quest_intent and allow_fee_quest_resume and not battle_open and session._pending.is_empty():
			if not _restore_quest_saved_position():return
		if state.has("kind"):automation.load_resume(state)
		if quest_intent and allow_fee_quest_resume:quest_auto.load_resume(self,state.quest_auto)

func _restore_quest_saved_position()->bool:
	var persisted=JSON.parse_string(last_saved_payload)
	if not persisted is Dictionary or not persisted.get("location") is Dictionary:return false
	var location:Dictionary=persisted.location
	var numeric=preload("res://server/quest_auto_motion.gd")
	var map_id=numeric.integer(location.get("map_id"))
	var x=numeric.integer(location.get("x"))
	var y=numeric.integer(location.get("y"))
	if map_id==null or x==null or y==null or not session._location_valid(location):return false
	var data:Dictionary=preload("res://scripts/map_file.gd").load_map(quest_helper.places.file(map_id))
	if data.is_empty() or x>=int(data.width) or y>=int(data.height) or int(data.blocked[y*int(data.width)+x])!=0:return false
	# Project placement deliberately grants no walk/arrival/approach proof.
	automation.position_changed(map_id,Vector2i(x,y),false,"project")
	return true

## 重启后自动恢复's file: <save>.resume.json, or tests' resume_path.
func _resume_file() -> String:
	if not resume_path.is_empty():return resume_path
	return save_path.get_basename()+".resume.json" if not save_path.is_empty() else ""

## Where a capture came from: the find-pet cycle (with its run), the hunt's
## automatic capture battle, or a battle the player fought; GM grants say so.
func _capture_entry(event: Dictionary) -> Dictionary:
	if event.has("entry"):return event.entry.duplicate(true)
	var pet: Dictionary = event.pet
	var source := str(event.get("source",""))
	if source.is_empty():
		if automation.flow_active():source = "找宠流程"
		elif automation.running and str(automation.settings.get("preset",""))=="capture":source = "自动抓宠"
		else:source = "手动捕获"
	var lv120: Dictionary = Progression.project_pet(pet,120) if int(pet.get("level",1))<120 else {}
	var entry := ReleaseLog.capture_entry(pet,lv120,automation.position_map,map_name(automation.position_map),automation.position_cell,source,automation.flow_run_id if source=="找宠流程" else "",automation.capture_decision(pet,source))
	return entry

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
	# This command is handled before Stationary/quest cancellation paths. Its
	# only client-supplied field is seq; transport identity is injected here by
	# WsServer/ProfileHub and bound to this Backend's attached peer epoch.
	if type=="quest_loot_start":return _cmd_quest_loot_start(command)
	# Reject forged encounter/set commands before canceling activities/dialogues.
	var position_error:=""
	if type=="auto" and str(command.get("name",""))=="set":
		position_error=str(automation.command("set",command).reason)
	elif type in ["wild_encounter","field_step","auto_start","auto","auto_step","stationary_encounters","stationary_keepalive"]:
		position_error=encounter_command_error(command,type in ["wild_encounter","field_step"])
	if not position_error.is_empty():return {"ok":false,"reason":position_error,"seq":command.get("seq",0),"type":"rejected"}
	# Exact service cancellation precedes generic activity/quest conflicts.
	if type=="permit_shop_cancel" or (type=="quest_close" and original_quests.pending.get("phase","")=="permit_shop"):
		var closed:Dictionary=RequiredFee.close_shop(self,command)
		closed.seq=command.get("seq",0);closed.type="ack" if closed.get("ok",false) else "rejected"
		return closed
	var fee_refusal:Dictionary=_permit_entry_refusal(command)
	if not fee_refusal.is_empty():return fee_refusal
	stationary.command(self,type)
	var quest_conflict:bool=quest_auto.running and type in ["quest_talk","quest_choose","quest_close","quest_visit","quest_discard","permit_shop_open","permit_shop_choose"]
	if quest_conflict and type in ["quest_choose","quest_close"] and quest_auto.accepts_waiting_command(self,command):quest_conflict=false
	if quest_auto.running:
		if type in ["warp","auto","auto_start","flow_start","hunt_start","start_hunt","open_battle","begin_battle","start_battle_config","start_wild_battle_config","start_wild_battle","field_step","wild_encounter"]:
			var stop_result:Dictionary=quest_auto.stop(self,"其他操作停止了自动任务。")
			if not stop_result.get("ok",false):
				stop_result.seq=command.get("seq",0)
				stop_result.type="rejected"
				return stop_result
	var before_position := [automation.position_map,automation.position_cell]
	var reply: Dictionary
	# Movement/activity invalidates the conversation even if another device
	# later walks back or stops before confirming the old window.
	if type in ["warp","auto","auto_start","flow_start","open_battle","begin_battle","start_battle_config","start_wild_battle_config","start_wild_battle"]:original_quests.pending={}
	if quest_conflict:reply = _reject("自动任务正在执行，请先停止。")
	elif not admin and admin_only(type):reply = _reject("只有管理员角色可以使用 GM 和开发者功能。")
	elif type in TURN_COMMANDS and command.has("turn") and not _current_turn(command):reply = _stale("battle turn already resolved")
	elif PROFILE_COMMANDS.has(type):reply = _profile_command(type,command)
	elif has_method("_cmd_"+type):reply = call("_cmd_"+type,command)
	else:reply = _reject("unknown command "+type)
	var fee_completed:bool=reply.get("_required_fee_call") is RefCounted
	reply.erase("_required_fee_call")
	if not fee_completed and before_position!=[automation.position_map,automation.position_cell]:
		original_quests.pending={}
		stationary.stop(self,"位置改变，已停止原地遇敌。")
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
	return {"type":"snapshot","v":PROTOCOL,"rev":rev,"profile":profile,"derived":_derived(),"options":_options(),"battle":_live_battle_state(),"battle_open":battle_open,"automation":automation.status(),"capabilities":_capabilities()}

func _capabilities() -> Dictionary:
	return {"quest_loot_enabled":_quest_loot_public_enabled()}

## The immutable server-side switch is shared by projection and future server
## authorization. Tests may override this getter on an isolated Backend; no
## client field or runtime RPC can enable the feature.
func _quest_loot_public_enabled() -> bool:
	return QUEST_LOOT_PUBLIC_ENABLED

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
	var loot_checkpoint:Dictionary=quest_loot.capture_followup_checkpoint(self,command)
	if battle_open and str(battle.snapshot().outcome)=="defeat":
		session.set_location(VILLAGE.map_id,VILLAGE.x,VILLAGE.y)
	elif command.has("map_id"):
		session.set_location(int(command.map_id),int(command.x),int(command.y))
	# A nonempty call is an exact read-only same-payload checkpoint candidate.
	# Pass it explicitly to the original private save body; ordinary save()
	# and unrelated checkpoint paths never inherit a dynamic capability.
	var saved:bool=save() if loot_checkpoint.is_empty() else _save_profile_boundary(loot_checkpoint)
	if not loot_checkpoint.is_empty():loot_checkpoint.timer.finish_followup_checkpoint(self,loot_checkpoint,saved)
	_publish()
	if not saved:return _reject("save_failed")
	return {"ok":true}

## Confirmed appearance + mount transaction. The chooser supplies the field
## context it opened with; a second device cannot silently retarget it.
func _cmd_mount_pet_as(command: Dictionary) -> Dictionary:
	if battle_open or not session._pending.is_empty():return _reject("战斗中不能骑乘或下骑。")
	if automation.running or automation.hunt_running or automation.flow_active() or quest_auto.running:return _reject("自动活动中不能更换骑乘造型，请先停止。")
	for field in ["pet_id","character_id","expected_character"]:
		if not command.get(field) is String:return _reject("无效的骑乘请求。")
	var cell = command.get("cell")
	if not cell is Array or cell.size()!=2:return _reject("无效的位置。")
	if not session._integer(command.get("map_id"),0,2147483647) or not session._integer(cell[0],0,2147483647) or not session._integer(cell[1],0,2147483647):return _reject("无效的位置。")
	if str(session._profile.character_id)!=command.expected_character or int(command.map_id)!=automation.position_map or Vector2i(int(cell[0]),int(cell[1]))!=automation.position_cell:return _reject("造型或位置已改变，请重新选择骑乘。")
	var before: Dictionary = session.snapshot()
	if not session.mount_pet_as(command.pet_id,command.character_id):return _reject(session.last_error)
	if not save():
		session._profile = before
		return _reject("save_failed")
	_publish()
	return {"ok":true}

func _required_arguments(method: String) -> int:
	for info in session.get_script().get_script_method_list():
		if info.name==method:return info.args.size()-info.default_args.size()
	return 0

func _profile_command(type: String, command: Dictionary) -> Dictionary:
	if type=="use_item":
		if command.has("pet_id") and not command.has("item"):return _reject("missing item")
		if battle_open:return _reject("野外道具不能在战斗中使用；复活秘药请从战斗道具菜单选择。")
	# Warehouse transfers must not become visible until their save commits.
	var warehouse_transfer := type in ["store_pet","retrieve_pet","retrieve_pet_by_id"]
	var rollback_on_save_failure := warehouse_transfer or type in ["use_item","equip_item"]
	var before: Dictionary=session.snapshot() if rollback_on_save_failure else {}
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
	var saved := save()
	if rollback_on_save_failure and not saved:
		session._profile=before
		session.last_note=""
		return _reject("保存失败，宠物未移动，请重试。" if warehouse_transfer else "save_failed")
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
	var previous_settings:Dictionary=session.automation_settings()
	session.last_error = ""
	var validated:Dictionary=AutomationSettings.apply_patch(previous_settings,command.settings)
	if not validated.ok:return _reject(str(validated.reason))
	if not save_path.is_empty() and not session._pending.is_empty():
		# Persist only preferences against the trusted pre-battle save. Never
		# mark the live HP/items/rewards/location as already saved by this write.
		var saved:Dictionary=session.save_settings_on_saved_profile(last_saved_payload,validated.overrides,save_path)
		if not saved.ok:return _reject("save_failed")
		last_saved_payload=saved.payload
		quest_save_serial+=1
		session._profile.automation_settings=validated.overrides.duplicate(true)
	else:
		# Preserve ordinary and memory-only backend save semantics.
		session._profile.automation_settings=validated.overrides.duplicate(true)
		if not save():
			session._profile.automation_settings=previous_settings
			return _reject("save_failed")
	automation.profile_settings_changed()
	quest_auto.settings_changed(self,previous_settings)
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
	# 放生 only: sorted by a stat, and 未捕获 (hits let go from the queue) only.
	var sort := "" if caught else str(command.get("sort",""))
	var page: Dictionary = log.page(int(command.get("page",0)),int(command.get("page_size",20)),int(command.get("template_id",-1)),run,sort,bool(command.get("ascending",false)),not caught and bool(command.get("uncaught",false)))
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

## 宠物记录's 排队 tab: the 后台搜宠 queue (automation.gd queue_view).
func _cmd_hunt_queue(_command: Dictionary) -> Dictionary:
	return {"ok":true,"queue":automation.queue_view()}

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
		var rule: Dictionary = AutomationSettings.keep_rule(session.automation_settings())
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
	# Borrowed source presentation is issued only by this authority.
	for key in ["capture_only","capture_destination","capture_slots","can_capture","original_revival_items","original_revival_budget","revival_transaction","pvp","norisk"]:
		config.erase(key)
		if session._pending.has(key):config[key] = session._pending[key]
	config.erase("training_borrow")
	if session._pending.get("training_borrow") is Dictionary:config.training_borrow=session._pending.training_borrow.duplicate(true)
	var source_encounter := bool(session._pending.get("source_encounter",false))
	if source_encounter and config.get("enemies",[]).size()!=session._pending.get("enemies",[]).size():return _reject("stale battle troop")
	for i in range(config.get("enemies",[]).size()):
		for key in ["generated_drops","source_enemy_id","source_wait_only"]:
			config.enemies[i].erase(key)
			if source_encounter and session._pending.enemies[i].has(key):config.enemies[i][key] = session._pending.enemies[i][key]
	return {"ok":true,"state":open_battle(config)}

func _cmd_begin_battle(command: Dictionary) -> Dictionary:
	if battle.snapshot().active:return _stale("battle active")
	var boss := bool(command.get("boss",false))
	var enemy_count := int(command.get("enemy_count",0))
	var config: Dictionary = session.start_battle_config("woolistan" if boss else DEBUG_SPECIES[encounter_serial%3],boss,1 if boss else (enemy_count if enemy_count > 0 else 1 + encounter_serial % 3))
	if config.is_empty():return _reject("battle unavailable")
	return {"ok":true,"state":open_battle(config)}

## Temporary stationary encounters; movement randomness remains shared.
func _cmd_stationary_encounters(command: Dictionary) -> Dictionary:
	var reason:=encounter_command_error(command,false)
	if not reason.is_empty():return _reject(reason)
	return stationary.start(self,command)

func _cmd_stationary_keepalive(command: Dictionary) -> Dictionary:
	return stationary.keepalive(self,command)

func _cmd_stationary_pause(_command: Dictionary) -> Dictionary:
	stationary.stop(self,"打开菜单或对话，已停止原地遇敌。")
	return {"ok":true}

func _cmd_no_random_encounters(command: Dictionary) -> Dictionary:
	if not command.get("enabled") is bool:return _reject("开关必须为布尔值。")
	var previous: bool = session._profile.get("no_random_encounters",false)
	session._profile.no_random_encounters = command.enabled
	# Battle settlement saves the changed preference with its committed rewards.
	if session._pending.is_empty() and not save():
		session._profile.no_random_encounters = previous
		return _reject("保存助手设置失败。")
	if command.enabled:stationary.stop(self,"不遇敌已开启。")
	publish()
	return {"ok":true,"enabled":command.enabled}

## Encounter coordinates are assertions, never a movement command. Validate before
## pressure/RNG or pending battle state changes, including no-encounter mode.
func encounter_position_error(map_id: int, cell: Vector2i) -> String:
	if automation.position_map>=0 and map_id==automation.position_map and cell==automation.position_cell:return ""
	var reason:="位置已改变或尚未确认，请同步服务器位置后再遇敌。"
	automation.log_line("[遇敌位置拒绝] 请求 %d (%d,%d)，服务器 %d (%d,%d)。"%[map_id,cell.x,cell.y,automation.position_map,automation.position_cell.x,automation.position_cell.y])
	return reason

func encounter_command_error(command: Dictionary, required: bool = true) -> String:
	if not required and not command.has("map_id") and not command.has("cell"):return ""
	var point=command.get("cell",[])
	if not session._integer(command.get("map_id",-1),0,2147483647) or not point is Array or point.size()!=2 or not session._integer(point[0],0,2147483647) or not session._integer(point[1],0,2147483647):
		automation.log_line("[遇敌位置拒绝] 无效地图或坐标参数。")
		return "无效的遇敌位置。"
	return encounter_position_error(int(command.map_id),Vector2i(int(point[0]),int(point[1])))

func _cmd_field_step(command: Dictionary) -> Dictionary:
	var reason:=encounter_command_error(command)
	if not reason.is_empty():return _reject(reason)
	if battle_open or not session._pending.is_empty():return _stale("battle active or awaiting settlement")
	# Only walking randomness is disabled. Explicit battles/hunting keep their authority.
	if session._profile.get("no_random_encounters",false):return {"ok":true,"hit":false,"battle":false}
	var hit: bool = encounter_catalog.step(automation.position_map,automation.position_cell,encounter_rng)
	if not hit or not bool(command.get("encounter",false)):return {"ok":true,"hit":hit,"battle":false}
	var opened := wild_encounter(automation.position_map,automation.position_cell)
	opened.hit = true
	opened.battle = bool(opened.ok)
	opened.ok = true
	return opened

func _cmd_wild_encounter(command: Dictionary) -> Dictionary:
	var reason:=encounter_command_error(command)
	if not reason.is_empty():return _reject(reason)
	var result := wild_encounter(automation.position_map,automation.position_cell)
	return result

func wild_encounter(map_id: int, cell: Vector2i, training_groups: Variant = null) -> Dictionary:
	var reason:=encounter_position_error(map_id,cell)
	if not reason.is_empty():return _reject(reason)
	if battle_open or not session._pending.is_empty() or battle.snapshot().active:return _stale("battle active or awaiting settlement")
	var troop: Dictionary = encounter_catalog.roll(automation.position_map,automation.position_cell,encounter_rng,session.snapshot().get("original_items",[]))
	if troop.is_empty():
		var reply := _reject(encounter_catalog.last_error)
		reply.skipped = "data"
		return reply
	if not TroopArt.can_render(troop.enemies):
		var reply := _reject("art")
		reply.skipped = "art"
		return reply
	if training_groups is Array and not int(troop.get("group_id",-1)) in training_groups:
		encounter_catalog.pressure=int(encounter_catalog.area_at(map_id,cell).get("probability_min",0))
		return {"ok":false,"skipped":"training","troop":troop}
	var config: Dictionary = session.start_wild_battle_config(troop)
	if config.is_empty():return _reject("battle validation failed")
	var state := open_battle(config)
	encounter_catalog.pressure = int(encounter_catalog.area_at(map_id,cell).get("probability_min",0))
	return {"ok":true,"state":state,"troop":troop}

## Dedicated server stream; persist the fully consumed roll before any battle
## or forecast. It never touches encounter pressure, walking or hunt streams.
func prepare_training_borrow() -> Dictionary:
	if battle_open or not session._pending.is_empty():return _reject("battle active")
	var Borrow=preload("res://server/training_borrow.gd")
	var candidates: Array=Borrow.available(encounter_catalog,session.world_catalog,session.snapshot())
	if candidates.is_empty():return _reject("没有可用的已审核高等级敌群，请检查素材和进场条件，或关闭借用。")
	var saved: Dictionary=session.training_borrow_rng()
	if Borrow.valid_rng(saved):training_pool_rng.seed=int(saved.seed);training_pool_rng.state=int(saved.state)
	var troop: Dictionary=Borrow.roll(encounter_catalog,candidates,training_pool_rng,session.snapshot().get("original_items",[]))
	session.set_training_borrow_rng({"seed":str(training_pool_rng.seed),"state":str(training_pool_rng.state)})
	if not save():return _reject("无法保存借用敌群随机进度，已暂停，没有进入战斗。")
	if troop.is_empty() or not TroopArt.can_render(troop.get("enemies",[])):return _reject("借用敌群的真实队形或素材不可用，已暂停。")
	var config:=training_borrow_config(troop)
	if config.is_empty():return _reject("借用敌群战斗配置无法通过原规则校验，已暂停。")
	return {"ok":true,"troop":troop,"config":config}

func valid_training_borrow(troop: Dictionary) -> bool:
	var meta: Dictionary=troop.get("training_borrow",{})
	if meta.is_empty():return false
	for row in preload("res://server/training_borrow.gd").available(encounter_catalog,session.world_catalog,session.snapshot()):
		if int(row.map_id)==int(meta.map_id) and int(row.area_id)==int(meta.area_id) and int(row.group_id)==int(meta.group_id) and row.cell==meta.cell:return true
	return false

func training_borrow_config(troop: Dictionary) -> Dictionary:
	var config: Dictionary=session.preview_wild_battle_config(troop)
	if config.is_empty():return {}
	if training_borrow_preview.is_valid():config=training_borrow_preview.call(config)
	return config

func open_battle(config: Dictionary) -> Dictionary:
	WildLoot.freeze(self)
	quest_loot.bind_battle(self)
	session.battle_pets_hook = _live_battle_pets
	session.capture_entry_hook = _capture_entry
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
## Read-only roster/experience mode of the party the next encounter will open.
var training_reward_context: Callable
var training_borrow_preview: Callable

## This profile joins a party battle (its pending record is already set):
## `view` is its window on it (server/party_battles.gd SlotView).
func open_party_battle(view) -> Dictionary:
	session.battle_pets_hook = _live_battle_pets
	session.capture_entry_hook = _capture_entry
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
	_dispatch_boundary_depth+=1
	_depth += 1
	_after_turn(state,slice,drop_claims)
	_depth -= 1
	_flush()
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()

## A party member sent a command; the turn still waits for others.
func party_status() -> void:
	_dispatch_boundary_depth+=1
	_depth += 1
	_refresh_battle_state()
	_depth -= 1
	_flush()
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()

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
	if str(command.get("action","")).begins_with("revival:"):
		if not session._integer(command.get("target"),0,19):return _reject("无效的复活目标。")
		if not party_battle():
			var reason: String=battle.revival_refusal({"kind":"player","index":-1},str(command.action),int(command.target))
			if not reason.is_empty():return _reject(reason)
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
	# Party dispatch consumes each terminal slice once. Keep the server-owned
	# personal result and claims across save rollback; the shared view cannot
	# substitute its battle id, XP or loot ownership on battle_close retry.
	if not bool(state.active) and bool(session._pending.get("party",false)):
		if not settle.is_empty() and not session._pending.has("party_settlement"):
			session._pending.party_settlement={"result":settle.duplicate(true),"drop_claims":drop_claims.duplicate(true)}
		if session._pending.has("party_settlement"):
			settle=session._pending.party_settlement.result.duplicate(true)
			drop_claims=session._pending.party_settlement.drop_claims.duplicate(true)
	if not bool(state.active) and bool(battle_state.get("settled",false)) and str(battle_state.get("battle_id",""))==str(state.get("battle_id","")):
		return battle_state.duplicate(true)
	if settle.is_empty() and battle_open and not party_battle():session._pending.loot_claims = battle.drop_claims_for()
	var before: Dictionary = session.snapshot()
	var capture_only := bool(session._pending.get("capture_only",false)) and not party_battle()
	var quest_transaction: bool=session._pending.has("quest_guard") or session._pending.has("wild_drop_receipt") or session._pending.get("enemies",[]).any(func(enemy):return EncounterCatalog.transactional_drop_enemy(int(enemy.get("source_enemy_id",0))))
	var revival_transaction: bool=_revival_transaction()
	var loot_transaction:bool=session._pending.has("quest_loot_receipt")
	var atomic: bool=capture_only or quest_transaction or revival_transaction or loot_transaction
	var pending_before: Dictionary = session._pending.duplicate(true) if atomic and not bool(state.active) else {}
	var capture_events_before: Array = session.capture_events.duplicate(true) if atomic and not bool(state.active) else []
	# A party battle settles this player's own slice (its own battle id and
	# rewards); the state its devices see stays the shared battle.
	var result: Dictionary = settle if not settle.is_empty() else state
	var arrival_denied:=""
	if not bool(state.active) and pending_before.has("quest_guard") and str(state.outcome)=="win":
		arrival_denied=quest_arrival.check_battle(self,pending_before.quest_guard)
		if not arrival_denied.is_empty():
			var blocked:Array=quest_arrival.blocked_guard_items(pending_before.quest_guard)
			if bool(pending_before.get("party",false)):
				drop_claims=_allowed_guard_claims(pending_before,drop_claims,blocked,result)
			else:
				session._pending.loot_claims=_allowed_guard_claims(pending_before,pending_before.get("loot_claims",[]),blocked,result)
	var wild_denied:=""
	var wild_error:=""
	if not bool(state.active) and pending_before.has("wild_drop_receipt"):
		wild_error=str(pending_before.wild_drop_receipt.get("error",""))
		var party:=bool(pending_before.get("party",false))
		var original_claims:Array=drop_claims if party else pending_before.get("loot_claims",[])
		if _loot_claims_valid(pending_before,original_claims,result):
			var filtered:Dictionary=WildLoot.filter_claims(self,pending_before.wild_drop_receipt,original_claims)
			wild_denied=str(filtered.denied)
			if party:drop_claims=filtered.claims
			else:session._pending.loot_claims=filtered.claims
	var applied:bool=not bool(state.active) and wild_error.is_empty() and session.apply_battle_result(result,drop_claims)
	if not applied and not bool(state.active) and (not arrival_denied.is_empty() or pending_before.has("wild_drop_receipt") or loot_transaction):session._pending=pending_before
	if not wild_error.is_empty():state.settlement_error=wild_error
	if applied:
		if pending_before.has("quest_guard") and str(state.outcome)=="win" and arrival_denied.is_empty():
			preload("res://server/brothers_quests.gd").settle_profile(self,pending_before.quest_guard)
		var loot_frame:Dictionary={}
		var loot_saved:Dictionary={}
		if loot_transaction:
			loot_frame=_prepare_loot_settlement(pending_before,result)
			if loot_frame.get("ok",false):loot_saved=_commit_loot_settlement(loot_frame)
			if loot_saved.get("ok",false):
				if loot_frame.timer.settlement_committed(loot_frame.lifetime,loot_frame.receipt,loot_saved.profile.quest_loot):
					loot_frame.timer.retire_cancelled_battle(self,loot_frame.lifetime,loot_frame.receipt)
			# The disk result is real even if a callback installed another run or
			# manual pending. Do not publish/rollback this old frame over it.
			if not _owns_loot_settlement(loot_frame):
				state.settled=bool(loot_saved.get("ok",false))
				if not state.settled:state.settlement_error="刷物结算上下文已改变；旧事务停止，未覆盖新状态。"
				return state.duplicate(true)
		if loot_transaction and loot_saved.get("ok",false):
			loot_frame.timer.record_followup(self,loot_frame.followup,loot_saved,loot_frame.receipt)
		var failed:bool=not loot_saved.get("ok",false) if loot_transaction else (atomic and not save())
		if failed:
			if loot_transaction:return _rollback_loot_settlement(loot_frame,before,pending_before,capture_events_before,state)
			session._profile = before
			session._pending = pending_before
			session.capture_events = capture_events_before
			stationary.settled(self,state,false)
			if quest_auto.running and quest_auto.phase=="waiting_boss":quest_auto.handoff(self,"守卫战保存失败，停止自动任务。")
			state.settled = false
			state.settlement_error = "复活道具战保存失败，已回滚道具、体力与奖励；再次结束战斗可重试。" if revival_transaction else "任务战保存失败，已回滚奖励与传送；请检查保存位置后再次结束战斗。" if quest_transaction else "只抓不练捕获保存失败，已回滚库存与奖励；请检查保存位置后再次结束战斗。"
			state.xp = 0;state.gold = 0;state.result_summary = []
			battle_state = state
			_emit({"type":"battle_turn","state":state.duplicate(true)})
			return state.duplicate(true)
		if not settle.is_empty():
			for key in ["xp","gold","pet_reward_xp","experience_multiplier","drop_summary"]:state[key] = result.get(key,0)
		state.settled = true
		if not wild_denied.is_empty():
			state.quest_drop_denied=wild_denied
			state.events.append(wild_denied)
		if not arrival_denied.is_empty():
			state.quest_arrival_denied=arrival_denied
			state.events.append(arrival_denied)
		if pending_before.has("quest_guard") and str(state.outcome)=="win" and arrival_denied.is_empty():
			preload("res://server/brothers_quests.gd").committed(self,pending_before.quest_guard)
			quest_arrival.battle_committed(self,pending_before.quest_guard)
			if not str(pending_before.quest_guard.get("warp","")).is_empty():state.quest_warp=str(pending_before.quest_guard.warp)
		for drop in state.get("drop_summary",[]):
			var item_name := str(quest_catalog.items.get(str(int(drop.item_id)),{}).get("name","原版物品 #%d"%int(drop.item_id)))
			drop.name = item_name
			state.events.append("获得%s。"%item_name if drop.received else "背包已满，%s已销毁。"%item_name)
		if state.outcome in ["win","captured"] and int(state.get("xp",0)) > 0:
			state.events.append("获得经验 %d，石币 %d。" % [int(state.get("xp",0)),int(state.get("gold",0))])
			var after: Dictionary = loot_saved.profile if loot_transaction else session.snapshot()
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
			state.events.append((("随身已满，已存仓" if pending_before.has("capture_destination") else "只抓不练：Lv.1伙伴已留在旧仓库。") if str(pending_before.get("capture_destination","storage"))=="storage" else "只抓不练：Lv.1伙伴已加入随身。") if capture_only else "伙伴已加入宠物栏，可为它取名并选择出战。")
		# The first atomic loot save already committed both rewards and counters.
		var saved_ok:bool = true if loot_transaction else save()
		stationary.settled(self,state,saved_ok)
		if not saved_ok and quest_auto.running and quest_auto.owns_battle:quest_auto.fail(self,"沿途战斗保存失败，停止自动任务。")
		_publish()
		if loot_transaction:
			if not _owns_loot_settlement(loot_frame):return state.duplicate(true)
			state.capture_assist=battle.capture_assist
			battle_state=state
			_publish_battle_pets()
			if _owns_loot_settlement(loot_frame):_emit({"type":"battle_turn","state":state.duplicate(true)})
			return state.duplicate(true)
	if capture_only and not bool(state.get("active",true)) and not bool(state.get("settled",false)):
		state.settlement_error = session.last_error if not session.last_error.is_empty() else "只抓不练捕获结算校验失败，已暂停，未发放奖励。"
		state.xp = 0;state.gold = 0;state.result_summary = []
	state.capture_assist = battle.capture_assist
	_publish_battle_pets()
	battle_state = state
	_emit({"type":"battle_turn","state":state.duplicate(true)})
	return state.duplicate(true)

## Narrow loot frame, independent of a later runner or live profile snapshot.
func _prepare_loot_settlement(pending:Dictionary,result:Dictionary)->Dictionary:
	var timer=quest_loot
	var frame:Dictionary={"ok":false,"session":session,"path":save_path,"battle":battle,
		"timer":timer,"lifetime":timer.lifetime,"automation":automation,"auto_token":automation.start_lifetime,"auto_scope":automation._loot_frame(),"receipt":pending.quest_loot_receipt.duplicate(true),"battle_id":str(pending.battle_id),
		"run_identity":quest_auto.identity.checkpoint(),"profile_ref":session._profile,
		"profile":session._profile.duplicate(true),"pending_ref":session._pending,
		"pending":session._pending.duplicate(true),"captures_ref":session.capture_events,
		"captures":session.capture_events.duplicate(true)}
	frame.followup=timer.capture_followup(self,frame.receipt)
	var prepared:Dictionary=session.prepare_loot_settlement(frame.receipt,str(pending.battle_id))
	if prepared.is_empty():
		timer.pause_storage_for(frame.lifetime);frame.reason="原战结算候选无法绑定。";return frame
	frame.capability=prepared.capability
	var candidate:Dictionary=timer.settlement_candidate(self,pending,result)
	if not candidate.ok:
		timer.pause_storage_for(frame.lifetime);frame.reason=str(candidate.reason);return frame
	if not _owns_loot_settlement(frame):
		frame.reason="刷物候选构建期间上下文已改变。";return frame
	frame.profile=prepared.profile
	frame.profile.quest_loot=candidate.ledger
	session._profile.quest_loot=candidate.ledger.duplicate(true)
	frame.ok=true
	return frame

func _owns_loot_settlement(frame:Dictionary)->bool:
	return not frame.is_empty() and is_same(session,frame.session) and save_path==frame.path and is_same(battle,frame.battle) and str(battle.snapshot().get("battle_id",""))==frame.battle_id and is_same(session._profile,frame.profile_ref) and session._profile==frame.profile and is_same(session._pending,frame.pending_ref) and session._pending==frame.pending and is_same(session.capture_events,frame.captures_ref) and session.capture_events==frame.captures

func _rollback_loot_settlement(frame:Dictionary,before:Dictionary,pending:Dictionary,captures:Array,state:Dictionary)->Dictionary:
	# Caller has already checked ownership after the failed synchronous write.
	session._profile=before;session._pending=pending;session.capture_events=captures
	session.abandon_loot_settlement(frame.get("capability"))
	frame.timer.pause_storage_for(frame.lifetime)
	# Bind the restored objects before callbacks; no write follows a lost frame.
	frame.profile_ref=session._profile;frame.profile=before.duplicate(true)
	frame.pending_ref=session._pending;frame.pending=pending.duplicate(true)
	frame.captures_ref=session.capture_events;frame.captures=captures.duplicate(true)
	state.settled=false
	state.settlement_error=frame.get("reason","刷物战保存失败，战果与预算均已回滚；原战结算可重试。")
	state.xp=0;state.gold=0;state.result_summary=[]
	battle_state=state
	frame.timer.freeze_failed_auto(self,frame)
	if not _owns_loot_settlement(frame):return state.duplicate(true)
	stationary.settled(self,state,false)
	if not _owns_loot_settlement(frame):return state.duplicate(true)
	if is_same(quest_loot,frame.timer) and is_same(frame.timer.lifetime,frame.lifetime) and is_same(automation,frame.automation) and is_same(automation.start_lifetime,frame.auto_token) and quest_auto.running and quest_auto.identity.checkpoint()==frame.run_identity:quest_auto.handoff(self,"刷物战结算未保存，停止新尝试。")
	if _owns_loot_settlement(frame):_emit({"type":"battle_turn","state":state.duplicate(true)})
	return state.duplicate(true)

func _commit_loot_settlement(frame:Dictionary)->Dictionary:
	if not frame.get("ok",false) or not _owns_loot_settlement(frame):return {"ok":false}
	return frame.session.commit_loot_settlement(frame.capability,frame.profile,frame.path,_loot_settlement_written.bind(frame.session,frame.path))

func _loot_settlement_written(payload:String,owner,path:String)->void:
	# Called synchronously at the actual candidate write boundary. A later
	# observer's save updates this cache afterwards and wins normally.
	if not is_same(session,owner) or save_path!=path:return
	last_saved_payload=payload
	quest_save_serial+=1

## Validate the entire original list before either task filter. Invalid claims
## stay untouched for the normal Session rejection; suppression cannot repair them.
func _loot_claims_valid(pending:Dictionary, claims:Array, battle_result:Dictionary)->bool:
	var enemies:Array=pending.get("enemies",[])
	var finished:Array=battle_result.get("enemies",[])
	if finished.size()!=enemies.size():return false
	var seen:Dictionary={}
	for claim in claims:
		if not claim is Dictionary or not session._integer(claim.get("enemy"),0,enemies.size()-1):return false
		var index:=int(claim.enemy)
		var generated:Array=enemies[index].get("generated_drops",[])
		if not session._integer(claim.get("item"),0,generated.size()-1):return false
		var key:="%d:%d"%[index,int(claim.item)]
		if seen.has(key) or not finished[index] is Dictionary or not session._integer(finished[index].get("hp"),0,0) or bool(finished[index].get("captured",false)):return false
		seen[key]=true
	return true

func _allowed_guard_claims(pending:Dictionary, claims:Array, blocked:Array, battle_result:Dictionary)->Array:
	if blocked.is_empty() or not _loot_claims_valid(pending,claims,battle_result):return claims.duplicate(true)
	var result:Array=[]
	for claim in claims:
		if not int(pending.enemies[int(claim.enemy)].generated_drops[int(claim.item)]) in blocked:result.append(claim.duplicate(true))
	return result

func _cmd_battle_close(command: Dictionary) -> Dictionary:
	if not battle_open:return _stale("no open battle")
	# Naming the battle: one already closed and replaced (a party leader's
	# 自动练级 met the next troop, LAN phase 4c) is not an error.
	if command.has("battle_id") and str(command.battle_id)!=str(battle.snapshot().get("battle_id","")):return _stale("battle already closed")
	if battle.snapshot().active:return _reject("battle not finished")
	if _revival_transaction() or session._pending.has("quest_loot_receipt") or bool(session._pending.get("capture_only",false)) or session._pending.has("quest_guard") or session._pending.has("wild_drop_receipt") or session._pending.get("enemies",[]).any(func(enemy):return EncounterCatalog.transactional_drop_enemy(int(enemy.get("source_enemy_id",0)))):
		var loot_retry:bool=session._pending.has("quest_loot_receipt")
		var retry_session=session
		var retry_battle=battle
		var retry_id:=str(battle.snapshot().get("battle_id",""))
		var retried := _after_turn(battle.snapshot())
		if loot_retry and (not is_same(session,retry_session) or not is_same(battle,retry_battle) or str(battle.snapshot().get("battle_id",""))!=retry_id or (bool(retried.get("settled",false)) and not session._pending.is_empty())):return _stale("loot settlement context replaced")
		if not bool(retried.get("settled",false)):return _reject(str(retried.get("settlement_error","捕获未结算")))
	return {"ok":true,"outcome":close_battle()}

func close_battle() -> String:
	var loot_close:Dictionary=quest_loot.capture_followup_close(self)
	var outcome := str(battle.snapshot().outcome)
	if outcome=="defeat":session.set_location(VILLAGE.map_id,VILLAGE.x,VILLAGE.y)
	battle_open = false
	var close_saved:bool=save()
	quest_loot.record_followup_close(self,loot_close,close_saved)
	_publish_battle_pets()
	_emit({"type":"battle_closed","battle_id":str(battle_state.get("battle_id","")),"outcome":outcome})
	if battle_state.has("quest_warp"):preload("res://server/brothers_quests.gd").publish_warp(self,str(battle_state.quest_warp))
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
	for key in ["settled","settlement_error","result_summary","xp","gold","pet_reward_xp","experience_multiplier","drop_summary"]:
		if battle_state.has(key) and not live.get("active",false):live[key] = battle_state[key]
	if not live.get("active",false) and battle_state.has("events") and str(battle_state.get("outcome",""))==str(live.get("outcome","")):live.events = battle_state.events
	live.capture_assist = battle.capture_assist
	return live.duplicate(true)

# ---- automation ------------------------------------------------------------

## Capture-only project travel: the server chooses the cell from reviewed data.
func _cmd_reviewed_hunt_travel(command: Dictionary) -> Dictionary:
	if battle_open or not session._pending.is_empty() or automation.running or automation.hunt_running or automation.flow_active() or quest_auto.running:return _reject("当前正忙，请先停止战斗或自动活动。")
	if quest_visit_guard.is_valid() and not str(quest_visit_guard.call()).is_empty():return _reject("组队时请先离开队伍再使用捕宠瞬移。")
	var plan: Dictionary=reviewed_hunt_travel.resolve(self,command)
	if plan.is_empty():return _reject("此目标不在服务器审核的捕宠直达名单，或原资料已改变。")
	original_quests.pending={}
	automation.position_changed(int(plan.map_id),plan.cell,int(plan.map_id)!=automation.position_map)
	_emit({"type":"position","map_id":int(plan.map_id),"cell":[plan.cell.x,plan.cell.y],"client":"server"})
	_publish()
	return {"ok":true,"target":{"map_id":int(plan.map_id),"area_id":int(plan.area_id),"template_id":int(plan.template_id),"cell":[plan.cell.x,plan.cell.y],"level_one":bool(plan.level_one)},"notice":reviewed_hunt_travel.POLICY}

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

## Internal-only original undersea permit transaction. No _cmd_ dispatcher entry.
func commit_undersea_permit_gate(source_id:String,run_id:String,step_id:String,revision:int)->Dictionary:
	if not quest_auto.running or not quest_auto.internal or quest_auto.phase!="travel" or run_id.is_empty() or step_id.is_empty() or quest_auto.identity.run_id!=run_id or quest_auto.identity.step_id!=step_id or quest_auto.identity.revision!=revision:return _reject("原守卫推进请求已过期。")
	if battle_open or not session._pending.is_empty() or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return _reject("当前正忙，不能通过持证守卫。")
	if quest_visit_guard.is_valid():
		var reason:=str(quest_visit_guard.call())
		if not reason.is_empty():return _reject(reason)
	var checked:Dictionary=preload("res://server/quest_auto_permit_gate.gd").validate(self,source_id)
	if not checked.get("ok",false):return checked
	if not quest_auto.running or not quest_auto.internal or quest_auto.phase!="travel" or quest_auto.identity.run_id!=run_id or quest_auto.identity.step_id!=step_id or quest_auto.identity.revision!=revision:return _reject("原守卫推进请求已过期。")
	if battle_open or not session._pending.is_empty() or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return _reject("当前状态已改变，不能通过持证守卫。")
	var target:Dictionary=checked.target
	var before:Dictionary=session.snapshot()
	if not session.set_location(10202,int(target.cell[0]),int(target.cell[1])):return _reject("无法保存原守卫目的位置。")
	if not save():
		session._profile=before
		return _reject("save_failed")
	# Saving is the commit boundary. Even a cancellation observer inside save
	# must not turn a committed source Warp into a fictitious failed transaction.
	automation.position_changed(10202,Vector2i(int(target.cell[0]),int(target.cell[1])),false,"script")
	return {"ok":true,"committed":true,"target":target}

## Authorize the guarded sea portal using this backend's current map and permit.
func _cmd_check_passage(command: Dictionary) -> Dictionary:
	var timed_reason:=TimePassage.check(quest_helper.places,automation.position_map,automation.position_cell,int(command.get("to_map",-1)))
	if not timed_reason.is_empty():return _reject(timed_reason)
	if int(command.get("to_map",-1))==10204 and automation.position_map!=10204 and int(session._profile.player.level)<30:return _reject("原仪式入口需要等级30。")
	if int(command.get("from_map",-1))!=automation.position_map:return _reject("位置已经改变。")
	if preload("res://scripts/passage_rules.gd").requires_permit(automation.position_map,int(command.get("to_map",-1))) and not session.has_travel_pass():
		return _reject("穿过海底关卡需要通行证。")
	return {"ok":true}

## Positions are reported by whichever client walks; every other client
## follows the broadcast (the reporter recognises its own client id).
## Internal host call, never selected by a client command or its "client" field.
func report_party_position(command:Dictionary, evidence:Dictionary = {})->Dictionary:
	_following_party=true
	_party_move_evidence=evidence.duplicate(true)
	var result:=handle(command)
	_following_party=false
	_party_move_evidence={}
	return result

## Explicit project movement can only revoke route proof. The source kind is
## selected here, never accepted from a caller's report/party/grant fields.
func _cmd_project_position(command:Dictionary)->Dictionary:
	if quest_visit_guard.is_valid() and not str(quest_visit_guard.call()).is_empty():return _reject("组队时请先离开队伍再使用地图瞬移。")
	if battle_open or not session._pending.is_empty() or automation.running or automation.hunt_running or automation.flow_active() or quest_auto.running:return _reject("当前正忙，请先停止自动活动或战斗。")
	var values=command.get("cell",[])
	if not session._integer(command.get("map_id"),0,2147483647) or int(command.map_id)!=automation.position_map or not values is Array or values.size()!=2 or not session._integer(values[0],0,2147483647) or not session._integer(values[1],0,2147483647):return _reject("位置已改变，请重新选择地图落点。")
	var map:Dictionary=preload("res://scripts/map_file.gd").load_map(quest_helper.places.file(int(command.map_id)))
	var cell:=_cell(command)
	if map.is_empty() or cell.x>=int(map.width) or cell.y>=int(map.height) or int(map.blocked[cell.y*int(map.width)+cell.x])!=0:return _reject("项目移动落点不可通行。")
	for npc in quest_helper.places.residents:
		if int(npc.map_id)==int(command.map_id) and cell==Vector2i(int(npc.cell[0]),int(npc.cell[1])):return _reject("项目移动不能占用人物格。")
	var request:Dictionary=command.duplicate(true)
	request.erase("quest_position_seq")
	request.client="server"
	_project_position=true
	var reply:Dictionary=_cmd_report_position(request)
	_project_position=false
	return reply

func _cmd_report_position(command: Dictionary) -> Dictionary:
	var helper_stage: Array = quest_helper.navigation_key(self)
	# Validate before accepting old helper receipts: none authorizes a new
	# same-map jump across the dream cave's original maze or final guard.
	if not _following_party:
		var dream_reason:=DreamPassage.check(quest_helper.places,automation.position_map,automation.position_cell,int(command.get("map_id",-1)),command.get("cell",[]))
		if not dream_reason.is_empty():
			_emit({"type":"position","map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"client":"server"})
			return _reject(dream_reason)
	if not _project_position and quest_auto.accept_report(self,command):return {"ok":true}
	if not _following_party:
		var timed_reason:=TimePassage.check(quest_helper.places,automation.position_map,automation.position_cell,int(command.get("map_id",-1)),command.get("cell",[]))
		if not timed_reason.is_empty():
			_emit({"type":"position","map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"client":"server"})
			return _reject(timed_reason)
	if int(command.map_id)==10204 and automation.position_map!=10204 and int(session._profile.player.level)<30:return _reject("原仪式入口需要等级30。")
	var origin: int = automation.position_map
	if preload("res://scripts/passage_rules.gd").requires_permit(origin,int(command.map_id)) and not session.has_travel_pass():
		return _reject("穿过海底关卡需要通行证。")
	var cell := _cell(command)
	var moved: bool = int(command.map_id)!=automation.position_map or cell!=automation.position_cell
	var paused: String = automation.position_changed(int(command.map_id),cell,bool(command.get("map_changed",false)),"project" if _project_position else "party" if _following_party and not _party_move_evidence.is_empty() else "project" if _following_party else "report",_party_move_evidence)
	if moved:_emit({"type":"position","map_id":int(command.map_id),"cell":[cell.x,cell.y],"client":str(command.get("client",""))})
	if helper_stage!=quest_helper.navigation_key(self):_publish()
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
	return _save_profile_boundary()

func _save_profile_boundary(checkpoint:Dictionary={}) -> bool:
	if save_path.is_empty():
		quest_save_serial+=1
		return true
	var payload := JSON.stringify(session.snapshot())
	if payload==last_saved_payload:
		quest_save_serial+=1
		if not checkpoint.is_empty():checkpoint.timer.mark_followup_checkpoint_saved(self,checkpoint,payload)
		return true
	if not session.save_game(save_path):return false
	last_saved_payload = payload
	quest_save_serial+=1
	return true

func publish() -> void:
	_publish()

func _publish() -> void:
	original_quests.refresh_npc_state()
	_npc_state_published_version=original_quests.npc_state.version
	rev += 1
	var profile: Dictionary = session.snapshot()
	var storage: Array = profile.get("pet_storage",[])
	profile.erase("pet_storage")
	var storage_json := JSON.stringify(storage)
	if storage_json!=_storage_json:
		_storage_json = storage_json
		_emit({"type":"pet_storage","rev":rev,"pet_storage":storage})
	_emit({"type":"profile","rev":rev,"profile":profile,"derived":_derived(),"options":_options(),"capabilities":_capabilities()})

func emit_event(message: Dictionary) -> void:
	_emit(message)

func _emit(message: Dictionary) -> void:
	_dispatch_boundary_depth+=1
	message.v = PROTOCOL
	var queued:Dictionary=message
	var source:Dictionary=_quest_source_call
	if not source.is_empty() and source.get("saved",false) and not source.get("position_claimed",false) and message.get("type")=="position" and message.get("client","")=="":
		var warp:Array=source.get("warp",[])
		if warp.size()==3 and quest_auto.Motion.same_integer(message.get("map_id"),warp[0]) and quest_auto.Motion.cell(message.get("cell"))==[warp[1],warp[2]]:
			source.position_claimed=true
			# Prepare authority before later snapshots are constructed. Delivery
			# still owns the final capability check and the original plain event.
			var packet:Dictionary=quest_auto.source_position_packet(self,source,message)
			queued={"_source_position":source,"message":message,"packet":packet}
	if _depth > 0:
		_queue.append(queued)
		_dispatch_boundary_depth-=1
		_complete_dispatch_barrier()
		return
	_deliver_event(queued)
	_dispatch_boundary_depth-=1
	_complete_dispatch_barrier()

func _deliver_event(queued:Dictionary)->void:
	_observer_depth+=1
	_dispatch_dirty=true
	var message:Dictionary=queued
	if queued.has("_source_position"):
		var source:Dictionary=queued._source_position
		message=queued.message
		var packet:Dictionary=queued.packet
		if quest_auto.source_position_current(self,source,packet):message=packet
	# Observers are independent manual calls, even at depth zero. They must
	# never inherit a save capability, suppress a manual tail or steal a Warp.
	var source_scope:Dictionary=_quest_source_call
	var source_internal:bool=quest_auto.internal
	if not source_scope.is_empty():quest_auto.internal=false
	_quest_source_call={}
	event.emit(message)
	_quest_source_call=source_scope
	if not source_scope.is_empty():quest_auto.internal=source_internal
	_observer_depth-=1
	_complete_dispatch_barrier()

func _flush() -> void:
	if _depth > 0:return
	_flush_depth+=1
	while not _queue.is_empty():
		_deliver_event(_queue.pop_front())
	_flush_depth-=1
	_complete_dispatch_barrier()

func _complete_dispatch_barrier()->void:
	if _dispatch_boundary_depth!=0 or _depth!=0 or _observer_depth!=0 or _flush_depth!=0 or not _queue.is_empty() or not _dispatch_dirty:return
	_dispatch_dirty=false
	_dispatch_epoch+=1

func continuation_dispatch_checkpoint()->Dictionary:
	return {"epoch":_dispatch_epoch,"generation":_normal_process_generation}

func continuation_dispatch_ready(checkpoint:Dictionary)->bool:
	# Internal checkpoint only; not a wire capability or success certificate.
	if not checkpoint.get("epoch") is int or not checkpoint.get("generation") is int:return false
	return _process_depth==1 and _dispatch_boundary_depth==1 and _observer_depth==0 and _flush_depth==0 and _depth==1 and _queue.is_empty() and _normal_process_generation>checkpoint.generation and _normal_process_entry_epoch>checkpoint.epoch

## Called only by the runner's dormant internal source entry points.
func call_quest_source(frame,proposal:Dictionary,choice:Dictionary={}) -> Dictionary:
	if not _quest_source_call.is_empty() or not quest_auto.source_live(frame) or not quest_auto.internal:return _reject("原服务调用身份已失效。")
	if frame.owner_profile!={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}:return _reject("原服务所属角色已经变化。")
	var checked:Dictionary=quest_auto.Source.validate_step(self,2,proposal)
	if not checked.ok or proposal!=quest_auto.step:return _reject("原服务步骤已变化。")
	if not choice.is_empty() and not frame.claim_choice(choice):return _reject("原服务回复未绑定当前公开页。")
	if choice.is_empty() and (not frame.page.is_empty() or not frame.consumed.is_empty()):return _reject("原服务窗口不可重开。")
	var call=frame.begin_call(quest_auto.identity.checkpoint(),quest_auto.connection)
	if call==null:return _reject("原服务调用已在进行。")
	var source:Dictionary={"frame":frame,"call":call,"step":proposal.duplicate(true),"identity":quest_auto.identity.checkpoint(),"connection":quest_auto.connection,"character_id":str(session._profile.get("character_id","")),"profile_id":str(session._profile.get("profile_id","")),"saved":false,"origin":{"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]}}
	_quest_source_call=source
	var reply:Dictionary=original_quests.talk(self,str(proposal.npc_id)) if choice.is_empty() else original_quests.choose(self,str(choice.token),str(choice.choice),str(choice.get("text","")))
	frame.close_save_window(call)
	if not reply.get("ok",false):frame.cancel()
	if reply.get("dialogue") is Dictionary:
		frame.receive_page(call,reply.dialogue,str(original_quests.pending.get("token","")))
	var result:Dictionary=frame.complete_call(call,quest_auto.identity.checkpoint(),quest_auto.connection)
	result.continued=quest_source_call_live(source)
	result.warp=source.has("warp")
	result.durable=bool(source.get("durable",false))
	result.candidate_sha=str(source.get("candidate_sha",""))
	_quest_source_call={}
	# Clean only pages issued by this frame, never a newer manual window.
	if not result.continued and frame.owns_pending(str(original_quests.pending.get("token",""))):original_quests.pending={}
	reply.source_commit=result
	return reply

func capture_quest_source_call(npc_id:String)->Dictionary:
	return _quest_source_call if not _quest_source_call.is_empty() and str(_quest_source_call.step.get("npc_id",""))==npc_id else {}

func quest_source_call_live(source:Dictionary)->bool:
	return not source.is_empty() and quest_auto.source_live(source.frame) and source.frame.matches(source.identity,int(source.connection)) and str(session._profile.get("character_id",""))==str(source.character_id) and str(session._profile.get("profile_id",""))==str(source.profile_id)

func save_quest_source_transaction(npc_id:String,branch:Dictionary,phase:String)->bool:
	if _quest_source_call.is_empty():return save()
	var source:Dictionary=capture_quest_source_call(npc_id)
	if source.is_empty() or not quest_source_call_live(source) or source.saved or not source.frame.can_save(source.call) or not quest_auto.Source.transaction(source.step,branch,phase):return false
	# Snapshot the actual transaction candidate at its one synchronous save
	# boundary. Generic observer saves cannot update this record.
	var candidate:String=JSON.stringify(session.snapshot())
	if not _save_profile_boundary():return false
	source.saved=true
	source.durable=not save_path.is_empty()
	source.candidate_sha=candidate.sha256_text()
	source.frame.record_saved(source.call,quest_save_serial)
	var raw:String=str(branch.actions.get("Warp",""))
	if not raw.is_empty():
		var parts:PackedStringArray=raw.split(",")
		source.warp=[int(parts[0]),int(parts[1]),int(parts[2])]
	return true

func _derived() -> Dictionary:
	# battle_pets: pet_id -> reason for the open battle's participants, which
	# release, store, deploy and ride refuse until it ends.
	_published_battle_pets = session.battle_pets()
	return {"quest_npcs":original_quests.npc_state.snapshot(),"stationary":stationary.snapshot(self),"no_random_encounters":bool(session._profile.get("no_random_encounters",false)),"quest_auto":quest_auto.snapshot(self),"quest_helper":quest_helper.snapshot(self),"has_travel_pass":session.has_travel_pass(),"can_fight_boss":session.can_fight_boss(),"effective_stats":session.effective_player_stats(),"gm_pending":not session._pending.is_empty(),"battle_pets":_published_battle_pets.duplicate(),"pet_capacity":GameSession.PET_CAPACITY,"max_level":GameSession.MAX_LEVEL}

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

# Exact original ItemShop adapter, separate from quest REQUEST/ACCEPT.
# Opaque transport epochs only, no backend/session backreference. Never serialized.
var _fee_bindings:Dictionary={}
func fee_attach(connection:int)->RefCounted:
	fee_detach(connection)
	var binding=RefCounted.new()
	_fee_bindings[connection]=binding
	return binding
func fee_detach(connection:int)->void:
	var binding=_fee_bindings.get(connection)
	var page:Dictionary=original_quests.pending
	if binding!=null and page.get("phase","")=="permit_shop" and page.get("permit_connection")==connection and page.get("permit_binding")==binding:
		original_quests.pending={}
	_fee_bindings.erase(connection)
const RequiredFee=preload("res://server/required_fee_transaction.gd")
func _permit_entry_refusal(command:Dictionary)->Dictionary:
	if str(command.get("type","")) not in ["permit_shop_open","permit_shop_choose"]:return {}
	var reason:String=RequiredFee.entry_error(self,command)
	return {} if reason.is_empty() else {"ok":false,"reason":reason,"seq":command.get("seq",0),"type":"rejected"}
func _cmd_buy_travel_pass(_command:Dictionary)->Dictionary:
	return _reject("请到原售证商人处确认购买；旧无人物购买命令已停用。")
func _cmd_permit_shop_open(command:Dictionary)->Dictionary:
	if not command.get("source_id") is String:return _reject("无效的原售证来源。")
	return RequiredFee.open_shop(self,command.source_id,command)
func _cmd_permit_shop_choose(command:Dictionary)->Dictionary:
	if not command.get("token") is String or not command.get("choice") is String:return _reject("无效的原售证确认。")
	return RequiredFee.choose_shop(self,command.token,command.choice,command)
## Dormant Start journal seam. No production caller or purchase authority.
func _begin_fee_start_journal_frame(candidate:Variant)->Dictionary:
	return _fee_start_journal_writer.begin(self,candidate)

func _persist_fee_start_journal_pair(handle:Variant)->Dictionary:
	return _fee_start_journal_writer.persist(self,handle)

func _end_fee_start_journal_frame(handle:Variant)->void:
	_fee_start_journal_writer.end(self,handle)

## Internal-only frame factory. It is deliberately not a command or RPC. The
## caller still has to prove the original route/offer facts before preparing
## this candidate; this method only freezes the exact in-process writer owner.
func _begin_fee_attempt_writer_frame(candidate:Dictionary)->Dictionary:
	if _quest_auto_stop_operation_call!=null:return {}
	if _depth<=0 or save_path.is_empty() or _fee_attempt_writer_call!=null or _fee_attempt_writer_executing:return {}
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return {}
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return {}
	if battle_open or not session._pending.is_empty() or not session._loot_settlement.is_empty() or stationary.running or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return {}
	if not quest_auto.running or not quest_auto.internal or not quest_auto.identity is Object:return {}
	var run_id:String=str(quest_auto.identity.run_id)
	if run_id.is_empty() or not candidate.has("quest_auto_fee_lifecycle") or not session._valid_profile(candidate):return {}
	var previous:Variant=session._profile.get("quest_auto_fee_lifecycle",null)
	var journal:Variant=candidate.get("quest_auto_fee_lifecycle",null)
	if not FeeAttemptJournal.valid(previous) or not FeeAttemptJournal.valid(journal):return {}
	if previous.owner!={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}:return {}
	if previous.current.run_id!=run_id or previous.current.run_status!="active":return {}
	var purchase:Dictionary=journal.current.purchase
	if journal.current.run_id!=run_id or journal.current.run_status!="active" or purchase.state!="attempting":return {}
	var transition:Dictionary=FeeAttemptJournal.begin_attempt(previous,run_id,purchase.attempt_id,purchase.source_id,purchase.offer_id,purchase.item_id,purchase.amount,purchase.balance_before)
	if not transition.get("ok",false) or transition.get("candidate")!=journal:return {}
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	if journal.owner!=owner:return {}
	var expected:Dictionary=session._profile.duplicate(true)
	expected["quest_auto_fee_lifecycle"]=journal.duplicate(true)
	if candidate!=expected:return {}
	var cache_bytes:PackedByteArray=last_saved_payload.to_utf8_buffer()
	if cache_bytes.is_empty() or JSON.stringify(session._profile)!=last_saved_payload:return {}
	var primary_before:Dictionary=session._read_fee_attempt_file(save_path,cache_bytes)
	if not primary_before.get("ok",false) or not primary_before.get("exists",false) or not primary_before.get("matches",false):return {}
	var backup_before:Dictionary=session._read_fee_attempt_file(save_path+".bak",PackedByteArray())
	var temporary_before:Dictionary=session._read_fee_attempt_file(save_path+".tmp",PackedByteArray())
	if not backup_before.get("ok",false) or not temporary_before.get("ok",false):return {}
	var candidate_bytes:PackedByteArray=JSON.stringify(candidate).to_utf8_buffer()
	if candidate_bytes==cache_bytes or (backup_before.exists and candidate_bytes==backup_before.bytes):return {}
	var call:=RefCounted.new()
	_fee_attempt_writer_call=call
	var refs:Dictionary={
		"session":weakref(session),"profile":session._profile,"pending":session._pending,
		"loot_settlement":session._loot_settlement,"page":original_quests.pending,
		"quest_auto":weakref(quest_auto),"identity":weakref(quest_auto.identity),"automation":weakref(automation),
		"stationary":weakref(stationary),"original_quests":weakref(original_quests),"battle":weakref(battle)
	}
	var values:Dictionary={
		"profile":session._profile.duplicate(true),"pending":session._pending.duplicate(true),
		"loot_settlement":session._loot_settlement.duplicate(true),"page":original_quests.pending.duplicate(true),
		"candidate":candidate.duplicate(true),"owner":owner.duplicate(true),
		"cache":last_saved_payload,"serial_before":quest_save_serial,
		"auto_identity":quest_auto.identity.checkpoint(),"auto_client":quest_auto.client,"auto_connection":quest_auto.connection,
		"auto_running":quest_auto.running,"auto_internal":quest_auto.internal,"auto_detached":quest_auto.detached,"auto_phase":quest_auto.phase,
		"auto_token":automation.start_lifetime,"automation_running":automation.running,"hunt_running":automation.hunt_running,"flow_active":automation.flow_active(),"compact":automation.compact_active,
		"stationary_running":stationary.running,"battle_open":battle_open,
		"depth":_depth,"dispatch_boundary_depth":_dispatch_boundary_depth,"observer_depth":_observer_depth,"flush_depth":_flush_depth,"dispatch_epoch":_dispatch_epoch,
		"primary_before":primary_before.bytes,"backup_before_exists":backup_before.exists,"backup_before":backup_before.bytes,
		"temporary_before_exists":temporary_before.exists,"temporary_before":temporary_before.bytes,
		"candidate_bytes":candidate_bytes
	}
	_fee_attempt_writer_snapshot={"call":call,"refs":refs,"values":values,"path":save_path,"account_name":account_name,"expected_serial":quest_save_serial,"phase":"prepared"}
	return {"call":call}

func _fee_attempt_writer_frame_current(frame:Dictionary)->bool:
	if _quest_auto_stop_operation_call!=null:return false
	if frame.is_empty() or not is_same(_fee_attempt_writer_call,frame.get("call")):return false
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return false
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return false
	var refs:Dictionary=frame.refs
	var v:Dictionary=frame.values
	if not is_same(refs.session.get_ref(),session) or not is_same(refs.quest_auto.get_ref(),quest_auto) or not is_same(refs.identity.get_ref(),quest_auto.identity) or not is_same(refs.automation.get_ref(),automation) or not is_same(refs.stationary.get_ref(),stationary) or not is_same(refs.original_quests.get_ref(),original_quests) or not is_same(refs.battle.get_ref(),battle):return false
	if save_path!=frame.path or account_name!=frame.account_name:return false
	if quest_auto.identity.checkpoint()!=v.auto_identity or quest_auto.client!=v.auto_client or quest_auto.connection!=v.auto_connection or quest_auto.running!=v.auto_running or quest_auto.internal!=v.auto_internal or quest_auto.detached!=v.auto_detached or quest_auto.phase!=v.auto_phase:return false
	if not is_same(automation.start_lifetime,v.auto_token) or automation.running!=v.automation_running or automation.hunt_running!=v.hunt_running or automation.flow_active()!=v.flow_active or automation.compact_active!=v.compact:return false
	if stationary.running!=v.stationary_running or battle_open!=v.battle_open:return false
	if _depth!=v.depth or _dispatch_boundary_depth!=v.dispatch_boundary_depth or _observer_depth!=v.observer_depth or _flush_depth!=v.flush_depth or _dispatch_epoch!=v.dispatch_epoch:return false
	if not is_same(session._profile,refs.profile) or session._profile!=v.profile:return false
	if not is_same(session._pending,refs.pending) or session._pending!=v.pending:return false
	if not is_same(session._loot_settlement,refs.loot_settlement) or session._loot_settlement!=v.loot_settlement or not session._loot_settlement.is_empty():return false
	if not is_same(original_quests.pending,refs.page) or original_quests.pending!=v.page:return false
	if str(session._profile.get("profile_id",""))!=str(v.owner.profile_id) or str(session._profile.get("character_id",""))!=str(v.owner.character_id):return false
	return last_saved_payload==v.cache and quest_save_serial==frame.expected_serial

func _fee_attempt_file_same(row:Dictionary,exists:bool,bytes:PackedByteArray)->bool:
	if not row.get("ok",false) or row.get("exists",false)!=exists:return false
	return not exists or row.get("bytes") is PackedByteArray and row.bytes==bytes

func _end_fee_attempt_writer_frame(handle:Dictionary)->void:
	if handle.size()!=1 or not handle.has("call") or not is_same(_fee_attempt_writer_call,handle.call):return
	_fee_attempt_writer_call=null
	_fee_attempt_writer_snapshot={}
	_fee_attempt_writer_executing=false

## Two direct Session raw-candidate writes. Serial advances once when W1 is
## installed in memory; W2 is a second physical write and never advances it.
func _persist_fee_attempt_fence(handle:Dictionary)->Dictionary:
	var outcome:Dictionary={"ok":false,"persisted":"unknown","stage":"invalid_handle"}
	if handle.size()!=1 or not handle.has("call") or not is_same(_fee_attempt_writer_call,handle.get("call")):return outcome
	if _fee_attempt_writer_executing:return {"ok":false,"persisted":"unknown","stage":"already_executing"}
	if _fee_attempt_writer_snapshot.is_empty() or not is_same(handle.call,_fee_attempt_writer_snapshot.call):return outcome
	_fee_attempt_writer_executing=true
	var frame:Dictionary=_fee_attempt_writer_snapshot
	var v:Dictionary=frame.values
	var refs:Dictionary=frame.refs
	if not _fee_attempt_writer_frame_current(frame):
		_end_fee_attempt_writer_frame(handle)
		return {"ok":false,"persisted":false,"stage":"owner_or_cas_rejected_before_w1"}
	var primary_pre:Dictionary=session._read_fee_attempt_file(frame.path,v.cache.to_utf8_buffer())
	var backup_pre:Dictionary=session._read_fee_attempt_file(frame.path+".bak",PackedByteArray())
	var temporary_pre:Dictionary=session._read_fee_attempt_file(frame.path+".tmp",PackedByteArray())
	if not _fee_attempt_file_same(primary_pre,true,v.primary_before) or not _fee_attempt_file_same(backup_pre,v.backup_before_exists,v.backup_before) or not _fee_attempt_file_same(temporary_pre,v.temporary_before_exists,v.temporary_before):
		_end_fee_attempt_writer_frame(handle)
		return {"ok":false,"persisted":"unknown","stage":"disk_changed_before_w1"}
	if not _fee_attempt_writer_frame_current(frame):
		_end_fee_attempt_writer_frame(handle)
		return {"ok":false,"persisted":false,"stage":"owner_or_cas_changed_before_w1"}
	var candidate:Dictionary=v.candidate
	var candidate_text:String=JSON.stringify(candidate)
	var candidate_bytes:PackedByteArray=v.candidate_bytes
	var primary_old:PackedByteArray=v.primary_before
	var s0:int=v.serial_before
	if quest_save_serial!=s0:
		_end_fee_attempt_writer_frame(handle)
		return {"ok":false,"persisted":false,"stage":"serial_changed_before_w1"}
	var first:Dictionary=session._write_fee_attempt_candidate_once(candidate,frame.path,refs.profile,v.profile)
	var p1:Dictionary=first.get("primary",{})
	var b1:Dictionary=first.get("backup",{})
	var t1:Dictionary=first.get("temporary",{})
	var primary_is_candidate:bool=p1.get("ok",false) and p1.get("exists",false) and p1.get("matches",false)
	if primary_is_candidate:
		if not _fee_attempt_writer_frame_current(frame):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"primary_matches":true,"stage":"w1_landed_but_frame_changed_before_install"}
		var installed:Dictionary=candidate.duplicate(true)
		session._profile=installed
		last_saved_payload=candidate_text
		quest_save_serial=s0+1
		frame.refs.profile=session._profile
		frame.values.profile=session._profile.duplicate(true)
		frame.values.cache=candidate_text
		frame.expected_serial=s0+1
		frame.phase="w1_installed"
		if not bool(first.get("writer_return",false)):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"stage":"w1_wrapper_false_after_primary_readback","w1_calls":1,"serial_before":s0,"serial_after_w1":s0+1}
		if not _fee_attempt_file_same(b1,true,primary_old) or not _fee_attempt_file_same(t1,false,PackedByteArray()):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"stage":"w1_backup_or_tmp_mismatch","w1_calls":1,"serial_before":s0,"serial_after_w1":s0+1}
		if not _fee_attempt_writer_frame_current(frame):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"stage":"w1_post_install_cas_changed","w1_calls":1,"serial_before":s0,"serial_after_w1":s0+1}
		var p_before_w2:Dictionary=session._read_fee_attempt_file(frame.path,candidate_bytes)
		var b_before_w2:Dictionary=session._read_fee_attempt_file(frame.path+".bak",PackedByteArray())
		var t_before_w2:Dictionary=session._read_fee_attempt_file(frame.path+".tmp",PackedByteArray())
		if not p_before_w2.get("ok",false) or not p_before_w2.get("exists",false) or not p_before_w2.get("matches",false) or not _fee_attempt_file_same(b_before_w2,true,b1.bytes) or not _fee_attempt_file_same(t_before_w2,false,PackedByteArray()):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"stage":"disk_changed_before_w2","w1_calls":1,"serial_before":s0,"serial_after_w1":s0+1}
		if quest_save_serial!=s0+1 or not _fee_attempt_writer_frame_current(frame):
			_end_fee_attempt_writer_frame(handle)
			return {"ok":false,"persisted":true,"stage":"serial_or_owner_changed_before_w2","w1_calls":1,"serial_before":s0,"serial_after_w1":s0+1}
		var second:Dictionary=session._write_fee_attempt_candidate_once(candidate,frame.path,refs.profile,v.profile)
		var p2:Dictionary=second.get("primary",{})
		var b2:Dictionary=second.get("backup",{})
		var t2:Dictionary=second.get("temporary",{})
		var both_exact:bool=p2.get("ok",false) and p2.get("exists",false) and p2.get("matches",false) and b2.get("ok",false) and b2.get("exists",false) and b2.get("matches",false) and t2.get("ok",false) and not t2.get("exists",true)
		var after_current:bool=quest_save_serial==s0+1 and _fee_attempt_writer_frame_current(frame)
		_end_fee_attempt_writer_frame(handle)
		return {"ok":bool(second.get("writer_return",false)) and both_exact and after_current,"persisted":true,"primary_matches":p2.get("matches",false),"backup_matches":b2.get("matches",false),"writer_return":second.get("writer_return",false),"stage":"pair_verified" if bool(second.get("writer_return",false)) and both_exact and after_current else "w2_incomplete_or_owner_changed","w1_calls":1,"w2_calls":1,"serial_before":s0,"serial_after_w1":s0+1,"serial_after_w2":quest_save_serial}
	var p_known:bool=p1.get("ok",false) and p1.get("exists",false)
	var b_known:bool=b1.get("ok",false) and (not b1.get("exists",false) or b1.get("bytes") is PackedByteArray)
	var p_has_candidate:bool=p1.get("matches",false)
	var b_has_candidate:bool=b1.get("exists",false) and b1.get("matches",false)
	if p_known and b_known and not p_has_candidate and not b_has_candidate and not bool(first.get("writer_return",false)):
		_end_fee_attempt_writer_frame(handle)
		return {"ok":false,"persisted":false,"stage":"w1_candidate_absent_from_primary_and_backup","w1_calls":1,"serial_before":s0,"serial_after_w1":quest_save_serial,"primary":p1,"backup":b1,"temporary":t1}
	_end_fee_attempt_writer_frame(handle)
	return {"ok":false,"persisted":"unknown","stage":"w1_io_or_readback_ambiguous","w1_calls":1,"serial_before":s0,"serial_after_w1":quest_save_serial,"primary":p1,"backup":b1,"temporary":t1}

## Closed-pair candidate. This is internal-only and has no Stop/RPC caller.
## stopped_identity is captured before the caller invalidates the old quest frame;
## this factory accepts only that exact one-revision retired identity.
func _close_and_retire_stopped_fee_run(stopped_identity:Dictionary,stop_handle:Dictionary)->Dictionary:
	var result:Dictionary={"ok":false,"applicable":false,"stopped_in_memory":true,"lifecycle":"legacy","profile_close":{"stage":"not_applicable","primary_closed":"unknown","backup_closed":"unknown","profile_pair_closed":"unknown","serial_before":quest_save_serial,"serial_after_w1":"unknown","serial_after_w2":"unknown"},"sidecar_retire":{"stage":"not_attempted","operation_attempted":false,"operation_completed":false,"target_state":"unknown","sidecar_exists":"unknown","temporary_clear":"unknown"}}
	if not _quest_auto_stop_operation_current(stop_handle):
		result.merge({"ok":false,"stage":"stop_owner_stale","lifecycle":"unknown"},true)
		return result
	if session==null:
		result.merge({"ok":false,"stage":"session_missing","lifecycle":"unknown"},true)
		return result
	if not session._profile.has("quest_auto_fee_lifecycle"):
		# This helper is reached only after stop() admitted a journal-bearing
		# profile. Its disappearance after the operation claim is stale/unknown,
		# never a legacy-success fallback.
		result.merge({"ok":false,"applicable":true,"lifecycle":"unknown","stage":"journal_missing_after_claim"},true)
		return result
	result.applicable=true
	result.lifecycle="unknown"
	var previous:Variant=session._profile.get("quest_auto_fee_lifecycle",null)
	if not FeeAttemptJournal.valid(previous):
		result.stage="journal_invalid_preserved"
		return result
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	if previous.owner!=owner or previous.current.run_id!=stopped_identity.get("run_id",null):
		result.stage="journal_owner_or_run_mismatch_preserved"
		return result
	if previous.current.run_status in ["active","closed"]:
		var closed:Dictionary=FeeAttemptJournal.close_run(previous,str(stopped_identity.run_id))
		var close_transition_ok:Variant=closed.get("ok",null)
		if not close_transition_ok is bool:
			result.stage="close_transition_refused"
			return result
		var close_transition_ok_bool:bool=close_transition_ok
		if not close_transition_ok_bool:
			result.stage="close_transition_refused"
			return result
		var candidate_value:Variant=closed.get("candidate",null)
		if not candidate_value is Dictionary:
			result.stage="close_candidate_invalid"
			return result
		var closed_journal:Dictionary=candidate_value
		var expected_profile:Dictionary=session._profile.duplicate(true)
		expected_profile["quest_auto_fee_lifecycle"]=closed_journal.duplicate(true)
		if not session._valid_profile(expected_profile):
			result.stage="close_candidate_profile_invalid"
			return result
		var close_handle:Dictionary=_begin_fee_attempt_close_frame(stopped_identity,expected_profile,stop_handle)
		if close_handle.is_empty():
			result.stage="close_frame_refused"
			return result
		var close_fact:Dictionary=_persist_fee_attempt_close_pair(close_handle)
		var closed_pair:Variant=close_fact.get("profile_pair_closed","unknown")
		var primary:Variant=close_fact.get("primary_closed","unknown")
		var backup:Variant=close_fact.get("backup_closed","unknown")
		var close_ok:Variant=close_fact.get("ok",null)
		var writer1:Variant=close_fact.get("w1_writer_return","unknown")
		var writer2:Variant=close_fact.get("w2_writer_return","unknown")
		var close_verified:bool=false
		var tmp_state:Variant=close_fact.get("temporary",null)
		if close_ok is bool and closed_pair is bool and primary is bool and backup is bool and writer1 is bool and writer2 is bool and tmp_state is String:
			var close_ok_bool:bool=close_ok
			var closed_pair_bool:bool=closed_pair
			var primary_bool:bool=primary
			var backup_bool:bool=backup
			var writer1_bool:bool=writer1
			var writer2_bool:bool=writer2
			var tmp_state_string:String=tmp_state
			close_verified=close_ok_bool and closed_pair_bool and primary_bool and backup_bool and writer1_bool and writer2_bool and tmp_state_string=="absent"
		result.profile_close={"stage":str(close_fact.get("stage","unknown")),"primary_closed":primary,"backup_closed":backup,"profile_pair_closed":closed_pair,"serial_before":close_fact.get("serial_before","unknown"),"serial_after_w1":close_fact.get("serial_after_w1","unknown"),"serial_after_w2":close_fact.get("serial_after_w2","unknown"),"w1_writer_return":writer1,"w2_writer_return":writer2}
		if not close_verified:
			result.stage="profile_close_partial_or_unknown"
			return result
		result.lifecycle="profile_closed_sidecar_pending"
	else:
		result.stage="journal_state_unsupported_preserved"
		return result
	var retire_handle:Dictionary=_begin_fee_resume_closed_retire_frame(stop_handle)
	var retire_begin_ok:Variant=retire_handle.get("ok",null)
	var retire_begin_ok_bool:bool=false
	if retire_begin_ok is bool:
		retire_begin_ok_bool=retire_begin_ok
	if not retire_begin_ok_bool:
		var retire_stage:String=str(retire_handle.get("stage","unknown"))
		result.sidecar_retire={"stage":retire_stage,"operation_attempted":false,"operation_completed":false,"target_state":"unknown","sidecar_exists":"unknown","temporary_clear":"unknown","profile_pair_state":retire_handle.get("profile_pair_state","unknown"),"sidecar_preserved":retire_stage=="present_sidecar_unattributed"}
		result.stage="sidecar_preserved_unattributed" if retire_stage=="present_sidecar_unattributed" else "sidecar_retire_begin_failed"
		result.lifecycle="profile_closed_sidecar_partial_or_unknown"
		return result
	var retire_fact:Dictionary=_commit_fee_resume_closed_retire_frame({"call":retire_handle.get("call")})
	var retire_ok_value:Variant=retire_fact.get("ok",null)
	var persisted:Variant=retire_fact.get("sidecar_persisted","unknown")
	var tmp_clear:Variant=retire_fact.get("temporary_clear","unknown")
	var operation_completed:Variant=retire_fact.get("operation_completed","unknown")
	var retire_ok:bool=false
	var pair_state:Variant=retire_fact.get("profile_pair_state",null)
	if retire_ok_value is bool and persisted is bool and tmp_clear is bool and operation_completed is bool and pair_state is String:
		var retire_ok_bool:bool=retire_ok_value
		var persisted_bool:bool=persisted
		var tmp_clear_bool:bool=tmp_clear
		var operation_completed_bool:bool=operation_completed
		var pair_state_string:String=pair_state
		retire_ok=retire_ok_bool and persisted_bool and tmp_clear_bool and operation_completed_bool and pair_state_string=="matches"
	result.sidecar_retire={"stage":str(retire_fact.get("stage","unknown")),"operation_attempted":retire_fact.get("operation_attempted","unknown"),"operation_completed":operation_completed,"target_state":retire_fact.get("target_state","unknown"),"sidecar_persisted":persisted,"sidecar_exists":retire_fact.get("sidecar_exists","unknown"),"temporary_clear":tmp_clear,"profile_pair_state":retire_fact.get("profile_pair_state","unknown")}
	result.ok=retire_ok
	result.lifecycle="closed_and_retired" if retire_ok else "profile_closed_sidecar_partial_or_unknown"
	result.stage="closed_and_retired" if retire_ok else "sidecar_retire_partial_or_unknown"
	return result

func _fee_attempt_close_read_snapshot(retired_identity:Dictionary,candidate:Dictionary,stop_handle:Dictionary={})->Dictionary:
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return {}
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return {}
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return {}
	if quest_auto.running or quest_auto.identity.checkpoint()!=retired_identity or quest_auto.source_frame!=null:return {}
	if battle_open or not session._pending.is_empty() or not session._loot_settlement.is_empty() or stationary.running or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return {}
	if JSON.stringify(session._profile)!=last_saved_payload:return {}
	var profile:Dictionary=session._profile
	return {
		"session":session,"profile_ref":session._profile,"profile":profile.duplicate(true),
		"pending_ref":session._pending,"pending":session._pending.duplicate(true),
		"loot_ref":session._loot_settlement,"loot":session._loot_settlement.duplicate(true),
		"quest_auto":quest_auto,"identity_ref":quest_auto.identity,"identity":quest_auto.identity.checkpoint(),
		"retired_identity":retired_identity.duplicate(true),"source_frame":quest_auto.source_frame,
		"automation":automation,"automation_running":automation.running,"hunt_running":automation.hunt_running,
		"flow_active":automation.flow_active(),"stationary":stationary,"stationary_running":stationary.running,
		"original_quests":original_quests,"page_ref":original_quests.pending,"page":original_quests.pending.duplicate(true),
		"battle":battle,"battle_open":battle_open,"owner":{"profile_id":str(profile.get("profile_id","")),"character_id":str(profile.get("character_id",""))},
		"path":save_path,"account_name":account_name,"cache":last_saved_payload,"serial":quest_save_serial,
		"candidate_ref":candidate,"candidate":candidate.duplicate(true),
		"depth":_depth,"dispatch_boundary_depth":_dispatch_boundary_depth,"observer_depth":_observer_depth,
		"flush_depth":_flush_depth,"dispatch_epoch":_dispatch_epoch,
		"stop_call":stop_handle.get("call",null),"stop_owner":stop_handle.get("owner",null)
	}

func _fee_attempt_close_read_snapshot_current(snapshot:Dictionary)->bool:
	if snapshot.is_empty() or _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return false
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current({"call":snapshot.get("stop_call"),"owner":snapshot.get("stop_owner")}):return false
	if _quest_auto_stop_operation_call==null and snapshot.get("stop_call",null)!=null:return false
	# These are independent claims; this close frame does not make them disappear.
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return false
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return false
	if not is_same(session,snapshot.get("session")) or not is_same(session._profile,snapshot.get("profile_ref")) or session._profile!=snapshot.get("profile",{}):return false
	if not is_same(session._pending,snapshot.get("pending_ref")) or session._pending!=snapshot.get("pending",{}):return false
	if not is_same(session._loot_settlement,snapshot.get("loot_ref")) or session._loot_settlement!=snapshot.get("loot",{}) or not session._loot_settlement.is_empty():return false
	if not is_same(quest_auto,snapshot.get("quest_auto")) or not is_same(quest_auto.identity,snapshot.get("identity_ref")):return false
	if quest_auto.identity.checkpoint()!=snapshot.get("retired_identity",{}) or quest_auto.running or quest_auto.source_frame!=snapshot.get("source_frame"):return false
	if not is_same(automation,snapshot.get("automation")) or automation.running!=snapshot.get("automation_running",true) or automation.hunt_running!=snapshot.get("hunt_running",true) or automation.flow_active()!=snapshot.get("flow_active",true):return false
	if not is_same(stationary,snapshot.get("stationary")) or stationary.running!=snapshot.get("stationary_running",true):return false
	if not is_same(original_quests,snapshot.get("original_quests")) or not is_same(original_quests.pending,snapshot.get("page_ref")) or original_quests.pending!=snapshot.get("page",{}):return false
	if not is_same(battle,snapshot.get("battle")) or battle_open!=snapshot.get("battle_open",true) or battle_open:return false
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	if owner!=snapshot.get("owner",{}):return false
	if save_path!=snapshot.get("path") or account_name!=snapshot.get("account_name"):return false
	if last_saved_payload!=snapshot.get("cache") or quest_save_serial!=snapshot.get("serial"):return false
	if _depth!=snapshot.get("depth") or _dispatch_boundary_depth!=snapshot.get("dispatch_boundary_depth") or _observer_depth!=snapshot.get("observer_depth") or _flush_depth!=snapshot.get("flush_depth") or _dispatch_epoch!=snapshot.get("dispatch_epoch"):return false
	var live_candidate:Variant=snapshot.get("candidate_ref",null)
	return live_candidate is Dictionary and live_candidate==snapshot.get("candidate",{})

func _begin_quest_auto_stop_operation(owner_auto:Variant)->Dictionary:
	if _quest_auto_stop_operation_call!=null or not is_same(owner_auto,quest_auto):return {}
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return {}
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return {}
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return {}
	var call:=RefCounted.new()
	_quest_auto_stop_operation_call=call
	_quest_auto_stop_operation_owner=owner_auto
	return {"call":call,"owner":owner_auto}

func _quest_auto_stop_operation_current(handle:Variant)->bool:
	if not handle is Dictionary or handle.size()!=2 or not handle.has("call") or not handle.has("owner"):return false
	var call_value:Variant=handle.get("call",null)
	var owner_value:Variant=handle.get("owner",null)
	if not call_value is RefCounted:return false
	return is_same(_quest_auto_stop_operation_call,call_value) and is_same(_quest_auto_stop_operation_owner,owner_value) and is_same(owner_value,quest_auto)

func _end_quest_auto_stop_operation(handle:Variant)->void:
	# Release only this token. If Backend.quest_auto changed, still release our own
	# claim; never clear a successor call/owner.
	if not handle is Dictionary or handle.size()!=2 or not handle.has("call") or not handle.has("owner"):return
	if not is_same(_quest_auto_stop_operation_call,handle.get("call")) or not is_same(_quest_auto_stop_operation_owner,handle.get("owner")):return
	_quest_auto_stop_operation_call=null
	_quest_auto_stop_operation_owner=null

func _begin_fee_attempt_close_frame(stopped_identity:Dictionary,candidate:Dictionary,stop_handle:Dictionary={})->Dictionary:
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current(stop_handle):return {}
	if _quest_auto_stop_operation_call==null and not stop_handle.is_empty():return {}
	if _fee_attempt_close_call!=null or not _fee_attempt_close_frame.is_empty() or _fee_attempt_close_executing:return {}
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return {}
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return {}
	if save_path.is_empty() or not FeeAttemptJournal.exact_keys(stopped_identity,["run_id","step_id","revision"]):return {}
	if not FeeAttemptJournal.opaque(stopped_identity.get("run_id")) or not stopped_identity.get("step_id") is String:return {}
	var old_revision:Variant=stopped_identity.get("revision",null)
	if not FeeAttemptJournal.strict_int(old_revision,0,2147483645):return {}
	var retired_identity:Dictionary=stopped_identity.duplicate(true)
	retired_identity.revision=int(old_revision)+1
	if quest_auto.running or quest_auto.identity.checkpoint()!=retired_identity or quest_auto.source_frame!=null:return {}
	if battle_open or not session._pending.is_empty() or not session._loot_settlement.is_empty() or stationary.running or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return {}
	if JSON.stringify(session._profile)!=last_saved_payload:return {}
	var profile:Dictionary=session._profile
	var owner:Dictionary={"profile_id":str(profile.get("profile_id","")),"character_id":str(profile.get("character_id",""))}
	var previous:Variant=profile.get("quest_auto_fee_lifecycle",null)
	if not FeeAttemptJournal.valid(previous) or previous.current.run_id!=stopped_identity.run_id or previous.owner!=owner:return {}
	var repairing:bool=previous.current.run_status=="closed"
	# Only a live, exact Stop operation may repair its already-closed pair.
	if repairing and (stop_handle.is_empty() or not _quest_auto_stop_operation_current(stop_handle)):return {}
	if not repairing and previous.current.run_status!="active":return {}
	var closed:Dictionary=FeeAttemptJournal.close_run(previous,stopped_identity.run_id)
	if not closed.get("ok",false) or bool(closed.get("already_closed",false))!=repairing:return {}
	var expected_journal:Dictionary=closed.get("candidate",{})
	if not FeeAttemptJournal.valid(expected_journal) or expected_journal.current.run_status!="closed":return {}
	var expected_profile:Dictionary=profile.duplicate(true)
	expected_profile["quest_auto_fee_lifecycle"]=expected_journal.duplicate(true)
	if candidate!=expected_profile or not session._valid_profile(candidate):return {}
	# Freeze all live owner/state/cache/serial facts before the first virtual read.
	var snapshot:Dictionary=_fee_attempt_close_read_snapshot(retired_identity,candidate,stop_handle)
	if snapshot.is_empty() or not _fee_attempt_close_read_snapshot_current(snapshot):return {}
	var path:String=snapshot.path
	var cache_bytes:PackedByteArray=str(snapshot.cache).to_utf8_buffer()
	var primary:Dictionary=snapshot.session._read_fee_attempt_file(path,cache_bytes)
	if not _fee_attempt_close_read_snapshot_current(snapshot):return {}
	var backup:Dictionary=snapshot.session._read_fee_attempt_file(path+".bak",PackedByteArray())
	if not _fee_attempt_close_read_snapshot_current(snapshot):return {}
	var temporary:Dictionary=snapshot.session._read_fee_attempt_file(path+".tmp",PackedByteArray())
	if not _fee_attempt_close_read_snapshot_current(snapshot) or candidate!=snapshot.candidate:return {}
	if _fee_close_file_state(primary,true,cache_bytes)!="matches":return {}
	if not _fee_close_read_complete(backup) or not _fee_close_read_complete(temporary):return {}
	var temporary_exists_value:Variant=temporary.get("exists",null)
	if not (temporary_exists_value is bool):return {}
	var temporary_exists:bool=temporary_exists_value
	if temporary_exists:return {}
	var candidate_bytes:PackedByteArray=JSON.stringify(candidate).to_utf8_buffer()
	# A repair must exactly retain the already-closed primary; a first close must change it.
	if (candidate_bytes==primary.bytes)!=repairing:return {}
	# No callback occurs between the last snapshot check and publishing the claim.
	if not _fee_attempt_close_read_snapshot_current(snapshot):return {}
	var call:=RefCounted.new()
	_fee_attempt_close_call=call
	_fee_attempt_close_frame={
		"call":call,"session":snapshot.session,"profile_ref":snapshot.profile_ref,"profile":snapshot.profile.duplicate(true),
		"quest_auto":snapshot.quest_auto,"identity":snapshot.identity_ref,"automation":snapshot.automation,
		"stationary":snapshot.stationary,"original_quests":snapshot.original_quests,"battle":snapshot.battle,
		"pending_ref":snapshot.pending_ref,"pending":snapshot.pending.duplicate(true),
		"loot_ref":snapshot.loot_ref,"loot":snapshot.loot.duplicate(true),
		"page_ref":snapshot.page_ref,"page":snapshot.page.duplicate(true),"stopped_identity":snapshot.retired_identity.duplicate(true),
		"owner":snapshot.owner.duplicate(true),"run_id":str(snapshot.retired_identity.run_id),"path":snapshot.path,
		"account_name":snapshot.account_name,"cache":snapshot.cache,"serial_before":snapshot.serial,
		"expected_serial":snapshot.serial,"candidate":snapshot.candidate.duplicate(true),
		"candidate_bytes":candidate_bytes,"primary_before":primary.bytes.duplicate(),
		"backup_before_exists":backup.get("exists",false),"backup_before":backup.get("bytes",PackedByteArray()).duplicate(),
		"temporary_before_exists":temporary.get("exists",false),"temporary_before":temporary.get("bytes",PackedByteArray()).duplicate(),
		"depth":snapshot.depth,"dispatch_boundary_depth":snapshot.dispatch_boundary_depth,
		"observer_depth":snapshot.observer_depth,"flush_depth":snapshot.flush_depth,"dispatch_epoch":snapshot.dispatch_epoch,
		"phase":"prepared","repairing":repairing,"stop_call":snapshot.get("stop_call",null),"stop_owner":snapshot.get("stop_owner",null)
	}
	return {"call":call}

func _fee_attempt_close_frame_current(frame:Dictionary)->bool:
	if _quest_auto_stop_operation_call!=null and not _quest_auto_stop_operation_current({"call":frame.get("stop_call"),"owner":frame.get("stop_owner")}):return false
	if _quest_auto_stop_operation_call==null and frame.get("stop_call",null)!=null:return false
	if frame.is_empty() or not is_same(_fee_attempt_close_call,frame.get("call")):return false
	# The close claim is separate from both pre-existing seam claims. Refuse to
	# proceed if either old seam is outstanding at any frame checkpoint.
	if _fee_attempt_writer_call!=null or not _fee_attempt_writer_snapshot.is_empty() or _fee_attempt_writer_executing:return false
	if _fee_resume_sidecar_call!=null or not _fee_resume_sidecar_frame.is_empty() or _fee_resume_sidecar_executing:return false
	if not is_same(session,frame.get("session")) or not is_same(quest_auto,frame.get("quest_auto")) or not is_same(quest_auto.identity,frame.get("identity")):return false
	if not is_same(automation,frame.get("automation")) or not is_same(stationary,frame.get("stationary")) or not is_same(original_quests,frame.get("original_quests")):return false
	if quest_auto.running or quest_auto.source_frame!=null or quest_auto.identity.checkpoint()!=frame.get("stopped_identity",{}):return false
	if save_path!=frame.get("path") or account_name!=frame.get("account_name"):return false
	if not is_same(session._profile,frame.get("profile_ref")) or session._profile!=frame.get("profile",{}):return false
	if not is_same(session._pending,frame.get("pending_ref")) or session._pending!=frame.get("pending",{}):return false
	if not is_same(session._loot_settlement,frame.get("loot_ref")) or session._loot_settlement!=frame.get("loot",{}) or not session._loot_settlement.is_empty():return false
	if not is_same(original_quests.pending,frame.get("page_ref")) or original_quests.pending!=frame.get("page",{}):return false
	if not is_same(battle,frame.get("battle")) or battle_open:return false
	if _depth!=frame.get("depth") or _dispatch_boundary_depth!=frame.get("dispatch_boundary_depth") or _observer_depth!=frame.get("observer_depth") or _flush_depth!=frame.get("flush_depth") or _dispatch_epoch!=frame.get("dispatch_epoch"):return false
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	if owner!=frame.get("owner",{}):return false
	if automation.running or automation.hunt_running or automation.flow_active() or stationary.running or battle_open:return false
	return last_saved_payload==frame.get("cache") and quest_save_serial==frame.get("expected_serial")

func _fee_close_file_state(row:Dictionary,expected_exists:bool,expected_bytes:PackedByteArray)->Variant:
	var ok_value:Variant=row.get("ok",null)
	var exists_value:Variant=row.get("exists",null)
	if not (ok_value is bool) or not (exists_value is bool):return "unknown"
	var read_ok:bool=ok_value
	var exists:bool=exists_value
	if not read_ok:return "unknown"
	if exists!=expected_exists:return "differs"
	if not exists:return "matches"
	var bytes_value:Variant=row.get("bytes",null)
	if not bytes_value is PackedByteArray:return "unknown"
	var bytes:PackedByteArray=bytes_value
	return "matches" if bytes==expected_bytes else "differs"

func _fee_close_fact(row:Dictionary,candidate_bytes:PackedByteArray)->Variant:
	var state:Variant=_fee_close_file_state(row,true,candidate_bytes)
	if state=="matches":return true
	if state=="differs":return false
	return "unknown"

func _fee_close_read_complete(row:Variant)->bool:
	if not row is Dictionary:return false
	var ok_value:Variant=row.get("ok",null)
	var exists_value:Variant=row.get("exists",null)
	if not (ok_value is bool) or not (exists_value is bool):return false
	var read_ok:bool=ok_value
	var exists:bool=exists_value
	if not read_ok:return false
	if not exists:return true
	return row.get("bytes",null) is PackedByteArray

func _fee_close_result(frame:Dictionary,stage:String,w1_writer:Variant,w2_writer:Variant,primary:Dictionary,backup:Dictionary,temporary:Dictionary,operation_ok:bool)->Dictionary:
	var primary_fact:Variant=_fee_close_fact(primary,frame.get("candidate_bytes",PackedByteArray()))
	var backup_fact:Variant=_fee_close_fact(backup,frame.get("candidate_bytes",PackedByteArray()))
	var tmp_state:Variant=_fee_close_file_state(temporary,false,PackedByteArray())
	var pair_fact:Variant="unknown"
	if primary_fact is bool and backup_fact is bool:
		var primary_closed_bool:bool=primary_fact
		var backup_closed_bool:bool=backup_fact
		pair_fact=primary_closed_bool and backup_closed_bool
	return {"ok":operation_ok,"stage":stage,"stop_state_current":_fee_attempt_close_frame_current(frame),
		"profile_pair_closed":pair_fact,"primary_closed":primary_fact,"backup_closed":backup_fact,
		"temporary":"absent" if tmp_state=="matches" else ("unknown" if tmp_state=="unknown" else "present_or_changed"),
		"serial_before":frame.get("serial_before",-1),"serial_after_w1":frame.get("serial_after_w1",null),
		"serial_after_w2":quest_save_serial,"w1_calls":int(frame.get("w1_calls",0)),"w2_calls":int(frame.get("w2_calls",0)),
		"w1_writer_return":w1_writer,"w2_writer_return":w2_writer}

func _end_fee_attempt_close_frame(handle:Variant)->void:
	if not handle is Dictionary or handle.size()!=1 or not handle.has("call") or not is_same(_fee_attempt_close_call,handle.get("call")):return
	_fee_attempt_close_call=null
	_fee_attempt_close_frame={}
	_fee_attempt_close_executing=false

## Two forced writes of one exact Journal.close_run profile candidate. One serial
## advance records W1 installation; W2 is physical redundancy, not a new save event.
func _persist_fee_attempt_close_pair(handle:Variant)->Dictionary:
	if not handle is Dictionary or handle.size()!=1 or not handle.has("call") or not is_same(_fee_attempt_close_call,handle.get("call")):
		return {"ok":false,"stage":"invalid_handle","profile_pair_closed":"unknown","primary_closed":"unknown","backup_closed":"unknown","temporary":"unknown"}
	if _fee_attempt_close_executing:return {"ok":false,"stage":"already_executing","profile_pair_closed":"unknown","primary_closed":"unknown","backup_closed":"unknown","temporary":"unknown"}
	if _fee_attempt_close_frame.is_empty() or not is_same(handle.get("call"),_fee_attempt_close_frame.get("call")):
		return {"ok":false,"stage":"frame_mismatch","profile_pair_closed":"unknown","primary_closed":"unknown","backup_closed":"unknown","temporary":"unknown"}
	_fee_attempt_close_executing=true
	var frame:Dictionary=_fee_attempt_close_frame
	var unknown_primary:Dictionary={"ok":false,"exists":false}
	var unknown_backup:Dictionary={"ok":false,"exists":false}
	var unknown_tmp:Dictionary={"ok":false,"exists":false}
	if not _fee_attempt_close_frame_current(frame):
		var stale_before:Dictionary=_fee_close_result(frame,"owner_or_cas_before_w1",null,null,unknown_primary,unknown_backup,unknown_tmp,false)
		_end_fee_attempt_close_frame(handle);return stale_before
	var path:String=frame.path
	var primary_pre:Dictionary=session._read_fee_attempt_file(path,frame.primary_before)
	if not _fee_attempt_close_frame_current(frame):
		var primary_stale:Dictionary=_fee_close_result(frame,"owner_or_claim_changed_after_primary_read",null,null,primary_pre,unknown_backup,unknown_tmp,false)
		_end_fee_attempt_close_frame(handle);return primary_stale
	var backup_pre:Dictionary=session._read_fee_attempt_file(path+".bak",frame.backup_before)
	if not _fee_attempt_close_frame_current(frame):
		var backup_stale:Dictionary=_fee_close_result(frame,"owner_or_claim_changed_after_backup_read",null,null,primary_pre,backup_pre,unknown_tmp,false)
		_end_fee_attempt_close_frame(handle);return backup_stale
	var tmp_pre:Dictionary=session._read_fee_attempt_file(path+".tmp",frame.temporary_before)
	if not _fee_attempt_close_frame_current(frame):
		var tmp_stale:Dictionary=_fee_close_result(frame,"owner_or_claim_changed_after_tmp_read",null,null,primary_pre,backup_pre,tmp_pre,false)
		_end_fee_attempt_close_frame(handle);return tmp_stale
	var p0_state:Variant=_fee_close_file_state(primary_pre,true,frame.primary_before)
	var b0_state:Variant=_fee_close_file_state(backup_pre,bool(frame.backup_before_exists),frame.backup_before)
	var t0_state:Variant=_fee_close_file_state(tmp_pre,bool(frame.temporary_before_exists),frame.temporary_before)
	if p0_state!="matches" or b0_state!="matches" or t0_state!="matches" or not _fee_attempt_close_frame_current(frame):
		var disk_changed:Dictionary=_fee_close_result(frame,"disk_or_owner_changed_before_w1",null,null,primary_pre,backup_pre,tmp_pre,false)
		_end_fee_attempt_close_frame(handle);return disk_changed
	var s0:int=frame.serial_before
	var first:Dictionary=session._write_fee_close_candidate_once(frame.candidate,path,frame.profile_ref,frame.profile,frame.run_id,"w2" if frame.get("repairing",false) else "w1")
	frame.w1_calls=1
	var p1:Dictionary=first.get("primary",unknown_primary)
	var b1:Dictionary=first.get("backup",unknown_backup)
	var t1:Dictionary=first.get("temporary",unknown_tmp)
	var p1_fact:Variant=_fee_close_fact(p1,frame.candidate_bytes)
	var p1_is_candidate:bool=false
	if p1_fact is bool:
		var p1_fact_bool:bool=p1_fact
		p1_is_candidate=p1_fact_bool
	var w1_return:Variant=first.get("writer_return","unknown")
	var w1_return_is_true:bool=false
	if w1_return is bool:
		var w1_return_bool:bool=w1_return
		w1_return_is_true=w1_return_bool
	else:w1_return="unknown"
	if p1_is_candidate:
		if not _fee_attempt_close_frame_current(frame):
			var landed_stale:Dictionary=_fee_close_result(frame,"w1_closed_primary_but_old_frame_changed_before_install",w1_return,null,p1,b1,t1,false)
			_end_fee_attempt_close_frame(handle);return landed_stale
		var installed:Dictionary=frame.candidate.duplicate(true)
		session._profile=installed
		last_saved_payload=JSON.stringify(installed)
		quest_save_serial=s0+1
		frame.profile_ref=session._profile
		frame.profile=installed.duplicate(true)
		frame.cache=last_saved_payload
		frame.expected_serial=s0+1
		frame.serial_after_w1=s0+1
		frame.phase="w1_installed"
		if not w1_return_is_true or _fee_close_file_state(b1,true,frame.primary_before)!="matches" or _fee_close_file_state(t1,false,PackedByteArray())!="matches":
			var w1_partial:Dictionary=_fee_close_result(frame,"w1_landed_partial_or_wrapper_false",w1_return,null,p1,b1,t1,false)
			_end_fee_attempt_close_frame(handle);return w1_partial
		if not _fee_attempt_close_frame_current(frame):
			var stale_after_install:Dictionary=_fee_close_result(frame,"owner_or_cas_after_w1_install",w1_return,null,p1,b1,t1,false)
			_end_fee_attempt_close_frame(handle);return stale_after_install
		var primary_w2:Dictionary=session._read_fee_attempt_file(path,frame.candidate_bytes)
		if not _fee_attempt_close_frame_current(frame):
			var primary_w2_stale:Dictionary=_fee_close_result(frame,"w2_owner_or_claim_changed_after_primary_read",w1_return,null,primary_w2,unknown_backup,unknown_tmp,false)
			_end_fee_attempt_close_frame(handle);return primary_w2_stale
		var backup_w2:Dictionary=session._read_fee_attempt_file(path+".bak",PackedByteArray())
		if not _fee_attempt_close_frame_current(frame):
			var backup_w2_stale:Dictionary=_fee_close_result(frame,"w2_owner_or_claim_changed_after_backup_read",w1_return,null,primary_w2,backup_w2,unknown_tmp,false)
			_end_fee_attempt_close_frame(handle);return backup_w2_stale
		var tmp_w2:Dictionary=session._read_fee_attempt_file(path+".tmp",PackedByteArray())
		if not _fee_attempt_close_frame_current(frame):
			var tmp_w2_stale:Dictionary=_fee_close_result(frame,"w2_owner_or_claim_changed_after_tmp_read",w1_return,null,primary_w2,backup_w2,tmp_w2,false)
			_end_fee_attempt_close_frame(handle);return tmp_w2_stale
		if _fee_close_file_state(primary_w2,true,frame.candidate_bytes)!="matches" or _fee_close_file_state(backup_w2,true,frame.primary_before)!="matches" or _fee_close_file_state(tmp_w2,false,PackedByteArray())!="matches":
			var w2_pre:Dictionary=_fee_close_result(frame,"w2_preflight_changed",w1_return,null,primary_w2,backup_w2,tmp_w2,false)
			_end_fee_attempt_close_frame(handle);return w2_pre
		var second:Dictionary=session._write_fee_close_candidate_once(frame.candidate,path,frame.profile_ref,frame.profile,frame.run_id,"w2")
		frame.w2_calls=1
		var p2:Dictionary=second.get("primary",unknown_primary)
		var b2:Dictionary=second.get("backup",unknown_backup)
		var t2:Dictionary=second.get("temporary",unknown_tmp)
		var primary_closed:Variant=_fee_close_fact(p2,frame.candidate_bytes)
		var backup_closed:Variant=_fee_close_fact(b2,frame.candidate_bytes)
		var tmp_state:Variant=_fee_close_file_state(t2,false,PackedByteArray())
		var pair_closed:bool=false
		if primary_closed is bool and backup_closed is bool and tmp_state=="matches":
			var primary_closed_bool:bool=primary_closed
			var backup_closed_bool:bool=backup_closed
			pair_closed=primary_closed_bool and backup_closed_bool
		var current:bool=_fee_attempt_close_frame_current(frame)
		var w2_return:Variant=second.get("writer_return","unknown")
		var w2_return_is_true:bool=false
		var w2_return_is_false:bool=false
		if w2_return is bool:
			var w2_return_bool:bool=w2_return
			w2_return_is_true=w2_return_bool
			w2_return_is_false=not w2_return_bool
		else:w2_return="unknown"
		var operation_ok:bool=pair_closed and current and w2_return_is_true
		var stage:String="pair_verified" if operation_ok else ("pair_facts_verified_wrapper_false" if pair_closed and current and w2_return_is_false else "w2_partial_or_unknown")
		var final_result:Dictionary=_fee_close_result(frame,stage,w1_return,w2_return,p2,b2,t2,operation_ok)
		_end_fee_attempt_close_frame(handle)
		return final_result
	var old_primary:Variant=_fee_close_file_state(p1,true,frame.primary_before)
	var old_backup:Variant=_fee_close_file_state(b1,bool(frame.backup_before_exists),frame.backup_before)
	var old_pair:Variant="unknown"
	if old_primary=="matches" and old_backup=="matches":old_pair=false
	var no_install:Dictionary=_fee_close_result(frame,"w1_candidate_not_read_back",w1_return,null,p1,b1,t1,false)
	no_install.profile_pair_closed=old_pair
	_end_fee_attempt_close_frame(handle)
	return no_install

func _save_required_fee(frame:Dictionary)->bool:
	if not RequiredFee.writer_ready(self,frame):return false
	# Preserve Backend.save()'s explicit memory-only contract without passing an
	# empty path to GameSession.save_game() (which would attempt a disk write).
	session._profile=frame.candidate
	if save_path.is_empty():
		if not RequiredFee.mark_memory_committed(self,frame):
			if RequiredFee.same_owner(self,frame) and is_same(session._profile,frame.candidate) and session._profile==frame.expected and last_saved_payload==frame.cache and quest_save_serial==frame.serial:
				session._profile=frame.profile
			return false
		quest_save_serial+=1
		frame.committed_serial=quest_save_serial
		RequiredFee.publish_committed(self,frame)
		return true
	# Disk-backed transactions still use the original normalized atomic writer.
	if not session.save_game(save_path):
		# Roll back our exact uncommitted candidate BEFORE virtual return observers.
		if RequiredFee.same_owner(self,frame) and is_same(session._profile,frame.candidate) and session._profile==frame.expected and last_saved_payload==frame.cache and quest_save_serial==frame.serial:
			session._profile=frame.profile
		return false
	last_saved_payload=JSON.stringify(session.snapshot())
	quest_save_serial+=1
	RequiredFee.mark_written(self,frame)
	if not frame.marked:return false
	RequiredFee.publish_committed(self,frame)
	return true

func _cmd_quest_visit(command: Dictionary) -> Dictionary:
	var mode := str(command.get("mode","near"))
	if mode not in ["near","arrival"]:return _reject("无效的任务旅行方式。")
	if battle_open or not session._pending.is_empty() or automation.running or automation.hunt_running or automation.flow_active() or not original_quests.pending.is_empty():return _reject("当前正忙。")
	if quest_visit_guard.is_valid():
		var reason := str(quest_visit_guard.call())
		if not reason.is_empty():return _reject(reason)
	var npc: Dictionary = original_quests.npc_by_id(str(command.get("npc_id","")))
	if command.has("quest_id") or command.has("step_id"):
		var quest_id = command.get("quest_id")
		if not quest_id is int and not quest_id is float:return _reject("无效任务编号。")
		if float(quest_id)!=floor(float(quest_id)):return _reject("无效任务编号。")
		var step:Dictionary=quest_helper.resolve_step(self,int(quest_id),str(command.get("step_id","")))
		if step.is_empty():return _reject("任务步骤尚未开放。")
		if not str(step.npc_id).is_empty():npc=original_quests.npc_by_id(str(step.npc_id))
		elif str(step.source.get("type",""))=="encounter":npc={"id":"","map_id":int(step.map_id),"cell":step.cell,"area_rect":step.source.area_rect}
	if npc.is_empty():return _reject("任务人物尚未开放。")
	var target: Dictionary = quest_helper.destination(self,npc,mode)
	if target.is_empty():return _reject("没有安全且可抵达人物的落点。")
	var map_id := int(target.map_id)
	var cell := Vector2i(int(target.cell[0]),int(target.cell[1]))
	original_quests.pending={}
	automation.position_changed(map_id,cell,map_id!=automation.position_map)
	_emit({"type":"position","map_id":map_id,"cell":target.cell,"client":str(command.get("client",""))})
	_publish()
	return {"ok":true,"target":target}

func _cmd_quest_talk(command: Dictionary) -> Dictionary:
	return original_quests.talk(self,str(command.get("npc_id","")))

func _cmd_quest_choose(command: Dictionary) -> Dictionary:
	if quest_auto.running:return quest_auto.choose_waiting(self,command)
	return original_quests.choose(self,str(command.get("token","")),str(command.get("choice","")),str(command.get("text","")),command.get("pet_ids",[]))

func _cmd_quest_close(command: Dictionary) -> Dictionary:
	if quest_auto.running:
		if not quest_auto.accepts_waiting_command(self,command):return _reject("自动任务等待已过期。")
		var stop_result:Dictionary=quest_auto.stop(self,"已取消奖励选择，停止自动任务。")
		if not stop_result.get("ok",false):return stop_result
		return {"ok":true,"closed":true}
	if original_quests.pending.is_empty() or str(command.get("token",""))!=str(original_quests.pending.token):return _reject("对话已过期。")
	original_quests.pending={}
	return {"ok":true,"closed":true}

func _cmd_quest_discard(command: Dictionary) -> Dictionary:
	if battle_open or automation.running or automation.hunt_running or automation.flow_active():return _reject("当前正忙。")
	var before: Dictionary=session.snapshot()
	var item = command.get("item_id")
	if not item is int and not item is float:return _reject("无效物品。")
	if float(item)!=floor(float(item)) or not int(item) in before.original_items:return _reject("没有这个物品。")
	var uid = command.get("instance_uid")
	if uid!=null:
		if not GameSession.OriginalEquipment.integer(uid,1,2147483647):return _reject("无效物品。")
		var index: int=-1
		for i in range(before.original_instances.size()):
			if int(before.original_instances[i].uid)==int(uid) and int(before.original_items[i])==int(item):index=i;break
		if index<0:return _reject("没有这个物品。")
		GameSession.OriginalEquipment.remove_at(session._profile,index)
	else:GameSession.OriginalEquipment.remove_at(session._profile,before.original_items.find(int(item)))
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
	if not GameSession.OriginalEquipment.result_valid(config.get("original_equipment_items",[]),live.get("original_equipment_items",[])):return false
	session._profile = session._normalize_numbers(profile)
	GameSession.OriginalEquipment.migrate(session._profile)
	session._pending = config.duplicate(true)
	session._pending.original_equipment_items = session._normalize_numbers(config.get("original_equipment_items",[]))
	battle = BattleSession.new()
	battle.rng_seed = int(saved.get("rng_seed",42))
	battle.start_battle(session._pending)
	battle._state = live.duplicate(true)
	battle._state.original_equipment_items = session._normalize_numbers(live.get("original_equipment_items",[]))
	battle.restore_original_equipment()
	battle._rng.state = int(saved.get("rng_state",battle._rng.state))
	battle._escape_attempts = int(saved.get("escape_attempts",0))
	battle._skill_used = bool(saved.get("skill_used",false))
	battle._chosen_skill = int(saved.get("chosen_skill",0))
	battle._pet_target = int(saved.get("pet_target",-1))
	battle_state = battle.snapshot()
	battle_open = true
	_publish()
	return true

func _cmd_quest_auto_continue(command:Dictionary)->Dictionary:
	return quest_auto.continue_boss(self,command)

func _cmd_quest_auto_start(command: Dictionary) -> Dictionary:
	return quest_auto.start(self,command)

func _cmd_quest_loot_start(command:Dictionary)->Dictionary:
	var seq_value:Variant=command.get("seq",null)
	var seq:int=int(seq_value) if seq_value is int else 0
	if not _quest_loot_public_enabled():return {"ok":false,"reason":"限时刷物尚未开放。","seq":seq,"type":"rejected","persisted":false}
	for key in command:
		if key not in ["type","seq","_quest_connection"]:return {"ok":false,"reason":"刷物启动只接受序号；来源和位置由服务端核验。","seq":seq,"type":"rejected","persisted":false}
	if command.get("type")!="quest_loot_start" or not command.has("seq") or not seq_value is int or seq_value<=0:return {"ok":false,"reason":"无效刷物启动序号。","seq":seq,"type":"rejected","persisted":false}
	var connection:Variant=command.get("_quest_connection",null)
	if not connection is int or connection==-1:return {"ok":false,"reason":"刷物启动需要可信发起连接。","seq":seq,"type":"rejected","persisted":false}
	var binding:Variant=_fee_bindings.get(connection)
	if not binding is RefCounted or _fee_bindings.get(connection)!=binding:return {"ok":false,"reason":"刷物启动需要当前已连接的可信设备。","seq":seq,"type":"rejected","persisted":false}
	return quest_loot.public_start(self,int(connection),binding,seq)

func _cmd_quest_auto_stop(_command: Dictionary) -> Dictionary:
	var stopped:Dictionary=quest_auto.stop(self,"已停止自动任务。",true,{},true)
	var lifecycle_value:Variant=stopped.get("lifecycle",null)
	var stop_ok_value:Variant=stopped.get("ok",null)
	if lifecycle_value is String and lifecycle_value=="legacy" and stop_ok_value is bool and stop_ok_value:return {"ok":true}
	return stopped

func _revival_transaction() -> bool:
	return bool(session._pending.get("revival_transaction",false)) or not session._pending.get("original_revival_items",[]).is_empty()

func _cmd_item_storage_transfer(command: Dictionary) -> Dictionary:
	return GameSession.ItemStorage.transfer(self,command)

func _cmd_transmigration(command:Dictionary)->Dictionary:
	return transmigration.command(self,command)
