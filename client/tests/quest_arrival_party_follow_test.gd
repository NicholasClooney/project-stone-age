extends "res://tests/lan_party_test.gd"
const WorldClock=preload("res://server/original_world_clock.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
func run()->void:
 var old:Callable=WorldClock.clock;WorldClock.clock=func():return WorldClock.ERA+100
 dir="user://arrival-party-%d"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(dir)
 var h=ProfileHub.new(dir+"/accounts.json");root.add_child(h);check(h.start(),"arrival party real Hub starts")
 for info in [[1,"Alice","1111"],[2,"Bob","2222"]]:check(h.handle(info[0],{"type":"create_profile","name":info[1],"pin":info[2]}).ok,"create party character")
 report(h,1,400,Vector2i(97,119));report(h,2,400,Vector2i(96,119))
 check(h.handle(2,{"type":"party_join","facing":EAST}).ok,"join actual party outside public root")
 check(report(h,1,41,Vector2i(11,8),true).ok,"leader enters original timed root and members follow")
 var leader=h.backend_of(1);var member=h.backend_of(2)
 check(leader.quest_arrival.has_arrival(leader,41,leader.automation.position_cell) and member.quest_arrival.has_arrival(member,41,member.automation.position_cell),"each party character receives its own root route")
 var steps:Array=Route.path(leader,41,Vector2i(34,42),[41])
 var crossed:=false
 for step in steps:
  var before:Vector2i=leader.automation.position_cell
  check(report(h,1,int(step.map_id),Vector2i(int(step.cell[0]),int(step.cell[1]))).ok,"production leader original route report")
  if not member.quest_arrival.has_arrival(member,41,member.automation.position_cell):
   check(false,"member loses independent route at leader %s->%s member=%s"%[before,leader.automation.position_cell,member.automation.position_cell]);break
  if before.distance_to(leader.automation.position_cell)>2:crossed=true;break
 check(crossed,"actual inner maze portal followed after normal walking")
 var candidates: Array=Route.path(leader,41,Vector2i(34,42),[41])
 if not candidates.is_empty():
  var first: Dictionary=candidates[0]
  check(report(h,1,int(first.map_id),Vector2i(int(first.cell[0]),int(first.cell[1]))).ok,"party walks off genuine portal landing")
 var origin: Vector2i=leader.automation.position_cell
 var target: Vector2i=origin
 var data: Dictionary=leader.quest_arrival._map_data(leader,41)
 for y in range(int(data.height)):
  for x in range(int(data.width)):
   var cell:=Vector2i(x,y)
   if maxi(absi(origin.x-x),absi(origin.y-y))>1 and leader.quest_arrival._same_room(leader,41,origin,cell):
    target=cell;break
  if target!=origin:break
 check(target!=origin,"independent same-room nonadjacent point exists")
 check(report(h,1,41,target).ok,"same-room project-sized raw jump accepted as position only")
 check(not leader.quest_arrival.has_arrival(leader,41,leader.automation.position_cell) and not member.quest_arrival.has_arrival(member,41,member.automation.position_cell),"leader project-sized raw jump cannot launder members' routes")
 check(h.handle(3,{"type":"create_profile","name":"Eve","pin":"3333"}).ok,"create independent character for client-forgery boundary")
 report(h,3,400,Vector2i(96,119))
 h.handle(3,{"type":"report_position","map_id":41,"cell":[11,8],"client":"party","arrival_kind":"party","evidence":{"leader_from_map":400,"leader_from_cell":[97,119],"leader_to_map":41,"leader_to_cell":[11,8]}})
 var outsider=h.backend_of(3)
 check(not outsider.quest_arrival.has_arrival(outsider,41,Vector2i(11,8)),"client-named party origin and plausible leader evidence cannot issue root proof")
 h.shut_down();h.queue_free();await process_frame;remove_tree(dir);WorldClock.clock=old
 print("QUEST ARRIVAL PARTY FOLLOW: %d failures"%failures);quit(1 if failures else 0)
