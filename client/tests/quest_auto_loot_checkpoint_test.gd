extends "res://tests/quest_auto_loot_continuation_test.gd"
## TMP/UNRUN internal driver; signed peer tags are not real WS authentication.
# Location is established BEFORE E1, not patched into a settled ticket.
func setup(b,path:String)->bool:
 if not super.setup(b,path):return false
 check(b.session.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y) and b.save(),"Explicit ordinary-source initial location save before E1")
 return failures==0
func command_for(b,peer:int)->Dictionary:
 return {"map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y,"_quest_connection":peer}
func checkpoint_record(b)->Dictionary:
 var result:Dictionary=frozen_record(b)
 result.runner={"running":b.quest_auto.running,"phase":b.quest_auto.phase,"message":b.quest_auto.message,"pause_reason":b.quest_auto.pause_reason,"connection":b.quest_auto.connection,"client":b.quest_auto.client,"detached":b.quest_auto.detached}
 result.auto_state={"running":b.automation.running,"compact":b.automation.compact_active,"battles":b.automation.battles,"reason":b.automation.stop_reason}
 return result
func run()->void:
 for mode in ["two_after_close","before_close","unrelated_save","different_location","different_profile"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if mode=="before_close":
   b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
   if not real_battle(b,"user://loot-checkpoint-"+mode+".json",time):b.free();quit(1);return
   for index in range(100):
    if not b.battle.snapshot().active:break
    time[0]+=500;b.automation.tick_battle(0.5)
    if failures:b.free();quit(1);return
   check(not b.quest_loot.followup.is_empty() and not b.quest_loot.followup.closed and b.battle_open,"Real captured settlement before original close")
   if failures:b.free();quit(1);return
  elif not closed_fixture(b,"user://loot-checkpoint-"+mode+".json",time):b.free();quit(1);return
  var ticket:Dictionary=b.quest_loot.followup
  var token=ticket.token;var serial:int=ticket.serial
  var original:Dictionary=frozen_record(b)
  if mode in ["two_after_close","before_close"]:
   for peer in [-7001,-7002]:
    var reply:Dictionary=b._cmd_checkpoint(command_for(b,peer))
    if failures:b.free();quit(1);return
    check(reply.get("ok",false) and is_same(b.quest_loot.followup,ticket) and is_same(ticket.token,token) and b.quest_loot.followup_current(b,ticket),"Two independent internal checkpoint call origins preserve exact current ticket")
    if failures:b.free();quit(1);return
   check(b.quest_save_serial==serial+2 and ticket.serial==serial+2 and b.session.snapshot()==original.profile and b.last_saved_payload==original.cache and FileAccess.get_file_as_bytes(b.save_path)==original.disk,"Full same-payload checkpoint preserves native/cache/disk; serial is not OS writes")
   if failures:b.free();quit(1);return
   if mode=="before_close":
    if not drive_original(b,time):b.free();quit(1);return
    check(b.quest_loot.followup_current(b,ticket) and ticket.closed and not b.battle_open,"Original close still separately marks the advanced ticket")
    if failures:b.free();quit(1);return
  else:
   if mode=="unrelated_save":check(b.save(),"Unrelated same-payload save succeeds normally")
   else:
    var command:Dictionary=command_for(b,-7002)
    if mode=="different_location":command.x+=1
    else:b.session._profile.player.gold+=3
    var reply:Dictionary=b._cmd_checkpoint(command)
    if failures:b.free();quit(1);return
    check(reply.get("ok",false),"Original checkpoint behavior retained for non-eligible mutation")
   if failures:b.free();quit(1);return
   check(ticket.serial==serial and not b.quest_loot.followup_current(b,ticket),"Unrelated save/real profile/location changes cannot advance old ticket")
   if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  print("CHECKPOINT FIXTURE COMPLETE ",mode)
  b.free()
 print("QUEST AUTO LOOT CHECKPOINT: 0 failures; 5 internal original169 fixtures")
 quit(0)
