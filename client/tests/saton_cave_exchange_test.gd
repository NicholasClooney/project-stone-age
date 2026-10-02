extends "res://tests/yam_axe_quest_test.gd"
## Source-pinned exchange isolation. This does not certify the guard route.
const SATON="sainasu/event/event13_1@1112:16:15"
const YOUTH="sainasu/event/event13_2@1100:86:99"
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saton-cave-exchanges.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs)
 b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.enabled_events.append_array([13,14])
 b.session.gm_raise_level(-1,16)
 return b
func treasures(b) -> void:
 # These source battle drops are fixture inputs; guard acquisition is tested separately.
 for id in [2428,2429,2430]:Session.OriginalEquipment.add(b.session._profile,id)
func run() -> void:
 var b=setup()
 var request:=talk(b,SATON)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-saton-parent/save.json"
 check(not choose(b,request,"yes").ok and b.session.snapshot()==before,"initial REQUEST save failure preserves profile")
 b.save_path=""
 check(trade(b,SATON).ok and Rules.flag(b.session.snapshot(),"now",13) and b.session.snapshot().original_items.count(2431)==1,"original LV16 request issues exactly one footprint")
 check(b.handle({"type":"quest_discard","item_id":2431}).ok,"lost footprint uses real discard command")
 # MESSAGE performs its action while opening the source window, not on OK.
 talk(b,SATON);check(b.session.snapshot().original_items.count(2431)==1,"source MESSAGE replaces missing footprint")
 b.handle({"type":"quest_discard","item_id":2431})
 before=b.session.snapshot();b.save_path="user://missing-saton-parent/save.json"
 check(not talk(b,SATON).ok and b.session.snapshot()==before,"footprint MESSAGE save failure gives no item")
 b.save_path="";talk(b,SATON)
 treasures(b)
 var thanks:=choose(b,talk(b,SATON),"yes")
 before=b.session.snapshot();b.save_path="user://missing-saton-parent/save.json"
 check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,"three treasures and both completion flags roll back on save failure")
 b.save_path=""
 check(trade(b,SATON).ok,"source three-treasure exchange completes")
 check(Rules.flag(b.session.snapshot(),"ended",13) and Rules.flag(b.session.snapshot(),"ended",14),"source13 and approved14 committed together")
 check(b.session.snapshot().original_items==[2450],"three treasures plus footprint removed and only original medicine granted")
 var clean:=talk(b,YOUTH)
 before=b.session.snapshot()
 check(str(clean.get("dialogue",{}).get("text","")).contains("加点项14保留"),"project confirmation states preserved bonus14")
 check(choose(b,clean,"no").ok and b.session.snapshot()==before,"declining repeat leaves entire profile unchanged")
 clean=talk(b,YOUTH);before=b.session.snapshot();b.save_path="user://missing-saton-parent/save.json"
 check(not choose(b,clean,"yes").ok and b.session.snapshot()==before,"failed CLEAN preserves13 and14")
 check(not choose(b,clean,"yes").ok,"failed CLEAN token cannot replay")
 b.save_path=""
 check(choose(b,talk(b,YOUTH),"yes").ok and not Rules.flag(b.session.snapshot(),"ended",13) and Rules.flag(b.session.snapshot(),"ended",14),"confirmed source CLEAN removes13 alone")
 check(trade(b,SATON).ok,"approved repeat actually reaccepts original request")
 treasures(b)
 check(trade(b,SATON).ok and b.session.snapshot().original_items.count(2450)==2,"second real exchange awards a second medicine")
 b.free()
 await lan()
 print("SATON CAVE EXCHANGES: %d failures"%failures)
 quit(1 if failures else 0)
func lan() -> void:
 var b=setup();root.add_child(b)
 check(trade(b,SATON).ok,"LAN starts with original request")
 treasures(b);check(trade(b,SATON).ok,"LAN starts with completed original exchange")
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Saton LAN ephemeral port")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new()
  link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"two Saton devices share authoritative profile")
  await rpc(link,{"type":"ping"})
 await rpc(links[0],{"type":"quest_visit","npc_id":YOUTH,"mode":"near"})
 var first:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":YOUTH})
 await rpc(links[0],{"type":"ping"})
 var second:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":YOUTH})
 var stale:Dictionary=await rpc(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})
 check(not stale.ok and Rules.flag(b.session.snapshot(),"ended",13),"device B invalidates A old cleanup token without clearing13")
 var cancelled:Dictionary=await rpc(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"no"})
 check(cancelled.ok and Rules.flag(b.session.snapshot(),"ended",13) and Rules.flag(b.session.snapshot(),"ended",14),"device B cancel leaves13 and14")
 second=await rpc(links[1],{"type":"quest_talk","npc_id":YOUTH})
 var cleared:Dictionary=await rpc(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
 check(cleared.ok,"device B explicitly confirms cleanup")
 var replay:Dictionary=await rpc(links[0],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
 check(not replay.ok,"other device cannot replay committed cleanup")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return not Rules.flag(s.profile,"ended",13) and Rules.flag(s.profile,"ended",14) and s.profile.original_items.count(2450)==1),"both devices see13 cleared,14 and earned medicine preserved")
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame
