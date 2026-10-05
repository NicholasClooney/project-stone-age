extends SceneTree
## UNRUN pure source/proposal; profile-copy negatives are not earned progress.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_miner_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func stage_copy(now:bool,ended:bool,items:Array,level:int=30)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 copy.original_items=items.duplicate()
 Rules.set_flag(copy,"now",27,now)
 Rules.set_flag(copy,"ended",27,ended)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,14)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 b.session._profile.player.level=30
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var result:Dictionary=Plan.request_proposal(b,14)
 if not check(result.get("status")=="step","job14 proposes only exact original REQUEST27"):finish();return
 if not check(result.step.id=="miner:request:27" and result.step.npc_id==Plan.LEADER and result.step.map_id==31805 and result.step.cell==[19,21],"unique original leader target"):finish();return
 var source:Dictionary=result.step.source
 if not check(source.type=="REQUEST" and source.actions=={} and source.source_line==41 and source.branch_index==3 and source.branch_data.source_branch_index==3 and source.condition=="LV>29&ENDEV!=27","original numbered branch and empty actions"):finish();return
 if not check(result.step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(result.step,14,false),"ordinary source proposal shape only, no job registration"):finish();return
 if not check(Plan.request_proposal(b,27).get("stage")=="unsupported_job","event27 is not job27"):finish();return
 if not check(stage_copy(false,false,[],29).get("stage")=="level","original strict LV greater than29"):finish();return
 if not check(stage_copy(true,false,[]).get("stage")=="claim_lunch","NOW27 stops before unapproved next transaction, no repeated REQUEST cancellation"):finish();return
 if not check(stage_copy(true,false,[2534]).get("stage")=="exchange_ore","NOW27 and2534 requires no invented2536 condition"):finish();return
 if not check(stage_copy(true,false,[2534,2536]).get("stage")=="exchange_ore","same original ore stage with2536"):finish();return
 if not check(stage_copy(true,false,[2534,2535,2536]).get("stage")=="wait_boss","earlier2535 branch retains priority, human Boss"):finish();return
 if not check(stage_copy(false,false,[2533]).get("stage")=="claim_ticket","original reward condition does not invent NOW27"):finish();return
 for items in [[],[2527],[2533,2535]]:
  if not check(stage_copy(false,true,items).get("status")=="done","END27 stops without extra purchase or floor6"):finish();return
 # Source-only mutations restored before assertion; never talk/choose or save.
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.LEADER:
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions.DelStone="999"
   var denied:Dictionary=Plan.request_proposal(b,14)
   npc.branches[0]=saved
   if not check(denied.get("stage")=="source_changed","unselected purchase branch drift rejects full lock"):finish();return
  if npc.get("source_script")=="giiru/event/giruev2_2":
   var saved:Dictionary=npc.branches[3].duplicate(true)
   npc.branches[3].condition="NOWEV=27&ITEM=2534&ITEM=2536"
   var denied:Dictionary=Plan.request_proposal(b,14)
   npc.branches[3]=saved
   if not check(denied.get("stage")=="source_changed","invented ore prerequisite in other original NPC rejects lock"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(27)
 var disabled:Dictionary=Plan.request_proposal(b,14)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","disabled event27 rejects first proposal"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.LEADER]={"hidden":true}
 var hidden:Dictionary=Plan.request_proposal(b,14)
 b.quest_catalog.npc_overrides=overrides
 if not check(hidden.get("stage")=="source_changed","hidden leader is not a valid live source"):finish();return
 if not check(Plan.request_proposal(b,14).get("status")=="step","restored complete source allows proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"profile-copy/source checks leave live profile authority and NPC version unchanged"):finish();return
 if not check(not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no REQUEST/Boss/reward transaction opened"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_miner_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
