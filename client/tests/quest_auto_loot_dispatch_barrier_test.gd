extends SceneTree
## Stack-completion unit fixtures, NOT forged C1 authorization or loot attempts.
const Backend=preload("res://server/backend.gd")
const Wait=preload("res://tests/support/wait.gd")
class ProbeRunner extends "res://server/quest_auto.gd":
 var probe:Callable
 func tick(b,delta:float)->void:
  if probe.is_valid():probe.call(b)
var failures:=0
var observed_backend:Node
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 print(("PASS " if value else "FAIL ")+label)
 if not value:
  failures+=1
  if is_instance_valid(observed_backend):
   print("BARRIER FAILURE COUNTERS ",{"depth":observed_backend._depth,"boundary":observed_backend._dispatch_boundary_depth,"observer":observed_backend._observer_depth,"flush":observed_backend._flush_depth,"process":observed_backend._process_depth,"epoch":observed_backend._dispatch_epoch,"generation":observed_backend._normal_process_generation,"queue_size":observed_backend._queue.size()})
func host():
 var b=Backend.new();observed_backend=b;b.set_process(false);b.quest_auto=ProbeRunner.new();root.add_child(b)
 return b
func balanced(b)->bool:
 return b._depth==0 and b._dispatch_boundary_depth==0 and b._observer_depth==0 and b._flush_depth==0 and b._process_depth==0
