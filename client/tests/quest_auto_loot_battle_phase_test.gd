extends SceneTree
## UNRUN pure predicate + original _process/cancel; no WS/producer/pixel proof.
const Travel=preload("res://scripts/quest_helper_travel.gd")
const STEP="jewels:hunt:2760"
class Link extends RefCounted:

 signal connected
 signal disconnected
 var online:bool=true
 var local_mode:bool=false
 var requests:Array=[]
 func is_local()->bool:return local_mode
 func request(command:Dictionary)->Dictionary:
  requests.append(command.duplicate(true));return {"ok":true}
class Visible extends RefCounted:
 var visible:bool=true
class Router extends RefCounted:
 var cancelled:Array=[]
 func cancel(reason:String)->void:cancelled.append(reason)
class LocalTravel extends Node:
 var pending:int=7
class State extends RefCounted:

 signal changed(kind:String)
 var derived:Dictionary={"quest_auto":{}}
 func quest_loot_enabled()->bool:return false
class World extends Node:
 var state=State.new()
 var link=Link.new()
 var battle_view=Visible.new()
 var travel_router=Router.new()
 var world_travel=LocalTravel.new()
 var message=Label.new()
 var _client_id:String="observer-device"
 var last_adventure_message:String=""
 var party:bool=false
 var path:Array=[Vector2i(1,2)]
 func _init()->void:
  add_child(world_travel);add_child(message)
 func party_locked()->bool:return party
var checks:int=0
func check(ok:bool,note:String)->bool:
 print(("PASS " if ok else "FAIL ")+note)
 if not ok:quit(1);return false
 checks+=1;return true
func fixture()->Dictionary:
 return {"running":true,"phase":"loot_battle","step_id":STEP,"strict_walk":false,"client":"initiating-other-device","message":"原原因","budget":{"enabled":false,"entry":{"step_id":STEP},"activity":"battle","finish_current_battle":false}}
func process_case(auto:Dictionary,party:bool,visible_battle:bool,online:bool,local_mode:bool,active:bool,expected:int,label:String)->bool:
 var world=World.new();var travel=Travel.new();travel.configure(world)
 world.state.derived.quest_auto=auto;world.party=party;world.battle_view.visible=visible_battle;world.link.online=online;world.link.local_mode=local_mode
 travel.active=active;travel.phase="walking" if active else ""
 travel._process(0.0) # Call actual consumer once, no overridden auto_status/cancel.
 var ok:bool=check(world.link.requests.size()==expected,label)
 if ok and expected>0:
  ok=check(world.link.requests==[{"type":"quest_auto_stop","client":"observer-device"}],label+" original command exact")
  if ok:ok=check(not travel.active and travel.generation==1,label+" original cancel lifecycle")
 if ok and active:
  ok=check(world.travel_router.cancelled.size()==1 and world.path.is_empty() and world.world_travel.pending==-1,label+" original navigation cleanup")
 travel.free();world.free();return ok
func _initialize()->void:
 var auto:Dictionary=fixture()
 if not check(Travel.is_service_battle(auto),"Exact original loot battle matches even enabledfalse and other client"):return
 for malformed in [null,17,"budget",[]]:
  auto=fixture();auto.budget=malformed
  if not check(not Travel.is_service_battle(auto),"Predicate rejects nonDictionary budget without reading entry"):return
 for missing in [{},{"entry":null},{"entry":7},{"entry":[]},{"entry":{}},{"entry":{"step_id":"other"}}]:
  auto=fixture();auto.budget=missing
  if not check(not Travel.is_service_battle(auto),"Predicate rejects missing/malformed/mismatched entry"):return
 auto=fixture();auto.erase("budget")
 if not check(not Travel.is_service_battle(auto),"Predicate rejects absent budget"):return
 auto=fixture();auto.step_id="other"
 if not check(not Travel.is_service_battle(auto),"Predicate rejects wrong root step"):return
 for phase in ["loot_admission","travel","unknown",""]:
  auto=fixture();auto.phase=phase
  if not check(not Travel.is_service_battle(auto),"No broad phase exemption "+phase):return
  if not process_case(auto,false,true,true,false,false,1,"Original cancellation "+phase):return
 auto=fixture();auto.phase="battle";auto.erase("budget")
 if not check(Travel.is_service_battle(auto),"Original battle phase needs no loot budget"):return
 if not process_case(auto,false,true,true,false,false,0,"Original battle exemption unchanged"):return
 for activity in ["battle","settling","storage_paused","stopped"]:
  auto=fixture();auto.budget.activity=activity
  for finish in [false,true]:
   auto.budget.finish_current_battle=finish
   if not check(Travel.is_service_battle(auto),"Activity/finish do not define exact service phase"):return
   if not process_case(auto,false,true,true,false,false,0,"Exact loot stage survives visible battle"):return
 for strict in [false,true]:
  auto=fixture();auto.strict_walk=strict
  if not process_case(auto,true,true,true,false,false,1,"Party remains independent OR despite legal battle/strict"):return
 auto=fixture();auto.phase="unknown";auto.strict_walk=true
 if not process_case(auto,false,true,true,false,false,0,"Original strict behavior remains"):return
 auto=fixture();auto.phase="unknown"
 if not process_case(auto,false,false,true,false,false,0,"No visible battle does not cancel ordinary running task"):return
 if not process_case(auto,false,true,false,false,false,0,"Original remote offline gate"):return
 if not process_case(auto,false,true,false,true,false,1,"Original local transport gate"):return
 auto=fixture()
 if not process_case(auto,false,true,true,false,true,1,"Active navigation later branch still cancels exact loot battle"):return
 var world=World.new();var travel=Travel.new();travel.configure(world);world.state.derived.quest_auto=fixture()
 travel.cancel("原用户停止")
 var ok:bool=check(world.link.requests==[{"type":"quest_auto_stop","client":"observer-device"}] and travel.generation==1 and world.message.text=="原用户停止","Generic explicit Stop unchanged even ledger enabledfalse")
 travel.free();world.free()
 if not ok:return
 print("LOOT BATTLE PHASE PURE: ",checks," checks; predicate and original consumer only")
 quit(0)
