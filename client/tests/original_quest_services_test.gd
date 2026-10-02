extends "res://tests/bonus_quest_transactions_test.gd"
func service_setup():
 var b=setup()
 b.original_quests.services.private_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/golden-bui-private-services.json"))
 var npcs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/golden-bui-public-npcs.json"))
 b.quest_catalog.npcs.append_array(npcs);b.quest_catalog.enabled_events.append(44)
 return b
func public_only(value:Variant)->bool:
 if value is Dictionary:
  for key in value:
   if str(key) in ["state","service_state","services","questions","answer_choice","answer_text","answer_type","order"]:return false
   if not public_only(value[key]):return false
 elif value is Array:
  for entry in value:
   if not public_only(entry):return false
 return true
func run()->void:
 var b=service_setup();root.add_child(b)
 var npcs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/golden-bui-public-npcs.json"))
 var quiz:String=npcs[0].id;var janken:String=npcs[1].id
 b.quest_visit_guard=func():return "party"
 check(not talk(b,quiz).ok,"authoritative party rejects quiz opening")
 b.quest_visit_guard=Callable()
 Session.OriginalEquipment.add(b.session._profile,2752)
 var r:=talk(b,quiz)
 check(public_only(r),"opening reply excludes private service state")
 b.save_path="user://blocked-service-save/child.json"
 var before:Dictionary=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before and b.original_quests.pending.is_empty(),"entry save failure keeps ticket and consumes token")
 b.save_path=""
 r=choose(b,talk(b,quiz),"yes")
 check(r.ok and not 2752 in b.session.snapshot().original_items and b.original_quests.pending.has("service_state") and public_only(r),"saved ticket consumption installs private question, public reply hides answer")
 # Server reads its own state. Client-supplied answer/state cannot replace it.
 var state:Dictionary=b.original_quests.pending.service_state
 var correct:=str(state.get("answer_choice","submit"))
 var text:=str(state.get("answer_text",""))
 var token:String=r.dialogue.token
 r=b.handle({"type":"quest_choose","token":token,"choice":correct,"text":text,"state":{"correct":999},"answer_choice":"forged"})
 check(r.ok and public_only(r) and not b.handle({"type":"quest_choose","token":token,"choice":correct}).ok,"answer command ignores forged state and rejects replay")
 b.quest_visit_guard=func():return "party"
 check(not choose(b,r,"1").ok,"joining party mid-series invalidates answer")
 b.quest_visit_guard=Callable()
 # Explicitly approved original no-ticket exception still goes through same token layer.
 while 2751 in b.session.snapshot().original_items:Session.OriginalEquipment.remove(b.session._profile,2751)
 before=b.session.snapshot()
 r=choose(b,talk(b,janken),"yes")
 check(r.ok and public_only(r) and b.session.snapshot()==before,"no-ticket janken retains original approved behavior")
 var events:Array=[];b.event.connect(func(event):events.append(event))
 b.save_path="user://blocked-service-save/child.json"
 before=b.session.snapshot()
 var origin:=[b.automation.position_map,b.automation.position_cell]
 for index in range(40):
  r=choose(b,r,"rock")
  if not r.ok:break
 check(not r.ok and b.session.snapshot()==before and [b.automation.position_map,b.automation.position_cell]==origin and events.is_empty(),"final save failure publishes neither result nor warp")
 b.save_path=""
 r=choose(b,talk(b,janken),"yes")
 var closed:=false
 for index in range(40):
  r=choose(b,r,"rock")
  if bool(r.get("closed",false)):closed=true;break
 check(closed,"server RNG resolves janken")
 var result_index:=-1;var position_index:=-1
 for index in range(events.size()):
  if events[index].type=="quest_result":result_index=index
  if events[index].type=="position":position_index=index
 check(result_index>=0 and position_index>result_index and public_only(events),"saved result notification precedes map movement without private data")
 b.queue_free();await process_frame
 await service_lan(npcs)
 print("ORIGINAL QUEST SERVICES: %d failures"%failures)
 quit(1 if failures else 0)
func service_lan(npcs:Array)->void:
 var b=service_setup();root.add_child(b)
 var id:String=npcs[0].id
 Session.OriginalEquipment.add(b.session._profile,2752)
 place(b,id)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"service ephemeral LAN server")
 for index in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(link):return link.online)),"two service devices connect")
 for link in links:await request(link,{"type":"ping"})
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":id})
 var second:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":id})
 check(not (await request(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})).ok,"other device opening invalidates first token")
 var answer:Dictionary=await request(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
 check(answer.ok and public_only(answer),"actual LAN question contains no answers or private state")
 check(public_only(await request(links[0],{"type":"snapshot"})),"remote snapshot excludes questions and private answer state")
 check(not (await request(links[0],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})).ok and b.session.snapshot().original_items.is_empty(),"LAN cannot consume entry twice")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame
