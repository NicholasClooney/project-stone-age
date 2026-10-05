extends "res://tests/quest_auto_loot_admission_test.gd"
## Real clock Callable reentry, internal run fixtures; never a public start.
class ObservationLog extends Node:
 var values:Array=[]
func observe(b)->Dictionary:
 var q=b.quest_auto;var t=b.quest_loot
 return {"timer":t.admission_timer_snapshot(),"lifetime":t.lifetime,"admission":t.admission,"clock":t.clock,"identity":q.identity.checkpoint(),"connection":q.connection,"client":q.client,"running":q.running,"phase":q.phase,"nav":q.navigation.key,"profile":b.session.snapshot(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"disk":FileAccess.get_file_as_string(b.save_path)}
func run()->void:
 for mode in ["normal","identity","lifetime","newsave","cancel","clock","ready","backward","bool","fraction","nan","infinity"]:
  var b=ObservedBackend.new()
  if not setup(b,"user://loot-admission-clock-"+mode+".json"):check(false,"Clock fixture setup");b.free();quit(1);return
  var timer=b.quest_loot;var old_life=timer.lifetime
  if mode=="backward":timer.last_ms=2000
  var reached:Array=[false]
  var observation_log=ObservationLog.new()
  var log_weak:WeakRef=weakref(observation_log)
  var timer_weak:WeakRef=weakref(timer)
  var backend_weak:WeakRef=weakref(b)
  var returned:Variant=1000
  match mode:
   "bool":returned=true
   "fraction":returned=1000.5
   "nan":returned=NAN
   "infinity":returned=INF
  timer.clock=func():
   if failures:return 1000
   var live_timer=timer_weak.get_ref()
   var host=backend_weak.get_ref()
   var log=log_weak.get_ref()
   check(is_instance_valid(live_timer) and is_instance_valid(host) and is_instance_valid(log) and is_same(live_timer,host.quest_loot),"Clock weak owners are alive and exact")
   if failures:return 1000
   check(not reached[0],"E1 startup clock called once")
   if failures:return 1000
   reached[0]=true
   check(host.commits==2 and host.session._profile.quest_loot.entries[KEY].open_span,"Clock follows actual acquired/opened durable candidate")
   if failures:return 1000
   match mode:
    "identity":
     host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
     host.quest_auto.phase="successor";host.quest_auto.navigation.key="clock-successor"
    "lifetime":
     # Same object, explicit internal lifetime replacement, NOT public start.
     live_timer.lifetime=RefCounted.new();live_timer.last_ms=7000;live_timer.anchor_ms=7000
     live_timer.cached_sample={"successor":"preserve"}
    "newsave":
     host.session._profile.player.gold+=7
     check(host.save(),"Actual complete successor save inside clock callback")
     if failures:return 1000
    "cancel":host.quest_auto.stop(host,"Clock callback actual cancellation")
    "clock":live_timer.clock=func():return 9000
    "ready":live_timer.ready_frame={"successor":"preserve"};live_timer.next_attempt_ms=9000
   if failures:return 1000
   log.values.append(observe(host))
   return returned
  var reply:Dictionary=timer.admit_prepared_run(b)
  var after:Array=observation_log.values
  if failures:b.free();observation_log.free();quit(1);return
  check(reached[0] and after.size()==1 and reply.get("persisted",false),"Actual open remains reported as persisted after clock")
  if failures:b.free();observation_log.free();quit(1);return
  if mode in ["identity","lifetime","newsave","cancel","clock","ready"]:
   check(not reply.get("ok",true) and observe(b)==after[0],"Clock ownership mismatch changes no successor timer/ready/nav/profile/cache/disk")
   if failures:b.free();observation_log.free();quit(1);return
  elif mode=="normal":
   check(reply.get("ok",false) and not is_same(old_life,timer.lifetime) and is_same(reply.lifetime,timer.lifetime) and is_same(reply.capability,timer.admission) and is_same(reply.ready_token,timer.ready_frame.ready_token) and reply.identity==b.quest_auto.identity.checkpoint() and reply.open_anchor_ms==1000 and timer.last_ms==1000 and timer.next_attempt_ms==1000,"Normal E1 installs exact same-call lifetime/capability/ready seal")
   if failures:b.free();observation_log.free();quit(1);return
   check(b.session.snapshot()==after[0].profile and b.last_saved_payload==after[0].cache and FileAccess.get_file_as_string(b.save_path)==after[0].disk,"Normal timer installation adds no persistence mutation")
   if failures:b.free();observation_log.free();quit(1);return
  else:
   check(not reply.get("ok",true) and timer.blocked and is_same(timer.lifetime,old_life) and timer.anchor_ms==-1 and timer.ready_frame.is_empty() and timer.last_ms==(2000 if mode=="backward" else -1),"Same-owner invalid/backward clock retains original blocked refusal without ready install")
   if failures:b.free();observation_log.free();quit(1);return
   check(b.session.snapshot()==after[0].profile and b.last_saved_payload==after[0].cache and FileAccess.get_file_as_string(b.save_path)==after[0].disk,"Clock refusal preserves actual durable open and complete profile/bytes")
   if failures:b.free();observation_log.free();quit(1);return
  print("E1 CLOCK FIXTURE ",mode," complete")
  b.free();observation_log.free()
 print("QUEST AUTO LOOT ADMISSION CLOCK: 0 failures; 12 internal clock fixtures")
 quit(0)
