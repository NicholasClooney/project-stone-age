extends RefCounted
## UNRUN tmp candidate. Exact ordinary first REQUEST only; no registry or execution.
const Rules=preload("res://server/original_quests.gd")
const SOURCE_PATH="res://server/quest_auto_spirit_fire_sources.json"
const SOURCE_SHA="31621c6888c7cf2e0404dfbf3e917c8ec119b1353df9dfe61c94a7f7edede2b2"
const REQUEST_NPC="giiru/event/sink/sink07@5106:26:15"
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
static func select(b,job_id:int=37)->Dictionary:
 if job_id!=37:return hold("unsupported_job","火首段仅job37/event40。")
 var profile:Dictionary=b.session._profile
 if Rules.flag(profile,"ended",40):return {"status":"done"}
 if Rules.flag(profile,"now",40):return hold("manual_feather_jug_keyword","已委托，羽毛/壶/口令及Boss奖励仍人工；不重发REQUEST取消。")
 if not Rules.flag(profile,"ended",4):return hold("prerequisite","须原成人END4；不自动取得前置。")
 return hold("request40","原真红首委托候选。")
static func request_proposal(b,job_id:int=37)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("stage")!="request40":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","火首委托完整源锁缺失或改变。")
 var job_count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==37:
   job_count+=1
   if not same_source(job,table.job):return hold("source_changed","原job37完整映射改变。")
 if job_count!=1:return hold("source_changed","原job37身份不唯一。")
 if not 40 in b.quest_catalog.enabled_events:return hold("disabled","原event40未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","真红完整原人物/三支顺序改变。")
 if count!=1:return hold("source_changed","真红人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not same_source(active,projected):return hold("source_changed","实际位置/隐藏/分支投影改变。")
 var locked:Dictionary=expected.branches[2]
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if not same_source(branch,locked) or branch.get("event")!=40 or branch.get("type")!="REQUEST" or branch.get("condition")!="ENDEV=4" or not same_source(branch.get("actions",{}),{}):return hold("source_changed","最高匹配不是原空动作REQUEST40。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持当前原地图合法到达资格。")
 return {"status":"step","step":{"id":"spirit_fire:request:40","npc_id":REQUEST_NPC,"map_id":5106,"cell":[26,15],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":2,"branch_data":branch.duplicate(true),"source_line":18,"source_sha":str(table.sources["npc/giiru/event/sink/sink07"].sha256),"audit_policy":"spirit_fire_request40_v1"}}}
