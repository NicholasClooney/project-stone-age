extends "res://tests/quest_auto_loot_crystal_prerequisite_test.gd"
## UNRUN pilot candidate. Disclosed GM60 + the original near helper are setup
## conveniences; the last leg is real GameScene collision walking. This is
## not the birth route, public loot authorization, or a seeded drop test.
const Server=preload("res://server/ws_server.gd")
const Game=preload("res://scripts/game.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
const Plan=preload("res://server/quest_auto_jewel_loot_plan.gd")
const Wait=preload("res://tests/support/wait.gd")
const GENOU="sainasu/event/genou_3@100:346:356"
const MAX_ATTEMPTS:=360
const MAX_BATTLES:=20
const MAX_ROUTE_BATTLES:=20
const HARD_LIMIT_MS:=360000
const BUDGET_MINUTES:=3
const MAX_SOURCE_CELLS:=1800
const MAX_PATH_QUERIES:=8
const MAX_ASTAR_SEARCH_WINDOWS:=32
const MAX_ROUTE_SEARCH_WINDOWS:=64
const MAX_ROUTE_SEARCH_CELL_VISITS:=24000000
const MAX_ROUTE_WALK_REPLANS:=20
const MAX_ROUTE_CELLS:=4096
const MAX_MAP_CELLS:=1000000
const MAX_ASTAR_CELL_VISITS:=12000000
const MAX_ROUTE_REPORTS:=4096
const MAX_NORMAL_TICKS:=200000
const MAX_NORMAL_TRANSITIONS:=4096
const MAX_ACTIVE_ENTRY_SAMPLES:=512
const MAX_TRACE_EVENT_BYTES:=1048576
const MAX_TRACE_OUTPUT_BYTES:=16777216
const MAX_UNCOMPLETE_EVIDENCE_BYTES:=4194304
const DISK_PATH:="user://loot-2760-natural-pilot.json"
const UNCOMPLETE_PATH:="user://loot-2760-natural-pilot.uncomplete.json"

class PilotBackend:
 extends "res://server/backend.gd"
 const PilotState=preload("res://server/quest_auto_loot_state.gd")
 const Compare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
 const PILOT_MAX_ROUTE_REPORTS:=4096
 const PILOT_MAX_ATTEMPTS:=360
 const PILOT_MAX_SETTLEMENTS:=20
 const PILOT_MAX_TRACE_EVENT_BYTES:=1048576
 const PILOT_MAX_TRACE_OUTPUT_BYTES:=16777216
 const PILOT_MAX_PROFILE_DISK_BYTES:=8388608
 var route_reports:Array[Dictionary]=[]
 var field_steps:Array[Dictionary]=[]
 var closed_receipts:Array[Dictionary]=[]
 var close_attempts:Array[Dictionary]=[]
 var settlement_commits:Array[Dictionary]=[]
 var retired_battles:Array[Dictionary]=[]
 var expected_client_id:=""
 var received_transports:Array[Dictionary]=[]
 var invalid_transport_binding:=false
 var route_trace_enabled:=false
 var route_trace_overflow:=false
 var settlement_trace_overflow:=false
 var settlement_failed:=false
 var settlement_observation_failed:=false
 var close_observation_failed:=false
 var transport_binding_changed:=false
 var client_peer_ids:Dictionary={}
 var pilot_attempt_count:=0
 var trace_output_bytes:=0
 var trace_output_overflow:=false
 var pilot_initial_e2_failure:=""
 var pilot_initial_e2_calls:=0
 var pilot_initial_e2_retired:=false
 var pilot_initial_e2_last_generation:=0
 var pilot_initial_e2_generation_floor:=0
 var pilot_initial_runner:WeakRef
 var pilot_initial_e2_connection:Variant=-1
 var pilot_initial_e2_client:=""
 func trace_event(label:String,value:Variant)->bool:
  var encoded:String=JSON.stringify(value)
  var size:int=encoded.to_utf8_buffer().size()
  if size>PILOT_MAX_TRACE_EVENT_BYTES or trace_output_bytes+size>PILOT_MAX_TRACE_OUTPUT_BYTES:
   trace_output_overflow=true
   route_trace_overflow=true
   print("PILOT_TRACE_OVERFLOW ",JSON.stringify({"label":label,"event_bytes":size,"event_limit":PILOT_MAX_TRACE_EVENT_BYTES,"total_bytes":trace_output_bytes,"total_limit":PILOT_MAX_TRACE_OUTPUT_BYTES,"complete_record_not_emitted":true}))
   return false
  trace_output_bytes+=size
  print(label," ",encoded)
  return true
 func handle(command:Dictionary)->Dictionary:
  var incoming_client_id:String=str(command.get("client",""))
  var incoming_connection:Variant=command.get("_quest_connection",-1)
  var incoming_type:String=str(command.get("type",""))
  var reply:Dictionary=super.handle(command)
  if not expected_client_id.is_empty() and incoming_client_id==expected_client_id:
   var valid_binding:bool=typeof(incoming_connection)==TYPE_INT and int(incoming_connection)!=-1
   if not valid_binding:invalid_transport_binding=true
   var binding:Dictionary={"client_id":incoming_client_id,"server_connection_id":incoming_connection,"command_type":incoming_type,"valid_server_transport_binding":valid_binding}
   if received_transports.is_empty():received_transports.append(binding)
   elif received_transports[0].server_connection_id!=binding.server_connection_id:transport_binding_changed=true
  if route_trace_enabled and str(command.get("type",""))=="report_position":
   if route_reports.size()>=PILOT_MAX_ROUTE_REPORTS:route_trace_overflow=true
   else:
    var report:Dictionary={"command":{"map_changed":bool(command.get("map_changed",false)),"map_id":command.get("map_id",-1),"cell":command.get("cell",[]).duplicate(true) if command.get("cell",[]) is Array else command.get("cell")},"reply_ok":bool(reply.get("ok",false)),"authority":{"map":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]},"process_generation":_normal_process_generation}
    route_reports.append(report)
    trace_event("PILOT_ROUTE_REPORT",report)
  return reply
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var rng_before:int=encounter_rng.state
  var pressure_before:int=encounter_catalog.pressure
  var reply:Dictionary=super._cmd_field_step(command)
  var attempt:bool=quest_loot.attempt_call!=null
  if attempt:
   if field_steps.size()>=PILOT_MAX_ATTEMPTS:
    route_trace_overflow=true
    return reply
   var sample:Dictionary={"attempt":true,"generation":_normal_process_generation,"map":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"area":encounter_catalog.area_at(automation.position_map,automation.position_cell).get("id",-1),"rng_before":str(rng_before),"rng_after":str(encounter_rng.state),"pressure_before":pressure_before,"pressure_after":encounter_catalog.pressure,"reply":reply.duplicate(true)}
   pilot_attempt_count+=1
   sample.pending_group=session._pending.get("group_id",-1)
   sample.pending_battle_id=str(session._pending.get("battle_id",""))
   sample.receipt=session._pending.get("quest_loot_receipt",{}).duplicate(true)
   field_steps.append(sample)
   trace_event("PILOT_FIELD_STEP",sample)
  return reply
 func _after_turn(state:Dictionary,settle:Dictionary={},drop_claims:Array=[])->Dictionary:
  var pending_before:Dictionary=session._pending.duplicate(true)
  var receipt:Dictionary=pending_before.get("quest_loot_receipt",{}).duplicate(true)
  var battle_id:=str(pending_before.get("battle_id",""))
  var state_battle_id:=str(state.get("battle_id",""))
  var before_profile:Dictionary=session._profile.duplicate(true)
  var before_entry:Dictionary=before_profile.get("quest_loot",{}).get("entries",{}).get(PilotState.STEP,{}).duplicate(true)
  var before_cache:String=last_saved_payload
  var before_serial:int=quest_save_serial
  var result:Dictionary=super._after_turn(state,settle,drop_claims)
  if receipt.is_empty():return result
  var state_active:bool=bool(state.get("active",false))
  var result_active:bool=bool(result.get("active",false))
  if state_active:
   var pending_after:Dictionary=session._pending
   var active_identity_ok:bool=result_active and result.get("settled",false)!=true and not battle_id.is_empty() and battle_id==state_battle_id and str(pending_after.get("battle_id",""))==battle_id and pending_after.get("quest_loot_receipt",{})==receipt
   if not active_identity_ok:
    trace_event("PILOT_AFTER_TURN_INVALID_ACTIVE",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"state":state,"result":result,"pending_before":pending_before,"pending_after":pending_after,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
    settlement_failed=true
    return result
   # Original nonterminal turns retain the receipt and continue the same battle.
   # They are observations only: no receipt commit, disk capture, or battle count.
   if not trace_event("PILOT_AFTER_TURN_ACTIVE",{"battle_id":battle_id,"receipt":receipt,"state":state,"result":result,"pending_after":pending_after,"serial_before":before_serial,"serial_after":quest_save_serial}):settlement_failed=true
   return result
  if result_active:
   trace_event("PILOT_AFTER_TURN_INVALID_TERMINAL",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"state":state,"result":result,"pending_before":pending_before,"pending_after":session._pending,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
   settlement_failed=true
   return result
  if result.get("settled",false)!=true:
   trace_event("PILOT_AFTER_TURN_NOT_COMMITTED",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"result":result,"pending_after":session._pending,"profile_before":before_profile,"profile_after":session._profile.duplicate(true),"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
   settlement_failed=true
   return result
  var identity_ok:bool=not battle_id.is_empty() and battle_id==state_battle_id and str(receipt.get("ledger",{}).get("battle_id",""))==battle_id and not _has_settlement(battle_id)
  var after_profile:Dictionary=session._profile.duplicate(true)
  var after_entry:Dictionary=after_profile.get("quest_loot",{}).get("entries",{}).get(PilotState.STEP,{})
  var received_target:=0
  var drop_summary:Variant=result.get("drop_summary",[])
  if not drop_summary is Array:
   trace_event("PILOT_AFTER_TURN_INVALID_RESULT",{"battle_id":battle_id,"result":result,"profile_before":before_profile,"profile_after":after_profile,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
   settlement_failed=true
   return result
  for drop in drop_summary:
   if not drop is Dictionary:
    trace_event("PILOT_AFTER_TURN_INVALID_DROP",{"battle_id":battle_id,"result":result,"invalid_drop":drop,"profile_before":before_profile,"profile_after":after_profile,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
    settlement_failed=true
    return result
   if int(drop.get("item_id",-1))==2760 and drop.get("received",false)==true:received_target+=1
  var before_target_uids:Array=[]
  for item in before_profile.get("original_instances",[]):
   if int(item.get("item_id",-1))==2760:before_target_uids.append(int(item.get("uid",-1)))
  var received_target_uids:Array=[]
  for item in after_profile.get("original_instances",[]):
   var uid:int=int(item.get("uid",-1))
   if int(item.get("item_id",-1))==2760 and not before_target_uids.has(uid):received_target_uids.append(uid)
  var primary:Dictionary=_capture_disk(save_path)
  var backup:Dictionary=_capture_disk(save_path+".bak")
  var disk_copy:Dictionary=Compare.validated_copy(session,primary.bytes.get_string_from_utf8()) if primary.ok else {"ok":false}
  var backup_copy:Dictionary=Compare.validated_copy(session,backup.bytes.get_string_from_utf8()) if backup.ok else {"ok":false}
  var cache_copy:Dictionary=Compare.validated_copy(session,last_saved_payload)
  var native_copy:Dictionary=session._normalize_numbers(after_profile.duplicate(true))
  var capture_valid:bool=primary.ok and backup.ok and disk_copy.get("ok",false) and backup_copy.get("ok",false) and cache_copy.get("ok",false) and session._valid_profile(after_profile)
  var capture_matches:bool=capture_valid and disk_copy.profile==native_copy and cache_copy.profile==native_copy and primary.bytes.get_string_from_utf8()==last_saved_payload
  trace_event("PILOT_AFTER_TURN_RECEIPT",{"battle_id":battle_id,"state_battle_id":state_battle_id,"identity_ok":identity_ok,"receipt":receipt,"pending_before":pending_before,"result":result,"received_target":received_target,"received_target_uids":received_target_uids,"profile_before":before_profile,"profile_after":after_profile,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial,"primary":{"ok":primary.get("ok",false),"sha256":primary.get("sha256",""),"declared":primary.get("declared",-1),"actual":primary.get("actual",-1)},"backup":{"ok":backup.get("ok",false),"sha256":backup.get("sha256",""),"declared":backup.get("declared",-1),"actual":backup.get("actual",-1)},"capture_valid":capture_valid,"capture_matches":capture_matches,"backup_valid":backup_copy.get("ok",false)})
  if not capture_valid:
   settlement_failed=true
   return result
  if not capture_matches:
   settlement_failed=true
   return result
  if not identity_ok or int(after_entry.get("saved_battles",-1))!=int(before_entry.get("saved_battles",-2))+1 or int(after_entry.get("new_items",-1))!=int(before_entry.get("new_items",-2))+received_target or received_target_uids.size()!=received_target or not session._pending.is_empty():settlement_observation_failed=true
  if settlement_failed:return result
  if settlement_observation_failed:return result
  if settlement_commits.size()>=PILOT_MAX_SETTLEMENTS:
   settlement_trace_overflow=true
   return result
  settlement_commits.append({"battle_id":battle_id,"receipt":receipt,"pending_before_commit":pending_before,"result":result.duplicate(true),"profile_before_commit":before_profile,"profile_after_commit":after_profile,"cache_before_commit":before_cache,"cache_after_commit":last_saved_payload,"serial_before_commit":before_serial,"serial_after_commit":quest_save_serial,"primary":{"bytes":primary.bytes,"sha256":primary.sha256,"declared":primary.declared,"actual":primary.actual},"backup":{"bytes":backup.bytes,"sha256":backup.sha256,"declared":backup.declared,"actual":backup.actual},"received_target":received_target,"received_target_uids":received_target_uids})
  return result
 func _capture_disk(path:String)->Dictionary:
  var file:=FileAccess.open(path,FileAccess.READ)
  var opened:int=FileAccess.get_open_error()
  if file==null:return {"ok":false,"path":path,"open_error":opened}
  var declared:int=file.get_length()
  var length_error:int=file.get_error()
  if length_error!=OK:
   file.close()
   return {"ok":false,"path":path,"open_error":opened,"length_error":length_error,"declared":declared}
  if declared<=0 or declared>PILOT_MAX_PROFILE_DISK_BYTES:
   file.close()
   return {"ok":false,"path":path,"open_error":opened,"length_error":length_error,"declared":declared,"limit":PILOT_MAX_PROFILE_DISK_BYTES,"reason":"disk_evidence_length_out_of_bounds"}
  var bytes:PackedByteArray=file.get_buffer(declared)
  var read_error:int=file.get_error()
  file.close()
  if opened!=OK or read_error!=OK or declared<=0 or bytes.size()!=declared:return {"ok":false,"path":path,"open_error":opened,"read_error":read_error,"declared":declared,"actual":bytes.size()}
  var context:=HashingContext.new()
  if context.start(HashingContext.HASH_SHA256)!=OK or context.update(bytes)!=OK:return {"ok":false,"path":path,"hash_error":true,"declared":declared,"actual":bytes.size()}
  var digest:PackedByteArray=context.finish()
  if digest.size()!=32:return {"ok":false,"path":path,"hash_error":true,"hash_bytes":digest.size()}
  return {"ok":true,"path":path,"open_error":opened,"length_error":length_error,"read_error":read_error,"declared":declared,"actual":bytes.size(),"sha256":digest.hex_encode(),"bytes":bytes}
 func _has_settlement(battle_id:String)->bool:
  return settlement_commits.any(func(row):return str(row.get("battle_id",""))==battle_id)
 func close_battle()->String:
  var battle_before:Dictionary=battle._state.duplicate(true)
  var battle_id:=str(battle_before.get("battle_id",""))
  var had_loot_receipt:bool=session._pending.get("quest_loot_receipt",{}) is Dictionary and not session._pending.get("quest_loot_receipt",{}).is_empty()
  var already_retired:bool=retired_battles.any(func(previous):return str(previous.get("battle_id",""))==battle_id)
  var commit:Dictionary={}
  for row in settlement_commits:
   if str(row.get("battle_id",""))==battle_id:commit=row;break
  var profile_before:Dictionary=session._profile.duplicate(true)
  var cache_before:String=last_saved_payload
  var serial_before:int=quest_save_serial
  var outcome:String=super.close_battle()
  var profile_after:Dictionary=session._profile.duplicate(true)
  var entry_before:Dictionary=profile_before.get("quest_loot",{}).get("entries",{}).get(PilotState.STEP,{})
  var entry_after:Dictionary=profile_after.get("quest_loot",{}).get("entries",{}).get(PilotState.STEP,{})
  var row:Dictionary={"battle_id":battle_id,"commit_seen_before_close":not commit.is_empty(),"settlement_commit":commit,"battle_before_close":battle_before,"profile_before_close":profile_before,"cache_before_close":cache_before,"serial_before_close":serial_before,"outcome":outcome,"saved_battles_before_close":entry_before.get("saved_battles",0),"saved_battles_after_close":entry_after.get("saved_battles",0),"new_items_after_close":entry_after.get("new_items",0),"profile_after_close":profile_after,"cache_after_close":last_saved_payload,"serial_after_close":quest_save_serial,"pending_after_close":session._pending.duplicate(true)}
  if already_retired:
   close_observation_failed=true
   return outcome
  if not commit.is_empty():
   if int(row.saved_battles_after_close)!=int(row.saved_battles_before_close):close_observation_failed=true
   var archive_stage:String="battle-%02d"%[retired_battles.size()+1]
   var primary_archive:Dictionary=_archive_commit_bytes(archive_stage+".primary",commit.primary.bytes,str(commit.primary.sha256))
   var backup_archive:Dictionary=_archive_commit_bytes(archive_stage+".backup",commit.backup.bytes,str(commit.backup.sha256))
   if not primary_archive.get("ok",false) or not backup_archive.get("ok",false):
    close_observation_failed=true
    row.archive_failure={"primary":primary_archive,"backup":backup_archive}
    retired_battles.append(row.duplicate(true))
    closed_receipts.append({"battle_id":battle_id,"receipt":commit.get("receipt",{}),"archive_failure":row.archive_failure})
    trace_event("PILOT_CLOSE_ARCHIVE_FAILED",{"battle_id":battle_id,"primary_archive":primary_archive,"backup_archive":backup_archive,"saved_battles_before_close":row.saved_battles_before_close,"saved_battles_after_close":row.saved_battles_after_close,"profile_after_close":profile_after,"cache_after_close":last_saved_payload,"serial_after_close":quest_save_serial})
    return outcome
   for index in range(settlement_commits.size()):
    if str(settlement_commits[index].get("battle_id",""))==battle_id:
     settlement_commits[index].primary.erase("bytes")
     settlement_commits[index].backup.erase("bytes")
     settlement_commits[index].primary.archive=primary_archive
     settlement_commits[index].backup.archive=backup_archive
     row.settlement_commit=settlement_commits[index].duplicate(true)
     break
   retired_battles.append(row.duplicate(true))
   closed_receipts.append(row.settlement_commit.duplicate(true))
   trace_event("PILOT_CLOSE_RETIRE",{"battle_id":battle_id,"outcome":outcome,"commit_seen_before_close":true,"saved_battles_before_close":row.saved_battles_before_close,"saved_battles_after_close":row.saved_battles_after_close,"primary_archive":primary_archive,"backup_archive":backup_archive,"pending_after_close":row.pending_after_close,"serial_before_close":serial_before,"serial_after_close":quest_save_serial})
  elif route_trace_enabled and not battle_id.is_empty():
   if had_loot_receipt:close_observation_failed=true
   if close_attempts.size()>=PILOT_MAX_ROUTE_REPORTS:close_observation_failed=true
   else:close_attempts.append({"battle_id":battle_id,"outcome":outcome,"saved_battles_before_close":row.saved_battles_before_close,"saved_battles_after_close":row.saved_battles_after_close,"serial_before_close":serial_before,"serial_after_close":quest_save_serial})
  return outcome
 func _archive_commit_bytes(name:String,bytes:PackedByteArray,expected_sha:String)->Dictionary:
  var destination:String=save_path+".evidence/"+name
  if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):return {"ok":false,"path":destination,"reason":"destination exists"}
  var output:=FileAccess.open(destination,FileAccess.WRITE)
  var open_error:int=FileAccess.get_open_error()
  if output==null:return {"ok":false,"path":destination,"open_error":open_error}
  output.store_buffer(bytes);output.flush()
  var write_error:int=output.get_error();output.close()
  if open_error!=OK or write_error!=OK:return {"ok":false,"path":destination,"open_error":open_error,"write_error":write_error}
  var copied:Dictionary=_capture_disk(destination)
  if not copied.get("ok",false) or copied.bytes!=bytes or copied.sha256!=expected_sha:return {"ok":false,"path":destination,"readback":copied}
  return {"ok":true,"path":destination,"sha256":copied.sha256,"declared":copied.declared,"actual":copied.actual}

class PassiveAutomation:
 extends "res://server/automation.gd"
 const PILOT_MAX_NORMAL_TICKS:=200000
 const PILOT_MAX_NORMAL_TRANSITIONS:=4096
 const PILOT_MAX_ACTIVE_ENTRY_SAMPLES:=512
 var observed_backend
 var normal_ticks:=0
 var all_normal_active_ticks:=0
 var loot_receipt_active_ticks:=0
 var observation_overflow:=false
 var observe_loot_run:=false
 var transitions:Array[Dictionary]=[]
 var active_entry_samples:Array[Dictionary]=[]
 var last_signature:=""
 var previous_active:=false
 func _init(owner)->void:
  observed_backend=owner
  super(owner)
 func begin_observation()->void:
  normal_ticks=0;all_normal_active_ticks=0;loot_receipt_active_ticks=0;observation_overflow=false
  transitions.clear();active_entry_samples.clear();last_signature="";previous_active=false
 func tick(delta:float)->void:
  var b=observed_backend
  var generation:int=b._normal_process_generation
  var normal:bool=b._process_depth==1 and b._dispatch_boundary_depth==1 and b._observer_depth==0 and b._flush_depth==0 and b._depth==1 and generation>0
  super.tick(delta)
  if not normal or generation!=b._normal_process_generation:return
  if not observe_loot_run:return
  normal_ticks+=1
  if normal_ticks>PILOT_MAX_NORMAL_TICKS:
   observation_overflow=true
   return
  # BattleSession.snapshot() refreshes capture_player from live session config.
  # Passive observation must not mutate the battle it is measuring.
  var state:Dictionary=b.battle._state.duplicate(true)
  var receipt:Dictionary=b.session._pending.get("quest_loot_receipt",{})
  var q=b.quest_auto
  var scope:Dictionary=b.automation._loot_frame()
  var exact_live_receipt:bool=not receipt.is_empty() and receipt==b.quest_loot.battle_receipt and str(receipt.get("ledger",{}).get("battle_id",""))==str(state.get("battle_id","")) and str(b.session._pending.get("battle_id",""))==str(state.get("battle_id","")) and b.battle_open and b.automation._loot_current(scope)
  var active:bool=bool(state.get("active",false))
  var active_receipt:bool=active and q.running and q.internal and q.phase=="loot_battle" and exact_live_receipt
  var sample:Dictionary={"generation":generation,"active_after_automation_tick":active,"turn":int(state.get("turn",0)),"receipt":not receipt.is_empty(),"exact_live_receipt":exact_live_receipt,"battle_id":str(state.get("battle_id","")),"phase":q.phase,"running":q.running,"internal":q.internal,"compact":compact_active}
  if active:
   all_normal_active_ticks+=1
   if active_receipt:loot_receipt_active_ticks+=1
  var signature:String=str([active,str(state.get("battle_id","")),int(state.get("turn",0)),q.phase,q.running,q.internal,not receipt.is_empty(),exact_live_receipt,compact_active])
  var active_entry:bool=active and not previous_active
  if signature!=last_signature:
   if transitions.size()>=PILOT_MAX_NORMAL_TRANSITIONS:
    observation_overflow=true
    return
   last_signature=signature
   var transition:Dictionary={"generation":generation,"active_after_automation_tick":active,"loot_receipt_active_after_automation_tick":active_receipt,"battle_id":str(state.get("battle_id","")),"turn":int(state.get("turn",0)),"phase":q.phase,"running":q.running,"internal":q.internal,"receipt":not receipt.is_empty(),"exact_live_receipt":exact_live_receipt,"compact":compact_active}
   transitions.append(transition)
   if not b.trace_event("PILOT_NORMAL_PROCESS_TRANSITION",transitions.back()):
    observation_overflow=true
    return
  if active_entry:
   if active_entry_samples.size()>=PILOT_MAX_ACTIVE_ENTRY_SAMPLES:
    observation_overflow=true
    return
   active_entry_samples.append(sample)
   if not b.trace_event("PILOT_NORMAL_ACTIVE_ENTRY",sample):
    observation_overflow=true
    return
  previous_active=active

class CappedPilotRunner:
 extends "res://server/quest_auto.gd"
 const PILOT_MAX_ATTEMPTS:=360
 const PILOT_MAX_BATTLES:=20
 const PILOT_STEP="jewels:hunt:2760"
 var initial_e2_token:RefCounted
 var initial_e2_lifetime:RefCounted
 var initial_e2_identity:Dictionary={}
 var initial_e2_connection:Variant=-1
 var initial_e2_client:=""
 var initial_e2_step:Dictionary={}
 var initial_e2_generation_floor:=0
 var initial_e2_last_generation:=0
 var initial_e2_retired:=false
 func _normal_process(b,generation:int)->bool:
  return b._process_depth==1 and b._dispatch_boundary_depth==1 and b._observer_depth==0 and b._flush_depth==0 and b._depth==1 and generation>0 and generation==b._normal_process_generation
 func _initial_e2_owner(b,generation:int,token:RefCounted,identity_snapshot:Dictionary)->bool:
  if not _normal_process(b,generation) or generation<=initial_e2_generation_floor:return false
  if not is_same(b.quest_auto,self) or not is_same(b.quest_loot.lifetime,initial_e2_lifetime) or not is_same(initial_e2_token,token):return false
  if connection!=initial_e2_connection or client!=initial_e2_client or step!=initial_e2_step:return false
  if identity.checkpoint()!=identity_snapshot or identity_snapshot!=initial_e2_identity:return false
  var ready:Dictionary=b.quest_loot.ready_frame
  return not ready.is_empty() and ready.get("identity",{})==identity_snapshot and ready.get("connection",-1)==initial_e2_connection and ready.get("client","")==initial_e2_client and ready.get("step",{})==initial_e2_step and is_same(ready.get("ready_token"),token) and not ready.has("continuation_gate")
 func _initial_e2_fail(b,reason:String,reply:Dictionary)->void:
  b.pilot_initial_e2_failure=reason
  b.trace_event("PILOT_INITIAL_E2_FAILURE",{"reason":reason,"reply":reply.duplicate(true),"generation":b._normal_process_generation,"q_running":running,"q_phase":phase,"identity":identity.checkpoint(),"attempt_call_active":b.quest_loot.attempt_call!=null,"battle_open":b.battle_open,"pending":b.session._pending.duplicate(true),"settlement":b.session._loot_settlement.duplicate(true)})
 func tick(b,delta:float)->void:
  var generation:int=b._normal_process_generation
  var normal_at_entry:bool=_normal_process(b,generation)
  var initial_owner_at_entry:bool=normal_at_entry and is_same(b.quest_auto,self) and is_same(b.quest_loot.lifetime,initial_e2_lifetime) and not initial_e2_identity.is_empty() and identity.checkpoint()==initial_e2_identity
  var token_at_entry:RefCounted=initial_e2_token
  var entry:Dictionary=b.session._profile.quest_loot.entries.get(PILOT_STEP,{})
  var safe_to_stop:bool=not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty()
  if running and safe_to_stop and (b.pilot_attempt_count>=PILOT_MAX_ATTEMPTS or int(entry.get("saved_battles",0))>=PILOT_MAX_BATTLES):
   stop(b,"内部pilot达到有限业务上限。")
   return
  super.tick(b,delta)
  var after:Dictionary=b.session._profile.quest_loot.entries.get(PILOT_STEP,{})
  var settled:bool=not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty()
  if running and settled and b.pilot_attempt_count>=PILOT_MAX_ATTEMPTS:
   stop(b,"内部pilot达到360次原field_step上限。")
  elif running and settled and int(after.get("saved_battles",0))>=PILOT_MAX_BATTLES:
   stop(b,"内部pilot达到20场已保存战斗上限。")
  if not running:return
  if initial_e2_retired:return
  if not normal_at_entry or not _normal_process(b,generation) or generation!=b._normal_process_generation:return
  if not initial_owner_at_entry or not _initial_e2_owner(b,generation,token_at_entry,initial_e2_identity):
   _initial_e2_fail(b,"初始E2 normal tick返回后归属/代次已变化。",{})
   return
  if not internal or detached or restored or phase!="loot_admission" or step.get("id")!=PILOT_STEP:
   _initial_e2_fail(b,"初始E2尚未发生但当前执行不再是原admission；不接管后继run。",{})
   return
  if b.quest_loot.ready_frame.has("continuation_gate"):return
  if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or b.quest_loot.attempt_call!=null:return
  if generation<=initial_e2_last_generation:return
  initial_e2_last_generation=generation
  b.pilot_initial_e2_last_generation=generation
  b.pilot_initial_e2_calls+=1
  var reply:Dictionary=b.quest_loot.attempt_once(b)
  if reply.get("_sample_stale",false):
   _initial_e2_fail(b,"初始E2返回stale；不触碰可能的后继run。",reply)
   return
  if not _normal_process(b,generation) or generation!=b._normal_process_generation:
   _initial_e2_fail(b,"初始E2返回时已不在同一真实normal process代。",reply)
   return
  var returned_battle:bool=bool(reply.get("battle",false))
  var returned_ready:Dictionary=b.quest_loot.ready_frame
  var expected_phase:String="loot_battle" if returned_battle else "loot_admission"
  var current_runner:bool=is_same(b.quest_auto,self) and running and internal and not detached and not restored and is_same(b.quest_loot.lifetime,initial_e2_lifetime) and is_same(initial_e2_token,token_at_entry) and identity.checkpoint()==initial_e2_identity and connection==initial_e2_connection and client==initial_e2_client and step==initial_e2_step and phase==expected_phase and returned_ready.get("identity",{})==initial_e2_identity and returned_ready.get("connection",-1)==initial_e2_connection and returned_ready.get("client","")==initial_e2_client and returned_ready.get("step",{})==initial_e2_step and is_same(returned_ready.get("ready_token"),token_at_entry) and not returned_ready.has("continuation_gate")
  if not current_runner:
   _initial_e2_fail(b,"初始E2返回后run/token归属已变化；旧调用不写后继。",reply)
   return
  if returned_battle:
   if not b.battle_open or b.session._pending.is_empty() or phase!="loot_battle":
    _initial_e2_fail(b,"初始E2返回battle但原receipt/loot_battle状态不完整。",reply)
   elif not reply.get("ok",false):
    _initial_e2_fail(b,"原battle已发生但E2返回失败；保留真实战斗现场。",reply)
   else:
    initial_e2_retired=true
    b.pilot_initial_e2_retired=true
   return
  if phase!="loot_admission" or b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():
   _initial_e2_fail(b,"初始E2未产生battle却返回到非admission状态。",reply)
   return
  if reply.get("ok",false):
   var progress:Variant=reply.get("_progress_sample",{})
   if progress is Dictionary and not progress.is_empty():
    b.quest_loot.publish_attempt_progress(b,progress)
   return
  var ready:Dictionary=b.quest_loot.ready_frame
  if is_same(ready.get("ready_token"),token_at_entry) and not ready.has("continuation_gate") and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty():
   _initial_e2_fail(b,"初始E2在原owner上拒绝；沿原同owner stop分支退出。",reply)
   stop(b,str(reply.get("reason","刷物尝试停止。")))

var host:PilotBackend
var server
var world
var pilot_started_ms:=0
var pilot_deadline_ms:=0
var pilot_e1_opened_ms:=0
var pilot_e1_anchor_ms:=-1
var pilot_peer_id:=-1
var pilot_client_peer_id:=-1
var route_destination:=Vector2i(-1,-1)
var route_search_candidates:int=0
var route_search_queries:int=0
var route_path_cells:Array=[]
var route_report_start:=0
var route_battle_count:=0
var route_walk_replans:=0
var route_search_map_cells:=0
var route_search_cell_visits:=0
var route_search_windows:=0
var candidate_search_windows:=0
var route_search_searches_baseline:=0
var route_search_cells_baseline:=0
var trace_output_bytes:=0
var trace_output_overflow:=false
func emit_pilot_trace(label:String,value:Variant)->bool:
 var encoded:String=JSON.stringify(value)
 var size:int=encoded.to_utf8_buffer().size()
 if size>MAX_TRACE_EVENT_BYTES or trace_output_bytes+size>MAX_TRACE_OUTPUT_BYTES:
  trace_output_overflow=true
  print("PILOT_TRACE_OVERFLOW ",JSON.stringify({"label":label,"event_bytes":size,"event_limit":MAX_TRACE_EVENT_BYTES,"total_bytes":trace_output_bytes,"total_limit":MAX_TRACE_OUTPUT_BYTES,"complete_record_not_emitted":true}))
  return false
 trace_output_bytes+=size
 print(label," ",encoded)
 return true
func pilot_remaining_seconds()->float:
 return maxf(0.0,float(pilot_deadline_ms-Time.get_ticks_msec())/1000.0)
func pilot_wait(condition:Callable,label:String)->bool:
 while Time.get_ticks_msec()<pilot_deadline_ms:
  if failures>0:return false
  if not pilot_trace_ok():check(false,"Pilot observation/evidence overflow or settlement/transport mismatch");return false
  if condition.call():return true
  await physics_frame
 var ok:bool=condition.call()
 check(ok,label+" before the single pilot deadline")
 return ok and failures==0
func pilot_trace_ok()->bool:
 return not trace_output_overflow and (host==null or (not host.route_trace_overflow and not host.settlement_trace_overflow and not host.settlement_failed and not host.settlement_observation_failed and not host.close_observation_failed and not host.transport_binding_changed and not host.invalid_transport_binding and not host.trace_output_overflow and not host.automation.observation_overflow and host.pilot_initial_e2_failure.is_empty()))
func request_world(command:Dictionary,label:String)->Dictionary:
 var reply:Array=[{}]
 world.link.request(command,func(value):reply[0]=value.duplicate(true))
 var arrived:bool=await pilot_wait(func():return not reply[0].is_empty(),label)
 if not arrived:return {}
 return reply[0]
func checked_pilot_disk(b,stage:String)->bool:
 var raw:Dictionary=read_disk(b.save_path)
 if failures:return false
 var backup:Dictionary=read_disk(b.save_path+".bak")
 if failures:return false
 var native:Dictionary=b.session._profile.duplicate(true)
 var normalized_native:Dictionary=b.session._normalize_numbers(native.duplicate(true))
 var primary_copy:Dictionary=ProfileCompare.validated_copy(b.session,raw.bytes.get_string_from_utf8())
 var backup_copy:Dictionary=ProfileCompare.validated_copy(b.session,backup.bytes.get_string_from_utf8())
 var cache_copy:Dictionary=ProfileCompare.validated_copy(b.session,b.last_saved_payload)
 check(primary_copy.get("ok",false) and backup_copy.get("ok",false) and cache_copy.get("ok",false) and b.session._valid_profile(native),stage+" primary/backup/cache all pass complete original profile validation")
 if failures:return false
 check(primary_copy.profile==normalized_native and cache_copy.profile==normalized_native and raw.bytes.get_string_from_utf8()==b.last_saved_payload,stage+" primary and exact writer cache match full copied native profile")
 if failures:return false
 # A rotating backup is the previous complete original profile, not a copy of current state.
 check(backup_copy.profile is Dictionary and b.session._valid_profile(backup_copy.profile),stage+" rotated backup is a complete valid prior profile")
 return failures==0
func checkpoint_world(label:String)->bool:
 var reply:Dictionary=await request_world({"type":"checkpoint","map_id":world.data.map_id,"x":world.cell.x,"y":world.cell.y},label)
 if failures:return false
 check(reply.get("ok",false),label+" uses the original checkpoint transaction")
 return failures==0
func original_yes_end(npc_id:String,label:String)->bool:
 var talk:Dictionary=await request_world({"type":"quest_talk","npc_id":npc_id},label+" original talk")
 if failures:return false
 check(talk.get("ok",false) and talk.has("dialogue"),label+" original page opens")
 if failures:return false
 var token:String=str(talk.dialogue.get("token",""))
 check(not token.is_empty(),label+" original token is captured")
 if failures:return false
 var yes:Dictionary=await request_world({"type":"quest_choose","token":token,"choice":"yes"},label+" original yes")
 if failures:return false
 check(yes.get("ok",false) and yes.has("dialogue"),label+" original yes transaction succeeds")
 if failures:return false
 var ok:Dictionary=await request_world({"type":"quest_choose","token":str(yes.dialogue.get("token",token)),"choice":"ok"},label+" original end ok")
 if failures:return false
 check(ok.get("ok",false) and host.original_quests.pending.is_empty(),label+" original end page closes")
 return failures==0
func prepare_near(npc_id:String,map_id:int,label:String)->bool:
 var travel=world.quest_helper_travel
 var required_packs:Array=world._areas.area_packs(map_id)
 check(world.asset_packs.is_ready(required_packs),"Original helper target packs are already ready, keeping the existing callback inside the single pilot deadline")
 if failures:return false
 travel.cancel()
 travel.active=true
 travel.phase="request"
 travel.target={"quest_id":-1,"id":"","mode":"near"}
 var ticket:int=travel.generation
 var reply:Array=[{}]
 world.link.request({"type":"quest_visit","npc_id":npc_id,"mode":"near","client":world._client_id},func(value:Dictionary):
  reply[0]=value.duplicate(true)
  travel._visited(reply[0],ticket)
 )
 if not await pilot_wait(func():return not reply[0].is_empty(),label+" original near helper reply"):return false
 if failures:return false
 var near_target_value:Variant=reply[0].get("target",{})
 var near_target:Dictionary=near_target_value if near_target_value is Dictionary else {}
 var near_reply_clauses:Dictionary={"ok":reply[0].get("ok",false)==true,"target_dictionary":near_target_value is Dictionary,"npc_id":near_target.get("npc_id","")==npc_id,"map_id":NumericSource.same_source(near_target.get("map_id",-1),map_id),"cell_matches_authority":NumericSource.same_source(near_target.get("cell",[]),[host.automation.position_cell.x,host.automation.position_cell.y]),"authority_map_id":host.automation.position_map==map_id}
 print("PILOT_NEAR_REPLY_OBSERVATION ",JSON.stringify({"reply":reply[0].duplicate(true),"clauses":near_reply_clauses,"authority":{"map_id":host.automation.position_map,"cell":[host.automation.position_cell.x,host.automation.position_cell.y]}}))
 check(reply[0].get("ok",false) and reply[0].get("target",{}).get("npc_id","")==npc_id and NumericSource.same_source(reply[0].get("target",{}).get("map_id",-1),map_id) and NumericSource.same_source(reply[0].get("target",{}).get("cell",[]),[host.automation.position_cell.x,host.automation.position_cell.y]),"Near helper provides only disclosed ordinary setup point: "+label)
 if failures:return false
 # The raw-NPC server helper has no quest-helper menu step to call visit() with;
 # the actual response callback invokes the existing helper's production landing consumer.
 if not await pilot_wait(func():return not travel.active and travel.report_ok and NumericSource.same_source(world.data.map_id,map_id) and NumericSource.same_source(reply[0].target.cell,[world.cell.x,world.cell.y]) and host.automation.position_map==map_id and host.automation.position_cell==world.cell and not world.moving and not world.area_transition_busy,label+" existing helper consumes response, loads scene, and receives original report ack"):return false
 var settled:bool=await Wait.settle(self,world)
 if failures or not pilot_trace_ok():return false
 return settled
func choose_safe_source_destination()->Vector2i:
 route_search_candidates=0;route_search_queries=0;route_search_cell_visits=0;route_search_windows=0;candidate_search_windows=0;route_path_cells.clear()
 var data:Dictionary=MapFile.load_map(host.quest_helper.places.file(100))
 if not host.quest_loot.admission_terrain_valid(data):
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"terrain_invalid","area":56}))
  return Vector2i(-1,-1)
 route_search_map_cells=int(data.get("width",0))*int(data.get("height",0))
 if route_search_map_cells<=0 or route_search_map_cells>MAX_MAP_CELLS or world.navigation.region.get_area()!=route_search_map_cells:
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"map_cell_bound_or_navigation_region_mismatch","map_cells":route_search_map_cells,"max_map_cells":MAX_MAP_CELLS,"nav_region_cells":world.navigation.region.get_area()}))
  return Vector2i(-1,-1)
 var occupied:Dictionary={}
 for npc in host.quest_catalog.active_npcs():
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 for npc in host.quest_helper.places.residents:
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=host.quest_helper.places.links(100)
 var candidates:Array[Vector2i]=[]
 for y in range(341,413):
  for x in range(621,646):
   var cell:=Vector2i(x,y)
   if host.encounter_catalog.area_at(100,cell).get("id")!=56 or not host.quest_helper.safe(data,cell,occupied,links):continue
   if links.has(cell) or not world.is_walkable(cell):continue
   candidates.append(cell)
 if candidates.size()>MAX_SOURCE_CELLS:
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"candidate_scan_overflow","candidate_cells":candidates.size(),"limit":MAX_SOURCE_CELLS}))
  return Vector2i(-1,-1)
 var origin:Vector2i=world.cell
 candidates.sort_custom(func(a:Vector2i,b:Vector2i)->bool:
  var da:int=absi(a.x-origin.x)+absi(a.y-origin.y)
  var db:int=absi(b.x-origin.x)+absi(b.y-origin.y)
  if da!=db:return da<db
  if a.y!=b.y:return a.y<b.y
  return a.x<b.x
 )
 var queries:=0
 route_search_candidates=candidates.size()
 route_search_cells_baseline=world.navigation.searched_cells
 route_search_searches_baseline=world.navigation.searches
 var searched_cells_before:int=route_search_cells_baseline
 var searches_before:int=route_search_searches_baseline
 for cell in candidates:
  if queries>=MAX_PATH_QUERIES:break
  if candidate_search_windows>=MAX_ASTAR_SEARCH_WINDOWS:break
  if Time.get_ticks_msec()>=pilot_deadline_ms:
   route_search_queries=queries
   route_search_candidates=candidates.size()
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"hard_deadline_before_next_astar","candidate_cells":route_search_candidates,"queries":route_search_queries,"query_limit":MAX_PATH_QUERIES,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells,"deadline_ms":HARD_LIMIT_MS}))
   return Vector2i(-1,-1)
  queries+=1
  route_search_queries=queries
  var candidate:Array=world.navigation.get_id_path(origin,cell)
  candidate_search_windows=world.navigation.searches-searches_before
  route_search_cell_visits=world.navigation.searched_cells-searched_cells_before
  route_search_windows=world.navigation.searches-route_search_searches_baseline
  if route_search_cell_visits>MAX_ASTAR_CELL_VISITS:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"astar_cell_visit_overflow","queries":queries,"search_windows":route_search_windows,"candidate_search_windows":candidate_search_windows,"searched_cells":route_search_cell_visits,"limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
   return Vector2i(-1,-1)
  if candidate_search_windows>MAX_ASTAR_SEARCH_WINDOWS or route_search_windows>MAX_ROUTE_SEARCH_WINDOWS:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"astar_window_overflow","queries":queries,"search_windows":route_search_windows,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_search_windows":candidate_search_windows,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
   return Vector2i(-1,-1)
  if Time.get_ticks_msec()>=pilot_deadline_ms:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"hard_deadline_during_bounded_astar","candidate_cells":candidates.size(),"queries":queries,"query_limit":MAX_PATH_QUERIES,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells,"deadline_ms":HARD_LIMIT_MS}))
   return Vector2i(-1,-1)
  if candidate.is_empty() or candidate.back()!=cell or candidate.size()>MAX_ROUTE_CELLS:continue
  var crosses_portal:=false
  for route_cell in candidate:
   if links.has(route_cell):crosses_portal=true;break
  if crosses_portal:continue
  route_search_queries=queries
  route_search_candidates=candidates.size()
  route_path_cells=candidate.duplicate(true)
  return cell
 route_search_queries=queries
 route_search_candidates=candidates.size()
 print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"no_reachable_safe_destination_within_bounded_queries","candidate_cells":route_search_candidates,"queries":route_search_queries,"query_limit":MAX_PATH_QUERIES,"search_windows":route_search_windows,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_search_windows":candidate_search_windows,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
 return Vector2i(-1,-1)
