extends SceneTree
## UNRUN: public manifest spawn to exact original flower ACCEPT; no job runner.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_jan_plan.gd")
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
var assertions:int=0
var failures:int=0
var failed:bool=false
var walked:int=0
var fields:int=0
var target:Dictionary={}
var trace:Array=[]
var first_failure:Dictionary={}
func _initialize()->void:call_deferred("run")
func state()->Dictionary:
 return {"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true)}
func write_trace()->void:
 var f=FileAccess.open("user://jan-flower-route-trace.json",FileAccess.WRITE)
 if f:f.store_string(JSON.stringify({"trace":trace,"navigation":nav.calls,"first_failure":first_failure,"walked":walked,"fields":fields},"  "));f.close()
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:
  failures+=1;failed=true
  if first_failure.is_empty():first_failure={"label":label,"state":state(),"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
  write_trace();push_error(label)
 return ok
# Complete persisted-profile comparison: exact finite numeric values, including
# legitimate fractions; no rounding/tolerance/omitted fields or array reordering.
func saved_equal(a:Variant,c:Variant)->bool:
 if a is bool or c is bool:return a is bool and c is bool and a==c
 if a is int or a is float:return (c is int or c is float) and is_finite(float(a)) and is_finite(float(c)) and a==c
 if a is Dictionary and c is Dictionary:
  if a.size()!=c.size():return false
  for key in a:
   if not c.has(key) or not saved_equal(a[key],c[key]):return false
  return true
 if a is Array and c is Array:
  if a.size()!=c.size():return false
  for index in range(a.size()):
   if not saved_equal(a[index],c[index]):return false
  return true
 return typeof(a)==typeof(c) and a==c
func near()->bool:
 var offset:Vector2i=b.automation.position_cell-Vector2i(target.cell[0],target.cell[1])
 return b.automation.position_map==3400 and maxi(absi(offset.x),absi(offset.y))<=2
func run()->void:
 b=Backend.new()
 var metadata:Dictionary=b.session.world_catalog.maps.get("3400",{})
 if not check(metadata.get("kind")=="village" and metadata.get("path")=="world/3400.map" and int(metadata.get("width",0))==120 and int(metadata.get("height",0))==120 and Plan.same_source(metadata.get("spawn"),[60,41]),"locked public manifest village spawn, not guessed NPC neighbour"):finish();return
 # Exact original incoming portal target, used only as a disclosed public fixture.
 # This does not claim an actual journey from200 or confer protected arrival.
 b.automation.position_changed(3400,Vector2i(60,41),true,"project")
 b.save_path="user://jan-flower-route.json"
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"original no-random compatibility setting saves"):finish();return
 var initial:Dictionary=b.session.snapshot()
 if not check(initial.original_items.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no flower or protected proof injected"):finish();return
 if not check(Plan.same_source(initial.original_events,{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]}),"no initial task flags injected"):finish();return
 b.original_quests.refresh_npc_state()
 var proposal:Dictionary=Plan.flower_proposal(b,27)
 if not check(proposal.get("status")=="step","exact original flower proposal at public origin"):finish();return
 target={"id":proposal.step.npc_id,"map_id":proposal.step.map_id,"cell":proposal.step.cell.duplicate()}
 var reached:bool=await Wait.until(self,advance)
 if failed:finish();return
 if not check(reached and near() and walked>0 and fields==walked,"original public A approach reaches talk range with every field step"):finish();return
 var before:Dictionary=b.session.snapshot()
 var current:Dictionary=Plan.flower_proposal(b,27)
 if not check(current.get("status")=="step" and current.step.source.type=="ACCEPT" and current.step.source.branch_data.event==-1 and current.step.source.actions=={"GetItem":"2486"},"fresh exact source branch2, never original delete branch3"):finish();return
 var npc:Dictionary=b.quest_catalog.active_npc(target.id)
 if not check(b.quest_arrival.check_action(b,npc,current.step.source.branch_data,"ACCEPT").is_empty(),"actual ordinary arrival accepts flower transaction"):finish();return
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"original Kai talk opens"):finish();return
 if not check(Plan.same_source(b.original_quests.pending.branch,current.step.source.branch_data),"full pending original branch2 before confirmation"):finish();return
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original ACCEPT yes commits flower"):finish();return
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original final page closes"):finish();return
 var earned:Dictionary=b.session.snapshot()
 if not check(earned.original_items.size()==before.original_items.size()+1 and earned.original_items.count(2486)==1 and earned.original_instances.size()==before.original_instances.size()+1 and int(earned.original_instances[-1].item_id)==2486 and int(earned.original_instances[-1].uid)==int(before.next_original_uid) and int(earned.next_original_uid)==int(before.next_original_uid)+1,"exact original flower and new instance allocated once"):finish();return
 var left:Dictionary=before.duplicate(true)
 var right:Dictionary=earned.duplicate(true)
 for key in ["original_items","original_instances","next_original_uid"]:
  left.erase(key);right.erase(key)
 if not check(saved_equal(left,right),"no other profile field or quest flag changed by event-1 ACCEPT"):finish();return
 var disk=Session.new()
 if not check(disk.load_game(b.save_path),"normal transaction saved readable profile"):finish();return
 var persisted:Dictionary=disk.snapshot()
 if not check(saved_equal(persisted,earned),"complete normal saved profile readback, no extra save"):finish();return
 var next:Dictionary=Plan.flower_proposal(b,27)
 if not check(next.get("status")=="manual" and next.get("stage")=="request20","stop at manual Gide request without revisiting delete-flower branch"):finish();return
 if not check(not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty(),"no open battle/dialogue or acquired protected proof"):finish();return
 trace.append({"transaction":"flower2486","state":state(),"before":before,"earned":earned,"persisted":persisted,"next":next,"disk_location":persisted.get("location",{})})
 finish()
func advance()->bool:
 if near():return true
 if not check(walked<200,"200 logical neighbour limit"):return true
 var origin:Dictionary=state()
 var point:Dictionary=nav.next(b,target)
 if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
 if not check(not point.is_empty(),"original next returns point"):return true
 var valid:bool=nav.validate(b,point)
 trace.append({"origin":origin,"point":point.duplicate(true),"validate":valid})
 if not valid:first_failure={"kind":"validate_rejected","origin":origin,"point":point.duplicate(true)}
 if not check(valid,"original validate accepts current point"):return true
 var delta:Vector2i=Vector2i(point.cell[0],point.cell[1])-b.automation.position_cell
 if not check(int(point.map_id)==3400 and not point.has("portal") and not point.has("gate") and absi(delta.x)+absi(delta.y)==1,"ordinary cardinal village walk only, no door shortcuts"):return true
 var result:Dictionary=b.handle({"type":"report_position","map_id":3400,"cell":point.cell.duplicate(),"client":"jan-flower-route"})
 if not check(result.get("ok",false) and b.automation.position_map==3400 and b.automation.position_cell==Vector2i(point.cell[0],point.cell[1]),"actual ordinary authority commits neighbour"):return true
 walked+=1
 var field:Dictionary=b.handle({"type":"field_step","map_id":3400,"cell":point.cell.duplicate(),"encounter":true})
 fields+=1;trace[-1].field=field.duplicate(true);trace[-1].committed=state()
 if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"each original field call in explicit no-random mode"):return true
 return near()
func finish()->void:
 write_trace()
 print("JAN FLOWER ROUTE: walked=%d fields=%d failed=%s"%[walked,fields,str(failed)])
 b.free()
 print("quest_auto_jan_flower_route_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
