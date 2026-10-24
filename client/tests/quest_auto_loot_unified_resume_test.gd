extends "res://tests/quest_auto_loot_public_start_test.gd"
const Clock=preload("res://scripts/clock.gd")
## UNRUN static candidate. One combined entry; no natural/P3/2760 claim.
## Initial uses disclosed miss-only catalog. C1 uses original seed4101/group169,
## strong player and a fixed fixture clock; no seed search or synthetic reward.
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const Session=preload("res://server/game_session.gd")
const MODES=["positive","external_save","ordinary_save","changed_payload","profile_replace","owner_replace","runner_replace","ticket_replace","extra_writer","false_before","false_after","unknown","no_mark","nested"]
class MissCatalog:
 extends "res://server/encounter_catalog.gd"
 func step(_map_id:int,_cell:Vector2i,_rng:RandomNumberGenerator,_is_portal:=false)->bool:return false
class Driver:
 extends "res://server/automation.gd"
 var yielded_once:=false
 func step()->void:
  super.step() # Exactly one real step; original receipts/rewards/close unchanged.
  if backend.stage=="preclose" and not yielded_once and backend.battle_open and backend.battle_state.get("settled",false) and not backend.quest_loot.followup.is_empty():
   yielded_once=true
   _training_yield=true # Disclosed one-frame yield of original compact loop.
class Runner:
 extends "res://server/quest_auto.gd"
 var after:Callable
 func tick(b,delta:float)->void:
  super.tick(b,delta)
  if after.is_valid():after.call(b)
class UnifiedResumeTimer:
 extends "res://server/quest_auto_loot.gd"
 func capture_initial_resume_save(b)->Dictionary:
  var value:Dictionary=super.capture_initial_resume_save(b)
  b.initial_capture_calls+=1
  return value
 func finish_initial_resume_save(b,ticket:Dictionary,saved:bool)->void:
  b.initial_finish_calls+=1;b.initial_actual_bool=saved
  super.finish_initial_resume_save(b,ticket,saved)
 func capture_outer_resume_save(b)->Dictionary:
  if b.claim_mode=="capture" and not b.injected and not followup.is_empty() and followup.closed and outer_resume_context(b):
   b.claim_handle=b._begin_quest_auto_stop_operation(b.quest_auto)
   b.claim_prepared=not b.claim_handle.is_empty()
   b.ticket=followup;b.ticket_value=followup.duplicate(true)
   b.before=b.facts();b.injected=true
   var denied:Dictionary=super.capture_outer_resume_save(b)
   b.claim_capture_empty=denied.is_empty()
   b.claim_preserved=b._quest_auto_stop_operation_current(b.claim_handle)
   return denied
  var e:Dictionary=super.capture_outer_resume_save(b)
  if b.matches_stage(e) and not b.injected:
   b.envelope=e;b.ticket=e.target;b.ticket_value=e.target.duplicate(true)
   b.before=b.facts();b.before_fields=b.field_calls
  return e
 func mark_outer_resume_saved(b,e:Dictionary,payload:String)->void:
  b.mark_calls+=1
  super.mark_outer_resume_saved(b,e,payload)
 func finish_outer_resume_save(b,e:Dictionary,result:Variant)->void:
  var target:bool=not b.finished and (not e.is_empty() and is_same(e,b.envelope) or b.claim_mode=="capture" and b.injected)
  if target:
   b.pre_finish=b.facts();b.real_return=result
  super.finish_outer_resume_save(b,e,null if target and (b.mode=="unknown" or not b.successor_kind.is_empty() and b.successor_unknown) else result)
  if target and b.successor_late:b.install_successor_input()
  if target:
   b.post_finish=b.facts();b.finished=true
   if not b.claim_mode.is_empty():b.claim_preserved=b.claim_preserved and b._quest_auto_stop_operation_current(b.claim_handle)
   b.set_process(false) # Future frames only; original resume tail still executes.
class Host:
 extends "res://server/backend.gd"
 var claim_mode:=""
 var claim_handle:Dictionary={}
 var claim_prepared:=false
 var claim_capture_empty:=false
 var claim_preserved:=false
 var successor_unknown:=true
 var successor_kind:=""
 var successor_late:=false
 var successor_installed:=false
 var successor_record:Dictionary={}
 var queued_before_successor:=false
 var stage:=""
 var mode:=""
 var test_clock:=1000
 var injected:=false
 var finished:=false
 var envelope:Dictionary={}
 var ticket:Dictionary={}
 var ticket_value:Dictionary={}
 var before:Dictionary={}
 var pre_finish:Dictionary={}
 var post_finish:Dictionary={}
 var process_tail:Dictionary={}
 var real_return:Variant
 var field_calls:=0
 var before_fields:=0
 var mark_calls:=0
 var initial_capture_calls:=0
 var initial_finish_calls:=0
 var initial_actual_bool:=false
 var writer_entries:=0
 var super_calls:=0
 var save_calls:=0
 var close_calls:=0
 var settlement_calls:=0
 var settlement_payload:=""
 var settlement_receipt:Dictionary={}
 var baseline_before_result:Dictionary={}
 var expected_settlement:Dictionary={}
 var settlement_group:=-1
 var before_settlement_primary:PackedByteArray
 var settlement_primary:PackedByteArray
 var settlement_backup:PackedByteArray
 var replacement_owner
 var replacement_runner
 var replacement_ticket:Dictionary={}
 var replacement_state:Dictionary={}
 var nested_empty:=false
 var fake_serials:=0
 func _init()->void:
  super()
  quest_loot=UnifiedResumeTimer.new();quest_auto=Runner.new();automation=Driver.new(self)
 func _quest_loot_public_enabled()->bool:return true
 func matches_stage(e:Dictionary)->bool:
  if e.is_empty():return false
  if stage=="initial":return e.kind=="initial"
  return e.kind=="followup" and bool(e.target.closed)==(stage=="closed")
 func facts()->Dictionary:
  return {"profile":session._profile.duplicate(true),"cache":last_saved_payload,"primary":FileAccess.get_file_as_bytes(save_path),"backup":FileAccess.get_file_as_bytes(save_path+".bak"),"temporary_exists":FileAccess.file_exists(save_path+".tmp"),"temporary":FileAccess.get_file_as_bytes(save_path+".tmp") if FileAccess.file_exists(save_path+".tmp") else PackedByteArray(),"serial":quest_save_serial,"entries":writer_entries,"super_calls":super_calls,"save_calls":save_calls,"marks":mark_calls,"fields":field_calls,"close_calls":close_calls,"settlements":settlement_calls,"generation":_normal_process_generation,"q_running":quest_auto.running,"phase":quest_auto.phase,"battle_open":battle_open,"auto_running":automation.running,"initial_serial":quest_loot.initial_e2.get("serial",-1),"followup_serial":quest_loot.followup.get("serial",-1),"initial_failure_queued":not quest_loot.failed_initial_resume.is_empty(),"followup_failure_queued":not quest_loot.failed_followup_resume.is_empty()}
 func _process(delta:float)->void:
  super._process(delta)
  if finished:process_tail=facts()
  # Unit clock only, not production clock or natural elapsed-time evidence.
  if not finished:test_clock+=500
 func _keep_resume_file()->void:
  # Ensure one original resume observation at the selected stage; no extra writer.
  if not injected and (stage=="initial" and not quest_loot.initial_e2.is_empty() or stage!="initial" and not quest_loot.followup.is_empty() and bool(quest_loot.followup.closed)==(stage=="closed")):_resume_written_msec=-1
  super._keep_resume_file()
 func save()->bool:
  save_calls+=1
  return super.save()
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  writer_entries+=1
  var target:bool=not injected and not checkpoint.is_empty() and is_same(checkpoint,envelope)
  if target:
   injected=true
   if mode=="false_before":return false
   if mode=="no_mark":quest_save_serial+=1;fake_serials+=1;return true # Disclosed forged counter, never writer proof.
   if mode=="ordinary_save":return save() # Real ordinary API gets empty checkpoint, no mark.
   if mode=="changed_payload":session._profile.player.hp-=1
   if mode=="nested":
    nested_empty=quest_loot.capture_outer_resume_save(self).is_empty()
    _resume_written_msec=-1 # Disclosed due marker for this nested negative only.
    keep_resume_file() # Actual nested wrapper; cannot acquire outer source.
  super_calls+=1
  var saved:bool=super._save_profile_boundary(checkpoint)
  if target:
   if claim_mode=="writer_return":
    claim_handle=_begin_quest_auto_stop_operation(quest_auto)
    claim_prepared=not claim_handle.is_empty()
    claim_preserved=_quest_auto_stop_operation_current(claim_handle)
   if mode=="false_after":return false
   if mode=="extra_writer":super_calls+=1;super._save_profile_boundary()
   if mode=="profile_replace":session._profile=session._profile.duplicate(true)
   if mode=="owner_replace":
    replacement_owner=Session.new();replacement_owner._profile=session._profile.duplicate(true)
    session=replacement_owner
    replacement_state={"profile":session._profile.duplicate(true),"identity":quest_auto.identity.checkpoint(),"phase":quest_auto.phase,"message":quest_auto.message}
   if mode=="runner_replace":
    replacement_runner=Runner.new();quest_auto=replacement_runner
    quest_auto.identity.begin();quest_auto.identity.select_step("successor")
    quest_auto.phase="successor";quest_auto.navigation.key="successor"
    replacement_state={"profile":session._profile.duplicate(true),"identity":quest_auto.identity.checkpoint(),"phase":quest_auto.phase,"message":quest_auto.message}
   if mode=="ticket_replace":
    replacement_ticket=checkpoint.target.duplicate(true)
    if checkpoint.kind=="initial":quest_loot.initial_e2=replacement_ticket
    else:quest_loot.followup=replacement_ticket
   if not successor_kind.is_empty() and not successor_late:install_successor_input()
  return saved
 # Independent hostile callback input, NOT a fabricated valid loot permit.
 # Each changed component is isolated; unchanged owners/runner remain identical.
 func install_successor_input()->void:
  if successor_installed:return
  successor_installed=true
  queued_before_successor=not quest_loot.failed_followup_resume.is_empty()
  match successor_kind:
   "scope":
    automation.loot_scope=automation.loot_scope.duplicate(true)
    automation.loot_scope.capability=RefCounted.new()
    automation.loot_scope.token=RefCounted.new()
    automation.loot_scope.receipt=automation.loot_scope.receipt.duplicate(true)
    automation.loot_scope.receipt.ledger.battle_id+="-successor-input"
    quest_loot.ready_frame=quest_loot.ready_frame.duplicate(true)
    quest_loot.ready_frame.ready_token=RefCounted.new()
    quest_loot.ready_frame.capability=RefCounted.new()
   "capability":automation.loot_scope.capability=RefCounted.new()
   "token":automation.loot_scope.token=RefCounted.new()
   "receipt":
    automation.loot_scope.receipt=automation.loot_scope.receipt.duplicate(true)
    automation.loot_scope.receipt.ledger.battle_id+="-successor-input"
   "lifetime":quest_loot.lifetime=RefCounted.new()
   "identity_value":quest_auto.identity.begin();quest_auto.identity.select_step("jewels:hunt:2760")
   "identity_object":
    quest_auto.identity=preload("res://server/quest_auto_state.gd").new()
    quest_auto.identity.begin();quest_auto.identity.select_step("jewels:hunt:2760")
  successor_record=successor_state()
 func successor_state()->Dictionary:
  return {"runner":quest_auto,"identity_object":quest_auto.identity,"identity":quest_auto.identity.checkpoint(),"running":quest_auto.running,"phase":quest_auto.phase,"message":quest_auto.message,"pause_reason":quest_auto.pause_reason,"owns_battle":quest_auto.owns_battle,"lifetime":quest_loot.lifetime,"admission":quest_loot.admission,"scope_ref":automation.loot_scope,"scope":automation.loot_scope.duplicate(true),"auto_token":automation.start_lifetime,"ready_ref":quest_loot.ready_frame,"ready":quest_loot.ready_frame.duplicate(true),"initial_ref":quest_loot.initial_e2,"initial":quest_loot.initial_e2.duplicate(true),"profile_ref":session._profile,"profile":session._profile.duplicate(true)}
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_calls+=1
  return super._cmd_field_step(command)
 func _prepare_loot_settlement(pending:Dictionary,result:Dictionary)->Dictionary:
  baseline_before_result=session._profile.duplicate(true)
  settlement_receipt=pending.quest_loot_receipt.duplicate(true)
  settlement_group=int(pending.group_id)
  before_settlement_primary=FileAccess.get_file_as_bytes(save_path)
  expected_settlement=baseline_before_result.duplicate(true)
  var entry:Dictionary=expected_settlement.quest_loot.entries["jewels:hunt:2760"]
  entry.used_ms=quest_loot.base_used_ms+test_clock-quest_loot.anchor_ms
  entry.revision+=1;entry.open_span=false;entry.settled_seq=entry.issued_seq;entry.saved_battles+=1
  for drop in result.get("drop_summary",[]):
   if drop.get("item_id")==2760 and drop.get("received",false)==true:entry.new_items+=1
  return super._prepare_loot_settlement(pending,result)
 func _loot_settlement_written(payload:String,owner,path:String)->void:
  super._loot_settlement_written(payload,owner,path)
  var value:Variant=JSON.parse_string(payload)
  if value is Dictionary and value.quest_loot.entries.has("jewels:hunt:2760") and int(value.quest_loot.entries["jewels:hunt:2760"].saved_battles)==1 and not value.quest_loot.entries["jewels:hunt:2760"].open_span and settlement_calls==0:
   settlement_calls+=1;settlement_payload=payload
   settlement_primary=FileAccess.get_file_as_bytes(path);settlement_backup=FileAccess.get_file_as_bytes(path+".bak")
 func close_battle()->String:
  close_calls+=1
  return super.close_battle()
