extends RefCounted
## Bounded geometry fallback. Never writes actor position, arrival or quest state.
const MapFile=preload("res://scripts/map_file.gd")
const MAX_NODES=64
const MAX_MAPS=16
const MAX_MAP_CELLS=65536
const MAX_LOADED_CELLS=262144
const MAX_VISITED_CELLS=262144
const MAX_EDGES=256
const MAX_OUTPUT_POINTS=65536
var searches:=0
var context_copies:=0
var output_points:=0
var last_reason:=""
var last_context:Dictionary={}
var failed_context:Dictionary={}
var failed_origin:Array=[]
var failed_arrival:=false
var grids:Dictionary={}
var loaded_cells:=0
var visited_cells:=0
var edge_count:=0
var exhausted:=false
var skipped_large_map:=false

func context(b,target:Dictionary)->Dictionary:
 context_copies+=1
 return {"target":target.duplicate(true),"maps":b.quest_helper.places.maps.duplicate(true),
  "links":b.quest_helper.places.portals.duplicate(true),"residents":b.quest_helper.places.residents.duplicate(true),
  "raw_npcs":b.quest_catalog.npcs.duplicate(true),"services":b.quest_catalog.service_npcs.duplicate(true),
  "overrides":b.quest_catalog.npc_overrides.duplicate(true),"enabled":b.quest_catalog.enabled_events.duplicate(),
  "npc_version":b.original_quests.npc_state.version,"level":b.session._profile.player.level,"permit":b.session.has_travel_pass()}

## Live full-field comparison against an owned frozen snapshot, not hashes.
## No world-sized allocation on each movement tick or negative-cache hit.
func matches_context(b,target:Dictionary,frozen:Dictionary)->bool:
 return not frozen.is_empty() and target==frozen.target and b.quest_helper.places.maps==frozen.maps \
  and b.quest_helper.places.portals==frozen.links and b.quest_helper.places.residents==frozen.residents \
  and b.quest_catalog.npcs==frozen.raw_npcs and b.quest_catalog.service_npcs==frozen.services \
  and b.quest_catalog.npc_overrides==frozen.overrides and b.quest_catalog.enabled_events==frozen.enabled \
  and b.original_quests.npc_state.version==frozen.npc_version and b.session._profile.player.level==frozen.level \
  and b.session.has_travel_pass()==frozen.permit

func find(planner,b,target:Dictionary)->Array:
 var origin:Array=[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y]
 var arrived:bool=b.quest_arrival.has_arrival(b,int(origin[0]),Vector2i(origin[1],origin[2]))
 if origin==failed_origin and arrived==failed_arrival and matches_context(b,target,failed_context):
  last_context=failed_context
  last_reason="cached_failure";return []
 var current:=context(b,target)
 last_context=current
 searches+=1
 grids={};loaded_cells=0;visited_cells=0;edge_count=0;output_points=0;exhausted=false;skipped_large_map=false
 last_reason="unreachable"
 var result:Array=[]
 if arrived:
  result=_search(planner,b,target,origin)
 else:last_reason="arrival_required"
 if exhausted:result=[];last_reason="budget"
 elif result.is_empty() and skipped_large_map:last_reason="map_size_budget"
 # A search observes one immutable world revision; never keep a mixed result.
 if not matches_context(b,target,current):result=[];last_reason="world_changed"
 if result.is_empty():failed_context=current;failed_origin=origin;failed_arrival=arrived
 else:failed_context={};failed_origin=[];last_reason="found"
 grids.clear()
 return result

func _grid(b,map_id:int)->Dictionary:
 if grids.has(map_id):return grids[map_id]
 var info:Dictionary=b.quest_helper.places.info(map_id)
 var count:int=int(info.get("width",0))*int(info.get("height",0))
 if count<=0:return {}
 if count>MAX_MAP_CELLS:
  skipped_large_map=true;return {}
 if grids.size()>=MAX_MAPS or loaded_cells+count>MAX_LOADED_CELLS:
  exhausted=true;return {}
 var grid:=MapFile.load_map(b.quest_helper.places.file(map_id))
 if grid.is_empty() or int(grid.width)*int(grid.height)!=count:return {}
 grids[map_id]=grid;loaded_cells+=count
 return grid

func _floor(grid:Dictionary,p:Vector2i)->bool:
 return not grid.is_empty() and p.x>=0 and p.y>=0 and p.x<int(grid.width) and p.y<int(grid.height) and int(grid.blocked[p.y*int(grid.width)+p.x])==0

