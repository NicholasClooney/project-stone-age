extends RefCounted
## UNRUN. Static answers d878 exist; keyword/Warp/Charm execution is NOT implied.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=8:return hold("unsupported_job","仅梦德job8。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",9):return {"status":"done"}
 if Rules.flag(p,"ended",10) and Rules.flag(p,"ended",11) and Rules.flag(p,"ended",12):
  return hold("final_reward","原最终ACCEPT待绑定；不重复领石。","sainasu/event/event09",3)
 if not Rules.flag(p,"now",9):
  if int(p.player.level)<=29 or not Rules.flag(p,"ended",4):return hold("prerequisite","原LV>29且END4。")
  return hold("request9","待原REQUEST及路线。","sainasu/event/event09",14)
 if not Rules.flag(p,"ended",11) and not Rules.flag(p,"now",11):
  return hold("request11","卡坦原REQUEST，按当前NOW10精确匹配分支。","sainasu/event/event11",29 if Rules.flag(p,"now",10) else 41)
 if not Rules.flag(p,"ended",10) and not Rules.flag(p,"now",10):
  return hold("request10","霍特尔原REQUEST，按当前NOW11精确匹配分支。","sainasu/event/event10",28 if Rules.flag(p,"now",11) else 41)
 if 2420 in held and Rules.flag(p,"now",11) and not Rules.flag(p,"ended",11):
  return hold("return_stone_charm","原Charm1不能省略，待核心精确事务合同。","sainasu/event/event11",4 if Rules.flag(p,"ended",10) else 16)
 if 2419 in held and Rules.flag(p,"ended",11) and Rules.flag(p,"now",10) and not Rules.flag(p,"ended",10):
  return hold("return_stone10","交2419原ACCEPT，原END10/12。","sainasu/event/event10",4)
 if 2419 in held or 2420 in held or Rules.flag(p,"ended",10) or Rules.flag(p,"ended",11):
  return hold("partial_state","部分石/事件组合须精确源分支核对；不清旗补物。")
 if b.automation.position_map==11107:
  return hold("boss_and_stones","须原合法区域/人工悟唐胜利保存后才领双石；当前位置不证明胜利，不进入风41/42。","sainasu/event/event12",4)
 return hold("keyword_route","复用d878公开口令resolver；四门执行/原Warp receipt未冻结，王确认人工。","genout/wpm_100_443_127",1)

# First REQUEST9 only. Keyword, Charm, Boss and rewards remain manual.
const SOURCE_PATH="res://server/quest_auto_munde_sources.json"
const SOURCE_SHA="624b8d8fd52db51a66a2ece7388172f38f15fda3382f2436926319dbdc0d21b5"
const REQUEST_NPC="sainasu/event/event09@1200:97:75"
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
static func request_proposal(b,job_id:int=8)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request9":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","梦德源锁缺失或改变。")
 var count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==8:
   count+=1
   if not same_source(job,table.job):return hold("source_changed","原job8/event9完整记录改变。")
 if count!=1:return hold("source_changed","梦德任务身份不唯一。")
 if not 9 in b.quest_catalog.enabled_events:return hold("disabled","原event9未启用。")
 var expected:Dictionary=table.npc
 count=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","首委托人物完整原字段或分支顺序改变。")
 if count!=1:return hold("source_changed","首委托人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 var locked:Dictionary={}
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  if candidate.get("source_branch_index")==1:locked=candidate
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not same_source(active,projected):return hold("source_changed","首委托实际位置、隐藏或分支投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if locked.is_empty() or not same_source(branch,locked) or branch.get("source_branch_index")!=1 or branch.get("source_line")!=14 or branch.get("event")!=9 or branch.get("type")!="REQUEST" or branch.get("condition")!="LV>29&ENDEV=4" or not branch.get("actions",{}).is_empty():return hold("source_changed","当前首匹配分支不是原空动作REQUEST9。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持原受保护地图合法到达资格。")
 return {"status":"step","step":{"id":"munde:request:9","npc_id":REQUEST_NPC,"map_id":1200,"cell":[97,75],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":{},"branch_index":1,"branch_data":branch.duplicate(true),"source_line":14,"source_sha":str(table.sources["npc/sainasu/event/event09"].sha256),"audit_policy":"munde_request9_v1"}}}

# Unopened next-stage proposal. No talk/choose/save or source-service permission.
const REQUEST11_SOURCE_PATH="res://server/quest_auto_munde_request11_sources.json"
const REQUEST11_SOURCE_SHA="6536357117ff4d08b58bf8a4bab67ce01b37b21797da06eebe806bd8e2d591de"
const REQUEST11_NPC="sainasu/event/event11@1400:71:76"
static func request11_source_table()->Dictionary:
 if not FileAccess.file_exists(REQUEST11_SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(REQUEST11_SOURCE_PATH)
 if raw.sha256_text()!=REQUEST11_SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func request11_proposal(b,job_id:int=8)->Dictionary:
 if job_id!=8:return hold("unsupported_job","仅本任务的精确下一原事务。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request11":return stage
 var table:Dictionary=request11_source_table()
 if table.is_empty():return hold("source_changed","完整源锁缺失或改变。")
 for expected_job in table.jobs:
  var job_count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==expected_job.id:
    job_count+=1
    if not same_source(job,expected_job):return hold("source_changed","完整job/event记录改变。")
  if job_count!=1:return hold("source_changed","任务身份不唯一。")
 if not 11 in b.quest_catalog.enabled_events:return hold("disabled","所需原事件未启用。")
 var active_target:Dictionary={}
 var expected_target:Dictionary={}
 for expected in table.npcs:
  var count:int=0
  for npc in b.quest_catalog.npcs:
   if npc.get("id")==expected.id:
    count+=1
    if not same_source(npc,expected):return hold("source_changed","完整原人物字段/原分支顺序改变。")
  if count!=1:return hold("source_changed","原人物身份不唯一。")
  var projected:Dictionary=expected.duplicate(true)
  projected.branches=[]
  for candidate in expected.branches:
   if candidate.get("enabled",false) and candidate.get("events",[]).any(func(value):return int(value) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  var active:Dictionary=b.quest_catalog.active_npc(str(expected.id))
  if not same_source(active,projected):return hold("source_changed","原位置/隐藏/完整活动投影改变。")
  if expected.id==REQUEST11_NPC:
   active_target=active;expected_target=expected
 if active_target.is_empty():return hold("source_changed","目标原人物缺失。")
 var branch:Dictionary=b.original_quests.branch_for(active_target,b.session._profile)
 var locked:Dictionary={}
 for original in expected_target.branches:
  if (same_source(original.get("source_branch_index"),2) or same_source(original.get("source_branch_index"),3)) and same_source(branch,original):locked=original
 if locked.is_empty():return hold("branch_unavailable","当前最高原支不是本片获审事务。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","当前原地图合法到达资格不足。")
 return {"status":"step","step":{"id":"munde:request11","npc_id":REQUEST11_NPC,"map_id":int(active_target.map_id),"cell":active_target.cell.duplicate(),"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST11_NPC,"type":str(branch.type),"condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":int(branch.source_branch_index),"branch_data":branch.duplicate(true),"source_line":int(branch.source_line),"source_sha":str(table.sources["npc/"+str(active_target.source_script)].sha256),"audit_policy":"munde_request11_v1"}}}