func log_fact(label:String,row:Dictionary)->void:
 var encoded:Dictionary=row.duplicate(true)
 for key in ["primary","backup","temporary"]:
  encoded[key+"_base64"]="" if encoded[key].is_empty() else Marshalls.raw_to_base64(encoded[key])
  encoded.erase(key)
 print("UNIFIED_RESUME_FACT ",label," ",JSON.stringify(encoded))
func pair(b,expected:Dictionary,primary:PackedByteArray,backup:PackedByteArray,label:String)->bool:
 check(b.session._profile==expected and b.last_saved_payload==primary.get_string_from_utf8(),label+": complete native/cache")
 if failures:return false
 check(FileAccess.get_file_as_bytes(b.save_path)==primary and FileAccess.get_file_as_bytes(b.save_path+".bak")==backup,label+": complete primary/backup generations")
 if failures:return false
 var p:Dictionary=ProfileCompare.validated_copy(b.session,primary.get_string_from_utf8())
 var q:Dictionary=ProfileCompare.validated_copy(b.session,backup.get_string_from_utf8())
 check(p.get("ok",false) and q.get("ok",false) and p.profile==expected,label+": both independently validated profiles")
 return failures==0
func make_host(stage:String,mode:String):
 var b=Host.new();b.stage=stage;b.mode=mode
 var path:String="user://unified-resume-"+stage+"-"+mode+".json"
 if not fresh_path(path):b.free();return null
 root.add_child(b);b.set_process(false)
 if not prepare_source(b,path):check(false,"Original source setup");b.free();return null
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 if not b.session.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y) or not b.save():check(false,"Original location and pre-E1 save");b.free();return null
 b.quest_loot.clock=func():return b.test_clock
 b.keep_resume_current=true
 if stage=="initial":b.encounter_catalog=MissCatalog.new()
 else:b.encounter_rng.seed=4101;b.encounter_catalog.pressure=50
 b.fee_attach(101)
 var reply:Dictionary=b.handle(start_command(1,101))
 check(reply.get("ok",false) and reply.get("persisted",false) and not b.quest_loot.initial_e2.is_empty(),"Actual public handler E1 seal; test-only capability")
 if failures:b.free();return null
 return b
# Keep the shared condition deadline: seed4101 needs 41 real field attempts
# before the first battle, and initial E2 permits only one per normal generation.
# Diagnostics only observe memory after the original condition wait returns.
func wait_progress(b,label:String,condition:Callable)->bool:
 var started:int=Clock.ticks_msec()
 var generation:int=b._normal_process_generation
 var fields:int=b.field_calls
 var reached:bool=await Wait.until(self,condition)
 print("UNIFIED_RESUME_WAIT ",b.stage,"/",b.mode,"/",label," ",JSON.stringify({"condition_met":reached,"failures":failures,"elapsed_ms":Clock.ticks_msec()-started,"deadline_ms":int(Wait.DEADLINE*1000),"generation":b._normal_process_generation,"generation_delta":b._normal_process_generation-generation,"fields":b.field_calls,"field_delta":b.field_calls-fields,"phase":b.quest_auto.phase,"q_running":b.quest_auto.running,"battle_open":b.battle_open,"settled":b.battle_state.get("settled",false),"settlements":b.settlement_calls,"close_calls":b.close_calls,"initial_serial":b.quest_loot.initial_e2.get("serial",-1),"followup_serial":b.quest_loot.followup.get("serial",-1),"finished":b.finished,"injected":b.injected}))
 return reached

func run_case(stage:String,mode:String)->void:
 var b=make_host(stage,mode)
 if b==null:return
 b.set_process(true)
 var arrived:bool=await wait_progress(b,"selected_resume",func():return b.finished or failures>0)
 if failures:b.free();return
 log_fact(stage+"/"+mode+"/wait_return",b.facts())
 check(arrived and b.injected and b.finished and not b.before.is_empty() and not b.process_tail.is_empty(),"Actual selected resume and complete process tail: "+stage+"/"+mode)
 if failures:b.free();return
 var source:Dictionary=b.before
 for row in [["before",source],["return",b.pre_finish],["finish",b.post_finish],["tail",b.process_tail]]:log_fact(stage+"/"+mode+"/"+row[0],row[1])
 check(not source.temporary_exists and not b.process_tail.temporary_exists,"No fabricated rollback/deletion of a temporary profile")
 if failures:b.free();return
 var expected:Dictionary=source.profile.duplicate(true)
 var primary:PackedByteArray=source.primary
 var backup:PackedByteArray=source.backup
 if mode=="changed_payload":expected.player.hp-=1;primary=JSON.stringify(expected).to_utf8_buffer();backup=source.primary
 if not pair(b,expected,primary,backup,"Return boundary"):b.free();return
 var expected_delta:int=0 if mode=="false_before" else (2 if mode in ["extra_writer","nested"] else 1)
 var expected_super:int=0 if mode in ["false_before","no_mark"] else (2 if mode in ["extra_writer","nested"] else 1)
 check(b.pre_finish.serial==source.serial+expected_delta and b.pre_finish.super_calls==source.super_calls+expected_super and b.fake_serials==(1 if mode=="no_mark" else 0),"Actual return serial/super calls; false is not rollback")
 if failures:b.free();return
 var expected_entries:int=2 if mode in ["ordinary_save","nested"] else 1
 var expected_marks:int=0 if mode in ["false_before","no_mark","ordinary_save","changed_payload"] else 1
 check(b.pre_finish.entries==source.entries+expected_entries and b.pre_finish.marks==source.marks+expected_marks and b.pre_finish.save_calls==source.save_calls+(1 if mode in ["ordinary_save","nested"] else 0),"Exact entry/mark/save-wrapper counts at actual return")
 if failures:b.free();return
 check(b.post_finish.serial==b.pre_finish.serial and b.process_tail.serial==b.post_finish.serial and b.post_finish.profile==b.pre_finish.profile,"Finisher and remainder add no profile writer at this boundary")
 if failures:b.free();return
 var expected_ticket:Dictionary=b.ticket_value.duplicate(true)
 if stage=="initial" and mode=="changed_payload":expected_ticket.profile_ref=expected.duplicate(true)
 if mode in ["positive","external_save"]:expected_ticket.serial=source.serial+1
 check(b.ticket==expected_ticket,"Only true original marked +1 reseals; all captured values retained")
 if failures:b.free();return
 check(b.real_return is bool and b.real_return==(mode not in ["false_before","false_after"]),"Real boundary return independently retained")
 if failures:b.free();return
 var should_mark:bool=mode not in ["false_before","no_mark","ordinary_save","changed_payload","nested"]
 check(b.envelope.fact.written==should_mark,"Original writer mark provenance independent of bool return")
 if failures:b.free();return
 if mode=="nested":check(b.nested_empty,"Reentrant capture cannot acquire another envelope")
 if failures:b.free();return
 check(b._loot_resume_envelope.is_empty() and b._loot_outer_resume_call==null,"All original process claims released")
 if failures:b.free();return
 if stage=="initial":
  check(b.initial_capture_calls>0 and b.initial_finish_calls>0 and b.initial_actual_bool==(mode not in ["false_before","false_after","unknown"]),"Existing initial observer seams and actual bool remain reached")
  if failures:b.free();return
 else:
  check(b.settlement_group==169 and b.settlement_calls==1 and not b.settlement_receipt.is_empty() and b.settlement_receipt.ledger.battle_id in expected.completed_battles and expected.quest_loot.entries[KEY].saved_battles==1 and not expected.quest_loot.entries[KEY].open_span,"One real original receipt/atomic settlement, no injected reward")
  if failures:b.free();return
  check(b.settlement_primary==JSON.stringify(b.expected_settlement).to_utf8_buffer() and b.settlement_backup==b.before_settlement_primary,"Independent whole original result plus exact ledger settlement; backup is prior durable profile")
  if failures:b.free();return
  check(b.before.primary==b.settlement_primary and b.before.backup==b.settlement_backup and b.before.cache==b.settlement_payload,"Resume full generations are exactly the real original settlement pair")
  if failures:b.free();return
 # Out-of-process source check is read-only and cannot allocate a claim.
 check(b.quest_loot.capture_outer_resume_save(b).is_empty() and b._loot_resume_envelope.is_empty(),"No original outer-process source, no permission")
 if failures:b.free();return
 if mode in ["owner_replace","runner_replace"]:
  check({"profile":b.session._profile.duplicate(true),"identity":b.quest_auto.identity.checkpoint(),"phase":b.quest_auto.phase,"message":b.quest_auto.message}==b.replacement_state,"Returning old call never stops/messages/writes successor")
  if failures:b.free();return
  # One real next tick checks old callbacks without granting the replacement
  # a fixture request/runner. No new task or rescue save is sent.
 if mode=="external_save":
  var external:Dictionary=b.facts()
  check(b.save(),"Separate ordinary save outside the original resume invocation succeeds")
  if failures:b.free();return
  check(b.quest_save_serial==external.serial+1 and b.save_calls==external.save_calls+1 and b.super_calls==external.super_calls+1 and b.mark_calls==external.marks and b.ticket.serial==external.serial,"Ordinary API does not borrow or advance the retired envelope")
  if failures or not pair(b,expected,primary,backup,"Separate ordinary writer"):b.free();return
  log_fact(stage+"/"+mode+"/ordinary",b.facts())
 var reached:Array=[false];var opened:Array=[false];var rolled:Array=[false]
 var fields:int=b.field_calls
 b.quest_auto.after=func(host):
  if failures:host.set_process(false);return
  if mode=="positive":
   if stage=="initial":
    if host.field_calls>fields:rolled[0]=true;reached[0]=true;host.set_process(false)
   elif host.quest_loot.ready_frame.has("continuation_gate"):
    opened[0]=true;reached[0]=true;host.set_process(false)
  else:
   if mode in ["owner_replace","runner_replace"] or not host.battle_open and not host.automation.running:
    reached[0]=true;host.set_process(false)
 b.test_clock+=500
 b.set_process(true)
 var progressed:bool=await wait_progress(b,"next_disposition",func():return reached[0] or failures>0)
 if failures:b.free();return
 check(progressed and reached[0],"Bounded next real process reached its disposition")
 if failures:b.free();return
 if mode=="positive":
  if stage=="initial":
   check(rolled[0] and b.field_calls==fields+1,"Initial legitimate next E2")
   if failures or not pair(b,expected,primary,backup,"Initial success later full tail"):b.free();return
  else:
   var reopened:Dictionary=expected.duplicate(true)
   reopened.quest_loot.entries[KEY].open_span=true
   reopened.quest_loot.entries[KEY].revision+=1
   reopened.quest_loot.entries[KEY].issued_seq+=1
   check(opened[0] and b.close_calls==1 and b.settlement_calls==1 and b.field_calls==fields,"Original close/retire/open, no same-generation E2")
   if failures or not pair(b,reopened,JSON.stringify(reopened).to_utf8_buffer(),primary,"Independent reopen full oracle"):b.free();return
   b.quest_auto.after=func(host):
    if host.field_calls>fields:rolled[0]=true;host.set_process(false)
   b.test_clock+=500;b.set_process(true)
   var attempted:bool=await wait_progress(b,"successor_attempt",func():return rolled[0] or failures>0)
   if failures:b.free();return
   check(attempted and b.field_calls==fields+1,"Exactly one actual successor E2, no RNG reset")
   if failures:b.free();return
 else:
  check(b.field_calls==fields and not b.quest_loot.ready_frame.has("continuation_gate"),"Failure never reaches successor E2/gate")
  if failures:b.free();return
  if mode in ["owner_replace","runner_replace"]:
   check({"profile":b.session._profile.duplicate(true),"identity":b.quest_auto.identity.checkpoint(),"phase":b.quest_auto.phase,"message":b.quest_auto.message}==b.replacement_state,"Later old execution still cannot touch replacement")
   if failures:b.free();return
  else:
   check(not b.quest_auto.running,"Current failed execution explicitly stops; no indefinite wait")
   if failures:b.free();return
  if stage=="initial" and not b.quest_loot.initial_failure.is_empty() and b.quest_loot.initial_failure.result.budget_close=="persisted":
   var record:Dictionary=b.quest_loot.initial_failure
   var closed:Dictionary=expected.duplicate(true)
   closed.quest_loot.entries[KEY].used_ms=record.base+record.cutoff-record.anchor
   closed.quest_loot.entries[KEY].revision+=1
   closed.quest_loot.entries[KEY].open_span=false
   closed.quest_loot.entries[KEY].settled_seq=closed.quest_loot.entries[KEY].issued_seq
   if not pair(b,closed,JSON.stringify(closed).to_utf8_buffer(),primary,"Independent existing initial failure close"):b.free();return
  elif not pair(b,expected,primary,backup,"Negative later full tail retains facts"):b.free();return
  if stage!="initial" and mode not in ["owner_replace","runner_replace"]:
   check(b.close_calls==1 and b.settlement_calls==1 and not b.battle_open and not b.automation.running and b.automation.loot_scope.is_empty() and b.quest_loot.ready_frame.is_empty(),"Failed preclose keeps exactly original close and auto exit; exact old scope/readiness retired")
   if failures:b.free();return
 log_fact(stage+"/"+mode+"/final",b.facts())
 print("UNIFIED_RESUME_CASE ",stage,"/",mode," PASS ",JSON.stringify({"serial_before":source.serial,"serial_return":b.pre_finish.serial,"serial_tail":b.process_tail.serial,"writer_super_delta":b.pre_finish.super_calls-source.super_calls,"marks":b.mark_calls,"close":b.close_calls,"settlements":b.settlement_calls}))
 b.free() # Preserve all files. No Stop/rescue save during teardown.
func successor_unchanged(b,label:String)->bool:
 var before:Dictionary=b.successor_record
 var after:Dictionary=b.successor_state()
 for key in ["runner","identity_object","lifetime","admission","scope_ref","auto_token","ready_ref","initial_ref","profile_ref"]:
  check(is_same(before[key],after[key]),label+": same successor reference "+key)
  if failures:return false
 check(after==before,label+": all successor values/running/message preserved")
 return failures==0
func run_successor_case(kind:String,late:bool=false,unknown:bool=false)->void:
 var b=make_host("closed","successor-"+kind+("-queued" if late else "-return"))
 if b==null:return
 b.successor_kind=kind;b.successor_late=late;b.successor_unknown=unknown
 b.set_process(true)
 var arrived:bool=await wait_progress(b,"selected_resume",func():return b.finished or failures>0)
 if failures:b.free();return
 check(arrived and b.successor_installed and b.finished and not b.process_tail.is_empty(),"Real closed C1 resume returned through injected successor callback")
 if failures:b.free();return
 check(b.queued_before_successor==late,"Queued-marker case comes from real unknown finisher; no hand-filled ticket/marker")
 if failures:b.free();return
 check(b.real_return is bool and b.real_return and b.envelope.fact.written is bool and b.envelope.fact.written and b.pre_finish.serial==b.before.serial+1 and b.pre_finish.super_calls==b.before.super_calls+1 and b.ticket.serial==b.ticket_value.serial,"Actual successful writer remains a fact; replaced successor never reseals old ticket")
 if failures or not successor_unchanged(b,"Old finisher and current process tail"):b.free();return
 var expected:Dictionary=b.before.profile.duplicate(true)
 var primary:PackedByteArray=b.before.primary
 var backup:PackedByteArray=b.before.backup
 check(b.settlement_calls==1 and b.close_calls==1 and b.settlement_group==169 and b.settlement_primary==JSON.stringify(b.expected_settlement).to_utf8_buffer() and b.settlement_backup==b.before_settlement_primary and primary==b.settlement_primary and backup==b.settlement_backup,"Successor fixture retains real original receipt/settlement/close and independent full pair")
 if failures or not pair(b,expected,primary,backup,"Successor return full profile/pair"):b.free();return
 var reached:Array=[false]
 var fields:int=b.field_calls
 var tick_before:Dictionary=b.facts()
 b.quest_auto.after=func(host):reached[0]=true;host.set_process(false)
 b.set_process(true)
 var ticked:bool=await wait_progress(b,"next_disposition",func():return reached[0] or failures>0)
 if failures:b.free();return
 check(ticked and reached[0] and b.field_calls==fields,"Next original tick arrives without an old E2")
 if failures or not successor_unchanged(b,"Next original tick and its resume tail"):b.free();return
 var tick_after:Dictionary=b.facts()
 var tail_writes:int=int(tick_after.serial)-int(tick_before.serial)
 check(tail_writes in [0,1] and tick_after.super_calls==tick_before.super_calls+tail_writes and tick_after.save_calls==tick_before.save_calls+tail_writes and tick_after.marks==tick_before.marks,"One later frame has at most its real ordinary resume writer; no hidden finisher write or mark")
 if failures:b.free();return
 log_fact("successor/"+kind+"/next_before",tick_before);log_fact("successor/"+kind+"/next_after",tick_after)
 check(b.quest_loot.failed_followup_resume.is_empty() and b.quest_loot.failed_initial_resume.is_empty(),"Obsolete failure marker cannot reserve successor execution")
 if failures or not pair(b,expected,primary,backup,"Successor next tick full profile/pair"):b.free();return
 # A hostile tuple alone is not evidence of an executable successor. The
 # independent internal test driver now creates real E1 using original APIs.
 # Same Backend/Session/runner/timer; no hand-filled ready/E2/followup ticket.
 var q=b.quest_auto;var timer=b.quest_loot
 q.identity.begin();q.identity.select_step(KEY);q.phase="loot_admission"
 var e1_serial:int=b.quest_save_serial
 var admitted:Dictionary=timer.admit_prepared_run(b)
 check(admitted.get("ok",false) and admitted.get("persisted",false) and b.quest_save_serial==e1_serial+1 and is_same(q,b.quest_auto) and is_same(timer,b.quest_loot),"Actual internal E1 admits successor on same runner/timer, not merely a false owner predicate")
 if failures:b.free();return
 var reopened:Dictionary=expected.duplicate(true)
 reopened.quest_loot.entries[KEY].open_span=true
 reopened.quest_loot.entries[KEY].revision+=1
 reopened.quest_loot.entries[KEY].issued_seq+=1
 if not pair(b,reopened,JSON.stringify(reopened).to_utf8_buffer(),primary,"Independent successor E1 retains complete rewards/UIDs/limit/used"):b.free();return
 b.encounter_catalog=MissCatalog.new() # Disclosed deterministic successor miss only.
 b.test_clock+=500
 var attempted:Dictionary=timer.attempt_once(b)
 check(b.quest_save_serial==e1_serial+1 and attempted.get("ok",false) and attempted.get("attempted",false) and not attempted.get("battle",true) and b.field_calls==fields+1 and b.quest_loot.failed_followup_resume.is_empty(),"Real original successor E2 executes once; stale marker does not block it")
 if failures or not pair(b,reopened,JSON.stringify(reopened).to_utf8_buffer(),primary,"Successor E2 full profile/pair"):b.free();return
 log_fact("successor/"+kind+("/queued" if late else "/return"),b.facts())
 print("UNIFIED_RESUME_SUCCESSOR ",kind,"/",("queued" if late else "return")," PASS")
 b.free()
func run_claim_case(point:String)->void:
 var b=make_host("closed","claim-"+point)
 if b==null:return
 b.claim_mode=point
 b.set_process(true)
 var arrived:bool=await wait_progress(b,"selected_resume",func():return b.finished or failures>0)
 if failures:b.free();return
 check(arrived and b.finished and b.claim_prepared and b.claim_preserved and b._quest_auto_stop_operation_current(b.claim_handle),"Actual Stop begin claim survives capture/writer-return rejection and full original tail: "+point)
 if failures:b.free();return
 var source:Dictionary=b.before
 check(b.real_return is bool and b.real_return and b.pre_finish.serial==source.serial+1 and b.pre_finish.super_calls==source.super_calls+1 and b.ticket.serial==b.ticket_value.serial,"One real successful save remains +1; active claim grants no old ticket reseal")
 if failures:b.free();return
 if point=="capture":
  check(b.claim_capture_empty and b.envelope.is_empty() and b.pre_finish.save_calls==source.save_calls+1 and b.pre_finish.marks==source.marks,"Capture refusal retains original ordinary save fallback without an envelope or mark")
 else:
  check(not b.envelope.is_empty() and b.envelope.fact.written is bool and b.envelope.fact.written and b.pre_finish.save_calls==source.save_calls and b.pre_finish.marks==source.marks+1 and not b.quest_loot.failed_followup_resume.is_empty(),"Writer-return claim rejects actual true after real mark, keeps old failure pending")
 if failures:b.free();return
 check(b._loot_resume_envelope.is_empty() and b._loot_outer_resume_call==null and b.process_tail.serial==b.pre_finish.serial,"Only own resume claims released; no hidden finisher writer")
 if failures or not pair(b,source.profile,source.primary,source.backup,"Held claim actual complete profile/pair"):b.free();return
 check(b.settlement_calls==1 and b.close_calls==1 and source.primary==b.settlement_primary and source.backup==b.settlement_backup and b.settlement_primary==JSON.stringify(b.expected_settlement).to_utf8_buffer() and b.settlement_backup==b.before_settlement_primary,"Held claim preserves independently derived original settlement/receipt/close generations")
 if failures:b.free();return
 log_fact("claim/"+point+"/held",b.facts())
 b._end_quest_auto_stop_operation(b.claim_handle)
 check(b._quest_auto_stop_operation_call==null and b._quest_auto_stop_operation_owner==null and b.quest_loot.outer_resume_persistent_claims_idle(b),"Only actual original end releases its own persistent claim")
 if failures:b.free();return
 var fields:int=b.field_calls
 var disposed:Array=[false]
 b.quest_auto.after=func(host):
  if not host.quest_auto.running:disposed[0]=true;host.set_process(false)
 b.set_process(true)
 var stopped:bool=await wait_progress(b,"claim_retirement",func():return disposed[0] or failures>0)
 if failures:b.free();return
 check(stopped and disposed[0] and b.field_calls==fields and b.quest_loot.followup.is_empty() and b.quest_loot.failed_followup_resume.is_empty() and b.quest_loot.ready_frame.is_empty() and b.automation.loot_scope.is_empty(),"Release does not revive invalid old C1; original current-owner failure exits without E2")
 if failures or not pair(b,source.profile,source.primary,source.backup,"Claim released old current execution retired without disk close"):b.free();return
 b.claim_mode="" # End the disclosed injector; no pending production claim is cleared here.
 var q=b.quest_auto;var timer=b.quest_loot
 var serial:int=b.quest_save_serial
 var reply:Dictionary=b.handle(start_command(2,101))
 check(reply.get("ok",false) and reply.get("persisted",false) and is_same(q,b.quest_auto) and is_same(timer,b.quest_loot) and b.quest_save_serial==serial+1 and not timer.initial_e2.is_empty(),"After actual release a new legitimate public E1 request is accepted on same owner/runner/timer")
 if failures:b.free();return
 var reopened:Dictionary=source.profile.duplicate(true)
 reopened.quest_loot.entries[KEY].open_span=true
 reopened.quest_loot.entries[KEY].revision+=1
 reopened.quest_loot.entries[KEY].issued_seq+=1
 var reopened_bytes:PackedByteArray=JSON.stringify(reopened).to_utf8_buffer()
 if not pair(b,reopened,reopened_bytes,source.primary,"Independent new E1 preserves full budget and rewards"):b.free();return
 b.encounter_catalog=MissCatalog.new()
 var next_frame:Dictionary=timer.initial_e2
 var rolled:Array=[false]
 var new_marks:int=b.mark_calls
 b.quest_auto.after=func(host):
  if host.field_calls>fields:rolled[0]=true;host.set_process(false)
 b._resume_written_msec=-1 # Disclosed due marker: observe the new legal original resume too.
 b.test_clock+=500;b.set_process(true)
 var attempted:bool=await wait_progress(b,"successor_attempt",func():return rolled[0] or failures>0)
 if failures:b.free();return
 check(attempted and rolled[0] and b.field_calls==fields+1 and b.mark_calls==new_marks+1 and next_frame.serial==b.quest_save_serial and b._loot_resume_envelope.is_empty() and b._loot_outer_resume_call==null and b._quest_auto_stop_operation_call==null,"New actual E2 and original resume succeed; no old envelope or Stop claim blocks successor")
 if failures or not pair(b,reopened,reopened_bytes,source.primary,"New E2/resume full generations"):b.free();return
 log_fact("claim/"+point+"/released_successor",b.facts())
 print("UNIFIED_RESUME_CLAIM ",point," PASS")
 b.free()
