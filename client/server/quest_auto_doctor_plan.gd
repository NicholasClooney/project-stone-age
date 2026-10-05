extends RefCounted
## UNRUN: never selects, consumes or captures a pet UID.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":"sainasu/event/event15_1","line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [6,7]:return hold("unsupported_job","仅博士job6/7。")
 var p:Dictionary=b.session._profile
 var event:=15 if job_id==6 else 16
 if Rules.flag(p,"ended",event):return {"status":"done"}
 if job_id==7 and not Rules.flag(p,"ended",15):return hold("prerequisite","第二委托须END15；不自动启动job6。")
 if not Rules.flag(p,"now",event):
  if int(p.player.level)<=(9 if job_id==6 else 15):return hold("level","未满足原REQUEST等级。")
  return hold("request","待原REQUEST及六层合法路径绑定。",26 if job_id==6 else 37)
 return hold("manual_uid","请玩家确认原合格宠UID及消耗；即使仅一只也不代选。第一委托是原随机单奖，第二GetPet95未获自动权限。",4 if job_id==6 else 15)

# Independent first REQUEST only. Pet UID selection/exchange stays manual.
const SOURCE_PATH="res://server/quest_auto_doctor_sources.json"
const SOURCE_SHA="d94995a12dc07f158107d2aed151cf39d237fee0bd1d3f4825a16cebb85495cb"
const DOCTOR="sainasu/event/event15_1"
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func same_source(a:Variant,b:Variant)->bool:
 if a is bool or b is bool:return a is bool and b is bool and a==b
 if a is int or a is float:
  return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and float(a)==floor(float(a)) and float(b)==floor(float(b)) and a==b
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same_source(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for index in range(a.size()):
   if not same_source(a[index],b[index]):return false
  return true
 return typeof(a)==typeof(b) and a==b
static func request_proposal(b,job_id:int=6)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request":return stage
 if job_id!=6:return hold("second_request_pending","本首片只准备job6/event15委托；不代启动或交宠完成job7。",37)
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","博士锁源表缺失或改变。")
 for locked_job in table.jobs:
  var count:=0
  for live_job in b.quest_catalog.jobs:
   if live_job.get("id")==locked_job.id:
    count+=1
    if not same_source(live_job,locked_job):return hold("source_changed","job6/7原映射或字段漂移。")
  if count!=1:return hold("source_changed","博士任务身份不唯一。")
 if not 15 in b.quest_catalog.enabled_events:return hold("disabled","原event15未启用。")
 var expected:Dictionary=table.npc
 var count:=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==DOCTOR:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","博士完整原分支/坐标发生变化。")
 if count!=1:return hold("source_changed","博士人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(DOCTOR)
 if not same_source(active,projected):return hold("source_changed","博士隐藏/位置/启用投影不同。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 var locked:Dictionary=expected.branches[int(table.request.branch_index)]
 if not same_source(branch,locked) or branch.get("event")!=15 or branch.get("type")!="REQUEST" or not branch.get("actions",{}).is_empty():return hold("source_changed","实际首分支不是原空动作REQUEST15。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","不能从非法保护位置发起。")
 return {"status":"step","step":{"id":"doctor:request:15","npc_id":DOCTOR,"map_id":11006,"cell":[11,11],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":DOCTOR,"type":"REQUEST","condition":str(branch.condition),"actions":{},"branch_data":branch.duplicate(true),"source_line":26,"source_sha":str(table.sources["npc/sainasu/event/event15_1"].sha256),"audit_policy":"doctor_request15_v1"}}}
