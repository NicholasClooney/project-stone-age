extends SceneTree
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Plan=preload("res://server/quest_auto_golden_bui_plan.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Fixture=preload("res://tests/support/quest_auto_golden_bui_fixture.gd")
var failures:=0
var assertions:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 for row in Sources.table().portals:
  var b=Fixture.new()
  var nav=Navigation.new()
  var map_id:=int(row.from_map)
  var goal:=Vector2i(int(row.from_cell[0]),int(row.from_cell[1]))
  var portal:Dictionary={"from_map":map_id,"from_cell":row.from_cell.duplicate(),"to_map":int(row.to_map),"to_cell":row.to_cell.duplicate()}
  var before:=portal.duplicate(true)
  b.at(map_id,goal+Vector2i(0,2))
  var selected:=Plan.select(b,2)
  check(selected.status=="step" and selected.step.get("portal",{})==portal,"All 30 won floors select only their frozen stairs")
  check(nav.next_portal(b,portal)=={"map_id":map_id,"cell":[goal.x,goal.y+1]},"First original logical cell after won Warp")
  b.at(map_id,goal+Vector2i(0,1))
  check(nav.next_portal(b,portal)=={"map_id":map_id,"cell":[goal.x,goal.y]},"Second original logical cell reaches stairs")
  b.at(map_id,goal)
  var crossing:Dictionary=nav.next_portal(b,portal)
  check(crossing.get("portal",{})==row.live_link and crossing.get("cell",[])==row.to_cell,"Exact original portal point")
  check(portal==before,"Geometry does not mutate proposal")
  b.quest_arrival.valid=false
  check(nav.next_portal(b,portal).is_empty(),"No proof cannot cross")
  b.quest_arrival.valid=true
  b.at(map_id,Vector2i(goal.x,21))
  check(nav.next_portal(b,portal).is_empty(),"Entry component cannot cross source y18 wall")
  b.at(map_id,goal+Vector2i(0,2))
  b.quest_helper.places.residents.append({"id":"dynamic-stair-blocker","map_id":map_id,"cell":row.from_cell.duplicate()})
  check(nav.next_portal(b,portal).is_empty(),"Live actor blocks stair even with unchanged NPC version")
  b.quest_helper.places.residents.pop_back()
  var link:Dictionary=b.quest_helper.places.portals[str(map_id)][goal]
  link.disabled=true
  check(nav.next_portal(b,portal).is_empty(),"Disabled link refuses")
  link.erase("disabled");link.gate_source="genout/wpm_10202_31_13"
  check(nav.next_portal(b,portal).is_empty(),"Even generally allowed permit gate cannot replace stairs")
  link.erase("gate_source");link.source="quiz.create:0"
  check(nav.next_portal(b,portal).is_empty(),"Changed original source line refuses")
  link.source=row.live_link.source
  for malformed in [true,29.25,INF,NAN,"29"]:
   var bad:=portal.duplicate(true);bad.from_cell[0]=malformed
   check(nav.next_portal(b,bad).is_empty(),"Coordinates cannot be coerced")
  var alternate:=portal.duplicate(true);alternate.from_cell[0]+=1;alternate.to_cell[0]+=1
  check(nav.next_portal(b,alternate).is_empty(),"Adjacent genuine original portal is not an automatic fallback")
  var extra:=portal.duplicate(true);extra.proof=true
  check(nav.next_portal(b,extra).is_empty(),"Proposal cannot provide proof")
 print("golden bui exact portals: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
