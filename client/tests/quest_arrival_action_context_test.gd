extends "res://tests/quest_arrival_transactions_test.gd"
## Exercises generic receipts through existing production gates and combat.
## Third-stage source stages remain disabled until their separate policy lands.
func walk_sage(b)->void:
 for y in range(38,26,-1):
  check(b.handle({"type":"report_position","map_id":41,"cell":[34,y]}).ok,"walk to source sage")
func run()->void:
 # Isolated identity-policy checks do not mint a runtime arrival grant.
 var king:Dictionary={"id":"777/ten.arg@32021:31:28","source_script":"777/ten.arg","map_id":32021,"cell":[31,28],"kind":"original_transmigration","handler":"Transmigration","service_id":"777/ten.arg","branches":[]}
 var policy=preload("res://server/quest_arrival_policy.gd")
 check(policy.context_service(king),"only reviewed king identity supports empty service branch")
 for field in ["id","source_script","map_id","cell","kind","handler","service_id","branches"]:
  var changed:Dictionary=king.duplicate(true)
  changed[field]=0 if field=="map_id" else ([0] if field in ["cell","branches"] else "forged")
  check(not policy.context_service(changed),"changed king %s identity rejected"%field)
 var old:Callable=WorldClock.clock;WorldClock.clock=func():return WorldClock.ERA+100
 var b=fresh();adult(b);Equipment.add(b.session._profile,2603)
 enter_route(b);start_guard(b);fight(b)
 check(b.handle({"type":"battle_close"}).ok,"actual saved victory publishes mark")
 walk_sage(b)
 var a=b.quest_arrival
 var npc:Dictionary=b.original_quests.npc_by_id(SAGE_ID)
 var branch:Dictionary=b.original_quests.branch_for(npc,b.session.snapshot())
 var proof:Dictionary=a.action_context(b,npc,branch,"reward")
 check(not proof.is_empty() and a.check_action_context(b,proof).is_empty(),"real route issues private action receipt")
 var fake:Dictionary=proof.duplicate(true);fake.serial=int(fake.get("serial",0))+1
 check(not a.check_action_context(b,fake).is_empty(),"client-shaped receipt cannot authorize")
 a.consume_action_context(fake)
 check(a.check_action_context(b,proof).is_empty(),"forged consume cannot revoke real receipt")
 var other=fresh()
 check(not other.quest_arrival.check_action_context(other,proof).is_empty(),"another character or loaded authority cannot reuse receipt")
 other.free()
 var altered:Dictionary=npc.duplicate(true);altered.cell=[34,26]
 check(a.action_context(b,altered,branch,"reward").is_empty(),"mutated actual NPC rejected")
 check(a.action_context(b,npc,{},"SERVICE").is_empty(),"ordinary NPC cannot use empty service branch")
 var forged_branch:Dictionary=branch.duplicate(true);forged_branch["untrusted"]=true
 check(a.action_context(b,npc,forged_branch,"reward").is_empty(),"mutated source branch rejected")
 var previous:Dictionary=proof
 proof=a.action_context(b,npc,branch,"reward")
 check(not a.check_action_context(b,previous).is_empty() and a.check_action_context(b,proof).is_empty(),"new preview supersedes previous receipt")
 var before:Dictionary=b.session.snapshot()
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":SAGE_ID});r=choose(b,r,"yes")
 b.save_path="user://no-action-context-parent/save.json"
 check(choose(b,r,"ok").get("reason","")=="save_failed" and b.session.snapshot()==before,"real transaction failed save rolls back")
 check(a.check_action_context(b,proof).is_empty() and a.check_action_context(b,proof).is_empty(),"failed save and repeated checks preserve exact receipt")
 b.save_path=""
 # Leave the actual reward component, win again, and return to the same cell.
 # The continuous route epoch survives, but the new final mark is a new grant.
 for y in range(28,41):
  check(b.handle({"type":"report_position","map_id":41,"cell":[34,y]}).ok,"walk original reward exit")
 check(b.handle({"type":"report_position","map_id":41,"cell":[34,43]}).ok,"actual original portal exits reward room")
 check(not a.check_action_context(b,proof).is_empty(),"room exit invalidates old final receipt")
 check(b.handle({"type":"report_position","map_id":41,"cell":[34,42]}).ok,"walk back to original guard")
 start_guard(b);fight(b)
 check(b.handle({"type":"battle_close"}).ok,"second real victory publishes fresh mark")
 walk_sage(b)
 check(not a.check_action_context(b,proof).is_empty(),"regaining same final room never revives previous preview")
 var renewed:Dictionary=a.action_context(b,npc,branch,"reward")
 check(not renewed.is_empty() and renewed.epoch==proof.epoch and renewed.marks!=proof.marks,"mark generation changes independently of continuous route epoch")
 r=b.handle({"type":"quest_talk","npc_id":SAGE_ID});r=choose(b,r,"yes")
 check(choose(b,r,"ok").ok,"real reward save succeeds on retry")
 check(a.check_action_context(b,renewed).is_empty(),"generic receipt remains until owning service consumes after save")
 a.consume_action_context(renewed)
 check(not a.check_action_context(b,renewed).is_empty() and not a.has_arrival(b,41,Vector2i(34,27)),"successful consume revokes route and receipt once")
 a.consume_action_context(renewed)
 check(not a.check_action_context(b,renewed).is_empty(),"duplicate consume cannot revive receipt")
 b.free();WorldClock.clock=old
 print("QUEST ARRIVAL ACTION CONTEXT: %d failures"%failures);quit(1 if failures else 0)
