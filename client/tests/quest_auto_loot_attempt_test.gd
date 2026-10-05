extends "res://tests/quest_auto_loot_admission_test.gd"
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
class CountedBackend:
 extends ObservedBackend
 var field_calls:=0
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_calls+=1
  return super._cmd_field_step(command)
func prepare_attempt(b,path:String,clock_ms:Array)->bool:
 if not setup(b,path):return false
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 if not b.save():return false
 b.quest_loot.clock=func():return clock_ms[0]
 var admitted:Dictionary=b.quest_loot.admit_prepared_run(b)
 check(admitted.get("ok",false),"E2 requires actual E1 durable acquire/open")
 return failures==0
func run()->void:
 for mode in ["no_hit","ordinary","cancel_on_battle","cancel_guard","random_disabled","limit","nested_guard"]:
  var b=CountedBackend.new();var time:Array=[1000]
  var guard_armed:Array=[false]
  if mode=="cancel_guard":
   b.quest_visit_guard=func():
    if guard_armed[0]:b.quest_auto.stop(b,"Attempt guard cancellation")
    return ""
  var nested:Array=[]
  if mode=="nested_guard":
   b.quest_visit_guard=func():
    if guard_armed[0] and nested.is_empty():
     # Mark entry before invoking the actual production method, so even an
     # implementation regression cannot make this test recurse indefinitely.
     nested.append({})
     var before_rng:int=b.encounter_rng.state
     var before_pressure:int=b.encounter_catalog.pressure
     check(b.quest_loot.attempt_call!=null and b.quest_loot.attempt_frame.is_empty(),"CHECKING lock grants no original-roll qualification")
     if failures:return "Nested guard assertion failed before reentry"
     nested[0]=b.quest_loot.attempt_once(b)
     check(not nested[0].get("ok",true) and not nested[0].get("attempted",true) and b.field_calls==0 and b.encounter_rng.state==before_rng and b.encounter_catalog.pressure==before_pressure,"Nested real guard call rejects before any original step")
     if failures:return "Nested guard assertion failed after reentry"
    return ""
  if not prepare_attempt(b,"user://loot-attempt-"+mode+".json",time):check(false,"E2 fixture setup");b.free();quit(1);return
  # Explicit deterministic RNG fixture, NOT a natural-probability pilot.
  # Never choose a group, edit weights/drop, search seeds, or replace pending.
  b.encounter_rng.seed=4101
  b.encounter_catalog.pressure=5 if mode=="no_hit" else 50
  var initial_rng:int=b.encounter_rng.state
  var initial_pressure:int=b.encounter_catalog.pressure
  var cancelled:Array=[false]
  if mode=="cancel_on_battle":
   b.event.connect(func(event):
    if event.get("type")=="battle_started" and not cancelled[0]:
     cancelled[0]=true;b.quest_auto.stop(b,"Actual battle publication cancels attempt owner")
   )
  guard_armed[0]=true
  if mode=="random_disabled":b.session._profile.no_random_encounters=true
  if mode=="limit":time[0]+=1800000
  var reply:Dictionary=b.quest_loot.attempt_once(b)
  check(reply.has("ok"),"Attempt returns a bounded result")
  if failures:b.free();quit(1);return
  if mode=="nested_guard":
   check(nested.size()==1 and reply.get("attempted",false) and b.field_calls==1 and b.quest_loot.attempt_call==null and b.quest_loot.attempt_frame.is_empty(),"Outer guard invocation executes exactly one original field_step and retires only itself")
   if failures:b.free();quit(1);return
   b.free();continue
  if mode in ["cancel_guard","random_disabled","limit"]:
   check(not reply.ok and b.encounter_rng.state==initial_rng and b.encounter_catalog.pressure==initial_pressure and not b.battle_open,"Rejected attempt consumes no original RNG or pressure")
   if failures:b.free();quit(1);return
   b.free();continue
  if mode=="no_hit":
   check(reply.get("attempted",false) and not reply.get("hit",false) and not reply.get("battle",false),"Fixed-seed first original step is a no-encounter fixture")
   if failures:b.free();quit(1);return
   var rng_after:int=b.encounter_rng.state;var pressure_after:int=b.encounter_catalog.pressure
   reply=b.quest_loot.attempt_once(b)
   check(reply.ok and not reply.get("attempted",true) and b.encounter_rng.state==rng_after and b.encounter_catalog.pressure==pressure_after,"Same time cannot issue a second logical step")
   if failures:b.free();quit(1);return
   b.free();continue
  # Bounded driver advances only explicit 500ms calls; no group selection.
  for attempt in range(199):
   if reply.get("battle",false) or not reply.ok:break
   time[0]+=500
   reply=b.quest_loot.attempt_once(b)
  check(reply.get("battle",false) and b.battle_open and b.session._pending.has("quest_loot_receipt"),"Original complete pool produced actual pending and ledger receipt")
  if failures:b.free();quit(1);return
  var group:int=int(b.session._pending.group_id)
  print("E2 FIXTURE "+mode+" seed4101 group="+str(group))
  if mode=="cancel_on_battle":
   check(cancelled[0] and not reply.ok and not b.automation.running and not b.quest_auto.running,"Published battle remains, cancelled owner never starts automation")
   if failures:b.free();quit(1);return
   b.free();continue
  check(group!=711 and b.automation.single_battle and b.automation.settings.preset=="attack" and b.automation.settings.compact and b.automation.compact_active,"Disclosed fixed seed exercises original non-target ordinary attack+compact")
  if failures:b.free();quit(1);return
  for tick in range(100):
   if not b.automation.running:break
   b.automation.tick_battle(0.5)
  check(not b.automation.running and not b.battle_open and b.session._pending.is_empty() and b.battle_state.get("settled",false),"Actual original single battle finishes and saves")
  if failures:b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  check(entry.saved_battles==1 and entry.new_items==0 and not entry.open_span,"Non-target battle still counted once by original atomic ledger")
  if failures:b.free();quit(1);return
  var copied:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
  check(copied.get("ok",false),"Full disk profile validates")
  if failures:b.free();quit(1);return
  check(copied.profile==b.session.snapshot(),"Complete original battle profile and ledger actually stored")
  if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT ATTEMPT: %d failures; fixed seed internal driver, target drops untested"%failures)
 quit(1 if failures else 0)
