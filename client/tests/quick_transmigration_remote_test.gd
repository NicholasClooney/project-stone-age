extends "res://tests/quick_transmigration_test.gd"
const Wait=preload("res://tests/support/wait.gd")
const Server=preload("res://server/ws_server.gd")
const Link=preload("res://network/ws_link.gd")
var links:Array=[]
func poll()->void:
 for link in links:link.poll(0.01)
func request(link,c:Dictionary)->Dictionary:
 var answer:=[{}];link.request(c,func(reply):answer[0]=reply)
 check(await Wait.until(self,func():poll();return not answer[0].is_empty()),"remote round trip")
 return answer[0]
func run()->void:
 var b=fresh();root.add_child(b)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"ephemeral two-device server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 if not await Wait.until(self,func():poll();return links.all(func(l):return l.online)):
  check(false,"both devices connected");server.stop();quit(1);return
 for link in links:await request(link,{"type":"ping"})
 var first:Dictionary=await request(links[0],packet())
 check(first.has("quick_transmigration"),"nonadmin remote preview receives full contract")
 if not first.has("quick_transmigration"):print(first);quit(1);return
 var a:String=first.quick_transmigration.token
 var second:Dictionary=await request(links[1],packet("130",0,["strength","dexterity"]))
 var token:String=second.quick_transmigration.token
 check(token!=a and not (await request(links[0],{"type":"quick_transmigration","action":"confirm","token":a})).ok,"second device supersedes first token")
 check(not (await request(links[0],{"type":"quick_transmigration","action":"cancel","token":a})).ok and b.quick_transmigration.pending.token==token,"late old cancel preserves latest token")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://quick-rebirth-missing-parent/remote.json"
 var failed:Dictionary=await request(links[1],{"type":"quick_transmigration","action":"confirm","token":token})
 check(not failed.ok and failed.reason=="save_failed" and b.session.snapshot()==before,"remote failed save no partial state")
 b.save_path="user://quick-rebirth-remote.json"
 var count:=[0];var successes:=[0]
 for link in links:
  link.request({"type":"quick_transmigration","action":"confirm","token":token},func(r):count[0]+=1;successes[0]+=int(r.get("ok",false)))
 check(await Wait.until(self,func():poll();return count[0]==2),"both concurrent confirmations return")
 check(successes[0]==1 and b.session.snapshot().player.transmigration==1 and b.session.snapshot().pets.size()==1,"one winner and one reward across devices")
 var saved:Dictionary=b.session.snapshot()
 links[1].close()
 var reconnected=Link.new("ws://127.0.0.1:%d"%server.port);links[1]=reconnected;reconnected.connect_now()
 check(await Wait.until(self,func():poll();return reconnected.online),"reconnect after transaction")
 await request(reconnected,{"type":"ping"})
 check(not (await request(reconnected,{"type":"quick_transmigration","action":"confirm","token":token})).ok and b.session.snapshot()==saved,"reconnected retry never duplicates")
 var next:Dictionary=await request(reconnected,packet())
 var cancel:Dictionary=await request(reconnected,{"type":"quick_transmigration","action":"cancel","token":next.quick_transmigration.token})
 check(cancel.ok and b.quick_transmigration.pending.is_empty() and b.session.snapshot()==saved,"cancel token only is side-effect-free")
 # Original route cannot be bypassed with quick options or through a quick token.
 var natural:Dictionary=await request(reconnected,{"type":"transmigration","action":"preview","npc_id":"777/ten.arg@32021:31:28","pet_ids":[],"level_mode":"130","bonus_quests":20,"allocation_stats":["strength"]})
 check(not natural.ok and b.session.snapshot()==saved,"natural remote command rejects quick-policy injection")
 natural=await request(reconnected,{"type":"transmigration","action":"preview","npc_id":"777/ten.arg@32021:31:28","pet_ids":[]})
 check(not natural.ok and b.session.snapshot()==saved,"natural entry retains route admission")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
 for suffix in ["",".tmp",".bak"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quick-rebirth-remote.json"+suffix))
 print("QUICK TRANSMIGRATION REMOTE: %d failures"%failures);quit(1 if failures else 0)
