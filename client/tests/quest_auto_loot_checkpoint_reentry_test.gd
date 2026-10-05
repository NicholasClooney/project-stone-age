extends "res://tests/quest_auto_loot_checkpoint_test.gd"
## TMP/UNRUN precise private writer return injection, no publication suppression.
class ReentrantBackend:
 extends CountedBackend
 var after_checkpoint_save:Callable
 var armed:=false
 var omit_mark:=false
 var simulated_returns:=0
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  if armed and omit_mark and not checkpoint.is_empty():
   # TEST DOUBLE ONLY: one eligible checkpoint, after real setup/battle/close.
   # Never execute the actual branch or mark; imitate +1/true to test provenance.
   armed=false;simulated_returns+=1;quest_save_serial+=1
   return true
  var result:bool=super._save_profile_boundary(checkpoint)
  if armed and not checkpoint.is_empty():
   armed=false
   if after_checkpoint_save.is_valid():after_checkpoint_save.call(self)
  return result
var successor:Dictionary={}
func run()->void:
 for mode in ["same_save","new_save","identity","stop","no_mark"]:
  var b=ReentrantBackend.new();var time:Array=[1000]
  if not closed_fixture(b,"user://loot-checkpoint-reentry-"+mode+".json",time):b.free();quit(1);return
  var ticket:Dictionary=b.quest_loot.followup;var serial:int=ticket.serial
  var ticket_before:Dictionary=ticket.duplicate(true)
  var expected:Dictionary=checkpoint_record(b)
  if mode=="no_mark":expected.serial+=1
  var fired:Array=[false]
  # Callback takes its owner parameter, captures no strong Backend or own record.
  b.after_checkpoint_save=func(host):
   if failures:return
   fired[0]=true
   check(not host.quest_loot.followup.is_empty() and ticket.serial==serial,"Original branch marked local capability, not yet advanced ticket")
   if failures:return
   if mode in ["same_save","new_save"]:
    if mode=="new_save":host.session._profile.player.gold+=7
    var saved:bool=host.save()
    if failures:return
    check(saved,"Nested actual successor save")
    if failures:return
   elif mode=="identity":
    host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
    host.quest_auto.navigation.key="checkpoint-successor"
   else:
    host.quest_auto.stop(host,"Checkpoint observer stop")
    if failures:return
   successor=checkpoint_record(host)
  b.omit_mark=mode=="no_mark"
  b.armed=true
  var reply:Dictionary=b._cmd_checkpoint(command_for(b,-7002))
  if failures:b.free();quit(1);return
  if mode=="no_mark":
   check(reply.get("ok",false) and b.simulated_returns==1 and not fired[0] and not b.armed,"TEST DOUBLE only armed eligible checkpoint fakes true/+1 without real mark")
   if failures:b.free();quit(1);return
   check(checkpoint_record(b)==expected and is_same(b.quest_loot.followup,ticket) and ticket==ticket_before,"No-mark call changes only simulated serial; entire original ticket/native/cache/disk/timer/runner retained")
  else:
   check(reply.get("ok",false) and fired[0] and b.simulated_returns==0 and checkpoint_record(b)==successor,"Old checkpoint ACK/publication retains full successor without old tail writes")
  if failures:b.free();quit(1);return
  check(ticket.serial==serial and not b.quest_loot.followup_current(b,ticket),"Nested save/identity/stop prevents old local capability from advancing ticket")
  if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  print("CHECKPOINT REENTRY COMPLETE ",mode)
  b.free()
 print("QUEST AUTO LOOT CHECKPOINT REENTRY: 0 failures; 4 internal return-observer fixtures; 1 explicit no-mark double")
 quit(0)
