extends "res://tests/jan_cave_route_test.gd"
const Jan=preload("res://server/jan_cave_helper.gd")
func run()->void:
 var b=setup()
 check(trade(b,FRIEND).ok and trade(b,JIDE).ok and trade(b,SON).ok,"source village prerequisites")
 for mode in ["near","arrival"]:
  var outside:Dictionary=b.handle({"type":"quest_visit","quest_id":27,"step_id":"jan20:entrance","mode":mode})
  check(outside.get("ok",false) and int(outside.get("target",{}).get("map_id",-1))==200 and str(outside.get("target",{}).get("npc_id","missing"))=="","both modes publish only the source public entrance")
  check(not b.quest_arrival.has_arrival(b,20601,Vector2i(9,59)),"public helper approach grants no cave arrival")
 var targets:Array=[]
 for npc in b.quest_catalog.active_npcs():
  if Jan.owns(npc) and int(npc.map_id) in range(20601,20609):targets.append(npc)
 # These project positions are negative probes, never a claimed arrival route.
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
 check(JanRoute.approach(b,guards[0]),"real root, all stairs/passwords and walk to guard")
 b.publish()
 await request(links[1],{"type":"ping"})
 check((await request(links[1],{"type":"quest_visit","quest_id":27,"step_id":"jan20:battle","mode":"near"})).ok,"second device sees reached guard floor")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var current:Vector2i=b.automation.position_cell
 var next:Vector2i=current
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  var candidate:Vector2i=current+offset
  if Jan.region_at(b.quest_helper,b,20607,candidate)!=Jan.region_at(b.quest_helper,b,20607,current):continue
  var same_near:=true
  for npc in b.quest_catalog.active_npcs():
   if not Jan.owns(npc) or int(npc.map_id)!=20607:continue
   var point:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
   if (maxi(absi(current.x-point.x),absi(current.y-point.y))<=2)!=(maxi(absi(candidate.x-point.x),absi(candidate.y-point.y))<=2):same_near=false;break
  if same_near:next=candidate;break
 check(next!=current,"same-region adjacent walking tile exists")
 observed.clear()
 check((await request(links[1],{"type":"report_position","map_id":20607,"cell":[next.x,next.y],"client":"jan-navigation"})).ok,"ordinary same-region movement")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(observed.all(func(e):return str(e.get("type",""))!="profile"),"same component and same nearby NPC set does not broadcast helper rebuild")
 await request(links[1],{"type":"quest_visit","quest_id":27,"step_id":"jan20:battle","mode":"near"})
 var r:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":guards[0].id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"remote original guard begins")
 fight(b);await request(links[1],{"type":"battle_close"});await request(links[0],{"type":"ping"})
 check(not (await request(links[0],{"type":"quest_visit","quest_id":27,"step_id":"jan20:meet","mode":"near"})).ok,"victory alone cannot replace walking to Jan")
 check(JanRoute.Travel.walk_near(b,b.original_quests.npc_by_id(JAN),[20607]),"walk from saved victory Warp to father")
 b.publish();await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 for mode in ["near","arrival"]:
  var original:Vector2i=b.automation.position_cell
  var arrival:Dictionary=await request(links[0],{"type":"quest_visit","quest_id":27,"step_id":"jan20:meet","mode":mode})
  check(arrival.ok and b.automation.position_cell==original,"other device can only talk from current legal near position")
  check(Jan.region_at(b.quest_helper,b,20607,original)==Jan.region_at(b.quest_helper,b,20607,Vector2i(int(arrival.target.cell[0]),int(arrival.target.cell[1]))),"final permitted landing retains original component")
  var raw:Dictionary=await request(links[1],{"type":"quest_visit","npc_id":JAN,"mode":mode})
  check(raw.ok and b.automation.position_cell==original and raw.target.cell==arrival.target.cell,"raw NPC and step return the same unchanged legal talk point")
 var previous_map:Dictionary=b.quest_helper.maps.get(20607,{})
 Jan.region_cache.clear();b.quest_helper.maps[20607]={}
 for mode in ["near","arrival"]:
  check(Jan.destination(b.quest_helper,b,b.original_quests.npc_by_id(JAN),mode).is_empty(),"otherwise legal near arrival fails closed when geometry is unavailable")
 b.quest_helper.maps[20607]=previous_map;Jan.region_cache.clear()
 check(not (await request(links[1],{"type":"quest_visit","npc_id":SARAH,"mode":"near"})).ok,"even victory cannot skip original eighth-floor portal")
 check(JanRoute.Travel.walk_near(b,b.original_quests.npc_by_id(SARAH),[20607,20608]),"walk through actual original portal then near Sarah")
 b.publish()
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check((await request(links[1],{"type":"quest_visit","npc_id":SARAH,"mode":"near"})).ok,"source portal plus actual near approach unlocks Sarah on other device")
 check(not (await request(links[0],{"type":"quest_visit","npc_id":JAN,"mode":"near"})).ok,"return to Jan requires original return portal")
 b.quest_arrival.reset();b.publish()
 for mode in ["near","arrival"]:
  check(not (await request(links[1],{"type":"quest_visit","npc_id":SARAH,"mode":mode})).ok,"authority reset invalidates previous near arrival without moving the actor")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
