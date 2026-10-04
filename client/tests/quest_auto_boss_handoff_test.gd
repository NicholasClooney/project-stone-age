extends "res://tests/original_fixed_guards_test.gd"
## Original source troop, actual route receipts and atomic settlement.
func run()->void:
 for save_failure in [false,true]:
  var b=setup()
  var reply:Dictionary=guard_talk(b,guards[0])
  check(reply.ok,"Real audited route reaches guard")
  check(choose(b,reply,"yes").ok and b.battle_open,"Original guard actually starts")
  b.quest_auto.running=true;b.quest_auto.strict_walk=true;b.quest_auto.quest_id=11
  b.quest_auto.identity.begin();b.quest_auto.identity.select_step("test:original-guard")
  b.quest_auto.wait_boss(b)
  check(b.quest_auto.phase=="waiting_boss" and not b.automation.running,"Actual guard is handed to player")
  if save_failure:b.save_path="user://missing-quest-boss-parent/save.json"
  fight(b)
  if save_failure:
   check(not b.quest_auto.running and b.quest_auto.phase=="manual","Atomic save failure stops handoff immediately")
   b.save_path=""
   check(b.handle({"type":"battle_close"}).ok,"Player may retry actual settlement")
   b.quest_auto.tick(b,1.0)
   check(not b.quest_auto.running,"Late successful settlement cannot revive stopped run")
  else:
   check(b.handle({"type":"battle_close"}).ok,"Close saved actual guard victory")
   b.quest_auto.tick(b,1.0)
   check(b.quest_auto.snapshot(b).can_continue and b.quest_auto.phase=="waiting_boss","Real victory waits for explicit continue")
   var s:Dictionary=b.quest_auto.snapshot(b)
   check(b.handle({"type":"quest_auto_continue","quest_run_id":s.run_id,"quest_step_id":s.step_id,"quest_revision":s.revision,"client":"player"}).ok,"Explicit continuation accepted for original saved battle")
  b.free()
 print("QUEST AUTO BOSS HANDOFF: %d failures"%failures)
 quit(1 if failures else 0)
