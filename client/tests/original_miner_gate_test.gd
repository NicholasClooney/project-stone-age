extends "res://tests/original_fixed_guards_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
func source_talk(b,npc:Dictionary)->Dictionary:
 check(preload("res://tests/support/legacy_cave_route.gd").approach(b,npc).get("ok",false),"actual original miner entrance and cave route before gate/service")
 return b.handle({"type":"quest_talk","npc_id":npc.id})
var gate:Dictionary={}
var seller:Dictionary={}
func install(b)->void:
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-miner-gate.json"))
 gate=f.module.npcs[0];seller=f.module.npcs[1]
 b.session.world_catalog.maps.merge(f.maps)
 b.quest_catalog.npcs.append_array(f.module.npcs.duplicate(true));b.quest_catalog.items.merge(f.module.items)
 b.quest_catalog.enabled_events.append(27)
func ticket(b)->void:Session.OriginalEquipment.add(b.session._profile,2527)
func run()->void:
 var b=Backend.new();install(b)
 var r:=source_talk(b,gate)
 check(r.ok and r.dialogue.choices[0].id=="ok" and not choose(b,r,"yes").ok,"no permit sees original PayMsg; MONEY minus1 never bypasses")
 ticket(b);ticket(b);r=source_talk(b,gate)
 var before:Dictionary=b.session.snapshot()
 check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel keeps both permits")
 r=source_talk(b,gate);Session.OriginalEquipment.remove(b.session._profile,2527);Session.OriginalEquipment.remove(b.session._profile,2527)
 check(not choose(b,r,"yes").ok and b.automation.position_map==31805,"confirmation rechecks latest bag")
 ticket(b);ticket(b);r=source_talk(b,gate);before=b.session.snapshot();b.save_path="user://missing-miner-gate/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before and b.automation.position_map==31805,"failed save restores both permit UIDs and location")
 b.save_path="user://miner-gate.json";r=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.automation.position_map==31806 and b.automation.position_cell==Vector2i(34,6),"source permit commits original Warp")
 check(b.session.snapshot().original_items.count(2527)==1 and b.session.snapshot().original_instances[0].uid==before.original_instances[1].uid,"exactly first bag permit consumed; spare UID preserved")
 check(not choose(b,r,"yes").ok,"committed token cannot consume again")
 var loaded=Backend.new();install(loaded)
 check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_items.count(2527)==1 and int(loaded.session.snapshot().location.map_id)==31806,"real save readback keeps permit consumption and destination")
 loaded.free()
 Rules.set_flag(b.session._profile,"ended",27,true);b.session._profile.player.gold=1000
 r=source_talk(b,seller);check(r.ok and Rules.matches(b.session.snapshot(),"ENDEV=27&ITEM!=2391"),"missing definition retains exact original negative predicate")
 check(choose(b,r,"yes").ok and b.session.snapshot().player.gold==0 and b.session.snapshot().original_items.count(2527)==2,"source completed-event fee buys permit without inventing2391")
 b.free()
 await lan_gate()
 party_gate()
 print("ORIGINAL MINER GATE: %d failures"%failures);quit(1 if failures else 0)
func lan_gate()->void:
 var b=Backend.new();install(b);root.add_child(b);ticket(b);source_talk(b,gate);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"miner real remote port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two permit devices ready")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 Session.OriginalEquipment.remove(b.session._profile,2527)
 check(not (await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes","items":[2527]})).ok,"second device cannot forge removed permit")
 ticket(b);r=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok and b.session.snapshot().original_items.is_empty(),"two devices share one saved permit transaction")
 check(not (await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"other device cannot replay permit")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
func party_gate()->void:
 var hub=Hub.new("user://miner-gate-party-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"miner party hub")
 for i in range(2):
  check(hub.handle(i+1,{"type":"create_profile","name":"Miner%d"%i,"pin":"1234"}).ok,"miner party profile")
  var b=hub.backend_of(i+1);install(b);ticket(b)
  var opened:Dictionary=source_talk(b,gate)
  choose(b,opened,"no")
 # Keep the leader on the actually reachable pre-gate side. The old
 # (22,3) fixture is across the permit door and cannot be walked to.
 var leader=hub.backend_of(1);var member=hub.backend_of(2)
 var facing:=-1
 for index in range(8):
  var delta:Vector2i=preload("res://server/party.gd").DIRECTIONS[index]
  var goal:Vector2i=leader.automation.position_cell+delta
  if Route.walk(member,31805,goal,[31805]).get("ok",false):facing=index;break
 check(facing>=0,"party member walks next to leader on original pre-gate side")
 var r:Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":gate.id})
 check(r.ok and hub.handle(2,{"type":"party_join","facing":facing}).ok,"party joins after permit offer")
 var result:Dictionary=hub.handle(1,{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 check(not result.ok and result.reason.contains("解散团队") and hub.backend_of(1).session.snapshot().original_items.count(2527)==1,"source default PartyMsg rejects confirmation without consuming permit")
 r=hub.handle(1,{"type":"quest_talk","npc_id":gate.id})
 check(r.ok and r.dialogue.choices[0].id=="ok" and r.dialogue.text.contains("解散团队"),"party opening also refuses with original default message")
 hub.shut_down();hub.queue_free()
