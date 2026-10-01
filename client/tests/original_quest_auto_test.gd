extends "res://tests/quest_helper_ui_test.gd"
## Real event2 catalog/session/transactions; deterministic runner time only.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
class LinkPump extends Node:
 var links:Array=[]
 func _process(delta:float) -> void:
  for link in links:link.poll(delta)
func rpc(link,command:Dictionary) -> Dictionary:
 var answers:Array=[]
 if link.awaiting_login and str(command.type) in ["create_profile","login"]:link.login(command,func(reply:Dictionary):answers.append(reply))
 else:link.request(command,func(reply:Dictionary):answers.append(reply))
 if not await ready(func():return not answers.is_empty(),"Real WebSocket RPC answers "+str(command.type)):return {}
 return answers[0]
func remove_tree(path:String) -> void:
 if not DirAccess.dir_exists_absolute(path):return
 for entry in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(entry))
 for entry in DirAccess.get_directories_at(path):remove_tree(path.path_join(entry))
 DirAccess.remove_absolute(path)
func start(b) -> Dictionary:
 return b.handle({"type":"quest_auto_start","quest_id":11,"client":"test"})
func advance(b,confirm:bool=true) -> void:
 b.quest_auto.tick(b,0.21)
 if confirm and b.quest_auto.phase=="landing":
  b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
func finish(b) -> void:
 for index in range(40):
  if not b.quest_auto.running:return
  advance(b)
 check(false,"Runner completes within its finite source steps")
func run() -> void:
 for bit in range(4):
  var b=Backend.new()
  b.quest_catalog.enabled_events=[2]
  b.session._profile.original_savepoint_bits=1<<bit
  var before:Dictionary=b.session.snapshot()
  check(start(b).ok,"SP%d starts real shell direction" % bit)
  check(not start(b).ok,"Duplicate start refused")
  advance(b,false)
  var target:Dictionary=b.quest_auto.target.duplicate(true)
  for i in range(10):advance(b,false)
  check(b.quest_auto.phase=="landing" and b.session.snapshot()==before,"No exchange before client confirms authoritative landing")
  b.handle({"type":"report_position","map_id":target.map_id,"cell":target.cell,"client":"other"})
  check(b.quest_auto.phase=="landing","Other device cannot advance runner")
  b.handle({"type":"report_position","map_id":target.map_id,"cell":target.cell,"client":"test"})
  finish(b)
  var reward:int=2414 if bit in [0,3] else 2415
  check(Rules.flag(b.session._profile,"ended",2) and b.session._profile.original_items==[reward],"SP%d exactly original reward once" % bit)
  var completed:Dictionary=b.session.snapshot()
  check(not start(b).ok and b.session.snapshot()==completed,"Reward retained prevents replay/CLEAN")
  check(b.handle({"type":"quest_discard","item_id":reward}).ok,"Player explicitly discards reward")
  check(start(b).ok and b.quest_auto.clean_authorized,"Start authorizes only truly eligible CLEAN")
  finish(b)
  check(b.session._profile.original_items==[reward] and Rules.flag(b.session._profile,"ended",2),"Eligible repeat completes once without CLEAN loop")
  b.free()
 for wanted in ["travel","landing","talk","yes","ok"]:
  var b=Backend.new()
  b.quest_catalog.enabled_events=[2]
  check(start(b).ok,"Stop fixture starts")
  while b.quest_auto.phase!=wanted and b.quest_auto.running:
   advance(b,wanted!="landing")
  var before:Dictionary=b.session.snapshot()
  check(b.handle({"type":"quest_auto_stop"}).ok,"Stop accepted at "+wanted)
  for i in range(15):advance(b)
  check(not b.quest_auto.running and b.session.snapshot()==before and b.original_quests.pending.is_empty(),"Stop at %s never executes pending token or REQUEST cancel" % wanted)
  b.free()
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 start(b)
 advance(b,false)
 check(not b.handle({"type":"quest_talk","npc_id":b.quest_auto.step.npc_id}).ok,"External dialogue rejected during runner")
 check(not b.handle({"type":"quest_visit","quest_id":11,"step_id":"shell:request"}).ok,"External travel rejected during runner")
 b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[1,1],"client":"test"})
 check(not b.quest_auto.running,"Different manual position stops server runner")
 b.free()
 b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.quest_visit_guard=func():return "party"
 check(not start(b).ok,"Party locks start")
 b.quest_visit_guard=Callable()
 b.session._profile.original_savepoint_bits=0
 check(not start(b).ok,"Invalid source savepoint refuses start")
 b.free()
 var failed=Backend.new()
 failed.quest_catalog.enabled_events=[2]
 var before:Dictionary=failed.session.snapshot()
 start(failed)
 remove_tree("user://quest-auto-missing")
 failed.save_path="user://quest-auto-missing/failed.json"
 finish(failed)
 check(failed.session.snapshot()==before and failed.quest_auto.message=="save_failed","Failed original save rolls back and stops")
 failed.free()
 b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 for i in range(15):b.session._profile.original_items.append(2410)
 before=b.session.snapshot()
 check(start(b).ok,"Capacity fixture starts from authentic branch")
 finish(b)
 check(b.session.snapshot()==before and not Rules.flag(b.session._profile,"now",2),"Full inventory safely refuses original REQUEST")
 b.free()
 extra_stops_and_failures()
 await devices()
 await profiles()
 await remote_auto()
 print("ORIGINAL QUEST AUTO: %d failures" % failures)
 quit(1 if failures else 0)
