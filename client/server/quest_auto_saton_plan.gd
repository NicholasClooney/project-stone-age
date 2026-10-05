extends RefCounted
## Reviewed stage selector; independent REQUEST proposal below remains UNRUN.
const Rules=preload("res://server/original_quests.gd")
const SOURCE="sainasu/event/event13_1"
static func hold(stage:String,reason:String,source_key:String=SOURCE,line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":source_key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=10:return hold("unsupported_job","仅萨顿job10。")
 var p:Dictionary=b.session._profile
 if Rules.flag(p,"ended",13):return {"status":"done"}
 if not Rules.flag(p,"now",13):
  if int(p.player.level)<=15:return hold("level","原委托要求LV>15。")
  return hold("request","待绑定原REQUEST及合法路线；不得调用CLEAN13。",SOURCE,28)
 var held:Array=p.original_items
 if 2428 in held and 2429 in held and 2430 in held:
  return hold("return_treasures","待精确ACCEPT事务；消三宝及足迹，原END13，项目另补END14。",SOURCE,9)
 if not 2431 in held:return hold("replace_footprint","待精确MESSAGE补足迹合同，不泛放MESSAGE。",SOURCE,20)
 for index in range(3):
  if not (2428+index) in held:
   return hold("wait_boss","王确认由玩家操作；缺宝不代表王可重开，须原隐藏/到达校验。","100/sb_nusu%d.arg"%(index+1))
 return hold("unknown","源状态无法唯一确定。")

# Independent first transaction proposal; select() remains a manual stage API.
# No registry, admission, source-service or automatic Boss confirmation.
const SOURCE_PATH="res://server/quest_auto_saton_sources.json"
const SOURCE_SHA="361145184044d43a6bdbb35057dc4699a6e30b9386e6fcc1950286e00714ee9b"
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var value:Variant=JSON.parse_string(raw)
 return value if value is Dictionary else {}
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
static func request_proposal(b)->Dictionary:
 var stage:Dictionary=select(b,10)
 if stage.get("status")=="done" or stage.get("stage")!="request":return stage
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","萨顿完整锁源缺失或改变。")
 if not 13 in b.quest_catalog.enabled_events:return hold("disabled","原事件13未启用。")
 if not b.quest_catalog.jobs.any(func(job):return job.get("id")==10 and job.get("event")==13):return hold("source_changed","job10/event13映射不符。")
 var expected:Dictionary={}
 for locked in table.npcs:
  var count:=0
  for actual in b.quest_catalog.npcs:
   if actual.get("id")==locked.id:
    count+=1
    if not same_source(actual,locked):return hold("source_changed","原完整分支或人物字段漂移。")
  if count!=1:return hold("source_changed","原人物身份不唯一。")
  if locked.id==table.request.npc_id:expected=locked
 var active:Dictionary=b.quest_catalog.active_npc(table.request.npc_id)
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for branch in expected.get("branches",[]):
  if branch.get("enabled",false) and branch.get("events",[]).any(func(event):return int(event) in b.quest_catalog.enabled_events):projected.branches.append(branch.duplicate(true))
 if not same_source(active,projected):return hold("source_changed","当前人物位置/隐藏/启用分支与原源不同。")
 var profile:Dictionary=b.session.snapshot()
 var branch:Dictionary=b.original_quests.branch_for(active,profile)
 var locked:Dictionary=expected.branches[int(table.request.branch_index)]
 if not same_source(branch,locked) or branch.get("source_branch_index",-1)!=2 or branch.get("type")!="REQUEST":return hold("source_changed","首匹配原分支不是锁定委托。")
 if Rules.flag(profile,"now",13):return hold("cancel_forbidden","不确认原REQUEST取消委托。")
 if Rules.Session.bag_slots(profile)+1>15:return hold("bag_full","原足迹需一个道具栏位。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return hold("arrival_required","不从非法保护位置发起原路提案。")
 return {"status":"step","step":{"id":"saton:request","npc_id":str(active.id),"map_id":int(active.map_id),"cell":active.cell.duplicate(),"current":true,"done":false,"actionable":true,"label":"向老人萨顿领取原盗贼足迹","auto_choices":["yes","ok"],"source":{"npc_id":str(active.id),"branch":2,"type":"REQUEST","condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_data":branch.duplicate(true),"source_branch_index":2,"source_line":28,"source_sha":str(table.sources[SOURCE].sha256),"audit_policy":"saton_request_v1"}}}
