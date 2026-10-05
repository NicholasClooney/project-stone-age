extends SceneTree
## UNRUN pure proposal; level/flags/papers only in disclosed profile copies.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_brothers_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(job:int,level:int,ended:Array,now:Array,items:Array)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level;copy.original_items=items.duplicate()
 for event in [28,31]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(18,31,[],[],[])
func run()->void:
 b=Backend.new()
 # Public authority fixture is explicit, distinct from profile's saved location.
 b.automation.position_changed(300,Vector2i(384,432),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public authority only, no dungeon placement or arrival proof"):finish();return
 if not check(Plan.request_proposal(b,18).get("stage")=="level" and copied_case(18,30,[],[],[]).get("stage")=="level","real level1 and copy level30 cannot bypass strict LV>30"):finish();return
 var result:Dictionary=positive()
 if not check(result.get("status")=="step","level31 copy is proposal eligibility, not original REQUEST or route proof"):finish();return
 var step:Dictionary=result.step
 var source:Dictionary=step.source
 if not check(step.id=="brothers:request:28" and step.npc_id=="giiru/event/ev28_0" and step.map_id==31701 and step.cell==[29,44],"exact original first NPC with legacy catalog identity"):finish();return
 if not check(source.type=="REQUEST" and source.branch_data.event==28 and source.condition=="LV>30" and source.actions.is_empty() and source.branch_index==0 and source.source_line==11,"empty original actions, no guessed gift or completion"):finish();return
 if not check(not source.branch_data.has("source_branch_index") and not source.branch_data.has("source_line") and Plan.same_source(source.branch_data,Plan.source_table().npc.branches[0]),"exact catalog branch copied without forged metadata"):finish();return
 if not check(step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,18,false),"ordinary request shape only; registry remains closed"):finish();return
 if not check(copied_case(28,31,[],[],[]).get("stage")=="unsupported_job" and copied_case(19,31,[],[],[]).get("stage")=="unsupported_job","event28 is not job28; no implicit job19 start"):finish();return
 var active:Dictionary=copied_case(18,31,[],[28],[])
 if not check(active.get("status")=="manual" and active.get("stage")=="statue_contract_missing" and not active.has("step"),"NOW28 stops before statues, answers or REQUEST cancellation"):finish();return
 if not check(copied_case(18,31,[28],[28],[]).get("status")=="done","END28 wins even with stale NOW28"):finish();return
 if not check(copied_case(18,31,[31],[],[]).get("status")=="step","END31 does not replace job18 END28"):finish();return
 if not check(copied_case(18,31,[],[28],[2507,2509,2511,2513,2515]).get("stage")=="claim_crystal","copied five papers remain manual; never probe deleting failure MESSAGE"):finish();return
 var table:Dictionary=Plan.source_table()
 if not check(table.npc.branches.size()==2 and table.npc.branches[1].condition=="ENDEV=28" and table.npc.branches[1].actions.is_empty(),"entire original two-branch order and message locked"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[1].actions.DelItem="2507"
   var unselected:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(unselected.get("stage")=="source_changed","unselected MESSAGE mutation rejected before talk"):finish();return
   npc.branches.reverse()
   var order:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(order.get("stage")=="source_changed","raw order change cannot authorize array0"):finish();return
   npc.branches[0].actions.GetItem="2517"
   var gift:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(gift.get("stage")=="source_changed","no invented crystal on empty REQUEST"):finish();return
   npc.branches[0].condition="LV>29"
   var condition:Dictionary=positive()
   npc.branches=saved
   if not check(condition.get("stage")=="source_changed","source level threshold cannot be weakened"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(28)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event28 required despite31 tag"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden first NPC rejected"):finish();return
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"map_id":31701,"cell":[29,43]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","changed target cell rejected without changing actual world"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==18:job.event=31
 var mapping:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(mapping.get("stage")=="source_changed","job18/19 mapping exact"):finish();return
 if not check(positive().get("status")=="step","restored raw source gives only original proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"copies and guards preserve actual profile location authority NPC version"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no actual request papers crystal proof save or implicit jobs"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_brothers_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