func continue_actual_walk(goal:Vector2i)->bool:
 var initial_map:int=int(world.data.map_id)
 check(initial_map==100 and host.automation.position_map==100,"Actual route begins on ordinary map100 after public near")
 if failures:return false
 while pilot_remaining_seconds()>0:
  if failures>0 or not pilot_trace_ok():
   check(false,"Pilot route observation remains complete during ordinary walking")
   return false
  if host.battle_open:
   if not await settle_route_battle():return false
   if not request_route_walk(goal):return false
   continue
  var reported_map:int=int(world.data.map_id)
  var projected_position:Dictionary=world.state.automation.get("position",{}).duplicate(true)
  var reported_automation_map:int=int(projected_position.get("map_id",-1))
  if reported_map!=100 or reported_automation_map!=100:
   emit_pilot_trace("PILOT_ROUTE_MAP_ASSERTION_OBSERVATION",{"clauses":{"world_data_map_is_100":reported_map==100,"client_automation_map_is_100":reported_automation_map==100},"world_data_map":reported_map,"client_automation_position":projected_position,"world_cell":[world.cell.x,world.cell.y],"authority_automation_map":host.automation.position_map,"authority_automation_cell":[host.automation.position_cell.x,host.automation.position_cell.y],"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1),"battle_open":host.battle_open,"battle_state":{"active":bool(host.battle._state.get("active",false)),"outcome":str(host.battle._state.get("outcome","")),"battle_id":str(host.battle._state.get("battle_id",""))},"pending_battle_id":str(host.session._pending.get("battle_id",""))})
   check(false,"Ordinary walk never substitutes a direct map transfer")
   return false
  if world.cell==goal and not world.moving:return true
  await physics_frame
 check(false,"Actual collision walk did not reach area56 before pilot deadline")
 return false
func request_route_walk(goal:Vector2i)->bool:
 if route_walk_replans>=MAX_ROUTE_WALK_REPLANS:
  check(false,"Actual walk replans reached the fixed cap; no extra AStar route request")
  return false
 route_walk_replans+=1
 world.walk_to(goal)
 route_search_windows=world.navigation.searches-route_search_searches_baseline
 route_search_cell_visits=world.navigation.searched_cells-route_search_cells_baseline
 if route_search_windows>MAX_ROUTE_SEARCH_WINDOWS or route_search_cell_visits>MAX_ROUTE_SEARCH_CELL_VISITS:
  check(false,"Actual route planner crossed the fixed aggregate AStar search bound")
  return false
 return true
func settle_route_battle()->bool:
 route_battle_count+=1
 var reached_route_battle_limit:bool=route_battle_count>=MAX_ROUTE_BATTLES
 var state:Dictionary=host.battle._state.duplicate(true)
 var battle_id:String=str(state.get("battle_id",""))
 check(not battle_id.is_empty() and state.get("active",false),"Route encounter is a real active original battle")
 if failures:return false
 var turns:=0
 while bool(host.battle._state.get("active",false)) and pilot_remaining_seconds()>0 and turns<100:
  var live:Dictionary=host.battle._state.duplicate(true)
  var target:=-1
  for index in range(live.get("enemies",[]).size()):
   if int(live.enemies[index].get("hp",0))>0:target=index;break
  if target<0:break
  var reply:Dictionary=await request_world({"type":"battle_command","action":"attack","target":target},"Original route battle attack")
  if failures:return false
  var reply_state:Dictionary=reply.get("state",{})
  var battle_state:Dictionary=host.battle._state
  var attack_observed:bool=emit_pilot_trace("PILOT_ROUTE_ATTACK_OBSERVATION",{"battle_id":battle_id,"reply_ok":bool(reply.get("ok",false)),"reply_state":{"active":bool(reply_state.get("active",false)),"outcome":str(reply_state.get("outcome","")),"player_hp":int(reply_state.get("player_hp",-1)),"battle_id":str(reply_state.get("battle_id",""))},"authority_state":{"active":bool(battle_state.get("active",false)),"outcome":str(battle_state.get("outcome","")),"player_hp":int(battle_state.get("player_hp",-1)),"battle_id":str(battle_state.get("battle_id",""))},"battle_open":host.battle_open,"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1)})
  check(attack_observed,"Attack observation fits the bounded pilot trace")
  if failures:return false
  check(reply.get("ok",false),"Original battle attack command accepted")
  if failures:return false
  turns+=1
 var finished:bool=not bool(host.battle._state.get("active",false))
 check(finished,"Original route battle finishes without escape/forced result")
 if failures:return false
 var closed:Dictionary=await request_world({"type":"battle_close","battle_id":battle_id},"Original route battle close")
 if failures:return false
 var closed_state:Dictionary=host.battle._state
 var close_observed:bool=emit_pilot_trace("PILOT_ROUTE_CLOSE_OBSERVATION",{"battle_id":battle_id,"reply":closed.duplicate(true),"authority_state":{"active":bool(closed_state.get("active",false)),"outcome":str(closed_state.get("outcome","")),"settled":bool(closed_state.get("settled",false)),"player_hp":int(closed_state.get("player_hp",-1)),"battle_id":str(closed_state.get("battle_id",""))},"battle_open":host.battle_open,"pending_battle_id":str(host.session._pending.get("battle_id","")),"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1),"authority_automation_map":host.automation.position_map,"authority_automation_cell":[host.automation.position_cell.x,host.automation.position_cell.y]})
 check(close_observed,"Close observation fits the bounded pilot trace")
 if failures:return false
 check(closed.get("ok",false) and not host.battle_open and host.session._pending.is_empty(),"Original route battle settles and closes normally")
 if failures:return false
 if reached_route_battle_limit:
  check(false,"Twenty route encounters reached; do not issue another walk replan or start another route battle")
  return false
 return failures==0
func activate_internal_pilot()->bool:
 var q=CappedPilotRunner.new();host.quest_auto=q
 q.identity.begin();q.identity.select_step(State.STEP)
 q.running=true;q.internal=true;q.detached=false;q.restored=false;q.phase="loot_admission"
 var server_peers:Array=server.clients()
 var client_peer=world.link._peer
 if server_peers.size()!=1 or not is_instance_valid(client_peer) or client_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN or str(world._client_id).is_empty():
  check(false,"Internal pilot has one live client link peer")
  return false
 var server_peer=server_peers[0]
 if not is_instance_valid(server_peer) or server_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN:
  check(false,"Internal pilot has one live server accepted peer")
  return false
 pilot_peer_id=server_peer.get_instance_id()
 pilot_client_peer_id=client_peer.get_instance_id()
 var observed_binding:bool=not host.transport_binding_changed and not host.invalid_transport_binding and host.received_transports.any(func(row):return row.get("valid_server_transport_binding",false)==true and str(row.get("client_id",""))==world._client_id and typeof(row.get("server_connection_id"))==TYPE_INT and int(row.get("server_connection_id"))==pilot_peer_id)
 if host.received_transports.is_empty() or not observed_binding:
  check(false,"A real command carrying this client _client_id arrived from this exact accepted server peer")
  return false
 if pilot_client_peer_id==pilot_peer_id:
  check(false,"Client WebSocketPeer and accepted server WebSocketPeer are separate objects with distinct process-local ids")
  return false
 host.client_peer_ids={"client_link_peer_id":pilot_client_peer_id,"server_accepted_peer_id":pilot_peer_id,"peer_objects_distinct":true,"client_id":world._client_id,"server_connection_id_seen_in_backend":host.received_transports[0].get("server_connection_id",-1)}
 q.connection=pilot_peer_id
 q.client=world._client_id
 q.step=Sources.step()
 var selected:Dictionary=Plan.select(host,Sources.matches_backend)
 check(selected.get("status")=="step" and Sources.same(selected.get("step"),q.step),"Independent plan and complete backend verifier accept actual safe area56 source")
 if failures:return false
 var baseline=JSON.parse_string(host.last_saved_payload)
 var native_before:Dictionary=host.session._profile.duplicate(true)
 check(baseline is Dictionary and host.session._valid_profile(baseline) and host.session._normalize_numbers(baseline)==host.session._normalize_numbers(native_before.duplicate(true)),"Complete current saved profile is the exact E1 pre-admission baseline; normalization is only on independent copies")
 if failures:return false
 var opened:Dictionary=host.quest_loot.admit_prepared_run(host)
 if failures:return false
 check(opened.get("ok",false) and opened.get("persisted",false) and host.quest_loot.anchor_ms>=0 and host.quest_auto.running and not host.battle_open,"Original E1 durable acquisition/open only after genuine route and source verification")
 if failures:return false
 check(host.session._profile.quest_loot.entries[State.STEP].limit_ms==BUDGET_MINUTES*60000 and not host.session._pending.has("quest_loot_receipt"),"Actual E1 has a persisted three-minute span and no planted receipt")
 if failures:return false
 var ready:Dictionary=host.quest_loot.ready_frame
 var token:Variant=ready.get("ready_token")
 check(not ready.is_empty() and token is RefCounted and ready.get("identity",{})==host.quest_auto.identity.checkpoint() and not ready.has("continuation_gate") and host.quest_auto.running and host.quest_auto.internal and host.quest_auto.phase=="loot_admission","Initial E1 exposes only its real un-gated internal admission frame")
 if failures:return false
 check(is_same(host.quest_auto,q),"The original candidate runner still owns the E1 frame")
 if failures:return false
 host.pilot_initial_runner=weakref(q)
 q.initial_e2_token=token
 q.initial_e2_lifetime=host.quest_loot.lifetime
 q.initial_e2_identity=q.identity.checkpoint()
 q.initial_e2_connection=q.connection
 q.initial_e2_client=q.client
 q.initial_e2_step=q.step.duplicate(true)
 q.initial_e2_generation_floor=host._normal_process_generation
 q.initial_e2_last_generation=q.initial_e2_generation_floor
 host.pilot_initial_e2_generation_floor=q.initial_e2_generation_floor
 host.pilot_initial_e2_last_generation=q.initial_e2_generation_floor
 host.pilot_initial_e2_connection=q.initial_e2_connection
 host.pilot_initial_e2_client=q.initial_e2_client
 pilot_e1_opened_ms=Time.get_ticks_msec()
 pilot_e1_anchor_ms=host.quest_loot.anchor_ms
 check(pilot_e1_anchor_ms>=0 and pilot_e1_opened_ms>=pilot_e1_anchor_ms and pilot_e1_generation_ok(q),"E1 records read-only monotonic open time/anchor without sampling the timer")
 return failures==0
func pilot_e1_generation_ok(q:CappedPilotRunner)->bool:
 return q.initial_e2_generation_floor==host._normal_process_generation and q.initial_e2_last_generation==q.initial_e2_generation_floor
func pilot_initial_runner_is_current()->bool:
 if host.pilot_initial_runner==null:return false
 var original=host.pilot_initial_runner.get_ref()
 return is_instance_valid(original) and is_same(host.quest_auto,original)
func source_snapshot()->Dictionary:
 var entry:Dictionary=host.session._profile.quest_loot.entries.get(State.STEP,{})
 var baseline=JSON.parse_string(host.last_saved_payload)
 var profile:Dictionary=host.session._profile.duplicate(true)
 var cache_copy:Dictionary=ProfileCompare.validated_copy(host.session,host.last_saved_payload)
 var cache_matches:bool=baseline is Dictionary and host.session._valid_profile(baseline) and cache_copy.get("ok",false) and cache_copy.profile==host.session._normalize_numbers(profile.duplicate(true))
 return {"source":Sources.source(),"plan":Plan.select(host,Sources.matches_backend),"position":{"map":host.automation.position_map,"cell":[host.automation.position_cell.x,host.automation.position_cell.y],"area":host.encounter_catalog.area_at(host.automation.position_map,host.automation.position_cell).get("id",-1)},"entry":entry.duplicate(true),"profile":profile,"profile_valid":host.session._valid_profile(profile),"cache_valid_and_matches_profile":cache_matches,"cache":host.last_saved_payload,"serial":host.quest_save_serial,"server_peer_id":pilot_peer_id,"client_peer_id":pilot_client_peer_id,"transport_binding":host.client_peer_ids,"attempts":host.pilot_attempt_count,"saved_battles":entry.get("saved_battles",0),"new_items":entry.get("new_items",0),"running":host.quest_auto.running,"phase":host.quest_auto.phase,"battle_open":host.battle_open,"pending":host.session._pending.duplicate(true),"settlement":host.session._loot_settlement.duplicate(true),"p3":{"normal_ticks":host.automation.normal_ticks,"all_normal_active_ticks":host.automation.all_normal_active_ticks,"loot_receipt_active_after_automation_tick":host.automation.loot_receipt_active_ticks,"normal_tick_limit":MAX_NORMAL_TICKS,"transition_count":host.automation.transitions.size(),"transition_limit":MAX_NORMAL_TRANSITIONS,"active_entry_sample_count":host.automation.active_entry_samples.size(),"active_entry_sample_limit":MAX_ACTIVE_ENTRY_SAMPLES,"records":"bounded complete state-change/active-entry events; not a per-frame history","recent_transitions":host.automation.transitions.slice(maxi(0,host.automation.transitions.size()-8)),"recent_active_entries":host.automation.active_entry_samples.slice(maxi(0,host.automation.active_entry_samples.size()-8)),"initial_e2_calls":host.pilot_initial_e2_calls,"initial_e2_failure":host.pilot_initial_e2_failure,"initial_e2_retired":host.pilot_initial_e2_retired,"initial_e2_generation_floor":host.pilot_initial_e2_generation_floor,"initial_e2_last_generation":host.pilot_initial_e2_last_generation,"initial_runner_is_current":pilot_initial_runner_is_current()},"field_step_count":host.field_steps.size(),"settlement_commit_count":host.settlement_commits.size(),"closed_receipt_count":host.closed_receipts.size(),"retired_battle_count":host.retired_battles.size(),"close_attempt_count":host.close_attempts.size(),"route_report_count":host.route_reports.size(),"route_battle_count":route_battle_count,"route_walk_replans":route_walk_replans,"trace_output":{"backend_bytes":host.trace_output_bytes,"backend_limit":host.PILOT_MAX_TRACE_OUTPUT_BYTES,"test_bytes":trace_output_bytes,"test_limit":MAX_TRACE_OUTPUT_BYTES},"route_search":{"candidate_cells":route_search_candidates,"astar_queries":route_search_queries,"candidate_search_windows":candidate_search_windows,"astar_search_windows":route_search_windows,"astar_searched_cells":route_search_cell_visits,"map_cells":route_search_map_cells,"path_cells":route_path_cells}}
func run()->void:
 pilot_started_ms=Time.get_ticks_msec();pilot_deadline_ms=pilot_started_ms+HARD_LIMIT_MS
 var path:String=DISK_PATH
 if FileAccess.file_exists(UNCOMPLETE_PATH) or DirAccess.dir_exists_absolute(UNCOMPLETE_PATH):
  check(false,"Refuse a reused hard-deadline evidence path")
  quit(1);return
 if not fresh_paths(path):quit(1);return
 host=PilotBackend.new();host.save_path=path;host.automation=PassiveAutomation.new(host)
 root.add_child(host)
 check(host.automation.auto_tick and not host.keep_resume_current,"Pilot inherits original auto cadence and default non-resume test-host behavior")
 if failures:quit(1);return
 check(host.session.gm_raise_level(-1,60),"Disclosed GM fixture raises only the original scholar level gate")
 if failures:quit(1);return
 var allocation_before:Dictionary=host.session._profile.duplicate(true)
 check(host.session._pending.is_empty() and int(allocation_before.player.get("stat_points",-1))==177,"Level60 grants 177 normal stat points before any battle; allocation starts outside combat")
 if failures:quit(1);return
 var distributed:bool=host.session.distribute_stats(["vitality","strength","toughness"])
 check(distributed,"Spend the 177 earned points through the original even-distribution API")
 if failures:quit(1);return
 var allocation_after:Dictionary=host.session._profile.duplicate(true)
 check(allocation_after.player.allocated_stats=={"vitality":59,"strength":59,"toughness":59,"dexterity":0} and int(allocation_after.player.stat_points)==0,"Original allocation API assigns exactly 59 each to vitality/strength/toughness and leaves zero points")
 if failures:quit(1);return
 check(allocation_after.player.base_stats=={"vitality":6800,"strength":6600,"toughness":5900,"dexterity":400} and int(allocation_after.player.hp)==401 and int(allocation_after.player.max_hp)==401 and int(allocation_after.player.attack)==78 and int(allocation_after.player.defence)==72 and int(allocation_after.player.speed)==4,"Original progression derives expected profile after three 59-point allocations")
 if failures:quit(1);return
 var allocation_before_rest:Dictionary=allocation_before.duplicate(true)
 var allocation_after_rest:Dictionary=allocation_after.duplicate(true)
 for profile in [allocation_before_rest,allocation_after_rest]:
  for field in ["allocated_stats","base_stats","stat_points","hp","max_hp","attack","defence","speed"]:profile.player.erase(field)
 check(allocation_before_rest==allocation_after_rest,"Complete profile before/after differs only in fields changed by allocate_stat/Progression")
 if failures:quit(1);return
 print("PILOT_NORMAL_STAT_ALLOCATION ",JSON.stringify({"before_points":allocation_before.player.stat_points,"allocated":allocation_after.player.allocated_stats,"remaining_points":allocation_after.player.stat_points,"base_stats":allocation_after.player.base_stats,"hp":allocation_after.player.hp,"max_hp":allocation_after.player.max_hp,"attack":allocation_after.player.attack,"defence":allocation_after.player.defence,"speed":allocation_after.player.speed}))
 check(host.save(),"Fresh complete profile saved before original scholar request")
 if failures:quit(1);return
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Actual isolated port-zero WebSocket host")
 if failures:quit(1);return
 Game.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();Game.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://loot-2760-pilot-view.cfg";root.add_child(world)
 if not await pilot_wait(func():return world.link.online and not world.data.is_empty(),"Actual remote GameScene connects"):quit(1);return
 host.expected_client_id=world._client_id
 check(world.backend==null and await Wait.settle(self,world),"The walking client has no Backend and completes a real ping roundtrip")
 if failures:quit(1);return
 var settings:Dictionary=await request_world({"type":"set_automation_settings","settings":{"quest":{"loot_minutes":BUDGET_MINUTES}}},"Persist disclosed three-minute pilot setting")
 if failures:quit(1);return
 check(settings.get("ok",false),"Original settings writer accepts the bounded pilot budget")
 if failures:quit(1);return
 if not await prepare_near(SCHOLAR,6000,"Scholar prerequisite convenience"):quit(1);return
 var scholar:Dictionary=host.original_quests.npc_by_id(SCHOLAR)
 check(not scholar.is_empty() and scholar.map_id==6000 and NumericSource.same_source(scholar.cell,[58,44]) and scholar.source_script=="extra/event/hougyoku","Frozen scholar source identity")
 if failures:quit(1);return
 check(scholar.branches[1].type=="REQUEST" and scholar.branches[1].condition=="LV>59" and scholar.branches[1].actions=={"GetItem":"2764*1"},"Original scholar REQUEST=yes is the only 2764 grant")
 if failures:quit(1);return
 if not await original_yes_end(SCHOLAR,"Scholar 2764 prerequisite"):quit(1);return
 check(host.session._profile.original_items.count(2764)==1 and Rules.flag(host.session._profile,"now",45) and host.session._profile.original_instances.any(func(row):return int(row.get("item_id",-1))==2764),"Actual saved original REQUEST grants one UID-backed 2764 and NOW45")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual scholar completion"):quit(1);return
 var before_mhasah:Dictionary=host.session._profile.duplicate(true)
 if not await prepare_near(GENOU,100,"Map100 Mhasah setup convenience"):quit(1);return
 check(before_mhasah.original_items.count(2764)==1 and host.session._profile.original_items.count(2764)==1 and host.session._profile.original_instances==before_mhasah.original_instances,"Second near setup grants no source proof or item")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual map100 starting cell"):quit(1);return
 var position_start:Vector2i=world.cell
 route_destination=choose_safe_source_destination()
 check(route_destination.x>=0 and host.automation.position_map==100 and host.automation.position_cell==position_start and host.encounter_catalog.area_at(100,route_destination).get("id")==56,"Safe reachable area56 destination chosen from actual map collision/path data")
 if failures:quit(1);return
 check(world.random_encounters and not host.session._profile.no_random_encounters,"Original map walking encounters remain enabled; no safe bypass")
 if failures:quit(1);return
 route_report_start=host.route_reports.size()
 host.route_trace_enabled=true
 check(emit_pilot_trace("PILOT_ROUTE_START",{"map":100,"from":[position_start.x,position_start.y],"to":[route_destination.x,route_destination.y],"area":host.encounter_catalog.area_at(100,route_destination),"route_cells":route_path_cells.map(func(cell):return [cell.x,cell.y]),"map_cells":route_search_map_cells,"astar_queries":route_search_queries,"candidate_search_windows":candidate_search_windows,"astar_search_windows":route_search_windows,"astar_searched_cells":route_search_cell_visits,"candidate_cells":route_search_candidates,"candidate_scan_limit":MAX_SOURCE_CELLS,"astar_query_limit":MAX_PATH_QUERIES,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_cell_visit_limit":MAX_ASTAR_CELL_VISITS,"route_cell_visit_limit":MAX_ROUTE_SEARCH_CELL_VISITS,"route_replan_limit":MAX_ROUTE_WALK_REPLANS,"route_battle_limit":MAX_ROUTE_BATTLES,"near_convenience":GENOU,"near_not_route_proof":true}),"Complete bounded route evidence fits output limit")
 if failures:quit(1);return
 if not request_route_walk(route_destination):quit(1);return
 if not await continue_actual_walk(route_destination):quit(1);return
 check(world.cell==route_destination and host.automation.position_map==100 and host.automation.position_cell==route_destination,"Every final route cell arrived through normal report_position/field_step authority")
 if failures:quit(1);return
 var route_reports:Array=host.route_reports.slice(route_report_start)
 var route_reports_valid:bool=not route_reports.is_empty()
 for row in route_reports:
  var command:Dictionary=row.command
  var authority:Dictionary=row.authority
  if not bool(row.get("reply_ok",false)) or bool(command.get("map_changed",false)) or not NumericSource.same_source(command.get("map_id",-1),100) or not NumericSource.same_source(authority.get("map",-1),100) or not NumericSource.same_source(command.get("cell",[]),authority.get("cell",[])):route_reports_valid=false
 var final_route_report_matches:bool=not route_reports.is_empty() and NumericSource.same_source(route_reports.back().authority.cell,[route_destination.x,route_destination.y])
 check(route_reports_valid and final_route_report_matches,"Every post-start route report was an ordinary same-map position accepted at the identical backend cell")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual walked source-area checkpoint"):quit(1);return
 var source_pre:Dictionary=source_snapshot()
 check(int(source_pre.position.area)==56 and source_pre.profile.original_items.count(2764)==1 and not source_pre.profile.original_items.has(2760) and source_pre.profile_valid,"Actual area56, original prerequisite and complete native/cache baseline before E1")
 if failures:quit(1);return
 if not checked_pilot_disk(host,"source-before-open"):quit(1);return
 if not archive_pair(host,"source-before-open"):quit(1);return
 if not activate_internal_pilot():quit(1);return
 var e1_timing:Dictionary={"pilot_started_ms":pilot_started_ms,"e1_opened_ms":pilot_e1_opened_ms,"e1_anchor_ms":pilot_e1_anchor_ms,"setup_elapsed_ms":pilot_e1_opened_ms-pilot_started_ms,"outer_ms_remaining_at_e1":maxi(0,pilot_deadline_ms-pilot_e1_opened_ms),"original_budget_ms":BUDGET_MINUTES*60000,"budget_elapsed_at_e1_ms":pilot_e1_opened_ms-pilot_e1_anchor_ms,"original_budget_remaining_at_e1_ms":maxi(0,BUDGET_MINUTES*60000-(pilot_e1_opened_ms-pilot_e1_anchor_ms))}
 e1_timing.post_budget_outer_margin_ms=e1_timing.outer_ms_remaining_at_e1-e1_timing.original_budget_remaining_at_e1_ms
 check(emit_pilot_trace("PILOT_E1_OPEN_TIMING",e1_timing),"Read-only monotonic E1 timing fits bounded evidence")
 if failures:quit(1);return
 check(emit_pilot_trace("PILOT_E1_OPEN",source_snapshot()),"Complete E1 state evidence fits output limit")
 if failures:quit(1);return
 if not checked_pilot_disk(host,"e1-open") or not archive_pair(host,"e1-open"):quit(1);return
 host.automation.begin_observation()
 host.automation.observe_loot_run=true
 while pilot_remaining_seconds()>0:
  if failures:quit(1);return
  if not pilot_trace_ok():check(false,"Bounded pilot instrumentation preserves all records without overflow");quit(1);return
  var entry:Dictionary=host.session._profile.quest_loot.entries.get(State.STEP,{})
  var attempts:int=host.pilot_attempt_count
  if not host.quest_auto.running and not host.battle_open and host.session._pending.is_empty() and host.session._loot_settlement.is_empty():break
  if attempts>=MAX_ATTEMPTS or int(entry.get("saved_battles",0))>=MAX_BATTLES:
   if not host.battle_open and host.session._pending.is_empty() and host.session._loot_settlement.is_empty():break
  await physics_frame
 var hard_expired:bool=Time.get_ticks_msec()>=pilot_deadline_ms
 var unsettled_at_deadline:bool=host.quest_auto.running or host.battle_open or not host.session._pending.is_empty() or not host.session._loot_settlement.is_empty()
 if hard_expired and not unsettled_at_deadline:
  # Do not run the full source/profile/disk audit beyond the single hard wall.
  # There is no open battle to preserve, but the bounded result was not verified.
  var observed_ms:int=Time.get_ticks_msec()
  print("PILOT_FINAL ",JSON.stringify({"elapsed_ms":observed_ms-pilot_started_ms,"hard_unfinished":false,"result":"DEADLINE_REACHED_BEFORE_FINAL_VERIFICATION","settled":true,"e1_anchor_ms":pilot_e1_anchor_ms,"e1_elapsed_ms":observed_ms-pilot_e1_anchor_ms,"e1_budget_remaining_ms":maxi(0,BUDGET_MINUTES*60000-(observed_ms-pilot_e1_anchor_ms)),"outer_remaining_ms":maxi(0,pilot_deadline_ms-observed_ms)}))
  check(false,"Single hard deadline leaves time for the complete final verification")
  quit(1);return
 if hard_expired and unsettled_at_deadline:
  # The hard window is also a hard evidence boundary: avoid another source/plan
  # verification or copying the growing observer trace after it has expired.
  # This is read-only and deliberately leaves the original open receipt untouched.
  var cutoff:=_hard_cutoff_observation()
  var cutoff_trace_ok:bool=emit_pilot_trace("PILOT_FINAL",{"elapsed_ms":Time.get_ticks_msec()-pilot_started_ms,"hard_unfinished":true,"result":"UNCOMPLETE","cutoff":cutoff})
  var evidence_text:String=JSON.stringify(cutoff)
  var evidence_bytes:PackedByteArray=evidence_text.to_utf8_buffer()
  if evidence_bytes.size()>MAX_UNCOMPLETE_EVIDENCE_BYTES:
   print("PILOT_UNCOMPLETE_WRITE_FAILED ",JSON.stringify({"path":UNCOMPLETE_PATH,"reason":"evidence_size_limit","actual":evidence_bytes.size(),"limit":MAX_UNCOMPLETE_EVIDENCE_BYTES}))
   check(false,"Hard cutoff evidence remains complete within the fixed byte limit")
   quit(1);return
  var evidence=FileAccess.open(UNCOMPLETE_PATH,FileAccess.WRITE)
  var evidence_open_error:int=FileAccess.get_open_error()
  if evidence==null:
   print("PILOT_UNCOMPLETE_WRITE_FAILED ",JSON.stringify({"path":UNCOMPLETE_PATH,"open_error":evidence_open_error}))
   check(false,"Hard cutoff evidence file opens at the single reserved path")
   quit(1);return
  evidence.store_buffer(evidence_bytes);evidence.flush()
  var evidence_write_error:int=evidence.get_error();evidence.close()
  if evidence_open_error!=OK or evidence_write_error!=OK:
   print("PILOT_UNCOMPLETE_WRITE_FAILED ",JSON.stringify({"path":UNCOMPLETE_PATH,"open_error":evidence_open_error,"write_error":evidence_write_error}))
   check(false,"Hard cutoff evidence flush succeeds without retry")
   quit(1);return
  var evidence_read:Dictionary=read_disk(UNCOMPLETE_PATH)
  if failures:quit(1);return
  check(evidence_read.get("ok",false) and evidence_read.bytes.get_string_from_utf8()==evidence_text,"Hard cutoff evidence reads back exact bytes from the same reserved path")
  if failures:quit(1);return
  check(cutoff_trace_ok,"Full hard-cutoff trace fits the bounded output without truncation")
  if failures:quit(1);return
  check(false,"Hard pilot deadline arrived before original receipt settlement; preserve pending and report UNCOMPLETE")
  quit(1);return
 var final:Dictionary=source_snapshot()
 var final_observed_ms:int=Time.get_ticks_msec()
 check(host.pilot_initial_e2_calls>0 and host.pilot_attempt_count>0,"The real initial E1 was consumed by test-only E2 and reached an original field_step")
 if failures:quit(1);return
 check(emit_pilot_trace("PILOT_FINAL",{"elapsed_ms":final_observed_ms-pilot_started_ms,"hard_unfinished":false,"result":"BOUNDED_FINISH","e1_anchor_ms":pilot_e1_anchor_ms,"e1_elapsed_ms":final_observed_ms-pilot_e1_anchor_ms,"e1_budget_remaining_ms":maxi(0,BUDGET_MINUTES*60000-(final_observed_ms-pilot_e1_anchor_ms)),"outer_remaining_ms":maxi(0,pilot_deadline_ms-final_observed_ms),"final":final}),"Complete final profile/cache/ledger summary fits output limit")
 if failures:quit(1);return
 check(host.quest_auto.running==false and pilot_initial_runner_is_current() and not host.battle_open and host.session._pending.is_empty() and host.session._loot_settlement.is_empty(),"Bounded pilot stopped only after no original receipt remains and the original runner still owns the result")
 if failures:quit(1);return
 if not archive_pair(host,"pilot-final") or not checked_pilot_disk(host,"pilot-final"):quit(1);return
 var actual_received:=0
 for row in host.closed_receipts:
  var result:Variant=row.get("result",null)
  if not result is Dictionary or not result.get("drop_summary",null) is Array:
   host.settlement_observation_failed=true
   continue
  for drop in result.drop_summary:
   if not drop is Dictionary:
    host.settlement_observation_failed=true
    continue
   if int(drop.get("item_id",-1))==2760 and drop.get("received",false)==true:actual_received+=1
 check(not host.settlement_observation_failed,"Every retired receipt retains its original result.drop_summary")
 if failures:quit(1);return
 var entry:Dictionary=host.session._profile.quest_loot.entries[State.STEP]
 check(host.settlement_commits.size()==host.retired_battles.size() and host.retired_battles.size()==host.closed_receipts.size() and entry.saved_battles==host.settlement_commits.size() and entry.new_items==actual_received and entry.saved_battles<=MAX_BATTLES and host.pilot_attempt_count<=MAX_ATTEMPTS,"Each actual _after_turn receipt commit is retired once; close does not invent counts and only actual received 2760 drops are counted")
 if failures:quit(1);return
 check(host.session._profile.original_items.count(2760)==actual_received and host.session._profile.original_instances.filter(func(row):return int(row.get("item_id",-1))==2760).size()==actual_received,"Only actual original received drops create matching UID-backed item instances")
 if failures:quit(1);return
 var attempt_rows:Array=host.field_steps.filter(func(row):return bool(row.get("attempt",false)))
 var actual_attempts:bool=attempt_rows.size()==host.pilot_attempt_count
 for row in attempt_rows:
  if int(row.get("map",-1))!=100 or int(row.get("area",-1))!=56:actual_attempts=false
  if bool(row.get("reply",{}).get("battle",false)) and (not row.get("receipt",{}) is Dictionary or row.get("receipt",{}).is_empty() or str(row.get("pending_battle_id",""))!=str(row.get("receipt",{}).get("ledger",{}).get("battle_id",""))):actual_attempts=false
 check(actual_attempts,"Every counted E2 attempt used the actual area56 field_step and any battle is bound to its returned original receipt")
 if failures:quit(1);return
 check(emit_pilot_trace("PILOT_DROP_RESULT",{"target_2760_received":actual_received,"inventory_count":host.session._profile.original_items.count(2760),"saved_battles":entry.saved_battles,"attempts":host.pilot_attempt_count,"plan_after_pilot":Plan.select(host,Sources.matches_backend),"backend_trace_bytes":host.trace_output_bytes,"backend_trace_limit":host.PILOT_MAX_TRACE_OUTPUT_BYTES,"test_trace_bytes":trace_output_bytes,"test_trace_limit":MAX_TRACE_OUTPUT_BYTES}),"Complete drop result fits aggregate stream limits")
 if failures:quit(1);return
 print("QUEST AUTO LOOT 2760 NATURAL PILOT: %d failures; actual near setup + collision walk; no selected group/seed/drop; P3 active loot-receipt samples=%d (zero means P3 UNPROVEN)"%[failures,host.automation.loot_receipt_active_ticks])
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 server.stop();server.queue_free();host.queue_free()
 await process_frame
 quit(1 if failures else 0)

func _hard_cutoff_observation()->Dictionary:
 var entry:Dictionary=host.session._profile.quest_loot.entries.get(State.STEP,{})
 var profile:Dictionary=host.session._profile.duplicate(true)
 var baseline=JSON.parse_string(host.last_saved_payload)
 var native_valid:bool=host.session._valid_profile(profile)
 var native_normalized:Dictionary=host.session._normalize_numbers(profile.duplicate(true)) if native_valid else {}
 var cache_copy:Dictionary=ProfileCompare.validated_copy(host.session,host.last_saved_payload)
 var primary:Dictionary=host._capture_disk(host.save_path)
 var backup:Dictionary=host._capture_disk(host.save_path+".bak")
 var transitions:Array=host.automation.transitions
 var recent_transitions:Array=transitions.slice(maxi(0,transitions.size()-8))
 var active_entries:Array=host.automation.active_entry_samples
 var recent_active_entries:Array=active_entries.slice(maxi(0,active_entries.size()-8))
 var observed_ms:int=Time.get_ticks_msec()
 var retired_summary:Array=[]
 for row in host.retired_battles:
  var commit:Dictionary=row.get("settlement_commit",{})
  retired_summary.append({"battle_id":row.get("battle_id",""),"outcome":row.get("outcome",""),"commit_seen":row.get("commit_seen_before_close",false),"saved_before_close":row.get("saved_battles_before_close",-1),"saved_after_close":row.get("saved_battles_after_close",-1),"received_target":commit.get("received_target",-1),"result":commit.get("result",{}),"primary":commit.get("primary",{}),"backup":commit.get("backup",{})})
 return {"source":"PILOT_HARD_CUTOFF_READ_ONLY_NO_SETTLEMENT_OR_CLEANUP","elapsed_ms":observed_ms-pilot_started_ms,"deadline_ms":pilot_deadline_ms-pilot_started_ms,"e1_anchor_ms":pilot_e1_anchor_ms,"e1_elapsed_ms":observed_ms-pilot_e1_anchor_ms,"e1_budget_remaining_ms":maxi(0,BUDGET_MINUTES*60000-(observed_ms-pilot_e1_anchor_ms)),"outer_remaining_ms":maxi(0,pilot_deadline_ms-observed_ms),"attempts":host.pilot_attempt_count,"profile":profile,"profile_valid":native_valid,"cache":host.last_saved_payload,"cache_valid_and_matches_profile":baseline is Dictionary and cache_copy.get("ok",false) and cache_copy.profile==native_normalized,"serial":host.quest_save_serial,"entry":entry.duplicate(true),"pending":host.session._pending.duplicate(true),"settlement":host.session._loot_settlement.duplicate(true),"primary":{"ok":primary.get("ok",false),"path":host.save_path,"open_error":primary.get("open_error",-1),"length_error":primary.get("length_error",-1),"read_error":primary.get("read_error",-1),"declared":primary.get("declared",-1),"actual":primary.get("actual",-1),"sha256":primary.get("sha256","")},"backup":{"ok":backup.get("ok",false),"path":host.save_path+".bak","open_error":backup.get("open_error",-1),"length_error":backup.get("length_error",-1),"read_error":backup.get("read_error",-1),"declared":backup.get("declared",-1),"actual":backup.get("actual",-1),"sha256":backup.get("sha256","")},"battle_open":host.battle_open,"battle":host.battle._state.duplicate(true),"q":{"running":host.quest_auto.running,"phase":host.quest_auto.phase,"identity":host.quest_auto.identity.snapshot(),"connection":host.quest_auto.connection,"step":host.quest_auto.step.duplicate(true),"attempt_call_active":host.quest_loot.attempt_call!=null},"p3":{"normal_ticks":host.automation.normal_ticks,"all_normal_active_ticks":host.automation.all_normal_active_ticks,"loot_receipt_active_after_automation_tick":host.automation.loot_receipt_active_ticks,"normal_tick_limit":MAX_NORMAL_TICKS,"transitions_recorded":transitions.size(),"transition_limit":MAX_NORMAL_TRANSITIONS,"recent_transitions":recent_transitions,"active_entry_samples_recorded":active_entries.size(),"active_entry_sample_limit":MAX_ACTIVE_ENTRY_SAMPLES,"recent_active_entry_samples":recent_active_entries,"records":"bounded complete state-change/active-entry events; not a per-frame history","initial_e2_calls":host.pilot_initial_e2_calls,"initial_e2_failure":host.pilot_initial_e2_failure,"initial_e2_retired":host.pilot_initial_e2_retired,"initial_e2_generation_floor":host.pilot_initial_e2_generation_floor,"initial_e2_last_generation":host.pilot_initial_e2_last_generation,"initial_runner_is_current":pilot_initial_runner_is_current()},"retired_battles":retired_summary}
