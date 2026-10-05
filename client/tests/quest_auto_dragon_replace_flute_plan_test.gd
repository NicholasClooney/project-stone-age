extends SceneTree
## UNRUN pure proposal; flags/items are isolated profile-copy eligibility only.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_dragon_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const Equipment=preload("res://server/original_equipment.gd")
var b
var base:Dictionary={}
var assertions:int=0
var failures:int=0
var fixture_failed:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func fixture_ready()->bool:
 if fixture_failed:
  if failures==0:check(false,"fixture did not complete; stop before branch/proposal")
  return false
 return true
func fixture(ended:Array,now:Array,items:Array,level:int)->Dictionary:
 fixture_failed=true
 var base_before:Dictionary=base.duplicate(true)
 var live_before:Dictionary=b.session._profile.duplicate(true)
 var p:Dictionary=base.duplicate(true)
 Equipment.migrate(p)
 if not check(p.get("original_items") is Array and p.get("original_instances") is Array and p.get("original_equipment") is Dictionary and typeof(p.get("next_original_uid"))==TYPE_INT and p.get("next_original_uid",0)>0,"fixture migration creates items/instances/equipment/positive integer next_uid"):return {}
 if not check(p.original_items.size()==p.original_instances.size() and p.original_equipment.size()==5,"fixture migrated collection structure"):return {}
 for slot in ["arm","bracelet","amulet","head","body"]:
  if not check(typeof(p.original_equipment.get(slot))==TYPE_INT and p.original_equipment.get(slot,-1)>=0,"fixture migrated equipment slot integer"):return {}
 for index in range(p.original_items.size()):
  var entry:Variant=p.original_instances[index]
  if not check(typeof(p.original_items[index])==TYPE_INT and entry is Dictionary,"fixture migrated item and instance types"):return {}
  if not check(typeof(entry.get("uid"))==TYPE_INT and entry.get("uid",0)>0 and entry.get("uid",0)<p.next_original_uid and typeof(entry.get("item_id"))==TYPE_INT and entry.get("item_id")==p.original_items[index] and typeof(entry.get("durability"))==TYPE_INT,"fixture migrated instance fields and UID bound"):return {}
 if not check(base==base_before and b.session._profile==live_before,"fixture migration preserves base and live full profile"):return {}
 p.player.level=level
 for value in [4,9,10,11,12,17,27]:
  Rules.set_flag(p,"ended",value,value in ended)
  Rules.set_flag(p,"now",value,value in now)
 # Complete copy, actual item-instance constructor; never add to live base.
 p.original_items=[];p.original_instances=[]
 for slot in p.original_equipment:p.original_equipment[slot]=0
 for item in items:Equipment.add(p,int(item))
 if not check(base==base_before and b.session._profile==live_before,"fixture eligibility edits preserve base and live full profile"):return {}
 fixture_failed=false
 return p
func state()->Dictionary:
 return {"profile":b.session._profile.duplicate(true),"position":[b.automation.position_map,b.automation.position_cell],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true),"npc_version":b.original_quests.npc_state.version,"pending":b.original_quests.pending.duplicate(true),"session_pending":b.session._pending.duplicate(true),"serial":b.original_quests.serial,"save_serial":b.quest_save_serial,"resume_writes":b.resume_writes,"running":b.quest_auto.running,"battle":b.battle_open}
func proposal(p:Dictionary)->Dictionary:
 var saved:Dictionary=b.session._profile
 b.session._profile=p
 var before:Dictionary=state()
 var result:Dictionary=Plan.replace_flute_proposal(b,26)
 var unchanged:bool=state()==before
 b.session._profile=saved
 if not check(unchanged,"proposal preserves full fixture/profile authority proof pending and save counters"):return {}
 return result
func selected(p:Dictionary)->Dictionary:
 var active:Dictionary=b.quest_catalog.active_npc(Plan.REPLACE_FLUTE_NPC)
 return b.original_quests.branch_for(active,p)
func no_step_case(p:Dictionary,stage:String,expected_index:int=-999)->bool:
 if expected_index!=-999:
  var actual:Dictionary=selected(p)
  if not check(actual.get("source_branch_index",-999)==expected_index,"negative fixture first proves real highest source branch"):return false
 var result:Dictionary=proposal(p)
 return check(result.get("status")=="manual" and result.get("stage")==stage and not result.has("step"),"manual boundary "+stage)
