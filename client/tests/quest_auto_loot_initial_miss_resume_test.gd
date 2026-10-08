extends "res://tests/quest_auto_loot_public_start_test.gd"
## UNRUN draft: focused deterministic resume/initial-E2 regression, NOT natural loot proof.
## Reuses only prepare_source/read_disk/start_command; never parent's one-step Backend.
class MissCatalog:
 extends "res://server/encounter_catalog.gd"
 func step(_map_id:int,_cell:Vector2i,_rng:RandomNumberGenerator,_is_portal:=false)->bool:
  return false # Explicit unit seam: no seed search, enemies, claims or rewards.
class ObservedTimer:
 extends "res://server/quest_auto_loot.gd"
 func capture_initial_resume_save(b)->Dictionary:
  var ticket:Dictionary=super.capture_initial_resume_save(b)
  b.capture_calls+=1
  if not ticket.is_empty():
   b.capture_ticket=ticket # Actual returned ticket reference, never constructed by test.
   b.capture_frame=ticket.frame
   b.capture_frame_value=ticket.frame.duplicate(true)
   b.capture_profile_value=ticket.profile.duplicate(true)
   b.capture_serial=int(ticket.serial)
   b.capture_owner=b.session # Keep old owner alive through replacement assertions.
   b.ticket_aliases_ok=is_same(ticket.profile_ref,b.session._profile) and is_same(ticket.frame,initial_e2) and is_same(ticket.ready,ready_frame) and not is_same(ticket.profile,b.session._profile) and not is_same(ticket.profile,initial_e2.profile)
  return ticket
 func finish_initial_resume_save(b,ticket:Dictionary,saved:bool)->void:
  b.finish_calls+=1
  b.finish_saved=saved
  b.finish_ticket_same=is_same(ticket,b.capture_ticket)
  b.before_finish_serial=b.quest_save_serial
  b.before_finish_profile=b.session._profile.duplicate(true)
  b.before_finish_cache=b.last_saved_payload
  b.before_finish_initial=initial_e2
  b.before_finish_initial_value=initial_e2.duplicate(true)
  b.before_finish_ready=ready_frame
  b.before_finish_ready_value=ready_frame.duplicate(true)
  super.finish_initial_resume_save(b,ticket,saved)
  b.finish_seen=true
  if not b.inject_mode.is_empty():b.set_process(false) # Observe this boundary only; no next tick masks its outcome.
