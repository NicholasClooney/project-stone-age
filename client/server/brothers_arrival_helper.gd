extends RefCounted
## Navigation does not confer arrival: only original walks, gates and battles do.
const Policy=preload("res://server/quest_arrival_policy.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
static func owns(npc:Dictionary)->bool:
 var id:String=Policy.source(npc)
 return id.begins_with("giiru/event/ev28_") or id=="genout/wpm_31705_25_8" or id in ["300/sb_5b1.arg","300/sb_5b2.arg","300/sb_5b3.arg","300/sb_5b4.arg","300/sb_5b5.arg"]
static func stage_key(backend)->Array:
 var map_id:int=backend.automation.position_map
 if Policy.scope(map_id)!="brothers":return []
 var cell:Vector2i=backend.automation.position_cell
 var nearby:Array=[]
 for npc in backend.quest_catalog.npcs:
  if not owns(npc) or int(npc.map_id)!=map_id:continue
  if cell-Vector2i(int(npc.cell[0]),int(npc.cell[1])) in Interaction.offsets():nearby.append(str(npc.id))
 return ["brothers",map_id,nearby,backend.quest_arrival.has_arrival(backend,map_id,cell)]
static func entrance(helper)->Dictionary:
 for portal in helper.places.links(300).values():
  if int(portal.to_map)==31701 and not bool(portal.get("disabled",false)):
   # Remain outside the portal. The player must actually step through it.
   var cell:Array=portal.cell
   if not helper.maps.has(300):helper.maps[300]=preload("res://scripts/map_file.gd").load_map(helper.places.file(300))
   for offset in Interaction.offsets():
    var point:=Vector2i(int(cell[0]),int(cell[1]))+offset
    if helper.safe(helper.maps[300],point,{},helper.places.links(300)):
     return {"map_id":300,"cell":[point.x,point.y],"npc_id":""}
 return {}
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or not owns(npc):return {}
 if Policy.scope(backend.automation.position_map)!="brothers":
  return entrance(helper) if Policy.source(npc)=="giiru/event/ev28_0" else {}
 var cell:Vector2i=backend.automation.position_cell
 if int(npc.map_id)!=backend.automation.position_map or not backend.quest_arrival.has_arrival(backend,int(npc.map_id),cell):return {}
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if cell-target not in Interaction.offsets():return {}
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 if branch.is_empty() or not backend.quest_arrival.check_action(backend,npc,branch,"talk").is_empty():return {}
 return {"map_id":int(npc.map_id),"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
static func can_visit(helper,backend,step:Dictionary)->bool:
 if not bool(step.get("current",false)):return false
 var npc:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
 return not destination(helper,backend,npc,"near").is_empty()
static func project(helper,backend,quest:Dictionary)->void:
 quest.completion_detail="按原路完成五层答题、五张正确纸条换水晶，再领取挑战并通过原层门。五条守卫通道中，第一、四条退回洞外，第二、三条退回五楼；须经第五条原通道到领奖厅，再从五种宠物中选择。助手仅提供公开入口；洞内须自行行走，已在人物近处时可原地定位。服务器重启后须重新走原路线取得到达资格。"
 var by_id:Dictionary={}
 for npc in backend.quest_catalog.npcs:
  if owns(npc):by_id[str(npc.id)]=npc
 for step in quest.steps:
  var npc:Dictionary=by_id.get(str(step.get("npc_id","")),{})
  var target:Dictionary=destination(helper,backend,npc,"near")
  var available:bool=bool(step.current) and bool(step.actionable) and not target.is_empty()
  # Root request remains the public entrance guide even after REQUEST28.
  if Policy.scope(backend.automation.position_map)!="brothers" and Policy.source(npc)=="giiru/event/ev28_0":available=true
  step.current=available
  step.navigation_allowed=available
  if not available:
   step.actionable=false
   step.erase("map_id");step.erase("cell")
   step.label+="（须沿原路线走到人物近处）"
  elif str(target.get("npc_id","" )).is_empty():
   step.label="前往五兄弟公开入口，沿原楼梯答题与挑战"
   step.map_id=target.map_id;step.cell=target.cell
