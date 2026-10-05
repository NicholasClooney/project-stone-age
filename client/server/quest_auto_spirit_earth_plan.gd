extends RefCounted
## Read-only source inspection. No executable step, arrival proof, or task registration.
const Compare=preload("res://server/quest_auto_spirit_fire_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const SOURCE_PATH="res://server/quest_auto_spirit_earth_sources.json"
const SOURCE_SHA="0f139d0bc12f9796dd8c42133ff81afd4ce24788947e6ae8490fb21b024a05f7"
const REQUEST_NPC="jaruga/event/ruri02@3413:16:18"
static func hold(stage:String,reason:String)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason}
static func source_table()->Dictionary:
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func request_proposal(b,job_id:int=36)->Dictionary:
 if job_id!=36:return hold("unsupported_job","仅原job36/event39。")
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","完整源锁改变。")
 var count:int=0
 for job in b.quest_catalog.jobs:
  if job.get("id")==36:
   count+=1
   if not Compare.same_source(job,table.job):return hold("source_changed","原job映射改变。")
 if count!=1:return hold("source_changed","原job身份不唯一。")
 if not 39 in b.quest_catalog.enabled_events:return hold("disabled","原事件未启用。")
 count=0
 for npc in b.quest_catalog.npcs:
  if npc.get("id")==REQUEST_NPC:
   count+=1
   if not Compare.same_source(npc,table.npc):return hold("source_changed","完整原jaruga/event/ruri02@3413:16:18或分支顺序改变。")
 if count!=1:return hold("source_changed","原jaruga/event/ruri02@3413:16:18身份不唯一。")
 var expected:Dictionary=table.npc.duplicate(true)
 expected.branches=[]
 for branch in table.npc.branches:
  if branch.get("enabled",false) and branch.get("events",[]).any(func(value):return int(value) in b.quest_catalog.enabled_events):expected.branches.append(branch.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(REQUEST_NPC)
 if not Compare.same_source(active,expected):return hold("source_changed","当前完整投影改变。")
 var snapshot:Dictionary=b.session.snapshot()
 if Rules.flag(snapshot,"ended",39):return {"status":"done"}
 if Rules.flag(snapshot,"now",39):return hold("manual_later_stage","已经接取；不重复REQUEST或自动推进后续。")
 if not Rules.flag(snapshot,"ended",4):return hold("prerequisite","须真实成人礼；副本条件不表示取得前置。")
 var selected:Dictionary=b.original_quests.branch_for(active,snapshot)
 if not Compare.same_source(selected,table.npc.branches[1]):return hold("manual_source_priority","实际最高原分支不是首REQUEST。")
 return hold("manual_disabled_entrance","原两入口禁用；未证明合法原路，不发可执行步骤。")
