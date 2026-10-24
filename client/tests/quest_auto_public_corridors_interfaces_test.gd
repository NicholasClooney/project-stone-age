extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Production policy/navigation interfaces; no runner execution or speed claims.
const Backend=preload("res://server/backend.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Extra=preload("res://server/quest_auto_public_corridors.gd")
var failures:=0
var assertions:=0
var next_fast:=0
var next_fallback:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func at(b,map_id:int,cell:Vector2i,reason:String="project")->void:
 b.automation.position_changed(map_id,cell,false,reason)
func path_tail(b,lane:Dictionary,cells:Array,start_index:int)->Array:
 var result:Array=cells.slice(start_index+1).duplicate(true)
 result.append({"map_id":int(lane.map),"cell":[lane.door.x,lane.door.y]})
 result.append({"map_id":int(lane.to_map),"cell":[lane.target.x,lane.target.y],"portal":b.quest_helper.places.links(int(lane.map))[lane.door].duplicate(true)})
 return result
func make_segment(b,audit:Dictionary,kind:String)->Dictionary:
 var points:Array=[audit.points[-1].duplicate(true)] if kind=="public_jump" else audit.points.slice(0,mini(3,audit.points.size())).duplicate(true)
 return {"kind":kind,"audit_id":audit.id,"points":points,"from_map":b.automation.position_map,"from_cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
func run()->void:
 var began:=Clock.ticks_msec()
 var b=Backend.new()
 var nav=Navigation.new()
 check(nav.public_routes.LANES.size()==7 and Extra.LANES.size()==29 and nav.public_routes.lanes().size()==36,"Original seven plus exactly 29 reviewed additions")
 for lane in nav.public_routes.LANES:
  check(nav.public_routes.corridor(nav,b,lane).size()>2,"Original corridor remains geometrically valid: "+str(lane.id))
 for lane in Extra.LANES:
  at(b,int(lane.map),lane.start);nav.clear()
  var cells:Array=nav.public_routes.corridor(nav,b,lane)
  check(cells.size()>2,"Expanded exact corridor remains valid: "+str(lane.id))
  if cells.size()<3:continue
  var npc:Dictionary={"id":"interface-geometry:"+str(lane.id),"map_id":int(lane.to_map),"cell":[lane.target.x,lane.target.y]}
  var start_index:=0
  var route:=path_tail(b,lane,cells,start_index)
  var starts_on_portal:bool=b.quest_helper.places.links(int(lane.map)).has(lane.start)
  if starts_on_portal:
   check(nav.public_routes.audit(nav,b,route).is_empty(),"A portal source cannot jump or stride before leaving")
   var initial:Dictionary=nav.next_segment(b,npc,"B",3)
   check(initial.get("kind")=="walk" and nav.validate_segment(b,npc,initial),"Production next_segment first proposes valid real walk from portal")
   # Geometry fixture advances one proposed original cell; executor evidence is separate.
   start_index=1
   at(b,int(lane.map),Vector2i(cells[1].cell[0],cells[1].cell[1]),"walk")
   nav.clear();route=path_tail(b,lane,cells,start_index)
  var audit:Dictionary=nav.public_routes.audit(nav,b,route)
  check(not audit.is_empty(),"Production audit accepts only exact A suffix: "+str(lane.id))
  if audit.is_empty():continue
  var jump:=make_segment(b,audit,"public_jump")
  var stride:=make_segment(b,audit,"public_stride")
  check(nav.public_routes.validate_audit(nav,b,jump) and nav.public_routes.validate_audit(nav,b,stride),"Production validation accepts current B and bounded C proposals")
  check(jump.points[0]==cells[-1] and not b.quest_helper.places.links(int(lane.map)).has(Vector2i(jump.points[0].cell[0],jump.points[0].cell[1])),"B destination is the last public cell, never the door")
  var bad:=jump.duplicate(true);bad.points[0].cell=[lane.door.x,lane.door.y]
  check(not nav.public_routes.validate_audit(nav,b,bad),"B cannot consume original portal step")
  bad=stride.duplicate(true);bad.remaining=bad.points.slice(1)
  check(not nav.public_routes.validate_audit(nav,b,bad),"Uncommitted prefix cannot pretend to have advanced")
  var forged:=route.duplicate(true);forged[-1].portal.source="unreviewed.create:1"
  check(nav.public_routes.audit(nav,b,forged).is_empty(),"Exact path cannot launder a changed portal source")
  var door:Dictionary=b.quest_helper.places.links(int(lane.map))[lane.door]
  var saved_source:String=door.source
  door.source="unreviewed.create:1"
  check(nav.public_routes.audit(nav,b,route).is_empty() and not nav.public_routes.validate_audit(nav,b,jump),"Live source change invalidates cached corridor and B")
  var changed:Dictionary=nav.next_segment(b,npc,"B",3)
  check(changed.is_empty() or changed.get("kind")=="walk","Live source change falls back to A or safely stops")
  door.source=saved_source;door.disabled=true
  check(nav.public_routes.audit(nav,b,route).is_empty() and not nav.public_routes.validate_audit(nav,b,stride),"Disabled door invalidates cached C")
  door.erase("disabled")
  var original_start:Dictionary=lane.start_sources[0]
  var start_links:Dictionary=b.quest_helper.places.links(int(original_start.from_map))
  var start_key:=Vector2i(original_start.cell[0],original_start.cell[1])
  var original_link:Dictionary=start_links[start_key].duplicate(true)
  # Some duplicated originals intentionally share one landing. Remove all reviewed origins.
  var restored:Array=[]
  for source in lane.start_sources:
   var links:Dictionary=b.quest_helper.places.links(int(source.from_map))
   var key:=Vector2i(source.cell[0],source.cell[1])
   restored.append({"map":int(source.from_map),"key":key,"link":links[key].duplicate(true)})
   links[key].source="unreviewed-start.create:1"
  check(nav.public_routes.corridor(nav,b,lane).is_empty(),"Changed landing-source identities fail closed")
  for entry in restored:b.quest_helper.places.links(entry.map)[entry.key]=entry.link
  check(Extra.same(start_links[start_key],original_link),"Start identities restored after isolated mutation")
  # Real public NPC projection changes, not a standalone geometric predicate.
  var outside:Array=cells[-1].cell
  var blocker:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
  check(not blocker.is_empty(),"Use a real active NPC and its production movement state")
  if blocker.is_empty():continue
  b.original_quests.npc_state.moved(str(blocker.id),[[int(lane.map),int(outside[0]),int(outside[1])]])
  b.original_quests.refresh_npc_state()
  check(not nav.public_routes.validate_audit(nav,b,jump),"A newly occupied landing invalidates actual production B validation")
  check(not nav.public_routes.public_cell(nav,b,int(lane.map),Vector2i(outside[0],outside[1])),"Live occupancy reaches production public-cell classification")
  b.original_quests.npc_state.moved(str(blocker.id),[[int(blocker.map_id),int(blocker.cell[0]),int(blocker.cell[1])]])
  b.original_quests.refresh_npc_state()
  check(not nav.blocked(b,int(lane.map)).has(Vector2i(outside[0],outside[1])),"Restoring through the real NPC API invalidates the old occupied-cell cache")
  nav.clear()
  var actual:Dictionary=nav.next_segment(b,npc,"C",99)
  if actual.get("kind")=="public_stride":
   next_fast+=1
   check(actual.points.size()<=3 and nav.validate_segment(b,npc,actual),"Production next_segment/validate_segment uses central bounded stride")
  else:
   next_fallback+=1
   check(actual.is_empty() or actual.get("kind")=="walk","Different actual A door selection remains walk/safe stop")
  print("PUBLIC_INTERFACE ",lane.id," next_kind=",actual.get("kind","empty")," actual_door_matches=",actual.get("audit_id","")==lane.id)
 for map_id in [10201,10202,10203,10204,120,121,20101,20401,20406,118,119,122,300,32001]:
  for cell in [Vector2i(105,228),Vector2i(108,225),Vector2i(103,228)]:
   check(not nav.public_routes.public_cell(nav,b,map_id,cell),"Production policy keeps sea/maze/300 approach outside public corridors")
 at(b,1000,Vector2i(89,73));nav.clear()
 var shell:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
 check(nav.next_segment(b,shell,"B",3).get("kind")=="walk","Unaudited public village origin uses A")
 at(b,-1,Vector2i.ZERO);nav.clear()
 check(nav.next_segment(b,shell,"B",3).is_empty(),"Unknown A geometry is not hidden by B")
 b.free()
 print("PUBLIC_INTERFACES_SUMMARY ",JSON.stringify({"assertions":assertions,"failures":failures,"next_fast":next_fast,"next_fallback":next_fallback,"wall_ms":Clock.ticks_msec()-began}))
 quit(1 if failures else 0)