# UNRUN passive oracle. Only the positive resume fixture installs this timer.
# Independent 500 is the reviewed contract, never imported from timer fields.
class CadenceObserver:
 extends RefCounted
 const CONTRACT_MS:=500
 var original:Callable
 var active:Dictionary={}
 var inner:Dictionary={}
 var attempts:=0
 var calls:=0
 var returns:=0
 var field_count:=0
 var early_zero:=0
 var accepted:=0
 var expected_next:=-1
 var previous_raw:=-1
 var accepted_clock_ordinal:=-1
 var owner_context:Dictionary={}
 var history:Array[Dictionary]=[]
 var issues:Array[String]=[]
 var overflow:=false
 func problem(reason:String)->void:
  if issues.size()<16:issues.append(reason)
  else:overflow=true
 func context(b,timer)->Dictionary:
  return {"session":b.session.get_instance_id(),"runner":b.quest_auto.get_instance_id(),"identity":b.quest_auto.identity.checkpoint(),"lifetime":timer.lifetime.get_instance_id()}
 func enter_attempt(b,timer)->Dictionary:
  attempts+=1
  var frame:Dictionary={"ordinal":attempts,"context":context(b,timer),"clock_count":0,"samples":0,"fields":0,"raw":null,"sample_call":-1,"clock_ordinal":-1,"threshold":expected_next,"last_field_clock":-1,"field_wall":-1,"early":false}
  if not active.is_empty():problem("nested outer attempt")
  if owner_context.is_empty():owner_context=frame.context.duplicate(true)
  elif owner_context!=frame.context:problem("owner/run/lifetime changed: independent deadline cannot be reused")
  return frame
 func observe_clock()->Variant:
  calls+=1
  var ordinal:int=calls
  var scope:Dictionary=active
  var sample_scope:Dictionary=inner
  # Exactly ONE original call, original Variant returned verbatim.
  var value:Variant=original.call()
  returns+=1
  if not scope.is_empty():scope.clock_count+=1
  if not sample_scope.is_empty():
   sample_scope.count+=1
   if not is_same(active,scope) or not is_same(inner,sample_scope):problem("clock callback replaced observation scope")
   if scope.is_empty():problem("sample without outer attempt")
   else:
    scope.raw=value;scope.clock_ordinal=ordinal
  return value
 func field_entry(call:Variant)->void:
  field_count+=1
  if active.is_empty():problem("field outside complete attempt");return
  active.fields+=1
  active.field_wall=Time.get_ticks_msec() # Wall is diagnostic only.
  if not inner.is_empty():problem("field before sample method returned")
  if active.samples!=1 or active.clock_count!=1:problem("field not paired with exactly one original clock sample")
  if not call is RefCounted:problem("field missing original attempt identity");return
  if call.get_instance_id()!=active.sample_call:problem("field belongs to another original attempt")
  if active.fields!=1:problem("sample reused for multiple field callbacks")
  var raw:Variant=active.raw
  if not raw is int:problem("original clock result not int");return
  if active.clock_ordinal<=accepted_clock_ordinal:problem("clock ordinal reused")
  active.last_field_clock=active.clock_ordinal
  accepted_clock_ordinal=active.clock_ordinal
  if previous_raw>=0 and raw<previous_raw:problem("original clock decreased")
  if active.threshold>=0 and raw<active.threshold:problem("field below independent raw+500 deadline")
  if raw>9007199254740991-CONTRACT_MS:problem("independent deadline overflow");return
  # This is the observer's accepted-call history, not production last/next.
  previous_raw=raw;expected_next=raw+CONTRACT_MS;accepted+=1
 func leave_attempt(b,timer,frame:Dictionary,result:Dictionary)->void:
  if context(b,timer)!=frame.context:problem("attempt exit owner changed")
  if frame.samples>1 or frame.clock_count>1:problem("more than one sample in complete attempt")
  if frame.fields>1:problem("more than one field in complete attempt")
  if frame.fields>0 and frame.samples!=1:problem("field without unique sample")
  if frame.raw is int and frame.threshold>=0 and frame.raw<frame.threshold:
   frame.early=true
   if frame.fields!=0:problem("early sample produced a field callback")
   # Count only a real completed sampled attempt explicitly returning no attempt.
   elif frame.samples==1 and frame.clock_count==1 and result.get("ok") is bool and result.ok and result.get("attempted") is bool and not result.attempted:early_zero+=1
  if result.get("attempted") is bool and result.attempted!=(frame.fields==1):problem("reported attempt disagrees with observed field count")
  if history.size()<4096:history.append(frame.duplicate(true))
  else:overflow=true
 func report()->Dictionary:
  var status:String="FAIL" if not issues.is_empty() else ("UNPROVEN" if overflow or calls!=returns or early_zero==0 or accepted<3 else "PROVEN")
  return {"status":status,"attempts":attempts,"original_calls":calls,"original_returns":returns,"accepted_fields":accepted,"all_fields":field_count,"early_sample_zero_field":early_zero,"overflow":overflow,"issues":issues.duplicate(),"last_attempts":history.slice(maxi(0,history.size()-4)).duplicate(true)}
class CadenceTimer:
 extends ObservedTimer
 var observer:=CadenceObserver.new()
 func _init()->void:
  observer.original=clock # Default original callable captured before public E1.
  clock=observer.observe_clock # Stable wrapper identity for the whole fixture.
 func attempt_once(b)->Dictionary:
  var prior:Dictionary=observer.active
  var frame:Dictionary=observer.enter_attempt(b,self)
  observer.active=frame
  var reply:Dictionary=super.attempt_once(b) # Includes sample return AND field.
  observer.leave_attempt(b,self,frame,reply)
  observer.active=prior
  return reply
 func sample_attempt_sealed(b,frame:Dictionary,fence:Dictionary)->Dictionary:
  var prior:Dictionary=observer.inner
  var scope:Dictionary={"count":0}
  if observer.active.is_empty():observer.problem("sample entry without outer attempt")
  else:
   observer.active.samples+=1
   var call:Variant=frame.get("attempt_call")
   if call is RefCounted:observer.active.sample_call=call.get_instance_id()
   else:observer.problem("sample entry has no original attempt call")
  observer.inner=scope
  var reply:Dictionary=super.sample_attempt_sealed(b,frame,fence)
  observer.inner=prior
  # A rejected pre-clock sample may legitimately count zero, but cannot field.
  if scope.count>1:observer.problem("sample method invoked clock more than once")
  return reply
