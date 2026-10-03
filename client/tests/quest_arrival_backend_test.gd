extends "res://tests/quest_legitimate_arrival_test.gd"
const Equipment=preload("res://server/original_equipment.gd")
const SAGE_ID="seimu/event/event01_2@41:34:25"
const GUARD_ID="400/sb_muge1.arg@41:34:41"
func enter_route(b)->void:
 b.automation.position_changed(400,Vector2i(97,119))
 check(b.handle({"type":"check_passage","from_map":400,"to_map":41}).ok,"actual original time check accepts public entrance")
 check(b.handle({"type":"report_position","map_id":41,"cell":[11,8]}).ok,"actual original time arrival accepted")
 check(b.quest_arrival.has_arrival(b,41,Vector2i(11,8)),"production move hook grants root route")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":GUARD_ID,"mode":mode}).ok and b.quest_arrival.has_arrival(b,41,Vector2i(11,8)),"distant helper refusal preserves real route")
 for point in maze_path(b):
  var r:Dictionary=b.handle({"type":"report_position","map_id":41,"cell":[point.x,point.y]})
  if not r.ok or not b.quest_arrival.has_arrival(b,41,point):check(false,"production route broke at %s: %s"%[point,str(r)]);return
 check(b.automation.position_cell==Vector2i(34,42),"all actual maze steps reach guard without project movement")
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":GUARD_ID,"mode":mode}).ok and b.automation.position_cell==Vector2i(34,42) and b.quest_arrival.has_arrival(b,41,Vector2i(34,42)),"nearby helper keeps stationary legal location")
func start_guard(b)->void:
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":GUARD_ID})
 check(r.ok and choose(b,r,"yes").ok and b.battle_open,"real guarded begin creates server-owned context")
func run()->void:
 var old:Callable=WorldClock.clock;WorldClock.clock=func():return WorldClock.ERA+100
 var b=fresh();Equipment.add(b.session._profile,2603)
 enter_route(b);start_guard(b)
 var original:Dictionary=b.session.snapshot();var pending:Dictionary=b.session._pending.duplicate(true)
 b.save_path="user://no-arrival-backend-parent/save.json";fight(b)
 check(not b.battle_state.get("settled",false) and b.session.snapshot()==original,"savefail keeps complete prebattle profile")
 check(b.session._pending.quest_guard.arrival==pending.quest_guard.arrival,"savefail retains original issued guard context")
 check(not b.handle({"type":"battle_close"}).ok,"repeated failed save still cannot publish victory Warp")
 b.save_path="";check(b.handle({"type":"battle_close"}).ok,"normal original result retries and closes")
 var sage:Dictionary=b.original_quests.npc_by_id(SAGE_ID)
 check(b.automation.position_cell==Vector2i(34,39) and b.quest_arrival.check_action(b,sage,sage.branches[0],"ACCEPT").is_empty(),"real saved victory Warp grants final mark")
 # Normal adjacent walking retains it; project capture to a different room
 # invalidates it and the old battle result cannot grant it again.
 check(b.handle({"type":"report_position","map_id":41,"cell":[34,38]}).ok,"ordinary reward-room movement allowed")
 check(b.quest_arrival.check_action(b,sage,sage.branches[0],"ACCEPT").is_empty(),"ordinary reward-room movement retains final mark")
 for point in [[34,39],[34,40],[34,43]]:
  check(b.handle({"type":"report_position","map_id":41,"cell":point}).ok,"actual original reward exit movement")
 check(b.quest_arrival.has_arrival(b,41,Vector2i(34,43)) and not b.quest_arrival.check_action(b,sage,sage.branches[0],"ACCEPT").is_empty(),"original same-map reward exit retains route but clears final eligibility")
 check(b.handle({"type":"reviewed_hunt_travel","map_id":41,"area_id":408,"template_id":65}).ok,"authorized capture exits reward component")
 check(b.handle({"type":"reviewed_hunt_travel","map_id":41,"area_id":416,"template_id":72}).ok,"authorized capture may return to exact reward-room pet point")
 check(not b.quest_arrival.check_action(b,sage,sage.branches[0],"ACCEPT").is_empty(),"capture return grants no final eligibility")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":SAGE_ID,"mode":mode}).ok,"raw helper request cannot promote capture arrival")
 check(not b.handle({"type":"auto_start","kind":"hunt","map_id":41,"cell":[34,26]}).ok and b.automation.position_cell==Vector2i(34,35),"auto_start cannot forge new authoritative position")
 b.free()
 b=fresh();enter_route(b);start_guard(b)
 b.automation.position_changed(41,Vector2i(35,42));b.automation.position_changed(41,Vector2i(34,42))
 original=b.session.snapshot();b.save_path="user://no-arrival-backend-parent/save.json"
 fight(b);check(b.session.snapshot()==original and not b.battle_state.get("settled",false),"invalidated route still uses atomic save rollback")
 b.save_path="";check(b.handle({"type":"battle_close"}).ok,"invalidated route saves ordinary combat and closes normally")
 check(not str(b.battle_state.get("quest_arrival_denied","")).is_empty() and not b.battle_state.has("quest_warp") and b.automation.position_cell==Vector2i(34,42),"invalidated route denies only quest side effects and victory Warp")
 check(b.session._pending.is_empty() and b.session.snapshot().completed_battles.size()==original.completed_battles.size()+1,"ordinary combat committed once without stuck pending")
 claims(b)
 b.free();WorldClock.clock=old
 print("QUEST ARRIVAL BACKEND: %d failures"%failures);quit(1 if failures else 0)
func claims(b)->void:
 var pending:={"enemies":[{"generated_drops":[2533,2482]}]}
 var result:={"enemies":[{"hp":0,"captured":false}]}
 var original:Array=[{"enemy":0,"item":0},{"enemy":0,"item":1}]
 check(b._allowed_guard_claims(pending,original,[2533],result)==[{"enemy":0,"item":1}] and original.size()==2,"exact special ID filtered on copy; ordinary Munde item preserved")
 for malformed in [[{"enemy":0,"item":0},{"enemy":0,"item":0}],[{"enemy":99,"item":0}],[{"enemy":0,"item":99}]]:
  check(b._allowed_guard_claims(pending,malformed,[2533],result)==malformed,"duplicate or invalid index never washed clean by filtering")
 result.enemies[0].hp=1
 check(b._allowed_guard_claims(pending,original,[2533],result)==original,"living enemy claim remains for Session to reject")
 result.enemies[0].hp=0;result.enemies[0].captured=true
 check(b._allowed_guard_claims(pending,original,[2533],result)==original,"captured enemy claim remains for Session to reject")
