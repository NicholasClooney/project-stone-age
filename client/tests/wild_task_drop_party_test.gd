extends "res://tests/wild_task_drop_test.gd"
func run()->void:
 dir="user://wild-task-party-%d"%OS.get_process_id();remove_tree(dir);DirAccess.make_dir_recursive_absolute(dir)
 for lose_killer_route in [false,true]:
  var pair:=party_hub(["Alice","Bob"]);var hub=pair[0]
  var leader=hub.backends.alice;var member=hub.backends.bob
  for b in [leader,member]:strong(b)
  var entrance:Dictionary={}
  for link in leader.quest_helper.places.links(300).values():
   if int(link.to_map)==31801 and not link.has("gate_source"):entrance=link;break
  check(not entrance.is_empty(),"real party public mine entrance")
  for b in [leader,member]:b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
  check(hub.handle(1,{"type":"report_position","map_id":31801,"cell":entrance.target}).ok,"actual Hub portal follows each member")
  for step in Route.path(leader,31801,Vector2i(37,48),[31801]):
   check(hub.handle(1,{"type":"report_position","map_id":step.map_id,"cell":step.cell}).ok,"actual Hub continuous party step")
  check(leader.quest_arrival.has_arrival(leader,31801,leader.automation.position_cell) and member.quest_arrival.has_arrival(member,31801,member.automation.position_cell),"each member retains own original route at trailing position")
  leader.encounter_rng.seed=27
  check(hub.handle(1,{"type":"wild_encounter","map_id":31801,"cell":[37,48]}).ok,"actual Hub seed27 source battle")
  check(leader.session._pending.has("wild_drop_receipt") and member.session._pending.has("wild_drop_receipt"),"both personal pending records freeze source")
  check(leader.session._pending.wild_drop_receipt.context!=member.session._pending.wild_drop_receipt.context,"leader context never copied to member")
  var bad=member if lose_killer_route else leader
  bad.quest_arrival.reset()
  var before:Dictionary=member.session.snapshot();var good_path:String=member.save_path
  member.save_path="user://no-party-task-drop-dir/save.json"
  for turn in range(100):
   var entry:Dictionary=entry_of(hub,"alice")
   if entry.is_empty() or not entry.session.snapshot().active:break
   for connection in [1,2]:
    var id:String=hub.profile_of(connection)
    if entry.ids.find(id) in entry.session.waiting_slots():send(hub,connection,"defend" if connection==1 else "attack")
   hub.party_battles.tick()
  check(not member.battle.snapshot().active and not member.battle_state.get("settled",false),"actual member kill freezes failed personal settlement")
  var pending:Dictionary=member.session._pending.duplicate(true)
  check(not pending.get("party_settlement",{}).get("drop_claims",[]).is_empty(),"original server killer claims preserved")
  check(not hub.handle(2,{"type":"battle_close"}).ok and member.session._pending==pending and member.session.snapshot()==before,"member savefail retry preserves frozen slice and all claims")
  var terminal:Dictionary=pending.party_settlement.result
  for malformed in [[{"enemy":99,"item":0}],[{"enemy":0,"item":99}],pending.party_settlement.drop_claims+pending.party_settlement.drop_claims]:
   check(not member.session.apply_battle_result(terminal,malformed) and member.session.snapshot()==before,"Session rejects invalid or duplicate full party claims before any suppression")
  member.save_path=good_path
  check(hub.handle(2,{"type":"battle_close"}).ok,"member ordinary personal settlement retries and closes")
  check(member.session.snapshot().original_items.count(2534)==(0 if lose_killer_route else 1),"killer gets exact special loot only with its own epoch")
  check(member.session.snapshot().completed_battles.size()==before.completed_battles.size()+1,"invalidated member still commits ordinary result exactly once")
  check(hub.handle(1,{"type":"battle_close"}).ok,"leader independently closes normal personal slice")
  await close(hub)
 remove_tree(dir)
 print("WILD TASK DROP PARTY: %d failures"%failures);quit(1 if failures else 0)
