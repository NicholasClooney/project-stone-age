extends SceneTree
## UNRUN: real public-village walk + original footprint request transaction/readback.
## Job10 registry is deliberately still closed. No completion flags/items injected.
const Backend=preload("res://server/backend.gd")
const Plan=preload("res://server/quest_auto_saton_plan.gd")
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
 # Public interior manifest spawn, not NPC talk endpoint or protected cave.
 # No Boss confirmation, no gift injection, no quest_helper convenience warp.
 b.automation.position_changed(1112,Vector2i(11,15),true,"project")
 b.save_path="user://saton-request-first.json"
 if not check(b.save(),"normal initial save"):finish(b);return
 var initial:Dictionary=b.session.snapshot()
 if not check(not Rules.flag(initial,"now",13) and not Rules.flag(initial,"now",14) and not Rules.flag(initial,"ended",13) and not Rules.flag(initial,"ended",14) and not 2431 in initial.original_items and not 2450 in initial.original_items,"fresh unfinished request/reward state"):finish(b);return
 # Detached dictionaries only: never injected into Backend or saved as progress.
 var ended14:Dictionary=initial.duplicate(true)
 Rules.set_flag(ended14,"ended",14,true)
 if not check(Plan.select({"session":{"_profile":ended14}},10).get("status")!="done","END14 alone cannot replace original END13"):finish(b);return
 Rules.set_flag(ended14,"ended",13,true)
 if not check(Plan.select({"session":{"_profile":ended14}},10).get("status")=="done","original END13 stops without another reward cycle"):finish(b);return
 b.original_quests.refresh_npc_state() # Normal lifecycle, outside pure proposal.
 var before:Dictionary=b.session.snapshot()
 var version:int=b.original_quests.npc_state.version
 var proposal:Dictionary=Plan.request_proposal(b)
 if not check(b.session.snapshot()==before and b.original_quests.npc_state.version==version,"proposal leaves profile and spawn state untouched"):finish(b);return
 if not check(proposal.get("status")=="step","exact full-source request proposal: "+str(proposal)):finish(b);return
 if not check(proposal.step.auto_choices==["yes","ok"] and proposal.step.source.actions=={"GetItem":"2431*1"},"only original REQUEST award; no broad MESSAGE/CLEAN"):finish(b);return
 if not check(b.quest_auto.safe_step(proposal.step,10,false),"existing ordinary runner shape is sufficient"):finish(b);return
 # Full ordered source lock catches changes even in an unselected forbidden branch.
 for npc in b.quest_catalog.npcs:
  if npc.id=="sainasu/event/event13_1@1112:16:15":
   var saved:Dictionary=npc.branches[0].duplicate(true)
   npc.branches[0].actions["GetItem"]="2431"
   check(Plan.request_proposal(b).status=="manual","changed earlier branch fails full-source lock")
   npc.branches[0]=saved
   if failures:finish(b);return
 var npc:Dictionary=b.quest_catalog.active_npc(proposal.step.npc_id)
 var nav=Nav.new()
 var walking:Dictionary={"walked":0,"failed":false}
 # Shared condition deadline (60s), never an extra 15s wall-clock cutoff.
 # The predicate drives one production A step per poll, preserving the 200-cell cap.
 var reached:bool=await Wait.until(self,func():return approach_tick(b,nav,npc,walking))
 if walking.failed:finish(b);return
 if not check(reached and near(b,npc),"shared Wait condition reaches real talk range"):finish(b);return
 var walked:int=walking.walked
 if not check(walked>0,"fixture actually approached NPC, not placed at transaction endpoint"):finish(b);return
 var fresh:Dictionary=Plan.request_proposal(b)
 if not check(fresh.get("status")=="step","proposal remains exact at real public endpoint"):finish(b);return
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":fresh.step.npc_id})
 if not check(opened.get("ok",false) and opened.has("dialogue"),"real original REQUEST opens"):finish(b);return
 if not check(Plan.same_source(b.original_quests.pending.branch,fresh.step.source.branch_data),"production chose locked full branch"):finish(b);return
 var yes:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(yes.get("ok",false) and yes.has("dialogue"),"original REQUEST commits normally"):finish(b);return
 if not check(b.handle({"type":"quest_choose","token":yes.dialogue.token,"choice":"ok"}).get("ok",false),"original end page closes"):finish(b);return
 var earned:Dictionary=b.session.snapshot()
 if not check(Rules.flag(earned,"now",13) and 2431 in earned.original_items,"real source gave NOW13 and footprint2431"):finish(b);return
 if not check(not Rules.flag(earned,"ended",13) and not Rules.flag(earned,"ended",14) and not 2450 in earned.original_items,"no medicine or END13/14 forged"):finish(b);return
 if not check(Plan.select(b,10).get("stage")=="wait_boss","next unbound stage remains manual"):finish(b);return
 var loaded=Session.new()
 if not check(loaded.load_game(b.save_path),"read actual transaction save without replacing endpoint"):finish(b);return
 if not check(loaded.snapshot().original_items==earned.original_items and loaded.snapshot().original_events==earned.original_events,"original reward and NOW survive disk readback"):finish(b);return
 print("SATON REQUEST: walked=%d actual_map=%d actual_cell=%s"%[walked,b.automation.position_map,str(b.automation.position_cell)])
 finish(b)
func near(b,npc:Dictionary)->bool:
 return b.automation.position_map==int(npc.map_id) and maxi(absi(b.automation.position_cell.x-int(npc.cell[0])),absi(b.automation.position_cell.y-int(npc.cell[1])))<=2
func approach_tick(b,nav,npc:Dictionary,state:Dictionary)->bool:
 if near(b,npc):return true
 if state.failed:return true
 if not check(int(state.walked)<200,"public approach logical limit is 200 neighbours"):
  state.failed=true;return true
 var point:Dictionary=nav.next(b,npc)
 if not check(not point.is_empty() and int(point.map_id)==1112 and not point.has("portal") and not point.has("gate"),"production A proposes public village walk only"):
  state.failed=true;return true
 if not check(nav.validate(b,point),"original Nav validates each proposed public step"):
  state.failed=true;return true
 var origin:Vector2i=b.automation.position_cell
 var next:=Vector2i(int(point.cell[0]),int(point.cell[1]))
 if not check(absi(next.x-origin.x)+absi(next.y-origin.y)==1,"one actual neighbour per manual walk"):
  state.failed=true;return true
 if not check(b.handle({"type":"report_position","map_id":1112,"cell":point.cell.duplicate(),"client":"saton-request"}).get("ok",false),"normal manual movement accepted"):
  state.failed=true;return true
 state.walked+=1
 return near(b,npc)
func finish(b)->void:
 b.free()
 print("quest_auto_saton_request_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
