extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Water=preload("res://tests/support/water_route_driver.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
func run()->void:
 var b=fresh();Water.install_fixture(b)
 check(Route.complete_adult(b).get("ok",false),"real adult ritual before original level65 gates")
 for script in ["genout/wpm_300_247_222","genout/wpm_300_182_162"]:
  var gate:Dictionary=Water.npc(b,script)
  check(not gate.is_empty(),"pinned original gate catalog "+script)
  if gate.is_empty():continue
  b.automation.position_changed(300,Vector2i(int(gate.cell[0])+1,int(gate.cell[1])))
  var before:Dictionary=b.session.snapshot();b.save_path="user://missing-stone-arrival/save.json"
  check(not Water.commit(b,gate) and b.session.snapshot()==before,"original stone gate save failure preserves public position")
  b.save_path=""
  check(Water.commit(b,gate) and b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"saved original script root grants continuous route")
  var reached:bool=false
  for link in b.quest_helper.places.links(30305).values():
   var target:Vector2i=Vector2i(int(link.cell[0]),int(link.cell[1]))
   for delta in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
    if not Route.path(b,30305,target+delta,range(30301,30308)).is_empty():
     reached=Route.walk(b,30305,target+delta,range(30301,30308)).get("ok",false);break
   if reached:break
  check(reached and b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"actual original portal graph reaches green-stone floor from each entrance")
  b.automation.position_changed(30305,Vector2i(50,52))
  check(not b.quest_arrival.has_arrival(b,30305,Vector2i(50,52)),"project material-floor placement grants no route")
 for map_id in range(30301,30308):check(Policy.scope(map_id)=="water_stone","complete source-connected cave scope")
 check(not Policy.portal_root(300,30301) and not Policy.portal_root(300,30307),"both old convenience portals cannot substitute source gates")
 b.free();print("QUEST ARRIVAL STONE ISLAND: %d failures"%failures);quit(1 if failures else 0)
