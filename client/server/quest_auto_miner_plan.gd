extends RefCounted
## UNRUN. End at END27; never buy replacement ticket or enter floor six.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=14:return hold("unsupported_job","仅矿工job14。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",27):return {"status":"done"}
 if 2533 in held:return hold("claim_ticket","原交2533得2527/END27即停；不买补票。","giiru/event/giruev2_1",23)
 if not Rules.flag(p,"now",27):
  if int(p.player.level)<=29:return hold("level","原LV>29。")
  return hold("request","待原REQUEST；map300入口有未决A路径，不便利入矿。","giiru/event/giruev2_1",41)
 if 2535 in held:return hold("wait_boss","巴卡斯确认人工、原胜利/奖励保存后继续；不清隐藏状态重开。","300/sb_bac.arg",5)
 if 2534 in held:return hold("exchange_ore","源要求NOW27且2534，不能额外臆加持2536条件；原事务删2534/2536得2535。","giiru/event/giruev2_2",27)
 if not 2536 in held:return hold("claim_lunch","原REQUEST领2536，不买票。","giiru/event/giruev2_2",43)
 var result:=hold("loot_contract_missing","矿石完整源签名/区域和执行未冻结；不能借2760签名。")
 result["review_needed"]={"item_id":2534,"count":1,"group_id":508,"enemy_id":1043,"map_ids":[31801,31802,31803]}
 return result

# First original REQUEST only; other selector stages stay manual.
const SOURCE_PATH="res://server/quest_auto_miner_sources.json"
const SOURCE_SHA="8eeb29d72447ec8dbee6a883e4b4cc199c0e99a2adbbae88a44623f35c14e3ea"
const LEADER="giiru/event/giruev2_1@31805:19:21"
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
static func request_proposal(b,job_id:int=14)->Dictionary:
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","矿工源锁缺失或改变。")
 var job_count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==14:
   job_count+=1
   if not same_source(job,table.job):return hold("source_changed","原job14/event27完整记录改变。")
 if job_count!=1:return hold("source_changed","矿工任务身份不唯一。")
 if not 27 in b.quest_catalog.enabled_events:return hold("disabled","原event27未启用。")
 var leader:Dictionary={}
 var locked_branch:Dictionary={}
 for expected in table.npcs:
  var count:int=0
  for npc in b.quest_catalog.npcs:
   if npc.get("id")==expected.id:
    count+=1
    if not same_source(npc,expected):return hold("source_changed","矿工人物完整原字段或分支顺序改变。")
  if count!=1:return hold("source_changed","矿工人物身份不唯一。")
  var projected:Dictionary=expected.duplicate(true)
  projected.branches=[]
  for candidate in expected.branches:
   if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
  var active:Dictionary=b.quest_catalog.active_npc(str(expected.id))
  if not same_source(active,projected):return hold("source_changed","矿工实际位置、隐藏或分支投影改变。")
  if expected.id==LEADER:
   leader=active
   for branch in expected.branches:
    if branch.get("source_branch_index")==3:locked_branch=branch
 if leader.is_empty() or locked_branch.is_empty():return hold("source_changed","精确原委托身份缺失。")
 var branch:Dictionary=b.original_quests.branch_for(leader,b.session.snapshot())
 if not same_source(branch,locked_branch) or branch.get("source_line")!=41 or branch.get("source_branch_index")!=3 or branch.get("event")!=27 or branch.get("type")!="REQUEST" or branch.get("condition")!="LV>29&ENDEV!=27" or not branch.get("actions",{}).is_empty():return hold("source_changed","当前首匹配分支不是原空动作REQUEST27。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持原受保护地图合法到达资格。")
 return {"status":"step","step":{"id":"miner:request:27","npc_id":LEADER,"map_id":31805,"cell":[19,21],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":LEADER,"type":"REQUEST","condition":str(branch.condition),"actions":{},"branch_index":3,"branch_data":branch.duplicate(true),"source_line":41,"source_sha":str(table.sources["npc/giiru/event/giruev2_1"].sha256),"audit_policy":"miner_request27_v1"}}}

# Unopened next-stage proposal. No talk/choose/save or source-service permission.
const CLAIM_MINING_PASS_SOURCE_PATH="res://server/quest_auto_miner_claim_mining_pass_sources.json"
const CLAIM_MINING_PASS_SOURCE_SHA="9145c85917f2ec312089479a2b5af89b8782665c5f5477a238d23adcd0e78096"
const CLAIM_MINING_PASS_NPC="giiru/event/giruev2_2@31805:33:23"
static func claim_mining_pass_source_table()->Dictionary:
 if not FileAccess.file_exists(CLAIM_MINING_PASS_SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(CLAIM_MINING_PASS_SOURCE_PATH)
 if raw.sha256_text()!=CLAIM_MINING_PASS_SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func claim_mining_pass_proposal(b,job_id:int=14)->Dictionary:
 if job_id!=14:return hold("unsupported_job","仅本任务的精确下一原事务。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="claim_lunch":return stage
 var table:Dictionary=claim_mining_pass_source_table()
 if table.is_empty():return hold("source_changed","完整源锁缺失或改变。")
 for expected_job in table.jobs:
  var job_count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==expected_job.id:
    job_count+=1
    if not same_source(job,expected_job):return hold("source_changed","完整job/event记录改变。")
  if job_count!=1:return hold("source_changed","任务身份不唯一。")
 if not 27 in b.quest_catalog.enabled_events:return hold("disabled","所需原事件未启用。")
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
  if expected.id==CLAIM_MINING_PASS_NPC:
   active_target=active;expected_target=expected
 if active_target.is_empty():return hold("source_changed","目标原人物缺失。")
 var branch:Dictionary=b.original_quests.branch_for(active_target,b.session._profile)
 var locked:Dictionary={}
 for original in expected_target.branches:
  if (same_source(original.get("source_branch_index"),5)) and same_source(branch,original):locked=original
 if locked.is_empty():return hold("branch_unavailable","当前最高原支不是本片获审事务。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","当前原地图合法到达资格不足。")
 return {"status":"step","step":{"id":"miner:claim_mining_pass","npc_id":CLAIM_MINING_PASS_NPC,"map_id":int(active_target.map_id),"cell":active_target.cell.duplicate(),"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":CLAIM_MINING_PASS_NPC,"type":str(branch.type),"condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":int(branch.source_branch_index),"branch_data":branch.duplicate(true),"source_line":int(branch.source_line),"source_sha":str(table.sources["npc/"+str(active_target.source_script)].sha256),"audit_policy":"miner_claim_mining_pass_v1"}}}
