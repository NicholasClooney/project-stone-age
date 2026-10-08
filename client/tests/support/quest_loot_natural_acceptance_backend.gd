extends "res://server/backend.gd"
## Static-only acceptance observer. Extracted receipt/collision oracles are cited
## in the companion report; no old natural run(), CappedPilotRunner or clock seam.
const PilotState=preload("res://server/quest_auto_loot_state.gd")
const Compare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const ACCEPTANCE_MAX_ATTEMPTS:=3601
const ACCEPTANCE_MAX_BATTLES:=3601
const PILOT_MAX_ROUTE_REPORTS:=4096
const PILOT_MAX_PROFILE_DISK_BYTES:=262144
const Store=preload("res://tests/support/quest_loot_acceptance_evidence.gd")
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
var pilot_attempt_count:=0
var trace_output_bytes:=0
var trace_output_overflow:=false
var trace_count:=0
var changed_writer_count:=0
var terminal_turn_count:=0
var active_turn_count:=0
var evidence:Store
var e1_record:Dictionary={}
var writer_count:=0
var initial_encounter_seed:=""
var initial_encounter_state:=""
var disk_primary_expected:=""
var disk_backup_expected:=""
var p3_publications:=0
var last_publication_revision:=-1
var p3_queued:Array[Dictionary]=[]
var observation_failed:=false

class NaturalTimer:
 extends "res://server/quest_auto_loot.gd"
 var accepted_active:=0
 var owner_accepts:=0
 var sample_ids:Dictionary={}
 var previous_sample_ms:=-1
 var previous_used_ms:=-1
 var previous_generation:=-1
 var observation_failed:=false
 func heartbeat_owner_current(b,generation:int,entry_epoch:int)->bool:
  var accepted:bool=super.heartbeat_owner_current(b,generation,entry_epoch)
  if accepted:owner_accepts+=1
  return accepted
 func heartbeat_normal_process(b,generation:int,entry_epoch:int)->void:
  # Exactly one original call. No duplicate, nested call, clock replacement or pause.
  var old_last:int=last_ms
  var old_stamp:Dictionary=progress_stamp
  var old_serial:int=b.quest_save_serial
  var old_payload:String=b.last_saved_payload
  var old_writer:int=b.writer_count
  var old_revision:int=b.rev
  var owner:RefCounted=lifetime
  var receipt:Dictionary=battle_receipt
  var raw:Dictionary=b.battle._state
  var active:bool=raw.get("active",false) and b.battle_open and receipt==b.session._pending.get("quest_loot_receipt",{}) and not receipt.is_empty()
  var battle_id:String=str(raw.get("battle_id",""))
  super.heartbeat_normal_process(b,generation,entry_epoch)
  if last_ms==old_last:return
  if not active or heartbeat_generation!=generation or not is_same(owner,lifetime) or cached_sample.get("span",{})!=span or not is_same(cached_sample.get("lifetime"),lifetime) or str(receipt.get("ledger",{}).get("battle_id",""))!=battle_id:
   observation_failed=true
   return
  if last_ms<=previous_sample_ms or int(cached_sample.get("used_ms",-1))<=previous_used_ms or generation<=previous_generation or b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1:observation_failed=true
  previous_sample_ms=last_ms;previous_used_ms=int(cached_sample.get("used_ms",-1));previous_generation=generation
  accepted_active+=1
  sample_ids[battle_id]=true
  if accepted_active>2401 or b.quest_save_serial!=old_serial or b.last_saved_payload!=old_payload or b.writer_count!=old_writer:observation_failed=true
  var published:bool=progress_stamp!=old_stamp
  var row:Dictionary={"generation":generation,"entry_epoch":entry_epoch,"dispatch_epoch":b._dispatch_epoch,"battle_id":battle_id,"run":b.quest_auto.identity.checkpoint(),"span":span.duplicate(true),"connection":b.quest_auto.connection,"sample_ms":last_ms,"used_ms":cached_sample.get("used_ms",-1),"revision_before":old_revision,"revision_after":b.rev,"serial":old_serial,"writer_count":old_writer,"published":published,"call_retired":heartbeat_call==null,"raw_active":active,"view_battle_id":b.battle_state.get("battle_id",""),"turn":raw.get("turn",-1)}
  if not b.trace_event("ACCEPTANCE_P3_SAMPLE",row):observation_failed=true
  if published:
   if b.p3_queued.size()>=1 or b.rev!=old_revision+1:observation_failed=true
   else:b.p3_queued.append(row)

func _init()->void:
 super()
 initial_encounter_seed=str(encounter_rng.seed)
 initial_encounter_state=str(encounter_rng.state)
 quest_loot=NaturalTimer.new()
 event.connect(_observe_publication)