class ResumeBackend:
 extends "res://server/backend.gd"
 var expected_e1_primary:Dictionary={}
 var expected_e1_backup:Dictionary={}
 var inject_mode:=""
 var injection_armed:=false
 var injection_count:=0
 var boundary_super_calls:=0
 var capture_calls:=0
 var finish_calls:=0
 var capture_ticket:Dictionary={}
 var capture_frame:Dictionary={}
 var capture_frame_value:Dictionary={}
 var capture_profile_value:Dictionary={}
 var capture_serial:=-1
 var capture_owner
 var ticket_aliases_ok:=false
 var finish_saved:=false
 var finish_ticket_same:=false
 var finish_seen:=false
 var before_finish_serial:=-1
 var before_finish_profile:Dictionary={}
 var before_finish_cache:=""
 var before_finish_initial:Dictionary={}
 var before_finish_initial_value:Dictionary={}
 var before_finish_ready:Dictionary={}
 var before_finish_ready_value:Dictionary={}
 var replacement_owner
 var field_calls:=0
 var field_times:Array[int]=[]
 var cadence_rows:Array[Dictionary]=[]
 var cadence_overflow:=false
 var resume_noops:=0
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var observed_call:bool=quest_loot.attempt_call!=null
  var before_sample:int=quest_loot.last_attempt_ms
  var before_deadline:int=quest_loot.next_attempt_ms
  var before_wall:int=Time.get_ticks_msec()
  if quest_loot is CadenceTimer:quest_loot.observer.field_entry(quest_loot.attempt_call)
  var reply:Dictionary=super._cmd_field_step(command)
  if quest_loot.attempt_call!=null:
   field_calls+=1
   field_times.append(Time.get_ticks_msec()) # Preserve original return-wall observation.
   if cadence_rows.size()<128:
    cadence_rows.append({"ordinal":field_calls,"call_present_before":observed_call,"wall_before":before_wall,"wall_return":field_times.back(),"sample_before":before_sample,"deadline_before":before_deadline,"sample_after":quest_loot.last_attempt_ms,"deadline_after":quest_loot.next_attempt_ms})
   else:cadence_overflow=true
  return reply
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  var before:String=last_saved_payload
  var serial:int=quest_save_serial
  var inject:bool=injection_armed and not capture_ticket.is_empty() and _process_depth==1 and _dispatch_boundary_depth==2 and _depth==0
  if inject:
   injection_armed=false
   injection_count+=1
   if inject_mode=="save_false_before":return false # Original Backend.save dispatch; deliberate failing boundary, no disk write.
   if inject_mode=="changed_payload":session._profile.player.hp-=1 # Damage-only valid-profile unit seam, no item/budget/reward.
  boundary_super_calls+=1
  var ok:bool=super._save_profile_boundary(checkpoint)
  if inject:
   if inject_mode=="save_false_after":return false # Deliberate ambiguous result AFTER the actual no-op writer.
   if inject_mode=="profile_replace":session._profile=session._profile.duplicate(true)
   if inject_mode=="owner_replace":
    replacement_owner=GameSession.new()
    replacement_owner._profile=session._profile.duplicate(true)
    session=replacement_owner
   if inject_mode=="extra_writer":
    boundary_super_calls+=1
    ok=super._save_profile_boundary(checkpoint) and ok
   if inject_mode=="successor_frame":quest_loot.initial_e2=quest_loot.initial_e2.duplicate(true)
  if ok and _process_depth==1 and _depth==0 and last_saved_payload==before and quest_save_serial==serial+1:resume_noops+=1
  return ok
