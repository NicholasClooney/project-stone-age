extends SceneTree
## UNRUN tmp pure candidate. No real adult/element completion, growth, route or REQUEST.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_spirit_water_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(level:int,ended:Array,now:Array=[],job:int=46)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 for event in [4,39,40,42,46]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(65,[4,39])
func run()->void:
 b=Backend.new()
 b.automation.position_changed(3400,Vector2i(60,41),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 print("water pure authority=",position," profile.location=",before.get("location",{}))
 if not check(Plan.same_source(b.quest_helper.places.info(3400).spawn,[60,41]),"fixed original public manifest spawn"):finish();return
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public fixture grants no dungeon proof"):finish();return
 if not check(Plan.request_proposal(b).get("stage")=="level" and copied_case(64,[4,39]).get("stage")=="level","real level1/copy64 cannot bypass LV>64"):finish();return
 if not check(copied_case(65,[39]).get("stage")=="prerequisite" and copied_case(65,[4]).get("stage")=="prerequisite","END4 and at least one element both required"):finish();return
 if not check(copied_case(65,[4,39],[],42).get("stage")=="unsupported_job","no wind event/job or parent implicit selection"):finish();return
 var table:Dictionary=Plan.source_table()
 if not check(not table.is_empty() and table.npc.branches.size()==5,"complete original five-branch lock"):finish();return
 var elements:Array=[39,40,42]
 var conditions:Array=["LV>64&ENDEV=4&ENDEV=39","LV>64&ENDEV=4&ENDEV=40","LV>64&ENDEV=4&ENDEV=42"]
 var lines:Array=[6,16,26]
 for index in range(3):
  var result:Dictionary=copied_case(65,[4,elements[index]])
  if not check(result.get("status")=="step","each original element alone permits pure proposal"):finish();return
  var step:Dictionary=result.step
  var source:Dictionary=step.source
  if not check(step.id=="spirit_water:request:46" and step.npc_id==Plan.REQUEST_NPC and step.map_id==3400 and step.cell==[63,72],"exact water messenger target"):finish();return
  if not check(source.type=="REQUEST" and source.condition==conditions[index] and source.actions.is_empty() and source.branch_index==index and source.source_line==lines[index],"distinct original condition and line, no merged OR actions"):finish();return
  if not check(Plan.same_source(source.branch_data,table.npc.branches[index]) and step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,46,false),"complete branch identity, ordinary proposal shape only"):finish();return
 for row in [{"ended":[4,39,40],"index":0},{"ended":[4,39,42],"index":0},{"ended":[4,40,42],"index":1},{"ended":[4,39,40,42],"index":0}]:
  var multiple:Dictionary=copied_case(65,row.ended)
  if not check(multiple.get("status")=="step" and multiple.step.source.branch_index==row.index,"multiple qualifications preserve original earth/fire/wind priority"):finish();return
 var running:Dictionary=copied_case(65,[4,39],[46])
 if not check(running.get("status")=="manual" and running.get("stage")=="manual_materials" and not running.has("step"),"NOW46 stops before materials gate and request cancellation"):finish();return
 if not check(copied_case(1,[46],[46]).get("status")=="done","END46 done even with stale NOW and no current prerequisites"):finish();return
 if not check(table.npc.branches[3].condition=="LV>64&ENDEV=46" and table.npc.branches[4].condition=="LV>0","lower message branches are not dropped"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[4].actions.GetItem="2760"
   var mutation:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","unselected MESSAGE cannot gain loot action"):finish();return
   npc.branches.reverse()
   mutation=positive();npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","source order cannot change first match"):finish();return
   npc.branches[0].condition="LV>63&ENDEV=4&ENDEV=39"
   mutation=positive();npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","original level threshold locked"):finish();return
   npc.branches[2].actions.GetItem="2760"
   mutation=positive();npc.branches=saved
   if not check(mutation.get("stage")=="source_changed","unmatched REQUEST raw mutation still rejected"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(46)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event46 must be active"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden NPC cannot propose"):finish();return
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"map_id":3400,"cell":[63,71]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","relocated NPC rejected"):finish();return
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append(table.npc.duplicate(true))
 var duplicate:Dictionary=positive()
 b.quest_catalog.npcs=npcs
 if not check(duplicate.get("stage")=="source_changed","duplicate identity rejected"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==46:job.event=42
 var mapping:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(mapping.get("stage")=="source_changed","job/event exact mapping required"):finish();return
 var alias:Dictionary=positive()
 alias.step.source.branch_data.actions.GetItem="2760"
 alias.step.cell[0]=0
 var restored:Dictionary=positive()
 if not check(restored.get("status")=="step" and restored.step.source.branch_data.actions.is_empty() and restored.step.cell==[63,72],"returned deep data cannot poison future proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"actual profile location authority NPC version unchanged"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending==pending and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no actual request items save proof battle or parent-chain execution"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_spirit_water_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
