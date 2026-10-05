extends RefCounted
## Pure inspection only. No step, receipt, payment, battle or route execution.
const Compare=preload("res://server/quest_auto_spirit_fire_plan.gd")
const SOURCE_PATH="res://server/quest_auto_dark_route_sources.json"
const SOURCE_SHA="1d618215f9422db5cc28f04467c8b2c9ec07f51bfb3d1fd5578765f5fa4677bc"
static func source_table()->Dictionary:
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func hold(stage:String,reason:String)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason}
const Rules=preload("res://server/original_quests.gd")
static func inspect(b)->Dictionary:
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","漆黑完整原源锁改变。")
 # Check every locked record, including denied final/side branches, before inspecting eligibility.
 for identity in table.current_npcs:
  var expected:Dictionary=table.current_npcs[identity]
  var count:int=0
  for npc in b.quest_catalog.npcs:
   if npc.get("id")==identity:
    count+=1
    if not Compare.same_source(npc,expected):return hold("source_changed","漆黑原NPC完整记录改变。")
  if count!=1:return hold("source_changed","漆黑原NPC身份不唯一。")
 var entry:Dictionary=table.current_npcs[table.entry_id]
 var projected:Dictionary=entry.duplicate(true)
 projected.branches=[]
 for branch in entry.branches:
  if branch.get("enabled",false) and branch.get("events",[]).any(func(value):return int(value) in b.quest_catalog.enabled_events):projected.branches.append(branch.duplicate(true))
 var active:Dictionary=b.quest_catalog.active_npc(str(table.entry_id))
 if active.is_empty():return hold("disabled","原入口当前不活动。")
 if not Compare.same_source(active,projected):return hold("source_changed","原入口当前投影改变。")
 var branch:Dictionary=b.original_quests.branch_for(active,b.session.snapshot())
 if not Compare.same_source(branch,entry.branches[0]):return hold("prerequisite","须原等级80及地39/火40/风42/水46四完成旗标。")
 # Current position, copied flags, or a source record never proves continuous travel or boss victory.
 return hold("manual_route_integration","仅原入口资格；连续原路、两固定战和最终门接线未验，王前停止。")
