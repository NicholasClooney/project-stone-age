extends SceneTree
## UNRUN tmp pure candidate. END4/items/flags below are eligibility copies, not real prerequisites.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_spirit_fire_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(job:int,ended:Array,now:Array,items:Array=[])->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.original_items=items.duplicate()
 for event in [4,40]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(37,[4],[])
func run()->void:
 b=Backend.new()
 # Manifest public spawn, not a position in 5106 or a claim to have walked its door.
 b.automation.position_changed(5100,Vector2i(49,37),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 print("fire pure authority=",position," profile.location=",before.get("location",{}))
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public authority only; no cave proof"):finish();return
 if not check(Plan.same_source(b.quest_helper.places.info(5100).spawn,[49,37]),"fixed original manifest spawn"):finish();return
 if not check(Plan.request_proposal(b).get("stage")=="prerequisite","real new profile lacks END4"):finish();return
 if not check(copied_case(40,[4],[]).get("stage")=="unsupported_job","event40 is not job40"):finish();return
 var result:Dictionary=positive()
 if not check(result.get("status")=="step","END4 copy permits proposal only"):finish();return
 var step:Dictionary=result.step
 var source:Dictionary=step.source
 var table:Dictionary=Plan.source_table()
 if not check(step.id=="spirit_fire:request:40" and step.npc_id==Plan.REQUEST_NPC and step.map_id==5106 and step.cell==[26,15],"exact original target, no route execution"):finish();return
 if not check(source.type=="REQUEST" and source.condition=="ENDEV=4" and source.actions.is_empty() and source.branch_index==2 and source.source_line==18,"ordinary empty actions, no invented gift SERVICE or Charm"):finish();return
 if not check(Plan.same_source(source.branch_data,table.npc.branches[2]) and source.branch_data.source_branch_index==2 and source.branch_data.source_line==18,"complete original branch data and source numbering"):finish();return
 if not check(step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,37,false),"ordinary safe shape only; no registry or runner start"):finish();return
 if not check(table.npc.branches.size()==3 and table.npc.branches[0].condition=="ENDEV=4&ENDEV=40" and table.npc.branches[1].condition=="ENDEV=4&NOWEV=40&ITEM=2706","entire higher-priority source branches preserved"):finish();return
 if not check(copied_case(37,[],[],[2706]).get("stage")=="prerequisite","feather does not replace END4"):finish();return
 for items in [[],[2706]]:
  var held:Dictionary=copied_case(37,[4],[40],items)
  if not check(held.get("status")=="manual" and held.get("stage")=="manual_feather_jug_keyword" and not held.has("step"),"NOW40 never repeats request or probes higher message"):finish();return
 if not check(copied_case(37,[40],[40]).get("status")=="done","END40 wins, no extra loop"):finish();return
 # Independently observe real branch selection on isolated snapshot copies.
 var active:Dictionary=b.quest_catalog.active_npc(Plan.REQUEST_NPC)
 var snapshot:Dictionary=before.duplicate(true)
 Rules.set_flag(snapshot,"ended",4,true)
 Rules.set_flag(snapshot,"now",40,true)
 snapshot.original_items=[2706]
 if not check(Plan.same_source(b.original_quests.branch_for(active,snapshot),table.npc.branches[1]),"actual higher message selected with NOW40 and feather"):finish();return
 Rules.set_flag(snapshot,"ended",40,true)
 if not check(Plan.same_source(b.original_quests.branch_for(active,snapshot),table.npc.branches[0]),"actual ended message has first priority"):finish();return
 # Raw source mutations must be restored BEFORE checking or aborting.
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[0].actions.GetItem="2706"
   var mutation:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","unselected raw actions drift rejected"):finish();return
   npc.branches.reverse()
   mutation=positive();npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","raw order drift rejected"):finish();return
   npc.branches[2].condition="LV>0"
   mutation=positive();npc.branches=saved.duplicate(true)
   if not check(mutation.get("stage")=="source_changed","adult guard cannot weaken"):finish();return
   npc.branches[2].texts.ThanksMsg2="changed"
   mutation=positive();npc.branches=saved
   if not check(mutation.get("stage")=="source_changed","full original dialogue locked"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(40)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event40 must be enabled"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden target rejected"):finish();return
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"map_id":5106,"cell":[26,14]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","target relocation rejected"):finish();return
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append(table.npc.duplicate(true))
 var duplicate:Dictionary=positive()
 b.quest_catalog.npcs=npcs
 if not check(duplicate.get("stage")=="source_changed","duplicate identity rejected"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==37:job.event=39
 var mapping:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(mapping.get("stage")=="source_changed","full job mapping locked"):finish();return
 # Returned structures are isolated; no caller may poison source or following proposal.
 step.source.branch_data.actions.GetItem="2706"
 step.cell[0]=0
 var restored:Dictionary=positive()
 if not check(restored.get("status")=="step" and restored.step.source.actions.is_empty() and restored.step.source.branch_data.actions.is_empty() and restored.step.cell==[26,15],"restoration and return alias isolation"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"profile saved location authority and NPC version unchanged"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending==pending and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no talk request save proof battle purchase or implicit start"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_spirit_fire_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
