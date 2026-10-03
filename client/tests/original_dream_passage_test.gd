extends "res://tests/original_fixed_guards_test.gd"
const Dream=preload("res://server/dream_cave_helper.gd")
func move(b,map_id:int,point:Array,extra:Dictionary={})->Dictionary:
 var command:Dictionary={"type":"report_position","map_id":map_id,"cell":point,"map_changed":true}
 command.merge(extra,true)
 return b.handle(command)
func run()->void:
 for map_id in [41,42]:
  var b=fresh()
  b.automation.position_changed(map_id,Vector2i(47,54))
  var before:Dictionary=b.session.snapshot().duplicate(true)
  for forged in [{},{"client":"party","_following_party":true},{"quest_position_seq":1,"_quest_connection":7}]:
   check(not move(b,map_id,[34,35],forged).ok,"raw/party/receipt cannot jump from hunt room to reward room %d"%map_id)
   check(b.automation.position_cell==Vector2i(47,54) and b.session.snapshot()==before,"rejected jump preserves position, reward and flags")
  check(not b.handle({"type":"quest_talk","npc_id":"seimu/event/event01_2@%d:34:25"%map_id}).ok,"rejection cannot open distant reward dialogue")
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":"seimu/event/event01_2@%d:34:25"%map_id,"mode":mode}).ok,"helper raw reward remains closed")
  b.automation.position_changed(map_id,Vector2i(11,8))
  check(move(b,map_id,[12,8]).ok,"known same-component movement remains allowed")
  check(not move(b,map_id,[56,25]).ok,"knowing original warp destination alone grants no passage")
  b.automation.position_changed(map_id,Vector2i(8,14))
  check(not move(b,map_id,[34,35]).ok,"standing on a portal cannot choose a different arrival")
  var link:Dictionary=b.quest_helper.places.links(map_id)[Vector2i(8,14)]
  check(move(b,map_id,link.target).ok,"exact server source and original warp target allowed %d"%map_id)
  b.automation.position_changed(map_id,Vector2i(11,8))
  b.quest_auto.running=true;b.quest_auto.client="old-device";b.quest_auto.connection=7;b.quest_auto.phase="travel"
  b.quest_auto.emit_position(b,{"map_id":map_id,"cell":[34,35]})
  check(not move(b,map_id,[34,35],{"client":"old-device","_quest_connection":7,"quest_position_seq":b.quest_auto.position_serial}).ok,"even a previously issued exact receipt cannot bypass room validation")
  check(b.automation.position_cell==Vector2i(11,8),"receipt rejection leaves authoritative room")
  b.quest_auto.running=false
  check(not move(b,map_id,[0,0]).ok and not move(b,map_id,[999,999]).ok,"unknown or outside destination fails closed")
  b.automation.position_changed(map_id,Vector2i(0,0))
  check(not move(b,map_id,[0,0]).ok,"two unknown component IDs never authorize each other")
  b.automation.position_changed(map_id,Vector2i(11,8))
  var info:Dictionary=b.quest_helper.places.maps[str(map_id)]
  b.quest_helper.places.maps.erase(str(map_id))
  check(not move(b,map_id,[12,8]).ok,"missing map catalog fails closed")
  b.quest_helper.places.maps[str(map_id)]=info.duplicate(true)
  b.quest_helper.places.maps[str(map_id)].path="world/missing-dream-test.map"
  check(not move(b,map_id,[12,8]).ok,"missing physical map fails closed even with cached labels")
  b.quest_helper.places.maps[str(map_id)]=info
  check(not move(b,map_id,[12.5,8]).ok,"fractional raw positions cannot be silently rounded")
  check(not b.handle({"type":"report_position","map_id":map_id,"cell":"12,8"}).ok,"malformed raw position fails closed without script error")
  var reached:Dictionary=preload("res://tests/support/dream_backend_route.gd").guard(b,map_id)
  check(reached.ok,"real time gate and original maze reach final guard: "+str(reached))
  var talk:Dictionary=b.handle({"type":"quest_talk","npc_id":"400/sb_muge1.arg@%d:34:41"%map_id})
  var started:Dictionary=choose(b,talk,"yes")
  check(talk.ok and started.ok and b.battle_open,"real original final battle opens: "+str(started))
  if b.battle_open:check(b.session._pending.enemies.size()==10,"source final troop keeps all ten enemies")
  fight(b)
  check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==41 and b.automation.position_cell==Vector2i(34,39),"real ten-enemy victory retains source Warp41 from either map")
  check(move(b,41,[34,35]).ok,"post-victory movement within reward component remains allowed")
  b.free()
 await party_follow()
 await two_devices()
 print("ORIGINAL DREAM PASSAGE: %d failures"%failures)
 quit(1 if failures else 0)
func party_follow()->void:
 var hub=Hub.new("user://dream-component-party-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"component party hub starts")
 for entry in [[11,"Leader"],[12,"Member"]]:check(hub.handle(entry[0],{"type":"create_profile","name":entry[1],"pin":"1234"}).ok,"component party account")
 var leader=hub.backends.leader;var member=hub.backends.member
 leader.automation.position_changed(41,Vector2i(8,14));member.automation.position_changed(41,Vector2i(7,14))
 check(hub.handle(12,{"type":"party_join","facing":5}).ok,"real adjacent party joins")
 check(not hub.handle(11,{"type":"report_position","map_id":41,"cell":[34,35]}).ok,"leader illegal jump rejected")
 check(member.automation.position_cell==Vector2i(7,14),"failed leader movement never creates a member exemption")
 var passage:Dictionary=hub.handle(11,{"type":"report_position","map_id":41,"cell":[56,25]})
 check(passage.ok,"leader original warp authorized: "+str(passage)+" at "+str(leader.automation.position_cell))
 check(member.automation.position_cell==Vector2i(56,25),"host follows member only after actual legal leader warp")
 hub.queue_free();await process_frame
func two_devices()->void:
 var b=fresh();root.add_child(b);b.automation.position_changed(42,Vector2i(47,54))
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"component two-socket server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two devices connect")
 check(not (await request(links[0],{"type":"report_position","map_id":42,"cell":[34,35],"client":"party","_following_party":true})).ok,"remote forged party cannot cross final wall")
 check(b.automation.position_cell==Vector2i(47,54),"remote rejected jump preserves authority")
 check((await request(links[1],{"type":"report_position","map_id":42,"cell":[47,54]})).ok,"other socket can report real current cell")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame
