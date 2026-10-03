extends "res://tests/quest_arrival_backend_test.gd"
## Final NPC transactions reuse the production route and battle hooks.
func adult(b)->void:
 check(preload("res://tests/support/original_route_driver.gd").complete_adult(b).get("ok",false),"original adult gate and corridors establish END4")
func run()->void:
 var old:Callable=WorldClock.clock;WorldClock.clock=func():return WorldClock.ERA+100
 var b=fresh();adult(b);Equipment.add(b.session._profile,2603)
 enter_route(b);start_guard(b);fight(b)
 check(b.handle({"type":"battle_close"}).ok,"real victory publishes reward arrival")
 for y in range(38,26,-1):
  check(b.handle({"type":"report_position","map_id":41,"cell":[34,y]}).ok,"walk original reward component to sage")
 var sage:Dictionary=b.original_quests.npc_by_id(SAGE_ID)
 var branch:Dictionary=b.original_quests.branch_for(sage,b.session.snapshot())
 var before:Dictionary=b.session.snapshot()
 check(not b.original_quests.transact(b,before,branch,"reward").ok and b.session.snapshot()==before,"missing real NPC context fails closed")
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":SAGE_ID})
 check(r.ok,"legitimate real NPC opens reward")
 r=choose(b,r,"yes")
 check(r.ok and r.has("dialogue"),"real reward confirmation remains pending")
 b.save_path="user://no-arrival-transaction-parent/save.json"
 var failed:Dictionary=choose(b,r,"ok")
 check(failed.get("reason","")=="save_failed" and b.session.snapshot()==before,"final reward save failure rolls profile back")
 check(b.quest_arrival.check_action(b,sage,branch,"reward").is_empty(),"save failure does not destroy legitimate arrival")
 b.save_path=""
 r=b.handle({"type":"quest_talk","npc_id":SAGE_ID});r=choose(b,r,"yes")
 var stale:Dictionary=r.duplicate(true)
 b.automation.position_changed(41,Vector2i(35,27));b.automation.position_changed(41,Vector2i(34,27))
 check(not choose(b,stale,"ok").ok and b.session.snapshot()==before,"old reward token cannot survive project out-and-back")
 check(not b.handle({"type":"quest_talk","npc_id":SAGE_ID}).ok,"early NPC dialogue rejects same-room project arrival")
 check(not b.original_quests.transact(b,before,branch,"reward","",SAGE_ID).ok and b.session.snapshot()==before,"final direct transaction independently rejects invalid arrival")
 b.free();WorldClock.clock=old
 print("QUEST ARRIVAL TRANSACTIONS: %d failures"%failures);quit(1 if failures else 0)
