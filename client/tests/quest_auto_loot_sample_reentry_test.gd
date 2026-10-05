extends "res://tests/quest_auto_loot_sample_clock_test.gd"
func after_field(b,reply:Dictionary)->Dictionary:
 # Explicit test-local return observer AFTER one actual original field super.
 # Production no-hit has NO corresponding callback; this probes failure fence.
 if failures:return reply
 if not p2_armed or p2_fired:return reply
 p2_fired=true
 check(reply.get("ok",false) and not reply.get("hit",true) and not reply.get("battle",true),"Field override first receives real fixed-seed no-hit")
 if failures:return reply
 mutate_owner(b,"same_save" if p2_mode=="field_same_save" else "identity")
 if failures:return reply
 return {"ok":false,"hit":false,"battle":false,"error":"explicit test return rejection"}
func run()->void:
 for mode in ["observer_save","observer_stop","observer_identity","field_same_save","field_identity"]:
  reset_probe(mode)
  var b=SampleBackend.new();var time:Array=[1000]
  if not await reopen_fixture(b,"user://loot-p2-reentry-"+mode+".json",time):b.free();quit(1);return
  if mode.begins_with("field_"):b.field_observer=after_field
  var fields:int=b.field_calls
  time[0]=b.quest_loot.anchor_ms+1000
  if not await one_normal_tick(b):b.free();quit(1);return
  check(p2_fired and not p2_successor.is_empty() and b.field_calls==fields+1,"Actual original step and designated observer reached once")
  if failures:b.free();quit(1);return
  check_record(b,p2_successor,"No returning old sample/failed field/tick/queue tail changes complete successor")
  if failures:b.free();quit(1);return
  if mode.begins_with("field_"):
   check(p2_profiles.is_empty() and b.quest_auto.running,"Derived field failure cannot old-stop same-identity new save or internal successor identity")
   if failures:b.free();quit(1);return
  else:
   check(p2_queue_seen and p2_profiles.size()>=1,"Actual original queued progress event—not a synchronous publish substitute")
   if failures:b.free();quit(1);return
  print("P2 REENTRY COMPLETE ",mode)
  b.free()
 print("QUEST AUTO LOOT SAMPLE REENTRY: 0 failures; 3 real queued observers; 2 explicit derived field-return observers")
 quit(0)
