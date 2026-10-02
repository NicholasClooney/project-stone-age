extends "res://tests/saton_cave_route_test.gd"
const Saton=preload("res://server/saton_cave_helper.gd")
func run()->void:
 var b=setup()
 check(trade(b,ELDER).ok,"source Saton request")
 for npc in guards:
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode}).ok,"village cannot skip original cave route")
 for location in [[10701,76,67],[10702,22,3],[10703,64,3],[10704,4,26],[10704,46,11],[10705,53,74]]:
  var map_id:int=location[0];var pos:=Vector2i(location[1],location[2])
  var region:int=Saton.region_at(b.quest_helper,b,map_id,pos)
  check(region>=0,"source landing resolves unique component")
  for i in range(guards.size()):
   var npc:Dictionary=guards[i]
   for mode in ["near","arrival"]:
    b.automation.position_changed(map_id,pos)
    var dest:Dictionary=b.quest_helper.destination(b,npc,mode)
    print("SATON DEST ",location," ",npc.id," ",mode," ",dest)
    check(dest.is_empty() or (int(dest.map_id)==map_id and Saton.region_at(b.quest_helper,b,map_id,Vector2i(int(dest.cell[0]),int(dest.cell[1])))==region),"final destination cannot cross original component")
    var r:Dictionary=b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode})
    check(bool(r.ok)==not dest.is_empty(),"raw NPC uses same filtered landing")
    if r.ok:check(Saton.region_at(b.quest_helper,b,map_id,b.automation.position_cell)==region,"actual backend position stays in original component")
    b.automation.position_changed(map_id,pos)
    r=b.handle({"type":"quest_visit","quest_id":10,"step_id":"saton13:battle%d"%(i+1),"mode":mode})
    check(bool(r.ok)==not dest.is_empty(),"old helper step obeys current authoritative map and component")
 b.automation.position_changed(10701,Vector2i(76,67))
 Saton.region_cache.clear();b.quest_helper.maps[10701]={}
 check(b.quest_helper.destination(b,guards[0],"near").is_empty(),"unreadable original map fails closed")
 Saton.region_cache.clear();b.free()
 await remote_navigation()
 await remote_characters()
 print("SATON CAVE NAVIGATION: %d failures"%failures);quit(1 if failures else 0)
func remote_navigation()->void:
 var b=setup();root.add_child(b);trade(b,ELDER)
 b.automation.position_changed(10701,Vector2i(76,67))
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"Saton ephemeral remote server")
 var states:Array=[]
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link)
  var state=preload("res://network/client_state.gd").new();states.append(state);link.message.connect(state.apply);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"Saton two devices online")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(not (await request(links[0],{"type":"quest_visit","npc_id":guards[2].id,"mode":"near"})).ok,"remote future third guardian remains locked")
 check((await request(links[0],{"type":"quest_visit","quest_id":10,"step_id":"saton13:battle1","mode":"near"})).ok,"reached first-floor guard navigable")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":guards[0].id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"other device confirms real guard battle")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-saton-remote/save.json"
 fight(b)
 check(b.session.snapshot()==before and not b.original_quests.npc_by_id(guards[0].id).is_empty(),"failed save preserves loot and guard visibility")
 b.save_path=""
 check((await request(links[1],{"type":"battle_close"})).ok,"other device retries same saved settlement")
 for link in links:await request(link,{"type":"ping"})
 check(states.all(func(s):return s.derived.quest_npcs.get(guards[0].id,{}).get("hidden",false)),"both devices see personal guard hidden")
 check(not (await request(links[0],{"type":"quest_visit","npc_id":guards[0].id,"mode":"near"})).ok,"hidden raw guard cannot be revisited")
 check(not (await request(links[1],{"type":"quest_visit","quest_id":10,"step_id":"saton13:battle1","mode":"near"})).ok,"hidden stale helper step rejected")
 now+=300;b.original_quests.refresh_npc_state();b.publish()
 for link in links:await request(link,{"type":"ping"})
 check(states.all(func(s):return s.derived.quest_npcs.get(guards[0].id,{}).get("hidden",false)),"both devices keep guard hidden at exactly300")
 now+=1;b.original_quests.refresh_npc_state();b.publish()
 for link in links:await request(link,{"type":"ping"})
 check(states.all(func(s):return not s.derived.quest_npcs.get(guards[0].id,{}).get("hidden",false)),"both devices restore strictly after300")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()

func remote_characters()->void:
 var folder:="user://saton-characters-%d"%OS.get_process_id()
 var hub=Hub.new(folder.path_join("accounts.json"));hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"actual isolated two-character hub")
 for name in ["Alice","Bob"]:check(hub.accounts.create(name,"1234").ok,"real Saton account created")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"Saton three-socket server")
 var states:Array=[]
 for i in range(3):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link)
  var state=preload("res://network/client_state.gd").new();states.append(state);link.message.connect(state.apply);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"three real sockets await account login")
 for i in range(3):
  links[i].login({"type":"login","name":"Alice" if i<2 else "Bob","pin":"1234"},func(_r):pass)
  check(await Wait.until(self,func():poll();return links[i].online),"device logs into correct original account")
 var a=hub.backends.alice;var other=hub.backends.bob
 for backend in [a,other]:
  var template=fresh();backend.session._profile=template.session.snapshot();template.free()
  backend.original_quests.npc_state.clock=func():return now
  trade(backend,ELDER)
 var npc:Dictionary=guards[0]
 source_talk(a,npc);a.original_quests.pending={};a.publish();other.publish()
 for link in links:await request(link,{"type":"ping"})
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"Alice second device starts actual source guard")
 fight(a);check((await request(links[1],{"type":"battle_close"})).ok,"Alice saves real reward settlement")
 for link in links:await request(link,{"type":"ping"})
 check(states[0].derived.quest_npcs.get(npc.id,{}).get("hidden",false) and states[1].derived.quest_npcs.get(npc.id,{}).get("hidden",false),"Alice both devices hide same guard")
 check(not states[2].derived.quest_npcs.get(npc.id,{}).get("hidden",false) and not other.original_quests.npc_by_id(npc.id).is_empty(),"Bob real account retains original visible guard")
 check(states[0].profile.original_items.count(2428)==1 and states[2].profile.original_items.count(2428)==0,"treasure belongs only to actual winning character")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()