func remote_auto() -> void:
 var backend=Backend.new()
 backend.quest_catalog.enabled_events=[2]
 root.add_child(backend)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
 root.add_child(server)
 if not check(server.start()==OK,"Auto ephemeral WebSocket starts"):return
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d" % server.port
 world=load("res://scenes/main.tscn").instantiate()
 script.server_url_override=""
 world.profile_persistence=false
 world.viewer_prefs_path="user://quest-auto-ui.cfg"
 var catalog=preload("res://scripts/quest_catalog.gd").new()
 catalog.enabled_events=[2]
 world.world_catalog.set_quest_catalog(catalog)
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Auto remote connects"):return
 if not check(await Wait.settle(self,world),"Auto startup settles"):return
 check(world.backend==null,"Remote automatic UI has no backend")
 world.quest_helper_menu.open_menu()
 var original_packs=world.asset_packs
 var gate:=PackGate.new()
 root.add_child(gate)
 world.asset_packs=gate
 var before:Dictionary=backend.session.snapshot()
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_11",true,false)):return
 check(gate.waiting.is_valid() and not backend.quest_auto.running,"Automatic button waits for download before server start")
 world.quest_helper_menu.close_menu()
 gate.finish(true)
 check(await Wait.settle(self,world),"Cancelled download settles")
 check(not backend.quest_auto.running and backend.session.snapshot()==before,"Close cancels late automatic download")
 world.asset_packs=original_packs
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_11",true,false)):return
 if not await ready(func():return backend.quest_auto.running and world.state.derived.get("quest_auto",{}).get("running",false),"Real button starts authoritative runner"):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStop",true,false)):return
 if not check(await Wait.settle(self,world),"Stop button settles"):return
 check(not backend.quest_auto.running,"Real stop button stops server immediately")
 before=backend.session.snapshot()
 for i in range(20):backend.quest_auto.tick(backend,0.21)
 check(backend.session.snapshot()==before,"Stopped server cannot execute more transactions")
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_11",true,false)):return
 if not await ready(func():return Rules.flag(backend.session._profile,"ended",2) and not backend.quest_auto.running,"Remote automatically confirms both downloaded maps and completes"):return
 if not check(await Wait.settle(self,world),"Completion settles"):return
 check(world.session.snapshot().original_items==[2414],"Remote reads original server reward")
 world.link.close()
 world.music.stop();world.effect.stop();world.queue_free()
 server.stop();server.queue_free();backend.queue_free();gate.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Auto remote disposed"):return
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quest-auto-ui.cfg"))

