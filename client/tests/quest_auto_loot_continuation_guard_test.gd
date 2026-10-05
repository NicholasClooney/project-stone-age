extends "res://tests/quest_auto_loot_continuation_test.gd"
## Actual E1 host Callable reentry after original169 C1 evidence, internal only.
func run()->void:
 for mode in ["nested","cancel","new_save","new_identity"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if not closed_fixture(b,"user://loot-continuation-guard-"+mode+".json",time):b.free();quit(1);return
  var fired:Array=[false];var done:Array=[false];var successor:Array=[]
  var fields:int=b.field_calls;var commits:int=b.commits
  var original:Dictionary=frozen_record(b)
  b.quest_visit_guard=func():
   if fired[0]:return ""
   fired[0]=true
   check(b.quest_loot.consume_call!=null and b.quest_loot.attempt_frame.is_empty(),"Consumer locks before real E1 host guard, grants no roll capability")
   if failures:return "Test guard failed"
   if mode=="nested":
    var inner:Dictionary=b.quest_loot.consume_followup(b)
    if failures:return "Nested consumer failed"
    check(not inner.get("ok",true) and b.field_calls==fields and b.commits==commits,"Nested actual consumer refuses before write/roll")
    if failures:return "Nested guard failed"
    var attempted:Dictionary=b.quest_loot.attempt_once(b)
    if failures:return "Nested attempt failed"
    check(not attempted.get("ok",true) and b.field_calls==fields,"Checking-stage guard cannot borrow old ready state for an attempt")
    if failures:return "Nested attempt guard failed"
   elif mode=="cancel":b.quest_auto.stop(b,"C2 actual guard cancellation")
   elif mode=="new_save":
    b.session._profile.player.gold+=7
    var saved:bool=b.save()
    if failures:return "Successor save callback failed"
    check(saved,"Guard performs real unrelated full-profile save")
    if failures:return "Successor save failed"
   else:
    # Internal identity API, explicitly NOT public start authentication.
    b.quest_auto.identity.begin();b.quest_auto.identity.select_step(KEY)
    b.quest_auto.navigation.key="guard-successor"
   if failures:return "Guard operation failed"
   if mode!="nested":successor.append(frozen_record(b))
   return ""
  b.quest_auto.after_tick=func(host):
   if failures:host.set_process(false);return
   if fired[0]:done[0]=true;host.set_process(false)
  root.add_child(b);b.set_process(true)
  var arrived:bool=await Wait.until(self,func():return failures>0 or done[0])
  if failures:b.free();quit(1);return
  check(arrived and fired[0] and done[0],"Real normal process reached actual guard and unwound")
  if failures:b.free();quit(1);return
  check(b.quest_loot.consume_call==null and b.field_calls==fields,"Only original call retired; no C2 field attempt")
  if failures:b.free();quit(1);return
  if mode=="nested":
   check(b.commits==commits+1 and b.session._profile.quest_loot.entries[KEY].open_span and b.quest_loot.ready_frame.has("continuation_gate"),"Outer invocation alone commits one same-budget open")
   if failures:b.free();quit(1);return
   if not complete_disk(b):b.free();quit(1);return
  else:
   check(successor.size()==1 and frozen_record(b)==successor[0],"Old return preserves full successor native/cache/serial/bytes/timer/ready/nav")
   if failures:b.free();quit(1);return
   check(b.commits==commits and not b.session._profile.quest_loot.entries[KEY].open_span,"Old E1 invocation writes no open after guard invalidation")
   if failures:b.free();quit(1);return
   if mode=="cancel":
    check(not b.quest_auto.running and b.session._profile.quest_loot==original.profile.quest_loot,"Cancelled closed budget remains unchanged; any original stop/resume position save is retained in the full successor record")
    if failures:b.free();quit(1);return
  print("C2 GUARD COMPLETE ",mode)
  b.free()
 print("QUEST AUTO LOOT CONTINUATION GUARD: 0 failures; 4 real guard fixtures")
 quit(0)
