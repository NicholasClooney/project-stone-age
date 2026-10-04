extends "res://tests/quest_delivery_routes_test.gd"
const Wait=preload("res://tests/support/wait.gd")
func begin(b,job:int)->void:
 check(b.handle({"type":"quest_auto_start","quest_id":job,"client":"delivery-boundary"}).get("ok",false),"start boundary job %d"%job)
func expect_manual(b,note:String)->void:
 b.quest_auto.tick(b,0.21)
 check(not b.quest_auto.running and b.quest_auto.phase=="manual" and not b.quest_auto.message.is_empty() and b.original_quests.pending.is_empty(),note)
func run()->void:
 var b=fixture(1400,Vector2i(68,90))
 for job in [13,24,25,9]:
  var before:Dictionary=b.session.snapshot();begin(b,job)
  expect_manual(b,"missing prerequisite stops %d"%job)
  check(b.session.snapshot()==before,"no fabricated prerequisite %d"%job)
 check(not b.handle({"type":"quest_auto_start","quest_id":23,"client":"delivery-boundary"}).get("ok",false),"Goya pet exchange6 remains unsupported")
 begin(b,12);b.quest_auto.tick(b,0.21)
 check(b.original_quests.pending.get("phase","")=="REQUEST","runner opens original request")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-delivery-boundaries/save.json"
 expect_manual(b,"source request savefail stops actual runner")
 check(b.session.snapshot()==before and not Rules.flag(b.session.snapshot(),"now",3),"savefail never grants axe or advances NOW3")
 b.save_path=""
 begin(b,12);b.quest_auto.tick(b,0.21);b.quest_auto.tick(b,0.21);b.quest_auto.tick(b,0.21)
 check(2416 in b.session.snapshot().original_items,"manual restart accepts original request")
 b.quest_auto.stop(b)
 check(b.handle({"type":"quest_discard","item_id":2416}).get("ok",false),"lose axe through production discard")
 before=b.session.snapshot();begin(b,12)
 expect_manual(b,"lost quest item never cancels or auto-reissues")
 check(b.session.snapshot()==before,"no charm loss on lost item stop")
 b.free()
 # Real plan source, with a deliberately unexpected choice response. This is
 # a dialogue boundary fixture, not an invented reward step in the six jobs.
 b=fixture(1400,Vector2i(68,90));begin(b,12);b.quest_auto.tick(b,0.21)
 before=b.session.snapshot()
 b.quest_auto.strict_dialogue_reply(b,{"ok":true,"dialogue":{"choices":[{"id":"yes"},{"id":"no"},{"id":"reward_2"}]}})
 check(not b.quest_auto.running and b.quest_auto.phase=="manual" and b.session.snapshot()==before and b.original_quests.pending.is_empty(),"extra reward choice ends actual runner without consent")
 b.free()
 await lan()
 print("QUEST DELIVERY BOUNDARIES: %d failures"%failures)
 quit(1 if failures else 0)
func lan()->void:
 var b=fixture(1400,Vector2i(68,90));root.add_child(b);b.set_process(false)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"real LAN ephemeral port")
 var links:Array=[];var states:Array=[];var pumps:Array=[]
 for index in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new();link.message.connect(state.apply)
  var pump:Callable=func():link.poll(0.016)
  process_frame.connect(pump);links.append(link);states.append(state);pumps.append(pump);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"backend-free LAN ready")
  await rpc(link,{"type":"ping"})
 check(links.all(func(link):return link.backend==null),"remote clients own no backend")
 var start:Dictionary=await rpc(links[0],{"type":"quest_auto_start","quest_id":12,"client":"delivery-route"})
 check(start.get("ok",false),"LAN starts real delivery job")
 b.quest_auto.tick(b,0.21)
 var token:String=str(b.original_quests.pending.get("token",""))
 check(not token.is_empty(),"real original request token exists")
 check((await rpc(links[1],{"type":"quest_auto_stop"})).get("ok",false) and not b.quest_auto.running,"second device stops first runner")
 var stale:Dictionary=await rpc(links[0],{"type":"quest_choose","token":token,"choice":"yes"})
 check(not stale.get("ok",false) and 2416 not in b.session.snapshot().original_items,"stopped token cannot replay transaction")
 if await drive(b,12,links[1]):
  for link in links:await rpc(link,{"type":"ping"})
  check(states.all(func(state):return Rules.flag(state.profile,"ended",3) and 2416 not in state.profile.original_items),"both LAN devices observe one earned END3")
  persisted(b,"lan-yam")
 for index in range(2):links[index].close();process_frame.disconnect(pumps[index])
 server.stop();server.queue_free();b.queue_free();await process_frame
