extends RefCounted
## UNRUN. No dragon loot source signature or gate executor is frozen.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=26:return hold("unsupported_job","仅龙洞job26。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",17):return {"status":"done"}
 if not Rules.flag(p,"now",17):
  if 2505 in held:return hold("inconsistent_token","原REQUEST要求无2505；不丢弃或伪造NOW17。")
  return hold("request","原一层REQUEST及合法原门路线待绑定。","jaruga/event/event17_4",13)
 if not 2505 in held:return hold("replace_token","仅原补领ACCEPT，不借金布伊权限。","jaruga/event/event17_4",3)
 for item in [2457,2458,2459]:
  if not item in held:
   var result:=hold("loot_contract_missing","龙洞完整源签名/ledger执行未冻结；2760合同不可复用。")
   result["review_needed"]={"item_id":item,"count":1,"map_id":{2457:20804,2458:20805,2459:20806}[item],"group_id":{2457:404,2458:405,2459:406}[item],"enemy_id":{2457:562,2458:560,2459:559}[item]}
   return result
 return hold("gate_and_manual_reward","三玉门原Warp需独立hook/合法区域；通过后玩家选三NPC之一，不默认衣/枪/铠。","genout/wpm_20807_11_37",1)

# First REQUEST17 only. Replacement, loot, gate and rewards remain manual.
const SOURCE_PATH="res://server/quest_auto_dragon_sources.json"
const SOURCE_SHA="a830ff15282ba01e204d84e8acbb1a7e82dc18c255bffcd00e887a75f9d61b7e"
const REQUEST_NPC="jaruga/event/event17_4@20801:13:63"
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
static func request_proposal(b,job_id:int=26)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","龙洞源锁缺失或改变。")
 var count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==26:
   count+=1
   if not same_source(job,table.job):return hold("source_changed","原job26/event17完整记录改变。")
 if count!=1:return hold("source_changed","龙洞任务身份不唯一。")
 if not 17 in b.quest_catalog.enabled_events:return hold("disabled","原event17未启用。")
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
 if locked.is_empty() or not same_source(branch,locked) or branch.get("source_branch_index")!=1 or branch.get("source_line")!=13 or branch.get("event")!=17 or branch.get("type")!="REQUEST" or branch.get("condition")!="LV>0&ITEM!=2505" or not same_source(branch.get("actions",{}),{"GetItem":"2505"}):return hold("source_changed","当前首匹配分支不是原领笛REQUEST17。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持原受保护地图合法到达资格。")
 return {"status":"step","step":{"id":"dragon:request:17","npc_id":REQUEST_NPC,"map_id":20801,"cell":[13,63],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":1,"branch_data":branch.duplicate(true),"source_line":13,"source_sha":str(table.sources["npc/jaruga/event/event17_4"].sha256),"audit_policy":"dragon_request17_v1"}}}

# Unopened next-stage proposal. No talk/choose/save or source-service permission.
const REPLACE_FLUTE_SOURCE_PATH="res://server/quest_auto_dragon_replace_flute_sources.json"
const REPLACE_FLUTE_SOURCE_SHA="a68c81fd8add929b79088cfc19dd2362cd5d9b03cd6c74c0485108361dec43ee"
const REPLACE_FLUTE_NPC="jaruga/event/event17_4@20801:13:63"
static func replace_flute_source_table()->Dictionary:
 if not FileAccess.file_exists(REPLACE_FLUTE_SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(REPLACE_FLUTE_SOURCE_PATH)
 if raw.sha256_text()!=REPLACE_FLUTE_SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func replace_flute_proposal(b,job_id:int=26)->Dictionary:
 if job_id!=26:return hold("unsupported_job","仅本任务的精确下一原事务。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="replace_token":return stage
 var table:Dictionary=replace_flute_source_table()
 if table.is_empty():return hold("source_changed","完整源锁缺失或改变。")
 for expected_job in table.jobs:
  var job_count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==expected_job.id:
    job_count+=1
    if not same_source(job,expected_job):return hold("source_changed","完整job/event记录改变。")
  if job_count!=1:return hold("source_changed","任务身份不唯一。")
 if not 17 in b.quest_catalog.enabled_events:return hold("disabled","所需原事件未启用。")
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
  if expected.id==REPLACE_FLUTE_NPC:
   active_target=active;expected_target=expected
 if active_target.is_empty():return hold("source_changed","目标原人物缺失。")
 var branch:Dictionary=b.original_quests.branch_for(active_target,b.session._profile)
 var locked:Dictionary={}
 for original in expected_target.branches:
  if (same_source(original.get("source_branch_index"),0)) and same_source(branch,original):locked=original
 if locked.is_empty():return hold("branch_unavailable","当前最高原支不是本片获审事务。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","当前原地图合法到达资格不足。")
 return {"status":"step","step":{"id":"dragon:replace_flute","npc_id":REPLACE_FLUTE_NPC,"map_id":int(active_target.map_id),"cell":active_target.cell.duplicate(),"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REPLACE_FLUTE_NPC,"type":str(branch.type),"condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":int(branch.source_branch_index),"branch_data":branch.duplicate(true),"source_line":int(branch.source_line),"source_sha":str(table.sources["npc/"+str(active_target.source_script)].sha256),"audit_policy":"dragon_replace_flute_v1"}}}

# UNRUN candidate; source identity only, never execution authority.
const POST_FLUTE_PATH="res://server/quest_auto_dragon_post_flute_sources.json"
const POST_FLUTE_SHA="5d715ebd8bf87bff8055868a0be763b09df554bb5cefa9ee5fcf88964f1de3dd"
static func post_flute_table()->Dictionary:
 var text:String=FileAccess.get_file_as_string(POST_FLUTE_PATH)
 if text.sha256_text()!=POST_FLUTE_SHA:return {}
 var parsed:Variant=JSON.parse_string(text)
 return parsed if parsed is Dictionary else {}
static func post_flute_active(b,id:String)->Dictionary:
 var table:Dictionary=post_flute_table()
 if table.is_empty():return {}
 for job in table.jobs:
  var matches:int=0
  for current in b.quest_catalog.jobs:
   if same_source(current.get("id"),job.id):
    matches+=1
    if not same_source(current,job):return {}
  if matches!=1:return {}
 for expected in table.npcs:
  var matches:int=0
  for current in b.quest_catalog.npcs:
   if current.get("id")==expected.id:
    matches+=1
    if not same_source(current,expected):return {}
  if matches!=1:return {}
  var projected:Dictionary=expected.duplicate(true)
  projected.branches=[]
  for branch in expected.branches:
   if branch.get("enabled",false) and branch.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(branch.duplicate(true))
  var active:Dictionary=b.quest_catalog.active_npc(str(expected.id))
  if not same_source(active,projected):return {}
  if expected.id==id:return active
 return {}
static func post_flute_boundary(b,job_id:int=26)->Dictionary:
 if job_id!=26:return hold("unsupported_job","仅原本任务；无跨job执行。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done":return stage
 if not 17 in b.quest_catalog.enabled_events:return hold("disabled","原事件未启用。")
 var active:Dictionary=post_flute_active(b,"jaruga/event/event17_4@20801:13:63")
 if active.is_empty():return hold("source_changed","原人物全分支或活动投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session._profile)
 var result:Dictionary=stage.duplicate(true)
 result["observed_branch"]=branch.duplicate(true)
 result["execution_available"]=false
 result["boundary"]="笛已持有后原MESSAGE不推进；三玉完整loot签名/三玉门与人选奖励未冻结；不得丢笛造补领进度。"
 return result
