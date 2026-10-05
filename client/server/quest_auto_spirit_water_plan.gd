extends RefCounted
## UNRUN tmp candidate. Three original REQUEST branches, no execution or registration.
const Rules=preload("res://server/original_quests.gd")
const SOURCE_PATH="res://server/quest_auto_spirit_water_sources.json"
const SOURCE_SHA="609acd0d1acef7ca3df8479d601c8fc76b2e293ecd8da42d18eb5649af505516"
const REQUEST_NPC="jaruga/event/hekisei@3400:63:72"
static func hold(stage:String,reason:String)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason}
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
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func select(b,job_id:int=46)->Dictionary:
 if job_id!=46:return hold("unsupported_job","水首段仅job46/event46。")
 var profile:Dictionary=b.session._profile
 if Rules.flag(profile,"ended",46):return {"status":"done"}
 if Rules.flag(profile,"now",46):return hold("manual_materials","原材料/门/守卫/奖励未接；不重发REQUEST取消。")
 if int(profile.player.level)<65:return hold("level","原LV>64，等级fixture不代表成长。")
 if not Rules.flag(profile,"ended",4):return hold("prerequisite","须真实成人END4。")
 if not (Rules.flag(profile,"ended",39) or Rules.flag(profile,"ended",40) or Rules.flag(profile,"ended",42)):return hold("prerequisite","须地/火/风任一原END，不自动执行前链。")
 return hold("request46","原水使者首委托候选。")
static func request_proposal(b,job_id:int=46)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("stage")!="request46":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","水首委托完整源锁缺失或改变。")
 var job_count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==46:
   job_count+=1
   if not same_source(job,table.job):return hold("source_changed","原job46完整映射改变。")
 if job_count!=1:return hold("source_changed","原job46身份不唯一。")
 if not 46 in b.quest_catalog.enabled_events:return hold("disabled","原event46未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","水使者完整原人物/五支顺序改变。")
 if count!=1:return hold("source_changed","水使者人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not same_source(active,projected):return hold("source_changed","实际位置/隐藏/分支投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 # Match the actual highest branch against each complete original record in source order.
 var selected:int=-1
 for index in range(3):
  if same_source(branch,expected.branches[index]):
   selected=index
   break
 if selected<0:return hold("source_changed","实际最高分支不是三条原首REQUEST之一。")
 var conditions:Array=["LV>64&ENDEV=4&ENDEV=39","LV>64&ENDEV=4&ENDEV=40","LV>64&ENDEV=4&ENDEV=42"]
 var lines:Array=[6,16,26]
 if branch.get("event")!=46 or branch.get("type")!="REQUEST" or branch.get("condition")!=conditions[selected] or not same_source(branch.get("actions",{}),{}):return hold("source_changed","原独立资格或空actions改变。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持当前原地图合法到达资格。")
 return {"status":"step","step":{"id":"spirit_water:request:46","npc_id":REQUEST_NPC,"map_id":3400,"cell":[63,72],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":selected,"branch_data":branch.duplicate(true),"source_line":lines[selected],"source_sha":str(table.sources["npc/jaruga/event/hekisei"].sha256),"audit_policy":"spirit_water_request46_v1"}}}
