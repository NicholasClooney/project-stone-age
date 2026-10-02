extends "res://tests/original_fixed_guards_test.gd"
var gate:Dictionary={}
func install_gate(b)->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-free-warp-gate.json"))
 gate=fixture.module.npcs[0]
 b.session.world_catalog.maps.merge(fixture.maps)
 b.quest_catalog.npcs.append(gate.duplicate(true));b.quest_catalog.enabled_events.append_array([37,38])
func run()->void:
 var b=Backend.new();install_gate(b)
 check(b.session.gm_raise_level(-1,49),"real GM creates valid level49 profile")
 var r:=source_talk(b,gate)
 check(r.ok and r.dialogue.text.contains("还太危险") and r.dialogue.choices[0].id=="ok","49 sees original PayMsg and OK only")
 check(not choose(b,r,"yes").ok and b.automation.position_map==120,"MONEY minus1 never becomes payment or bypass")
 check(b.session.gm_raise_level(-1,50),"real GM creates valid level50 profile");b.session._profile.player.gold=0
 r=source_talk(b,gate)
 check(r.ok and r.dialogue.text.contains("你要进入迷宫吗"),"50 sees original free confirmation")
 var before:Dictionary=b.session.snapshot()
 check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel does not warp or charge")
 r=source_talk(b,gate);b.session._profile.player.level=49
 check(not choose(b,r,"yes").ok and b.automation.position_map==120,"confirm rechecks current authoritative level")
 b.session._profile.player.level=50;r=source_talk(b,gate);before=b.session.snapshot()
 b.save_path="user://missing-free-gate/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before and b.automation.position_map==120,"free gate save failure restores location and currency")
 b.save_path="user://free-gate.json"
 var metadata:Dictionary=b.session.world_catalog.maps["122"]
 b.session.world_catalog.maps.erase("122");r=source_talk(b,gate)
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"unimported destination refuses before writing invalid save")
 b.session.world_catalog.maps["122"]=metadata;r=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.automation.position_map==122 and b.automation.position_cell==Vector2i(6,5),"free original gate commits exact destination")
 check(int(b.session.snapshot().player.gold)==0 and not choose(b,r,"yes").ok,"zero-gold pass costs nothing and token cannot replay")
 var again=Backend.new();install_gate(again);check(again.load_profile(b.save_path) and int(again.session.snapshot().location.map_id)==122,"free Warp persists to real save")
 b.free();again.free()
 party_gate()
 await gate_lan()
 print("ORIGINAL FREE WARP GATE: %d failures"%failures)
 quit(1 if failures else 0)
func party_gate()->void:
 var hub=Hub.new("user://free-gate-party-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"gate real ProfileHub starts")
 for i in range(2):
  check(hub.handle(i+1,{"type":"create_profile","name":"Gate%d"%i,"pin":"1234"}).ok,"gate party character")
  hub.handle(i+1,{"type":"report_position","map_id":120,"cell":[19+i,14],"client":"gate%d"%i})
  var b=hub.backend_of(i+1);install_gate(b);b.session.gm_raise_level(-1,50)
 var leader=hub.backend_of(1)
 var r:Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":gate.id})
 check(r.ok,"solo source gate offered before party change")
 check(hub.handle(2,{"type":"party_join","facing":1}).ok,"real party membership changes after offer")
 var denied:Dictionary=hub.handle(1,{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 check(not denied.ok and denied.reason.contains("团队没办法进入") and leader.automation.position_map==120,"confirmation rechecks actual party and source PartyMsg")
 r=hub.handle(1,{"type":"quest_talk","npc_id":gate.id})
 check(r.ok and r.dialogue.text.contains("团队没办法进入") and r.dialogue.choices[0].id=="ok","grouped opening shows original PartyMsg without pass")
 hub.shut_down();hub.queue_free()
func gate_lan()->void:
 var b=fresh();install_gate(b);root.add_child(b)
 b.session._profile.player.level=50;source_talk(b,gate);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"free gate two-device port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"gate two remote devices ready")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 b.session._profile.player.level=49
 check(not (await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes","level":80,"free":true})).ok,"second device cannot forge current free condition")
 b.session._profile.player.level=50
 r=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok and b.automation.position_map==122,"second device uses same authoritative saved free Warp")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
