extends SceneTree
## UNRUN pure token proposal; NOW20/items below are explicit profile copies.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_jan_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(job:int,ended:Array,now:Array,items:Array)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.original_items=items.duplicate()
 for event in [20,21,22]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.token_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(27,[],[20],[])
func run()->void:
 b=Backend.new()
 b.automation.position_changed(3400,Vector2i(60,41),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public fixture has no house placement or protected proof"):finish();return
 if not check(Plan.token_proposal(b,27).get("stage")=="flower","actual fresh profile cannot claim token without REQUEST"):finish();return
 if not check(copied_case(27,[],[],[2486]).get("stage")=="request20","flower alone does not imply completed REQUEST"):finish();return
 var result:Dictionary=positive()
 if not check(result.get("status")=="step","explicit NOW20 profile-copy eligibility, not actual REQUEST evidence"):finish();return
 var step:Dictionary=result.step
 var source:Dictionary=step.source
 if not check(step.id=="jan:token:2487" and step.npc_id==Plan.TOKEN_NPC and step.map_id==3406 and step.cell==[28,17],"son only, not father Kai or wife"):finish();return
 if not check(source.type=="ACCEPT" and source.branch_data.event==20 and source.condition=="NOWEV=20&ITEM!=2487" and source.actions=={"GetItem":"2487"} and source.branch_index==0 and source.branch_data.source_branch_index==0 and source.source_line==6,"exact first original token branch and sole action"):finish();return
 if not check(step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,27,false),"ordinary shape only, not new GetItem or service permission"):finish();return
 if not check(copied_case(20,[],[20],[]).get("stage")=="unsupported_job" and copied_case(28,[],[20],[]).get("stage")=="unsupported_job" and copied_case(29,[],[20],[]).get("stage")=="unsupported_job","event is not job and no parent starts"):finish();return
 var held:Dictionary=copied_case(27,[],[20],[2487])
 if not check(held.get("stage")=="keyword_boss_return" and held.get("status")=="manual" and not held.has("step"),"held token stops without repeated ACCEPT MESSAGE keyword Boss or reward"):finish();return
 if not check(copied_case(27,[20],[20],[]).get("status")=="done","END20 stops even with stale NOW20 and missing token"):finish();return
 if not check(copied_case(27,[21],[],[]).get("stage")=="flower","END21 cannot invent NOW20 eligibility"):finish();return
 if not check(copied_case(27,[21],[20],[]).get("status")=="step","END21 is not substituted for job27 END20"):finish();return
 var table:Dictionary=Plan.token_source_table()
 if not check(table.npc.branches.size()==3 and Plan.same_source(table.npc.branches[1].actions,{}) and table.npc.branches[1].condition=="NOWEV=20&ITEM=2487" and table.npc.branches[2].condition=="ENDEV=20&ENDEV=21","all three original ordered branches locked including unselected messages"):finish();return
 # Each mutation restores catalog before a check may terminate this test.
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.TOKEN_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[1].actions.GetItem="2487"
   var message_drift:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(message_drift.get("stage")=="source_changed","unselected held-token MESSAGE action drift rejects complete source"):finish();return
   npc.branches.reverse()
   var reordered:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(reordered.get("stage")=="source_changed","source order must remain exact"):finish();return
   npc.branches[0].actions.Charm="1"
   var extra:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(extra.get("stage")=="source_changed","Charm cannot be added to ordinary GetItem"):finish();return
   npc.branches[0].condition="ITEM!=2487"
   var missing_now:Dictionary=positive()
   npc.branches=saved
   if not check(missing_now.get("stage")=="source_changed","NOW20 source requirement cannot be weakened"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(20)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event20 required despite21/22 tags"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.TOKEN_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden son rejected"):finish();return
 b.quest_catalog.npc_overrides[Plan.TOKEN_NPC]={"map_id":3406,"cell":[27,14]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","father coordinates cannot replace son"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==27:job.event=21
 var wrong_job:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(wrong_job.get("stage")=="source_changed","job/event source mapping must remain exact"):finish();return
 if not check(positive().get("status")=="step","restored source returns only original ACCEPT"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"profile-copy guards preserve actual profile authority and NPC version"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no acquisition UID save dialogue proof or implicit job side effects"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_jan_token_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