func run()->void:
 b=Backend.new()
 # Public authority is explicit and distinct from the saved profile location.
 b.automation.position_changed(1000,Vector2i(80,90),true,"project")
 base=b.session._profile.duplicate(true)
 var baseline:Dictionary=state()
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"public start grants no protected arrival"):finish();return
 var eligible:Dictionary=fixture([],[17],[],1)
 if not fixture_ready():finish();return
 var branch:Dictionary=selected(eligible)
 if not check(branch.get("source_branch_index")==0,"positive fixture independently proves original highest branch"):finish();return
 var result:Dictionary=proposal(eligible)
 if not check(result.get("status")=="step","exact next ordinary proposal only"):finish();return
 if not check(result.step.npc_id==Plan.REPLACE_FLUTE_NPC and result.step.auto_choices==["yes","ok"] and Plan.same_source(result.step.source.branch_data,branch),"returned full original branch is unchanged"):finish();return
 if not check(result.step.source.actions=={"GetItem":"2505"} and result.step.source.branch_index==0 and result.step.source.branch_data.event==17,"exact event and action strings, no generated flags"):finish();return
 if not check(b.quest_auto.safe_step(result.step,26,false),"ordinary shape acceptance only; not registration or execution"):finish();return
 if not check(Plan.replace_flute_proposal(b,-1).get("stage")=="unsupported_job","wrong job rejected without touching original profile"):finish();return
 var fixture_copy_1:Dictionary=fixture([],[],[],1)
 if not fixture_ready():finish();return
 if not no_step_case(fixture_copy_1,"request",1):finish();return
 var fixture_copy_2:Dictionary=fixture([],[],[2505],1)
 if not fixture_ready():finish();return
 if not no_step_case(fixture_copy_2,"inconsistent_token"):finish();return
 var fixture_copy_3:Dictionary=fixture([],[17],[2505],1)
 if not fixture_ready():finish();return
 if not no_step_case(fixture_copy_3,"loot_contract_missing",2):finish();return
 var fixture_copy_4:Dictionary=fixture([],[17],[2505,2457,2458,2459],1)
 if not fixture_ready():finish();return
 if not no_step_case(fixture_copy_4,"gate_and_manual_reward",2):finish();return
 var fixture_copy_5:Dictionary=fixture([17],[],[],1)
 if not fixture_ready():finish();return
 if not check(proposal(fixture_copy_5).get("status")=="done","END17 stops before source REQUEST could replay"):finish();return
 var low:Dictionary=fixture([],[17],[],0)
 if not fixture_ready():finish();return
 if not check(selected(low).get("source_branch_index")==0 and proposal(low).get("status")=="step","original replacement has no invented LV>0 condition"):finish();return
 # A returned dictionary cannot mutate a later proposal or the frozen source.
 result.step.source.branch_data.actions["probe"]="changed"
 var fresh:Dictionary=proposal(eligible)
 if not check(fresh.get("status")=="step" and not fresh.step.source.branch_data.actions.has("probe"),"returned branch deep-copy isolation"):finish();return
 var table:Dictionary=Plan.replace_flute_source_table()
 var target:Dictionary={}
 for row in table.npcs:
  if row.id==Plan.REPLACE_FLUTE_NPC:target=row
 if not check(not target.is_empty(),"independent source table has exact target"):finish();return
 var found:bool=false
 for npc in b.quest_catalog.npcs:
  if npc.id!=Plan.REPLACE_FLUTE_NPC:continue
  found=true
  var saved_branches:Array=npc.branches.duplicate(true)
  npc.branches[0].actions["unreviewed"]="drift"
  var triggered:bool=not Plan.same_source(npc,target)
  var denied:Dictionary=proposal(eligible)
  npc.branches=saved_branches.duplicate(true)
  if not check(triggered and denied.get("stage")=="source_changed","raw branch drift actually changes full lock"):finish();return
  npc.branches.reverse()
  triggered=not Plan.same_source(npc,target)
  denied=proposal(eligible)
  npc.branches=saved_branches.duplicate(true)
  if not check(triggered and denied.get("stage")=="source_changed","original branch order drift rejects"):finish();return
 if not check(found,"mutation target was found; no vacuous negative"):finish();return
 var old_overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 # Production projection only uses cell together with map_id: supply both.
 b.quest_catalog.npc_overrides[Plan.REPLACE_FLUTE_NPC]={"map_id":int(target.map_id),"cell":[int(target.cell[0])+1,int(target.cell[1])]}
 var moved:Dictionary=b.quest_catalog.active_npc(Plan.REPLACE_FLUTE_NPC)
 var coordinate_trigger:bool=moved.get("cell",[])!=target.cell
 var move_denied:Dictionary=proposal(eligible)
 b.quest_catalog.npc_overrides=old_overrides.duplicate(true)
 if not check(coordinate_trigger and move_denied.get("stage")=="source_changed","map+cell override genuinely projects a different location"):finish();return
 b.quest_catalog.npc_overrides[Plan.REPLACE_FLUTE_NPC]={"hidden":true}
 var hidden_trigger:bool=b.quest_catalog.active_npc(Plan.REPLACE_FLUTE_NPC).is_empty()
 var hidden_denied:Dictionary=proposal(eligible)
 b.quest_catalog.npc_overrides=old_overrides
 if not check(hidden_trigger and hidden_denied.get("stage")=="source_changed","hidden projection is genuinely empty"):finish();return
 var old_enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(17)
 var event_trigger:bool=not 17 in b.quest_catalog.enabled_events
 var disabled:Dictionary=proposal(eligible)
 b.quest_catalog.enabled_events=old_enabled
 if not check(event_trigger and disabled.get("stage")=="disabled","explicit required-event guard, irrespective of other NPC tags"):finish();return
 var json_integral:Variant=JSON.parse_string("[2,3]")
 if not check(Plan.same_source(json_integral,[2,3]) and not Plan.same_source([2.5,3],[2,3]) and not Plan.same_source([true,3],[1,3]) and not Plan.same_source([3,2],[2,3]),"finite integral JSON equality preserves order and rejects fraction/bool"):finish();return
 if not check(proposal(eligible).get("status")=="step","all negative fixtures restored before final positive"):finish();return
 if not check(state()==baseline and b.session._profile==base,"original full profile/pets/UID/events and authority preserved"):finish();return
 if not check(not b.quest_auto.running and not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty(),"no runner dialogue payment battle loot or save launched"):finish();return
 finish()
func finish()->void:
 if b!=null:b.free()
 print("quest_auto_dragon_replace_flute_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
