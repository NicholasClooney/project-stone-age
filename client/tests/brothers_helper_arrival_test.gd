extends "res://tests/brothers_golden_quests_test.gd"
const Wait=preload("res://tests/support/wait.gd")
var links:Array=[]
const Navigation=preload("res://server/brothers_arrival_helper.gd")
func run()->void:
 var b=fresh()
 var first:Dictionary=b.original_quests.npc_by_id("giiru/event/ev28_0")
 var reward:Dictionary=b.original_quests.npc_by_id("giiru/event/ev28_ed5")
 var target:Dictionary=b.quest_helper.destination(b,first,"near")
 check(int(target.get("map_id",-1))==300 and str(target.get("npc_id","bad")).is_empty(),"outside helper returns public entrance without NPC auto-talk")
 check(b.quest_helper.destination(b,reward,"near").is_empty(),"raw old reward NPC cannot skip original route")
 check(not b.handle({"type":"quest_visit","npc_id":reward.id,"mode":"near"}).get("ok",false),"server rejects raw old reward travel command")
 check(Navigation.stage_key(b).is_empty(),"outside named stage key is empty")
 for npc in b.quest_catalog.active_npcs():
  if not Navigation.owns(npc):continue
  var route:Dictionary=b.quest_helper.destination(b,npc,"near")
  check(not route.is_empty() if str(npc.id)==str(first.id) else route.is_empty(),"every brothers source has only authorized outside guidance: "+str(npc.id))
 var old:Dictionary={}
 for quest in b.quest_helper.snapshot(b).quests:
  if int(quest.event)!=28:continue
  for step in quest.steps:
   if str(step.id)=="brothers:giiru/event/ev28_0":old={"quest_id":quest.id,"step_id":step.id}
 check(not old.is_empty(),"public root guidance remains available")
 check(brother_walk(b,str(first.id)),"real root and walking grant arrival")
 var position:Vector2i=b.automation.position_cell
 target=b.quest_helper.destination(b,first,"near")
 check(target.get("cell",[])==[position.x,position.y],"near helper retains exact actual position")
 check(b.handle({"type":"quest_visit","npc_id":first.id,"mode":"near"}).get("ok",false) and b.quest_arrival.has_arrival(b,int(first.map_id),position),"production near visit preserves legitimate arrival")
 trade(b,str(first.id))
 check(b.quest_helper.resolve_step(b,int(old.get("quest_id",-1)),str(old.get("step_id",""))).is_empty(),"old request step refused after branch changes")
 var stale:Dictionary=old.duplicate();stale.type="quest_visit";stale.mode="near"
 check(not b.handle(stale).get("ok",false),"production old step command is rejected")
 b.quest_arrival.reset()
 check(b.quest_helper.destination(b,first,"near").is_empty(),"restart rejects inherited cave position without arrival")
 check(b.quest_helper.destination(b,reward,"near").is_empty(),"restart cannot revive old final reward route")
 b.free()
 await remote_tokens()
 print("BROTHERS HELPER ARRIVAL: %d failures"%failures)
 quit(1 if failures else 0)

func poll_links()->void:
 for link in links:link.poll(0.01)
func request(link,command:Dictionary)->Dictionary:
 var result:Array=[{}]
 link.request(command,func(reply):result[0]=reply)
 check(await Wait.until(self,func():poll_links();return not result[0].is_empty()),"remote brothers response arrives")
 return result[0]
func remote_tokens()->void:
 var b=fresh();root.add_child(b)
 check(brother_walk(b,"giiru/event/ev28_0"),"two sockets use actual brothers entrance route")
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1")
 root.add_child(server);check(server.start()==OK,"brothers ephemeral socket server")
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll_links();return links.all(func(link):return link.online)),"two real brothers devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":"giiru/event/ev28_0"})
 var second:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":"giiru/event/ev28_0"})
 check(first.has("dialogue") and second.has("dialogue"),"both devices receive original request dialogue")
 if first.has("dialogue") and second.has("dialogue"):
  var stale:Dictionary=await request(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})
  check(not stale.get("ok",false),"second socket invalidates first socket old token")
  var accepted:Dictionary=await request(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
  if accepted.has("dialogue"):accepted=await request(links[1],{"type":"quest_choose","token":accepted.dialogue.token,"choice":"ok"})
  check(accepted.get("ok",false) and Rules.flag(b.session.snapshot(),"now",28),"second socket commits shared original request")
 var rejected:Dictionary=await request(links[0],{"type":"quest_visit","npc_id":"giiru/event/ev28_ed5","mode":"near"})
 check(not rejected.get("ok",false),"other device cannot raw travel into reward room")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