func extra_stops_and_failures() -> void:
 # Both directions, every REQUEST/ACCEPT confirmation, plus eligible CLEAN.
 for bit in [0,1]:
  for branch_type in ["REQUEST","ACCEPT","CLEAN"]:
   for wanted in ["landing","talk","yes","ok"]:
    var b=Backend.new()
    b.quest_catalog.enabled_events=[2]
    b.session._profile.original_savepoint_bits=1<<bit
    if branch_type=="CLEAN":Rules.set_flag(b.session._profile,"ended",2,true)
    check(start(b).ok,"Stop fixture %s/%s starts" % [branch_type,wanted])
    for index in range(40):
     if str(b.quest_auto.step.get("source",{}).get("type",""))==branch_type and b.quest_auto.phase==wanted:break
     advance(b,false)
     if b.quest_auto.phase=="landing" and not (str(b.quest_auto.step.source.type)==branch_type and wanted=="landing"):
      b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
    check(b.quest_auto.running and b.quest_auto.phase==wanted and str(b.quest_auto.step.source.type)==branch_type,"Reach specific original %s/%s" % [branch_type,wanted])
    var before:Dictionary=b.session.snapshot()
    b.handle({"type":"quest_auto_stop"})
    for i in range(20):advance(b)
    check(b.session.snapshot()==before and b.original_quests.pending.is_empty(),"Stop preserves finished transactions at %s/%s" % [branch_type,wanted])
    b.free()
  for branch_type in ["REQUEST","ACCEPT","CLEAN"]:
   var b=Backend.new()
   b.quest_catalog.enabled_events=[2]
   b.session._profile.original_savepoint_bits=1<<bit
   if branch_type=="CLEAN":Rules.set_flag(b.session._profile,"ended",2,true)
   start(b)
   for index in range(40):
    if str(b.quest_auto.step.source.type)==branch_type and b.quest_auto.phase==("ok" if branch_type=="ACCEPT" else "yes"):break
    advance(b)
   var before:Dictionary=b.session.snapshot()
   remove_tree("user://quest-auto-missing")
   b.save_path="user://quest-auto-missing/failed.json"
   finish(b)
   check(b.session.snapshot()==before and b.quest_auto.message=="save_failed","%s original save fails atomically" % branch_type)
   b.free()
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 start(b)
 b.battle_open=true
 advance(b)
 check(not b.quest_auto.running,"Battle stops runner before its next step")
 b.free()
 b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 start(b)
 b.quest_visit_guard=func():return "party changed"
 advance(b)
 check(not b.quest_auto.running,"Party changes stop before next transaction")
 b.free()
func drive_remote(link,b,client_id:String) -> void:
 for index in range(40):
  if not b.quest_auto.running:return
  b.quest_auto.tick(b,0.21)
  if b.quest_auto.phase=="landing":
   var target:Dictionary=b.quest_auto.target
   var reply:Dictionary=await rpc(link,{"type":"report_position","map_id":target.map_id,"cell":target.cell,"client":client_id})
   if not check(reply.ok,"Initiator confirms authoritative profile landing"):return
 check(false,"Remote profile finite chain completes")
func devices() -> void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.set_process(false)
 root.add_child(b)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1")
 root.add_child(server)
 check(server.start()==OK,"Two-device server listens on port0")
 var pump:=LinkPump.new()
 root.add_child(pump)
 var url:="ws://127.0.0.1:%d" % server.port
 var first=preload("res://network/ws_link.gd").new(url)
 var second=preload("res://network/ws_link.gd").new(url)
 pump.links=[first,second]
 first.connect_now();second.connect_now()
 if not await ready(func():return first.online and second.online and server.clients().size()==2,"Two actual devices connect"):return
 var reply:Dictionary=await rpc(first,{"type":"quest_auto_start","quest_id":11,"client":"initiator","_quest_connection":-777})
 check(reply.ok and b.quest_auto.connection!=-777,"Transport overrides forged ownership tag")
 var conflict:Dictionary=await rpc(first,{"type":"quest_visit","quest_id":11,"step_id":"shell:request"})
 check(not conflict.ok and conflict.type=="rejected","Remote conflict returns normal RPC rejection")
 b.quest_auto.tick(b,0.21)
 var target:Dictionary=b.quest_auto.target
 await rpc(second,{"type":"report_position","map_id":target.map_id,"cell":target.cell,"client":"initiator","_quest_connection":b.quest_auto.connection})
 check(b.quest_auto.phase=="landing","Other socket cannot spoof initiator landing confirmation")
 second.close()
 if not await ready(func():return server.clients().size()==1,"Other socket closes"):return
 check(b.quest_auto.running,"Other device disconnect does not stop initiator")
 second=preload("res://network/ws_link.gd").new(url)
 pump.links=[first,second]
 second.connect_now()
 if not await ready(func():return second.online and server.clients().size()==2,"Second device reconnects"):return
 reply=await rpc(second,{"type":"quest_auto_stop"})
 check(reply.ok and not b.quest_auto.running,"Same profile's other device can explicitly stop")
 reply=await rpc(first,{"type":"quest_auto_start","quest_id":11,"client":"initiator"})
 check(reply.ok,"Initiator starts again")
 var before:Dictionary=b.session.snapshot()
 first.close()
 if not await ready(func():return server.clients().size()==1 and not b.quest_auto.running,"Initiator disconnect stops owned runner"):return
 for index in range(30):b.quest_auto.tick(b,0.21)
 check(b.session.snapshot()==before,"Server executes no more transactions after initiator closes")
 reply=await rpc(second,{"type":"quest_auto_start","quest_id":11,"client":"other"})
 check(reply.ok,"Remaining device can start its own run")
 server.stop()
 check(not b.quest_auto.running,"Server stop immediately stops runner")
 second.close();pump.queue_free();server.queue_free();b.queue_free()
