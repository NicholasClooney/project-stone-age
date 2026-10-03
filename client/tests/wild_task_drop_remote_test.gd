extends "res://tests/wild_task_drop_test.gd"
func run()->void:
 var b=fresh();strong(b);mine(b,true);root.add_child(b)
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"real port-zero server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two actual devices connect")
 for link in links:await request(link,{"type":"ping"})
 b.encounter_rng.seed=27
 check((await request(links[0],{"type":"wild_encounter","map_id":31801,"cell":[37,48]})).ok,"device one opens real seed27 ore")
 check(b.session._pending.has("wild_drop_receipt"),"real socket battle freezes original route")
 b.save_path="user://no-remote-task-drop-dir/save.json"
 for turn in range(100):
  if not b.battle.snapshot().active:break
  var target:=0
  for i in range(b.battle_state.enemies.size()):
   if int(b.battle_state.enemies[i].hp)>0:target=i;break
  await request(links[0],{"type":"battle_command","action":"attack","target":target})
 check(not b.battle_state.get("settled",false),"remote terminal save failure retains pending")
 var frozen_pending:Dictionary=b.session._pending.duplicate(true)
 check(not (await request(links[1],{"type":"project_position","map_id":31801,"cell":[39,48]})).ok,"busy project teleport is refused without altering eligibility")
 check((await request(links[1],{"type":"report_position","map_id":31801,"cell":[39,48],"client":"party","arrival_kind":"walk"})).ok,"legacy raw report changes position but cannot grant route")
 check((await request(links[1],{"type":"report_position","map_id":31801,"cell":[37,48]})).ok,"raw return to battle cell cannot renew epoch")
 check(b.session._pending==frozen_pending,"second device movement does not rewrite frozen result")
 b.save_path=""
 var retried:Dictionary=await request(links[0],{"type":"battle_close"})
 check(retried.ok and b.session.snapshot().original_items.count(2534)==0 and b.battle_state.has("quest_drop_denied"),"first device retry commits ordinary result but withholds expired task ore")
 await request(links[1],{"type":"ping"})
 check(b.session._pending.is_empty(),"both devices share one completed authoritative settlement")
 for link in links:link.close()
 server.stop();server.queue_free();b.queue_free();await process_frame
 print("WILD TASK DROP REMOTE: %d failures"%failures);quit(1 if failures else 0)
