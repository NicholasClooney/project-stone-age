extends SceneTree
## Copies test source eligibility only; no actual level, elemental completion or cave arrival.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_dark_route_plan.gd")
const Rules=preload("res://server/original_quests.gd")
var b
var assertions:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func inspect_copy(level:int=80,ended:Array=[39,40,42,46])->Dictionary:
 var original:Dictionary=b.session._profile
 var copy:Dictionary=original.duplicate(true)
 copy.player.level=level
 for event in [39,40,41,42,46]:Rules.set_flag(copy,"ended",event,event in ended)
 b.session._profile=copy
 var result:Dictionary=Plan.inspect(b)
 b.session._profile=original
 return result
func run()->void:
 b=Backend.new()
 var before:Dictionary=b.session.snapshot()
 var authority:Array=[b.automation.position_map,b.automation.position_cell]
 var table:Dictionary=Plan.source_table()
 var version:int=b.original_quests.npc_state.version
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 if not check(not table.is_empty() and table.jobs.is_empty(),"no fabricated dark job id"):finish();return
 if not check(inspect_copy().get("stage")=="manual_route_integration","eligible source still not executable"):finish();return
 if not check(inspect_copy(79).get("stage")=="prerequisite","level79 blocked"):finish();return
 for missing in [39,40,42,46]:
  var ended:Array=[39,40,42,46];ended.erase(missing)
  if not check(inspect_copy(80,ended).get("stage")=="prerequisite","every elemental END required"):finish();return
 if not check(inspect_copy(80,[39,40,41,46]).get("stage")=="prerequisite","END41 cannot replace END42"):finish();return
 var first:Dictionary=table.current_npcs["300/sb_skr.arg@32010:54:30"].branches[0]
 var second:Dictionary=table.current_npcs["300/sb_skt.arg@32020:20:9"].branches[0]
 if not check(first.actions.Warp=="32011,56,36" and second.actions.Warp=="32021,29,57" and table.boundary=="777/ten.arg@32021:31:28","two distinct original victory warps, king boundary"):finish();return
 if not check(table.current_npcs["genout/wpm_300_103_228@300:103:228"].branches[0].actions.Warp=="300,105,228","outer gate is not alternative cave teleport"):finish();return
 for npc in b.quest_catalog.npcs:
  if npc.id!="300/sb_skt.arg@32020:20:9":continue
  var saved:Dictionary=npc.branches[0].actions.duplicate(true)
  npc.branches[0].actions.Warp="32021,31,28"
  var changed:Dictionary=inspect_copy();npc.branches[0].actions=saved
  if not check(changed.get("stage")=="source_changed","unselected future guard cannot drift"):finish();return
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[table.entry_id]={"hidden":true}
 var result:Dictionary=inspect_copy();b.quest_catalog.npc_overrides=overrides
 if not check(result.get("stage")=="disabled","hidden entry not callable"):finish();return
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append(table.current_npcs[table.entry_id].duplicate(true))
 result=inspect_copy();b.quest_catalog.npcs=npcs
 if not check(result.get("stage")=="source_changed","duplicate original entry"):finish();return
 if not check(not inspect_copy().has("step") and b.session.snapshot()==before and authority==[b.automation.position_map,b.automation.position_cell] and version==b.original_quests.npc_state.version,"no ability profile authority or refresh"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending==pending and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no battle save talk or route proof"):finish();return
 finish()
func finish()->void:
 b.free()
 print("quest_auto_dark_route_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
