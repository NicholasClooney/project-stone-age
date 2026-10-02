extends "res://tests/munde_cave_route_test.gd"
const Munde=preload("res://server/munde_cave_helper.gd")
func reject_future(b,id:String,step:String)->void:
 for mode in ["near","arrival"]:
  var before:Dictionary=b.session.snapshot()
  check(not b.handle({"type":"quest_visit","npc_id":id,"mode":mode}).ok and b.session.snapshot()==before,"raw NPC cannot bypass original stage "+mode)
  check(not b.handle({"type":"quest_visit","quest_id":8,"step_id":step,"mode":mode,"map_id":11107,"cell":[24,7]}).ok and b.session.snapshot()==before,"stale/forged step cannot bypass original stage "+mode)
func run()->void:
 var b=setup()
 Rules.set_flag(b.session._profile,"ended",4,true)
 check(trade(b,KOLK).ok and trade(b,KATAN).ok and trade(b,HOTOR).ok,"original three requests accepted")
 var guard:Dictionary=guards[0]
 reject_future(b,guard.id,"munde9:battle");reject_future(b,CHIEF,"munde12:stones")
 var outside_key:Array=Munde.stage_key(b.quest_helper,b)
 b.automation.position_changed(100,Vector2i(442,128))
 check(Munde.stage_key(b.quest_helper,b)==outside_key,"ordinary outside movement does not invalidate navigation projection")
 check(answer(b,talk(b,GATE),"在卡坦有梦德").ok,"original keyword moves into first floor")
 check(Munde.stage_key(b.quest_helper,b)!=outside_key,"original keyword updates navigation stage")
 for floor_id in range(11101,11107):
  b.automation.position_changed(floor_id,Vector2i(7,7)) # Component-negative fixture, not a walking claim.
  reject_future(b,guard.id,"munde9:battle");reject_future(b,CHIEF,"munde12:stones")
 b.automation.position_changed(11107,Vector2i(18,41)) # Exact original staircase landing, occupied portal cell.
 var entry_region:int=Munde.region_at(b.quest_helper,b,Vector2i(18,41))
 var victory_region:int=Munde.region_at(b.quest_helper,b,Vector2i(23,35))
 var chief_region:int=Munde.region_at(b.quest_helper,b,Vector2i(24,7))
 check(entry_region>=0 and victory_region==chief_region and entry_region!=victory_region,"source portal landing and guard side differ from victory/chief component")
 reject_future(b,CHIEF,"munde12:stones")
 var guarded_key:Array=b.quest_helper.navigation_key(b)
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","quest_id":8,"step_id":"munde9:battle","mode":mode}).ok,"current guard side can navigate in both modes")
  check(b.quest_helper.navigation_key(b)==guarded_key,"same component navigation preserves stage key")
 var r:=talk(b,guard.id)
 check(choose(b,r,"yes").ok,"original guard battle begins from reached region")
 fight(b);check(b.handle({"type":"battle_close"}).ok,"actual source win commits Warp")
 check(b.quest_helper.navigation_key(b)!=guarded_key,"victory Warp refreshes component projection")
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"raw chief navigation opens only on victory component")
 check(trade(b,CHIEF).ok and 2419 in b.session.snapshot().original_items and 2420 in b.session.snapshot().original_items,"post-victory component grants both original stones")
 b.free()
 await remote_navigation()
 print("MUNDE CAVE NAVIGATION: %d failures"%failures)
 quit(1 if failures else 0)
func remote_navigation()->void:
 var b=setup();root.add_child(b)
 Rules.set_flag(b.session._profile,"ended",4,true)
 trade(b,KOLK);trade(b,KATAN);trade(b,HOTOR)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"navigation real remote server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"navigation two devices online")
 var first_events:Array=[];var second_events:Array=[]
 links[0].message.connect(func(event):first_events.append(event.duplicate(true)))
 links[1].message.connect(func(event):second_events.append(event.duplicate(true)))
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 for command in [{"type":"quest_visit","npc_id":CHIEF,"mode":"near"},{"type":"quest_visit","quest_id":8,"step_id":"munde12:stones","mode":"arrival"}]:
  check(not (await request(links[0],command)).ok,"remote future chief navigation rejected")
 await request(links[0],{"type":"quest_visit","npc_id":GATE,"mode":"near"})
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":GATE})
 check((await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"submit","text":"在卡坦有梦德"})).ok,"remote exact keyword enters cave")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(not (await request(links[1],{"type":"quest_visit","npc_id":guards[0].id,"mode":"arrival"})).ok,"other device cannot jump from first floor to guards")
 b.automation.position_changed(11107,Vector2i(18,41));b.publish() # Stairs covered by actual walking suite.
 await request(links[1],{"type":"ping"})
 check((await request(links[1],{"type":"quest_visit","quest_id":8,"step_id":"munde9:battle","mode":"near"})).ok,"remote published current-region guard step unlocks")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var current:Vector2i=b.automation.position_cell
 var next:Vector2i=current
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  if Munde.region_at(b.quest_helper,b,current+offset)==Munde.region_at(b.quest_helper,b,current):next=current+offset;break
 check(next!=current,"same source component has adjacent ordinary cell")
 first_events.clear();second_events.clear()
 check((await request(links[1],{"type":"report_position","map_id":11107,"cell":[next.x,next.y],"client":"munde-navigation"})).ok,"remote same-region movement reports")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(first_events.all(func(e):return str(e.get("type",""))!="profile") and second_events.all(func(e):return str(e.get("type",""))!="profile"),"same region emits no profile/helper broadcast on either device")
 await request(links[1],{"type":"quest_visit","quest_id":8,"step_id":"munde9:battle","mode":"near"})
 r=await request(links[1],{"type":"quest_talk","npc_id":guards[0].id})
 check((await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})).ok,"remote source battle starts")
 fight(b);await request(links[1],{"type":"battle_close"});await request(links[0],{"type":"ping"})
 check((await request(links[0],{"type":"quest_visit","quest_id":8,"step_id":"munde12:stones","mode":"near"})).ok,"other device sees victory component and can visit chief")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
