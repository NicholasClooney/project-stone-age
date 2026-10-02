extends "res://tests/original_fixed_guards_test.gd"
const Clock=preload("res://server/original_world_clock.gd")
var seconds:=Clock.ERA
var time_npcs:Array=[]
func install(b)->void:
 b.quest_catalog.npcs.append_array(time_npcs.duplicate(true))
 if 34 not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(34)
func at_hour(value:int)->void:seconds=Clock.ERA+int(ceil(float(value)*5400.0/1024.0))
func run()->void:
 var previous:=Clock.clock;Clock.clock=func():return seconds
 time_npcs=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dream-timeman.json")).module.npcs
 var b=Backend.new();install(b)
 var before:Dictionary=b.session.snapshot()
 for hour in [126,127,299,300,700,701]:
  at_hour(hour);b.original_quests.refresh_npc_state()
  var mode:="main" if hour>126 and hour<300 else "changed"
  for source in time_npcs:
   var npc:Dictionary=b.original_quests.npc_by_id(source.id)
   check(npc.graphic==source.time_visuals[mode].graphic and npc.text==source.time_visuals[mode].text,"authoritative TimeMan source image and text at %d"%hour)
   check(npc.map_id==source.map_id and npc.cell==source.cell,"TimeMan mode never moves collision cell")
   var reply:=source_talk(b,source)
   check(reply.ok and reply.dialogue.text==source.time_visuals[mode].text,"actual source dialogue uses current server phase")
   check(choose(b,reply,"ok").ok,"TimeMan close is read only")
  var version:int=b.original_quests.npc_state.version
  b.original_quests.refresh_npc_state()
  check(version==b.original_quests.npc_state.version,"stable time mode does not republish")
 # Position reports deliberately change location, so compare all other profile fields.
 var after:Dictionary=b.session.snapshot();before.erase("location");after.erase("location")
 check(before==after,"TimeMan dialogue changes no inventory, event flags or profile data")
 b.free()
 await remote_projection()
 Clock.clock=previous
 print("ORIGINAL TIMEMAN: %d failures"%failures)
 quit(1 if failures else 0)
func remote_projection()->void:
 var hub=Hub.new("user://timeman-lan-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"TimeMan LAN hub starts")
 check(hub.accounts.create("Alice","1234").ok,"TimeMan account")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"TimeMan LAN port")
 var snapshots:Array=[{},{}]
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link)
  link.message.connect(func(event):
   if event.get("type","") in ["snapshot","profile"]:snapshots[i]=event)
  link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"TimeMan sockets connect")
 for link in links:
  link.login({"type":"login","name":"Alice","pin":"1234"},func(_reply):pass)
  check(await Wait.until(self,func():poll();return link.online),"TimeMan devices log in")
 var b=hub.backends.alice;install(b)
 for hour in [126,127,299,300]:
  at_hour(hour)
  # A talk/lookup may update state before tick; tick must still publish version.
  b.original_quests.npc_by_id(time_npcs[0].id)
  b._process(0.0)
  await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
  var mode:="main" if hour>126 and hour<300 else "changed"
  for snapshot in snapshots:
   for npc in time_npcs:
    check(snapshot.get("derived",{}).get("quest_npcs",{}).get(npc.id,{}).get("time_mode","")==mode,"both devices receive authoritative TimeMan mode")
  var source:Dictionary=time_npcs[0]
  b.automation.position_changed(400,Vector2i(int(source.cell[0]),int(source.cell[1])))
  var reply:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":source.id,"time_mode":"forged"})
  check(reply.ok and reply.dialogue.text==source.time_visuals[mode].text,"remote dialogue cannot forge TimeMan mode")
  await request(links[0],{"type":"quest_choose","token":reply.dialogue.token,"choice":"ok"})
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()
