extends "res://tests/quest_auto_loot_admission_test.gd"
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
class ResumeObservedBackend:
 extends ObservedBackend
 var after_resume_save:Callable
 func save()->bool:
  var result:bool=super.save()
  if result and after_resume_save.is_valid():after_resume_save.call(self)
  return result
func after_close_resume_cases()->bool:
 for mode in ["resume_clock","resume_publish","resume_save"]:
  var b=ResumeObservedBackend.new()
  if not setup(b,"user://loot-after-close-resume-"+mode+".json"):check(false,"After-close resume setup");b.free();return false
  b.session.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y)
  check(b.save(),"Persist actual fixture authority before resume callbacks")
  if failures:b.free();return false
  var clock_ms:Array=[1000]
  b.quest_loot.clock=func():return clock_ms[0]
  check(b.quest_loot.admit_prepared_run(b).ok,"After-close resume actual durable admission")
  if failures:b.free();return false
  clock_ms[0]=2500
  var fired:Array=[false];var successor:Array=[];var payload:Array=[];var old_ticket:Array=[]
  var replace:Callable=func(host):
   if fired[0]:return
   fired[0]=true
   check(host.commits==3 and not host.session._profile.quest_loot.entries[KEY].open_span,"Original close is durable before resume callback")
   if failures:return
   host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
   host.quest_auto.connection=72;host.quest_auto.client="successor-internal"
   host.quest_auto.running=true;host.quest_auto.phase="successor"
   host.quest_auto.navigation.key="successor-navigation"
   host.automation.running=true;host.automation.single_battle=true
   host.session._profile.player.gold+=7
   check(host.save(),"Callback successor complete save succeeds")
   if failures:return
   successor.append(host.quest_auto.identity.checkpoint())
   payload.append(host.last_saved_payload)
  if mode=="resume_save":b.after_resume_save=replace
  elif mode=="resume_publish":
   b.event.connect(func(message):
    if message.get("type")=="profile":replace.call(b))
   b.resume_clock=func():b.publish();return 9000
  else:b.resume_clock=func():replace.call(b);return 9000
  var captured:Dictionary=b.quest_loot.capture_idle_close(b)
  check(not captured.is_empty(),"Capture exact old close ticket for replay negative")
  if failures:b.free();return false
  old_ticket.append(captured)
  b.quest_auto.suspend(b)
  if failures:b.free();return false
  check(fired[0] and successor.size()==1 and b.quest_auto.identity.checkpoint()==successor[0] and b.quest_auto.connection==72 and b.quest_auto.client=="successor-internal","After-close resume callback new run identity is never adopted by old ticket")
  if failures:b.free();return false
  check(b.commits==3 and not b.session._profile.quest_loot.entries[KEY].open_span and b.quest_auto.navigation.key=="successor-navigation" and b.automation.running and b.quest_auto.phase=="successor","After durable old close, suspend cannot clear new navigation or stop new automation")
  if failures:b.free();return false
  check(payload.size()==1 and b.last_saved_payload==payload[0] and FileAccess.get_file_as_string(b.save_path)==payload[0],"Old close return cannot overwrite callback successor full save")
  if failures:b.free();return false
  check(not b.quest_loot.finish_idle_close(b,old_ticket[0]).get("ok",false),"Direct old finish refuses arbitrary current identity")
  if failures:b.free();return false
  b.free()
 return true