func _quest_loot_public_enabled()->bool:return true
func open_evidence(path:String)->bool:
 evidence=Store.new()
 return evidence.open(path)
func trace_event(label:String,value:Variant)->bool:
 if trace_output_overflow:return false
 if evidence==null or not evidence.append(label,value):
  trace_output_overflow=true
  return false
 trace_output_bytes=evidence.event_bytes
 trace_count=evidence.event_count
 return true
func _observe_publication(message:Dictionary)->void:
 if message.get("type")!="profile" or p3_queued.is_empty():return
 var expected:Dictionary=p3_queued[0]
 if int(message.get("rev",-1))<int(expected.revision_after):return # Earlier ordinary publication in the same original queue.
 var row:Dictionary=p3_queued.pop_front()
 var valid:bool=message.get("rev",-1)==row.revision_after and message.get("rev",-1)>last_publication_revision and quest_loot.heartbeat_call==null and quest_loot.last_ms==row.sample_ms and quest_loot.span==row.span and quest_save_serial==row.serial and writer_count==row.writer_count
 if not valid:observation_failed=true
 last_publication_revision=int(message.get("rev",-1));p3_publications+=1
 if not trace_event("ACCEPTANCE_P3_PUBLICATION",{"sample":row,"event_revision":message.get("rev",-1),"owner_current":valid,"observer_depth":_observer_depth}):observation_failed=true
func _writer_observed(kind:String,before:String)->void:
 writer_count+=1
 if last_saved_payload!=before or kind=="loot_settlement_written":
  disk_backup_expected=before
  disk_primary_expected=last_saved_payload
 if evidence!=null:
  if last_saved_payload!=before or kind=="loot_settlement_written":
   changed_writer_count+=1
   if changed_writer_count>32768:observation_failed=true
  if last_saved_payload.to_utf8_buffer().size()>PILOT_MAX_PROFILE_DISK_BYTES:observation_failed=true
  var row:Dictionary={"kind":kind,"ordinal":writer_count,"serial":quest_save_serial,"changed":last_saved_payload!=before,"primary_sha256":disk_primary_expected.sha256_text(),"backup_sha256":disk_backup_expected.sha256_text()}
  if last_saved_payload!=before or kind=="loot_settlement_written":
   row.payload=evidence.blob(last_saved_payload.to_utf8_buffer(),"profile","utf8")
   row.previous_payload=evidence.blob(before.to_utf8_buffer(),"profile","utf8")
  if not trace_event("ACCEPTANCE_WRITER",row):observation_failed=true
func _save_profile_boundary(checkpoint:Dictionary={})->bool:
 var before:String=last_saved_payload
 var ok:bool=super._save_profile_boundary(checkpoint)
 if ok:_writer_observed("save_profile_boundary",before)
 return ok
func _loot_settlement_written(payload:String,owner,path:String)->void:
 var before:String=last_saved_payload
 var valid:bool=is_same(session,owner) and save_path==path
 super._loot_settlement_written(payload,owner,path)
 if valid:_writer_observed("loot_settlement_written",before)
func _cmd_quest_loot_start(command:Dictionary)->Dictionary:
 var before:Dictionary=session._profile.duplicate(true)
 var before_serial:int=quest_save_serial
 var writers_before:int=writer_count
 var reply:Dictionary=super._cmd_quest_loot_start(command)
 e1_record={"command":command.duplicate(true),"reply":reply.duplicate(true),"before":before,"after":session._profile.duplicate(true),"cache":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial,"writer_before":writers_before,"writer_after":writer_count,"anchor_ms":quest_loot.anchor_ms,"generation":_normal_process_generation,"binding_current":_fee_bindings.get(command.get("_quest_connection",-1)) is RefCounted,"primary":_capture_disk(save_path),"backup":_capture_disk(save_path+".bak")}
 if not trace_event("ACCEPTANCE_E1_HANDLER",e1_record):observation_failed=true
 return reply
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
  if field_steps.size()>=ACCEPTANCE_MAX_ATTEMPTS:
   route_trace_overflow=true
   return reply
  var sample:Dictionary={"attempt":true,"generation":_normal_process_generation,"map":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"area":encounter_catalog.area_at(automation.position_map,automation.position_cell).get("id",-1),"rng_before":str(rng_before),"rng_after":str(encounter_rng.state),"pressure_before":pressure_before,"pressure_after":encounter_catalog.pressure,"reply":reply.duplicate(true)}
  pilot_attempt_count+=1
  sample.pending_group=session._pending.get("group_id",-1)
  sample.pending_battle_id=str(session._pending.get("battle_id",""))
  sample.receipt=session._pending.get("quest_loot_receipt",{}).duplicate(true)
  sample.generated_enemies=session._pending.get("enemies",[]).duplicate(true)
  if JSON.stringify(sample).to_utf8_buffer().size()>65536:
   route_trace_overflow=true
   return reply
  field_steps.append(sample)
  trace_event("PILOT_FIELD_STEP",sample)
 return reply
