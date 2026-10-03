extends "res://tests/original_fixed_guards_test.gd"
const Travel=preload("res://tests/support/water_route_driver.gd")
func source_talk(b,npc:Dictionary)->Dictionary:
 if not b.quest_arrival.has_arrival(b,int(npc.map_id),b.automation.position_cell) or not Travel.walk_near(b,npc,range(20801,20808)):
  var entered:=false
  for portal in b.quest_helper.places.links(200).values():
   if int(portal.to_map)==20801 and not portal.get("disabled",false):
    b.automation.position_changed(200,Vector2i(int(portal.cell[0]),int(portal.cell[1])))
    entered=b.handle({"type":"report_position","map_id":20801,"cell":portal.target}).get("ok",false);break
  check(entered and Travel.walk_near(b,npc,range(20801,20808)),"real seven-floor dragon route precedes jewel gate")
 return b.handle({"type":"quest_talk","npc_id":npc.id})
var gate:Dictionary={}
func install(b)->void:
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-dragon-gate.json"))
 gate=f.module.npcs[0];b.session.world_catalog.maps.merge(f.maps)
 b.quest_catalog.npcs.append(gate.duplicate(true));b.quest_catalog.items.merge(f.module.items);b.quest_catalog.enabled_events.append(17)
func jewels(b)->void:
 for id in [2457,2458,2459]:Session.OriginalEquipment.add(b.session._profile,id)
func run()->void:
 var b=Backend.new();install(b)
 for missing in [2457,2458,2459]:
  b.session._profile.original_items=[];Session.OriginalEquipment.migrate(b.session._profile)
  for id in [2457,2458,2459]:
   if id!=missing:Session.OriginalEquipment.add(b.session._profile,id)
  var r:=source_talk(b,gate)
  check(r.ok and r.dialogue.choices[0].id=="ok" and not choose(b,r,"yes").ok,"each missing original jewel refuses gate %d"%missing)
 b.session._profile.original_items=[];Session.OriginalEquipment.migrate(b.session._profile);jewels(b)
 var r:=source_talk(b,gate);var before:Dictionary=b.session.snapshot()
 check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel preserves three jewels and location")
 r=source_talk(b,gate);Session.OriginalEquipment.remove(b.session._profile,2459)
 check(not choose(b,r,"yes").ok,"confirm rechecks latest third jewel")
 Session.OriginalEquipment.add(b.session._profile,2459);r=source_talk(b,gate);before=b.session.snapshot();var origin:Vector2i=b.automation.position_cell
 b.save_path="user://missing-dragon-gate/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before and b.automation.position_cell==origin,"failed save rolls back original gate Warp")
 b.save_path="user://dragon-gate.json";r=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.automation.position_cell==Vector2i(13,35),"three jewels open exact source Warp")
 check(b.session.snapshot().original_instances==before.original_instances and b.session.snapshot().player.gold==before.player.gold,"source has no DelItem or charge; all original UIDs survive")
 var loaded=Backend.new();install(loaded)
 check(loaded.load_profile(b.save_path) and int(loaded.session.snapshot().location.x)==13 and int(loaded.session.snapshot().location.y)==35 and loaded.session.snapshot().original_instances==before.original_instances,"real gate save validates and reloads unchanged jewels")
 loaded.free();b.free()
 await lan_gate()
 print("ORIGINAL DRAGON GATE: %d failures"%failures);quit(1 if failures else 0)
func lan_gate()->void:
 var hub=Hub.new("user://dragon-gate-lan-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"dragon real hub")
 for name in ["Alice","Bob"]:check(hub.accounts.create(name,"1234").ok,"dragon profile created")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"dragon ephemeral sockets")
 for i in range(3):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"dragon three sockets connect")
 for i in range(3):
  links[i].login({"type":"login","name":"Alice" if i<2 else "Bob","pin":"1234"},func(_reply):pass)
  check(await Wait.until(self,func():poll();return links[i].online),"dragon device login")
 var a=hub.backends.alice;var other=hub.backends.bob
 for b in [a,other]:install(b);jewels(b)
 source_talk(a,gate);a.original_quests.pending={};var origin:Vector2i=a.automation.position_cell;other.automation.position_changed(20807,origin+Vector2i.RIGHT)
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 check((await request(links[2],{"type":"party_join","facing":1})).ok,"party enters between gate offer and confirmation")
 var result:Dictionary=await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 check(not result.ok and result.reason.contains("不能团体进入") and a.automation.position_cell==origin,"second device cannot bypass authoritative party restriction")
 await request(links[2],{"type":"party_leave"})
 r=await request(links[0],{"type":"quest_talk","npc_id":gate.id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok and a.session.snapshot().original_items.size()==3,"solo second device commits without consuming jewels")
 check(not (await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"dragon remote token replay rejected")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()
