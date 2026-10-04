extends SceneTree
## UNRUN: real public-village walk + original commission transaction/readback.
## Job22 registry is deliberately still closed. No completion flags/items injected.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_harn_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Nav=preload("res://server/quest_auto_navigation.gd")
const Wait=preload("res://tests/support/wait.gd")
var assertions:=0
var failures:=0
func check(value:bool,label:String)->bool:
 assertions+=1
 if not value:failures+=1;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Backend.new()
 # Explicit eligible level and public starting cell only. No GM reward/END/NOW,
 # inventory grants or protected-map placement. This is not an entrance crossing.
 b.session._profile.player.level=16
 b.automation.position_changed(3300,Vector2i(44,66),true,"project")
 b.save_path="user://harn-commission-first.json"
 if not check(b.save(),"normal initial save"):finish(b);return
 var initial:Dictionary=b.session.snapshot()
 if not check(not Rules.flag(initial,"now",18) and not Rules.flag(initial,"now",19) and not Rules.flag(initial,"ended",18) and not Rules.flag(initial,"ended",19) and not 2466 in initial.original_items and not 2465 in initial.original_items,"fresh unfinished commission/axe state"):finish(b);return
 b.original_quests.refresh_npc_state() # Normal lifecycle, outside pure proposal.
 var before:Dictionary=b.session.snapshot()
 var version:int=b.original_quests.npc_state.version
 var proposal:Dictionary=Plan.commission_proposal(b)
 check(b.session.snapshot()==before and b.original_quests.npc_state.version==version,"proposal leaves profile and spawn state untouched")
 if not check(proposal.get("status")=="step","exact full-source commission proposal: "+str(proposal)):finish(b);return
 check(proposal.step.auto_choices==["yes","ok"] and proposal.step.source.actions=={"GetItem":"2466"},"only original REQUEST award; no broad MESSAGE/CLEAN")
 check(b.quest_auto.safe_step(proposal.step,22,false),"existing ordinary runner shape is sufficient")
 # Full ordered source lock catches changes even in an unselected forbidden branch.
 for npc in b.quest_catalog.npcs:
  if npc.id=="jaruga/event/20501ev3":
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions["GetItem"]="2465"
   check(Plan.commission_proposal(b).status=="manual","changed earlier branch fails full-source lock")
   npc.branches[0]=saved
 var npc:Dictionary=b.quest_catalog.active_npc(proposal.step.npc_id)
 var nav=Nav.new()
 var walking:Dictionary={"walked":0,"failed":false}
 # Shared condition deadline (60s), never an extra 15s wall-clock cutoff.
 # The predicate drives one production A step per poll, preserving the 200-cell cap.
 var reached:bool=await Wait.until(self,func():return approach_tick(b,nav,npc,walking))
 if not check(reached and not walking.failed and near(b,npc),"shared Wait condition reaches real talk range"):finish(b);return
 var walked:int=walking.walked
 check(walked>0,"fixture actually approached NPC, not placed at transaction endpoint")
 var fresh:Dictionary=Plan.commission_proposal(b)
 if not check(fresh.get("status")=="step","proposal remains exact at real public endpoint"):finish(b);return
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":fresh.step.npc_id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"real original REQUEST opens"):finish(b);return
 if not check(Plan.same_source(b.original_quests.pending.branch,fresh.step.source.branch_data),"production chose locked full branch"):finish(b);return
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original REQUEST commits normally"):finish(b);return
 check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original end page closes")
 var earned:Dictionary=b.session.snapshot()
 check(Rules.flag(earned,"now",18) and 2466 in earned.original_items,"real source gave NOW18 and commission2466")
 check(not Rules.flag(earned,"ended",18) and not Rules.flag(earned,"ended",19) and not 2465 in earned.original_items,"no axe or extra completion forged")
 check(Plan.select(b,22).get("stage")=="request_axe","next unbound stage remains manual")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path),"read actual transaction save without replacing endpoint")
 check(loaded.snapshot().original_items==earned.original_items and loaded.snapshot().original_events==earned.original_events,"original reward and NOW survive disk readback")
 print("HARN COMMISSION: walked=%d actual_map=%d actual_cell=%s"%[walked,b.automation.position_map,str(b.automation.position_cell)])
 finish(b)
func near(b,npc:Dictionary)->bool:
 return b.automation.position_map==int(npc.map_id) and maxi(absi(b.automation.position_cell.x-int(npc.cell[0])),absi(b.automation.position_cell.y-int(npc.cell[1])))<=2
func approach_tick(b,nav,npc:Dictionary,state:Dictionary)->bool:
 if near(b,npc):return true
 if state.failed:return true
 if not check(int(state.walked)<200,"public approach logical limit is 200 neighbours"):
  state.failed=true;return true
 var point:Dictionary=nav.next(b,npc)
 if not check(not point.is_empty() and int(point.map_id)==3300 and not point.has("portal") and not point.has("gate"),"production A proposes public village walk only"):
  state.failed=true;return true
 var origin:Vector2i=b.automation.position_cell
 var next:=Vector2i(int(point.cell[0]),int(point.cell[1]))
 if not check(absi(next.x-origin.x)+absi(next.y-origin.y)==1,"one actual neighbour per manual walk"):
  state.failed=true;return true
 if not check(b.handle({"type":"report_position","map_id":3300,"cell":point.cell.duplicate(),"client":"harn-commission"}).get("ok",false),"normal manual movement accepted"):
  state.failed=true;return true
 state.walked+=1
 return near(b,npc)
func finish(b)->void:
 b.free()
 print("quest_auto_harn_commission_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
