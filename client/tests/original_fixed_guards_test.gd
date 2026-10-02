extends "res://tests/brothers_golden_quests_test.gd"
const Wait=preload("res://tests/support/wait.gd")
const Server=preload("res://server/ws_server.gd")
const Link=preload("res://network/ws_link.gd")
var guards:Array=[]
var links:Array=[]
func setup():
 var b=fresh()
 var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-fixed-guards.json"))
 guards=[]
 for fixture in fixtures:guards.append_array(fixture.npcs)
 b.quest_catalog.npcs.append_array(guards);b.quest_catalog.enabled_events.append_array([9,10,11,12,20,21,22])
 return b
func source_talk(b,npc:Dictionary)->Dictionary:
 b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0]),int(npc.cell[1])))
 return b.handle({"type":"quest_talk","npc_id":npc.id})
func fight(b)->void:
 for i in range(100):
  var state:Dictionary=b.battle.snapshot()
  if not state.active:return
  var target:=0
  for index in range(state.enemies.size()):
   if int(state.enemies[index].hp)>0:target=index;break
  b.handle({"type":"battle_command","action":"attack","target":target})
 check(not b.battle.snapshot().active,"real multi-enemy battle completes")
func run()->void:
 var b=setup()
 for npc in guards:
  var r:=source_talk(b,npc)
  check(r.ok,"actual bound fixed guard dialogue")
  if not r.ok:continue
  var expected:Array=npc.branches[0].guard.enemy_ids.map(func(id):return int(id))
  var start:=choose(b,r,"yes")
  check(start.ok and b.battle_open,"complete original fixed troop starts")
  if not b.battle_open:continue
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==expected,"exact source enemy order and count")
  var before:Dictionary=b.session.snapshot()
  b.save_path="user://missing-fixed-guard-parent/fail.json"
  fight(b)
  check(not b.battle_state.get("settled",false) and b.session.snapshot().location==before.location and b.session.snapshot().completed_battles==before.completed_battles,"failed save preserves profile and victory Warp")
  check(b.session._pending.has("quest_guard") and not b.handle({"type":"battle_close"}).ok,"failed settlement retains retryable guard")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok,"same complete troop settlement retries successfully")
  var warp:PackedStringArray=str(npc.branches[0].actions.Warp).split(",")
  check(b.automation.position_map==int(warp[0]) and b.automation.position_cell==Vector2i(int(warp[1]),int(warp[2])),"source victory Warp only after saved settlement")
  check(not choose(b,r,"yes").ok,"guard confirmation cannot replay")
 b.free()
 await lan_guard()
 print("ORIGINAL FIXED GUARDS: %d failures"%failures)
 quit(1 if failures else 0)
func poll()->void:
 for link in links:link.poll(0.01)
func request(link,command:Dictionary)->Dictionary:
 var answer:=[{}];link.request(command,func(reply):answer[0]=reply)
 check(await Wait.until(self,func():poll();return not answer[0].is_empty()),"guard LAN roundtrip")
 return answer[0]
func lan_guard()->void:
 var b=setup();root.add_child(b)
 var npc:Dictionary=guards[0]
 source_talk(b,npc);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"fixed guard LAN ephemeral server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two guard devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":npc.id})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})).ok,"other device supersedes old guard token")
 var answer:Dictionary=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes","enemies":[1001]})
 check(answer.ok and b.session._pending.enemies.size()==4,"remote client cannot replace four original enemies")
 if b.battle_open:
  fight(b);await request(links[1],{"type":"battle_close"})
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
