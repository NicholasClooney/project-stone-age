extends RefCounted
## Production walk planner. Plans are geometry only, never arrival receipts.
const MapFile=preload("res://scripts/map_file.gd")
const Gates=preload("res://server/quest_auto_route_gates.gd")
const Passage=preload("res://scripts/passage_rules.gd")
var public_routes=preload("res://server/quest_auto_public_routes.gd").new()
var maps:Dictionary={}
var route:Array=[]
var key:=""
var grid_key:=""
var nav:AStarGrid2D
var block_key:=""
var block_cells:Dictionary={}
var entry_routes=preload("res://server/quest_auto_entry_routes.gd").new()
var entry_context:Dictionary={}
func clear()->void:
 route.clear()
 key=""
 entry_context={}
func data(b,map_id:int)->Dictionary:
 if not maps.has(map_id):maps[map_id]=MapFile.load_map(b.quest_helper.places.file(map_id))
 return maps[map_id]
func usable(b,link:Dictionary)->bool:
 if bool(link.get("disabled",false)):return false
 if link.has("gate_source") and str(link.gate_source)!="genout/wpm_10202_31_13":return false
 if int(link.get("requires_level",0))>int(b.session._profile.player.level):return false
 if (bool(link.get("requires_travel_pass",false)) or Passage.requires_permit(int(link.from_map),int(link.to_map))) and not b.session.has_travel_pass():return false
 return not b.quest_helper.places.info(int(link.to_map)).is_empty()
