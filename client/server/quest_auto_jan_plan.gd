extends RefCounted
## UNRUN. Parent explicitly orchestrates 28 -> 29 -> 28; never starts another job.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [27,28,29]:return hold("unsupported_job","强恩保27/28/29原映射。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 var end_event:={27:20,28:21,29:22}
 if Rules.flag(p,"ended",end_event[job_id]):return {"status":"done"}
 if job_id==27:
  if not Rules.flag(p,"now",20):
   if not 2486 in held:return hold("flower","原吉德领花分支待核，不反复探测ACCEPT。","jaruga/event/event20_1",23)
   return hold("request20","原吉德REQUEST消花。","jaruga/event/event20_2",17)
  if not 2487 in held:return hold("claim_token","原领2487 ACCEPT。","jaruga/event/event20_3",6)
  return hold("keyword_boss_return","三个精确口令门需d878及新hook，山贼人工；原胜后区域通过才交强恩END20，持2487不授proof。","jaruga/event/event20_4",5)
 if not Rules.flag(p,"ended",20):return hold("prerequisite","须END20，不自动启动job27。")
 if job_id==29:
  if not Rules.flag(p,"now",21):return hold("parent_request28","父链须先明确启动28并完成沙拉原REQUEST。")
  return hold("random_equipment","原随机2490..2494一件，非人选五选，GetRandItem事务待核。","jaruga/event/event20_4",16)
 if not Rules.flag(p,"now",21):
  if not 2487 in held:return hold("missing_token","缺沙拉REQUEST所需2487；不注物或重开27。")
  return hold("request21","妻子说明无持久flag；沙拉原REQUEST消2487。","jaruga/event/event20_6",26)
 if not Rules.flag(p,"ended",22):
  var result:=hold("parent_job29","父链显式切29取得装备后再回28；纯计划不会start。")
  result["required_parent_job"]=29
  return result
 if not 2488 in held:return hold("claim_letter","沙拉原ACCEPT领家书。","jaruga/event/event20_6",5)
 return hold("deliver_letter","原event20_2交信END21；event20_1前页/转交效果须核完整分支，不发明额外消费。","jaruga/event/event20_2",5)

