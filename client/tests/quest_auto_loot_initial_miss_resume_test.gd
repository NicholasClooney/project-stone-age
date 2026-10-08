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
 var resume_noops:=0
 func _quest_loot_public_enabled()->bool:return true
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var reply:Dictionary=super._cmd_field_step(command)
  if quest_loot.attempt_call!=null:
   field_calls+=1
   field_times.append(Time.get_ticks_msec())
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
func make_case(path:String,resume:bool):
 if not fresh_path(path) or FileAccess.file_exists(path.get_basename()+".resume.json"):
  check(false,"New isolated regression profile/resume path")
  return null
 var b=ResumeBackend.new()
 b.encounter_catalog=MissCatalog.new()
 b.quest_loot=ObservedTimer.new()
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
 check(Backend.QUEST_LOOT_PUBLIC_ENABLED==false and b.automation.auto_tick and ack.get("ok",false) and ack.get("persisted",false),"Original public E1 with immutable test capability, normal auto_tick")
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
func positive_and_external()->void:
 var b=make_case("user://loot-initial-miss-resume-short.json",true)
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
 for i in range(1,b.field_times.size()):check(b.field_times[i]-b.field_times[i-1]>=500,"Original 500ms cadence is not bypassed")
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
 check(external.save() and external.quest_save_serial==old_serial+1,"Ordinary save still increments its serial outside the resume ticket")
 check(not external.quest_loot._initial_e2_owner(external,stale,true),"Generic no-op save retains the strict initial writer rejection")
 var retired:bool=await Wait.until(self,func():return external.quest_loot.initial_e2.is_empty(),12.0)
 emit_wait_diagnostic(external,"external-retired",retired,stale)
 check(retired,"Next normal process retires the stale initial frame")
 if failures:external.free();quit(1);return
 check(external.field_calls==count,"No unauthorized attempt after ordinary save invalidates the old frame")
 check(external.capture_calls==0 and external.finish_calls==0 and external.capture_ticket.is_empty() and stale.serial==old_serial,"Ordinary save never obtains any resume ticket or reseals the retired frame")
 check(external.session._profile==external.expected_e1_primary and external.last_saved_payload==external_cache and external.quest_save_serial==old_serial+1,"Generic save preserves complete profile and budget with exactly one writer")
 assert_pair(external,external.expected_e1_primary,external.expected_e1_backup,external_primary.bytes,external_backup.bytes,"Generic save negative")
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
