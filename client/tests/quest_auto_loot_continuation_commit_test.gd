extends "res://tests/quest_auto_loot_continuation_test.gd"
## Real same-budget open observer failures/reentry. No target-drop/public evidence.
func run()->void:
 for mode in ["cancel_after_open","save_after_open","identity_after_open","clock_identity","open_write_failure"]:
  var b=CountedBackend.new();var time:Array=[1000]
  var fired:Array=[false];var done:Array=[false];var successor:Array=[]
  var clock_armed:Array=[false]
  if mode=="clock_identity":
   b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
   if not real_battle(b,"user://loot-continuation-commit-"+mode+".json",time):b.free();quit(1);return
   var weak_host:WeakRef=weakref(b)
   # Installed before C1 captures the clock; no post-ticket clock substitution.
   # Full snapshots are captured outside this Callable. It captures only a
   # weak host and primitive arrays, never an array containing its own clock.
   b.quest_loot.clock=func():
    var host=weak_host.get_ref()
    if host!=null and clock_armed[0] and not fired[0]:
     fired[0]=true
     host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
     host.quest_auto.navigation.key="clock-successor"
    return time[0]
   if not drive_original(b,time):b.free();quit(1);return
  elif not closed_fixture(b,"user://loot-continuation-commit-"+mode+".json",time):b.free();quit(1);return
  var fields:int=b.field_calls;var commits:int=b.commits
  var original:Dictionary=frozen_record(b)
  if mode=="open_write_failure":
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own next-open tmp writer blocker")
   if failures:b.free();quit(1);return
  elif mode!="clock_identity":
   b.observer=func(host):
    if fired[0]:return
    fired[0]=true
    check(host.session._profile.quest_loot.entries[KEY].open_span and host.quest_loot.consume_call!=null,"Real candidate installed/cache confirmed before open observer")
    if failures:return
    if mode=="cancel_after_open":host.quest_auto.stop(host,"Actual next-open observer cancellation")
    elif mode=="save_after_open":
     host.session._profile.player.gold+=11
     var saved:bool=host.save()
     if failures:return
     check(saved,"Observer's later whole-profile save really wins")
     if failures:return
    else:
     host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
     host.quest_auto.navigation.key="commit-successor"
    if failures:return
    successor.append(frozen_record(host))
  var before_clock:Dictionary=b.quest_loot.admission_timer_snapshot()
  clock_armed[0]=true
  b.quest_auto.after_tick=func(host):
   if failures:host.set_process(false);return
   done[0]=true;host.set_process(false)
  root.add_child(b);b.set_process(true)
  var arrived:bool=await Wait.until(self,func():return failures>0 or done[0])
  if failures:b.free();quit(1);return
  check(arrived and done[0],"Normal process returned from actual one-open writer")
  if failures:b.free();quit(1);return
  check(b.field_calls==fields and b.quest_loot.consume_call==null,"Old consumer performs no roll and retires only its local lock")
  if failures:b.free();quit(1);return
  if mode=="open_write_failure":
   check(b.commits==commits and b.session.snapshot()==original.profile and b.last_saved_payload==original.cache and b.quest_save_serial==original.serial and FileAccess.get_file_as_bytes(b.save_path)==original.disk and DirAccess.dir_exists_absolute(b.save_path+".tmp"),"Actual failed open retains complete old saved result and own blocker for evidence")
   if failures:b.free();quit(1);return
  elif mode=="clock_identity":
   check(fired[0] and b.commits==commits+1 and b.session._profile.quest_loot.entries[KEY].open_span and b.quest_auto.navigation.key=="clock-successor","Real E1 post-open clock changes identity; saved open remains real")
   if failures:b.free();quit(1);return
   check(b.quest_loot.last_ms==before_clock.last_ms and b.quest_loot.next_attempt_ms==before_clock.next_attempt_ms and b.quest_loot.ready_frame==before_clock.ready_frame and b.quest_loot.anchor_ms==before_clock.anchor_ms and not b.quest_loot.ready_frame.has("continuation_gate"),"Clock-invalidated old continuation cannot install last_ms/anchor/ready/deadline")
   if failures:b.free();quit(1);return
   if not complete_disk(b):b.free();quit(1);return
  else:
   check(fired[0] and successor.size()==1 and frozen_record(b)==successor[0],"Old return cannot alter successor ready/lifetime/profile/cache/bytes/identity/nav")
   if failures:b.free();quit(1);return
   if mode=="cancel_after_open":
    check(not b.quest_auto.running and not b.session._profile.quest_loot.entries[KEY].open_span and b.quest_loot.close_pending.is_empty(),"Actual persisted open cancellation closes its obligation without resurrecting runner")
    if failures:b.free();quit(1);return
   else:
    check(b.session._profile.quest_loot.entries[KEY].open_span and not b.quest_loot.ready_frame.has("continuation_gate"),"Already-saved open remains a fact; stale caller does not install successor readiness")
    if failures:b.free();quit(1);return
   if not complete_disk(b):b.free();quit(1);return
  print("C2 COMMIT COMPLETE ",mode)
  b.free()
 print("QUEST AUTO LOOT CONTINUATION COMMIT: 0 failures; 5 actual writer/clock fixtures")
 quit(0)
