extends SceneTree
## UNRUN six-floor direct-Backend route; no pet UID/consume/reward operation.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_doctor_plan.gd")
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
var walked:=0
var portals:=0
var field_calls:=0
var protected_walk:=0
var target:Dictionary={}
var events:Array=[]
var first_failure:Dictionary={}
var source:Dictionary={}
var initial:Dictionary={}
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
 var f=FileAccess.open("user://doctor-request-route-trace.json",FileAccess.WRITE)
 if f:f.store_string(JSON.stringify({"events":events,"navigation":nav.calls,"first_failure":first_failure,"walked":walked,"portals":portals,"field_calls":field_calls,"protected_walk":protected_walk,"done":done},"  "));f.close()
func reviewed_portal(point:Dictionary)->bool:
 if not point.get("portal") is Dictionary:return false
 var link:Dictionary=point.portal
 if bool(link.get("disabled",false)) or link.has("gate_source"):return false
 for original in source.get("doors",[]):
  if bool(original.get("disabled",false)):continue
  if Plan.same_source(link,original) and Plan.same_source(point.get("cell"),original.target):
   return b.automation.position_map==int(original.from_map) and b.automation.position_cell==Vector2i(original.cell[0],original.cell[1]) and int(point.get("map_id",-1))==int(original.to_map)
 return false
func run()->void:
 b=Backend.new()
 b.session._profile.player.level=10
 # Fixed north-adjacent public cell of the original root328,633. No geometry
 # pre-search selects a passing spawn; failure preserves this exact fixture.
 b.automation.position_changed(100,Vector2i(328,632),true,"project")
 b.save_path="user://doctor-request-route.json"
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"original encounter-off compatibility setting saves"):finish();return
 initial=b.session.snapshot()
 if not check(not Rules.flag(initial,"now",15) and not Rules.flag(initial,"now",16) and not Rules.flag(initial,"ended",15) and not Rules.flag(initial,"ended",16),"fresh Doctor flags, no injected completed prerequisite"):finish();return
 source=Plan.source_table()
 if not check(not source.is_empty() and source.doors.size()==14,"full14 original edges including disabled alternative retained"):finish();return
 var rejected:=0
 for door in source.doors:
  if bool(door.get("disabled",false)):
   rejected+=1
   if not check(not reviewed_portal({"map_id":door.to_map,"cell":door.target.duplicate(),"portal":door.duplicate(true)}),"disabled original alternate never accepted"):finish();return
 if not check(rejected==1,"only reviewed1222 alternate is disabled"):finish();return
 b.original_quests.refresh_npc_state()
 var request:Dictionary=Plan.request_proposal(b,6)
 if not check(request.get("status")=="step" and request.step.source.actions.is_empty(),"actual empty-action REQUEST15 proposal"):finish();return
 target={"id":request.step.npc_id,"map_id":request.step.map_id,"cell":request.step.cell.duplicate()}
 var reached:bool=await Wait.until(self,drive,120.0)
 if failed:finish();return
 if not check(reached and done,"six-floor request reaches explicit condition deadline"):finish();return
 if not check(portals==6 and protected_walk>0 and field_calls==walked,"root plus five stairs and original protected field steps"):finish();return
 if not check(not b.battle_open and b.session._pending.is_empty() and b.original_quests.pending.is_empty(),"no battle/pet exchange/dialogue remains open"):finish();return
 finish()
func drive()->bool:
 for _index in range(16):
  if failed or done:return true
  if not advance():return true
 return failed or done
func near()->bool:
 var offset:Vector2i=b.automation.position_cell-Vector2i(target.cell[0],target.cell[1])
 return b.automation.position_map==int(target.map_id) and maxi(absi(offset.x),absi(offset.y))<=2
