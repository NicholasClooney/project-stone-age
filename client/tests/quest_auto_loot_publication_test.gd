extends "res://tests/quest_auto_loot_continuation_test.gd"
## Real queued publication, original169; no second battle/target-drop/WS proof.
# Records live outside event callbacks; no captured array can hold its own closure.
var p1_successor:Dictionary={}
var p1_trace:Array=[]
func p1_record(b)->Dictionary:
 var result:Dictionary=frozen_record(b)
 result.runner={"running":b.quest_auto.running,"phase":b.quest_auto.phase,"message":b.quest_auto.message,"pause_reason":b.quest_auto.pause_reason,"connection":b.quest_auto.connection,"client":b.quest_auto.client}
 result.lifetime=b.quest_loot.lifetime
 result.obligation=b.quest_loot.open_obligation.duplicate(true)
 return result
func run()->void:
 await publication_modes(["success","failure","limit"],"QUEST AUTO LOOT PUBLICATION")
func publication_modes(modes:Array,label:String)->void:
 # PURE decision only, not a fabricated successful drop or terminal profile.
 check(Loot.followup_decision({"status":"done"},{"used_ms":10,"limit_ms":10})=="completed","PURE completed precedes limit, not actual2760 drop")
 if failures:quit(1);return
 for mode in modes:
  p1_successor={};p1_trace=[]
  var b=CountedBackend.new();var time:Array=[1000]
  var path:String="user://loot-publication-"+str(mode)+".json"
  if mode=="limit":
   b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
   if not real_battle(b,path,time):b.free();quit(1);return
   time[0]+=1800000
   if not drive_original(b,time):b.free();quit(1);return
  elif not closed_fixture(b,path,time):b.free();quit(1);return
  b.quest_auto.pause_reason="obsolete prior pause"
  var failed_open:bool=str(mode).begins_with("failure")
  var original:Dictionary=p1_record(b)
  var fields:int=b.field_calls;var commits:int=b.commits
  # Explicit helper rejection boundaries: no inferred commit result/capability.
  for refused in [{"ok":false,"reason":"no commit marker"},{"ok":false,"persisted":true,"reason":"historical open"}]:
   var unchanged:Dictionary=b.quest_loot.announce_failed_open(b,{},refused)
   if failures:b.free();quit(1);return
   check(unchanged==refused and p1_record(b)==original,"Absent marker or persisted=true cannot manufacture a failure stop")
   if failures:b.free();quit(1);return
  if failed_open:
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own real next-open tmp blocker")
   if failures:b.free();quit(1);return
  var queued:Array=[false];var observed:Array=[false]
  var weak_host:WeakRef=weakref(b)
  # Production runner returns while _depth==1. No test flush or direct publish.
  b.quest_auto.after_tick=func(host):
   host.set_process(false)
   if failures:return
   check(host._depth==1 and host._flush_depth==0 and host.field_calls==fields,"Normal consumer returns without rolling before original flush")
   if failures:return
   for event in host._queue:
    if event.get("type")=="profile":queued[0]=true
   check(queued[0],"Production publication really queued profile")
   if failures:return
   p1_trace.append("queued:"+str(mode))
  b.event.connect(func(message):
   if failures or observed[0] or message.get("type")!="profile":return
   var host=weak_host.get_ref()
   check(host!=null,"Queued observer still has real host")
   if failures:return
   observed[0]=true
   check(queued[0] and host._flush_depth>0 and host._observer_depth>0 and host._depth==0 and host.quest_loot.consume_call==null,"Actual production flush delivers profile after consumer returned")
   if failures:return
   var wire:Dictionary=message.derived.quest_auto
   if failed_open or mode=="limit":
    check(not wire.running and wire.phase=="manual" and not wire.message.is_empty() and wire.pause_reason==wire.message and wire.pause_reason!="obsolete prior pause","Queued manual profile replaces old pause_reason with actual reason")
    if failures:return
    check(not host.session._profile.quest_loot.entries[KEY].open_span and host.commits==commits,"Failure or limit publishes old closed ledger without an extra save")
    if failures:return
    if failed_open:
     check(host.session.snapshot()==original.profile and host.last_saved_payload==original.cache and host.quest_save_serial==original.serial and FileAccess.get_file_as_bytes(host.save_path)==original.disk,"Before failure observer: complete old native/cache/serial/disk retained")
     if failures:return
     check(host.quest_loot.admission_timer_snapshot()==original.timer and host.quest_loot.close_pending.is_empty() and not host.quest_loot.storage_paused and DirAccess.dir_exists_absolute(host.save_path+".tmp"),"Closed failure makes no new timer/repair obligation and retains blocker")
     if failures:return
   else:
    check(host.quest_loot.ready_frame.has("continuation_gate") and host.quest_loot.admission_owner(host,host.quest_loot.ready_frame) and host.session._profile.quest_loot.entries[KEY].open_span and host.commits==commits+1,"Success observer sees real sealed ready/gate and exactly one next open")
    if failures:return
    check(message.profile.quest_loot==host.session._profile.quest_loot and wire.running and wire.phase==host.quest_auto.phase,"Success queued profile describes sealed current ledger/runner")
    if failures:return
   p1_trace.append("observer:"+str(mode))
   print("P1 OBSERVER REACHED ",mode," flush=",host._flush_depth)
   if str(mode).ends_with("_save"):
    host.session._profile.player.gold+=17
    var saved:bool=host.save()
    if failures:return
    check(saved,"Real queued observer successor whole-profile save")
    if failures:return
   elif str(mode).ends_with("_stop"):
    host.quest_auto.stop(host,"Queued P1 observer stop")
    if failures:return
   elif str(mode).ends_with("_identity"):
    # Internal identity replacement only; explicitly not public start/authentication.
    host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
    host.quest_auto.navigation.key="p1-successor"
   if failures:return
   p1_successor=p1_record(host)
  )
  root.add_child(b);b.set_process(true)
  var arrived:bool=await Wait.until(self,func():return failures>0 or observed[0])
  if failures:b.free();quit(1);return
  check(arrived and observed[0] and p1_trace==["queued:"+str(mode),"observer:"+str(mode)],"Real queued and observer stages both reached in order")
  if failures:b.free();quit(1);return
  check(b.field_calls==fields and b.quest_loot.consume_call==null and p1_record(b)==p1_successor,"Consumer/flush return leaves full successor profile/cache/bytes/timer/ready/nav/identity unchanged")
  if failures:b.free();quit(1);return
  if failed_open:
   check(DirAccess.dir_exists_absolute(b.save_path+".tmp") and not b.session._profile.quest_loot.entries[KEY].open_span and b.quest_loot.close_pending.is_empty(),"Failure blocker persists and no new span/repair is invented")
   if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  print("P1 FIXTURE COMPLETE ",mode)
  b.free()
 print(label+": 0 failures; "+str(modes.size())+" real queued publication fixtures; pure completed decision only")
 quit(0)
