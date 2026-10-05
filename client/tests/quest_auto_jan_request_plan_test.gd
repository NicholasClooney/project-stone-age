extends SceneTree
## UNRUN pure proposal; flower/flags below are disclosed isolated profile copies.
## Real driver must earn flower+UID through original Kai branch2 on same Backend.
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
 var result:Dictionary=Plan.request_proposal(b,job)
 b.session._profile=original
 return result
func positive()->Dictionary:return copied_case(27,[],[],[2486])
func run()->void:
 b=Backend.new()
 # Disclosed public fixture only; no protected house placement or proof.
 b.automation.position_changed(3400,Vector2i(60,41),true,"project")
 var before:Dictionary=b.session.snapshot()
 var position:Array=[b.automation.position_map,b.automation.position_cell]
 var version:int=b.original_quests.npc_state.version
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public fixture has no protected arrival"):finish();return
 if not check(Plan.request_proposal(b,27).get("stage")=="flower","actual fresh profile lacks flower; no REQUEST eligibility claimed"):finish();return
 var result:Dictionary=positive()
 if not check(result.get("status")=="step","profile copy with flower proposes REQUEST, not real acquisition"):finish();return
 var step:Dictionary=result.step
 var source:Dictionary=step.source
 if not check(step.id=="jan:request:20" and step.npc_id==Plan.REQUEST_NPC and step.map_id==3406 and step.cell==[27,14],"Gide himself, not Kai son or wife"):finish();return
 if not check(source.type=="REQUEST" and source.branch_data.event==20 and source.condition=="ITEM=2486" and source.actions=={"DelItem":"2486"} and source.branch_index==1 and source.branch_data.source_branch_index==1 and source.source_line==17,"complete first REQUEST signature, no new action"):finish();return
 if not check(step.auto_choices==["yes","ok"] and b.quest_auto.safe_step(step,27,false),"ordinary proposal shape only; registry remains closed"):finish();return
 if not check(copied_case(20,[],[],[2486]).get("stage")=="unsupported_job" and copied_case(28,[],[],[2486]).get("stage")=="unsupported_job","event/job mapping and no implicit parent handoff"):finish();return
 if not check(copied_case(27,[],[20],[]).get("stage")=="claim_token" and copied_case(27,[],[20],[2486]).get("stage")=="claim_token","NOW20 stops before son and never offers cancellation or duplicate REQUEST"):finish();return
 if not check(copied_case(27,[],[20],[2487]).get("stage")=="keyword_boss_return","token copy still manual; no keyword Boss or reward"):finish();return
 if not check(copied_case(27,[20],[21],[2486,2488]).get("status")=="done","END20 immediately stops, never bypasses priority letter branch"):finish();return
 if not check(copied_case(27,[21],[],[2486]).get("status")=="step","END21 is not substituted for job27 END20"):finish();return
 var table:Dictionary=Plan.request_source_table()
 if not check(table.npc.branches.size()==4 and table.original_branch_order.size()==6 and Plan.same_source(table.npc.branches[0].actions,{"DelItem":"2488","GetItem":"2489","EndSetFlg":"21"}),"full current four branches and original six distinguished; letter source preserved"):finish();return
 # Mutations are restored before any assertion can stop the suite.
 for npc in b.quest_catalog.npcs:
  if npc.id==Plan.REQUEST_NPC:
   var saved:Array=npc.branches.duplicate(true)
   npc.branches[0].actions.DelItem="2489"
   var drift:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(drift.get("stage")=="source_changed","unselected higher priority letter action drift rejected"):finish();return
   npc.branches.reverse()
   var order:Dictionary=positive()
   npc.branches=saved.duplicate(true)
   if not check(order.get("stage")=="source_changed","branch order drift rejected"):finish();return
   npc.branches[1].actions.GetItem="2487"
   var extra:Dictionary=positive()
   npc.branches=saved
   if not check(extra.get("stage")=="source_changed","son token action cannot be smuggled into REQUEST"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(20)
 var disabled:Dictionary=positive()
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("stage")=="disabled","event20 required even if21/22 enabled"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"hidden":true}
 var hidden:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden Gide rejected"):finish();return
 b.quest_catalog.npc_overrides[Plan.REQUEST_NPC]={"map_id":3406,"cell":[28,17]}
 var moved:Dictionary=positive()
 b.quest_catalog.npc_overrides=overrides
 if not check(moved.get("stage")=="source_changed","son position is not an alternative Gide target"):finish();return
 var jobs:Array=b.quest_catalog.jobs.duplicate(true)
 for job in b.quest_catalog.jobs:
  if int(job.id)==27:job.event=21
 var wrong_job:Dictionary=positive()
 b.quest_catalog.jobs=jobs
 if not check(wrong_job.get("stage")=="source_changed","job27 event mapping drift rejected"):finish();return
 if not check(positive().get("status")=="step","restored source proposes same exact REQUEST"):finish();return
 if not check(b.session.snapshot()==before and position==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"profile-copy source checks leave actual profile authority NPC version untouched"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no talk choose save job service proof or reward side effects"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_jan_request_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
