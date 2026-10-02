extends "res://tests/marju_quest_test.gd"
const KATAN="seimu/event/event02_1@100:230:180:area:525:200"
func prepare():
 var b=Backend.new();clean_bag(b)
 b.session.gm_raise_level(-1,80)
 b.session._profile.pets=[];b.session._profile.active_pet=-1;b.session._profile.ride_pet=-1
 b.session._profile.default_companions_claimed=true
 return b
func pet(b,species:int,level:int=25) -> String:
 check(b.session.gm_grant_pet(species),"source pet birth %d"%species)
 var uid:String=b.session._profile.pets[-1].pet_id
 check(b.session.level_pet_to(uid,level),"real growth to exact source level")
 return uid
func born(b) -> bool:
 return await Wait.until(self,func():return not b.original_quests.npc_by_id(KATAN).is_empty())
func run() -> void:
 var b=prepare()
 check(35 in b.quest_catalog.enabled_events and await born(b),"registered source NPC actually spawns")
 var npc:Dictionary=b.original_quests.npc_by_id(KATAN)
 var cell:Array=npc.cell.duplicate()
 var offset:=(int(cell[1])-180)*296+int(cell[0])-230
 check(offset>=0 and offset<6216 and str(npc.source_spawn.walkable).substr(offset,1)=="1","actual random cell obeys pinned C mapset mask")
 var target:Dictionary=b.quest_helper.destination(b,npc,"near")
 check(not target.is_empty(),"actual born cell has safe reachable original interaction neighbour")
 if target.is_empty():b.free();quit(1);return
 var request_offer:Dictionary=talk(b,KATAN)
 var request_before:Dictionary=b.session.snapshot();b.save_path="user://missing-katan-dir/save.json"
 check(not choose(b,request_offer,"yes").ok and b.session.snapshot()==request_before,"request save failure does not set NOW35 or mutate roster")
 b.save_path=""
 check(trade(b,KATAN).ok and Rules.flag(b.session.snapshot(),"now",35),"real source request starts35 without completion")
 var steps:Array=row(b,35).steps
 for species in [221,222,223,224]:
  var captures:Array=steps.filter(func(s):return s.id=="katan:pet:%d"%species)
  check(captures.size()==1 and captures[0].has("map_id") and int(captures[0].source.level_max)<=25,"real helper has ordinary capturable source route %d"%species)
 var first:=pet(b,223,24);pet(b,224,26)
 var before:Dictionary=b.session.snapshot();trade(b,KATAN)
 check(b.session.snapshot().pets==before.pets and not 2607 in b.session.snapshot().original_items,"24 and26 fail exact25 through actual dialogue")
 b.session.level_pet_to(first,25)
 b.session._profile.pets.remove_at(1)
 var second:=pet(b,224)
 b.session._profile.pets[1].original_end_event=1
 before=b.session.snapshot();trade(b,KATAN)
 check(b.session.snapshot().pets==before.pets and not 2607 in b.session.snapshot().original_items,"event pet cannot satisfy original ordinary-pet handover")
 b.session._profile.pets[1].original_end_event=0
 var spare:=pet(b,223);var spare_second:=pet(b,224)
 var answer:=choose(b,talk(b,KATAN),"yes")
 b.session._profile.pets[1].original_end_event=1;before=b.session.snapshot()
 check(not choose(b,answer,"ok").ok and b.session.snapshot()==before,"confirmed pair cannot silently substitute another eligible UID")
 b.session._profile.pets[1].original_end_event=0
 b.session._profile.active_pet=1;b.session._profile.ride_pet=3
 b.session._profile.automation_settings={"capture":{"pet":3,"pet_id":spare_second}}
 b.automation.settings.capture_pet=3;b.automation.settings.capture_pet_id=spare_second;b.automation.training_pet_id=first
 answer=choose(b,talk(b,KATAN),"yes");before=b.session.snapshot();b.save_path="user://missing-katan-dir/save.json"
 check(not choose(b,answer,"ok").ok and b.session.snapshot()==before,"first-pair save failure restores every pet/index/UID and proof")
 check(b.original_quests.npc_by_id(KATAN).cell==cell,"failed transaction does not reroll born cell")
 b.save_path=""
 check(trade(b,KATAN).ok,"actual first pair commits")
 var state:Dictionary=b.session.snapshot()
 check(state.pets.map(func(p):return str(p.pet_id))==[spare,spare_second] and state.original_items==[2607],"exact two bound UIDs consumed and source proof granted")
 check(state.active_pet==-1 and state.ride_pet==1 and b.automation.settings.capture_pet==1 and b.automation.training_pet_id=="","all surviving pet indexes repair only after commit")
 check(row(b,35).steps.any(func(s):return s.id=="katan:second" and s.current),"proof advances helper to second pair")
 pet(b,221);pet(b,222)
 for i in range(Session.PET_CAPACITY-b.session._profile.pets.size()):pet(b,173,1)
 answer=choose(b,talk(b,KATAN),"yes");before=b.session.snapshot();b.save_path="user://missing-katan-dir/save.json"
 check(not choose(b,answer,"ok").ok and b.session.snapshot()==before,"second-pair save failure rolls back full roster/proof/reward UID/completion")
 b.save_path="user://katan-quest.json"
 answer=choose(b,talk(b,KATAN),"yes")
 check(choose(b,answer,"ok").ok,"full roster permits original net two-for-one reward")
 state=b.session.snapshot()
 check(state.pets.size()==Session.PET_CAPACITY-1 and int(state.pets[-1].source_enemy_id)==93 and int(state.pets[-1].level)==1 and Rules.flag(state,"ended",35) and not 2607 in state.original_items,"original level1 Xiubao93 and END35 commit together")
 check(not choose(b,answer,"ok").ok,"completed token cannot repeat reward")
 before=b.session.snapshot();trade(b,KATAN)
 check(b.session.snapshot().pets==before.pets and b.session.snapshot().original_items==before.original_items,"finished source branch cannot reward again")
 var loaded=Backend.new()
 check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_events==state.original_events and JSON.parse_string(JSON.stringify(loaded.session.snapshot().pets))==JSON.parse_string(JSON.stringify(state.pets)),"actual source reward and completion reload")
 check(not JSON.stringify(loaded.session.snapshot()).contains("source_spawn") and not JSON.stringify(loaded.session.snapshot()).contains(KATAN),"source birthplace never enters save schema")
 check(loaded.original_quests.npc_state!=b.original_quests.npc_state and await born(loaded),"restart owns new source RNG/state and births again")
 loaded.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(b.save_path+suffix))
 b.free();await lan_katan()
 print("KATAN QUEST: %d failures"%failures);quit(1 if failures else 0)
func lan_katan() -> void:
 var b=prepare();root.add_child(b)
 check(await born(b) and trade(b,KATAN).ok,"LAN source birth/request")
 pet(b,223);pet(b,224)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"two-device server uses port0")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new();link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"real remote state connects")
  await rpc(link,{"type":"ping"})
 check(states[0].derived.quest_npcs[KATAN]==states[1].derived.quest_npcs[KATAN],"both devices see same random born cell")
 await rpc(links[0],{"type":"quest_visit","quest_id":4,"step_id":"katan:first","mode":"near"})
 var first:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":KATAN})
 var second:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":KATAN})
 check(not (await rpc(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})).ok,"other socket invalidates old first-pair offer")
 second=await rpc(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
 check((await rpc(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"ok"})).ok,"socket commits actual first pair")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return s.profile.original_items==[2607] and s.profile.pets.is_empty()),"first pair is identical on both devices")
 pet(b,221);pet(b,222)
 var last:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":KATAN})
 last=await rpc(links[0],{"type":"quest_choose","token":last.dialogue.token,"choice":"yes"})
 check((await rpc(links[0],{"type":"quest_choose","token":last.dialogue.token,"choice":"ok"})).ok,"socket commits original second pair")
 check(not (await rpc(links[1],{"type":"quest_choose","token":last.dialogue.token,"choice":"ok"})).ok,"other device cannot duplicate Xiubao")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return Rules.flag(s.profile,"ended",35) and s.profile.pets.size()==1 and int(s.profile.pets[0].source_enemy_id)==93),"both sockets receive one original reward and completion")
 check(states[0].derived.quest_npcs[KATAN]==states[1].derived.quest_npcs[KATAN],"successful deliveries retain original born cell")
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame
