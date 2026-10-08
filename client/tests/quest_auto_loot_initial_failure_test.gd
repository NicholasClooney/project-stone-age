extends "res://tests/quest_auto_loot_initial_miss_resume_test.gd"
## UNRUN independent failure-exit oracle. Fixed clock/physical partial-write seams
## are unit conveniences, never natural encounter or reward proof.
class FaultSession:
 extends "res://server/game_session.gd"
 var mode:=""
 var writes:=0
 var after_write:Callable
 var malformed_args:Dictionary={}
 var replace_close_result:=false
 var close_result:Dictionary={}
 var observed_begin:Dictionary={}
 var pre_io_calls:=0
 var pre_io_hook:Callable
 func begin_loot_failure_close(expected:Dictionary,args:Dictionary,path:String,host,timer,caller_cap:RefCounted)->Dictionary:
  var supplied:Dictionary=malformed_args if not malformed_args.is_empty() else args
  observed_begin=super.begin_loot_failure_close(expected,supplied,path,host,timer,caller_cap)
  return observed_begin
 func commit_loot_idle_transition(expected_profile:Dictionary,expected_ledger:Dictionary,operation:String,args:Dictionary,path:String,committed:Callable)->Dictionary:
  var actual:Dictionary=super.commit_loot_idle_transition(expected_profile,expected_ledger,operation,args,path,committed)
  return close_result.duplicate(true) if replace_close_result and operation=="close" else actual
 func _loot_failure_pre_io_ready()->bool:
  pre_io_calls+=1
  if pre_io_hook.is_valid():pre_io_hook.call()
  if mode in ["pre_io_always","multi_writer"]:return false
  return mode!="pre_io_once" or pre_io_calls>1
 func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
  if mode.is_empty():return super._write_profile_candidate(candidate,path)
  writes+=1
  if mode=="before":return false
  if mode=="multi_writer":
   super._write_profile_candidate(candidate,path)
   return super._write_profile_candidate(candidate,path)
  if mode=="partial_tmp":
   var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
   if file==null:return false
   file.store_string(JSON.stringify(candidate));file.flush();file.close()
   return false # Actual temporary bytes preserved; no rename or rescue.
  var ok:bool=super._write_profile_candidate(candidate,path)
  if after_write.is_valid():after_write.call()
  return false if mode=="false_after" else ok
class FaultTimer:
 extends "res://server/quest_auto_loot.gd"
 var obscure_read:=false
 var reads:Array[String]=[]
 var read_hook:Callable
 var bad_at:=0
 var bad_fact:Dictionary={}
 func _failure_disk(path:String)->Dictionary:
  reads.append(path)
  var actual:Dictionary=super._failure_disk(path)
  if read_hook.is_valid():read_hook.call(reads.size())
  if reads.size()==bad_at:return bad_fact.duplicate(true)
  if obscure_read:return {"state":"unknown"}
  return actual
class FailureHost:
 extends "res://server/backend.gd"
 var publications:=0
 func _publish()->void:
  publications+=1
  super._publish()
 func _init()->void:
  session=FaultSession.new() # Install before original _init wires the two session hooks.
  super()
  quest_loot=FaultTimer.new()
 func _quest_loot_public_enabled()->bool:return true
func new_failure_case(label:String):
 var path:String="user://loot-initial-failure-"+label+".json"
 if not fresh_path(path) or FileAccess.file_exists(path.get_basename()+".resume.json"):check(false,"Fresh failure path");return null
 var b=FailureHost.new();root.add_child(b)
 if not prepare_source(b,path):check(false,"Original source fixture");b.free();return null
 if not b.session.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y) or not b.save():check(false,"Original pre-E1 location/save");b.free();return null
 var prior:Dictionary=b.session._profile.duplicate(true)
 b.fee_attach(101)
 var ack:Dictionary=b.handle(start_command(1,101))
 check(ack.get("ok",false) and ack.get("persisted",false),"Original E1")
 if failures:b.free();return null
 var acquired:Dictionary=State.acquire(prior.quest_loot,State.STEP,str(ack.budget_identity.budget_id),str(ack.run_identity.run_id),30,0)
 var opened:Dictionary=State.open(acquired.ledger,State.STEP,State.identity(acquired.ledger.entries[State.STEP]))
 var open_profile:Dictionary=prior.duplicate(true);open_profile.quest_loot=opened.ledger
 var acquire_profile:Dictionary=prior.duplicate(true);acquire_profile.quest_loot=acquired.ledger
 assert_pair(b,open_profile,acquire_profile,JSON.stringify(open_profile).to_utf8_buffer(),JSON.stringify(acquire_profile).to_utf8_buffer(),"Independent E1 full pair")
 if failures:b.free();return null
 return b
# UNRUN. The six r3 failure cases retain full disk/profile oracles; the new
# contract permits subsequent ordinary saves to rotate these generations.
func contract_case(mode:String)->void:
 var b=new_failure_case("r3-"+mode)
 if b==null:return
 var baseline:Dictionary=b.session._profile.duplicate(true)
 var primary:Dictionary=read_disk(b.save_path)
 var backup:Dictionary=read_disk(b.save_path+".bak")
 var backup_profile:Dictionary=disk_profile(backup,b.session)
 var sample:int=maxi(Time.get_ticks_msec(),b.quest_loot.last_ms)+1000
 var used:int=b.quest_loot.base_used_ms+sample-b.quest_loot.anchor_ms
 var plan:Dictionary=State.progress(baseline.quest_loot,State.STEP,State.identity(baseline.quest_loot.entries[State.STEP]),used,true)
 check(plan.get("ok",false),"Independent frozen close plan")
 if failures:b.free();return
 var expected:Dictionary=baseline.duplicate(true);expected.quest_loot=plan.ledger
 b.quest_loot.clock=func():return sample
 check(b.save(),"Actual ordinary save invalidates initial seal")
 if failures:b.free();return
 var serial:int=b.quest_save_serial
 b.session.mode=mode
 if mode=="unknown_read":b.session.after_write=func():b.quest_loot.obscure_read=true
 if mode=="unproven_profile":b.session._profile.player.hp-=1
 b.set_process(true)
 check(await Wait.until(self,func():return not b.quest_auto.running,12.0),"Actual process reaches failure retirement")
 if failures:b.free();return
 b.set_process(false)
 if failures:b.free();return
 var record:Dictionary=b.quest_loot.initial_failure
 check(not record.is_empty(),"Actual obligation captured")
 if failures:b.free();return
 check(record.retry_count==0 and not record.prewrite_proven,"No bool-false-derived retry permission")
 if failures:b.free();return
 if mode=="unproven_profile":
  check(record.expected.is_empty() and record.cutoff==-1 and b.session.writes==0,"Unproven source cannot freeze a close or write")
  if failures:b.free();return
 else:
  check(record.cutoff==sample and record.expected==expected and record.expected_payload==JSON.stringify(expected) and record.writer_attempts==1,"Candidate and cutoff frozen before exactly one original writer")
  if failures:b.free();return
 if mode in ["success","unknown_read","false_after"]:
  assert_pair(b,expected,baseline,JSON.stringify(expected).to_utf8_buffer(),primary.bytes,"Full closed/open physical generations")
 else:
  assert_pair(b,baseline,backup_profile,primary.bytes,backup.bytes,"Original open/acquire physical generations")
 if mode=="partial_tmp":check(read_disk(b.save_path+".tmp").bytes==JSON.stringify(expected).to_utf8_buffer(),"Actual partial tmp retained by failure call")
 if failures:b.free();return
 if mode=="success":
  check(record.result.budget_close=="persisted" and not b.quest_loot.failure_pending_for_profile(b),"Verified close completes exact obligation")
  if failures:b.free();return
  b.free();return
 check(b.quest_loot.failure_pending_for_profile(b),"Only this profile's new loot entry is pending")
 if failures:b.free();return
 var pending_result:Dictionary=b.handle(start_command(2,101))
 check(not pending_result.get("ok",true) and pending_result.get("reason","")=="刷物记录待确认。","Actual loot Start refuses with explicit pending reason")
 if failures:b.free();return
 var old_identity:Dictionary=b.quest_auto.identity.checkpoint()
 var stop:Dictionary=b._cmd_quest_auto_stop({})
 check(stop.get("ok",false) and b.quest_auto.identity.checkpoint()!=old_identity and b.quest_loot.failure_pending_for_profile(b),"Ordinary Stop is unrestricted; obligation survives identity invalidation")
 if failures:b.free();return
 var writes:int=b.session.writes
 var before_serial:int=b.quest_save_serial
 var before_profile:Dictionary=b.session._profile.duplicate(true)
 var before_cache:String=b.last_saved_payload
 var before_primary:Dictionary=read_disk(b.save_path)
 var before_backup:Dictionary=read_disk(b.save_path+".bak")
 var before_message:String=b.quest_auto.message
 var before_publications:int=b.publications
 if mode=="unknown_read":
  b.quest_loot.obscure_read=false
  check(record.installed_proven and b.quest_loot.confirm_failed_initial_readonly(b),"Original installed close can be confirmed by reads only after identity change")
  if failures:b.free();return
  check(not b.quest_loot.failure_pending_for_profile(b) and record.result.stage=="readonly_confirmed","Only matching ledger obligation retires")
  if failures:b.free();return
 else:
  check(not b.quest_loot.confirm_failed_initial_readonly(b) and b.quest_loot.failure_pending_for_profile(b),"False/partial/unproven cannot confirm or earn retry")
  if failures:b.free();return
 check(b.session.writes==writes and b.quest_save_serial==before_serial and b.session._profile==before_profile and b.last_saved_payload==before_cache and b.quest_auto.message==before_message and b.publications==before_publications,"Old confirmation performs no writer/profile/message/publication")
 if failures:b.free();return
 check(read_disk(b.save_path).bytes==before_primary.bytes and read_disk(b.save_path+".bak").bytes==before_backup.bytes,"Read-only confirmation preserves complete disk bytes")
 if failures:b.free();return
 if mode!="unknown_read":
  # Authorized ordinary saves remain available after failure handling.
  # Freeze all original evidence in the old record; DO NOT claim physical
  # main/bak/tmp preservation after the following authorized normal writer.
  var frozen_expected:Dictionary=record.expected.duplicate(true)
  var frozen_facts:Array=record.baseline_facts.duplicate(true)
  var expected_live:Dictionary=before_profile.duplicate(true)
  expected_live.player.hp-=1
  b.session.mode="";b.session._profile.player.hp-=1
  check(b.save() and b.session._profile==expected_live,"Normal unrelated profile save is not blocked")
  if failures:b.free();return
  check(is_same(record,b.quest_loot.initial_failure) and record.expected==frozen_expected and record.baseline_facts==frozen_facts and record.retry_count==0 and b.quest_loot.failure_pending_for_profile(b),"Only in-memory evidence survives ordinary save; no new loot/retry authority")
  if failures:b.free();return
  assert_pair(b,expected_live,disk_profile(before_primary,b.session),JSON.stringify(expected_live).to_utf8_buffer(),before_primary.bytes,"Normal save rotates actual generations: subsequent legal save may rotate archived failure facts")
 b.free()
func retry_case(mode:String)->void:
 var b=new_failure_case("r4-retry-"+mode)
 if b==null:return
 var profile:Dictionary=b.session._profile.duplicate(true)
 var primary:Dictionary=read_disk(b.save_path);var backup:Dictionary=read_disk(b.save_path+".bak")
 var backup_profile:Dictionary=disk_profile(backup,b.session)
 var serial:int=b.quest_save_serial
 var sample:int=maxi(Time.get_ticks_msec(),b.quest_loot.last_ms)+1000
 var used:int=b.quest_loot.base_used_ms+sample-b.quest_loot.anchor_ms
 var plan:Dictionary=State.progress(profile.quest_loot,State.STEP,State.identity(profile.quest_loot.entries[State.STEP]),used,true)
 check(plan.get("ok",false),"Independent retry close plan")
 if failures:b.free();return
 var expected:Dictionary=profile.duplicate(true);expected.quest_loot=plan.ledger
 b.quest_loot.clock=func():return sample
 b.session.mode="pre_io_once" if mode in ["owner_successor","session_successor","reentrant","extra_serial"] else mode
 var result:Dictionary=b.quest_loot._retire_initial_failure(b,b.quest_loot.initial_e2)
 var record:Dictionary=b.quest_loot.initial_failure
 check(not result.ok and b.quest_save_serial==serial and b.session._profile==profile,"First pre-IO/opaque/multiple writer failure does not install")
 if failures:b.free();return
 assert_pair(b,profile,backup_profile,primary.bytes,backup.bytes,"Original complete pair before retry")
 if failures:b.free();return
 var proven:bool=mode in ["pre_io_once","pre_io_always","owner_successor","session_successor","reentrant","extra_serial"]
 check(record.prewrite_proven==proven,"Only one actual original pre-IO refusal mints proof")
 if failures:b.free();return
 var first_writes:int=b.session.writes
 var duplicate:Dictionary=b.session.begin_loot_failure_close(profile,{"step_id":State.STEP,"expected_entry":State.identity(profile.quest_loot.entries[State.STEP]),"total_used_ms":used},b.save_path,b,b.quest_loot,record.revoked_cap)
 check(not duplicate.get("ok",true) and duplicate.get("stage")=="duplicate_close_operation" and b.session.writes==first_writes,"Repeated begin cannot reset the obligation's retry allowance")
 if failures:b.free();return
 check(b.session.loot_failure_retryable(RefCounted.new())==false,"Forged opaque token earns no permission")
 if failures:b.free();return
 var old_message:String=b.quest_auto.message
 var old_identity:Dictionary=b.quest_auto.identity.checkpoint()
 if mode=="owner_successor":
  b.quest_auto.identity.begin();b.quest_auto.message="successor owns message"
 if mode=="session_successor":
  var replacement=FaultSession.new();replacement._profile=b.session._profile.duplicate(true)
  b.session=replacement;b.quest_auto.message="successor owns message"
 if mode=="extra_serial":check(b.save(),"Actual extra ordinary writer invalidates proof scope")
 if failures:b.free();return
 if mode=="reentrant":
  b.session.pre_io_hook=func():check(not b.quest_loot.retry_failed_initial_once(b),"Retry consumed before pre-IO hook can reenter")
 var retry_ok:bool=b.quest_loot.retry_failed_initial_once(b)
 var should_close:bool=mode in ["pre_io_once","reentrant"]
 check(retry_ok==should_close,"Exact bounded retry outcome: "+mode)
 if failures:b.free();return
 if should_close:
  check(record.cutoff==sample and record.expected==expected and record.retry_count==1 and record.writer_attempts==2 and b.quest_save_serial==serial+1,"Exactly same cutoff/candidate; only successful writer commits once")
  if failures:b.free();return
  assert_pair(b,expected,profile,JSON.stringify(expected).to_utf8_buffer(),primary.bytes,"Independent full retry-close pair")
 else:
  check(b.session._profile==profile and b.quest_save_serial==serial+(1 if mode=="extra_serial" else 0),"No unproven retry installation")
  if failures:b.free();return
  assert_pair(b,profile,backup_profile,primary.bytes,backup.bytes,"No retry rescue/write of original pair")
 if mode=="pre_io_always":check(record.retry_count==1 and b.session.pre_io_calls==2,"Second pre-IO failure cannot mint a third attempt")
 if failures:b.free();return
 if mode=="multi_writer":check(record.write_receipts[0].receipts[0].entries==2 and not record.prewrite_proven,"Two original writer entries invalidate the once-only proof")
 if failures:b.free();return
 var count:int=b.session.writes
 check(not b.quest_loot.retry_failed_initial_once(b) and b.session.writes==count,"No second retry")
 if failures:b.free();return
 if mode in ["owner_successor","session_successor"]:check(b.quest_auto.message=="successor owns message" and (mode=="session_successor" or b.quest_auto.identity.checkpoint()!=old_identity),"Old proof cannot mutate successor")
 else:check(b.quest_auto.message==old_message,"Retry performs no runner message mutation")
 if failures:b.free();return
 b.free()
func write_fixture(path:String,profile:Dictionary)->void:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 if file==null:check(false,"Fresh isolated fixture writer");return
 file.store_string(JSON.stringify(profile));file.flush()
 check(file.get_error()==OK,"Complete isolated fixture bytes")
 file.close()
func independently_retired(ledger:Dictionary)->Dictionary:
 # Field oracle deliberately DOES NOT call State.recovered/progress/reset.
 var expected:Dictionary=ledger.duplicate(true)
 var entry:Dictionary=expected.entries[State.STEP]
 entry.open_span=false;entry.settled_seq=entry.issued_seq
 entry.revision+=1;entry.recovery_blocked=false
 expected.recovery_blocked=false
 return expected
func cold_case(fallback:bool,reward:bool)->void:
 var label:String="r4-cold-%s-%s"%[str(fallback),str(reward)]
 var source=new_failure_case(label)
 if source==null:return
 var path:String=source.save_path
 var before:Dictionary=source.session._profile.duplicate(true)
 var old_run:String=source.quest_auto.identity.run_id
 var old_quest_intent:Dictionary=source.quest_auto.resume_state()
 # Explicit serialized-ledger fixture: no claim of naturally received reward.
 var entry:Dictionary=before.quest_loot.entries[State.STEP]
 entry.limit_ms=420000 if fallback else 1800000
 entry.used_ms=12345;entry.saved_battles=3;entry.new_items=1 if reward else 0
 entry.issued_seq=4;entry.settled_seq=3;entry.revision=9
 if reward:source.session.OriginalEquipment.add(before,2760)
 before.player.gold+=17
 check(source.session._valid_profile(before),"Valid complete selected recovery source")
 if failures:source.free();return
 var expected_ledger:Dictionary=independently_retired(before.quest_loot)
 var selected_bytes:PackedByteArray=JSON.stringify(before).to_utf8_buffer()
 source.free() # No Stop/save; all following bytes are explicit cold fixtures.
 write_fixture(path+".bak",before)
 if failures:return
 if fallback:
  var broken:=FileAccess.open(path,FileAccess.WRITE)
  if broken==null:check(false,"Corrupt-primary fixture open");return
  broken.store_string(JSON.stringify({"version":8,"invalid_profile":true}));broken.close()
 else:write_fixture(path,before)
 if failures:return
 # Archive both exact source files before the real cold writer can rotate.
 for suffix in ["",".bak"]:
  var original:Dictionary=read_disk(path+suffix)
  check(original.get("ok",false),"Full pre-load source bytes")
  if failures:return
  var original_archive:=FileAccess.open(path+suffix+".cold-source.archive",FileAccess.WRITE)
  if original_archive==null:check(false,"Source archive opens");return
  original_archive.store_buffer(original.bytes);original_archive.flush()
  check(original_archive.get_error()==OK,"Complete source archive retained")
  original_archive.close()
 # Differential oracle only for pre-existing login/equipment migrations.
 # The entire ledger expectation above is independent of production recovery.
 var control_path:String=path+"-control.json"
 if not fresh_path(control_path):return
 var control_input:Dictionary=before.duplicate(true);control_input.quest_loot=expected_ledger
 write_fixture(control_path,control_input)
 if failures:return
 var control=preload("res://server/game_session.gd").new()
 control.login_clock=func():return 1700000000
 control.login_rng.seed=741
 check(control.load_game(control_path),"Independent already-retired control migration")
 if failures:return
 var expected:Dictionary=control.snapshot()
 var b=FailureHost.new();root.add_child(b);b.set_process(false);b.save_path=path
 b.session.login_clock=func():return 1700000000
 b.session.login_rng.seed=741
 check(b.load_profile(path),"Actual Backend/Session cold load")
 if failures:b.free();return
 check(b.session.last_load_source==("backup" if fallback else "primary") and b.session._profile==expected and b.last_saved_payload==JSON.stringify(expected),"Whole loaded profile matches independent ledger plus unchanged migration oracle")
 check(b.session._profile.quest_loot==expected_ledger and b.session._profile.original_items==before.original_items and b.session._profile.original_instances==before.original_instances and b.session._profile.next_original_uid==before.next_original_uid and b.session._profile.player.gold==before.player.gold and b.session._profile.completed_battles==before.completed_battles,"All saved lower-bound counters, reward bytes, UIDs, gold and settled battles retained")
 assert_pair(b,expected,before,JSON.stringify(expected).to_utf8_buffer(),selected_bytes,"Cold retirement primary/selected previous generation")
 check(not b.session.last_loot_cold_retirement.is_empty() and b.quest_loot.projection(b).reason.contains("已存用时下界"),"Cold retirement is explicitly disclosed")
 # Real old sidecar, including an automation payload that must not resurrect.
 var old_sidecar:Dictionary={"version":b.automation.RESUME_VERSION,"kind":"hunt","map_id":before.location.map_id,"cell":[before.location.x,before.location.y],"quest_auto":old_quest_intent}
 var old_sidecar_bytes:PackedByteArray=JSON.stringify(JSON.from_native(old_sidecar)).to_utf8_buffer()
 var sidecar:=FileAccess.open(b._resume_file(),FileAccess.WRITE)
 if sidecar==null:check(false,"Actual isolated sidecar fixture");b.free();return
 sidecar.store_buffer(old_sidecar_bytes);sidecar.flush();sidecar.close()
 # Independent archived bytes survive normal loader's original consume/remove.
 var archive:=FileAccess.open(path+".old-sidecar.archive",FileAccess.WRITE)
 if archive==null:check(false,"Sidecar evidence archive");b.free();return
 archive.store_buffer(old_sidecar_bytes);archive.close()
 b.load_resume()
 check(not b.quest_auto.running and b.automation.pending_resume.is_empty() and not b.battle_open and b.quest_loot.initial_e2.is_empty(),"Old loot sidecar never restores runner/companion automation/battle")
 check(b.session._profile==expected and read_disk(path).bytes==JSON.stringify(expected).to_utf8_buffer(),"Sidecar rejection cannot change loaded profile")
 var acquired:Dictionary=State.acquire(expected_ledger,State.STEP,ID,RUN,180,99)
 check(acquired.get("ok",false) and acquired.ledger==expected_ledger,"Acquire cannot replace old limit, budget, origin, generation or counters")
 if failures:b.free();return
 check(b._restore_quest_saved_position(),"Original saved authority position for fresh run")
 if failures:b.free();return
 if not reward:
  b.fee_attach(101)
  var ack:Dictionary=b.handle(start_command(3,101))
  check(ack.get("ok",false) and b.quest_auto.identity.run_id!=old_run,"Actual same-step public Start creates only a fresh runner")
  if failures:b.free();return
  var reopened:Dictionary=expected_ledger.duplicate(true)
  reopened.entries[State.STEP].open_span=true
  reopened.entries[State.STEP].issued_seq+=1;reopened.entries[State.STEP].revision+=1
  var expected_open:Dictionary=expected.duplicate(true);expected_open.quest_loot=reopened
  check(b.session._profile==expected_open and reopened.entries[State.STEP].limit_ms-reopened.entries[State.STEP].used_ms==(420000 if fallback else 1800000)-12345,"Fresh run retains remaining budget, never full fresh allowance")
  assert_pair(b,expected_open,expected,JSON.stringify(expected_open).to_utf8_buffer(),JSON.stringify(expected).to_utf8_buffer(),"Fresh-run open/retired full generations")
  var ledger_copy:Dictionary=reopened.duplicate(true)
  b.session._profile.player.hp-=1
  check(b.save() and b.session._profile.quest_loot==ledger_copy,"Ordinary changed save preserves exact current ledger")
 else:
  b.fee_attach(101)
  var ack:Dictionary=b.handle(start_command(3,101))
  check(not ack.get("ok",true) and b.session._profile==expected and preload("res://server/quest_auto_jewel_loot_plan.gd").select(b).get("status")=="done","Existing inventory target still obeys original completed-goal gate")
 b.free()
