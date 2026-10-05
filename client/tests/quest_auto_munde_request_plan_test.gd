extends SceneTree
## UNRUN pure proposal. END4 is a profile-copy fixture, not earned progress.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_munde_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func copied_case(ended:Array,now:Array,level:int=30)->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 for event in [4,9,10,11,12]:
  Rules.set_flag(copy,"ended",event,event in ended)
  Rules.set_flag(copy,"now",event,event in now)
 b.session._profile=copy
 var result:Dictionary=Plan.request_proposal(b,8)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 var original:Dictionary=b.session._profile
 var eligible:Dictionary=original.duplicate(true)
 eligible.player.level=30
 Rules.set_flag(eligible,"ended",4,true)
 b.session._profile=eligible
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 var result:Dictionary=Plan.request_proposal(b,8)
 if not check(result.get("status")=="step","explicit END4-copy fixture proposes only first REQUEST9"):finish();return
 if not check(result.step.id=="munde:request:9" and result.step.npc_id==Plan.REQUEST_NPC and result.step.map_id==1200 and result.step.cell==[97,75],"unique original public-village target"):finish();return
 var source:Dictionary=result.step.source
 if not check(source.type=="REQUEST" and source.actions=={} and source.branch_index==1 and source.branch_data.source_branch_index==1 and source.source_line==14 and source.condition=="LV>29&ENDEV=4","complete original empty REQUEST identity"):finish();return
 if not check(result.step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(result.step,8,false),"ordinary proposal shape does not open registry or service"):finish();return
 if not check(Plan.request_proposal(b,9).get("stage")=="unsupported_job","event9 is not job9"):finish();return
 if not check(copied_case([],[]).get("stage")=="prerequisite","level30 alone cannot bypass original END4"):finish();return
 if not check(copied_case([4],[],29).get("stage")=="prerequisite","END4 alone cannot bypass LV greater than29"):finish();return
 if not check(copied_case([4],[9]).get("stage")=="request11","NOW9 ends this slice at manual next commission"):finish();return
 if not check(copied_case([4,10,11,12],[]).get("stage")=="final_reward","higher-priority final reward stays manual"):finish();return
 if not check(copied_case([4,9],[]).get("status")=="done","END9 stops without repetition"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions.GetItem="1358"
   var denied:Dictionary=Plan.request_proposal(b,8)
   npc.branches[0]=saved
   if not check(denied.get("stage")=="source_changed","unselected final reward drift rejects full source"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(9)
 var disabled:Dictionary=Plan.request_proposal(b,8)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event9 disabled despite other active source tags"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=Plan.request_proposal(b,8)
 b.quest_catalog.npc_overrides=overrides
 if not check(hidden.get("stage")=="source_changed","hidden original requester rejected"):finish();return
 if not check(Plan.request_proposal(b,8).get("status")=="step","restored source restores proposal"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"pure calls preserve profile-copy authority and NPC version"):finish();return
 if not check(not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no dialogue keyword Charm Boss or reward started"):finish();return
 b.session._profile=original
 if not check(not Rules.flag(b.session._profile,"ended",4),"restore original uncompleted END4 profile"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_munde_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
