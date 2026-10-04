extends RefCounted
## Geometry-only proposals for the two original reusable-permit guards.
## Source: npc/genout/10200npc.create:7-29 and each wpm script:1-3.
const GATES={
 "genout/wpm_10202_22_28":{"cell":Vector2i(22,28),"target":Vector2i(21,33)},
 "genout/wpm_10202_22_32":{"cell":Vector2i(22,32),"target":Vector2i(21,27)},
}
static func matches(b,source_id:String)->bool:
 if not GATES.has(source_id) or not b.session.has_travel_pass():return false
 var row:Dictionary=GATES[source_id]
 var matches_count:=0
 for resident in b.quest_helper.places.residents:
  if str(resident.get("dialogue_source",""))!="gmsv/data/npc/"+source_id:continue
  if int(resident.get("map_id",-1))!=10202 or str(resident.get("role",""))!="gate":return false
  var cell:Array=resident.get("cell",[])
  var target:Array=resident.get("destination",[])
  if cell.size()!=2 or target.size()!=2 or Vector2i(cell[0],cell[1])!=row.cell or Vector2i(target[0],target[1])!=row.target:return false
  matches_count+=1
 return matches_count==1
static func valid(nav,b,point:Dictionary)->bool:
 if point.has("portal") or not point.get("gate") is Dictionary or point.gate.keys()!=["source_id"]:return false
 var source_id:=str(point.get("gate",{}).get("source_id",""))
 if b.automation.position_map!=10202 or point.get("map_id",-1)!=10202 or not matches(b,source_id):return false
 var row:Dictionary=GATES[source_id]
 var cell:Array=point.get("cell",[])
 if cell.size()!=2 or cell[0]!=row.target.x or cell[1]!=row.target.y:return false
 var origin:Vector2i=b.automation.position_cell
 var delta:Vector2i=origin-row.cell
 if maxi(absi(delta.x),absi(delta.y))>2 or origin==row.cell:return false
 var occupied:Dictionary=nav.blocked(b,10202)
 if not nav.floor_cell(b,10202,origin,occupied) or not nav.floor_cell(b,10202,row.target,occupied):return false
 # The planner uses reachable ordinary neighbours on the source side. This
 # check never supplies the runner's separate transaction/proof authority.
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  if not nav.local_path(b,10202,origin,row.cell+offset,occupied).is_empty():return true
 return false
static func path(nav,b,goals:Array,occupied:Dictionary)->Array:
 if b.automation.position_map!=10202 or not b.session.has_travel_pass():return []
 var origin:Vector2i=b.automation.position_cell
 var best:Array=[]
 for source_id in GATES:
  if not matches(b,source_id):continue
  var row:Dictionary=GATES[source_id]
  if not nav.floor_cell(b,10202,row.target,occupied):continue
  var reaches_goal:=false
  for goal in goals:
   if not nav.local_path(b,10202,row.target,goal,occupied).is_empty():reaches_goal=true;break
  if not reaches_goal:continue
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var candidate:Array=nav.local_path(b,10202,origin,row.cell+offset,occupied)
   if candidate.is_empty():continue
   candidate.append({"map_id":10202,"cell":[row.target.x,row.target.y],"gate":{"source_id":source_id}})
   if best.is_empty() or candidate.size()<best.size():best=candidate
 return best
