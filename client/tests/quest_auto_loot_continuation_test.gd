extends "res://tests/quest_auto_loot_battle_cancel_test.gd"
## Internal seed4101/group169 evidence, not target-drop/public/WS acceptance.
const Wait=preload("res://tests/support/wait.gd")
const Loot=preload("res://server/quest_auto_loot.gd")
class WatchedRunner:
 extends "res://server/quest_auto.gd"
 var after_tick:Callable
 var failed:Callable
 func tick(b,delta:float)->void:
  super.tick(b,delta)
  if failed.is_valid() and failed.call():b.set_process(false);return
  if after_tick.is_valid():after_tick.call(b)
func fixture_failed()->bool:return failures>0
func closed_fixture(b,path:String,time:Array,advance:bool=true)->bool:
 b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
 if not real_battle(b,path,time):return false
 for index in range(100):
  if not b.automation.running:break
  if advance:time[0]+=500
  b.automation.tick_battle(0.5)
  if failures:return false
 check(not b.automation.running and not b.battle_open and b.quest_loot.followup_status(b).get("closed",false),"Real original169 result and original close create actual C1 evidence")
 if failures:return false
 check(b.session._profile.quest_loot.entries[KEY].saved_battles==1 and not b.session._profile.quest_loot.entries[KEY].open_span,"Actual saved result closes first span once")
 return failures==0
