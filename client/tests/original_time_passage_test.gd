extends "res://tests/original_fixed_guards_test.gd"
const Clock=preload("res://server/original_world_clock.gd")
var seconds:=Clock.ERA
var gates:Array=[]
func install(b)->void:
 for gate in gates:
  var key:=str(int(gate.from_map))
  if not b.quest_helper.places.portals.has(key):b.quest_helper.places.portals[key]={}
  b.quest_helper.places.portals[key][Vector2i(int(gate.cell[0]),int(gate.cell[1]))]=gate.duplicate(true)
func at_hour(value:int)->void:seconds=Clock.ERA+int(ceil(float(value)*5400.0/1024.0))
func run()->void:
 var previous:=Clock.clock
 Clock.clock=func():return seconds
 gates=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dream-time-gates.json"))
 for entry in [[-5401,0],[-5400,0],[-5399,-1023],[-1,0],[0,0],[1,0],[5399,1023],[5400,0],[5401,0]]:
  check(Clock.hour_at(Clock.ERA+entry[0])==entry[1],"original signed C clock boundary %d"%entry[0])
 for entry in [[0,"A"],[126,"A"],[127,"A"],[200,"A"],[201,"E"],[299,"E"],[300,"E"],[301,"N"],[700,"N"],[701,"M"],[930,"M"],[931,"A"],[1023,"A"]]:
  at_hour(entry[0]);check(Clock.hour()==entry[0] and Clock.phase_at(Clock.hour())==entry[1],"original phase boundary %d"%entry[0])
  check(Clock.after_at(entry[0])==(entry[0]>126 and entry[0]<300),"AFTER is independent strict interval")
 var b=Backend.new();install(b)
 for gate in gates:
  for value in [200,201,300,301,700,701,930,931]:
   at_hour(value)
   b.automation.position_changed(400,Vector2i(int(gate.cell[0]),int(gate.cell[1])))
   var expected:=Clock.allows(str(gate.requires_time),value)
   check(b.handle({"type":"check_passage","from_map":400,"to_map":gate.to_map,"hour":701}).ok==expected,"server checks source gate and ignores client hour")
   var r:Dictionary=b.handle({"type":"report_position","map_id":gate.to_map,"cell":gate.target,"client":"party"})
   check(r.ok==expected,"arrival repeats time check; client party label grants no authority")
   if not expected:check(b.automation.position_map==400,"closed gate keeps authoritative origin")
 b.automation.position_changed(400,Vector2i(97,119));at_hour(300)
 check(b.handle({"type":"check_passage","from_map":400,"to_map":41}).ok,"A gate authorizes last evening hour")
 at_hour(301)
 check(not b.handle({"type":"report_position","map_id":41,"cell":[11,8]}).ok,"clock boundary between authorization and arrival rejects stale transition")
 b.automation.position_changed(400,Vector2i(1,1));at_hour(200)
 check(not b.handle({"type":"report_position","map_id":41,"cell":[11,8]}).ok,"raw report cannot skip source entrance")
 b.automation.position_changed(400,Vector2i(97,119))
 check(not b.handle({"type":"report_position","map_id":41,"cell":[34,39]}).ok,"raw report cannot choose post-guard destination")
 check(b.report_party_position({"type":"report_position","map_id":41,"cell":[11,8]}).ok,"host-owned party follow preserves original party travel")
 check(b.handle({"type":"report_position","map_id":400,"cell":[97,120]}).ok,"unsuffixed return stays open")
 b.free()
 party_time_gate()
 await remote_time_gate()
 Clock.clock=previous
 print("ORIGINAL TIME PASSAGE: %d failures"%failures)
 quit(1 if failures else 0)
func remote_time_gate()->void:
 var hub=Hub.new("user://dream-clock-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"clock LAN hub")
 check(hub.accounts.create("Alice","1234").ok,"clock LAN account")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"clock LAN ephemeral port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"clock two sockets connected")
 for link in links:
  link.login({"type":"login","name":"Alice","pin":"1234"},func(_reply):pass)
  check(await Wait.until(self,func():poll();return link.online),"clock devices authenticated")
 var b=hub.backends.alice;install(b)
 b.automation.position_changed(400,Vector2i(97,119));at_hour(300)
 check((await request(links[0],{"type":"check_passage","from_map":400,"to_map":41})).ok,"remote authorizes evening entrance")
 at_hour(301)
 check(not (await request(links[1],{"type":"report_position","map_id":41,"cell":[11,8],"hour":200,"client":"party"})).ok,"other device cannot reuse stale time or forge party authority")
 at_hour(200)
 var opened:Dictionary=await request(links[1],{"type":"report_position","map_id":41,"cell":[11,8]})
 check(opened.ok,"remote enters when server clock opens gate: "+str(opened))
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()

func party_time_gate()->void:
 var hub=Hub.new("user://dream-party-clock-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"timed party hub starts")
 for entry in [[11,"Leader"],[12,"Member"]]:
  check(hub.handle(entry[0],{"type":"create_profile","name":entry[1],"pin":"1234"}).ok,"timed party account logs in")
 var leader=hub.backends.leader;var member=hub.backends.member
 install(leader);install(member)
 leader.automation.position_changed(400,Vector2i(97,119));member.automation.position_changed(400,Vector2i(96,119))
 check(hub.handle(12,{"type":"party_join","facing":5}).ok,"real adjacent party joins at original entrance")
 at_hour(301)
 check(not hub.handle(11,{"type":"report_position","map_id":41,"cell":[11,8]}).ok and member.automation.position_map==400,"closed gate cannot drag party inside")
 at_hour(200)
 check(hub.handle(11,{"type":"report_position","map_id":41,"cell":[11,8]}).ok,"leader crosses open original A entrance")
 check(member.automation.position_map==41 and member.automation.position_cell==Vector2i(11,8),"real ProfileHub follows member without requiring member's different M entrance to be open")
 hub.queue_free()
