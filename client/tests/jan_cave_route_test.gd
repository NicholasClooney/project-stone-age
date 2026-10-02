extends "res://tests/original_fixed_guards_test.gd"
const FRIEND="jaruga/event/event20_1@3400:59:66"
const JIDE="jaruga/event/event20_2@3406:27:14"
const SON="jaruga/event/event20_3@3406:28:17"
const JAN="jaruga/event/event20_4@20607:68:5"
const WIFE="jaruga/event/event20_5@20607:71:7"
const SARAH="jaruga/event/event20_6@20608:9:3"
func setup():
 var b=fresh();guards=[]
 for npc in b.quest_catalog.active_npcs():
  if str(npc.get("source_script","")) in ["200/sb_jan1.arg","200/sb_jan2.arg","200/sb_jan3.arg"]:guards.append(npc)
 return b
func answer(b,r:Dictionary,text:String)->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"submit","text":text})
func run()->void:
 var b=setup()
 check(guards.size()==3,"three actually bound original bandit guards")
 var events:Array=b.quest_catalog.enabled_events.filter(func(e):return e in [20,21,22,47,161]);events.sort()
 check(events==[20,21,22],"exact Jan events exclude later161 and47")
 check(trade(b,FRIEND).ok and trade(b,JIDE).ok and trade(b,SON).ok,"original flower request and ornament acquisition")
 var jobs:Dictionary={}
 for job in b.quest_helper.snapshot(b).quests:
  if int(job.event) in [20,21,22]:jobs[int(job.event)]=job
 check(jobs.size()==3 and jobs[20].steps.size()==8 and jobs[21].steps.size()==4 and jobs[22].steps.size()==1,"all three original logs have independent actionable helper stages")
 for script in ["genout/wpm_20604_11_53","genout/wpm_20605_51_4","genout/wpm_20606_9_23"]:
  var npc:Dictionary={}
  for entry in b.quest_catalog.active_npcs():
   if str(entry.get("source_script",""))==script:npc=entry;break
  check(not npc.is_empty(),"original keyword actual create binding")
  if npc.is_empty():continue
  # Fixture positions isolate each original transaction; walking is a separate suite.
  var gate_cell:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  var labels:Dictionary=preload("res://server/jan_cave_helper.gd").region_data(b.quest_helper,b,int(npc.map_id)).get("labels",{})
  for offset in preload("res://scripts/npc_interaction.gd").offsets():
   if labels.has(gate_cell+offset):b.automation.position_changed(int(npc.map_id),gate_cell+offset);break
  var phrase:String=npc.branches[0].keyword
  var r:=talk(b,npc.id);var before:Dictionary=b.session.snapshot()
  check(not answer(b,r,phrase+" ").ok and b.session.snapshot()==before,"exact source phrase rejects extra space")
  r=talk(b,npc.id);b.save_path="user://missing-jan-route/save.json"
  check(not answer(b,r,phrase).ok and b.session.snapshot()==before,"original keyword save rollback")
  b.save_path=""
  check(answer(b,talk(b,npc.id),phrase).ok,"actual original keyword accepted")
  var target:PackedStringArray=str(npc.branches[0].actions.Warp).split(",")
  check(b.automation.position_map==int(target[0]) and b.automation.position_cell==Vector2i(int(target[1]),int(target[2])),"original keyword server destination")
 for npc in guards:
  var r:=source_talk(b,npc)
  check(choose(b,r,"yes").ok,"each original three-enemy guard begins")
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==[961,963,962],"exact source bandit troop order")
  check(preload("res://server/troop_art.gd").can_render(b.session._pending.enemies),"all three original bandit sprites available")
  check(b.session._pending.enemies.all(func(e):return e.generated_drops.is_empty()),"no invented bandit fixed battle drops")
  var before:Dictionary=b.session.snapshot();b.save_path="user://missing-jan-route/save.json"
  fight(b)
  check(not b.battle_state.get("settled",false) and b.session.snapshot()==before,"failed guard save preserves profile and location")
  check(not b.handle({"type":"battle_close"}).ok,"failed guard settlement remains retryable")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==20607 and b.automation.position_cell==Vector2i(36,31),"successful retry commits original bandit Warp once")
  check(not choose(b,r,"yes").ok,"old guard token cannot replay")
 check(trade(b,JAN).ok and Rules.flag(b.session.snapshot(),"ended",20),"ornament reveals Jan and completes20")
 check(trade(b,WIFE).ok,"source mother story")
 b.automation.position_changed(20608,Vector2i(0,7)) # Exact original portal landing fixture.
 check(trade(b,SARAH).ok and Rules.flag(b.session.snapshot(),"now",21),"source Sarah request21")
 talk(b,SARAH);check(not 2488 in b.session.snapshot().original_items,"source letter waits for22")
 b.automation.position_changed(20607,Vector2i(75,13)) # Exact original return portal fixture.
 check(trade(b,JAN).ok and Rules.flag(b.session.snapshot(),"ended",22),"source random equipment completes22 first")
 b.automation.position_changed(20608,Vector2i(0,7))
 check(trade(b,SARAH).ok and 2488 in b.session.snapshot().original_items,"then Sarah issues letter")
 check(trade(b,JIDE).ok and Rules.flag(b.session.snapshot(),"ended",21) and 2489 in b.session.snapshot().original_items,"original flute and final21")
 for quest in b.quest_helper.snapshot(b).quests:
  if int(quest.event)==22:check(str(quest.blocked_reason).is_empty(),"completed22 does not show obsolete prerequisite warning")
 check(b.session.save_game("user://jan-route.json"),"real completed route saves")
 var loaded=Session.new();check(loaded.load_game("user://jan-route.json") and loaded.snapshot().original_events==b.session.snapshot().original_events,"all three completion flags survive reload")
 b.free();await lan_guard()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://jan-route.json"+suffix))
 print("JAN CAVE ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
func lan_guard()->void:
 var b=setup();root.add_child(b)
 source_talk(b,guards[0]);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"Jan ephemeral LAN server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two Jan devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":guards[0].id})
 var second:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":guards[0].id})
 check(not (await request(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})).ok,"second device supersedes stale guard token")
 var start:Dictionary=await request(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes","enemies":[1001]})
 check(start.ok and b.session._pending.enemies.size()==3,"LAN server ignores forged troop and uses three source enemies")
 if b.battle_open:
  fight(b);await request(links[1],{"type":"battle_close"})
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
