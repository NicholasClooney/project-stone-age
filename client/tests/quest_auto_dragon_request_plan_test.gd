extends SceneTree
## UNRUN pure proposal, explicit public origin; no protected placement or proof.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_dragon_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(now:bool,ended:bool,items:Array,level:int=1)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 copy.original_items=items.duplicate()
 Rules.set_flag(copy,"now",17,now)
 Rules.set_flag(copy,"ended",17,ended)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,26)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 # Authoritative position is not initialized merely by a default saved location.
 b.automation.position_changed(1000,Vector2i(80,90),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 if not check(position==[1000,Vector2i(80,90)] and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"explicit public start has no dragon arrival proof"):finish();return
 var result:Dictionary=Plan.request_proposal(b,26)
 if not check(result.get("status")=="step","level1 public profile proposes original first REQUEST17"):finish();return
 if not check(result.step.id=="dragon:request:17" and result.step.npc_id==Plan.REQUEST_NPC and result.step.map_id==20801 and result.step.cell==[13,63],"exact first-floor guardian source target"):finish();return
 var source:Dictionary=result.step.source
 if not check(source.type=="REQUEST" and source.branch_data.event==17 and source.actions=={"GetItem":"2505"} and source.condition=="LV>0&ITEM!=2505" and source.source_line==13 and source.branch_index==1 and source.branch_data.source_branch_index==1,"only original REQUEST flute action and complete identity"):finish();return
 if not check(result.step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(result.step,26,false),"ordinary action shape, not a generic GetItem grant"):finish();return
 if not check(Plan.request_proposal(b,17).get("stage")=="unsupported_job","event17 is not job17"):finish();return
 if not check(copied_case(false,false,[],0).get("status")=="manual","actual branch condition rejects LV0"):finish();return
 if not check(copied_case(false,false,[2505]).get("stage")=="inconsistent_token","existing flute without NOW17 cannot be silently fixed"):finish();return
 if not check(copied_case(true,false,[]).get("stage")=="replace_token","higher-priority replacement ACCEPT stays manual"):finish();return
 if not check(copied_case(true,false,[2505]).get("stage")=="loot_contract_missing","after original commission stops before unfrozen loot"):finish();return
 if not check(copied_case(true,false,[2505,2457,2458,2459]).get("stage")=="gate_and_manual_reward","three gems never grant gate proof or select reward"):finish();return
 if not check(copied_case(false,true,[]).get("status")=="done","END17 stops even without flute or gems"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions.GetItem="2506"
   var denied:Dictionary=Plan.request_proposal(b,26)
   npc.branches[0]=saved
   if not check(denied.get("stage")=="source_changed","unselected replacement branch drift rejects full source"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(17)
 var disabled:Dictionary=Plan.request_proposal(b,26)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","disabled17 rejects proposal"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=Plan.request_proposal(b,26)
 b.quest_catalog.npc_overrides=overrides
 if not check(hidden.get("stage")=="source_changed","hidden guardian rejects proposal"):finish();return
 if not check(Plan.request_proposal(b,26).get("status")=="step","restored source restores proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version and b.quest_arrival._scope.is_empty(),"profile authority NPC version and arrival unchanged by all proposals"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no auto job dialogue loot Boss or reward started"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_dragon_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
