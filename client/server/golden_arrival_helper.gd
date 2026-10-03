extends RefCounted
## Golden antelope cave; distinct from the GoldenBui quiz/janken route.
const Policy=preload("res://server/quest_arrival_policy.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
const ROOT="giiru/event/event30_1"
static func owns(npc:Dictionary)->bool:
 return int(npc.get("map_id",-1)) in range(31901,31912)
static func stage_key(backend)->Array:
 var map_id:int=backend.automation.position_map
 if not map_id in range(31901,31912):return []
 var cell:Vector2i=backend.automation.position_cell
 var nearby:Array=[]
 for npc in backend.quest_catalog.npcs:
  if int(npc.map_id)==map_id and cell-Vector2i(int(npc.cell[0]),int(npc.cell[1])) in Interaction.offsets():nearby.append(str(npc.id))
 return ["golden_antelope",map_id,nearby,backend.quest_arrival.has_arrival(backend,map_id,cell)]
static func entrance(helper)->Dictionary:
 for portal in helper.places.links(300).values():
  if int(portal.to_map)!=31901 or bool(portal.get("disabled",false)):continue
  if not helper.maps.has(300):helper.maps[300]=preload("res://scripts/map_file.gd").load_map(helper.places.file(300))
  var source:=Vector2i(int(portal.cell[0]),int(portal.cell[1]))
  for offset in Interaction.offsets():
   var point:Vector2i=source+offset
   if helper.safe(helper.maps[300],point,{},helper.places.links(300)):return {"map_id":300,"cell":[point.x,point.y],"npc_id":""}
 return {}
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if not owns(npc) or mode not in ["near","arrival"]:return {}
 if not backend.automation.position_map in range(31901,31912):return entrance(helper) if Policy.source(npc)==ROOT else {}
 var cell:Vector2i=backend.automation.position_cell
 if int(npc.map_id)!=backend.automation.position_map or not backend.quest_arrival.has_arrival(backend,int(npc.map_id),cell):return {}
 if cell-Vector2i(int(npc.cell[0]),int(npc.cell[1])) not in Interaction.offsets():return {}
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 if branch.is_empty() or not backend.quest_arrival.check_action(backend,npc,branch,"talk").is_empty():return {}
 return {"map_id":int(npc.map_id),"cell":[cell.x,cell.y],"npc_id":str(npc.get("id",""))}
static func can_visit(helper,backend,step:Dictionary)->bool:
 if not bool(step.get("current",false)):return false
 var npc:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
 if npc.is_empty():return false
 if not owns(npc):return not backend.original_quests.branch_for(npc,backend.session._profile).is_empty()
 return not destination(helper,backend,npc,"near").is_empty()
static func project(helper,backend,quest:Dictionary)->void:
 quest.completion_detail="按原入口进入采石场，取得钥匙并通过原门，沿原楼层寻找精灵；携真实之眼通过真正使者的原扣眼门，保存成功进入密室后才能领取衣服。库伊换镜与返村归还仍按原条件；补发镜2532不发金羊。助手只送公开入口，洞内须自行行走，近处合法人物仅原地定位。未开放自动执行；原装备未生效效果见各奖励标签。"
 var by_id:Dictionary={}
 for npc in backend.quest_catalog.npcs:by_id[str(npc.id)]=npc
 var public_action:bool=false
 for step in quest.steps:
  var public_npc:Dictionary=by_id.get(str(step.get("npc_id","")),{})
  if not public_npc.is_empty() and not owns(public_npc) and bool(step.current) and bool(step.actionable) and not step.get("source",{}).get("actions",{}).is_empty():public_action=true
 for step in quest.steps:
  var npc:Dictionary=by_id.get(str(step.get("npc_id","")),{})
  if npc.is_empty():
   if str(step.get("source",{}).get("type",""))=="encounter":
    step.erase("map_id");step.erase("cell");step.actionable=false
    step.label+="（须沿原入口、钥匙门与楼梯走到原遇敌区域）"
   continue
  if not owns(npc):continue
  var target:Dictionary=destination(helper,backend,npc,"near")
  var available:bool=bool(step.current) and bool(step.actionable) and not target.is_empty()
  if not backend.automation.position_map in range(31901,31912) and Policy.source(npc)==ROOT:available=quest.status!="已完成" and not public_action and not target.is_empty()
  step.current=available;step.navigation_allowed=available
  if not available:
   step.actionable=false;step.erase("map_id");step.erase("cell")
   step.label+="（须沿原路线走到人物近处）"
  elif str(target.get("npc_id","" )).is_empty():
   step.label="前往采石场公开入口，沿原楼层与钥匙门继续"
   step.map_id=target.map_id;step.cell=target.cell
