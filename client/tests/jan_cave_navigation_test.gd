extends "res://tests/jan_cave_route_test.gd"
const Jan=preload("res://server/jan_cave_helper.gd")
func run()->void:
 var b=setup()
 check(trade(b,FRIEND).ok and trade(b,JIDE).ok and trade(b,SON).ok,"source village prerequisites")
 var targets:Array=[]
 for npc in b.quest_catalog.active_npcs():
  if Jan.owns(npc) and int(npc.map_id) in range(20601,20609):targets.append(npc)
 for floor_id in range(20601,20604):
  b.automation.position_changed(floor_id,Vector2i(9,59))
  for npc in targets:
   for mode in ["near","arrival"]:
    check(not b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode}).ok,"early floor cannot jump to future NPC")
 for location in [[20607,7,5],[20607,36,31],[20608,0,7],[20608,0,8]]:
  var map_id:int=location[0];var position:=Vector2i(location[1],location[2])
  var region:int=Jan.region_at(b.quest_helper,b,map_id,position)
  check(region>=0,"actual source Warp/portal has unambiguous adjacent component")
  for npc in targets:
   for mode in ["near","arrival"]:
    b.automation.position_changed(map_id,position)
    var dest:Dictionary=b.quest_helper.destination(b,npc,mode)
    print("JAN DESTINATION ",location," ",npc.id," ",mode," ",dest)
    check(dest.is_empty() or (int(dest.map_id)==map_id and Jan.region_at(b.quest_helper,b,map_id,Vector2i(int(dest.cell[0]),int(dest.cell[1])))==region),"final near/arrival point remains in source component")
    var r:Dictionary=b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode})
    check(bool(r.ok)==not dest.is_empty(),"raw NPC follows authority-filtered result")
    if r.ok:check(Jan.region_at(b.quest_helper,b,map_id,b.automation.position_cell)==region,"actual backend landing stays same component")
 b.automation.position_changed(20607,Vector2i(7,5))
 var pre:int=Jan.region_at(b.quest_helper,b,20607,Vector2i(7,5))
 var post:int=Jan.region_at(b.quest_helper,b,20607,Vector2i(36,31))
 check(pre>=0 and post>=0 and pre!=post,"original guard divides entry and victory regions")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","quest_id":27,"step_id":"jan20:meet","mode":mode}).ok,"old helper step cannot jump past guard")
  check(not b.handle({"type":"quest_visit","npc_id":JAN,"mode":mode}).ok,"raw Jan cannot jump past guard")
 Jan.region_cache.clear();b.quest_helper.maps[20607]={}
 for npc in targets:
  if int(npc.map_id)==20607:check(b.quest_helper.destination(b,npc,"near").is_empty(),"missing map fails closed")
 Jan.region_cache.clear()
 b.free()
 await remote_navigation()
 print("JAN CAVE NAVIGATION: %d failures"%failures)
 quit(1 if failures else 0)

func remote_navigation()->void:
 var b=setup();root.add_child(b)
 trade(b,FRIEND);trade(b,JIDE);trade(b,SON)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"Jan navigation remote server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"Jan two devices online")
 var observed:Array=[]
 for link in links:link.message.connect(func(event):observed.append(event.duplicate(true)))
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(not (await request(links[0],{"type":"quest_visit","quest_id":27,"step_id":"jan20:meet","mode":"near"})).ok,"remote future Jan locked")
 b.automation.position_changed(20607,Vector2i(7,5));b.publish() # Original gate landing fixture; walking tested separately.
 await request(links[1],{"type":"ping"})
 check((await request(links[1],{"type":"quest_visit","quest_id":27,"step_id":"jan20:battle","mode":"near"})).ok,"second device sees reached guard floor")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var current:Vector2i=b.automation.position_cell
 var next:Vector2i=current
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  if Jan.region_at(b.quest_helper,b,20607,current+offset)==Jan.region_at(b.quest_helper,b,20607,current):next=current+offset;break
 check(next!=current,"same-region adjacent walking tile exists")
 observed.clear()
 check((await request(links[1],{"type":"report_position","map_id":20607,"cell":[next.x,next.y],"client":"jan-navigation"})).ok,"ordinary same-region movement")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(observed.all(func(e):return str(e.get("type",""))!="profile"),"same component does not broadcast helper rebuild to either device")
 await request(links[1],{"type":"quest_visit","quest_id":27,"step_id":"jan20:battle","mode":"near"})
 var r:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":guards[0].id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"remote original guard begins")
 fight(b);await request(links[1],{"type":"battle_close"});await request(links[0],{"type":"ping"})
 check((await request(links[0],{"type":"quest_visit","quest_id":27,"step_id":"jan20:meet","mode":"near"})).ok,"other device sees post-victory Jan stage")
 check(not (await request(links[1],{"type":"quest_visit","npc_id":SARAH,"mode":"near"})).ok,"even victory cannot skip original eighth-floor portal")
 b.automation.position_changed(20608,Vector2i(0,7));b.publish()
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check((await request(links[1],{"type":"quest_visit","npc_id":SARAH,"mode":"near"})).ok,"source eighth-floor landing unlocks Sarah on other device")
 check(not (await request(links[0],{"type":"quest_visit","npc_id":JAN,"mode":"near"})).ok,"return to Jan requires original return portal")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
