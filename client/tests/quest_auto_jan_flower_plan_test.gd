extends SceneTree
## UNRUN pure source/proposal. Item/flag cases are isolated profile copies.
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
 var result:Dictionary=Plan.flower_proposal(b,job)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var result:Dictionary=Plan.flower_proposal(b,27)
 if not check(result.get("status")=="step","fresh public profile proposes only original flower ACCEPT"):finish();return
 if not check(result.step.id=="jan:flower:2486" and result.step.npc_id==Plan.FLOWER_NPC and result.step.map_id==3400 and result.step.cell==[59,66],"unique original Kai target"):finish();return
 var source:Dictionary=result.step.source
 if not check(source.type=="ACCEPT" and source.branch_data.event==-1 and source.actions=={"GetItem":"2486"} and source.condition=="ITEM!=2486" and source.branch_index==2 and source.branch_data.source_branch_index==2 and source.source_line==23,"exact single source action; no invented REQUEST or NOW20"):finish();return
 if not check(result.step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(result.step,27,false),"ordinary action shape only, no generic GetItem permission"):finish();return
 if not check(Plan.flower_proposal(b,20).get("stage")=="unsupported_job","event20 is not job20"):finish();return
 if not check(copied_case(27,[],[],[2486]).get("stage")=="request20","holding flower stops before same NPC delete branch"):finish();return
 if not check(copied_case(27,[],[20],[]).get("stage")=="claim_token","NOW20 cannot repeat flower acquisition"):finish();return
 if not check(copied_case(27,[20],[],[]).get("status")=="done","job27 ends at original END20"):finish();return
 if not check(copied_case(28,[],[],[]).get("stage")=="prerequisite","job28 never implicitly starts27"):finish();return
 if not check(copied_case(29,[20],[],[]).get("stage")=="parent_request28","job29 requires explicit parent request28"):finish();return
 var parent:Dictionary=copied_case(28,[20],[21],[])
 if not check(parent.get("stage")=="parent_job29" and parent.get("required_parent_job")==29 and not parent.has("step"),"28 only proposes parent handoff without start29"):finish();return
 if not check(copied_case(29,[20],[21],[]).get("stage")=="random_equipment","original random equipment stays manual"):finish();return
 if not check(copied_case(28,[20,22],[21],[2488]).get("stage")=="deliver_letter","letter2488 can be delivered without inventing2489 prerequisite"):finish();return
 if not check(copied_case(28,[20,22],[21],[2489]).get("stage")=="claim_letter","reward2489 is not the letter to consume"):finish();return
 var table:Dictionary=Plan.source_table()
 var letter_matches:bool=table.manual_boundaries.letter_actions=={"DelItem":"2488","GetItem":"2489","EndSetFlg":"21"}
 var original_parent_matches:bool=table.manual_boundaries.parent_jobs==[28,29,28]
 var parent_matches:bool=Plan.same_source(table.manual_boundaries.parent_jobs,[28,29,28])
 var parent_elements:Array=[]
 for value in table.manual_boundaries.parent_jobs:
  parent_elements.append({"type":typeof(value),"value":value})
 # Passive observations of this run only; do not reconstruct the old failure.
 print("JAN PARENT COMPARISON: "+JSON.stringify({"letter_matches":letter_matches,"original_parent_matches":original_parent_matches,"finite_integer_parent_matches":parent_matches,"parent_elements":parent_elements}))
 if not check(letter_matches and parent_matches,"locked letter source and explicit parent ordering"):finish();return
 if not check(not Plan.same_source([28,28,29],[28,29,28]),"same numeric contract rejects reordered parent jobs"):finish();return
 if not check(not Plan.same_source([28,29.5,28],[28,29,28]),"same numeric contract rejects fractional parent job"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.FLOWER_NPC:
   var saved:Dictionary=npc.branches[3].duplicate(true)
   npc.branches[3].actions.DelItem="2489"
   var denied:Dictionary=Plan.flower_proposal(b,27)
   npc.branches[3]=saved
   if not check(denied.get("stage")=="source_changed","unselected original delete branch drift rejects full source"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(20)
 var disabled:Dictionary=Plan.flower_proposal(b,27)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","disabled event20 rejected despite other source tags"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.FLOWER_NPC]={"hidden":true}
 var hidden:Dictionary=Plan.flower_proposal(b,27)
 b.quest_catalog.npc_overrides=overrides
 if not check(hidden.get("stage")=="source_changed","hidden giver rejected"):finish();return
 if not check(Plan.flower_proposal(b,27).get("status")=="step","source restoration restores proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"all profile-copy and source checks leave actual profile authority NPC version unchanged"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no implicit job start dialogue service Boss reward or flower acquisition"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_jan_flower_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