func run()->void:
 var b=host();var trace:Array=[];var entered:Array=[false]
 var checkpoint:Dictionary=b.continuation_dispatch_checkpoint()
 # Explicit stack-only checkpoint; no followup ticket/profile/battle is created.
 b.quest_auto.probe=func(h):
  if failures:return
  if h._observer_depth>0:
   check(not h.continuation_dispatch_ready(checkpoint),"Observer nested process cannot authorize a checkpoint")
 b.event.connect(func(message):
  if failures:return
  var kind:String=str(message.get("type",""));trace.append("first:"+kind)
  check(not b.continuation_dispatch_ready(checkpoint),"Inside observer stack remains ineligible even with empty queue")
  if failures:return
  if kind=="outer" and not entered[0]:
   entered[0]=true
   var generation:int=b._normal_process_generation
   b._process(0.0)
   if failures:return
   check(b._normal_process_generation==generation,"Observer nested process never increments normal generation")
   if failures:return
   check(not b.handle({"type":"unknown-barrier-command"}).get("ok",true),"Nested actual handle preserves rejection")
   if failures:return
   b._emit({"type":"inner"})
 )
 b.event.connect(func(message):
  if failures:return
  trace.append("second:"+str(message.get("type",""))))
 # Normalize the NPC publication cache before the trace/checkpoint under test.
 b.publish()
 if failures:b.free();quit(1);return
 trace.clear();checkpoint=b.continuation_dispatch_checkpoint()
 b._emit({"type":"outer"})
 if failures:b.free();quit(1);return
 check(trace==["first:outer","first:inner","second:inner","second:outer"],"Direct nested event ordering remains recursive and unchanged")
 if failures:b.free();quit(1);return
 check(balanced(b) and b._dispatch_epoch>int(checkpoint.epoch),"Outermost direct emit completion balances counters and advances epoch")
 if failures:b.free();quit(1);return
 var ready:Array=[false]
 b.quest_auto.probe=func(h):
  if failures:return
  if h.continuation_dispatch_ready(checkpoint):ready[0]=true;h.set_process(false)
 b.set_process(true)
 var ready_wait:bool=await Wait.until(self,func():return ready[0] or failures>0)
 if failures:b.free();quit(1);return
 check(ready_wait,"Only actual SceneTree normal process observes completed earlier dispatch")
 if failures:b.free();quit(1);return
 b.free()
 # Original queued handle and source-context restore, including a nested flush.
 b=host();var scope:Dictionary={"barrier_test_marker":true};b._quest_source_call=scope;b.quest_auto.internal=true
 var restored:Array=[false];var fired:Array=[false]
 b.event.connect(func(message):
  if failures:return
  check(b._quest_source_call.is_empty(),"Actual observer has isolated source context")
  if failures:return
  if not fired[0]:
   fired[0]=true
   b.handle({"type":"ping"})
   if failures:return
   check(b._dispatch_epoch==0,"Inner handle flush cannot complete outer source-isolation stack")
   if failures:return
 )
 b.handle({"type":"set_options","clone_squad":false})
 if failures:b.free();quit(1);return
 restored[0]=is_same(b._quest_source_call,scope) and b.quest_auto.internal
 check(fired[0] and restored[0] and balanced(b),"Handle restores exact source context before outer completion")
 if failures:b.free();quit(1);return
 b._quest_source_call={};b.free()
 # Same real process generation: two checks after queueing both refuse.
 b=host();var same_done:Array=[false];var later:Array=[false];var current:Array=[]
 b.quest_auto.probe=func(h):
  if failures:return
  if not same_done[0]:
   current.append(h.continuation_dispatch_checkpoint())
   h._emit({"type":"same_generation"})
   if failures:return
   check(not h.continuation_dispatch_ready(current[0]) and not h.continuation_dispatch_ready(current[0]),"Two same-generation checks do not substitute for actual dispatch")
   if failures:return
   same_done[0]=true
  elif h.continuation_dispatch_ready(current[0]):later[0]=true;h.set_process(false)
 b.set_process(true)
 var later_wait:bool=await Wait.until(self,func():return later[0] or failures>0)
 if failures:b.free();quit(1);return
 check(later_wait,"Subsequent real process reaches actual completed barrier")
 if failures:b.free();quit(1);return
 check(later[0] and balanced(b),"Same-generation case completes and balances")
 if failures:b.free();quit(1);return
 b.free()
 # Actual process tail resume_clock reentry.
 b=host();b.save_path="user://loot-dispatch-barrier-resume.json";b.keep_resume_current=true
 var tail:Array=[false];var nested:Array=[false]
 b.quest_auto.probe=func(h):
  if failures:return
  if nested[0]:check(not h.continuation_dispatch_ready(checkpoint),"Resume-tail nested process remains ineligible")
 b.resume_clock=func():
  if failures:return 1000
  if not tail[0]:
   tail[0]=true;nested[0]=true
   var generation:int=b._normal_process_generation
   b.keep_resume_current=false;b._process(0.0)
   if failures:return 1000
   check(b._normal_process_generation==generation,"Wrapped process tail reentry cannot become normal generation")
   if failures:return 1000
   nested[0]=false;b.set_process(false)
  return 1000
 b.set_process(true)
 var tail_wait:bool=await Wait.until(self,func():return tail[0] or failures>0)
 if failures:b.free();quit(1);return
 check(tail_wait,"Actual process tail calls original resume clock")
 if failures:b.free();quit(1);return
 check(balanced(b),"Resume empty-state early return balances outer process")
 if failures:b.free();quit(1);return
 b.free()
 # Real depth-zero public resume wrapper. No loot candidate is forged.
 b=host();b.save_path="user://loot-dispatch-direct-resume.json"
 checkpoint=b.continuation_dispatch_checkpoint();b._emit({"type":"prior_completed"})
 var direct_called:Array=[false]
 b.quest_auto.probe=func(h):
  if failures:return
  check(not h.continuation_dispatch_ready(checkpoint),"Direct resume callback nested process cannot consume earlier completed barrier")
  if failures:return
 b.resume_clock=func():
  if failures:return 1000
  direct_called[0]=true
  var generation:int=b._normal_process_generation
  b._process(0.0)
  if failures:return 1000
  check(b._normal_process_generation==generation,"Direct public resume wrapper excludes nested normal generation")
  if failures:return 1000
  return 1000
 b.keep_resume_file()
 if failures:b.free();quit(1);return
 check(direct_called[0] and balanced(b),"Direct resume no-state return balances complete wrapper")
 if failures:b.free();quit(1);return
 b.free()
 b=host();var empty_called:Array=[false]
 b.resume_clock=func():
  if failures:return 1000
  empty_called[0]=true;return 1000
 b.keep_resume_file()
 if failures:b.free();quit(1);return
 check(not empty_called[0] and balanced(b),"Empty-path original early return balances without clock callback")
 if failures:b.free();quit(1);return
 b.free()
 # Existing original resume intent fixture; exercise original primary save and
 # same-key throttle. It is not a started hunt, battle or loot authorization.
 for blocked in [false,true]:
  b=host();b.save_path="user://loot-dispatch-resume-save-"+str(blocked)+".json"
  check(b.save(),"Original complete baseline save before resume fixture")
  if failures:b.free();quit(1);return
  var disk:String=FileAccess.get_file_as_string(b.save_path);var cache:String=b.last_saved_payload
  b.automation.position_map=100;b.automation.position_cell=Vector2i(635,341)
  b.quest_auto.identity.begin();b.quest_auto.running=true
  b.resume_clock=func():
   if failures:return 2000
   return 2000
  if blocked:
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own primary tmp write blocker")
   if failures:b.free();quit(1);return
  b.keep_resume_file()
  if failures:b.free();quit(1);return
  check(balanced(b),"Original resume save return balances boundary")
  if failures:b.free();quit(1);return
  if blocked:
   check(b._resume_written_msec==-1 and b.last_saved_payload==cache and FileAccess.get_file_as_string(b.save_path)==disk and not FileAccess.file_exists(b._resume_file()),"Original save-failed early return preserves old disk/cache and no side-file")
   if failures:b.free();quit(1);return
   # Preserve blocker even on success: evidence is owned by this isolated suite.
  else:
   check(FileAccess.file_exists(b._resume_file()),"Original normal return really writes resume side-file")
   if failures:b.free();quit(1);return
   var side:String=FileAccess.get_file_as_string(b._resume_file())
   b.keep_resume_file()
   if failures:b.free();quit(1);return
   check(balanced(b) and FileAccess.get_file_as_string(b._resume_file())==side,"Original same-key throttle early return balances and preserves bytes")
   if failures:b.free();quit(1);return
  b.free()
 # Explicit _depth fixture only tests the original flush early-return balance.
 b=host();b._depth=1;b._emit({"type":"queued_early"});b._flush()
 check(b._flush_depth==0 and b._dispatch_boundary_depth==0 and b._queue.size()==1 and b._dispatch_epoch==0,"Depth-positive flush early return does not enter counters or claim completion")
 if failures:b.free();quit(1);return
 b._depth=0
 # Actual party-status boundary performs its original flush; no fake battle result.
 b.party_status()
 check(balanced(b) and b._queue.is_empty(),"Original party status boundary balances and drains queued notifications")
 if failures:b.free();quit(1);return
 b.free()
 print("QUEST AUTO LOOT DISPATCH BARRIER: 0 failures; stack evidence only")
 quit(0)
