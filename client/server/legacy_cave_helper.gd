extends RefCounted
## Reviewed legacy cave geometry; this module never grants arrival evidence.
const RANGES=[[20101,20105,200],[11001,11006,100],[20401,20406,200],[20501,20508,200],[31801,31806,300]]
static func cave(map_id:int)->Array:
 for entry in RANGES:
  if map_id>=int(entry[0]) and map_id<=int(entry[1]):return entry
 return []
static func owns(npc:Dictionary)->bool:return not cave(int(npc.get("map_id",-1))).is_empty()
static func entrance(helper,npc:Dictionary)->Dictionary:
 var entry:Array=cave(int(npc.get("map_id",-1)))
 if entry.is_empty():return {}
 for portal in helper.places.links(int(entry[2])).values():
  if int(portal.to_map)==int(entry[0]) and not bool(portal.get("disabled",false)) and not portal.has("gate_source"):
   var result:Dictionary=portal.duplicate(true);result.from_map=int(entry[2]);return result
 return {}
static func walk_destination(helper,backend,npc:Dictionary)->Dictionary:
 if not owns(npc):return {}
 # Internal geometry for actual server/test walking, never a travel receipt.
 return helper.geometric_destination(backend,npc,"near")
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"]:return {}
 var current_map:int=backend.automation.position_map
 var current:Vector2i=backend.automation.position_cell
 var same_scope:bool=not cave(current_map).is_empty() and cave(current_map)==cave(int(npc.map_id))
 if same_scope and backend.quest_arrival.has_arrival(backend,current_map,current):
  if current_map!=int(npc.map_id):return {}
  var delta:=current-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  if maxi(absi(delta.x),absi(delta.y))>2:return {}
  var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
  if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return {}
  var geometric:Dictionary=walk_destination(helper,backend,npc)
  if geometric.is_empty() or not backend.quest_arrival.has_arrival(backend,current_map,Vector2i(int(geometric.cell[0]),int(geometric.cell[1]))):return {}
  return {"map_id":current_map,"cell":[current.x,current.y],"npc_id":str(npc.id)}
 var portal:Dictionary=entrance(helper,npc)
 if portal.is_empty():return {}
 var outside:Dictionary=helper.geometric_destination(backend,{"id":"","map_id":int(portal.from_map),"cell":portal.cell,"events":[]},"near")
 if not outside.is_empty():outside.npc_id="" # Arrival mode ends at the public entrance, without an unrelated NPC approach.
 return outside

# Pure original collision/portal plan. Each authority step is validated again;
# these records are never receipts and cannot grant route eligibility.
static func path_to_npc(helper,backend,npc:Dictionary)->Array:
 var bounds:Array=cave(int(npc.map_id))
 if bounds.is_empty():return []
 var allowed_maps:Array=range(int(bounds[0]),int(bounds[1])+1)
 var target:Dictionary=walk_destination(helper,backend,npc)
 if target.is_empty():return []
 var goal_map:int=int(target.map_id)
 var goal:=Vector2i(int(target.cell[0]),int(target.cell[1]))
 var places=backend.quest_helper.places
 var maps: Dictionary={}
 var blockers: Dictionary={}
 for map_id in allowed_maps:
  var data: Dictionary=preload("res://scripts/map_file.gd").load_map(places.file(int(map_id)))
  if data.is_empty():return []
  maps[int(map_id)]=data;blockers[int(map_id)]={}
 for resident in backend.quest_catalog.active_npcs():
  if blockers.has(int(resident.map_id)):blockers[int(resident.map_id)][Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 var initial_map: int=backend.automation.position_map
 var initial_cell: Vector2i=backend.automation.position_cell
 if not maps.has(initial_map) or not maps.has(goal_map):return []
 # Initial position may be a genuine just-arrived portal. The authority
 # independently checks its arrival lock; this oracle never grants one.
 var start:=Vector4i(initial_map,initial_cell.x,initial_cell.y,1)
 var queue: Array[Vector4i]=[start]
 var parents: Dictionary={start:start}
 var cursor: int=0
 var found:=Vector4i(-1,-1,-1,-1)
 while cursor<queue.size():
  var node: Vector4i=queue[cursor];cursor+=1
  var point:=Vector2i(node.y,node.z)
  if node.x==goal_map and point==goal:found=node;break
  var successors: Array[Vector4i]=[]
  var portal: Dictionary=places.links(node.x).get(point,{})
  if not portal.is_empty() and node.w==0:
   if maps.has(int(portal.to_map)) and not bool(portal.get("disabled",false)) and not portal.has("gate_source"):
    successors.append(Vector4i(int(portal.to_map),int(portal.target[0]),int(portal.target[1]),1))
  else:
   var data: Dictionary=maps[node.x]
   for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next: Vector2i=point+delta
    if next.x<0 or next.y<0 or next.x>=int(data.width) or next.y>=int(data.height) or blockers[node.x].has(next):continue
    if int(data.blocked[next.y*int(data.width)+next.x])==0:successors.append(Vector4i(node.x,next.x,next.y,0))
  for next in successors:
   if parents.has(next):continue
   parents[next]=node;queue.append(next)
 if found.x<0:return []
 var result: Array=[]
 while found!=start:
  result.push_front({"map_id":found.x,"cell":[found.y,found.z]})
  found=parents[found]
 return result

