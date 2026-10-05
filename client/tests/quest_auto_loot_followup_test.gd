extends "res://tests/quest_auto_loot_battle_cancel_test.gd"
## C1 evidence only. No continuation tick, next span, target item or public start.
func run()->void:
 for mode in ["success","save_observer","close_detach","save_failure"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if not real_battle(b,"user://loot-followup-"+mode+".json",time):b.free();quit(1);return
  var original_fields:int=b.field_calls
  var fired:Array=[false];var saved:Array=[]
  if mode=="save_observer":
   b.observer=func(host):
    if fired[0]:return
    fired[0]=true
    host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
    host.quest_auto.phase="successor";host.quest_auto.navigation.key="successor-nav"
    host.session._profile.player.gold+=9
    check(host.save(),"Actual post-candidate observer saves successor whole profile")
    if failures:return
    saved.append(host.last_saved_payload)
  if mode=="close_detach":
   b.event.connect(func(event):
    if fired[0] or event.get("type")!="battle_closed":return
    fired[0]=true
    check(b.quest_loot.followup_status(b).get("closed",false),"Original close marked before its first battle_closed observer")
    if failures:return
    b.quest_auto.detach(b,71)
   )
  if mode=="save_failure":
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own writer blocker before actual result")
   if failures:b.free();quit(1);return
  if mode in ["save_observer","close_detach"]:
   for tick in range(100):
    if fired[0] or failures:break
    time[0]+=500;b.automation.tick_battle(0.5)
   check(fired[0],"Actual configured original save/close callback reached")
   if failures:b.free();quit(1);return
  elif not drive_original(b,time):b.free();quit(1);return
  if mode=="success":
   var state:Dictionary=b.quest_loot.followup_status(b)
   check(state.get("closed",false) and state.get("auto_stopped",false),"Real immutable result and one original close retain evidence after auto stops")
   if failures:b.free();quit(1);return
   check(b.quest_loot.retire_followup_scope(b,state.token) and b.automation.loot_scope.is_empty(),"Only exact stopped scope retires through production method")
   if failures:b.free();quit(1);return
   check(b.session._profile.quest_loot.entries[KEY].saved_battles==1 and not b.session._profile.quest_loot.entries[KEY].open_span and b.field_calls==original_fields,"C1 does not open another span or field attempt")
   if failures:b.free();quit(1);return
  elif mode=="save_observer":
   check(b.quest_loot.followup_status(b).is_empty() and b.quest_auto.phase=="successor" and b.quest_auto.navigation.key=="successor-nav" and saved.size()==1 and b.last_saved_payload==saved[0] and FileAccess.get_file_as_string(b.save_path)==saved[0],"Old candidate cannot queue followup or overwrite actual successor save/run")
   if failures:b.free();quit(1);return
  elif mode=="close_detach":
   check(b.quest_auto.detached and b.quest_loot.followup_status(b).is_empty() and b.field_calls==original_fields,"Real close callback detach revokes continuation evidence without another attempt")
   if failures:b.free();quit(1);return
  else:
   check(b.quest_loot.followup_status(b).is_empty() and b.quest_loot.storage_paused and b.battle_open and b.session._pending.has("quest_loot_receipt"),"Actual failed result creates no continuation capability")
   if failures:b.free();quit(1);return
   var battle_id:String=str(b.session._pending.battle_id)
   check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Remove own blocker only after failed-state checks")
   if failures:b.free();quit(1);return
   check(b.handle({"type":"battle_close","battle_id":battle_id}).get("ok",false) and b.quest_loot.followup_status(b).is_empty() and not b.quest_auto.running,"Original repair commits but does not resume failed/cancelled run")
   if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT FOLLOWUP: 0 failures; 4 internal original-battle fixtures")
 quit(0)
