extends SceneTree
## UNRUN direct-Backend route, not running auto admission/reentrancy coverage.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_saton_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Wait=preload("res://tests/support/wait.gd")
class ObservedNav:
 extends "res://server/quest_auto_navigation.gd"
 var calls:Array=[]
 func local_path(b,map_id:int,origin:Vector2i,goal:Vector2i,occupied:Dictionary)->Array:
  var result:Array=super.local_path(b,map_id,origin,goal,occupied)
  calls.append({"call":"local_path","map_id":map_id,"origin":[origin.x,origin.y],"goal":[goal.x,goal.y],"result":result.duplicate(true),"npc_version":b.original_quests.npc_state.version})
  return result
 func plan(b,npc:Dictionary)->Array:
  var result:Array=super.plan(b,npc)
  calls.append({"call":"plan","target":npc.duplicate(true),"result":result.duplicate(true),"searches":entry_routes.searches,"copies":entry_routes.context_copies,"visited":entry_routes.visited_cells,"output":entry_routes.output_points})
  return result
var b
var nav=ObservedNav.new()
var assertions:=0
var failures:=0
var failed:=false
var done:=false
var commissioned:=false
var walked:=0
var portals:=0
var field_calls:=0
var protected_walk:=0
var target:Dictionary={}
var events:Array=[]
var first_failure:Dictionary={}
func _initialize()->void:call_deferred("run")
func state()->Dictionary:
 return {"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true)}
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:
  failures+=1;failed=true
  if first_failure.is_empty():first_failure={"label":label,"state":state(),"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
  write_trace();push_error(label)
 return ok
func write_trace()->void:
 var f=FileAccess.open("user://saton-first-boss-trace.json",FileAccess.WRITE)
 if f:f.store_string(JSON.stringify({"events":events,"navigation":nav.calls,"first_failure":first_failure,"walked":walked,"portals":portals,"field_calls":field_calls,"protected_walk":protected_walk,"commissioned":commissioned,"done":done},"  "));f.close()
func run()->void:
 b=Backend.new()
 b.session._profile.player.level=16
 b.automation.position_changed(1112,Vector2i(11,15),true,"project")
 b.save_path="user://saton-first-boss-route.json"
 # Explicit original setting: compatibility without random field battles only.
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"normal encounter-off setting saves"):finish();return
 if not check(not Rules.flag(b.session._profile,"now",13) and not Rules.flag(b.session._profile,"ended",13) and not Rules.flag(b.session._profile,"ended",14) and not [2431,2428,2429,2430,2450].any(func(item):return item in b.session._profile.original_items),"fresh ungranted quest state"):finish();return
 b.original_quests.refresh_npc_state()
 var request:Dictionary=Plan.request_proposal(b)
 if not check(request.get("status")=="step","actual original request available"):finish();return
 target={"id":request.step.npc_id,"map_id":request.step.map_id,"cell":request.step.cell.duplicate()}
 var reached:bool=await Wait.until(self,drive,120.0)
 if failed:finish();return
 if not check(reached and done,"first manual Boss boundary reached within explicit condition deadline"):finish();return
 if not check(portals==3 and protected_walk>0 and field_calls==walked,"three original doors plus actual protected field steps"):finish();return
 if not check(not b.battle_open and b.session._pending.is_empty() and b.original_quests.pending.is_empty(),"no Boss dialogue or battle opened"):finish();return
 if not check(Rules.flag(b.session._profile,"now",13) and 2431 in b.session._profile.original_items and not Rules.flag(b.session._profile,"ended",13) and not Rules.flag(b.session._profile,"ended",14) and not [2428,2429,2430,2450].any(func(item):return item in b.session._profile.original_items),"no treasure/end/reward granted"):finish();return
 finish()
func drive()->bool:
 # Scheduling batch only; each logical point still commits independently.
 for _index in range(16):
  if failed or done:return true
  if not advance():return true
 return failed or done
func near()->bool:
 var offset:Vector2i=b.automation.position_cell-Vector2i(target.cell[0],target.cell[1])
 return b.automation.position_map==int(target.map_id) and maxi(absi(offset.x),absi(offset.y))<=2
func advance()->bool:
 if near():
  if not commissioned:return commission()
  var before:Dictionary=b.session.snapshot()
  var proposal:Dictionary=Plan.boss_approach_proposal(b)
  if not check(proposal.get("status")=="manual" and proposal.get("stage")=="waiting_boss" and not proposal.has("step") and not proposal.has("auto_choices"),"read-only arrival stops before human confirmation"):return false
  if not check(b.session.snapshot()==before and b.quest_arrival.has_arrival(b,10701,b.automation.position_cell),"actual original saton arrival retained without proposal mutation"):return false
  var npc:Dictionary=b.quest_catalog.active_npc(target.id)
  if not check(b.quest_arrival.check_action(b,npc,b.original_quests.branch_for(npc,b.session._profile),"BATTLE").is_empty(),"read-only original action qualification accepts actual endpoint"):return false
  done=true;events.append({"manual_boundary":proposal,"state":state()});return true
 if not check(walked+portals<3000,"3000 logical-point route limit"):return false
 var origin:Dictionary=state()
 var point:Dictionary=nav.next(b,target)
 if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
 if not check(not point.is_empty(),"original next returns a point"):return false
 var valid:bool=nav.validate(b,point)
 events.append({"origin":origin,"point":point.duplicate(true),"validate":valid})
 if not valid:first_failure={"kind":"validate_rejected","origin":origin,"point":point.duplicate(true)}
 if not check(valid,"original validate accepts next point"):return false
 var changed:bool=int(point.map_id)!=b.automation.position_map
 if point.has("portal"):
  var locked:bool=Plan.reviewed_boss_portal(b,point)
  events[-1].source_matches=locked
  if not locked:
   var table:Dictionary=Plan.boss_source_table()
   var expected:Dictionary={}
   for row in table.get("doors",[]):
    if str(row.row.get("source",""))==str(point.portal.get("source","")):expected=row.row
   var difference:Dictionary={"reason":"source identity not in locked doors"}
   for field in expected:
    if not point.portal.has(field) or not Plan.same_source(point.portal[field],expected[field]):
     difference={"field":field,"expected":expected[field],"actual":point.portal.get(field)};break
   first_failure={"kind":"portal_source_rejected","origin":origin,"point":point.duplicate(true),"expected":expected.duplicate(true),"first_difference":difference}
  if not check(locked,"full original door identity matches locked source"):return false
  var passage:Dictionary=b.handle({"type":"check_passage","from_map":b.automation.position_map,"to_map":int(point.map_id)})
  if not check(passage.get("ok",false),"original passage accepts"):return false
 else:
  if not check(not changed and not point.has("gate") and absi(int(point.cell[0])-b.automation.position_cell.x)+absi(int(point.cell[1])-b.automation.position_cell.y)==1,"one ordinary cardinal walk"):return false
 var moved:Dictionary=b.handle({"type":"report_position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"map_changed":changed,"client":"saton-first-boss"})
 if not check(moved.get("ok",false) and b.automation.position_map==int(point.map_id) and b.automation.position_cell==Vector2i(point.cell[0],point.cell[1]),"actual ordinary movement commits"):return false
 if not check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"natural route preserves actual arrival"):return false
 events[-1].committed=state()
 if point.has("portal"):
  portals+=1
  if nav.entry_active:
   if not check(nav.portal_committed(b,point),"notify only after actual original portal and arrival"):return false
  else:nav.clear()
 else:
  walked+=1
  if b.automation.position_map==10701:protected_walk+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":int(point.map_id),"cell":point.cell.duplicate(),"encounter":true})
  field_calls+=1;events[-1].field=field.duplicate(true)
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"encounter-off compatibility uses each original field step"):return false
 return true
func commission()->bool:
 var proposal:Dictionary=Plan.request_proposal(b)
 if not check(proposal.get("status")=="step","fresh exact REQUEST at actual endpoint"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":proposal.step.npc_id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"original REQUEST opens"):return false
 if not check(Plan.same_source(b.original_quests.pending.branch,proposal.step.source.branch_data),"production pending matches full source"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"only original REQUEST yes commits"):return false
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original REQUEST page closes"):return false
 var loaded=Session.new()
 if not check(loaded.load_game(b.save_path) and loaded.snapshot().original_events==b.session.snapshot().original_events and loaded.snapshot().original_items==b.session.snapshot().original_items,"read normal transaction items/events without restoring stale location"):return false
 commissioned=true;events.append({"transaction":"request","state":state(),"items":b.session.snapshot().original_items.duplicate()})
 var before:Dictionary=b.session.snapshot()
 var version:int=b.original_quests.npc_state.version
 var approach:Dictionary=Plan.boss_approach_proposal(b)
 if not check(approach.get("status")=="approach" and not approach.has("step") and not approach.has("auto_choices"),"earned request permits only geometry target"):return false
 if not check(b.session.snapshot()==before and b.original_quests.npc_state.version==version,"approach proposal has no profile/spawn side effects"):return false
 # Restore this isolated source mutation before any route step.
 for raw in b.quest_catalog.npcs:
  if raw.id==approach.target.id:
   var saved:Array=raw.cell.duplicate()
   raw.cell[0]+=1
   var denied:Dictionary=Plan.boss_approach_proposal(b)
   raw.cell=saved
   if not check(denied.get("status")=="manual","raw Boss source drift rejects approach"):return false
 target=approach.target.duplicate(true);nav.clear()
 return true
func finish()->void:
 write_trace()
 print("SATON FIRST BOSS: walked=%d portals=%d fields=%d protected=%d done=%s"%[walked,portals,field_calls,protected_walk,str(done)])
 b.free()
 print("quest_auto_saton_first_boss_route_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
