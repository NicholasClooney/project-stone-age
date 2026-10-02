extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Wait=preload("res://tests/support/wait.gd")
const YAM="sainasu/event/event03_2@1400:69:89"
const MATI="sainasu/event/event03_1@1300:18:42"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func row(b,event:int) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==event:return q
 return {}
func talk(b,id:String) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":id,"mode":"near"})
 check(visit.ok,"real safe visit "+id)
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,c:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c})
func trade(b,id:String) -> Dictionary:
 var r:=choose(b,talk(b,id),"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func run() -> void:
 var b=Backend.new()
 check(3 in b.quest_catalog.enabled_events and 5 in b.quest_catalog.enabled_events,"public registration enables both axe stages")
 check(row(b,3).steps.size()==2 and row(b,5).steps.size()==2,"both stages have actionable original helper steps")
 check(row(b,5).blocked_reason.contains("先把"),"return-letter helper exposes prerequisite")
 check(not b.original_quests.npc_by_id(YAM).is_empty(),"real imported NPC exists")
 if b.original_quests.npc_by_id(YAM).is_empty():b.free();quit(1);return
 b.session.gm_raise_level(-1,25)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-yam-dir/save.json"
 check(not trade(b,YAM).ok and b.session.snapshot().original_events==before.original_events and b.session.snapshot().original_items==before.original_items,"failed request save grants neither flag nor axe")
 b.save_path=""
 check(trade(b,YAM).ok and 2416 in b.session.snapshot().original_items and Rules.flag(b.session.snapshot(),"now",3),"real source request grants temporary axe and NOW3")
 var uid:=int(b.session.snapshot().original_instances[0].uid)
 check(b.session.equip_item("original:%d"%uid),"source temporary axe is usable at Lv20+")
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(MATI),b.session.snapshot()).is_empty(),"source ITEM=2416 refuses worn-only axe")
 check(b.session.equip_item("original:%d"%uid),"unequip before original delivery")
 var thanks:=choose(b,talk(b,MATI),"yes")
 before=b.session.snapshot();b.save_path="user://missing-yam-dir/save.json"
 check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,"failed END3 save retains axe and flags")
 b.save_path=""
 check(trade(b,MATI).ok and Rules.flag(b.session.snapshot(),"ended",3) and not 2416 in b.session.snapshot().original_items,"delivery consumes axe and only completes END3")
 check(not Rules.flag(b.session.snapshot(),"ended",5),"END3 never stands in for END5")
 check(trade(b,MATI).ok and 2423 in b.session.snapshot().original_items and Rules.flag(b.session.snapshot(),"now",5),"second conversation really issues letter")
 check(b.handle({"type":"quest_discard","item_id":2423}).ok,"lost letter fixture uses real discard")
 var charm:=int(b.session.snapshot().player.charm)
 check(trade(b,MATI).ok and not Rules.flag(b.session.snapshot(),"now",5) and int(b.session.snapshot().player.charm)==charm-1,"lost letter cancellation preserves original charm penalty")
 check(trade(b,MATI).ok and 2423 in b.session.snapshot().original_items,"cancelled letter can be reaccepted")
 thanks=choose(b,talk(b,YAM),"yes")
 before=b.session.snapshot();b.save_path="user://missing-yam-dir/save.json"
 check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,"failed final save neither swallows letter nor grants axe")
 b.save_path=""
 thanks=choose(b,talk(b,YAM),"yes")
 check(choose(b,thanks,"ok").ok and Rules.flag(b.session.snapshot(),"ended",5) and b.session.snapshot().original_items==[2448],"END5 atomically grants only final axe2448")
 check(not choose(b,thanks,"ok").ok,"reward token cannot replay")
 before=b.session.snapshot();talk(b,YAM);talk(b,MATI)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"repeated conversations cannot restart completed chain")
 var path:="user://yam-full-chain.json"
 check(b.session.save_game(path),"full chain persists")
 var restored=Session.new()
 check(restored.load_game(path) and restored.snapshot().original_events==b.session.snapshot().original_events and restored.snapshot().original_items==[2448],"load preserves both END flags and final reward")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 b.free()
 await lan()
 print("YAM AXE QUEST: %d failures"%failures)
 quit(1 if failures else 0)
func rpc(link,command:Dictionary) -> Dictionary:
 var replies:Array=[]
 link.request(command,func(r):replies.append(r))
 check(await Wait.until(self,func():return not replies.is_empty()),"LAN command roundtrip")
 return replies[0] if not replies.is_empty() else {}
func lan() -> void:
 var b=Backend.new();root.add_child(b)
 check(trade(b,YAM).ok and trade(b,MATI).ok and trade(b,MATI).ok,"LAN fixture earned letter through actual source chain")
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"LAN server uses ephemeral port")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new()
  link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"second-device profile connected")
  await rpc(link,{"type":"ping"})
 check(links.all(func(l):return l.backend==null),"LAN clients have no authority backend")
 await rpc(links[0],{"type":"quest_visit","npc_id":YAM,"mode":"near"})
 var opened:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":YAM})
 var thanks:Dictionary=await rpc(links[0],{"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 await rpc(links[0],{"type":"ping"})
 var other:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":YAM})
 var stale:Dictionary=await rpc(links[0],{"type":"quest_choose","token":thanks.dialogue.token,"choice":"ok"})
 check(not stale.ok and 2423 in b.session.snapshot().original_items,"device B invalidates A pending reward without consuming letter")
 other=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"yes"})
 var done:Dictionary=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"ok"})
 check(done.ok,"device B commits earned reward")
 for i in range(2):await rpc(links[i],{"type":"ping"})
 check(states.all(func(s):return Rules.flag(s.profile,"ended",5) and s.profile.original_items.count(2448)==1),"both device snapshots see exactly one final axe")
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame
