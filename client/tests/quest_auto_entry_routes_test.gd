extends SceneTree
## UNRUN synthetic geometry: no Backend, quest flags, arrival receipts or registration.
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Entry=preload("res://server/quest_auto_entry_routes.gd")
class GeometryEntry:
 extends "res://server/quest_auto_entry_routes.gd"
 func _grid(b,map_id:int)->Dictionary:return b.grids.get(map_id,{})
class TinyPointEntry:
 extends GeometryEntry
 func _point_budget()->int:return 6
class GeometryNav:
 extends "res://server/quest_auto_navigation.gd"
 var decisions:Array=[]
 var plan_calls:=0
 var fallback_calls:=0
 func data(b,map_id:int)->Dictionary:return b.grids.get(map_id,{})
 func blocked(b,map_id:int)->Dictionary:return _portal_occupied(b,map_id)
 func _entry_fallback(b,npc:Dictionary)->Array:
  fallback_calls+=1
  var result:Array=super._entry_fallback(b,npc)
  decisions.append({"call":"fallback","origin":[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y],"result":result.duplicate(true),"reason":entry_routes.last_reason,"searches":entry_routes.searches,"context_copies":entry_routes.context_copies,"visited":entry_routes.visited_cells,"loaded":entry_routes.loaded_cells,"edges":entry_routes.edge_count,"output":entry_routes.output_points})
  return result
 func plan(b,npc:Dictionary)->Array:
  plan_calls+=1
  var before:int=fallback_calls
  var result:Array=super.plan(b,npc)
  decisions.append({"call":"plan","number":plan_calls,"origin":[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y],"source":"entry_fallback" if fallback_calls!=before else "old_plan","result":result.duplicate(true)})
  return result
 func next(b,npc:Dictionary)->Dictionary:
  var before:int=plan_calls
  var fallback_before:int=fallback_calls
  var remaining:Array=route.duplicate(true)
  var context_present:bool=not entry_context.is_empty()
  var result:Dictionary=super.next(b,npc)
  decisions.append({"call":"next","origin":[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y],"selection":"new_plan" if plan_calls!=before else ("entry_continuation" if fallback_calls!=fallback_before else "cached_tail"),"entry_context_before":context_present,"remaining_before":remaining,"point":result.duplicate(true),"remaining_after":route.duplicate(true),"plan_calls":plan_calls,"fallback_calls":fallback_calls,"entry_active":entry_active,"entry_anchor":entry_anchor.duplicate(),"pending":entry_pending.duplicate(true)})
  return result
class LegacyNav:
 extends GeometryNav
 func _entry_fallback(_b,_target:Dictionary)->Array:return []
class Positions:
 var position_map:=1
 var position_cell:=Vector2i(1,1)
class NPCState:
 var version:=0
class Original:
 var npc_state=NPCState.new()
class Session:
 var _profile:Dictionary={"player":{"level":20}}
 var permit:=false
 func has_travel_pass()->bool:return permit
class Arrival:
 var reads:=0
 var allowed:=true
 func has_arrival(_b,_map,_cell)->bool:reads+=1;return allowed
class Catalogue:
 var npcs:Array=[]
 var service_npcs:Array=[]
 var npc_overrides:Dictionary={}
 var enabled_events:Array=[18,19]
 func active_npcs()->Array:return npcs.duplicate(true)
class Places:
 var maps:Dictionary={}
 var portals:Dictionary={}
 var residents:Array=[]
 func info(id:int)->Dictionary:return maps.get(str(id),{})
 func links(id:int)->Dictionary:return portals.get(str(id),{})
class Helper:
 var places=Places.new()
class World:
 var automation=Positions.new()
 var original_quests=Original.new()
 var session=Session.new()
 var quest_arrival=Arrival.new()
 var quest_catalog=Catalogue.new()
 var quest_helper=Helper.new()
 var grids:Dictionary={}
var assertions:=0
var failures:=0
func check(ok:bool,label:String)->void:
 assertions+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func grid(width:int,height:int,wall:int=-1)->Dictionary:
 var blocked=PackedByteArray();blocked.resize(width*height)
 if wall>=0:
  for y in range(height):blocked[y*width+wall]=1
 return {"width":width,"height":height,"blocked":blocked}
func link(from_map:int,cell:Array,to_map:int,target:Array,name:String)->Dictionary:
 return {"from_map":from_map,"cell":cell,"to_map":to_map,"target":target,"source":"synthetic-reviewed:"+name}
func fixture()->World:
 var b=World.new()
 b.grids={1:grid(9,3,4),2:grid(9,3)}
 b.quest_helper.places.maps={"1":{"width":9,"height":3},"2":{"width":9,"height":3}}
 b.quest_helper.places.portals={"1":{Vector2i(3,1):link(1,[3,1],2,[1,1],"out"),Vector2i(5,1):link(1,[5,1],2,[7,1],"back")},"2":{Vector2i(1,1):link(2,[1,1],1,[3,1],"return_left"),Vector2i(7,1):link(2,[7,1],1,[5,1],"return_right")}}
 b.quest_catalog.npcs=[target()]
 return b
func target()->Dictionary:return {"id":"target","map_id":1,"cell":[7,1]}
func planner()->GeometryNav:
 var p=GeometryNav.new();p.entry_routes=GeometryEntry.new();return p
func first_portal(b:World,p:GeometryNav)->Dictionary:
 for _index in range(8):
  var point:Dictionary=p.next(b,target())
  if point.is_empty():return {}
  if not p.validate(b,point):return {}
  if point.has("portal"):return point
  b.automation.position_map=int(point.map_id)
  b.automation.position_cell=Vector2i(point.cell[0],point.cell[1])
 return {}
func commit_fixture(b:World,point:Dictionary)->void:
 # Synthetic authority only. No production transaction/proof claim.
 b.automation.position_map=int(point.map_id)
 b.automation.position_cell=Vector2i(point.cell[0],point.cell[1])
func continuation_guards()->void:
 var b:World=fixture();var p:GeometryNav=planner()
 var point:Dictionary=first_portal(b,p)
 check(not point.is_empty(),"continuation guard reaches original portal proposal")
 if point.is_empty():return
 var searches:int=p.entry_routes.searches
 var tail:Array=p.route.duplicate(true)
 check(p.next(b,target())==point and p.route==tail and p.entry_routes.searches==searches,"uncommitted portal repeats same proposal without consuming or searching")
 var returned:Dictionary=p.next(b,target())
 returned.portal.target[0]=999
 check(p.next(b,target())==point,"repeated proposal cannot mutate pending portal identity")
 check(not p.portal_committed(b,point) and not p.entry_active,"commit notification before actual landing clears intent")
 b=fixture();p=planner();point=first_portal(b,p)
 commit_fixture(b,point)
 check(p.next(b,target()).is_empty() and not p.entry_active,"matching landing coordinate without trusted commit cannot advance")
 for fault in ["landing","portal","arrival","permit","door","disabled","gate","npc","npc_cell","enabled"]:
  b=fixture();p=planner();point=first_portal(b,p)
  commit_fixture(b,point)
  var offered:Dictionary=point.duplicate(true)
  match fault:
   "landing":b.automation.position_cell+=Vector2i.RIGHT
   "portal":offered.portal.source="wrong-original-source"
   "arrival":b.quest_arrival.allowed=false
   "permit":b.session.permit=true
   "door":b.quest_helper.places.portals["2"][Vector2i(7,1)].target=[6,1]
   "disabled":b.quest_helper.places.portals["1"][Vector2i(3,1)].disabled=true
   "gate":b.quest_helper.places.portals["1"][Vector2i(3,1)].gate_source="unreviewed/script"
   "npc":b.original_quests.npc_state.version+=1
   "npc_cell":b.quest_catalog.npcs[0].cell=[7,2]
   "enabled":b.quest_catalog.enabled_events=[18]
  check(not p.portal_committed(b,offered) and not p.entry_active and p.entry_context.is_empty(),"commit rejects changed "+fault+" and clears frozen intent")
 b=fixture();p=planner();point=p.next(b,target())
 b.automation.position_cell=Vector2i(1,0)
 check(p.next(b,target()).is_empty() and not p.entry_active,"same-target unproposed manual displacement clears intent")
 b=fixture();p=planner();point=p.next(b,target())
 commit_fixture(b,point);p.clear()
 check(not p.entry_active and p.entry_pending.is_empty(),"manual move matching proposal still cancels through mandatory runner clear notification")
 b=fixture();p=planner();point=first_portal(b,p)
 p.clear();commit_fixture(b,point)
 check(p.portal_committed(b,point) and not p.entry_active and p.entry_pending.is_empty() and p.entry_context.is_empty(),"cancel clear plus late commit cannot resurrect intent")
 b=fixture();p=planner();point=p.next(b,target())
 var calls:int=p.entry_routes.searches
 check(p.next(b,{"id":"changed","map_id":1,"cell":[1,1]}).is_empty() and not p.entry_active and p.entry_routes.searches==calls,"new nearby target clears journey and keeps old zero-step success")
 b=fixture();p=planner();point=first_portal(b,p)
 commit_fixture(b,point)
 check(p.portal_committed(b,point),"exact actual landing and independent arrival preserve intent")
 calls=p.plan_calls;searches=p.entry_routes.searches
 var next_point:Dictionary=p.next(b,target())
 check(not next_point.is_empty() and not next_point.has("portal") and p.plan_calls==calls and p.entry_routes.searches==searches+1,"confirmed entry searches next first leg without old return-left plan")
 b=fixture();p=planner();point=first_portal(b,p)
 commit_fixture(b,point);check(p.portal_committed(b,point),"budget case confirms original portal")
 p.entry_routes=TinyPointEntry.new()
 check(p.next(b,target()).is_empty() and not p.entry_active and p.entry_routes.last_reason=="budget","continuation exhaustion returns empty and clears intent")
 for mode in ["B","C"]:
  b=fixture();p=planner()
  var segment:Dictionary=p.next_segment(b,target(),mode,3)
  check(segment.get("kind","")=="walk" and segment.get("points",[]).size()==1 and p.validate_segment(b,target(),segment),"entry fallback remains one validated original walk in "+mode)
 # Same-map ordinary portal still needs explicit commit notification. This is
 # synthetic geometry, not a runner publication/reentrancy or arrival test.
 for acknowledge in [false,true]:
  b=fixture();p=planner()
  b.quest_helper.places.portals["1"][Vector2i(3,1)]=link(1,[3,1],1,[5,1],"same_map")
  point=first_portal(b,p)
  check(not point.is_empty() and int(point.get("map_id",-1))==1,"same-map original portal is proposed separately")
  if point.is_empty():continue
  commit_fixture(b,point)
  if acknowledge:
   check(p.portal_committed(b,point) and p.entry_active,"same-map actual landing accepts explicit ordinary portal confirmation")
   check(p.next(b,target()).is_empty() and not p.entry_active,"same-map confirmed target arrival closes fallback journey")
  else:
   check(p.next(b,target()).is_empty() and not p.entry_active,"same-map matching coordinates alone cannot acknowledge portal")
func run()->void:
 var b=fixture();var nav=planner()
 var start:Vector2i=b.automation.position_cell
 var result:Array=nav.plan(b,target())
 check(not result.is_empty() and result[-1].has("portal") and int(result[-1].map_id)==2,"same map disconnected target permits original leave/reenter route")
 check(b.automation.position_cell==start and b.automation.position_map==1,"geometry never writes authority")
 check(nav.entry_routes.searches==1,"fallback invoked only after original local failure")
 # Actual point validation; fixture emulates the caller's sequential commits.
 var logical:=0;var portals:=0;var iterations:=0
 var movements:Array=[]
 while iterations<40:
  iterations+=1
  if b.automation.position_map==1 and b.automation.position_cell.distance_to(Vector2i(7,1))<=2:break
  var p:Dictionary=nav.next(b,target())
  if p.is_empty():check(false,"entry route reaches target without map-ID pruning");break
  var valid:bool=nav.validate(b,p)
  movements.append({"iteration":iterations,"origin":[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y],"point":p.duplicate(true),"validated":valid})
  if not valid:check(false,"every returned point uses original validation");break
  if p.has("portal"):
   portals+=1
   check(p.portal.cell==[b.automation.position_cell.x,b.automation.position_cell.y],"portal remains standalone at exact source cell")
  else:
   logical+=1
   check(absi(int(p.cell[0])-b.automation.position_cell.x)+absi(int(p.cell[1])-b.automation.position_cell.y)==1,"one cardinal walk per proposal")
  b.automation.position_map=int(p.map_id);b.automation.position_cell=Vector2i(p.cell[0],p.cell[1])
  movements[-1].committed=[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y]
  if p.has("portal"):
   var acknowledged:bool=nav.portal_committed(b,p)
   movements[-1].portal_acknowledged=acknowledged
   check(acknowledged,"trusted original portal commit acknowledges exact actual landing")
 var diagnostic:Dictionary={"iterations":iterations,"portal_count":portals,"logical_walks":logical,"final_map":b.automation.position_map,"final_cell":[b.automation.position_cell.x,b.automation.position_cell.y],"clauses":{"two_portals":portals==2,"walked":logical>0,"returned_map1":b.automation.position_map==1},"decisions":nav.decisions,"movements":movements}
 var trace_file=FileAccess.open("user://entry-return-diagnostic.json",FileAccess.WRITE)
 if trace_file:trace_file.store_string(JSON.stringify(diagnostic,"  "));trace_file.close()
 print("ENTRY RETURN DIAGNOSTIC: ",JSON.stringify(diagnostic))
 check(portals==2 and logical>0 and b.automation.position_map==1,"return to a different entry of already visited map")
 continuation_guards()
 # Existing successful A stays byte-for-byte and never calls the fallback.
 b=fixture();nav=planner()
 b.automation.position_map=2
 var near_target:Dictionary={"id":"near","map_id":2,"cell":[7,0]}
 var first:Array=nav.plan(b,near_target)
 var legacy=LegacyNav.new()
 var second:Array=legacy.plan(b,near_target)
 check(not first.is_empty() and first==second and nav.entry_routes.searches==0,"old successful A full sequence preserved without fallback work")
 b=fixture();nav=planner()
 check(nav.plan(b,{"id":"already_near","map_id":1,"cell":[2,1]}).is_empty() and nav.entry_routes.searches==0,"old success containing only origin remains zero-step without fallback")
 # Current blocked exit and future blocked return exit both reject geometry.
 for map_id in [1,2]:
  b=fixture();nav=planner()
  b.quest_catalog.npcs.append({"id":"blocker","map_id":map_id,"cell":[3,1] if map_id==1 else [7,1]})
  check(nav.plan(b,target()).is_empty(),"current/future occupied original door rejects: "+str(map_id))
 for flag in ["disabled","gate_source"]:
  b=fixture();nav=planner()
  b.quest_helper.places.portals["2"][Vector2i(7,1)][flag]=true if flag=="disabled" else "script/source"
  check(nav.plan(b,target()).is_empty(),"ordinary fallback cannot cross "+flag)
 # Positive tail and negative searches invalidate on complete world context.
 b=fixture();nav=planner();var point:Dictionary=nav.next(b,target())
 check(not point.is_empty() and not nav.entry_context.is_empty(),"first leg alone cached")
 var copies:int=nav.entry_routes.context_copies
 var frozen:Dictionary=nav.entry_context
 for _index in range(3):
  check(nav.entry_routes.matches_context(b,target(),frozen),"live full context equals frozen source without another deep copy")
 check(nav.entry_routes.context_copies==copies,"positive context comparisons do not allocate world snapshots")
 b.quest_helper.places.portals["2"][Vector2i(7,1)].disabled=true
 check(not frozen.links["2"][Vector2i(7,1)].has("disabled"),"frozen context does not alias mutated live doors")
 check(nav.next(b,target()).is_empty(),"future door change invalidates cached first leg")
 var searches:int=nav.entry_routes.searches
 copies=nav.entry_routes.context_copies
 check(nav.next(b,target()).is_empty() and nav.entry_routes.searches==searches,"unchanged negative result does not rescan entry graph every tick")
 check(nav.entry_routes.context_copies==copies,"negative cache hit does not duplicate full world")
 b.quest_helper.places.portals["2"][Vector2i(7,1)].erase("disabled")
 check(not nav.next(b,target()).is_empty() and nav.entry_routes.searches>searches,"restored complete door identity permits fresh search")
 var before:Dictionary=nav.entry_routes.context(b,target())
 b.session.permit=true
 check(before!=nav.entry_routes.context(b,target()),"permit participates in invalidation")
 before=nav.entry_routes.context(b,target());b.quest_catalog.npc_overrides["moved"]={"map_id":2,"cell":[7,1]}
 check(before!=nav.entry_routes.context(b,target()),"future NPC projection participates in invalidation")
 # Internal sharing must never expose a mutable leg or source through a return.
 b=fixture();nav=planner()
 var exported:Array=nav.entry_routes.find(nav,b,target())
 var original:Array=exported.duplicate(true)
 if not exported.is_empty():
  exported[0].cell[0]=999
  exported[-1].portal.target[0]=999
 check(not original.is_empty() and nav.entry_routes.find(nav,b,target())==original,"caller mutations do not poison later first-leg results")
 check(b.quest_helper.places.portals["1"][Vector2i(3,1)].target==[1,1],"exported portal deep copy cannot alter authoritative link")
 var internal:Array=[{"map_id":1,"cell":[2,1],"portal":{"target":[1,1]}}]
 var detached:Array=nav.entry_routes._export(internal)
 detached[0].cell[0]=888;detached[0].portal.target[0]=888
 check(internal[0].cell==[2,1] and internal[0].portal.target==[1,1],"final export detaches nested points and portal payload")
 var budget=Entry.new()
 check(budget._reserve_points(Entry.MAX_OUTPUT_POINTS) and not budget._reserve_points(1) and budget.exhausted,"exact cumulative65536 point ceiling rejects one more point")
 b=fixture();nav=planner();nav.entry_routes=TinyPointEntry.new()
 check(nav.entry_routes.find(nav,b,target()).is_empty() and nav.entry_routes.last_reason=="budget" and nav.entry_routes.output_points<=6,"restoration plus final copy exhaust budget without partial result")
 b=fixture();nav=planner();b.quest_arrival.allowed=false
 check(nav.entry_routes.find(nav,b,target()).is_empty() and nav.entry_routes.last_reason=="arrival_required","unqualified current origin cannot start fallback")
 searches=nav.entry_routes.searches;copies=nav.entry_routes.context_copies
 check(nav.entry_routes.find(nav,b,target()).is_empty() and nav.entry_routes.searches==searches and nav.entry_routes.context_copies==copies,"unchanged failed arrival uses negative cache")
 b.quest_arrival.allowed=true
 check(not nav.entry_routes.find(nav,b,target()).is_empty() and nav.entry_routes.searches==searches+1,"arrival input change invalidates failure at same origin and world")
 # More than64 distinct ingress states in one tiny map; no backend or huge asset.
 b=fixture();nav=planner();b.grids={1:grid(80,3),2:grid(9,3)}
 b.quest_helper.places.maps["1"]={"width":80,"height":3};b.quest_helper.places.portals={"1":{},"2":{}}
 b.quest_catalog.npcs=[]
 for x in range(1,72):b.quest_helper.places.portals["1"][Vector2i(x,0)]=link(1,[x,0],1,[x,2],str(x))
 check(nav.entry_routes.find(nav,b,{"id":"unreachable","map_id":2,"cell":[7,1]}).is_empty() and nav.entry_routes.last_reason=="budget","64-node ceiling stops safely without partial route")
 print("quest_auto_entry_routes_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
