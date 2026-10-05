extends SceneTree
## UNRUN: same Backend earns flower, submits REQUEST20, then claims original token.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_jan_plan.gd")
const Session=preload("res://server/game_session.gd")
const Rules=preload("res://server/original_quests.gd")
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
var portals:int=0
var flower_walked:int=0
var request_walked:int=0
var phase:String="flower"
var done:bool=false
var flower_uid:int=-1
var source:Dictionary={}
var transaction_trace:Dictionary={}
var target:Dictionary={}
var trace:Array=[]
var first_failure:Dictionary={}
func _initialize()->void:call_deferred("run")
func state()->Dictionary:
 return {"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true)}
func write_trace()->void:
 var f=FileAccess.open("user://jan-token-route-trace.json",FileAccess.WRITE)
 if f:f.store_string(JSON.stringify({"trace":trace,"navigation":nav.calls,"first_failure":first_failure,"walked":walked,"fields":fields,"portals":portals,"flower_walked":flower_walked,"request_walked":request_walked,"phase":phase,"done":done,"transaction_trace":transaction_trace,"profile":b.session.snapshot(),"pending":b.original_quests.pending.duplicate(true)},"  "));f.close()
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
 return b.automation.position_map==int(target.map_id) and maxi(absi(offset.x),absi(offset.y))<=2
func run()->void:
 b=Backend.new()
 var metadata:Dictionary=b.session.world_catalog.maps.get("3400",{})
 if not check(metadata.get("kind")=="village" and metadata.get("path")=="world/3400.map" and int(metadata.get("width",0))==120 and int(metadata.get("height",0))==120 and Plan.same_source(metadata.get("spawn"),[60,41]),"locked public manifest village spawn, not guessed NPC neighbour"):finish();return
 # Exact original incoming portal target, used only as a disclosed public fixture.
 # This does not claim an actual journey from200 or confer protected arrival.
 b.automation.position_changed(3400,Vector2i(60,41),true,"project")
 b.save_path="user://jan-token-route.json"
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"original no-random compatibility setting saves"):finish();return
 var initial:Dictionary=b.session.snapshot()
 if not check(initial.original_items.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no flower or protected proof injected"):finish();return
 if not check(Plan.same_source(initial.original_events,{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]}),"no initial task flags injected"):finish();return
 source=Plan.request_source_table()
 if not check(not source.is_empty() and source.house_doors.size()==3,"three complete original house identities locked"):finish();return
 if not check(doors_match(),"live original house doors match full source before travel"):finish();return
 b.original_quests.refresh_npc_state()
 var proposal:Dictionary=Plan.flower_proposal(b,27)
 if not check(proposal.get("status")=="step","exact original flower proposal at public origin"):finish();return
 target={"id":proposal.step.npc_id,"map_id":proposal.step.map_id,"cell":proposal.step.cell.duplicate()}
 var reached:bool=await Wait.until(self,drive)
 if failed:finish();return
 if not check(reached and done and fields==walked and portals==1 and flower_walked>0 and walked>flower_walked,"three transactions and one original house portal completed within shared Wait60"):finish();return
 finish()
func drive()->bool:
 if failed or done:return true
 if near():
  if phase=="flower":
   if not flower_transaction():return true
  elif phase=="request20":
   if not request_transaction():return true
  elif not token_transaction():return true
 else:
  if not advance():return true
 return failed or done
func flower_transaction()->bool:
 var before:Dictionary=b.session.snapshot()
 transaction_trace={"phase":"flower","before":before,"state":state()}
 var current:Dictionary=Plan.flower_proposal(b,27)
 if not check(current.get("status")=="step" and current.step.source.type=="ACCEPT" and current.step.source.branch_data.event==-1 and current.step.source.actions=={"GetItem":"2486"},"fresh exact source branch2, never original delete branch3"):return false
 var npc:Dictionary=b.quest_catalog.active_npc(target.id)
 if not check(b.quest_arrival.check_action(b,npc,current.step.source.branch_data,"ACCEPT").is_empty(),"actual ordinary arrival accepts flower transaction"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"original Kai talk opens"):return false
 if not check(Plan.same_source(b.original_quests.pending.branch,current.step.source.branch_data),"full pending original branch2 before confirmation"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original ACCEPT yes commits flower"):return false
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original final page closes"):return false
 var earned:Dictionary=b.session.snapshot()
 transaction_trace.earned=earned
 if not check(earned.original_items.size()==before.original_items.size()+1 and earned.original_items.count(2486)==1 and earned.original_instances.size()==before.original_instances.size()+1 and int(earned.original_instances[-1].item_id)==2486 and int(earned.original_instances[-1].uid)==int(before.next_original_uid) and int(earned.next_original_uid)==int(before.next_original_uid)+1,"exact original flower and new instance allocated once"):return false
 var left:Dictionary=before.duplicate(true)
 var right:Dictionary=earned.duplicate(true)
 for key in ["original_items","original_instances","next_original_uid"]:
  left.erase(key);right.erase(key)
 if not check(saved_equal(left,right),"no other profile field or quest flag changed by event-1 ACCEPT"):return false
 var disk=Session.new()
 if not check(disk.load_game(b.save_path),"normal transaction saved readable profile"):return false
 var persisted:Dictionary=disk.snapshot()
 if not check(saved_equal(persisted,earned),"complete normal saved profile readback, no extra save"):return false
 var next:Dictionary=Plan.flower_proposal(b,27)
 if not check(next.get("status")=="manual" and next.get("stage")=="request20","stop at manual Gide request without revisiting delete-flower branch"):return false
 if not check(not b.battle_open and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty(),"no open battle/dialogue or acquired protected proof"):return false
 trace.append({"transaction":"flower2486","state":state(),"before":before,"earned":earned,"persisted":persisted,"next":next,"disk_location":persisted.get("location",{})})
 flower_uid=int(earned.original_instances[-1].uid)
 flower_walked=walked
 var request:Dictionary=Plan.request_proposal(b,27)
 if not check(request.get("status")=="step","earned original flower enables next REQUEST proposal without injection"):return false
 phase="request20"
 target={"id":request.step.npc_id,"map_id":request.step.map_id,"cell":request.step.cell.duplicate()}
 nav.clear()
 return true
func doors_match()->bool:
 for row in source.house_doors:
  if row.get("disabled",false) or row.has("gate_source"):return false
  var link:Dictionary=b.quest_helper.places.links(int(row.from_map)).get(Vector2i(row.cell[0],row.cell[1]),{})
  if not Plan.same_source(link,row):return false
 return true
func reviewed_portal(point:Dictionary)->bool:
 if phase!="request20" or portals!=0 or not point.get("portal") is Dictionary:return false
 var link:Dictionary=point.portal
 if link.get("disabled",false) or link.has("gate_source"):return false
 for row in source.house_doors:
  if str(row.source)!="warp_y2.create:1402":continue
  return Plan.same_source(link,row) and int(point.map_id)==3406 and Plan.same_source(point.cell,row.target) and b.automation.position_map==3400 and b.automation.position_cell==Vector2i(54,62)
 return false
func advance()->bool:
 if not check(walked+portals<500 and (phase!="flower" or walked<200),"500 total points and original flower200-neighbour limits"):return false
 var origin:Dictionary=state()
 var point:Dictionary=nav.next(b,target)
 if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"target":target.duplicate(true),"remaining":nav.route.duplicate(true)}
 if not check(not point.is_empty(),"original next returns point"):return false
 var valid:bool=nav.validate(b,point)
 trace.append({"phase":phase,"origin":origin,"point":point.duplicate(true),"validate":valid})
 if not valid:first_failure={"kind":"validate_rejected","origin":origin,"point":point.duplicate(true)}
 if not check(valid,"original validate accepts current point"):return false
 var changed:bool=int(point.map_id)!=b.automation.position_map
 if point.has("portal"):
  var locked:bool=doors_match() and reviewed_portal(point) and not point.has("gate")
  trace[-1].source_matches=locked
  if not locked:first_failure={"kind":"portal_identity_rejected","origin":origin,"point":point.duplicate(true),"expected":source.house_doors.duplicate(true)}
  if not check(locked,"only actual1402 original house entrance, no alternate door"):return false
  if not check(b.handle({"type":"check_passage","from_map":3400,"to_map":3406}).get("ok",false),"original house passage accepts"):return false
 else:
  var delta:Vector2i=Vector2i(point.cell[0],point.cell[1])-b.automation.position_cell
  if not check(not changed and int(point.map_id) in [3400,3406] and (phase!="flower" or int(point.map_id)==3400) and (phase!="token" or int(point.map_id)==3406) and not point.has("gate") and absi(delta.x)+absi(delta.y)==1,"one ordinary cardinal walk, no script/gate/relocation"):return false
 var result:Dictionary=b.handle({"type":"report_position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"map_changed":changed,"client":"jan-token-route"})
 if not check(result.get("ok",false) and b.automation.position_map==int(point.map_id) and b.automation.position_cell==Vector2i(point.cell[0],point.cell[1]),"actual ordinary authority commits original point"):return false
 if not check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"current original arrival independently accepts after movement"):return false
 trace[-1].committed=state()
 if point.has("portal"):
  portals+=1
  # Direct Backend harness, not proof of runner pre/post-move ownership safety.
  if not check(nav.portal_committed(b,point),"notify only after original1402 commits actual10,15 and arrival"):return false
 else:
  walked+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":int(point.map_id),"cell":point.cell.duplicate(),"encounter":true})
  fields+=1;trace[-1].field=field.duplicate(true)
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"each original field call in explicit no-random mode"):return false
 return true