func advance()->bool:
 if near():return request_transaction()
 if not check(walked+portals<3000,"3000 logical-point hard limit"):return false
 var origin:Dictionary=state()
 var point:Dictionary=nav.next(b,target)
 if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
 if not check(not point.is_empty(),"original next produces a point"):return false
 var valid:bool=nav.validate(b,point)
 events.append({"origin":origin,"point":point.duplicate(true),"validate":valid})
 if not valid:first_failure={"kind":"validate_rejected","origin":origin,"point":point.duplicate(true)}
 if not check(valid,"original validate accepts next point"):return false
 var changed:bool=int(point.map_id)!=b.automation.position_map
 if point.has("portal"):
  var locked:bool=reviewed_portal(point)
  events[-1].source_matches=locked
  if not locked:
   var expected:Dictionary={}
   for row in source.doors:
    if str(row.get("source",""))==str(point.portal.get("source","")):expected=row
   first_failure={"kind":"portal_source_rejected","origin":origin,"point":point.duplicate(true),"expected":expected.duplicate(true)}
  if not check(locked,"exact enabled source edge accepts; no alternate fallback"):return false
  if origin.map_id==100:
   for row in source.doors:
    if bool(row.get("disabled",false)):
     if not check(not reviewed_portal({"map_id":row.to_map,"cell":row.target.duplicate(),"portal":row.duplicate(true)}),"disabled1222 rejected at actual same source cell"):return false
  var passage:Dictionary=b.handle({"type":"check_passage","from_map":b.automation.position_map,"to_map":int(point.map_id)})
  if not check(passage.get("ok",false),"original passage passes"):return false
 else:
  if not check(not changed and not point.has("gate") and absi(int(point.cell[0])-b.automation.position_cell.x)+absi(int(point.cell[1])-b.automation.position_cell.y)==1,"one cardinal original walk"):return false
 var moved:Dictionary=b.handle({"type":"report_position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"map_changed":changed,"client":"doctor-request-route"})
 if not check(moved.get("ok",false) and b.automation.position_map==int(point.map_id) and b.automation.position_cell==Vector2i(point.cell[0],point.cell[1]),"ordinary authority commits exact source point"):return false
 if not check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"natural original root/walk retains Doctor qualification"):return false
 events[-1].committed=state()
 if point.has("portal"):
  portals+=1
  if nav.entry_active:
   if not check(nav.portal_committed(b,point),"notify only after actual original portal/arrival"):return false
  else:nav.clear()
 else:
  walked+=1
  if b.automation.position_map>=11001 and b.automation.position_map<=11006:protected_walk+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":int(point.map_id),"cell":point.cell.duplicate(),"encounter":true})
  field_calls+=1;events[-1].field=field.duplicate(true)
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"each original field step in explicit no-random compatibility mode"):return false
 return true
func request_transaction()->bool:
 var proposal:Dictionary=Plan.request_proposal(b,6)
 if not check(proposal.get("status")=="step" and proposal.step.source.actions=={},"fresh exact empty-action REQUEST at earned six-floor endpoint"):return false
 var npc:Dictionary=b.quest_catalog.active_npc(target.id)
 if not check(b.quest_arrival.check_action(b,npc,proposal.step.source.branch_data,"REQUEST").is_empty(),"actual original qualification accepts REQUEST"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"real Doctor REQUEST opens"):return false
 if not check(Plan.same_source(b.original_quests.pending.branch,proposal.step.source.branch_data),"full original branch matches before yes"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original empty actions still commit NOW15"):return false
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original final page closes"):return false
 var earned:Dictionary=b.session.snapshot()
 if not check(Rules.flag(earned,"now",15) and not Rules.flag(earned,"now",16) and not Rules.flag(earned,"ended",15) and not Rules.flag(earned,"ended",16),"only real NOW15 created"):return false
 if not check(earned.pets==initial.pets and earned.original_items==initial.original_items and earned.inventory==initial.inventory,"no pet UID/DelPet/GetPet/reward transaction"):return false
 var loaded=Session.new()
 if not check(loaded.load_game(b.save_path) and loaded.snapshot().original_events==earned.original_events and loaded.snapshot().pets==earned.pets and loaded.snapshot().original_items==earned.original_items,"normal REQUEST save readback without extra save or reposition"):return false
 var next:Dictionary=Plan.request_proposal(b,6)
 if not check(next.get("status")=="manual" and next.get("stage")=="manual_uid","stop before any UID selection or consumption"):return false
 events.append({"transaction":"request15","state":state(),"events":earned.original_events.duplicate(true),"next":next,"disk_location":loaded.snapshot().get("location",{})})
 done=true;return true
func finish()->void:
 write_trace()
 print("DOCTOR REQUEST ROUTE: walked=%d portals=%d fields=%d protected=%d done=%s"%[walked,portals,field_calls,protected_walk,str(done)])
 b.free()
 print("quest_auto_doctor_request_route_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