# Static-only r5 oracle: drive the actual retire -> begin -> commit -> writer
# chain. Args are altered at begin; result anomalies only AFTER original commit.
func boundary_case(kind:String,value:Variant)->void:
 var label:String="r5-"+kind+"-"+str(boundary_serial)
 boundary_serial+=1
 var b=new_failure_case(label)
 if b==null:return
 var profile:Dictionary=b.session._profile.duplicate(true)
 var primary:Dictionary=read_disk(b.save_path);var backup:Dictionary=read_disk(b.save_path+".bak")
 var serial:int=b.quest_save_serial
 var sample:int=maxi(Time.get_ticks_msec(),b.quest_loot.last_ms)+1000
 var used:int=b.quest_loot.base_used_ms+sample-b.quest_loot.anchor_ms
 b.quest_loot.clock=func():return sample
 b.session.mode="pre_io_always"
 if kind=="result":
  b.session.replace_close_result=true;b.session.close_result=value.duplicate(true)
 else:
  var args:Dictionary={"step_id":State.STEP,"expected_entry":State.identity(profile.quest_loot.entries[State.STEP]),"total_used_ms":used}
  if kind=="missing":args.erase(value)
  elif kind=="identity_field":args.expected_entry[value[0]]=value[1]
  else:args[kind]=value
  b.session.malformed_args=args
 b.quest_loot._retire_initial_failure(b,b.quest_loot.initial_e2)
 var record:Dictionary=b.quest_loot.initial_failure
 check(not record.is_empty() and not record.prewrite_proven and not record.installed_proven,"Bad boundary never proves retry or install")
 if failures:b.free();return
 if kind=="result":
  check(b.session.pre_io_calls==1 and b.session.writes==1,"Unknown result follows actual original pre-IO refusal")
  if failures:b.free();return
  var envelope:Dictionary=b.session.observed_begin
  check(envelope.ok==null and envelope.receipts[0].ok==null and envelope.receipts[0].installed==null and envelope.result==value,"Missing/wrong boolean facts remain unknown; raw result retained")
 else:
  check(b.session.observed_begin.get("stage")=="close_args_rejected" and b.session.writes==0 and b.session.pre_io_calls==0,"Bad args rejected before writer")
 if failures:b.free();return
 check(not b.quest_loot.retry_failed_initial_once(b) and b.quest_save_serial==serial and b.session._profile==profile,"No retry, successor write, or budget change")
 if failures:b.free();return
 assert_pair(b,profile,disk_profile(backup,b.session),primary.bytes,backup.bytes,"Independent full boundary pair")
 if failures:b.free();return
 # A failed load must not erase this obligation OR an existing loaded hint.
 var hint:Dictionary={"reason":"prior cold disclosure","ledger":profile.quest_loot.duplicate(true)}
 b.session.last_loot_cold_retirement=hint.duplicate(true)
 var proof:Dictionary=b.session._loot_failure_write
 var failed_path:String=b.save_path+".never-created"
 check(fresh_path(failed_path),"Failure-load fixture path absent")
 if failures:b.free();return
 check(not b.session.load_game(failed_path) and b.session.last_loot_cold_retirement==hint and is_same(b.quest_loot.initial_failure,record) and is_same(b.session._loot_failure_write,proof) and b.session._profile==profile,"Failed missing-source load preserves hint, pending record and writer proof")
 if failures:b.free();return
 b.session._pending={"r5_guard":true}
 check(not b.session.load_game(failed_path) and b.session.last_loot_cold_retirement==hint and is_same(b.quest_loot.initial_failure,record),"Early pending-load rejection retains obligation and hint")
 b.session._pending={}
 if failures:b.free();return
 assert_pair(b,profile,disk_profile(backup,b.session),primary.bytes,backup.bytes,"Failed-load whole pair unchanged")
 b.free()
