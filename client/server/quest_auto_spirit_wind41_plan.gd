extends RefCounted
## Read-only source inspection. No executable step, arrival proof, or task registration.
const Compare=preload("res://server/quest_auto_spirit_fire_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const SOURCE_PATH="res://server/quest_auto_spirit_wind41_sources.json"
const SOURCE_SHA="e4272e344cd15bf7203e08d7c4b354bf177cca45751d4329a48518b937fe578c"
const REQUEST_NPC="sainasu/event/genou_1@11215:10:10"
static func hold(stage:String,reason:String)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason}
static func source_table()->Dictionary:
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func request_proposal(b,job_id:int=38)->Dictionary:
 if job_id!=38:return hold("unsupported_job","仅原job38/event41。")
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","完整源锁改变。")
 var count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==38:
   count+=1
   if not Compare.same_source(job,table.job):return hold("source_changed","原job映射改变。")
 if count!=1:return hold("source_changed","原job身份不唯一。")
 if not 41 in b.quest_catalog.enabled_events:return hold("disabled","原事件未启用。")
 count=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not Compare.same_source(npc,table.npc):return hold("source_changed","完整原sainasu/event/genou_1@11215:10:10或分支顺序改变。")
 if count!=1:return hold("source_changed","原sainasu/event/genou_1@11215:10:10身份不唯一。")
 var expected:Dictionary=table.npc.duplicate(true)
 expected.branches=[]
 for branch in table.npc.branches:
  if branch.get("enabled",false) and branch.get("events",[]).any(func(value):return int(value) in b.quest_catalog.enabled_events):expected.branches.append(branch.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not Compare.same_source(active,expected):return hold("source_changed","当前完整投影改变。")
 var snapshot:Dictionary=b.session.snapshot()
 if Rules.flag(snapshot,"ended",41):return {"status":"done"}
 if Rules.flag(snapshot,"now",41):return hold("manual_later_stage","已经接取；不重复REQUEST或自动推进后续。")
 if not Rules.flag(snapshot,"ended",4):return hold("prerequisite","须真实成人礼；副本条件不表示取得前置。")
 var selected:Dictionary=b.original_quests.branch_for(active,snapshot)
 if not Compare.same_source(selected,table.npc.branches[3]):return hold("manual_source_priority","实际最高原分支不是首REQUEST。")
 return hold("manual_guarded_arrival","须原Boss胜利传送；本纯计划不授到达资格或执行步骤。")
