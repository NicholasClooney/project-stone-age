extends SceneTree
## UNRUN production A-route + original transactions, encounter-off compatibility.
## No task item/flag/proof injection; no registration or generic source service hook.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_harn_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Nav=preload("res://server/quest_auto_navigation.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
const Wait=preload("res://tests/support/wait.gd")
class ObservedNav:
 extends "res://server/quest_auto_navigation.gd"
 var observations:Array=[]
 func entry_metrics()->Dictionary:
  return {"searches":entry_routes.searches,"context_copies":entry_routes.context_copies,"last_reason":entry_routes.last_reason,"last_search_visited":entry_routes.visited_cells,"last_search_output":entry_routes.output_points,"last_search_loaded":entry_routes.loaded_cells,"last_search_edges":entry_routes.edge_count}
 func state(b)->Dictionary:
  return {"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true),"npc_version":b.original_quests.npc_state.version,"overrides":b.quest_catalog.npc_overrides.duplicate(true),"enabled_events":b.quest_catalog.enabled_events.duplicate()}
 func map_route(b,origin:int,goal:int)->Array:
  var result:Array=super.map_route(b,origin,goal)
  observations.append({"call":"map_route","origin":origin,"goal":goal,"result":result.duplicate(true)})
  return result
 func usable(b,link:Dictionary)->bool:
  var result:bool=super.usable(b,link)
  if int(link.get("from_map",-1))==b.automation.position_map:
   observations.append({"call":"usable","link":link.duplicate(true),"result":result})
  return result
 func local_path(b,map_id:int,origin:Vector2i,goal:Vector2i,occupied:Dictionary)->Array:
  var before:Dictionary=state(b)
  var used_occupied:Array=[]
  for cell in occupied:used_occupied.append([cell.x,cell.y])
  var result:Array=super.local_path(b,map_id,origin,goal,occupied)
  var endpoints:Array=[]
  # Only inspect the grid already loaded by this actual call; no load/search.
  var grid:Dictionary=maps.get(map_id,{})
  for cell in [origin,goal]:
   var inside:bool=not grid.is_empty() and cell.x>=0 and cell.y>=0 and cell.x<int(grid.width) and cell.y<int(grid.height)
   endpoints.append({"cell":[cell.x,cell.y],"inside":inside,"blocked":int(grid.blocked[cell.y*int(grid.width)+cell.x]) if inside else -1,"occupied":occupied.has(cell)})
  observations.append({"call":"local_path","before":before,"map_id":map_id,"origin":[origin.x,origin.y],"goal":[goal.x,goal.y],"occupied":used_occupied,"endpoints":endpoints,"result":result.duplicate(true)})
  return result
 func plan(b,target:Dictionary)->Array:
  var before:Dictionary=state(b)
  var result:Array=super.plan(b,target)
  observations.append({"call":"plan","before":before,"target":target.duplicate(true),"result":result.duplicate(true),"entry_metrics":entry_metrics()})
  return result
 func validate(b,point:Dictionary)->bool:
  var before:Dictionary=state(b)
  var result:bool=super.validate(b,point)
  observations.append({"call":"validate","before":before,"point":point.duplicate(true),"result":result})
  return result
var assertions:=0
var failures:=0
var b
var nav=ObservedNav.new()
var navigation_failure:Dictionary={}
var selected:Dictionary={}
var npc:Dictionary={}
var transactions:Array=[]
var trace:Array=[]
var proof_trace:Array=[]
var projection_trace:Array=[]
var projection_guards_done:=false
var walked:=0
var protected_walk:=0
var field_calls:=0
var portals:=0
var failed:=false
var done:=false
func check(value:bool,label:String)->bool:
 assertions+=1
 if not value:
  failures+=1;failed=true;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func run()->void:
 b=Backend.new()
 # Same public initial fixture as accepted commission test. Quest state is fresh.
 b.session._profile.player.level=16
 b.automation.position_changed(3300,Vector2i(44,66),true,"project")
 b.save_path="user://harn-axe-route.json"
 # Explicit mode compatibility only; no wild/battle seed or result control.
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"normal encounter-off setting saves"):finish();return
 if not check(not Rules.flag(b.session._profile,"now",18) and not Rules.flag(b.session._profile,"now",19) and not Rules.flag(b.session._profile,"ended",18) and not Rules.flag(b.session._profile,"ended",19) and not [2463,2464,2465,2466].any(func(item):return item in b.session._profile.original_items),"no source quest progress injected"):finish();return
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(19)
 var disabled:Dictionary=Plan.axe_proposal(b)
 b.quest_catalog.enabled_events=enabled
 if not check(disabled.get("status")=="manual","event18 admission cannot authorize disabled event19 actions"):finish();return
 # Proposed route budget: two shared default periods, not a change to Wait.
 var completed:bool=await Wait.until(self,drive,Wait.DEADLINE*2.0)
 if failed:finish();return
 check(completed and done and not failed,"actual axe route completes within declared condition budget")
 if done:
  check(transactions==["commission","request_axe","fill_water","claim_axe"],"exact four earned original transactions, no refill/CLEAN/END18")
  check(Plan.axe_proposal(b)=={"status":"done"},"END19 plus actual axe stops immediately")
  check(Rules.flag(b.session._profile,"ended",19) and b.session._profile.original_items.count(2465)==1,"actual axe reward and END19")
  check(not Rules.flag(b.session._profile,"ended",18) and not [2463,2464,2466,2467,2484].any(func(item):return item in b.session._profile.original_items),"source inputs consumed; no END18 or downstream reward")
  check(protected_walk>0 and portals>0,"real protected walking and independent original portals occurred")
  check(field_calls==walked,"every same-map committed cell called original field_step")
  readback("final")
 finish()
func drive()->bool:
 if failed or done:return true
 # Up to16 sequential original logical cells per poll; no skipped cells/fast mode.
 # This bounds harness scheduling overhead, not game speed or proposal length.
 for _index in range(16):
  if not advance():return true
  if done or failed:return true
 return false
func advance()->bool:
 if selected.is_empty():
  b.original_quests.refresh_npc_state() # Normal lifecycle, outside read-only proposal.
  record_projection("before_proposal")
  if not projection_guards_done and transactions==["commission"]:
   if not projection_guards():return false
   projection_guards_done=true
  var before:Dictionary=b.session.snapshot()
  var version:int=b.original_quests.npc_state.version
  var result:Dictionary=Plan.axe_proposal(b)
  if not check(before==b.session.snapshot() and version==b.original_quests.npc_state.version,"pure exact proposal has no state side effects"):return false
  if result.get("status")=="done":done=true;return true
  if not check(result.get("status")=="step","next reviewed ordinary action: "+str(result)):return false
  selected=result.step
  npc=b.quest_catalog.active_npc(selected.npc_id)
  if not check(not npc.is_empty(),"actual target remains available"):return false
  nav.clear()
 if near():return transact()
 if not check(walked+portals<5000,"logical route upper bound5000; never teleport to progress"):return false
 var point:Dictionary=nav.next(b,npc)
 # Keep original short-circuit: empty next must not trigger a validate call.
 if point.is_empty():
  navigation_failure={"kind":"next_empty","state":nav.state(b),"target":npc.duplicate(true),"remaining":nav.route.duplicate(true),"key":nav.key}
  check(false,"actual production A next returned empty")
  return false
 var valid:bool=nav.validate(b,point)
 if not valid:
  navigation_failure={"kind":"validate_rejected","state":nav.state(b),"target":npc.duplicate(true),"point":point.duplicate(true),"remaining":nav.route.duplicate(true),"key":nav.key}
 if not check(valid,"actual production A validate accepts next point"):return false
 var from_map:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 var target:=Vector2i(int(point.cell[0]),int(point.cell[1]))
 var map_id:int=point.map_id
 var changed:=map_id!=from_map
 if changed:
  if not check(point.has("portal") and Plan.reviewed_portal(b,point),"only exact enabled locked original portal"):return false
  var altered:Dictionary=point.duplicate(true)
  altered.portal.target[0]+=1
  if not check(not Plan.reviewed_portal(b,altered),"changed portal endpoint never gains source permission"):return false
  var passage:Dictionary=b.handle({"type":"check_passage","from_map":from_map,"to_map":map_id})
  if not check(passage.get("ok",false),"original passage permission"):return false
 else:
  if not check(not point.has("gate") and absi(target.x-origin.x)+absi(target.y-origin.y)==1,"one same-map logical neighbour"):return false
 var moved:Dictionary=b.handle({"type":"report_position","map_id":map_id,"cell":[target.x,target.y],"map_changed":changed,"client":"harn-route"})
 if not check(moved.get("ok",false) and b.automation.position_map==map_id and b.automation.position_cell==target,"ordinary actual movement commits next source point"):return false
 if not check(b.quest_arrival.has_arrival(b,map_id,target),"natural original root/walk preserves required proof"):return false
 if changed:
  portals+=1
  trace.append(point.portal.duplicate(true))
  proof_trace.append({"from_map":from_map,"map_id":map_id,"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true)})
  nav.clear()
 else:
  walked+=1
  if not Policy.scope(map_id).is_empty():protected_walk+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":map_id,"cell":[target.x,target.y],"encounter":true})
  field_calls+=1
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"explicit encounter-off compatibility field step"):return false
 return true
func near()->bool:
 return b.automation.position_map==int(npc.map_id) and maxi(absi(b.automation.position_cell.x-int(npc.cell[0])),absi(b.automation.position_cell.y-int(npc.cell[1])))<=2

func projection_guards()->bool:
 var profile_before:Dictionary=b.session.snapshot()
 var version_before:int=b.original_quests.npc_state.version
 var table:Dictionary=Plan.source_table()
 var expected:Dictionary={}
 for candidate in table.npcs:
  if candidate.id=="jaruga/event/20501ev1":expected=candidate
 var active:Dictionary=b.quest_catalog.active_npc(expected.id)
 if not check(expected.branches.size()==10 and active.get("branches",[]).size()==8 and Plan.matches_active(expected,active,b.quest_catalog.enabled_events),"normal full raw10 to active8 projection accepted"):return false
 # A fresh copy cannot contaminate catalog or the subsequent actual route.
 var extra:Dictionary=active.duplicate(true)
 extra.branches.append(expected.branches[8].duplicate(true))
 if not check(not Plan.matches_active(expected,extra,b.quest_catalog.enabled_events),"production comparison rejects extra active branch"):return false
 for raw in b.quest_catalog.npcs:
  if raw.id!=expected.id:continue
  var saved:Dictionary=raw.branches[8].duplicate(true)
  raw.branches[8].actions.GetItem="2465"
  var drift:Dictionary=Plan.axe_proposal(b)
  raw.branches[8]=saved
  if not check(drift.get("stage")=="source_changed","disabled raw branch remains fully source locked"):return false
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 b.quest_catalog.npc_overrides[expected.id]={"map_id":expected.map_id,"cell":[int(expected.cell[0])+1,int(expected.cell[1])]}
 var moved:Dictionary=Plan.axe_proposal(b)
 record_projection("negative_wrong_cell")
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(moved.get("stage")=="source_changed","wrong active cell rejected without moving player"):return false
 b.quest_catalog.npc_overrides[expected.id]={"hidden":true}
 var hidden:Dictionary=Plan.axe_proposal(b)
 record_projection("negative_hidden")
 b.quest_catalog.npc_overrides=overrides.duplicate(true)
 if not check(hidden.get("stage")=="source_changed","hidden active NPC rejected"):return false
 if not check(Plan.same_source(b.quest_catalog.npc_overrides,overrides) and Plan.same_source(b.quest_catalog.active_npc(expected.id),active),"temporary projection fixtures restored before original journey"):return false
 if not check(b.session.snapshot()==profile_before and b.original_quests.npc_state.version==version_before,"projection negatives leave actual profile and NPC state unchanged"):return false
 return check(Plan.axe_proposal(b).get("status")=="step","earned commission permits exact normal request after restoration")

func first_difference(left:Variant,right:Variant,path:String="$")->Dictionary:
 if Plan.same_source(left,right):return {}
 if left is Dictionary and right is Dictionary:
  for key in left:
   if not right.has(key):return {"path":path+"."+str(key),"kind":"missing_active_field","expected":left[key]}
   var child:=first_difference(left[key],right[key],path+"."+str(key))
   if not child.is_empty():return child
  for key in right:
   if not left.has(key):return {"path":path+"."+str(key),"kind":"extra_active_field","active":right[key]}
 if left is Array and right is Array:
  if left.size()!=right.size():return {"path":path+".length","expected":left.size(),"active":right.size()}
  for index in range(left.size()):
   var child:=first_difference(left[index],right[index],path+"[%d]"%index)
   if not child.is_empty():return child
 return {"path":path,"expected":left,"active":right}

func record_projection(label:String)->void:
 # Passive copies only: never npc_by_id/refresh, path search or state mutation.
 var table:Dictionary=Plan.source_table()
 var stage:String=str(Plan.select(b,22).get("stage",""))
 if not table.get("recipes",{}).has(stage):return
 var id:String=str(table.recipes[stage].npc_id)
 for raw in table.npcs:
  if raw.id!=id:continue
  var expected:Dictionary=Plan.expected_active(raw,b.quest_catalog.enabled_events)
  var active:Dictionary=b.quest_catalog.active_npc(id)
  projection_trace.append({"label":label,"stage":stage,"raw":raw.duplicate(true),"expected":expected,"active":active,"first_difference":first_difference(expected,active),"raw_active_first_difference":first_difference(raw,active),"override":b.quest_catalog.npc_overrides.get(id,{}).duplicate(true),"npc_version":b.original_quests.npc_state.version,"enabled_events":b.quest_catalog.enabled_events.duplicate()})
func transact()->bool:
 var fresh:Dictionary=Plan.axe_proposal(b)
 if not check(fresh.get("status")=="step" and Plan.same_source(fresh.step,selected),"exact proposal still matches at actual target"):return false
 if not check(b.quest_arrival.check_action(b,npc,selected.source.branch_data,selected.source.type).is_empty(),"original action arrival guard independently passes"):return false
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":selected.npc_id})
 if not check(opened.get("ok",false) and opened.has("dialogue") and Plan.same_source(b.original_quests.pending.branch,selected.source.branch_data),"actual talk selects complete locked branch"):return false
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original yes response"):return false
 var ok:Dictionary=b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"})
 if not check(ok.get("ok",false) and b.original_quests.pending.is_empty(),"original final page/transaction commits"):return false
 var key:String=str(selected.id).trim_prefix("harn:")
 transactions.append(key)
 if not check(not Rules.flag(b.session._profile,"ended",18),"END18 must never be delivered"):return false
 if not readback(key):return false
 selected={};npc={}
 return true
func readback(label:String)->bool:
 var earned:Dictionary=b.session.snapshot()
 var loaded=Session.new()
 if not check(loaded.load_game(b.save_path),"normal source transaction readback: "+label):return false
 var saved:Dictionary=loaded.snapshot()
 return check(Plan.same_source(saved.original_items,earned.original_items) and Plan.same_source(saved.original_events,earned.original_events) and Plan.same_source(saved.location,earned.location),"earned source items/flags/location persisted: "+label)
func finish()->void:
 var report:Dictionary={"walked":walked,"protected_walk":protected_walk,"field_calls":field_calls,"portal_count":portals,"original_portals":trace,"proof_trace":proof_trace,"projection_trace":projection_trace,"navigation_failure":navigation_failure,"navigation_observations":nav.observations,"entry_metrics":nav.entry_metrics(),"transactions":transactions,"done":done,"failures":failures}
 var file=FileAccess.open("user://harn-axe-route-trace.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"  "))
 print("HARN AXE ROUTE: ",JSON.stringify(report))
 b.free()
 print("quest_auto_harn_axe_route_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