func make_case(path:String,resume:bool,observe_cadence:bool=false):
 if not fresh_path(path) or FileAccess.file_exists(path.get_basename()+".resume.json"):
  check(false,"New isolated regression profile/resume path")
  return null
 var b=ResumeBackend.new()
 b.encounter_catalog=MissCatalog.new()
 b.quest_loot=CadenceTimer.new() if observe_cadence else ObservedTimer.new()
 root.add_child(b)
 if not prepare_source(b,path):check(false,"Original prepared source fixture");b.free();return null
 # The inherited helper moves automation authority but save() does not copy
 # that position into profile.location. Synchronize BEFORE public E1 seals it.
 var expected_location:Dictionary={"map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y}
 var before_location:Dictionary=b.session._profile.duplicate(true)
 var expected_pre_e1:Dictionary=before_location.duplicate(true)
 expected_pre_e1.location=expected_location.duplicate(true)
 var setup_serial:int=b.quest_save_serial
 var setup_writers:int=b.boundary_super_calls
 check(not b.is_processing() and b.automation.position_map==100 and b.encounter_catalog.area_at(100,b.automation.position_cell).get("id")==56 and b.quest_loot.initial_e2.is_empty(),"Helper supplies valid authoritative area56 before any E1 seal")
 if failures:b.free();return null
 check(b.session.set_location(expected_location.map_id,expected_location.x,expected_location.y) and b.session._profile==expected_pre_e1,"Original set_location synchronizes only the independently captured authority position")
 if failures:b.free();return null
 check(b.save() and b.quest_save_serial==setup_serial+1 and b.boundary_super_calls==setup_writers+1 and b.session._profile==expected_pre_e1 and b.last_saved_payload==JSON.stringify(expected_pre_e1),"Exactly one original pre-E1 save persists the complete location-only candidate")
 if failures:b.free();return null
 assert_pair(b,expected_pre_e1,before_location,JSON.stringify(expected_pre_e1).to_utf8_buffer(),JSON.stringify(before_location).to_utf8_buffer(),"Pre-E1 authority location primary/previous backup")
 if failures:b.free();return null
 b.keep_resume_current=resume
 b.fee_attach(101)
 var pre_e1:Dictionary=b.session._profile.duplicate(true)
 var ack:Dictionary=b.handle(start_command(1,101))
 check(Backend.QUEST_LOOT_PUBLIC_ENABLED==true and b._quest_loot_public_enabled() and b.automation.auto_tick and ack.get("ok",false) and ack.get("persisted",false),"Original public E1 with real production capability/getter, normal auto_tick")
 if failures:b.free();return null
 var acquired:Dictionary=State.acquire(pre_e1.quest_loot,State.STEP,str(ack.budget_identity.budget_id),str(ack.run_identity.run_id),30,0)
 check(acquired.get("ok",false),"Independent E1 acquire oracle")
 if failures:b.free();return null
 var opened:Dictionary=State.open(acquired.ledger,State.STEP,State.identity(acquired.ledger.entries[State.STEP]))
 check(opened.get("ok",false),"Independent E1 open oracle")
 if failures:b.free();return null
 b.expected_e1_primary=pre_e1.duplicate(true);b.expected_e1_primary.quest_loot=opened.ledger
 b.expected_e1_backup=pre_e1.duplicate(true);b.expected_e1_backup.quest_loot=acquired.ledger
 check(b.session._profile==b.expected_e1_primary,"Complete live E1 profile from independent State transitions")
 assert_pair(b,b.expected_e1_primary,b.expected_e1_backup,JSON.stringify(b.expected_e1_primary).to_utf8_buffer(),JSON.stringify(b.expected_e1_backup).to_utf8_buffer(),"Original E1 two generations")
 if failures:b.free();return null
 return b
# Bounded observation only: no save/snapshot/disk/capture/owner-guard call.
# Fixed suite has ten Wait return points: positive1 + external2 + negatives7.
var diagnostic_count:=0
func diagnostic_location(value:Variant)->Dictionary:
 var result:Dictionary={"type":typeof(value),"map_id":-1,"x":-1,"y":-1,"integer_fields":false}
 if value is Dictionary:
  result.integer_fields=value.get("map_id") is int and value.get("x") is int and value.get("y") is int
  if result.integer_fields:
   result.map_id=value.map_id;result.x=value.x;result.y=value.y
 return result
func emit_wait_diagnostic(b,label:String,reached:bool,entry_frame:Dictionary)->void:
 if diagnostic_count>=10:return
 diagnostic_count+=1
 var frame:Dictionary=b.capture_frame
 var owner_ref:Variant=frame.get("session")
 var runner_ref:Variant=frame.get("runner")
 var current:Dictionary=b.quest_loot.initial_e2
 var row:Dictionary={"ordinal":diagnostic_count,"case":label.left(48),"condition":reached,"field":b.field_calls,"noop":b.resume_noops,"capture":b.capture_calls,"finish":b.finish_calls,"writers":b.boundary_super_calls,"serial":b.quest_save_serial,"captured_serial":b.capture_serial,"seal":frame.get("serial",-1),"entry_seal":entry_frame.get("serial",-1),"entry_frame_current":not entry_frame.is_empty() and is_same(current,entry_frame),"current_seal":current.get("serial",-1),"finish_serial":b.before_finish_serial,"saved_known":b.finish_calls>0,"saved":b.finish_saved,"ticket_present":not b.capture_ticket.is_empty(),"ticket_aliases_ok_at_capture":b.ticket_aliases_ok,"same_finish_ticket":b.finish_ticket_same,"captured_frame_present":not frame.is_empty(),"current_frame_present":not current.is_empty(),"same_current_frame":not frame.is_empty() and is_same(current,frame),"owner_type":typeof(owner_ref),"owner_is_weakref":owner_ref is WeakRef,"owner_current":owner_ref is WeakRef and is_same(owner_ref.get_ref(),b.session),"runner_current":runner_ref is WeakRef and is_same(runner_ref.get_ref(),b.quest_auto),"profile_ref_current":not frame.is_empty() and is_same(frame.get("profile_ref"),b.session._profile),"lifetime_current":not frame.is_empty() and is_same(frame.get("lifetime"),b.quest_loot.lifetime),"ready_token_current":not frame.is_empty() and is_same(frame.get("ready_token"),b.quest_loot.ready_frame.get("ready_token")),"continuation_gate":b.quest_loot.ready_frame.has("continuation_gate"),"running":b.quest_auto.running,"phase":str(b.quest_auto.phase).left(32),"processing":b.is_processing(),"auto_tick":b.automation.auto_tick,"battle":b.battle_open,"pending_empty":b.session._pending.is_empty(),"settlement_empty":b.session._loot_settlement.is_empty(),"authority":{"map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y},"profile_location":diagnostic_location(b.session._profile.get("location")),"sealed_location":diagnostic_location(frame.get("profile",{}).get("location")),"entry_location":diagnostic_location(entry_frame.get("profile",{}).get("location"))}
 var encoded:String=JSON.stringify(row)
 if encoded.to_utf8_buffer().size()>4096:
  print("INITIAL_MISS_RESUME_DIAGNOSTIC ",JSON.stringify({"ordinal":diagnostic_count,"overflow":true}))
  return
 print("INITIAL_MISS_RESUME_DIAGNOSTIC ",encoded)
func emit_cadence_diagnostic(b)->void:
 # At most four violating pairs, emitted BEFORE the unchanged first check.
 # All values are already stored scalars; no clock/sample/snapshot/disk/save.
 var pairs:Array[Dictionary]=[]
 var violations:=0
 for i in range(1,b.field_times.size()):
  var wall_delta:int=b.field_times[i]-b.field_times[i-1]
  if wall_delta>=500:continue
  violations+=1
  if pairs.size()>=4:continue
  var pair:Dictionary={"index":i,"wall_previous":b.field_times[i-1],"wall_current":b.field_times[i],"wall_delta":wall_delta,"callback_rows_available":i<b.cadence_rows.size()}
  if i<b.cadence_rows.size():
   var previous:Dictionary=b.cadence_rows[i-1]
   var current:Dictionary=b.cadence_rows[i]
   pair.previous=previous.duplicate(true);pair.current=current.duplicate(true)
   pair.sample_delta=current.sample_before-previous.sample_before
   pair.previous_sample_to_return=previous.wall_return-previous.sample_before
   pair.current_sample_to_return=current.wall_return-current.sample_before
   pair.previous_callback_wall=previous.wall_return-previous.wall_before
   pair.current_callback_wall=current.wall_return-current.wall_before
  pairs.append(pair)
 print("LOOT_CADENCE_DIAGNOSTIC ",JSON.stringify({"wall_source":"Time.get_ticks_msec after super field return","sample_source":"existing timer last_attempt_ms/next_attempt_ms; not independent oracle","attempts":b.field_times.size(),"stored_rows":b.cadence_rows.size(),"overflow":b.cadence_overflow,"violations":violations,"pairs":pairs}))
func positive_and_external()->void:
 var b=make_case("user://loot-initial-miss-resume-short.json",true,true)
 if b==null:quit(1);return
 var frame:Dictionary=b.quest_loot.initial_e2
 var serial:int=b.quest_save_serial
 var profile:Dictionary=b.session._profile.duplicate(true)
 var payload:String=b.last_saved_payload
 var primary:Dictionary=read_disk(b.save_path)
 var backup:Dictionary=read_disk(b.save_path+".bak")
 b.set_process(true)
 var advanced:bool=await Wait.until(self,func():return b.field_calls>=3 and b.resume_noops>=2,15.0)
 emit_wait_diagnostic(b,"positive",advanced,frame)
 check(advanced,"Miss survives original resume save and reaches three normal E2 attempts plus a periodic resume write")
 if failures:b.free();quit(1);return
 check(b.resume_noops>=2 and b.quest_save_serial>serial and is_same(b.quest_loot.initial_e2,frame) and frame.serial==b.quest_save_serial,"Only actual same-payload resume writes advance this captured serial seal")
 check(b.session._profile==profile and b.last_saved_payload==payload and read_disk(b.save_path).bytes==primary.bytes and read_disk(b.save_path+".bak").bytes==backup.bytes,"Full profile/cache/primary/backup unchanged across misses and no-op resume saves")
 emit_cadence_diagnostic(b)
 check(b.quest_loot is CadenceTimer,"Positive fixture must install the independent cadence observer")
 if failures:b.free();quit(1);return
 var evidence:Dictionary=b.quest_loot.observer.report()
 print("LOOT_CADENCE_ORACLE ",JSON.stringify(evidence))
 check(evidence.status=="PROVEN","Independent original-clock cadence status: "+str(evidence.status))
 if failures:b.free();quit(1);return
 # Return-wall pairs remain diagnostic; only independent original raw+500 is acceptance.
 check(b.quest_auto.phase=="loot_admission" and b.quest_auto.running and not b.battle_open and b.session._pending.is_empty() and FileAccess.file_exists(b._resume_file()),"Idle admission keeps its original runner and actual resume file")
 assert_pair(b,b.expected_e1_primary,b.expected_e1_backup,primary.bytes,backup.bytes,"Positive complete profiles/bytes")
 b.free() # No rescue save/Stop; isolated fixture artifacts retained.
 if failures:quit(1);return
 var external=make_case("user://loot-initial-miss-external-short.json",false)
 if external==null:quit(1);return
 external.set_process(true)
 var first_field:bool=await Wait.until(self,func():return external.field_calls>=1,12.0)
 emit_wait_diagnostic(external,"external-first",first_field,external.quest_loot.initial_e2)
 check(first_field,"Independent case reaches its first original idle attempt")
 if failures:external.free();quit(1);return
 var stale:Dictionary=external.quest_loot.initial_e2
 var count:int=external.field_calls
 var old_serial:int=external.quest_save_serial
 var external_primary:Dictionary=read_disk(external.save_path)
 var external_backup:Dictionary=read_disk(external.save_path+".bak")
 var external_cache:String=external.last_saved_payload
 # Test-only clock for this external-save case; derive full close from E1,
 # never from the returned candidate, result or observed closed disk.
 var close_sample:int=maxi(Time.get_ticks_msec(),external.quest_loot.last_ms)+1000
 var expected_used:int=external.quest_loot.base_used_ms+close_sample-external.quest_loot.anchor_ms
 var close_plan:Dictionary=State.progress(external.expected_e1_primary.quest_loot,State.STEP,State.identity(external.expected_e1_primary.quest_loot.entries[State.STEP]),expected_used,true)
 check(close_plan.get("ok",false),"Independent external close plan")
 if failures:external.free();quit(1);return
 var expected_closed:Dictionary=external.expected_e1_primary.duplicate(true)
 expected_closed.quest_loot=close_plan.ledger
 external.quest_loot.clock=func():return close_sample
 check(external.save() and external.quest_save_serial==old_serial+1,"Ordinary save still increments its serial outside the resume ticket")
 check(not external.quest_loot._initial_e2_owner(external,stale,true),"Generic no-op save retains the strict initial writer rejection")
 check(external.session._profile==external.expected_e1_primary and external.last_saved_payload==external_cache,"Ordinary save itself never changes full budget/profile")
 assert_pair(external,external.expected_e1_primary,external.expected_e1_backup,external_primary.bytes,external_backup.bytes,"Ordinary save before failure tick")
 if failures:external.free();quit(1);return
 var retired:bool=await Wait.until(self,func():return external.quest_loot.initial_e2.is_empty(),12.0)
 emit_wait_diagnostic(external,"external-retired",retired,stale)
 check(retired,"Next normal process retires the stale initial frame")
 if failures:external.free();quit(1);return
 check(external.field_calls==count,"No unauthorized attempt after ordinary save invalidates the old frame")
 check(external.capture_calls==0 and external.finish_calls==0 and external.capture_ticket.is_empty() and stale.serial==old_serial,"Ordinary save never obtains any resume ticket or reseals the retired frame")
 check(not external.quest_auto.running and external.quest_auto.phase=="stopped" and external.quest_loot.initial_failure.result.budget_close=="persisted","Stale seal revokes execution and independently closes the same budget")
 check(external.session._profile==expected_closed and external.last_saved_payload==JSON.stringify(expected_closed) and external.quest_save_serial==old_serial+2,"Exactly ordinary writer plus verified close; no new budget")
 assert_pair(external,expected_closed,external.expected_e1_primary,JSON.stringify(expected_closed).to_utf8_buffer(),external_primary.bytes,"Independent closed primary / original open backup")
 external.free()

# Expected profiles are derived from the pre-injection full baseline, never
# adopted from a returned writer candidate or a ticket being validated.
func disk_profile(disk:Dictionary,owner)->Dictionary:
 check(disk.get("ok",false),"Independent complete disk read including size/error/hash")
 if not disk.get("ok",false):return {}
 var parsed:Variant=JSON.parse_string(disk.bytes.get_string_from_utf8())
 check(parsed is Dictionary and owner._valid_profile(parsed),"Independent full disk profile validity")
 if not parsed is Dictionary:return {}
 return owner._normalize_numbers(parsed)
func assert_pair(b,expected_primary:Dictionary,expected_backup:Dictionary,primary_bytes:PackedByteArray,backup_bytes:PackedByteArray,label:String)->void:
 var primary:Dictionary=read_disk(b.save_path)
 var backup:Dictionary=read_disk(b.save_path+".bak")
 check(disk_profile(primary,b.session)==expected_primary and disk_profile(backup,b.session)==expected_backup,label+": both full independent disk profiles")
 if not primary.get("ok",false) or not backup.get("ok",false):return
 check(primary.bytes==primary_bytes and backup.bytes==backup_bytes,label+": both full byte arrays, correct previous generation")
func negative_case(mode:String)->void:
 var b=make_case("user://loot-initial-miss-"+mode+".json",true)
 if b==null:return
 var original_owner=b.session
 var original_profile_ref:Dictionary=b.session._profile
 var baseline:Dictionary=b.session._profile.duplicate(true)
 var expected:Dictionary=baseline.duplicate(true)
 var initial:Dictionary=b.quest_loot.initial_e2
 var ready:Dictionary=b.quest_loot.ready_frame
 var serial:int=b.quest_save_serial
 var cache:String=b.last_saved_payload
 var primary:Dictionary=read_disk(b.save_path)
 var backup:Dictionary=read_disk(b.save_path+".bak")
 var previous_profile:Dictionary=b.expected_e1_backup.duplicate(true)
 check(disk_profile(backup,b.session)==previous_profile,"Precase backup equals independently derived acquire generation: "+mode)
 check(disk_profile(primary,b.session)==baseline,"Precase primary equals independent full E1 baseline: "+mode)
 check(baseline.player.hp>1 and initial.serial==serial and not ready.has("continuation_gate"),"Valid pre-injection baseline: "+mode)
 if failures:b.free();return
 var before_super:int=b.boundary_super_calls
 if mode=="changed_payload":expected.player.hp-=1
 b.inject_mode=mode
 b.injection_armed=true
 b.set_process(true) # Engine drives original _process -> keep_resume_file -> capture -> inherited save -> finish.
 var finished:bool=await Wait.until(self,func():return b.finish_seen,12.0)
 emit_wait_diagnostic(b,mode,finished,initial)
 check(finished,"Actual first resume boundary reached: "+mode)
 if failures:b.free();return
 b.set_process(false)
 check(b.field_calls==1 and b.injection_count==1 and not b.injection_armed and b.capture_calls==1 and b.finish_calls==1,"One real miss/capture/injection/finish: "+mode)
 check(not b.capture_ticket.is_empty() and b.finish_ticket_same and b.ticket_aliases_ok,"Original nonempty ticket and reference/value-copy separation: "+mode)
 check(b.capture_serial==serial and b.capture_ticket.serial==serial and b.capture_frame.serial==serial,"Rejected finish never advances captured seal: "+mode)
 check(b.capture_profile_value==baseline and b.capture_ticket.profile==baseline and b.capture_frame.profile==baseline,"Immutable copied baseline is not aliased to changed live profile: "+mode)
 var expected_frame:Dictionary=b.capture_frame_value.duplicate(true)
 # profile_ref is intentionally live: damage changes that referenced value,
 # while both sealed profile value copies must remain the original baseline.
 expected_frame.profile_ref=expected.duplicate(true) if mode=="changed_payload" else baseline.duplicate(true)
 check(is_same(b.capture_frame.profile_ref,original_profile_ref) and is_same(b.capture_ticket.profile_ref,original_profile_ref) and b.capture_frame==expected_frame,"Complete old frame equals independently derived reference/value effects: "+mode)
 check(b.quest_save_serial==b.before_finish_serial and b.last_saved_payload==b.before_finish_cache and b.session._profile==b.before_finish_profile,"Finish adds no save/cache/profile mutation: "+mode)
 check(is_same(b.quest_loot.initial_e2,b.before_finish_initial) and b.quest_loot.initial_e2==b.before_finish_initial_value and is_same(b.quest_loot.ready_frame,b.before_finish_ready) and b.quest_loot.ready_frame==b.before_finish_ready_value,"Finish never writes or replaces current/successor frame: "+mode)
 var extra:int=0 if mode=="save_false_before" else (2 if mode=="extra_writer" else 1)
 check(b.quest_save_serial==serial+extra and b.boundary_super_calls==before_super+extra,"Only disclosed original writer count: "+mode)
 check(b.finish_saved==(mode not in ["save_false_before","save_false_after"]),"Actual save return propagated into finish: "+mode)
 check(b.session._profile==expected and b.session._profile.quest_loot==baseline.quest_loot and b.capture_owner._profile.quest_loot==baseline.quest_loot,"Complete live profile and original budget unchanged except specified damage: "+mode)
 check(b.quest_auto.identity.checkpoint()==initial.identity and b.quest_auto.phase=="loot_admission" and b.quest_auto.running and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty(),"No successor run, new budget, close, battle or reward: "+mode)
 if mode=="changed_payload":
  check(b.last_saved_payload==JSON.stringify(expected),"Changed save cache equals independently derived full expected profile")
  assert_pair(b,expected,baseline,JSON.stringify(expected).to_utf8_buffer(),primary.bytes,mode)
 else:
  check(b.last_saved_payload==cache,"No-op cache unchanged: "+mode)
  assert_pair(b,baseline,previous_profile,primary.bytes,backup.bytes,mode)
 if mode=="profile_replace":
  check(not is_same(b.session._profile,original_profile_ref) and is_same(b.session,original_owner) and original_profile_ref==baseline,"Equal content, distinct profile object; old object untouched")
 if mode=="owner_replace":
  check(not is_same(b.session,original_owner) and is_same(b.session,b.replacement_owner) and b.session._profile==baseline and original_owner._profile==baseline,"Distinct owner with equal complete profile; neither owner gets follow-on writes")
 if mode=="successor_frame":
  check(not is_same(b.quest_loot.initial_e2,initial) and b.quest_loot.initial_e2==initial and b.quest_loot.initial_e2.serial==serial,"Equal-but-distinct successor frame never resealed")
 if mode in ["save_false_before","save_false_after"]:
  check(b._resume_written_msec==-1,"Original failed-resume path preserves retry marker; no rescue save")
 b.free() # Keep isolated disk artifacts; do not Stop/close/rescue-save failed unit cases.
func run()->void:
 await positive_and_external()
 if failures:quit(1);return
 for mode in ["changed_payload","save_false_before","save_false_after","profile_replace","owner_replace","extra_writer","successor_frame"]:
  await negative_case(mode)
  if failures:quit(1);return
 print("INITIAL_MISS_RESUME ","PASS" if failures==0 else "FAIL")
 quit(0 if failures==0 else 1)
