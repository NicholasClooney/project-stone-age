extends SceneTree
## UNRUN source/proposal only. No movement, dialogue, pet mutation or save.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_doctor_plan.gd")
var b
var assertions:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func run()->void:
 b=Backend.new()
 b.session._profile.player.level=10
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var result:Dictionary=Plan.request_proposal(b,6)
 if not check(result.get("status")=="step","job6 exact original first REQUEST proposed"):finish();return
 if not check(result.step.source.type=="REQUEST" and result.step.source.actions=={} and result.step.source.branch_data.event==15 and result.step.source.source_line==26,"original event15 empty-action REQUEST, not pet transaction"):finish();return
 if not check(result.step.map_id==11006 and result.step.cell==[11,11] and result.step.auto_choices==["yes","ok"],"locked original Doctor target and ordinary choices"):finish();return
 if not check(b.quest_auto.safe_step(result.step,6,false),"existing ordinary source action shape accepts no pet actions"):finish();return
 if not check(Plan.request_proposal(b,7).get("stage")=="prerequisite","job7 is separate and requires END15"):finish();return
 for wrong in [15,16]:
  if not check(Plan.request_proposal(b,wrong).get("stage")=="unsupported_job","event number cannot be treated as job id"):finish();return
 # Source mutations are restored before checking the result; no actual role state
 # or pet list is changed by a negative fixture.
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.DOCTOR:
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions.DelPet="PET>0-74*1"
   var denied:Dictionary=Plan.request_proposal(b,6)
   npc.branches[0]=saved
   if not check(denied.get("status")=="manual","unselected original DelPet drift rejects entire source"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(15)
 var disabled:Dictionary=Plan.request_proposal(b,6)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("status")=="manual","disabled event15 rejects proposal"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.DOCTOR]={"hidden":true}
 var hidden:Dictionary=Plan.request_proposal(b,6)
 b.quest_catalog.npc_overrides=overrides
 if not check(hidden.get("status")=="manual","hidden original Doctor rejects proposal"):finish();return
 if not check(Plan.request_proposal(b,6).get("status")=="step","source restoration restores proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"all proposal calls preserve profile/pets/authority/spawn version"):finish();return
 if not check(not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no dialogue or battle or pet consumption opened"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_doctor_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
