extends "res://tests/quest_auto_loot_sample_clock_test.gd"
var denied_stages:Dictionary={"admission":0,"projection":0,"unknown":0}
func guard_stack_has(trace:Array,path:String,method:String)->bool:
 for frame in trace:
  if str(frame.get("source",""))==path and str(frame.get("function",""))==method:return true
 return false
func visit_probe(weak_host:WeakRef)->String:
 # Only this suite's denied case observes stages; all other callbacks unchanged.
 if not p2_armed or p2_mode!="guard_denied":return super.visit_probe(weak_host)
 var host=weak_host.get_ref()
 var trace:Array=get_stack()
 var stage:String="unknown"
 var running_before:bool=false;var phase_before:String="";var call_before:bool=false
 if is_instance_valid(host) and is_instance_valid(host.quest_auto) and is_instance_valid(host.quest_loot):
  running_before=host.quest_auto.running;phase_before=host.quest_auto.phase
  call_before=host.quest_loot.attempt_call!=null
  var from_admission:bool=guard_stack_has(trace,"res://server/quest_auto_loot.gd","admission_error") and guard_stack_has(trace,"res://server/quest_auto_loot.gd","attempt_locked")
  var from_projection:bool=guard_stack_has(trace,"res://server/quest_auto.gd","source_admission") and guard_stack_has(trace,"res://server/quest_auto.gd","source_entry") and guard_stack_has(trace,"res://server/quest_auto.gd","snapshot") and guard_stack_has(trace,"res://server/quest_auto.gd","stop") and guard_stack_has(trace,"res://server/backend.gd","_derived") and guard_stack_has(trace,"res://server/backend.gd","_publish")
  if from_admission and not from_projection and running_before and phase_before=="loot_admission" and call_before:stage="admission"
  elif from_projection and not from_admission and not running_before and phase_before=="stopped" and not call_before:stage="projection"
 var result:String=super.visit_probe(weak_host)
 if failures:return result
 denied_stages[stage]+=1
 print("P2 DENIED GUARD STAGE ",stage," running=",running_before," phase=",phase_before," attempt_call=",call_before," total_visits=",p2_visits)
 return result
func run()->void:
 for mode in ["first_same_save","first_save","last_save","nested","guard_denied"]:
  reset_probe(mode)
  denied_stages={"admission":0,"projection":0,"unknown":0}
  var b=SampleBackend.new();var time:Array=[1000]
  if not await reopen_fixture(b,"user://loot-p2-guard-"+mode+".json",time):b.free();quit(1);return
  var fields:int=b.field_calls
  time[0]=b.quest_loot.anchor_ms+1000
  if not await one_normal_tick(b):b.free();quit(1);return
  if mode in ["first_same_save","first_save","last_save"]:
   check(p2_fired and b.field_calls==fields and b.quest_auto.running,"Guard invalidation never rolls or old-tail stops successor")
   if failures:b.free();quit(1);return
   check_record(b,p2_successor,"Full successor guard state survives returning attempt/tick")
   if failures:b.free();quit(1);return
   var expected_visits:int=2 if mode=="last_save" else 1
   var expected_parties:int=1 if mode in ["first_same_save","last_save"] else 0
   check(p2_visits==expected_visits and p2_parties==expected_parties and p2_clock_reads==(1 if mode=="last_save" else 0),"Actual guard counts: samepayload FIRST guard may reach second guard, never sample afterward")
   if failures:b.free();quit(1);return
  elif mode=="nested":
   check(p2_fired and p2_visits==2 and p2_parties==2 and b.field_calls==fields+1 and b.quest_auto.running and not b.battle_open,"Nested busy tail rejects; outer call performs at most one original no-hit")
   if failures:b.free();quit(1);return
  else:
   check(not b.quest_auto.running and b.field_calls==fields and p2_visits==2 and denied_stages.admission==1 and denied_stages.projection==1 and denied_stages.unknown==0 and p2_parties==0 and b.quest_loot.close_pending.is_empty() and not b.session._profile.quest_loot.entries[KEY].open_span,"Same-owner denied guard retains original real close policy")
   if failures:b.free();quit(1);return
   if not complete_disk(b):b.free();quit(1);return
  print("P2 GUARD COMPLETE ",mode," visits=",p2_visits," parties=",p2_parties," clock=",p2_clock_reads)
  b.free()
 print("QUEST AUTO LOOT SAMPLE GUARD: 0 failures; 5 internal real-continuation fixtures")
 quit(0)
