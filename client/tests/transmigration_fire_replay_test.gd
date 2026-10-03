extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 var b=setup();root.add_child(b)
 Rules.set_flag(b.session._profile,"now",40,true)
 var phoenix:=source(b,"sink01")
 b.automation.position_changed(20309,Vector2i(44,47))
 var original:Dictionary=b.session.snapshot()
 check(not b.handle({"type":"quest_talk","npc_id":phoenix.id}).get("ok",false) and b.session.snapshot()==original,"raw project arrival cannot obtain actual feather or move Phoenix")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":phoenix.id,"mode":mode}).get("ok",false),"raw Phoenix helper cannot grant cave proof "+mode)
 Rules.set_flag(b.session._profile,"now",40,false)
 grant(b,[2709]);var dinosaur:=source(b,"sink055a")
 var water_request:=source_talk(b,dinosaur);water_request=choose(b,water_request,"yes")
 var water_before:Dictionary=b.session.snapshot();var dinosaur_before:Dictionary=b.original_quests.npc_by_id(dinosaur.id).duplicate(true)
 b.save_path="user://missing-fire-water-save/fail.json"
 check(not choose(b,water_request,"ok").get("ok",false) and b.session.snapshot()==water_before,"real route water savefail preserves input UID and whole profile")
 check(b.original_quests.npc_by_id(dinosaur.id)==dinosaur_before,"water savefail does not move personal dinosaur")
 b.save_path=""
 check(commit_trade(b,dinosaur).get("ok",false) and b.session.snapshot().original_items==[2712],"new water confirmation retries atomically after savefail")
 var messenger:=source(b,"sink06")
 check(source_talk(b,messenger).get("ok",false),"real original route and final battle reach messenger")
 b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"protected fire LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two devices share actual legitimate fire route")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":messenger.id})
 r=await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 var commit:={"type":"quest_choose","token":r.dialogue.token,"choice":"ok"}
 check((await request(links[1],commit)).ok,"second device commits legitimate original random reward")
 var after:Dictionary=b.session.snapshot()
 check(not (await request(links[0],commit)).ok and b.session.snapshot()==after,"protected random reward token replays cannot allocate extra UID")
 grant(b,[2712]);r=await request(links[0],{"type":"quest_talk","npc_id":messenger.id})
 r=await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 commit={"type":"quest_choose","token":r.dialogue.token,"choice":"ok"}
 var before:Dictionary=b.session.snapshot()
 b.automation.position_changed(30016,Vector2i(26,32))
 check(not (await request(links[1],commit)).ok and b.session.snapshot()==before,"same-component project movement invalidates other device old token without changing ticket UID")
 for mode in ["near","arrival"]:
  check(not (await request(links[0],{"type":"quest_visit","npc_id":messenger.id,"mode":mode})).ok,"rawNPC helper cannot wash project-invalidated final proof "+mode)
 for link in links:link.close()
 links.clear();server.stop();server.queue_free();b.queue_free();await process_frame
 print("TRANSMIGRATION FIRE REPLAY: %d failures"%failures);quit(1 if failures else 0)