func _point_budget()->int:return MAX_OUTPUT_POINTS

func _reserve_points(count:int)->bool:
 if count<0 or output_points+count>_point_budget():
  exhausted=true;return false
 output_points+=count
 return true

func _export(points:Array)->Array:
 if not _reserve_points(points.size()):return []
 return points.duplicate(true)

func _walk(parents:Dictionary,depths:Dictionary,goal:Vector2i,map_id:int)->Array:
 if not _reserve_points(int(depths[goal])+1):return []
 var result:Array=[]
 var p:Variant=goal
 while p!=null:
  result.append({"map_id":map_id,"cell":[p.x,p.y]})
  p=parents[p]
 result.reverse()
 return result

func _search(planner,b,target:Dictionary,initial:Array)->Array:
 var queue:Array=[initial]
 var seen:Dictionary={str(initial):true}
 var first_legs:Dictionary={str(initial):[]}
 var cursor:=0
 while cursor<queue.size() and not exhausted:
  var node:Array=queue[cursor];cursor+=1
  var map_id:int=node[0]
  var origin:=Vector2i(node[1],node[2])
  var grid:=_grid(b,map_id)
  if grid.is_empty() or not _floor(grid,origin):continue
  # Pure current personal projection; no npc_by_id()/spawn refresh or live AStar.
  var occupied:Dictionary=planner._portal_occupied(b,map_id)
  if occupied.has(origin):continue
  var links:Dictionary=b.quest_helper.places.links(map_id)
  var parents:Dictionary={origin:null}
  var depths:Dictionary={origin:0}
  var cells:Array=[origin]
  var index:=0
  while index<cells.size():
   if visited_cells>=MAX_VISITED_CELLS:exhausted=true;return []
   visited_cells+=1
   var cell:Vector2i=cells[index];index+=1
   for offset in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
    var point:Vector2i=cell+offset
    if parents.has(point) or occupied.has(point) or links.has(point) or not _floor(grid,point):continue
    parents[point]=cell;depths[point]=int(depths[cell])+1;cells.append(point)
  var first:Array=first_legs[str(node)]
  if map_id==int(target.map_id):
   var best_goal:=Vector2i.ZERO
   var best_depth:=-1
   var anchor:=Vector2i(target.cell[0],target.cell[1])
   for dy in range(-2,3):
    for dx in range(-2,3):
     var goal:=anchor+Vector2i(dx,dy)
     if links.has(goal) or occupied.has(goal) or not parents.has(goal):continue
     var depth:int=depths[goal]
     if best_depth<0 or depth<best_depth:best_goal=goal;best_depth=depth
   if best_depth>=0:
    if not first.is_empty():return _export(first)
    var best:=_walk(parents,depths,best_goal,map_id)
    if exhausted:return []
    best.pop_front();return _export(best)
  for value in links.values():
   var link:Dictionary=value
   if bool(link.get("disabled",false)) or link.has("gate_source") or str(link.get("source","")).is_empty() or not planner.usable(b,link):continue
   if int(link.get("from_map",-1))!=map_id:continue
   var goal:=Vector2i(link.cell[0],link.cell[1])
   if links.get(goal,{})!=link or occupied.has(goal) or not _floor(grid,goal):continue
   var best_neighbour:=origin
   var best_depth:=0 if goal==origin else -1
   if goal!=origin:
    for offset in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
     var neighbour:=goal+offset
     if not parents.has(neighbour):continue
     var depth:int=depths[neighbour]
     if best_depth<0 or depth<best_depth:best_neighbour=neighbour;best_depth=depth
   if best_depth<0:continue
   edge_count+=1
   if edge_count>MAX_EDGES:exhausted=true;return []
   var destination:Array=[int(link.to_map),int(link.target[0]),int(link.target[1])]
   if seen.has(str(destination)):continue
   if queue.size()>=MAX_NODES:exhausted=true;return []
   # Internal first legs are never mutated after publication to another node.
   # Descendants share the reference; only the final public return deep-copies.
   var leg:Array=first
   if leg.is_empty():
    leg=_walk(parents,depths,best_neighbour,map_id)
    if exhausted:return []
    if goal!=origin:
     if not _reserve_points(1):return []
     leg.append({"map_id":map_id,"cell":[goal.x,goal.y]})
    leg.pop_front()
    if not _reserve_points(1):return []
    leg.append({"map_id":destination[0],"cell":[destination[1],destination[2]],"portal":link.duplicate(true)})
   seen[str(destination)]=true;first_legs[str(destination)]=leg;queue.append(destination)
 return []