func frozen_record(b)->Dictionary:
 return {"profile":b.session.snapshot(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"disk":FileAccess.get_file_as_bytes(b.save_path),"identity":b.quest_auto.identity.checkpoint(),"nav":b.quest_auto.navigation.key,"ready":b.quest_loot.ready_frame.duplicate(true),"timer":b.quest_loot.admission_timer_snapshot(),"auto":b.automation.start_lifetime}
func run()->void:
 # Pure decision only: no synthetic inventory/proof/candidate is installed.
 check(Loot.followup_decision({"status":"done"},{"used_ms":10,"limit_ms":10})=="completed","PURE done wins over limit; this is not an actual2760 drop")
 if failures:quit(1);return
 for mode in ["old_deadline","late_anchor","actual_limit"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if mode=="actual_limit":
   # Still original settlement; move the explicit monotonic fixture clock to
   # the existing budget limit while its already-issued battle is active.
   b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
   if not real_battle(b,"user://loot-continuation-"+mode+".json",time):b.free();quit(1);return
   time[0]+=1800000
   if not drive_original(b,time):b.free();quit(1);return
  elif not closed_fixture(b,"user://loot-continuation-"+mode+".json",time,mode=="late_anchor"):
   b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY].duplicate(true)
  var fields:int=b.field_calls;var commits:int=b.commits
  var deadline:int=b.quest_loot.next_attempt_ms
  var old_lifetime=b.quest_loot.lifetime
  var direct:Dictionary=b.quest_loot.consume_followup(b)
  if failures:b.free();quit(1);return
  check(direct.get("waiting",false) and b.commits==commits and b.field_calls==fields,"Depth0 call cannot consume actual C1 before a normal process barrier")
  if failures:b.free();quit(1);return
  var reached:Array=[false]
  b.quest_auto.after_tick=func(host):
   if failures:host.set_process(false);return
   if mode=="actual_limit":
    if host.quest_auto.running:return
    reached[0]=true;host.set_process(false)
    return
   if not host.quest_loot.ready_frame.has("continuation_gate"):return
   reached[0]=true;host.set_process(false)
   check(host.field_calls==fields,"Consumer itself performs zero field_step calls")
   if failures:return
   var repeated:Dictionary=host.quest_loot.consume_followup(host)
   if failures:return
   check(not repeated.get("ok",true) and host.commits==commits+1,"Same-generation repeated consumer cannot open twice")
   if failures:return
   var reply:Dictionary=host.quest_loot.attempt_once(host)
   if failures:return
   check(reply.get("ok",false) and not reply.get("attempted",true) and host.field_calls==fields,"Same normal generation cannot consume newly reopened span")
  root.add_child(b);b.set_process(true)
  var arrived:bool=await Wait.until(self,func():return failures>0 or reached[0])
  if failures:b.free();quit(1);return
  check(arrived and reached[0],"Actual SceneTree process reaches one bounded continuation decision")
  if failures:b.free();quit(1);return
  var opened:Dictionary=b.session._profile.quest_loot.entries[KEY]
  if mode=="actual_limit":
   check(not opened.open_span and opened.saved_battles==1 and b.commits==commits and b.field_calls==fields and b.quest_auto.phase=="manual","Real late current battle safely saved; limit prevents next open/attempt")
   if failures:b.free();quit(1);return
  else:
   check(opened.budget_id==entry.budget_id and opened.generation==entry.generation and opened.saved_battles==entry.saved_battles and opened.used_ms==entry.used_ms and opened.issued_seq==entry.issued_seq+1 and opened.open_span and b.commits==commits+1,"One original A2 open preserves cumulative budget/generation and result counters")
   if failures:b.free();quit(1);return
   check(not is_same(old_lifetime,b.quest_loot.lifetime) and b.quest_loot.next_attempt_ms==maxi(deadline,time[0]) and b.quest_loot.ready_frame.clock==b.quest_loot.clock and not b.quest_loot.ready_frame.has("continuation") and not b.quest_loot.open_obligation.has("continuation"),"Exact sealed E1 installation preserves maximum deadline and drops temporary call envelope")
   if failures:b.free();quit(1);return
   # Fixed original no-hit RNG fixture for the next attempt, not natural odds.
   b.encounter_rng.seed=4101;b.encounter_catalog.pressure=5
   var checked_early:Array=[false];var rolled:Array=[false]
   time[0]=b.quest_loot.next_attempt_ms-1 if mode=="old_deadline" else time[0]
   b.quest_auto.after_tick=func(host):
    if failures:host.set_process(false);return
    if mode=="old_deadline" and not checked_early[0]:
     check(host.field_calls==fields,"Next normal process before real500ms deadline cannot roll")
     if failures:host.set_process(false);return
     checked_early[0]=true;time[0]+=1
     return
    if host.field_calls==fields:return
    rolled[0]=true;host.set_process(false)
    check(host.field_calls==fields+1 and not host.battle_open,"Next due process performs one fixed-seed original no-hit step")
    if failures:return
    var current_fields:int=host.field_calls
    time[0]+=500
    var duplicate:Dictionary=host.quest_loot.attempt_once(host)
    if failures:return
    check(not duplicate.get("attempted",true) and host.field_calls==current_fields,"Even later clock inside same process cannot roll twice")
   b.set_process(true)
   var attempted:bool=await Wait.until(self,func():return failures>0 or rolled[0])
   if failures:b.free();quit(1);return
   check(attempted and rolled[0],"Real normal process reaches bounded due attempt")
   if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  print("C2 COMPLETE ",mode," fields=",b.field_calls," saved_battles=",opened.saved_battles)
  b.free()
 # Separate non-battle internal boundary: original RNG must remain untouched.
 var overflow_host=CountedBackend.new();var overflow_clock:Array=[State.MAX_MSEC-100]
 if not prepare_attempt(overflow_host,"user://loot-continuation-overflow.json",overflow_clock):overflow_host.free();quit(1);return
 var before_rng:int=overflow_host.encounter_rng.state
 var before_deadline:int=overflow_host.quest_loot.next_attempt_ms
 var refused:Dictionary=overflow_host.quest_loot.attempt_once(overflow_host)
 if failures:overflow_host.free();quit(1);return
 check(not refused.get("ok",true) and overflow_host.field_calls==0 and overflow_host.encounter_rng.state==before_rng and overflow_host.quest_loot.last_attempt_ms==-1 and overflow_host.quest_loot.next_attempt_ms==before_deadline,"Deadline overflow refuses before final roll/last-attempt write")
 if failures:overflow_host.free();quit(1);return
 overflow_host.free()
 print("QUEST AUTO LOOT CONTINUATION: 0 failures; 3 internal original169 fixtures; overflow; pure done priority")
 quit(0)