var boundary_serial:=0
func boundary_cases()->void:
 for key in ["step_id","expected_entry","total_used_ms"]:
  boundary_case("missing",key)
  if failures:return
 for value in [null,17,true,{},[]]:
  boundary_case("step_id",value)
  if failures:return
 for value in [null,17,"unknown",{}, {"budget_id":"bad","generation":0,"revision":0}]:
  boundary_case("expected_entry",value)
  if failures:return
 for value in [null,true,"1",1.0,-1,State.MAX_MSEC+1]:
  boundary_case("total_used_ms",value)
  if failures:return
 for value in [["budget_id",9],["generation",0.0],["revision",false],["revision",-1],["generation",State.MAX_COUNTER+1]]:
  boundary_case("identity_field",value)
  if failures:return
 for value in [{},{"ok":null},{"ok":0},{"ok":"unknown"},{"ok":[],"installed":"unknown"}]:
  boundary_case("result",value)
  if failures:return
 print("LOOT_RECOVERY_CASE boundary-29-complete")
func run()->void:
 # The original nine cases execute unchanged except their reviewed external
 # close oracle. Do not call parent.run(), which owns quit().
 await positive_and_external()
 if failures:quit(1);return
 for mode in ["changed_payload","save_false_before","save_false_after","profile_replace","owner_replace","extra_writer","successor_frame"]:
  await negative_case(mode)
  if failures:quit(1);return
 print("LOOT_RECOVERY_CASE original-nine-complete")
 for mode in ["success","unknown_read","before","partial_tmp","false_after","unproven_profile"]:
  await contract_case(mode)
  if failures:quit(1);return
  print("LOOT_RECOVERY_CASE contract ",mode)
 for mode in ["pre_io_once","pre_io_always","before","multi_writer","owner_successor","session_successor","reentrant","extra_serial"]:
  retry_case(mode)
  if failures:quit(1);return
  print("LOOT_RECOVERY_CASE retry ",mode)
 for fallback in [false,true]:
  for reward in [false,true]:
   cold_case(fallback,reward)
   if failures:quit(1);return
   print("LOOT_RECOVERY_CASE cold ",fallback," ",reward)
 boundary_cases()
 if failures:quit(1);return
 print("LOOT_RECOVERY_RESULT ","PASS" if failures==0 else "FAIL")
 quit(0 if failures==0 else 1)
