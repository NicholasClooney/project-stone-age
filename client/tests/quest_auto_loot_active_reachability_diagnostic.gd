extends "res://tests/quest_auto_loot_continuation_test.gd"
# TMP UNPARSED/UNRUN: observation only; no heartbeat call or production patch.
var tail_seen:=false
var active_seen:=false
var observations:Array=[]
func observe_tail(b)->void:
 b.set_process(false)
 if failures:return
 tail_seen=true
 var state:Dictionary=b.battle.snapshot()
 observations.append({"generation":b._normal_process_generation,"active":state.active,"turn":state.turn,"running":b.automation.running,"compact":b.automation.compact_active,"pending":not b.session._pending.is_empty(),"settled":b.battle_state.get("settled",false)})
 if state.active and b.automation.running and b.battle_open and b.session._pending.has("quest_loot_receipt"):
  active_seen=true
func run()->void:
 var b=CountedBackend.new();var time:Array=[1000]
 b.quest_auto=WatchedRunner.new();b.quest_auto.failed=fixture_failed
 if not real_battle(b,"user://loot-p3-active-reachability.json",time):b.free();quit(1);return
 b.quest_auto.after_tick=observe_tail
 root.add_child(b)
 for index in range(100):
  if not b.automation.running:break
  time[0]+=1000;tail_seen=false;b.set_process(true)
  var arrived:bool=await Wait.until(self,func():return failures>0 or tail_seen)
  if failures:b.free();quit(1);return
  check(arrived and tail_seen,"Actual normal process reaches original runner tail")
  if failures:b.free();quit(1);return
  if active_seen:break
 print("P3 ACTIVE OBSERVATIONS ",JSON.stringify(observations))
 check(active_seen,"UNPROVEN reachability: original compact budget returns with actual battle active")
 if failures:b.free();quit(1);return
 # This diagnostic does not assert heartbeat, result or full P3 acceptance.
 print("P3 ACTIVE REACHABILITY: observed only; no heartbeat/settlement claim")
 b.free();quit(0)