# First flower ACCEPT only; no implicit parent-job start or service authority.
const SOURCE_PATH="res://server/quest_auto_jan_sources.json"
const SOURCE_SHA="c1b4ae1e6b03275977c371b33f3bd3ccb33982ba2c328536f124a466941e9c51"
const FLOWER_NPC="jaruga/event/event20_1@3400:59:66"
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
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
static func flower_proposal(b,job_id:int=27)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="flower":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","强恩源锁缺失或改变。")
 for locked_job in table.jobs:
  var count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==locked_job.id:
    count+=1
    if not same_source(job,locked_job):return hold("source_changed","原job27/28/29完整映射改变。")
  if count!=1:return hold("source_changed","强恩任务身份不唯一。")
 if not 20 in b.quest_catalog.enabled_events:return hold("disabled","原event20未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==FLOWER_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","凯伊完整原字段或分支顺序改变。")
 if count!=1:return hold("source_changed","凯伊人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 var locked:Dictionary={}
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  if candidate.get("source_branch_index")==2:locked=candidate
 var active:Dictionary=b.quest_catalog.active_npc(FLOWER_NPC)
 if not same_source(active,projected):return hold("source_changed","凯伊实际位置、隐藏或分支投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if locked.is_empty() or not same_source(branch,locked) or branch.get("source_branch_index")!=2 or branch.get("source_line")!=23 or branch.get("event")!=-1 or branch.get("type")!="ACCEPT" or branch.get("condition")!="ITEM!=2486" or not same_source(branch.get("actions",{}),{"GetItem":"2486"}):return hold("source_changed","当前首匹配分支不是原领花ACCEPT。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持原受保护地图合法到达资格。")
 return {"status":"step","step":{"id":"jan:flower:2486","npc_id":FLOWER_NPC,"map_id":3400,"cell":[59,66],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":FLOWER_NPC,"type":"ACCEPT","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":2,"branch_data":branch.duplicate(true),"source_line":23,"source_sha":str(table.sources["npc/jaruga/event/event20_1"].sha256),"audit_policy":"jan_flower2486_v1"}}}

# Independent first Gide REQUEST20 proposal; flower_proposal stays unchanged.
const REQUEST_SOURCE_PATH="res://server/quest_auto_jan_request_sources.json"
const REQUEST_SOURCE_SHA="5a9612aac8cac59fd0a7b8986dc5c25d300f44b5bed09033c1be330c93891e6a"
const REQUEST_NPC="jaruga/event/event20_2@3406:27:14"
static func request_source_table()->Dictionary:
 if not FileAccess.file_exists(REQUEST_SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(REQUEST_SOURCE_PATH)
 if raw.sha256_text()!=REQUEST_SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func request_proposal(b,job_id:int=27)->Dictionary:
 if job_id!=27:return hold("unsupported_job","本提案仅job27原REQUEST20，不切父链。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request20":return stage
 var table:Dictionary=request_source_table()
 if table.is_empty():return hold("source_changed","吉德REQUEST完整源锁缺失或改变。")
 for locked_job in table.jobs:
  var count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==locked_job.id:
    count+=1
    if not same_source(job,locked_job):return hold("source_changed","原job27/28/29完整映射改变。")
  if count!=1:return hold("source_changed","强恩任务身份不唯一。")
 if not 20 in b.quest_catalog.enabled_events:return hold("disabled","原event20未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","吉德本人完整原字段或分支顺序改变。")
 if count!=1:return hold("source_changed","吉德本人身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 var locked:Dictionary={}
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  if candidate.get("source_branch_index")==1:locked=candidate
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not same_source(active,projected):return hold("source_changed","吉德实际位置、隐藏或完整分支投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if locked.is_empty() or not same_source(branch,locked) or branch.get("source_branch_index")!=1 or branch.get("source_line")!=17 or branch.get("event")!=20 or branch.get("type")!="REQUEST" or branch.get("condition")!="ITEM=2486" or not same_source(branch.get("actions",{}),{"DelItem":"2486"}):return hold("source_changed","当前首匹配分支不是原吉德REQUEST20。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持当前原地图合法到达资格。")
 return {"status":"step","step":{"id":"jan:request:20","npc_id":REQUEST_NPC,"map_id":3406,"cell":[27,14],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":1,"branch_data":branch.duplicate(true),"source_line":17,"source_sha":str(table.sources["npc/jaruga/event/event20_2"].sha256),"audit_policy":"jan_request20_v1"}}}

# Independent son token ACCEPT only; existing flower/request proposals unchanged.
const TOKEN_SOURCE_PATH="res://server/quest_auto_jan_token_sources.json"
const TOKEN_SOURCE_SHA="2fc9452940c3dd4b0b0fa38cc51d90aed03e505c2eaf82da13e78f52a17da2ec"
const TOKEN_NPC="jaruga/event/event20_3@3406:28:17"
static func token_source_table()->Dictionary:
 if not FileAccess.file_exists(TOKEN_SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(TOKEN_SOURCE_PATH)
 if raw.sha256_text()!=TOKEN_SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func token_proposal(b,job_id:int=27)->Dictionary:
 if job_id!=27:return hold("unsupported_job","本提案仅job27儿子原领2487，不切父链。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="claim_token":return stage
 var table:Dictionary=token_source_table()
 if table.is_empty():return hold("source_changed","儿子领2487完整源锁缺失或改变。")
 for locked_job in table.jobs:
  var count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==locked_job.id:
    count+=1
    if not same_source(job,locked_job):return hold("source_changed","原job27/28/29完整映射改变。")
  if count!=1:return hold("source_changed","强恩任务身份不唯一。")
 if not 20 in b.quest_catalog.enabled_events:return hold("disabled","原event20未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==TOKEN_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","吉德儿子完整原字段或分支顺序改变。")
 if count!=1:return hold("source_changed","吉德儿子身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 var locked:Dictionary={}
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  if candidate.get("source_branch_index")==0:locked=candidate
 var active:Dictionary=b.quest_catalog.active_npc(TOKEN_NPC)
 if not same_source(active,projected):return hold("source_changed","儿子实际位置、隐藏或完整分支投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if locked.is_empty() or not same_source(branch,locked) or branch.get("source_branch_index")!=0 or branch.get("source_line")!=6 or branch.get("event")!=20 or branch.get("type")!="ACCEPT" or branch.get("condition")!="NOWEV=20&ITEM!=2487" or not same_source(branch.get("actions",{}),{"GetItem":"2487"}):return hold("source_changed","当前首匹配分支不是原儿子领2487 ACCEPT。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持当前原地图合法到达资格。")
 return {"status":"step","step":{"id":"jan:token:2487","npc_id":TOKEN_NPC,"map_id":3406,"cell":[28,17],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":TOKEN_NPC,"type":"ACCEPT","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":0,"branch_data":branch.duplicate(true),"source_line":6,"source_sha":str(table.sources["npc/jaruga/event/event20_3"].sha256),"audit_policy":"jan_token2487_v1"}}}