func profiles() -> void:
 var directory:="user://quest-auto-profiles"
 remove_tree(directory)
 var hub=preload("res://server/profile_hub.gd").new(directory.path_join("accounts.json"))
 hub.tick=false
 hub.share_dir=""
 root.add_child(hub)
 check(hub.start(),"Isolated profile hub starts")
 var server=preload("res://server/ws_server.gd").new(hub,0,"127.0.0.1")
 root.add_child(server)
 check(server.start()==OK,"Profile server binds port0")
 var pump:=LinkPump.new()
 root.add_child(pump)
 var url:="ws://127.0.0.1:%d" % server.port
 var alice=preload("res://network/ws_link.gd").new(url)
 var bob=preload("res://network/ws_link.gd").new(url)
 pump.links=[alice,bob]
 alice.connect_now();bob.connect_now()
 if not await ready(func():return alice.awaiting_login and bob.awaiting_login,"Two account devices need login"):return
 # Use the real WsLink login path while these sockets await authentication.
 var a:Dictionary=await rpc(alice,{"type":"create_profile","name":"Alice","pin":"1111"})
 var c:Dictionary=await rpc(bob,{"type":"create_profile","name":"Bob","pin":"2222"})
 check(a.ok and c.ok,"Real server creates two independent accounts")
 var ba=hub.backends.alice
 var bb=hub.backends.bob
 ba.quest_catalog.enabled_events=[2];bb.quest_catalog.enabled_events=[2]
 bb.session._profile.original_savepoint_bits=2
 var reply:Dictionary=await rpc(alice,{"type":"quest_auto_start","quest_id":11,"client":"alice","_quest_connection":-777})
 check(reply.ok and ba.quest_auto.connection!=-777 and not bb.quest_auto.running,"Hub binds initiator and keeps accounts separate")
 reply=await rpc(bob,{"type":"quest_auto_stop","profile":"alice","_quest_connection":ba.quest_auto.connection})
 check(reply.ok and ba.quest_auto.running,"Bob cannot stop Alice by forged profile/connection")
 reply=await rpc(bob,{"type":"quest_auto_start","quest_id":11,"client":"bob"})
 check(reply.ok and ba.quest_auto.running and bb.quest_auto.running,"Each profile has independent running state")
 # A real login on another socket replaces its previous account identity.
 reply=await rpc(bob,{"type":"login","name":"Alice","pin":"1111"})
 check(reply.ok and not bb.quest_auto.running and ba.quest_auto.running,"Switching initiator account stops its old runner only")
 reply=await rpc(bob,{"type":"quest_auto_stop"})
 check(reply.ok and not ba.quest_auto.running,"Second device logged into Alice can stop Alice")
 reply=await rpc(alice,{"type":"quest_auto_start","quest_id":11,"client":"alice"})
 check(reply.ok,"Alice starts before disconnect")
 alice.close()
 if not await ready(func():return not ba.quest_auto.running and hub.connections_of("alice").size()==1,"Hub stops initiating socket while same-account observer remains"):return
 reply=await rpc(bob,{"type":"quest_auto_start","quest_id":11,"client":"alice-other"})
 check(reply.ok,"Remaining Alice device starts continuation")
 await drive_remote(bob,ba,"alice-other")
 check(ba.session._profile.original_items==[2414] and not Rules.flag(bb.session._profile,"ended",2),"Alice completion does not change Bob's flags/items")
 reply=await rpc(bob,{"type":"login","name":"Bob","pin":"2222"})
 check(reply.ok,"Device returns to Bob")
 reply=await rpc(bob,{"type":"quest_auto_start","quest_id":11,"client":"bob"})
 check(reply.ok,"Bob starts independent reverse direction")
 await drive_remote(bob,bb,"bob")
 check(bb.session._profile.original_items==[2415] and ba.session._profile.original_items==[2414],"Two real profiles complete independent opposite original directions")
 var weak_hub=weakref(hub)
 server.stop();bob.close();hub.shut_down()
 pump.queue_free();server.queue_free();hub.queue_free()
 if not await ready(func():return weak_hub.get_ref()==null,"Profile test hub disposed"):return
 remove_tree(directory)
