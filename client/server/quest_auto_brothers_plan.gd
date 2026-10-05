extends RefCounted
## UNRUN. Five statues use yes -> ok; no quiz indices, private answers or paper injection.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [18,19]:return hold("unsupported_job","五兄弟仅job18/19。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",28 if job_id==18 else 31):return {"status":"done"}
 if job_id==18:
  if not Rules.flag(p,"now",28):
   if int(p.player.level)<=30:return hold("level","原LV>30。")
   return hold("request28","原REQUEST待绑定。","giiru/event/ev28_0",11)
  for index in range(5):
   var paper:=2507+index*2
   if not paper in held:
    var statue:int=[5,8,12,15,19][index]
    return hold("statue_contract_missing","完整公开题/全选项及精确原yes→ok替换分支尚未接线；不读私有答案，禁止ev28_end删纸MESSAGE探测。","giiru/event/ev28_%d"%statue)
  return hold("claim_crystal","齐五正纸原ACCEPT需完整分支事务；绝不talk失败删纸分支。","giiru/event/ev28_end",11)
 if not Rules.flag(p,"ended",28):return hold("prerequisite","须END28，不自动启动18。")
 if not Rules.flag(p,"now",31):return hold("request31","原持/缺水晶两个REQUEST须核完整当前分支，不授proof。","giiru/event/ev28_end",22)
 if not 2517 in held:return hold("missing_crystal","原水晶可能logout消失；补领须精确原分支，不恢复proof。","giiru/event/ev28_end",22)
 return hold("trap_boss_manual_reward","精确六楼门/陷阱、人工Boss胜后Warp、五NPC玩家选择/GetPet全字段均待hook；不自动选第五守卫或奖励。","genout/wpm_31705_25_8",1)

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

# First original REQUEST28 only; current catalog omits branch-index metadata.
const SOURCE_PATH="res://server/quest_auto_brothers_sources.json"
const SOURCE_SHA="753f7f502e954d73170238f0743a66fec549a36a8d505d073ae03f814cd846d2"
const REQUEST_NPC="giiru/event/ev28_0"
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func request_proposal(b,job_id:int=18)->Dictionary:
 if job_id!=18:return hold("unsupported_job","本提案仅job18首REQUEST28，不启动job19。")
 var stage:Dictionary=select(b,job_id)
 if stage.get("status")=="done" or stage.get("stage")!="request28":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","五兄弟首委托完整源锁缺失或改变。")
 for locked_job in table.jobs:
  var count:int=0
  for job in b.quest_catalog.jobs:
   if job.get("id")==locked_job.id:
    count+=1
    if not same_source(job,locked_job):return hold("source_changed","原job18/19完整映射改变。")
  if count!=1:return hold("source_changed","五兄弟任务身份不唯一。")
 if not 28 in b.quest_catalog.enabled_events:return hold("disabled","原event28未启用。")
 var expected:Dictionary=table.npc
 var count:int=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not same_source(npc,expected):return hold("source_changed","原吉诺完整人物或分支顺序改变。")
 if count!=1:return hold("source_changed","吉诺原人物身份不唯一。")
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for candidate in expected.branches:
  if candidate.get("enabled",false) and candidate.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(candidate.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not same_source(active,projected):return hold("source_changed","吉诺实际位置、隐藏或分支投影改变。")
 # The file SHA and complete ordered raw record bind this to original lines11-19.
 # Do not add missing source_branch_index/source_line fields to branch_data.
 var locked:Dictionary=expected.branches[0]
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if not same_source(branch,locked) or branch.get("event")!=28 or branch.get("type")!="REQUEST" or branch.get("condition")!="LV>30" or not same_source(branch.get("actions",{}),{}):return hold("source_changed","当前最高优先匹配不是原空动作REQUEST28。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","须保持当前原地图合法到达资格。")
 return {"status":"step","step":{"id":"brothers:request:28","npc_id":REQUEST_NPC,"map_id":31701,"cell":[29,44],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":REQUEST_NPC,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_index":0,"branch_data":branch.duplicate(true),"source_line":11,"source_sha":str(table.sources["npc/giiru/event/ev28_0"].sha256),"audit_policy":"brothers_request28_v1"}}}