func request_transaction()->bool:
 var before:Dictionary=b.session.snapshot()
 transaction_trace={"phase":"request20","before":before,"state":state()}
 if not check(portals==1 and flower_uid>0 and before.original_items.count(2486)==1 and before.original_instances.size()==1 and int(before.original_instances[0].uid)==flower_uid and int(before.original_instances[0].item_id)==2486,"same actual flower instance survives original journey"):return false
 var proposal:Dictionary=Plan.request_proposal(b,27)
 if not check(proposal.get("status")=="step" and proposal.step.npc_id==Plan.REQUEST_NPC and proposal.step.source.actions=={"DelItem":"2486"} and proposal.step.source.branch_index==1,"fresh exact Gide REQUEST, no son or letter action"):return false
 var npc:Dictionary=b.quest_catalog.active_npc(target.id)
 if not check(b.quest_arrival.check_action(b,npc,proposal.step.source.branch_data,"REQUEST").is_empty(),"actual house endpoint satisfies original action check"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"real Gide REQUEST opens"):return false
 if not check(Plan.same_source(b.original_quests.pending.branch,proposal.step.source.branch_data),"complete original branch1 still matches before confirmation"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"real REQUEST deletes original flower and commits NOW20"):return false
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original REQUEST final page closes"):return false
 var earned:Dictionary=b.session.snapshot()
 transaction_trace.earned=earned
 if not check(earned.original_items.is_empty() and earned.original_instances.is_empty() and earned.next_original_uid==before.next_original_uid and Rules.flag(earned,"now",20) and not Rules.flag(earned,"ended",20),"earned flower UID removed once, NOW20 not END20"):return false
 # Expected snapshot only: never assign this copy to live profile or save it.
 var expected:Dictionary=before.duplicate(true)
 expected.original_items=[];expected.original_instances=[]
 Rules.set_flag(expected,"now",20,true)
 if not check(saved_equal(earned,expected),"complete profile changed only by consumed flower/instance and NOW20"):return false
 var disk=Session.new()
 if not check(disk.load_game(b.save_path),"normal REQUEST transaction saved readable profile"):return false
 var persisted:Dictionary=disk.snapshot()
 transaction_trace.persisted=persisted;transaction_trace.disk_location=persisted.get("location",{})
 if not check(saved_equal(persisted,earned),"complete normal REQUEST readback, no extra save or restored authority"):return false
 var next:Dictionary=Plan.request_proposal(b,27)
 transaction_trace.next=next
 if not check(next.get("status")=="manual" and next.get("stage")=="claim_token" and not next.has("step"),"stop before son's2487/keyword/Charm/Boss/parent chain"):return false
 if not check(not b.battle_open and not b.quest_auto.running and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no pending operation or fabricated protected proof"):return false
 trace.append(transaction_trace.duplicate(true))
 request_walked=walked
 var token:Dictionary=Plan.token_proposal(b,27)
 if not check(token.get("status")=="step","actual REQUEST NOW20 enables son proposal without injected flags"):return false
 phase="token"
 target={"id":token.step.npc_id,"map_id":token.step.map_id,"cell":token.step.cell.duplicate()}
 nav.clear()
 return true
func token_transaction()->bool:
 var before:Dictionary=b.session.snapshot()
 transaction_trace={"phase":"token","before":before,"state":state()}
 if not check(Rules.flag(before,"now",20) and not Rules.flag(before,"ended",20) and before.original_items.is_empty() and before.original_instances.is_empty() and flower_uid>0 and int(before.next_original_uid)>flower_uid,"actual same Backend REQUEST consumed flower and retained NOW20"):return false
 var proposal:Dictionary=Plan.token_proposal(b,27)
 if not check(proposal.get("status")=="step" and proposal.step.npc_id==Plan.TOKEN_NPC and proposal.step.source.actions=={"GetItem":"2487"} and proposal.step.source.branch_index==0 and proposal.step.source.source_line==6,"fresh son branch0 only; no Charm or other reward"):return false
 var npc:Dictionary=b.quest_catalog.active_npc(target.id)
 if not check(b.quest_arrival.check_action(b,npc,proposal.step.source.branch_data,"ACCEPT").is_empty(),"actual son endpoint satisfies original action check"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"real son token ACCEPT opens"):return false
 if not check(Plan.same_source(b.original_quests.pending.branch,proposal.step.source.branch_data),"full original token branch before confirmation"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"real original ACCEPT gives token"):return false
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original token final page closes"):return false
 var earned:Dictionary=b.session.snapshot()
 transaction_trace.earned=earned
 if not check(earned.original_items.size()==before.original_items.size()+1 and earned.original_items.count(2487)==1 and earned.original_instances.size()==before.original_instances.size()+1 and int(earned.original_instances[-1].item_id)==2487 and int(earned.original_instances[-1].uid)==int(before.next_original_uid) and int(earned.next_original_uid)==int(before.next_original_uid)+1,"one original token UID derived from actual before, never hardcoded or injected"):return false
 var left:Dictionary=before.duplicate(true)
 var right:Dictionary=earned.duplicate(true)
 for key in ["original_items","original_instances","next_original_uid"]:
  left.erase(key);right.erase(key)
 if not check(saved_equal(left,right),"every other profile field unchanged: NOW/END, charm, equipment, gold, pets"):return false
 var disk=Session.new()
 if not check(disk.load_game(b.save_path),"normal token transaction saved readable profile"):return false
 var persisted:Dictionary=disk.snapshot()
 transaction_trace.persisted=persisted;transaction_trace.disk_location=persisted.get("location",{})
 if not check(saved_equal(persisted,earned),"complete token profile readback without extra save"):return false
 var next:Dictionary=Plan.token_proposal(b,27)
 transaction_trace.next=next
 if not check(next.get("status")=="manual" and next.get("stage")=="keyword_boss_return" and not next.has("step"),"stop before keyword Charm Boss parent chain or reward"):return false
 if not check(not b.battle_open and not b.quest_auto.running and b.original_quests.pending.is_empty() and b.session._pending.is_empty() and b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"no open operations or fabricated proof after token"):return false
 trace.append(transaction_trace.duplicate(true));done=true;return true
func finish()->void:
 write_trace()
 print("JAN TOKEN ROUTE: walked=%d flower_walked=%d request_walked=%d portals=%d fields=%d done=%s failed=%s"%[walked,flower_walked,request_walked,portals,fields,str(done),str(failed)])
 b.free()
 print("quest_auto_jan_token_route_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
