extends SceneTree
## UNRUN tmp candidate; temporary END4/NOW41 copies are not actual preceding quest evidence.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_spirit_wind42_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(level:int,ended:Array,now:Array,job:int=39)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 for event in [4,41,42]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(1,[4],[41])
func run()->void:
 b=Backend.new()
 b.automation.position_changed(100,Vector2i(637,493),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 print("wind42 pure authority=",position," profile.location=",before.get("location",{}))
 if not check(Plan.same_source(b.quest_helper.places.info(100).spawn,[637,493]),"original public manifest spawn, not NPC-side placement"):finish();return
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no protected arrival proof"):finish();return
 if not check(Plan.request_proposal(b).get("stage")=="prerequisite","real new profile cannot bypass preceding quest"):finish();return
 if not check(copied_case(1,[],[41]).get("stage")=="prerequisite" and copied_case(1,[4],[]).get("stage")=="prerequisite","both END4 and NOW41 needed"):finish();return
 if not check(copied_case(1,[4,41],[]).get("stage")=="prerequisite","END41 alone cannot replace NOW41"):finish();return
 if not check(copied_case(0,[4],[41]).get("stage")=="level","strict original LV>0"):finish();return
 if not check(copied_case(1,[4],[41],42).get("stage")=="unsupported_job" and copied_case(1,[4],[41],38).get("stage")=="unsupported_job","event42 not job42 and no implicit preceding job38"):finish();return
 var result:Dictionary=positive()
 if not check(result.get("status")=="step","copied eligibility only"):finish();return
 var step:Dictionary=result.step
 var source:Dictionary=step.source
 var table:Dictionary=Plan.source_table()
 if not check(step.id=="spirit_wind42:request:42" and step.npc_id==Plan.REQUEST_NPC and step.map_id==100 and step.cell==[346,356],"exact original public messenger target"):finish();return
 if not check(source.type=="REQUEST" and source.condition=="LV>0&NOWEV=41&ENDEV=4" and source.actions.is_empty() and source.branch_index==1 and source.source_line==15,"original empty REQUEST and source index"):finish();return
 if not check(Plan.same_source(source.branch_data,table.npc.branches[1]) and step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,39,false),"full source record and ordinary shape only"):finish();return
 var current:Dictionary=copied_case(1,[4],[41,42])
 if not check(current.get("status")=="manual" and current.get("stage")=="manual_harp_munde" and not current.has("step"),"NOW42 stops before harp Munde keyword and cancellation"):finish();return
 if not check(copied_case(0,[42],[42]).get("status")=="done","END42 stops even with stale NOW42"):finish();return
 if not check(table.npc.branches.size()==3 and table.npc.branches[0].condition=="LV>0&NOWEV=42" and table.npc.branches[2].condition=="LV>0","all three original branches retained"):finish();return
 var snapshot:Dictionary=before.duplicate(true)
 Rules.set_flag(snapshot,"ended",4,true);Rules.set_flag(snapshot,"now",41,true);Rules.set_flag(snapshot,"now",42,true)
 if not check(Plan.same_source(b.original_quests.branch_for(b.quest_catalog.active_npc(Plan.REQUEST_NPC),snapshot),table.npc.branches[0]),"actual highest MESSAGE0 wins; no talk probe"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[0].actions.GetItem="2736"
   var changed:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(changed.get("stage")=="source_changed","unselected raw MESSAGE drift rejected"):finish();return
   npc.branches.reverse()
   changed=positive();npc.branches=saved.duplicate(true)
   if not check(changed.get("stage")=="source_changed","source order drift rejected"):finish();return
   npc.branches[1].condition="LV>0&ENDEV=41&ENDEV=4"
   changed=positive();npc.branches=saved
   if not check(changed.get("stage")=="source_changed","NOW cannot be rewritten to END"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(42)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event42 disabled rejects even if41 still active"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden target rejected"):finish();return
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"map_id":100,"cell":[346,355]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","target drift rejected"):finish();return
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append(table.npc.duplicate(true))
 var duplicate:Dictionary=positive()
 b.quest_catalog.npcs=npcs
 if not check(duplicate.get("stage")=="source_changed","duplicate identity rejected"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==39:job.event=41
 var mapping:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(mapping.get("stage")=="source_changed","job39/event42 full mapping locked"):finish();return
 step.source.branch_data.actions.GetItem="2736";step.cell[0]=0
 var restored:Dictionary=positive()
 if not check(restored.get("status")=="step" and restored.step.source.branch_data.actions.is_empty() and restored.step.cell==[346,356],"deep return isolation after restoration"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"actual profile saved location authority NPC version unchanged"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending==pending and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no request save proof prior Boss or implicit chain execution"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_spirit_wind42_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
