extends RefCounted
## Audited public corridors, not a map-ID permission list. Each corridor is
## the original A path between an exact original landing and the next portal.
## Only its exact suffix may accelerate; doors themselves always remain walk.
const Extra=preload("res://server/quest_auto_public_corridors.gd")
const Arrival=preload("res://server/quest_arrival_policy.gd")
const LANES=[
 {"id":"samgir-marinas-field","map":100,"start":Vector2i(637,494),"door":Vector2i(78,614),"to_map":2000,"target":Vector2i(72,33),"source":"100warp.create:169"},
 {"id":"marinas-samgir-field","map":100,"start":Vector2i(79,614),"door":Vector2i(638,494),"to_map":1000,"target":Vector2i(50,119),"source":"100warp.create:34"},
 {"id":"samgir-kou-field","map":100,"start":Vector2i(706,488),"door":Vector2i(474,631),"to_map":1100,"target":Vector2i(67,35),"source":"100warp.create:349"},
 {"id":"kou-undersea-outside","map":1100,"start":Vector2i(67,35),"door":Vector2i(96,62),"to_map":10201,"target":Vector2i(6,4),"source":"dungeon00.create:214"},
 {"id":"tamutamu-house-outside","map":3100,"start":Vector2i(84,77),"door":Vector2i(44,55),"to_map":3110,"target":Vector2i(15,21),"source":"warp_y2.create:907"},
 {"id":"tamutamu-haro-field","map":200,"start":Vector2i(426,94),"door":Vector2i(452,162),"to_map":20101,"target":Vector2i(29,69),"source":"dungeon01.create:349"},
 {"id":"haro-tamutamu-field","map":200,"start":Vector2i(452,162),"door":Vector2i(427,94),"to_map":3100,"target":Vector2i(33,79),"source":"200warp.create:439"},
]
var cached:Dictionary={}
func lanes()->Array:return LANES+Extra.LANES
func public_cell(nav,b,map_id:int,cell:Vector2i)->bool:
 if map_id not in [100,200,1100,3100,5000] or not Arrival.scope(map_id).is_empty():return false
 if Arrival.approach_cell("transmigration_entry",map_id,cell):return false
 if b.quest_helper.places.links(map_id).has(cell):return false
 return nav.floor_cell(b,map_id,cell,nav.blocked(b,map_id))
func corridor(nav,b,lane:Dictionary)->Array:
 var links:Dictionary=b.quest_helper.places.links(int(lane.map))
 var door:Dictionary=links.get(lane.door,{})
 if door.is_empty() or not nav.usable(b,door) or door.has("gate_source") or door.has("requires_time") or str(door.get("source",""))!=lane.source or int(door.to_map)!=int(lane.to_map) or Vector2i(door.target[0],door.target[1])!=lane.target:return []
 if lane.has("link") and not Extra.source_valid(b,lane,door):return []
 var occupied:Dictionary=nav.blocked(b,int(lane.map))
 var signature:=str(lane.id)+str(hash(links))+str(hash(occupied))
 if cached.has(signature):return cached[signature]
 var cells:Array=nav.local_path(b,int(lane.map),lane.start,lane.door,occupied)
 if cells.size()<3:return []
 cells.pop_back() # The original door is never a project destination.
 # The public return from Haro is itself on the entrance portal. It must
 # first walk away normally; every candidate source after that is ordinary.
 for index in range(1,cells.size()):
  var cell:=Vector2i(cells[index].cell[0],cells[index].cell[1])
  if not public_cell(nav,b,int(lane.map),cell):return []
 cached.clear() # Only the currently planned corridor needs a geometry cache.
 cached[signature]=cells
 return cells
func audit(nav,b,route:Array)->Dictionary:
 var map_id:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 if not public_cell(nav,b,map_id,origin) or route.size()<3:return {}
 var portal:Dictionary=route[-1].get("portal",{})
 if portal.is_empty():return {}
 for lane in lanes():
  if int(lane.map)!=map_id or Vector2i(portal.cell[0],portal.cell[1])!=lane.door or int(portal.to_map)!=int(lane.to_map):continue
  if lane.has("link") and not Extra.same(portal,lane.link):continue
  if route[-2]!={"map_id":map_id,"cell":[lane.door.x,lane.door.y]}:continue
  var cells:=corridor(nav,b,lane)
  var index:=-1
  for cursor in range(cells.size()):
   if Vector2i(cells[cursor].cell[0],cells[cursor].cell[1])==origin:index=cursor;break
  if index<0 or index>=cells.size()-1:continue
  var suffix:Array=cells.slice(index+1)
  if route.size()!=suffix.size()+2:continue
  var same:=true
  for cursor in range(suffix.size()):
   if route[cursor]!=suffix[cursor]:same=false;break
  if same:return {"id":lane.id,"points":suffix,"door":portal.duplicate(true)}
 return {}
func validate_audit(nav,b,segment:Dictionary)->bool:
 var audit_id:=str(segment.get("audit_id",""))
 var points:Array=segment.get("points",[])
 var remaining:Array=segment.get("remaining",points)
 if points.is_empty() or remaining.is_empty() or remaining.size()>points.size():return false
 var skipped:=points.size()-remaining.size()
 if points.slice(skipped)!=remaining:return false
 var from:Array=segment.get("from_cell",[])
 if from.size()!=2:return false
 var expected:Vector2i=Vector2i(from[0],from[1]) if skipped==0 else Vector2i(points[skipped-1].cell[0],points[skipped-1].cell[1])
 if b.automation.position_cell!=expected or b.automation.position_map!=int(segment.get("from_map",-1)):return false
 for lane in lanes():
  if lane.id!=audit_id or int(lane.map)!=b.automation.position_map:continue
  var cells:=corridor(nav,b,lane)
  var index:=-1
  for cursor in range(cells.size()):
   if Vector2i(cells[cursor].cell[0],cells[cursor].cell[1])==expected:index=cursor;break
  if index<0 or not public_cell(nav,b,int(lane.map),expected):return false
  if str(segment.kind)=="public_jump":
   return points.size()==1 and index<cells.size()-1 and remaining[0]==cells[-1]
  if str(segment.kind)!="public_stride" or index+remaining.size()>=cells.size():return false
  return remaining==cells.slice(index+1,index+1+remaining.size())
 return false