func run()->void:
 if not after_close_resume_cases():quit(1);return
 for mode in ["stop","detach","suspend","savefail_retry","suspend_savefail_retry","observer_newsave","observer_newrun"]:
  var b=ObservedBackend.new();var clock_ms:Array=[1000];var calls:Array=[0]
  if not setup(b,"user://loot-idle-stop-"+mode+".json"):check(false,"Close fixture setup");b.free();quit(1);return
  b.quest_loot.clock=func():calls[0]+=1;return clock_ms[0]
  check(b.quest_loot.admit_prepared_run(b).ok,"Real durable E1 admission")
  if failures:b.free();quit(1);return
  var timer=b.quest_loot;var life=timer.lifetime;clock_ms[0]=2500
  var before:Dictionary=b.session.snapshot();var disk:String=FileAccess.get_file_as_string(b.save_path)
  if mode in ["savefail_retry","suspend_savefail_retry"]:
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own close blocker")
   if failures:b.free();quit(1);return
  var later:Array=[]
  if mode=="observer_newsave":
   b.observer=func(host):
    if host.commits==3:
     host.session._profile.player.gold+=3
     check(host.save(),"Later manual save during close callback")
     if failures:return
     later.append(host.last_saved_payload)
  if mode=="observer_newrun":
   b.observer=func(host):
    if host.commits==3:
     host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
     later.append(host.quest_auto.identity.checkpoint())
  var original_identity:Dictionary=b.quest_auto.identity.checkpoint()
  if mode=="detach":b.quest_auto.detach(b,71)
  elif mode in ["suspend","suspend_savefail_retry"]:b.quest_auto.suspend(b)
  else:b.quest_auto.stop(b,"Internal stop fixture")
  if failures:b.free();quit(1);return
  if mode in ["suspend","suspend_savefail_retry"]:
   check(b.quest_auto.shutdown_intent.get("identity",{})==original_identity,"Shutdown intent preserves the pre-revocation identity")
   if failures:b.free();quit(1);return
  check(timer.ready_frame.is_empty() and not timer.attempt_once(b).ok,"Stop invalidates all next-attempt capability")
  if failures:b.free();quit(1);return
  if mode in ["savefail_retry","suspend_savefail_retry"]:
   check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk and timer.storage_paused and not timer.close_pending.is_empty(),"Real failed close leaves entire profile/disk and frozen repair obligation")
   if failures:b.free();quit(1);return
   check(b.quest_auto.snapshot(b).budget.activity=="storage_paused","Stopped failed-close projection remains storage paused")
   if failures:b.free();quit(1);return
   var token=timer.close_pending.token;var sampled:int=calls[0];clock_ms[0]+=999999
   var repair_identity:Dictionary=b.quest_auto.identity.checkpoint()
   b.quest_auto.stop(b,"Repeated stop during repair")
   check(b.quest_auto.identity.checkpoint()==repair_identity and is_same(timer.close_pending.token,token) and calls[0]==sampled,"Repeated stop preserves exact repair identity and sample")
   if failures:b.free();quit(1);return
   check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own close blocker removed after all failure checks")
   if failures:b.free();quit(1);return
   check(timer.retry_idle_close(b,token).ok and calls[0]==sampled,"Repair retries the exact frozen sample without clock calls")
   if failures:b.free();quit(1);return
   check(not timer.retry_idle_close(b,token).ok,"Committed close token cannot replay")
   if failures:b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  check(not entry.open_span and entry.used_ms==1500 and entry.saved_battles==0 and entry.new_items==0,"Idle close stores one total and never invents battle/drop counts")
  if failures:b.free();quit(1);return
  if mode=="observer_newrun":
   check(later.size()==1 and b.quest_auto.identity.checkpoint()==later[0] and is_same(timer.lifetime,life) and timer.anchor_ms>=0,"Old return does not retire timer after run ownership changes")
  else:check(timer.anchor_ms<0 and timer.close_pending.is_empty(),"Only captured matching lifetime retires")
  if failures:b.free();quit(1);return
  if mode=="observer_newsave":
   check(later.size()==1 and b.last_saved_payload==later[0] and FileAccess.get_file_as_string(b.save_path)==later[0],"Later save exact payload wins over old close return")
   if failures:b.free();quit(1);return
  var copied:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
  check(copied.get("ok",false),"Full close disk validates")
  if failures:b.free();quit(1);return
  check(copied.profile==b.session.snapshot(),"Complete close profile equals actual disk")
  if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT IDLE STOP: %d failures; no-battle slice, battle cancellation separate"%failures)
 quit(1 if failures else 0)
