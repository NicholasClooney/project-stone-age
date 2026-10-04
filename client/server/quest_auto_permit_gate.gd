extends RefCounted
## Exactly the two original ITEM=2422 / MONEY=-1 undersea residents.
## Geometry validation only; backend owns the atomic save and script movement.
const Motion=preload("res://server/quest_auto_motion.gd")
const MapFile=preload("res://scripts/map_file.gd")
const GATES={
 "genout/wpm_10202_22_28":{"npc":[22,28],"target":[21,33],"anchor":[21,28]},
 "genout/wpm_10202_22_32":{"npc":[22,32],"target":[21,27],"anchor":[21,32]}
}
static func point_error(point:Dictionary)->String:
 var gate=point.get("gate")
 if not gate is Dictionary or gate.size()!=1 or not gate.get("source_id") is String or not GATES.has(gate.source_id):return "未审核的通行证守卫。"
 if point.has("portal"):return "原守卫不能伪装为普通出口。"
 var spec:Dictionary=GATES[gate.source_id]
 if point.has("map_id") and not Motion.same_integer(point.map_id,10202):return "原守卫目的地图不匹配。"
 if point.has("cell") and Motion.cell(point.cell)!=spec.target:return "原守卫目的位置不匹配。"
 return ""
static func occupied(b)->Dictionary:
 b.original_quests.refresh_npc_state()
 var known:Dictionary={}
 for npc in b.quest_catalog.npcs+b.quest_catalog.service_npcs:known[str(npc.id)]=true
 var cells:Dictionary={}
 for resident in b.quest_helper.places.residents:
  if int(resident.get("map_id",-1))==10202 and not known.has(str(resident.get("id",""))):cells[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for npc in b.quest_catalog.active_npcs():
  var actual:Dictionary=b.original_quests.npc_by_id(str(npc.id))
  if not actual.is_empty() and int(actual.map_id)==10202:cells[Vector2i(int(actual.cell[0]),int(actual.cell[1]))]=true
 return cells
static func floor_cell(data:Dictionary,cell:Vector2i,blocked:Dictionary,links:Dictionary)->bool:
 return cell.x>=0 and cell.y>=0 and cell.x<int(data.width) and cell.y<int(data.height) and int(data.blocked[cell.y*int(data.width)+cell.x])==0 and not blocked.has(cell) and not links.has(cell)
static func same_side(data:Dictionary,origin:Vector2i,anchor:Vector2i,blocked:Dictionary,links:Dictionary)->bool:
 if not floor_cell(data,anchor,blocked,links):return false
 var seen:Dictionary={origin:true}
 var queue:Array[Vector2i]=[origin]
 var index:=0
 while index<queue.size():
  var current:Vector2i=queue[index];index+=1
  if current==anchor:return true
  for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next:Vector2i=current+delta
   if not seen.has(next) and floor_cell(data,next,blocked,links):seen[next]=true;queue.append(next)
 return false
static func validate(b,source_id:String)->Dictionary:
 if not GATES.has(source_id):return {"ok":false,"reason":"未审核的通行证守卫。"}
 var spec:Dictionary=GATES[source_id]
 var matches:Array=[]
 for resident in b.quest_helper.places.residents:
  if str(resident.get("dialogue_source",""))=="gmsv/data/npc/"+source_id or (resident.get("map_id",-1)==10202 and Motion.cell(resident.get("cell"))==spec.npc and str(resident.get("role",""))=="gate"):matches.append(resident)
 if matches.size()!=1:return {"ok":false,"reason":"原守卫资料缺失或重复。"}
 var resident:Dictionary=matches[0]
 if resident.get("map_id",-1)!=10202 or Motion.cell(resident.get("cell"))!=spec.npc or Motion.cell(resident.get("destination"))!=spec.target or str(resident.get("role",""))!="gate" or str(resident.get("dialogue_source",""))!="gmsv/data/npc/"+source_id:return {"ok":false,"reason":"原守卫资料已经改变。"}
 var origin:Vector2i=b.automation.position_cell
 var npc:=Vector2i(int(spec.npc[0]),int(spec.npc[1]))
 if b.automation.position_map!=10202 or maxi(absi(origin.x-npc.x),absi(origin.y-npc.y))>2:return {"ok":false,"reason":"请先沿原路接近持证守卫。"}
 if not b.session.has_travel_pass():return {"ok":false,"reason":"穿过海底关卡需要通行证；自动任务不会购买。"}
 var data:Dictionary=MapFile.load_map(b.quest_helper.places.file(10202))
 if data.is_empty():return {"ok":false,"reason":"原海底通路地图不可用。"}
 var blocked:Dictionary=occupied(b)
 var links:Dictionary=b.quest_helper.places.links(10202)
 var target:=Vector2i(int(spec.target[0]),int(spec.target[1]))
 if not floor_cell(data,origin,blocked,links) or not floor_cell(data,target,blocked,links):return {"ok":false,"reason":"原守卫起点或目的位置已被阻挡。"}
 if not same_side(data,origin,Vector2i(int(spec.anchor[0]),int(spec.anchor[1])),blocked,links):return {"ok":false,"reason":"当前位置不在原守卫可接近的一侧。"}
 return {"ok":true,"target":{"map_id":10202,"cell":spec.target.duplicate()}}
