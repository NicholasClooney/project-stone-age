extends "res://tests/transmigration_earth_route_test.gd"
const Policy=preload("res://server/quest_arrival_policy.gd")
const Earth=preload("res://server/transmigration_earth_helper.gd")
func run()->void:
 if not check(Policy.scope(21001)=="earth" and Policy.scope(21015)=="earth","shared earth policy must be installed before final acceptance"):
  quit(1);return
 var b=fresh(80);b.save_path=""
 Rules.set_flag(b.session._profile,"ended",4,true)
 Rules.set_flag(b.session._profile,"now",39,true)
 for id in [2698,2699,2700]:b.session.OriginalEquipment.add(b.session._profile,id)
 # Authoritative project relocation can change position but cannot mint a
 # quest route. Exercise both raw helper modes, old step and final authority.
 for script in ["200/sb_dtp.arg","200/sb_dbt.arg","jaruga/event/ruri01","jaruga/event/ruri05","jaruga/event/ruri06"]:
  var n:=source(b,script)
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0]),int(n.cell[1])+1))
  check(b.automation.position_map==int(n.map_id) and not b.quest_arrival.has_arrival(b,int(n.map_id),b.automation.position_cell),"project relocation reaches actual map without route proof "+script)
  var before:Dictionary=b.session.snapshot().duplicate(true)
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":n.id,"mode":mode}).ok,"project placement cannot authorize raw helper "+script+mode)
  var old:Dictionary={"npc_id":n.id,"map_id":n.map_id,"cell":n.cell,"current":true,"actionable":true}
  check(not Earth.can_visit(b.quest_helper,b,old),"old step cannot mint route "+script)
  check(not b.handle({"type":"quest_talk","npc_id":n.id}).ok,"project placement cannot open protected branch "+script)
  var branch:Dictionary=b.original_quests.branch_for(n,b.session.snapshot())
  check(not b.original_quests.transact(b,b.session.snapshot(),branch,"ACCEPT","",n.id).ok,"final transaction independently refuses project arrival "+script)
  check(b.session.snapshot()==before,"refusal leaves items and flags unchanged "+script)
 b.free()
 b=fresh(80);b.save_path=""
 complete_core_route(b)
 check(b.quest_arrival.has_arrival(b,21015,b.automation.position_cell),"source entrance, judgement and two real battles grant final route")
 # Isolated transaction material fixture; route proof comes exclusively from
 # the complete preceding original route, never a scope/mark assignment.
 for script in ["jaruga/event/ruri05","jaruga/event/ruri06"]:
  b.session.OriginalEquipment.add(b.session._profile,2700)
  var n:=source(b,script)
  check(approach(b,n.id),"walk to actual bag")
  var here:Vector2i=b.automation.position_cell
  for mode in ["near","arrival"]:
   check(b.handle({"type":"quest_visit","npc_id":n.id,"mode":mode}).ok and b.automation.position_cell==here,"legitimate near helper stays at original position "+mode)
  check(trade(b,n.id).ok and Rules.item_count(b.session.snapshot(),2700)==0,"legitimate original bag trade "+script)
 var n:=source(b,"jaruga/event/ruri05")
 b.session.OriginalEquipment.add(b.session._profile,2700)
 check(approach(b,n.id),"walk before project relocation revoke")
 b.automation.position_changed(21015,b.automation.position_cell+Vector2i.RIGHT)
 check(not b.quest_arrival.has_arrival(b,21015,b.automation.position_cell),"project movement revokes final arrival")
 check(not b.handle({"type":"quest_talk","npc_id":n.id}).ok,"remaining feather cannot reuse revoked final route")
 b.free()
 print("TRANSMIGRATION EARTH ARRIVAL: %d failures"%failures)
 quit(1 if failures else 0)
