extends "res://tests/original_fixed_guards_test.gd"
const Dream=preload("res://server/dream_cave_helper.gd")
const Clock=preload("res://server/original_world_clock.gd")
const ELDER="seimu/event/event01_1@6000:73:54"
const SAGE="seimu/event/event01_2@41:34:25"
var seconds:=Clock.ERA
func forbidden(b)->void:
 for map_id in [41,42]:
  for mode in ["near","arrival"]:
   var r:Dictionary=b.handle({"type":"quest_visit","npc_id":"seimu/event/event01_2@%d:34:25"%map_id,"mode":mode})
   check(not r.ok,"raw future sage cannot bypass entrance/guard")
   check(not b.handle({"type":"quest_visit","quest_id":34,"step_id":"dream34:reward","mode":mode}).ok,"future reward step cannot bypass source gates")
func maze(b,map_id:int)->void:
 var start:=Dream.region(map_id,b.automation.position_cell)
 var goal:=Dream.region(map_id,Vector2i(34,42))
 var queue:Array=[start];var paths:Dictionary={start:[]};var cursor:=0
 var links:Dictionary=b.quest_helper.places.links(map_id)
 while cursor<queue.size() and not paths.has(goal):
  var current:int=queue[cursor];cursor+=1
  for link in links.values():
   if int(link.to_map)!=map_id:continue
   var from:=Vector2i(int(link.cell[0]),int(link.cell[1]));var to:=Vector2i(int(link.target[0]),int(link.target[1]))
   if Dream.region(map_id,from)!=current:continue
   var next:=Dream.region(map_id,to)
   if next<0 or paths.has(next):continue
   paths[next]=paths[current]+[link];queue.append(next)
 check(paths.has(goal),"original maze links reach final guard room")
 if not paths.has(goal):return
 for link in paths[goal]:
  var from:=Vector2i(int(link.cell[0]),int(link.cell[1]))
  check(Dream.region(map_id,from)==Dream.region(map_id,b.automation.position_cell),"next original warp is in current walkable room")
  check(b.handle({"type":"report_position","map_id":map_id,"cell":link.cell}).ok,"walked source portal reports")
  check(b.handle({"type":"report_position","map_id":map_id,"cell":link.target,"map_changed":true}).ok,"original maze destination reports")
func run()->void:
 var old:=Clock.clock;Clock.clock=func():return seconds
 var b=fresh();adult(b)
 var replay_profile:Dictionary={}
 for event in [32,33,34]:
  check(trade(b,ELDER).ok and Rules.flag(b.session.snapshot(),"now",event) and 2603 in b.session.snapshot().original_items,"original elder starts exact round%d"%event)
  check(not Rules.flag(b.session.snapshot(),"ended",34),"third END34 not prematurely written")
  forbidden(b)
  var map_id:=42 if event==33 else 41
  seconds=Clock.ERA+int(ceil(float(400 if map_id==42 else 200)*5400.0/1024.0))
  var door:=[87,101] if map_id==42 else [97,119]
  b.automation.position_changed(400,Vector2i(int(door[0]),int(door[1])))
  check(b.handle({"type":"check_passage","from_map":400,"to_map":map_id}).ok,"original phase permits chosen gate")
  check(b.handle({"type":"report_position","map_id":map_id,"cell":[11,8]}).ok,"original timed gate actual arrival")
  forbidden(b)
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":"400/sb_muge1.arg@%d:34:41"%map_id,"mode":mode}).ok,"maze entry cannot navigate directly to final guard room")
  b.automation.position_changed(map_id,Vector2i.ZERO)
  check(not b.handle({"type":"quest_visit","npc_id":"400/sb_muge1.arg@%d:34:41"%map_id,"mode":"near"}).ok,"unknown blocked component fails closed")
  b.automation.position_changed(map_id,Vector2i(11,8))
  maze(b,map_id);forbidden(b)
  var guard:="400/sb_muge%d.arg@%d:%d:41"%[2 if event==33 else 1,map_id,33 if event==33 else 34]
  check(choose(b,talk(b,guard),"yes").ok and b.battle_open,"actual bound dream guard starts")
  if not b.battle_open:b.free();Clock.clock=old;quit(1);return
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==[1095,1095,1095,1087,1086,1096,1096,1096,1096,1096],"exact ten source enemies unchanged")
  var before:Dictionary=b.session.snapshot();b.save_path="user://dream-no-parent/save.json"
  fight(b)
  check(b.session.snapshot()==before and Dream.region(map_id,b.automation.position_cell)==Dream.region(map_id,Vector2i(34,42)),"failed saved victory cannot cross guard wall")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==41 and b.automation.position_cell==Vector2i(33 if event==33 else 34,39),"saved source victory always warps41 including42 fight")
  for mode in ["near","arrival"]:
   check(b.handle({"type":"quest_visit","npc_id":SAGE,"mode":mode}).ok and Dream.region(41,b.automation.position_cell)==Dream.region(41,Vector2i(34,39)),"post-victory navigation stays in reward component")
  if event==34:replay_profile=b.session.snapshot()
  var response:=choose(b,talk(b,SAGE),"yes");before=b.session.snapshot();b.save_path="user://dream-no-parent/save.json"
  check(not choose(b,response,"ok").ok and b.session.snapshot()==before,"failed final delivery preserves light and END bits")
  b.save_path=""
  check(trade(b,SAGE).ok and Rules.flag(b.session.snapshot(),"ended",event) and not 2603 in b.session.snapshot().original_items,"real delivery completes only round%d"%event)
  check((2638-event) in b.session.snapshot().original_items,"exact original deterministic reward")
  check(Rules.flag(b.session.snapshot(),"ended",34)==(event==34),"END34 only on third completed delivery")
  check(not choose(b,response,"ok").ok,"old delivery token cannot duplicate reward")
 check(not replay_profile.is_empty(),"third-round earned state available")
 b.automation.position_changed(400,Vector2i(99,119))
 check(not b.handle({"type":"quest_visit","quest_id":34,"step_id":"dream34:reward","mode":"arrival"}).ok,"old post-victory step cannot return through timed entrance")
 b.automation.position_changed(1000,Vector2i(20,20))
 check(Dream.stage_key(b).is_empty(),"dream contributes no stage key outside source maps")
 var path:="user://dream-three-rounds.json";check(b.session.save_game(path),"three rounds save")
 var restored=Session.new();check(restored.load_game(path) and [32,33,34].all(func(e):return Rules.flag(restored.snapshot(),"ended",e)),"all three exact END bits survive reload")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 b.free();await dream_lan(replay_profile);Clock.clock=old
 print("DREAM CAVE: %d failures"%failures);quit(1 if failures else 0)

func dream_lan(earned:Dictionary)->void:
 var b=fresh();b.session._profile=earned.duplicate(true);root.add_child(b)
 b.automation.position_changed(41,Vector2i(34,39))
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"dream LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"dream two real sockets")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 await request(links[0],{"type":"quest_visit","npc_id":SAGE,"mode":"near"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":SAGE})
 a=await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})
 await request(links[0],{"type":"ping"})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":SAGE})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"ok"})).ok,"second socket invalidates old reward token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes"})
 check((await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok,"second socket commits third-round source clothes")
 check(not (await request(links[0],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok and b.session.snapshot().original_items.count(2604)==1,"LAN retry cannot duplicate chosen reward")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame
