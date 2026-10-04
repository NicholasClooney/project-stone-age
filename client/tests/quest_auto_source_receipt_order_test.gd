extends "res://tests/quest_delivery_loading_ui_test.gd"
## Core publication regression: original queued source Warp, real WS/scene
## cold readiness and full ACK. No protected placement or arrival fixture.
const Equipment=preload("res://server/original_equipment.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
class RecordingBackend extends "res://server/backend.gd":
 var reports:Array=[]
 var events:Array=[]
 func handle(command:Dictionary)->Dictionary:
  var result:Dictionary=super.handle(command)
  if command.get("type")=="report_position":reports.append({"command":command.duplicate(true),"reply":result.duplicate(true)})
  return result
func source_fixture():
 var b=RecordingBackend.new();b.set_process(false)
 b.session._profile.player.level=35
 b.session._profile.no_random_encounters=true
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 Equipment.add(b.session._profile,2755);Equipment.add(b.session._profile,2752)
 b.automation.position_changed(811,Vector2i(30,22),true)
 b.event.connect(func(m):b.events.append(m.duplicate(true)))
 return b
func matching_ack(b,packet:Dictionary)->bool:
 for entry in b.reports:
  var command:Dictionary=entry.command
  var equal:bool=entry.reply.get("ok",false) and command.get("map_id")==packet.map_id and command.get("cell")==packet.cell and command.get("quest_position_seq")==packet.quest_position_seq
  for field in Motion.IDENTITY_FIELDS:equal=equal and command.get(field)==packet[field]
  if equal:return true
 return false
func queued_cancel()->bool:
 var b=source_fixture();b.save_path="user://source-order-cancel.json"
 if not check(b.save() and b.quest_auto.begin_source_run(b,"cancel",71).ok,"Cancellation fixture enters only through public gate"):return false
 b._process(0.21) # Open original confirmation.
 var observed:Dictionary={}
 b.event.connect(func(m):
  if m.get("type")!="quest_result" or m.get("text")!="before-source-position":return
  b.quest_auto.stop(b,"cancel before queued Warp delivery")
  var npc:Dictionary=b.original_quests.npc_by_id("genout/quz_800_29_19@800:29:19")
  observed.walk=Travel.walk_near(b,npc,[800])
  var manual:Dictionary=b.handle({"type":"quest_talk","npc_id":npc.id})
  observed.manual=manual.get("ok",false)
  observed.pending=b.original_quests.pending.duplicate(true)
  b.session._profile.player.gold+=1
  observed.saved=b.save()
  b.publish()
  b.emit_event({"type":"quest_result","text":"later-manual-event"})
 )
 b._depth+=1
 b.emit_event({"type":"quest_result","text":"before-source-position"})
 b._process(0.21) # Real source confirmation queues Warp then profiles.
 var original_gold:int=b.session._profile.player.gold
 var prepared:Dictionary=b.quest_auto.issued[-1].duplicate()
 var queued_profiles:Array=[]
 for entry in b._queue:
  if entry.get("type")=="profile":queued_profiles.append(entry.duplicate(true))
 b._depth-=1;b._flush()
 if not check(observed.get("walk",false) and observed.get("manual",false) and observed.get("saved",false),"Earlier observer cancels, walks real route, opens new manual page and saves independently"):return false
 if not check(b.original_quests.pending==observed.pending and not b.quest_auto.running,"Prepared old source cannot clear newer real manual page"):return false
 var warp_events:Array=b.events.filter(func(m):return m.get("type")=="position" and m.get("map_id")==800 and m.get("cell")==[14,26])
 if not check(warp_events.size()==1 and not Motion.tagged(warp_events[0]),"Cancelled committed Warp still emits once as original plain position"):return false
 if not check(b.events.filter(func(m):return m.get("quest_source_landing",false)).is_empty(),"Cancelled prepared source receipt never leaves backend"):return false
 if not check(b.events.any(func(m):return m.get("text")=="later-manual-event"),"Later manual event is preserved"):return false
 for profile in queued_profiles:
  if not check(profile.profile.player.gold==original_gold and b.events.has(profile),"Historical queued profile is delivered unchanged, not rewritten from later save"):return false
 if not check(b.session._profile.player.gold==original_gold+1 and not prepared.is_empty(),"Independent saved candidate remains distinct from prepared source"):return false
 b.free();return true
func run()->void:
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
 if not queued_cancel():return
 backend_node=source_fixture();backend_node.save_path="user://source-order-ws.json"
 if not check(backend_node.save(),"Real WS baseline saved"):return
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Source receipt WS uses port0"):return
 if not await create_world():return
 if not await ready(func():return int(world.data.map_id)==811 and not world.area_transition_busy,"Production scene shows public source lobby"):return
 if not check(await Wait.settle(self,world),"Public initial position settled"):return
 var original_packs=world.asset_packs
 var cold:=ColdMapPacks.new();root.add_child(cold);world.asset_packs=cold
 if not check(backend_node.quest_auto.begin_source_run(backend_node,world._client_id,server_node.clients()[0].get_instance_id()).ok,"Internal-only original source admission on actual transport"):return
 backend_node._process(0.21)
 if not check(await Wait.settle(self,world),"Source confirm page settles"):return
 backend_node.events.clear()
 backend_node._depth+=1
 backend_node._process(0.21)
 var packet:Dictionary={}
 var seen_position:=false
 for entry in backend_node._queue:
  if entry.has("_source_position"):
   packet=entry.packet.duplicate(true);seen_position=true
  elif seen_position and entry.get("type")=="profile":
   var auto:Dictionary=entry.derived.quest_auto
   if not check(auto.revision==packet.quest_revision and not auto.motion.is_empty(),"Real depth queue snapshots after source Warp already include prepared revision/motion"):return
 if not check(seen_position and packet.get("quest_source_landing",false),"Original committed Warp has one prepared source candidate"):return
 backend_node._depth-=1;backend_node._flush()
 if not await ready(func():return cold.waiting.is_valid(),"Actual remote map follow waits for cold destination"):return
 if not check(await Wait.settle(self,world) and not matching_ack(backend_node,packet) and backend_node.quest_auto.phase=="landing","Cold map cannot ACK early"):return
 if not check(not world.get_meta("quest_position_receipt",{}).is_empty(),"Queued post-Warp profiles do not erase legitimate receipt"):return
 cold.finish(true)
 if not await ready(func():return int(world.data.map_id)==800 and backend_node.quest_auto.phase=="travel","Cold ready sends full production ACK and releases landing"):return
 if not check(matching_ack(backend_node,packet),"Actual WS command contains every original receipt identity field"):return
 var origin:Vector2i=backend_node.automation.position_cell
 backend_node._process(0.21)
 if not check(backend_node.automation.position_cell!=origin,"Acknowledged source route continues by original next logical step"):return
 backend_node.quest_auto.stop(backend_node,"order regression complete")
 world.asset_packs=original_packs;cold.queue_free()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Order regression scene disposed"):return
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 print("QUEST AUTO SOURCE RECEIPT ORDER: PASS; queued history preserved; cold WS full ACK; cancellation plain Warp")
 quit(0)
