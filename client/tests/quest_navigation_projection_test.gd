extends "res://tests/brothers_golden_quests_test.gd"
const Wind=preload("res://server/transmigration_wind_helper.gd")
const Golden=preload("res://server/golden_bui_helper.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
const Water=preload("res://tests/support/water_route_driver.gd")
func wind_reference(helper,backend,wind)->Array:
 var map_id:int=backend.automation.position_map
 var eligibility:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if wind.owns(npc) and int(npc.map_id)==map_id:eligibility.append([str(npc.id),wind.legitimate(backend,npc)])
 return [map_id,backend.original_quests.npc_state.version,wind.region_at(helper,backend,map_id,backend.automation.position_cell) if map_id in range(11201,11216) else -1,eligibility]
func golden_reference(backend)->Array:
 var map_id:int=backend.automation.position_map;var cell:Vector2i=backend.automation.position_cell
 var nearby:Array=[]
 for actor in backend.quest_catalog.active_npcs():
  if int(actor.map_id)!=map_id or not Golden.owns(actor) or str(actor.get("kind",""))=="golden_bui_gate":continue
  var delta:=cell-Vector2i(int(actor.cell[0]),int(actor.cell[1]))
  if maxi(absi(delta.x),absi(delta.y))<=2:nearby.append(str(actor.id))
 return [map_id,cell.y<18,backend.quest_arrival.has_arrival(backend,map_id,cell),nearby] if Golden.protected_map(map_id) else [map_id]
func compare(b,wind,label:String)->void:
 check(wind.stage_key(b.quest_helper,b)==wind_reference(b.quest_helper,b,wind),label+" exact original wind key")
 check(Golden.stage_key(b)==golden_reference(b),label+" exact original golden key")
 var expected:Array=b.quest_catalog.active_npcs().filter(func(n):return int(n.map_id)==b.automation.position_map)
 check(b.quest_catalog.active_npcs_on_map(b.automation.position_map)==expected,label+" exact ordered personal map projection")
func run()->void:
 var b=fresh();var wind=Wind.new()
 var all_active:Array=b.quest_catalog.active_npcs();var actual_maps:Array=[]
 for npc in all_active:
  if not int(npc.map_id) in actual_maps:actual_maps.append(int(npc.map_id))
 for map_id in actual_maps:
  check(b.quest_catalog.active_npcs_on_map(map_id)==all_active.filter(func(n):return int(n.map_id)==map_id),"all actual map projections including independent services "+str(map_id))
 check(b.quest_catalog.active_npcs_on_map(-909).is_empty(),"absent map returns empty")
 for map_id in [100,11107,11201,11206,11215,21201,21215,31301,800,810,811,840]:
  b.automation.position_changed(map_id,Vector2i(10,10));compare(b,wind,"map"+str(map_id))
  b.original_quests.npc_state.version+=1;compare(b,wind,"personal version "+str(map_id))
 var public_npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/genou_3@100:346:356")
 b.automation.position_changed(21215,Vector2i(19,20))
 b.quest_catalog.npc_overrides[str(public_npc.id)]={"map_id":21215,"cell":[20,20]}
 compare(b,wind,"wind NPC personally moved to unrelated water map")
 check(not wind.stage_key(b.quest_helper,b)[3].is_empty(),"override map is not lost by hardcoded floor filtering")
 b.quest_catalog.npc_overrides[str(public_npc.id)].hidden=true
 compare(b,wind,"hidden moved wind NPC")
 b.quest_catalog.npc_overrides.clear()
 var golden:Dictionary={}
 for actor in b.quest_catalog.active_npcs():
  if Golden.protected_map(int(actor.map_id)) and Golden.owns(actor) and str(actor.get("kind",""))!="golden_bui_gate":golden=actor;break
 check(not golden.is_empty(),"actual golden challenge source exists")
 if not golden.is_empty():
  b.automation.position_changed(int(golden.map_id),Vector2i(golden.cell[0]+1,golden.cell[1]));compare(b,wind,"golden near talk")
  var near:Array=Golden.stage_key(b)
  b.automation.position_changed(int(golden.map_id),Vector2i(golden.cell[0]+5,golden.cell[1]));compare(b,wind,"golden far talk")
  check(near!=Golden.stage_key(b),"golden original near-talk invalidation retained")
 # Prerequisite is an explicit profile fixture; original gate and all interior
 # steps issue authority naturally. Never grant a scope/mark to test a key.
 Rules.set_flag(b.session._profile,"ended",4,true)
 var gate:Dictionary=b.original_quests.npc_by_id("genout/wpm_100_278_325@100:278:325")
 b.automation.position_changed(100,Vector2i(279,325))
 check(Water.commit(b,gate),"actual wind source gate authorizes original route")
 var npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/genou_4@11206:5:36")
 var close:=Vector2i(5,37)
 var reached:bool=Route.walk(b,11206,close,range(11201,11207)).get("ok",false)
 check(reached and wind.legitimate(b,npc),"real six-floor route reaches legitimate near-talk range")
 compare(b,wind,"legitimate wind near talk")
 var near:Array=wind.stage_key(b.quest_helper,b);var moved:bool=false
 for delta in [Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-4)]:
  if Route.path(b,11206,close+delta,[11206]).is_empty():continue
  moved=Route.walk(b,11206,close+delta,[11206]).get("ok",false);break
 check(moved and not wind.legitimate(b,npc),"real walking out of talk range loses eligibility")
 compare(b,wind,"legitimate wind far talk")
 check(near!=wind.stage_key(b.quest_helper,b),"wind original near-talk invalidation retained")
 var projected:Array=b.quest_catalog.active_npcs_on_map(11206)
 if not projected.is_empty():projected[0].cell[0]=-909
 check(b.quest_catalog.active_npcs_on_map(11206)==b.quest_catalog.active_npcs().filter(func(n):return int(n.map_id)==11206),"map projection returns deep isolated records")
 b.free();print("QUEST NAVIGATION PROJECTION: %d failures"%failures);quit(1 if failures else 0)