func run_claim_residue_matrix()->void:
 var b=make_host("initial","claim-residues")
 if b==null:return
 # Synthetic incomplete residues, not a claim of wired fee concurrency.
 var rows:Array=[
  [b,"_fee_attempt_writer_call",RefCounted.new()], [b,"_fee_attempt_writer_snapshot",{"test_residue":true}], [b,"_fee_attempt_writer_executing",true],
  [b,"_fee_attempt_close_call",RefCounted.new()], [b,"_fee_attempt_close_frame",{"test_residue":true}], [b,"_fee_attempt_close_executing",true],
  [b,"_fee_resume_sidecar_call",RefCounted.new()], [b,"_fee_resume_sidecar_frame",{"test_residue":true}], [b,"_fee_resume_sidecar_executing",true],
  [b,"_quest_auto_stop_operation_call",RefCounted.new()], [b,"_quest_auto_stop_operation_owner",b.quest_auto],
  [b._fee_start_journal_writer,"_frame",{"test_residue":true}], [b._fee_start_journal_writer,"_executing",true]]
 var baseline:Dictionary=b.facts()
 for row in rows:
  var owner:Object=row[0];var key:String=row[1];var old:Variant=owner.get(key);var residue:Variant=row[2]
  check(b.quest_loot.outer_resume_persistent_claims_idle(b),"Residue precondition is all idle: "+key)
  if failures:b.free();return
  owner.set(key,residue)
  check(not b.quest_loot.outer_resume_persistent_claims_idle(b) and owner.get(key)==residue and b.facts()==baseline and b._loot_resume_envelope.is_empty(),"Read-only gate rejects exactly one disclosed residue without clearing claim or changing full facts: "+key)
  if failures:b.free();return
  owner.set(key,old) # Test input restoration, not a production end/repair API.
  check(b.quest_loot.outer_resume_persistent_claims_idle(b),"Restored test input does not leave an envelope: "+key)
  if failures:b.free();return
  print("UNIFIED_RESUME_RESIDUE ",key," PASS")
 b.free()
func run()->void:
 for stage in ["initial","preclose","closed"]:
  for mode in MODES:
   await run_case(stage,mode)
   if failures:quit(1);return
 for kind in ["scope","capability","token","receipt","lifetime","identity_value","identity_object"]:
  await run_successor_case(kind)
  if failures:quit(1);return
 await run_successor_case("scope",true,true)
 if failures:quit(1);return
 for point in ["capture","writer_return"]:
  await run_claim_case(point)
  if failures:quit(1);return
 run_claim_residue_matrix()
 if failures:quit(1);return
 print("UNIFIED_LOOT_RESUME PASS cases=65; internal deterministic; P3/2760 UNPROVEN")
 quit(0)