func blocked(b,map_id:int)->Dictionary:
 var signature:=str(map_id)+str(b.original_quests.npc_state.version)+str(hash(b.quest_catalog.npc_overrides))+str(hash(b.quest_catalog.enabled_events))
 if signature==block_key:return block_cells
 block_key=signature
 var result:Dictionary={}
 var known:Dictionary={}
 for npc in b.quest_catalog.npcs+b.quest_catalog.service_npcs:known[str(npc.id)]=true
 # Personal NPC relocation must replace, not supplement, catalogue coordinates.
 for npc in b.quest_helper.places.residents:
  if not known.has(str(npc.get("id",""))) and int(npc.map_id)==map_id:result[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 for npc in b.quest_catalog.active_npcs():
  var actual:Dictionary=b.original_quests.npc_by_id(str(npc.id))
  if not actual.is_empty() and int(actual.map_id)==map_id:result[Vector2i(int(actual.cell[0]),int(actual.cell[1]))]=true
 block_cells=result
 return result
func floor_cell(b,map_id:int,cell:Vector2i,occupied:Dictionary)->bool:
 var grid:=data(b,map_id)
 return not grid.is_empty() and cell.x>=0 and cell.y>=0 and cell.x<int(grid.width) and cell.y<int(grid.height) and int(grid.blocked[cell.y*int(grid.width)+cell.x])==0 and not occupied.has(cell)
func local_path(b,map_id:int,origin:Vector2i,goal:Vector2i,occupied:Dictionary)->Array:
 var grid:=data(b,map_id)
 if grid.is_empty():return []
 var links:Dictionary=b.quest_helper.places.links(map_id)
 var signature:=str(map_id)+str(hash(occupied))+str(hash(links))
 if grid_key!=signature:
  grid_key=signature
  nav=AStarGrid2D.new()
  nav.region=Rect2i(0,0,int(grid.width),int(grid.height))
  nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
  nav.update()
  for y in range(int(grid.height)):
   for x in range(int(grid.width)):
    var p:=Vector2i(x,y)
    nav.set_point_solid(p,int(grid.blocked[y*int(grid.width)+x])!=0 or occupied.has(p) or links.has(p))
 if not nav.region.has_point(origin) or not nav.region.has_point(goal):return []
 # An original arrival portal may share a cell with its gate NPC.
 var origin_solid:=nav.is_point_solid(origin)
 var goal_solid:=nav.is_point_solid(goal)
 if b.quest_arrival.has_arrival(b,map_id,origin) and floor_cell(b,map_id,origin,{}):nav.set_point_solid(origin,false)
 if links.has(goal) and usable(b,links[goal]) and floor_cell(b,map_id,goal,{}):nav.set_point_solid(goal,false)
 var result:Array=[]
 if not nav.is_point_solid(origin) and not nav.is_point_solid(goal):
  for point in nav.get_id_path(origin,goal):result.append({"map_id":map_id,"cell":[point.x,point.y]})
 nav.set_point_solid(origin,origin_solid)
 nav.set_point_solid(goal,goal_solid)
 return result
## Exact frozen golden44 stairs only; recomputed each call, no route cache.
## Arrival is observed, never granted. The caller still executes/validates it.
func next_portal(b,portal:Dictionary)->Dictionary:
 var sources=preload("res://server/quest_auto_golden_bui_sources.gd")
 var row:Dictionary=sources.portal_row(portal)
 if row.is_empty():return {}
 var map_id:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 if map_id!=int(row.from_map) or not b.quest_arrival.has_arrival(b,map_id,origin):return {}
 var goal:=Vector2i(int(row.from_cell[0]),int(row.from_cell[1]))
 var links:Dictionary=b.quest_helper.places.links(map_id)
 var link:Dictionary=links.get(goal,{})
 if link.is_empty() or link.has("gate_source") or bool(link.get("disabled",false)):return {}
 # Full source identity (including create line), not only a destination map.
 if not sources.same(link,row.live_link) or not usable(b,link):return {}
 var matches:=0
 for candidate in links.values():
  if sources.same(candidate,row.live_link):matches+=1
 if matches!=1:return {}
 # Do not let local_path's portal exception erase a live actor blocker.
 var occupied:=_portal_occupied(b,map_id)
 if not floor_cell(b,map_id,goal,occupied):return {}
 if origin==goal:return {"map_id":int(row.to_map),"cell":row.to_cell.duplicate(),"portal":link.duplicate(true)}
 var path:=local_path(b,map_id,origin,goal,occupied)
 if path.size()<2:return {}
 var next_point:Dictionary=path[1]
 if not b.quest_arrival.has_arrival(b,map_id,Vector2i(int(next_point.cell[0]),int(next_point.cell[1]))):return {}
 return next_point.duplicate(true)
func _portal_occupied(b,map_id:int)->Dictionary:
 var occupied:Dictionary={}
 var known:Dictionary={}
 for actor in b.quest_catalog.npcs+b.quest_catalog.service_npcs:known[str(actor.id)]=true
 for actor in b.quest_helper.places.residents:
  if not known.has(str(actor.get("id",""))) and int(actor.map_id)==map_id:occupied[Vector2i(int(actor.cell[0]),int(actor.cell[1]))]=true
 for actor in b.quest_catalog.active_npcs():
  if int(actor.map_id)==map_id:occupied[Vector2i(int(actor.cell[0]),int(actor.cell[1]))]=true
 return occupied
func map_route(b,origin:int,goal:int)->Array:
 var queue:Array=[origin]
 var parents:Dictionary={origin:-1}
 var cursor:=0
 while cursor<queue.size():
  var current:int=queue[cursor];cursor+=1
  if current==goal:
   var result:Array=[goal]
   while int(result[0])!=origin:result.push_front(parents[result[0]])
   return result
  for link in b.quest_helper.places.links(current).values():
   var next:=int(link.to_map)
   if parents.has(next) or not usable(b,link):continue
   parents[next]=current;queue.append(next)
 return []
func plan(b,npc:Dictionary)->Array:
 var map_id:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 var occupied:=blocked(b,map_id)
 var best:Array=[]
 var goals:Array=[]
 if map_id==int(npc.map_id):
  var anchor:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  for dy in range(-2,3):
   for dx in range(-2,3):
    var goal:=anchor+Vector2i(dx,dy)
    if b.quest_helper.places.links(map_id).has(goal) or not floor_cell(b,map_id,goal,occupied):continue
    goals.append(goal)
    var candidate:=local_path(b,map_id,origin,goal,occupied)
    if not candidate.is_empty() and (best.is_empty() or candidate.size()<best.size()):best=candidate
 else:
  var chain:=map_route(b,map_id,int(npc.map_id))
  if chain.size()<2:return _entry_fallback(b,npc)
  for link in b.quest_helper.places.links(map_id).values():
   if int(link.to_map)!=int(chain[1]) or not usable(b,link):continue
   var goal:=Vector2i(int(link.cell[0]),int(link.cell[1]))
   goals.append(goal)
   var candidate:=local_path(b,map_id,origin,goal,occupied)
   if candidate.is_empty():continue
   candidate.append({"map_id":int(link.to_map),"cell":link.target.duplicate(),"portal":link.duplicate(true)})
   if best.is_empty() or candidate.size()<best.size():best=candidate
 if best.is_empty():best=Gates.path(self,b,goals,occupied)
 if best.is_empty():return _entry_fallback(b,npc)
 best.pop_front()
 return best
func _entry_fallback(b,npc:Dictionary)->Array:
 var result:Array=entry_routes.find(self,b,npc)
 # Owned frozen snapshot: share internally without another world-sized copy.
 entry_context=entry_routes.last_context if not result.is_empty() else {}
 return result
func prepare_route(b,npc:Dictionary)->void:
 if not entry_context.is_empty() and not entry_routes.matches_context(b,npc,entry_context):clear()
 var signature:=str(npc.id)+str(npc.map_id)+str(npc.cell)+str(b.original_quests.npc_state.version)+str(hash(b.quest_catalog.npc_overrides))+str(hash(b.quest_catalog.enabled_events))
 if key!=signature:clear();key=signature
 # Cached geometry is never an instruction to keep walking from an old cell.
 # A battle, relocated resident or changed gate may invalidate the next point.
 if not route.is_empty() and not validate(b,route[0]):route.clear()
 if route.is_empty():route=plan(b,npc)
func next(b,npc:Dictionary)->Dictionary:
 prepare_route(b,npc)
 if route.is_empty():return {}
 return route.pop_front()
func validate(b,point:Dictionary)->bool:
 if point.has("gate"):return Gates.valid(self,b,point)
 var map_id:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 var goal:=Vector2i(int(point.cell[0]),int(point.cell[1]))
 if point.has("portal"):
  var link:Dictionary=b.quest_helper.places.links(map_id).get(origin,{})
  return not link.is_empty() and link==point.portal and usable(b,link) and int(link.to_map)==int(point.map_id) and link.target==point.cell
 if int(point.map_id)!=map_id or absi(goal.x-origin.x)+absi(goal.y-origin.y)!=1:return false
 var occupied:=blocked(b,map_id)
 if b.quest_helper.places.links(map_id).has(goal):
  var link:Dictionary=b.quest_helper.places.links(map_id)[goal]
  return usable(b,link) and floor_cell(b,map_id,goal,{})
 return floor_cell(b,map_id,goal,occupied)

func segment_key(b,npc:Dictionary)->String:
 return str(npc)+str(b.original_quests.npc_state.version)+str(hash(b.quest_catalog.npc_overrides))+str(hash(b.quest_catalog.enabled_events))+str(b.session.has_travel_pass())+str(b.session._profile.player.level)
func next_segment(b,npc:Dictionary,mode:String,max_cells:int)->Dictionary:
 prepare_route(b,npc)
 if route.is_empty():return {}
 var segment:Dictionary={"kind":"walk","points":[route[0].duplicate(true)]}
 var audit:Dictionary=public_routes.audit(self,b,route) if mode in ["B","C"] else {}
 if not audit.is_empty():
  if mode=="B":segment={"kind":"public_jump","points":[audit.points[-1].duplicate(true)],"audit_id":audit.id}
  else:
   var limit:=mini(clampi(max_cells,1,preload("res://server/quest_auto_settings_rules.gd").C_MAX_CELLS),audit.points.size())
   segment={"kind":"public_stride","points":audit.points.slice(0,limit).duplicate(true),"audit_id":audit.id}
 segment.from_map=b.automation.position_map
 segment.from_cell=[b.automation.position_cell.x,b.automation.position_cell.y]
 segment.navigation_key=segment_key(b,npc)
 if segment.kind=="public_jump":route=route.slice(audit.points.size())
 else:route=route.slice(segment.points.size())
 return segment
func validate_segment(b,npc:Dictionary,segment:Dictionary)->bool:
 if segment.get("navigation_key","")!=segment_key(b,npc):return false
 var points:Array=segment.get("remaining",segment.get("points",[]))
 if points.is_empty():return false
 if str(segment.get("kind",""))=="walk":
  var source:Array=segment.get("from_cell",[])
  return source.size()==2 and b.automation.position_map==int(segment.get("from_map",-1)) and b.automation.position_cell==Vector2i(source[0],source[1]) and segment.get("points",[]).size()==1 and points==segment.points and validate(b,points[0])
 if str(segment.get("kind",""))=="public_jump":
  var audit:Dictionary=public_routes.audit(self,b,plan(b,npc))
  if audit.is_empty() or audit.id!=segment.get("audit_id","") or audit.points[-1]!=points[0]:return false
 return public_routes.validate_audit(self,b,segment)