func _after_turn(state:Dictionary,settle:Dictionary={},drop_claims:Array=[])->Dictionary:
 var pending_before:Dictionary=session._pending.duplicate(true)
 var receipt:Dictionary=pending_before.get("quest_loot_receipt",{}).duplicate(true)
 var battle_id:=str(pending_before.get("battle_id",""))
 var state_battle_id:=str(state.get("battle_id",""))
 var raw_claims:Array=battle.drop_claims_for() if not state.get("active",false) else []
 var raw_terminal:Dictionary=state.duplicate(true) if not state.get("active",false) else {}
 var before_profile:Dictionary=session._profile.duplicate(true)
 var before_entry:Dictionary=before_profile.get("quest_loot",{}).get("entries",{}).get(PilotState.STEP,{}).duplicate(true)
 var before_cache:String=last_saved_payload
 var before_serial:int=quest_save_serial
 var result:Dictionary=super._after_turn(state,settle,drop_claims)
 if receipt.is_empty():return result
 var state_active:bool=bool(state.get("active",false))
 var result_active:bool=bool(result.get("active",false))
 if state_active:
  active_turn_count+=1
  if active_turn_count>ACCEPTANCE_MAX_BATTLES*200:settlement_trace_overflow=true
  var pending_after:Dictionary=session._pending
  var active_identity_ok:bool=result_active and result.get("settled",false)!=true and not battle_id.is_empty() and battle_id==state_battle_id and str(pending_after.get("battle_id",""))==battle_id and pending_after.get("quest_loot_receipt",{})==receipt
  if not active_identity_ok:
   trace_event("PILOT_AFTER_TURN_INVALID_ACTIVE",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"state":state,"result":result,"pending_before":pending_before,"pending_after":pending_after,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
   settlement_failed=true
   return result
  # Original nonterminal turns retain the receipt and continue the same battle.
  # They are observations only: no receipt commit, disk capture, or battle count.
  if not trace_event("PILOT_AFTER_TURN_ACTIVE",{"battle_id":battle_id,"turn":state.get("turn",-1),"raw_active":state_active,"view_active":result_active,"receipt_identity_ok":active_identity_ok,"serial_before":before_serial,"serial_after":quest_save_serial}):settlement_failed=true
  return result
 if result_active:
  trace_event("PILOT_AFTER_TURN_INVALID_TERMINAL",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"state":state,"result":result,"pending_before":pending_before,"pending_after":session._pending,"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
  settlement_failed=true
  return result
 if result.get("settled",false)!=true:
  trace_event("PILOT_AFTER_TURN_NOT_COMMITTED",{"battle_id":battle_id,"state_battle_id":state_battle_id,"receipt":receipt,"result":result,"pending_after":session._pending,"profile_before":before_profile,"profile_after":session._profile.duplicate(true),"cache_before":before_cache,"cache_after":last_saved_payload,"serial_before":before_serial,"serial_after":quest_save_serial})
  settlement_failed=true
  return result
 terminal_turn_count+=1
 if terminal_turn_count>ACCEPTANCE_MAX_BATTLES:settlement_trace_overflow=true
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
 # Independent generated -> terminal claim -> received -> exact UID/inventory oracle.
 var generated_claim_items:Array=[]
 var generated_target_claims:=0
 for claim in raw_claims:
  var enemy:Dictionary=pending_before.enemies[int(claim.enemy)]
  var item:int=int(enemy.generated_drops[int(claim.item)])
  generated_claim_items.append(item)
  if item==2760:
   var source:Dictionary=pending_before.get("wild_drop_source",{})
   if int(enemy.get("source_enemy_id",-1))!=1305 or int(enemy.get("generated_drop_slots",[])[int(claim.item)])!=0 or int(source.get("group",-1))!=711 or int(source.get("map",-1))!=100 or int(source.get("area",-1))!=56:settlement_observation_failed=true
   generated_target_claims+=1
 var inventory_expected:Array=before_profile.original_items.duplicate(true)
 var instances_expected:Array=before_profile.original_instances.duplicate(true)
 var next_uid:int=int(before_profile.next_original_uid)
 var unconsumed:Array=generated_claim_items.duplicate()
 for drop in drop_summary:
  var item:int=int(drop.get("item_id",-1))
  var index:int=unconsumed.find(item)
  if index<0:settlement_observation_failed=true
  else:unconsumed.remove_at(index)
  if drop.get("received",false):
   inventory_expected.append(item)
   var durability:int=int(GameSession.OriginalEquipment.ITEMS.get(item,{}).get("durability",0))
   instances_expected.append({"uid":next_uid,"item_id":item,"durability":durability})
   next_uid+=1
 if after_profile.original_items!=inventory_expected or after_profile.original_instances!=instances_expected or int(after_profile.next_original_uid)!=next_uid or received_target>generated_target_claims:settlement_observation_failed=true
 if received_target>0 and (raw_terminal.get("outcome","")!="win" or int(raw_terminal.get("player_hp",0))<=0):settlement_observation_failed=true
 if not trace_event("ACCEPTANCE_DROP_CHAIN",{"battle_id":battle_id,"raw_terminal":raw_terminal,"raw_claims":raw_claims,"original_generated_enemies":pending_before.enemies,"received":drop_summary,"expected_inventory":inventory_expected,"expected_instances":instances_expected,"expected_next_uid":next_uid,"passed":not settlement_observation_failed}):settlement_observation_failed=true
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
 trace_event("PILOT_AFTER_TURN_RECEIPT",{"battle_id":battle_id,"state_battle_id":state_battle_id,"identity_ok":identity_ok,"receipt":receipt,"pending_before":pending_before,"result":result,"received_target":received_target,"received_target_uids":received_target_uids,"profile_before_sha256":JSON.stringify(before_profile).sha256_text(),"profile_after_sha256":JSON.stringify(after_profile).sha256_text(),"cache_before_sha256":before_cache.sha256_text(),"cache_after_sha256":last_saved_payload.sha256_text(),"serial_before":before_serial,"serial_after":quest_save_serial,"primary":{"ok":primary.get("ok",false),"sha256":primary.get("sha256",""),"declared":primary.get("declared",-1),"actual":primary.get("actual",-1)},"backup":{"ok":backup.get("ok",false),"sha256":backup.get("sha256",""),"declared":backup.get("declared",-1),"actual":backup.get("actual",-1)},"capture_valid":capture_valid,"capture_matches":capture_matches,"backup_valid":backup_copy.get("ok",false)})
 if not capture_valid:
  settlement_failed=true
  return result
 if not capture_matches:
  settlement_failed=true
  return result
 if not identity_ok or int(after_entry.get("saved_battles",-1))!=int(before_entry.get("saved_battles",-2))+1 or int(after_entry.get("new_items",-1))!=int(before_entry.get("new_items",-2))+received_target or received_target_uids.size()!=received_target or not session._pending.is_empty():settlement_observation_failed=true
 if settlement_failed:return result
 if settlement_observation_failed:return result
 if settlement_commits.size()>=ACCEPTANCE_MAX_BATTLES:
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
 if not commit.is_empty() and not close_observation_failed:
  # Full atomic record goes to disk once; keep bounded scalar identities in RAM.
  if not trace_event("ACCEPTANCE_RETIRED_FULL",row.settlement_commit):close_observation_failed=true
  var compact:Dictionary={"battle_id":battle_id,"received_target":commit.received_target,"received_target_uids":commit.received_target_uids.duplicate(),"result":{"drop_summary":commit.result.get("drop_summary",[]).duplicate(true)},"primary":row.settlement_commit.primary,"backup":row.settlement_commit.backup}
  settlement_commits[settlement_commits.size()-1]=compact
  retired_battles[retired_battles.size()-1]={"battle_id":battle_id,"outcome":outcome}
  closed_receipts[closed_receipts.size()-1]=compact
 return outcome
func _archive_commit_bytes(name:String,bytes:PackedByteArray,expected_sha:String)->Dictionary:
 if evidence==null:return {"ok":false}
 return evidence.archive(name,bytes,expected_sha)

func _commit_loot_settlement(frame:Dictionary)->Dictionary:
 var expected:Dictionary=frame.get("profile",{}).duplicate(true)
 var prior:String=last_saved_payload
 var before_serial:int=quest_save_serial
 var result:Dictionary=super._commit_loot_settlement(frame)
 if result.get("ok",false):
  var normalized:Dictionary=session._normalize_numbers(expected.duplicate(true))
  var cached:Dictionary=Compare.validated_copy(session,last_saved_payload)
  if session._profile!=expected or not cached.get("ok",false) or cached.get("profile",{})!=normalized or quest_save_serial!=before_serial+1:observation_failed=true
  if not trace_event("ACCEPTANCE_ATOMIC_CANDIDATE",{"battle_id":frame.get("battle_id",""),"expected_full_profile":evidence.blob(JSON.stringify(expected).to_utf8_buffer(),"profile","json"),"prior_cache":evidence.blob(prior.to_utf8_buffer(),"profile","utf8"),"committed_cache":evidence.blob(last_saved_payload.to_utf8_buffer(),"profile","utf8"),"serial_before":before_serial,"serial_after":quest_save_serial,"full_profile_matches":not observation_failed}):observation_failed=true
 return result
