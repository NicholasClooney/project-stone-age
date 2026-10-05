extends SceneTree
## Eligibility copies only. Never enters a protected map or issues a command.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_spirit_wind41_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func proposal(ended:Array=[],now:Array=[],job:int=38)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 for event in [4,41]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 var table:Dictionary=Plan.source_table()
 if not check(not table.is_empty(),"source lock loads"):finish();return
 if not check(proposal().get("stage")=="prerequisite","no real adult prerequisite"):finish();return
 if not check(proposal([4]).get("stage")=="manual_guarded_arrival","eligible copy still blocked"):finish();return
 if not check(proposal([4],[],41).get("stage")=="unsupported_job","event is not job"):finish();return
 if not check(proposal([4],[41]).get("stage")=="manual_later_stage","no repeat request/cancel"):finish();return
 if not check(proposal([41],[41]).get("status")=="done","ended stops"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(41)
 var result:Dictionary=proposal([4])
 b.quest_catalog.enabled_events=enabled
 if not check(result.get("stage")=="disabled","disabled event"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 for change in [{"hidden":true},{"map_id":11215,"cell":[0,0]}]:
  b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]=change
  if change.has("map_id"):
   var projected:Dictionary=b.quest_catalog.active_npc(Plan.REQUEST_NPC)
   var moved:bool=projected.get("map_id")==11215 and projected.get("cell")==[0,0]
   if not check(moved,"fixture precondition: active NPC has original map and moved cell"):
    b.quest_catalog.npc_overrides=overrides.duplicate(true)
    finish();return
  result=proposal([4]);b.quest_catalog.npc_overrides=overrides.duplicate(true)
  if not check(result.get("stage")=="source_changed","active projection drift"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id!=Plan.REQUEST_NPC:continue
  var saved:Array=npc.branches.duplicate(true)
  npc.branches.reverse()
  result=proposal([4]);npc.branches=saved.duplicate(true)
  if not check(result.get("stage")=="source_changed","raw branch priority drift"):finish();return
  npc.branches[0].actions.GetItem="1"
  result=proposal([4]);npc.branches=saved
  if not check(result.get("stage")=="source_changed","unselected raw action drift"):finish();return
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append(table.npc.duplicate(true))
 result=proposal([4]);b.quest_catalog.npcs=npcs
 if not check(result.get("stage")=="source_changed","duplicate identity"):finish();return
 for ended in [[],[4],[41]]:
  if not check(not proposal(ended).has("step"),"no executable capability"):finish();return
 if not check(table.npc.branches[1].condition=="LV>0&ENDEV=42&ENDEV=4&PET>0-95,LV>0&PET>0-95" and table.manual_boss_npc.branches[0].actions.Warp=="11215,9,16","unweakened OR and original boss landing"):finish();return
 var pet_copy:Dictionary=before.duplicate(true)
 # Explicit eligibility copy, not a captured pet or a real prerequisite.
 pet_copy.pets=[{"species":"original_95","level":1,"pet_id":"eligibility-only-95","original_end_event":0}]
 Rules.set_flag(pet_copy,"ended",4,false)
 Rules.set_flag(pet_copy,"ended",42,false)
 if not check(Rules.Session.original_pet_event(pet_copy.pets[0])==0,"fixture precondition: eligibility copy is event0"):finish();return
 if not check(Rules.pet_indices(pet_copy,"PET>0-95")==[0],"fixture precondition: ordinary95 eligibility index is zero"):finish();return
 var selected:Dictionary=b.original_quests.branch_for(b.quest_catalog.active_npc(Plan.REQUEST_NPC),pet_copy)
 if not check(Plan.Compare.same_source(selected,table.npc.branches[1]),"actual original OR selects95 message without END4 or END42"):finish();return
 var original:Dictionary=b.session._profile
 Rules.set_flag(pet_copy,"ended",4,true)
 b.session._profile=pet_copy
 var pet_result:Dictionary=Plan.request_proposal(b)
 b.session._profile=original
 if not check(pet_result.get("stage")=="manual_source_priority" and pet_copy.pets.size()==1,"95 pet is not removed to evade original priority"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"no profile authority or NPC mutation"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending==pending and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no commands or protected proof"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_spirit_wind41_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
